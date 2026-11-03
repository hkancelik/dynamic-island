"""Komut paleti arka ucu: uygulama ve dosya araması.

Uygulamalar .desktop dosyalarından dizinlenir (klasörler değişince yeniden okunur); eşleşme
bulanık (fzf benzeri) ve Türkçe karakterlere duyarsızdır. Sık açılanlar öne çıkar (yalnızca
uygulama kimliği ve sayısı ~/.local/state altında tutulur). Pencereler, tarayıcı sekmeleri, birim
dönüştürme, web kısayolları, dosyalar, oturum işlemleri… KRunner eşdeğerleri runners.py'de.
Hesap makinesi, ada komutları, pano ve web araması arayüz tarafında anında hesaplanır.
"""
import json
import math
import os
import subprocess
import threading
import time
import unicodedata

import apps
import runners

STATE = os.path.expanduser("~/.local/state/dynamic-island/palette.json")
MAX_APPS = 8
MAX_FILES = 5

_FOLD = str.maketrans({"ı": "i", "İ": "i", "ş": "s", "Ş": "s", "ğ": "g", "Ğ": "g",
                       "ü": "u", "Ü": "u", "ö": "o", "Ö": "o", "ç": "c", "Ç": "c"})


def fold(s):
    """Küçük harf, aksansız: "Çalışma" -> "calisma"."""
    s = str(s).translate(_FOLD).lower()
    return "".join(c for c in unicodedata.normalize("NFKD", s) if not unicodedata.combining(c))


def score(query, text):
    """0 (eşleşmez) .. ~100. Baştan eşleşme > kelime başı > içerir > sırayla harfler."""
    q, t = fold(query).strip(), fold(text)
    if not q or not t:
        return 0
    if t == q:
        return 100
    if t.startswith(q):
        return 90 - min(20, len(t) - len(q)) * 0.3
    words = t.replace("-", " ").replace("_", " ").split()
    if any(w.startswith(q) for w in words):
        return 75
    # baş harfler: "vsc" -> "Visual Studio Code"
    if len(q) >= 2 and "".join(w[0] for w in words if w).startswith(q):
        return 70
    i = t.find(q)
    if i >= 0:
        return 60 - min(10, i)
    # sırayla harfler (ardışık olanlar daha değerli)
    pos, run, best, last = 0, 0, 0, -2
    for ch in q:
        j = t.find(ch, pos)
        if j < 0:
            return 0
        run = run + 1 if j == last + 1 else 1
        best = max(best, run)
        last, pos = j, j + 1
    return 20 + 25 * best / len(q)


def _desktop_entries():
    seen = {}
    for d in apps.DIRS:
        try:
            names = sorted(os.listdir(d))
        except OSError:
            continue
        for fn in names:
            if not fn.endswith(".desktop"):
                continue
            app_id = fn[:-len(".desktop")]
            if app_id in seen or app_id == apps.SELF_ID:
                continue
            e = _parse(os.path.join(d, fn))
            if e:
                e["id"] = app_id
                seen[app_id] = e
    return list(seen.values())


def _parse(path):
    lang = apps._lang
    vals, in_entry = {}, False
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if line.startswith("["):
                    in_entry = line == "[Desktop Entry]"
                elif in_entry and "=" in line:
                    k, v = line.split("=", 1)
                    vals[k.strip()] = v.strip()
    except OSError:
        return None
    if vals.get("Type") != "Application" or vals.get("NoDisplay") == "true" or vals.get("Hidden") == "true":
        return None
    if "OnlyShowIn" in vals and "KDE" not in vals["OnlyShowIn"]:
        return None
    name = vals.get(f"Name[{lang}]") or vals.get("Name")
    if not name:
        return None
    generic = vals.get(f"GenericName[{lang}]") or vals.get("GenericName", "")
    keywords = (vals.get(f"Keywords[{lang}]", "") + ";" + vals.get("Keywords", "")).replace(";", " ")
    # yerel ad gösterilir ama İngilizce adla da bulunur ("Görsel Stüdyo" ← "visual")
    return {"name": name, "name_en": vals.get("Name", name), "generic": generic, "keywords": keywords,
            "icon": vals.get("Icon", "")}


class Palette:
    def __init__(self, copy=None, dbus=True):
        self._copy = copy                 # metni panoya koyan işlev (arka uçtaki pano)
        self._dbus = None
        if dbus:
            try:
                self._dbus = runners.DBusRunners()
            except Exception as e:
                print("KRunner eklentileri yok:", e, flush=True)
        self._lock = threading.Lock()
        self._apps = []
        self._stamp = None
        self._usage = self._load_usage()

    # -- kullanım sıklığı
    def _load_usage(self):
        try:
            with open(STATE) as f:
                d = json.load(f)
            return {str(k): v for k, v in d.items() if isinstance(v, dict)}
        except Exception:
            return {}

    def _save_usage(self):
        try:
            os.makedirs(os.path.dirname(STATE), exist_ok=True)
            tmp = STATE + ".tmp"
            with open(tmp, "w") as f:
                json.dump(self._usage, f)
            os.replace(tmp, STATE)
        except OSError:
            pass

    def _boost(self, app_id):
        u = self._usage.get(app_id)
        if not u:
            return 0
        days = (time.time() - u.get("last", 0)) / 86400
        return min(25, 6 * math.log1p(u.get("n", 0))) * (0.5 ** (days / 14))   # 2 haftada yarılanır

    def used(self, app_id):
        u = self._usage.setdefault(app_id, {"n": 0, "last": 0})
        u["n"] += 1
        u["last"] = time.time()
        self._save_usage()

    # -- dizin
    def _index(self):
        stamp = []
        for d in apps.DIRS:
            try:
                stamp.append(os.stat(d).st_mtime)
            except OSError:
                stamp.append(0)
        with self._lock:
            if stamp != self._stamp:
                self._apps = _desktop_entries()
                self._stamp = stamp
            return self._apps

    def search_apps(self, q):
        out = []
        for e in self._index():
            s = max(score(q, e["name"]), score(q, e["name_en"]) * 0.95, score(q, e["generic"]) * 0.8,
                    score(q, e["keywords"]) * 0.7, score(q, e["id"]) * 0.7)
            if s >= 30:
                out.append({"kind": "app", "id": e["id"], "title": e["name"], "subtitle": e["generic"],
                            "icon": e["icon"] or "application-x-executable", "score": s + self._boost(e["id"])})
        out.sort(key=lambda r: -r["score"])
        return out[:MAX_APPS]

    def search(self, q, part="all"):
        """part: "fast" (yerel arayıcılar, anında), "slow" (KRunner D-Bus eklentileri), "all"."""
        q = str(q)[:120]
        if part == "slow":
            return sorted(self._dbus.search(q), key=lambda r: -r["score"])[:8] if self._dbus and q.strip() else []
        if not q.strip():
            # boş arama: en sık kullanılanlar
            idx = {e["id"]: e for e in self._index()}
            top = sorted(self._usage, key=lambda k: -self._boost(k))
            return [{"kind": "app", "id": k, "title": idx[k]["name"], "subtitle": idx[k]["generic"],
                     "icon": idx[k]["icon"], "score": 50} for k in top if k in idx][:6]
        out = self.search_apps(q)
        for fn in (runners.convert, runners.web_shortcut, runners.locations, runners.shell, runners.kill,
                   runners.color, runners.characters, runners.spell):
            out += fn(q)
        for fn in (runners.session, runners.settings, runners.recent, runners.bookmarks, runners.konsole_profiles):
            out += fn(q, score)
        out += runners.datetime_runner(q, fold)
        if self._dbus and part == "all":
            out += self._dbus.search(q)
        out += runners.locate(q)
        # aynı dosya birden çok yerden gelebilir (son belgeler + dosya araması)
        seen, uniq = set(), []
        for r in sorted(out, key=lambda r: -r["score"]):
            key = (r["kind"], r.get("path") or r.get("url") or r.get("id") or r.get("match") or r.get("text") or r["title"])
            if key not in seen:
                seen.add(key)
                uniq.append(r)
        return uniq[:14]

    def run(self, item):
        """Arayüzün seçtiği sonucu çalıştır. Yalnızca bilinen türler; her biri kendi içinde doğrulanır."""
        kind = str(item.get("kind", ""))
        if kind == "app" and apps.exists(str(item.get("id", ""))):
            self.used(item["id"])
            apps.launch_desktop(item["id"])
        elif kind in ("path", "file"):
            path = str(item.get("path") or item.get("id") or "")
            if not os.path.exists(path):
                return False
            runners.open_path(path)
        elif kind == "url":
            url = str(item.get("url", ""))
            if not url.startswith(("http://", "https://", "file://")):
                return False
            runners.open_path(url)
        elif kind == "copy" and self._copy:
            self._copy(str(item.get("text", "")))
        elif kind == "shell":
            argv = item.get("argv")
            if isinstance(argv, list) and argv and argv[0] == "konsole":
                subprocess.Popen([str(a) for a in argv], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                 start_new_session=True)
            elif item.get("cmd"):
                runners.run_shell(str(item["cmd"]), bool(item.get("terminal", True)))
            else:
                return False
        elif kind == "kill":
            return runners.kill_pid(int(item.get("pid", 0)))
        elif kind == "session":
            runners.run_session(str(item.get("action", "")))
        elif kind == "kcm":
            runners.open_kcm(str(item.get("kcm", "")))
        elif kind == "runner" and self._dbus:
            return self._dbus.run(str(item.get("service", "")), str(item.get("path", "")), str(item.get("match", "")))
        else:
            return False
        return True
