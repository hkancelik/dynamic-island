"""Komut paleti için KRunner eşdeğeri arayıcılar.

Her arayıcı `(sorgu) -> [sonuç]` döndürür; sonuç: {kind, title, subtitle, icon, score, ...çalıştırma bilgisi}.
`palette.Palette.run` sonucu `kind`'a göre çalıştırır. Hepsi bağımlılıksız ve hızlıdır (ağ yok).

  KRunner D-Bus eklentileri   pencereler (KWin), tarayıcı sekmeleri ve geçmişi, etkinlikler, Baloo
  birimler                    "10 km mi", "72 f to c", "5 gb in mb", "3 fincan ml"
  web kısayolları             "gg:…" "dd:…" "yt:…" "wp:…" "gh:…" "aur:…" "aw:…" "so:…" "map:…" "tr:…"
  konumlar                    "~/Belgeler", "/etc/fstab", "github.com/kde", "https://…"
  kabuk                       "> htop" (terminalde) , ">> komut" (arka planda)
  süreç sonlandır             "kill firefox"
  oturum                      kapat, yeniden başlat, oturumu kapat, uyku, hazırda beklet, kilitle
  sistem ayarları             98 KCM modülü ("ekran", "kısayol", "bluetooth" …)
  son belgeler                ~/.local/share/recently-used.xbel
  yer imleri                  Brave / Chrome / Chromium / Vivaldi / Edge
  konsole profilleri          ~/.local/share/konsole/*.profile
  saat ve tarih               "saat", "time tokyo", "tarih"
  renk                        "#ff6a00", "rgb(255 106 0)"
  karakter                    "u:arrow", "#2192" (Unicode adı ya da kod noktası)
  yazım                       "spell kelime" (hunspell)
  dosyalar                    Baloo kapalıysa plocate (yalnızca ev klasörü)
"""
import colorsys
import fnmatch
import glob
import json
import os
import re
import shutil
import signal
import subprocess
import threading
import time
import unicodedata
import urllib.parse
from datetime import datetime
from xml.etree import ElementTree
from zoneinfo import ZoneInfo, available_timezones

import i18n
from i18n import _

HOME = os.path.expanduser("~")


def _short(path):
    return path.replace(HOME, "~", 1) if path.startswith(HOME) else path


def _num(x):
    """Sayıyı sade yaz: 1234.5 -> "1 234,5" (Türkçe) / "1,234.5" (İngilizce)."""
    if abs(x) >= 1e12 or (x and abs(x) < 1e-4):
        return "%.4g" % x
    s = ("%.6f" % x).rstrip("0").rstrip(".")
    whole, _sep, frac = s.partition(".")
    neg = whole.startswith("-")
    whole = whole.lstrip("-")
    groups = []
    while len(whole) > 3:
        groups.insert(0, whole[-3:])
        whole = whole[:-3]
    groups.insert(0, whole)
    tr = i18n.current() == "tr"
    out = ("." if tr else ",").join(groups) + ((("," if tr else ".") + frac[:4]) if frac else "")
    return ("-" if neg else "") + out


# ---------------------------------------------------------------------------------------------
# Birim dönüştürme
# ---------------------------------------------------------------------------------------------
# birim -> (boyut, katsayı: temel birime çarpan). Sıcaklık ayrı.
UNITS = {}


def _add(dim, factor, *names):
    for n in names:
        UNITS[n] = (dim, factor)


_add("len", 1, "m", "metre", "meter", "meters", "metres")
_add("len", 1000, "km", "kilometre", "kilometer", "kilometers")
_add("len", 0.01, "cm", "santim", "santimetre", "centimeter")
_add("len", 0.001, "mm", "milimetre", "millimeter")
_add("len", 1609.344, "mi", "mil", "mile", "miles")
_add("len", 0.9144, "yd", "yard", "yards")
_add("len", 0.3048, "ft", "feet", "foot", "fit")
_add("len", 0.0254, "in", "inch", "inches", "inç", '"')
_add("len", 1852, "nmi", "deniz mili")
_add("mass", 1, "kg", "kilo", "kilogram", "kilograms")
_add("mass", 0.001, "g", "gr", "gram", "grams")
_add("mass", 1e-6, "mg", "miligram")
_add("mass", 1000, "t", "ton", "tonne")
_add("mass", 0.45359237, "lb", "lbs", "pound", "pounds", "libre")
_add("mass", 0.028349523125, "oz", "ounce", "ons")
_add("vol", 1, "l", "lt", "litre", "liter", "liters")
_add("vol", 0.001, "ml", "mililitre", "milliliter")
_add("vol", 3.785411784, "gal", "gallon", "galon")
_add("vol", 0.0295735296, "floz", "fl oz")
_add("vol", 0.24, "fincan", "cup", "cups", "su bardağı")
_add("vol", 0.015, "yk", "tbsp", "yemek kaşığı")
_add("vol", 0.005, "tk", "tsp", "çay kaşığı")
_add("speed", 1, "m/s", "mps")
_add("speed", 1 / 3.6, "km/h", "kmh", "kph", "km/sa")
_add("speed", 0.44704, "mph")
_add("speed", 0.514444, "knot", "knots", "kn", "knot")
_add("data", 1, "b", "byte", "bytes", "bayt")
_add("data", 1e3, "kb", "kilobyte")
_add("data", 1e6, "mb", "megabyte")
_add("data", 1e9, "gb", "gigabyte")
_add("data", 1e12, "tb", "terabyte")
_add("data", 1024, "kib")
_add("data", 1024 ** 2, "mib")
_add("data", 1024 ** 3, "gib")
_add("data", 1024 ** 4, "tib")
_add("time", 1, "s", "sn", "sec", "second", "seconds", "saniye")
_add("time", 60, "min", "dk", "dakika", "minute", "minutes")
_add("time", 3600, "h", "sa", "saat", "hour", "hours")
_add("time", 86400, "gün", "gun", "day", "days", "d")
_add("time", 604800, "hafta", "week", "weeks", "wk")
_add("area", 1, "m2", "m²", "metrekare")
_add("area", 1e6, "km2", "km²")
_add("area", 4046.8564224, "acre")
_add("area", 1000, "dönüm", "donum")
_add("area", 10000, "ha", "hektar", "hectare")
_add("area", 0.09290304, "ft2", "ft²", "sqft")
TEMPS = {"c": "c", "°c": "c", "celsius": "c", "santigrat": "c", "f": "f", "°f": "f", "fahrenheit": "f",
         "k": "k", "kelvin": "k"}
# yalnızca birim verilince gösterilecek karşılıklar
DEFAULT_TO = {"km": "mi", "mi": "km", "kg": "lb", "lb": "kg", "c": "f", "f": "c", "m": "ft", "ft": "m",
              "in": "cm", "cm": "in", "l": "gal", "gal": "l", "km/h": "mph", "mph": "km/h", "gb": "gib",
              "oz": "g", "g": "oz", "fincan": "ml", "ml": "floz"}
def _canon(u):
    u = u.strip().lower().rstrip(".")
    if u in TEMPS:
        return ("temp", TEMPS[u])
    if u in UNITS:
        return (UNITS[u][0], u)
    return None


def _temp(v, a, b):
    c = v if a == "c" else (v - 32) * 5 / 9 if a == "f" else v - 273.15
    return c if b == "c" else c * 9 / 5 + 32 if b == "f" else c + 273.15


_CONNECT = re.compile(r"^(to|in|into|=|->|→|kaç|için|olarak)\s*")


def _take_unit(text):
    """Metnin başındaki bilinen birim (en uzun ad önce) -> (ad, kalan)."""
    for n in sorted(list(UNITS) + list(TEMPS), key=len, reverse=True):
        if text == n or text.startswith(n + " "):
            return n, text[len(n):].strip()
    return None, text


def convert(q):
    m = re.match(r"^\s*(-?\d+(?:[.,]\d+)?)\s*(.*)$", q.lower())
    if not m or not m.group(2).strip():
        return []
    value = float(m.group(1).replace(",", "."))
    src_name, rest = _take_unit(m.group(2).strip())
    src = _canon(src_name) if src_name else None
    if not src:
        return []
    rest = _CONNECT.sub("", rest).strip()
    if rest:
        dst_name, extra = _take_unit(rest)
        dst = _canon(dst_name) if dst_name else None
        if not dst or extra or dst[0] != src[0]:
            return []
    else:
        dst = None
    if dst:
        targets = [dst[1]]
    else:
        key = src[1]
        if key not in DEFAULT_TO:
            return []
        targets = [DEFAULT_TO[key]]
    out = []
    for t in targets:
        if src[0] == "temp":
            r = _temp(value, src[1], t)
            unit = "°" + t.upper() if t != "k" else "K"
        else:
            r = value * UNITS[src[1]][1] / UNITS[t][1]
            unit = t
        text = "%s %s" % (_num(r), unit)
        out.append({"kind": "copy", "text": text, "title": text, "icon": "isle-update-symbolic",
                    "subtitle": "%s %s · %s" % (_num(value), src_name, _("kopyalamak için Enter")),
                    "score": 980})
    return out


# ---------------------------------------------------------------------------------------------
# Web kısayolları, konumlar, kabuk
# ---------------------------------------------------------------------------------------------
WEB = {
    "gg": ("Google", "https://www.google.com/search?q=%s"),
    "dd": ("DuckDuckGo", "https://duckduckgo.com/?q=%s"),
    "yt": ("YouTube", "https://www.youtube.com/results?search_query=%s"),
    "wp": ("Wikipedia", "https://%s.wikipedia.org/w/index.php?search=%%s"),
    "gh": ("GitHub", "https://github.com/search?q=%s"),
    "aur": ("AUR", "https://aur.archlinux.org/packages?K=%s"),
    "aw": ("ArchWiki", "https://wiki.archlinux.org/index.php?search=%s"),
    "so": ("Stack Overflow", "https://stackoverflow.com/search?q=%s"),
    "map": ("OpenStreetMap", "https://www.openstreetmap.org/search?query=%s"),
    "tr": ("Translate", "https://translate.google.com/?sl=auto&tl=%s&text=%%s"),
    "pkg": ("Arch paketleri", "https://archlinux.org/packages/?q=%s"),
    "kde": ("KDE Store", "https://store.kde.org/search?search=%s"),
}


def web_shortcut(q):
    m = re.match(r"^([a-z]{2,4})[:\s]\s*(.+)$", q.strip(), re.I)
    if not m or m.group(1).lower() not in WEB:
        return []
    key, term = m.group(1).lower(), m.group(2).strip()
    name, url = WEB[key]
    lang = i18n.current()
    if key in ("wp", "tr"):
        url = url % lang
    full = url.replace("%s", urllib.parse.quote_plus(term))
    return [{"kind": "url", "url": full, "title": "%s: %s" % (name, term), "subtitle": full[:80],
             "icon": "isle-globe", "score": 990}]


_URL_RE = re.compile(r"^(https?://\S+|www\.\S+|[a-z0-9-]+(\.[a-z0-9-]+)*\.(com|org|net|io|dev|tr|de|app|gov|edu|co|me|ai)(/\S*)?)$", re.I)


def locations(q):
    s = q.strip()
    out = []
    if s.startswith(("~", "/", "file://")):
        path = os.path.expanduser(urllib.parse.unquote(s[7:]) if s.startswith("file://") else s)
        if os.path.exists(path):
            out.append({"kind": "path", "path": path, "title": _short(path),
                        "subtitle": _("Klasörü aç") if os.path.isdir(path) else _("Dosyayı aç"),
                        "icon": "folder" if os.path.isdir(path) else "text-x-generic", "mono": False, "score": 985})
        else:   # yarım yol: aynı klasördeki eşleşenler
            base, part = os.path.split(path)
            if os.path.isdir(base):
                try:
                    names = sorted(n for n in os.listdir(base) if n.lower().startswith(part.lower()) and not n.startswith("."))
                except OSError:
                    names = []
                for n in names[:5]:
                    p = os.path.join(base, n)
                    out.append({"kind": "path", "path": p, "title": _short(p), "subtitle": _("Aç"),
                                "icon": "folder" if os.path.isdir(p) else "text-x-generic", "mono": False, "score": 900})
    elif _URL_RE.match(s):
        url = s if s.startswith("http") else "https://" + s
        out.append({"kind": "url", "url": url, "title": url, "subtitle": _("Tarayıcıda aç"), "icon": "isle-link",
                    "score": 970})
    return out


def shell(q):
    s = q.strip()
    if not s.startswith(">") or len(s) < 2:
        return []
    background = s.startswith(">>")
    cmd = s[2:].strip() if background else s[1:].strip()
    if not cmd:
        return []
    return [{"kind": "shell", "cmd": cmd, "terminal": not background, "title": cmd,
             "subtitle": _("Arka planda çalıştır") if background else _("Terminalde çalıştır"),
             "icon": "isle-terminal-symbolic", "score": 995}]


def run_shell(cmd, terminal):
    if terminal:
        term = shutil.which("konsole")
        if term:
            argv = [term, "--noclose", "-e", "bash", "-lc", cmd]
        else:
            argv = ["xdg-terminal-exec", "bash", "-lc", cmd]
    else:
        argv = ["bash", "-lc", cmd]
    subprocess.Popen(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
                     cwd=HOME)


# ---------------------------------------------------------------------------------------------
# Süreçler, oturum
# ---------------------------------------------------------------------------------------------
def processes():
    uid = os.getuid()
    out = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            if os.stat("/proc/" + pid).st_uid != uid:
                continue
            with open("/proc/%s/comm" % pid) as f:
                name = f.read().strip()
            with open("/proc/%s/cmdline" % pid, "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode(errors="replace").strip()
        except OSError:
            continue
        out.append((int(pid), name, cmdline))
    return out


def kill(q):
    m = re.match(r"^\s*(kill|öldür|sonlandır)\s+(\S.*)$", q, re.I)
    if not m:
        return []
    term = m.group(2).strip().lower()
    me = os.getpid()
    hits = [(p, n, c) for p, n, c in processes() if p != me and (term in n.lower() or term in c.lower()[:200])]
    hits.sort(key=lambda h: (not h[1].lower().startswith(term), h[1]))
    return [{"kind": "kill", "pid": p, "title": "%s %s" % (_("Sonlandır:"), n), "icon": "isle-close-symbolic",
             "subtitle": "PID %d · %s" % (p, c[:70] or n), "confirm": True, "score": 960} for p, n, c in hits[:6]]


SESSION = [
    ("lock", ("kilitle", "lock"), "isle-lock-symbolic", False),
    ("suspend", ("uyku", "sleep", "suspend", "askıya al"), "isle-moon", False),
    ("hibernate", ("hazırda beklet", "hibernate"), "isle-moon", True),
    ("logout", ("oturumu kapat", "çıkış yap", "logout", "log out", "sign out"), "isle-open-symbolic", True),
    ("reboot", ("yeniden başlat", "restart", "reboot"), "isle-reset", True),
    ("poweroff", ("kapat", "bilgisayarı kapat", "shutdown", "shut down", "power off", "poweroff"), "isle-bolt", True),
]
SESSION_TITLES = {"lock": "Ekranı kilitle", "suspend": "Uyku", "hibernate": "Hazırda beklet",
                  "logout": "Oturumu kapat", "reboot": "Yeniden başlat", "poweroff": "Bilgisayarı kapat"}


def session(q, score):
    out = []
    for key, words, icon, confirm in SESSION:
        s = max(score(q, w) for w in words + (_(SESSION_TITLES[key]),))
        if s >= 70:
            out.append({"kind": "session", "action": key, "title": _(SESSION_TITLES[key]), "icon": icon,
                        "subtitle": _("Onaylamak için tekrar Enter") if confirm else _("Oturum"),
                        "confirm": confirm, "score": s + 5})
    return out


def run_session(action):
    cmds = {
        "lock": ["loginctl", "lock-session"],
        "suspend": ["systemctl", "suspend"],
        "hibernate": ["systemctl", "hibernate"],
        "reboot": ["systemctl", "reboot"],
        "poweroff": ["systemctl", "poweroff"],
        "logout": ["qdbus6", "org.kde.Shutdown", "/Shutdown", "logout"],
    }
    if action in cmds:
        subprocess.Popen(cmds[action], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


# ---------------------------------------------------------------------------------------------
# Sistem ayarları, son belgeler, yer imleri, konsole profilleri
# ---------------------------------------------------------------------------------------------
class Cached:
    """Ara sıra yeniden okunan küçük listeler (dosya değişince ya da süre dolunca)."""

    def __init__(self, loader, ttl=300, watch=None):
        self._loader, self._ttl, self._watch = loader, ttl, watch
        self._data, self._at, self._stamp = None, 0, None
        self._lock = threading.Lock()

    def get(self):
        with self._lock:
            stamp = None
            if self._watch:
                try:
                    stamp = max(os.path.getmtime(p) for p in self._watch() if os.path.exists(p))
                except ValueError:
                    stamp = 0
            if self._data is None or time.time() - self._at > self._ttl or stamp != self._stamp:
                try:
                    self._data = self._loader()
                except Exception:
                    self._data = []
                self._at, self._stamp = time.time(), stamp
            return self._data


def _load_kcms():
    try:
        res = subprocess.run(["kcmshell6", "--list"], capture_output=True, text=True, timeout=5).stdout
    except Exception:
        return []
    out = []
    for line in res.splitlines():
        m = re.match(r"^(kcm_\S+|\S+)\s+-\s+(.+)$", line.strip())
        if m:
            out.append((m.group(1), m.group(2).strip()))
    return out


KCMS = Cached(_load_kcms, ttl=3600)


def settings(q, score):
    out = []
    for name, desc in KCMS.get():
        s = max(score(q, desc), score(q, name.replace("kcm_", "").replace("_", " ")) * 0.8)
        if s >= 60:
            out.append({"kind": "kcm", "kcm": name, "title": desc, "subtitle": _("Sistem Ayarları"),
                        "icon": "preferences-system", "mono": False, "score": s - 8})
    out.sort(key=lambda r: -r["score"])
    return out[:4]


RECENT_XBEL = os.path.join(HOME, ".local/share/recently-used.xbel")


def _load_recent():
    out = []
    root = ElementTree.parse(RECENT_XBEL).getroot()
    for b in root.findall("bookmark"):
        href = b.get("href", "")
        if not href.startswith("file://"):
            continue
        path = urllib.parse.unquote(href[7:])
        out.append((b.get("modified", ""), path))
    out.sort(reverse=True)
    seen, res = set(), []
    for _m, p in out:
        if p not in seen:
            seen.add(p)
            res.append(p)
    return res[:400]


RECENT = Cached(_load_recent, ttl=60, watch=lambda: [RECENT_XBEL])


def recent(q, score):
    out = []
    for i, path in enumerate(RECENT.get()):
        s = score(q, os.path.basename(path))
        if s >= 50 and os.path.exists(path):
            out.append({"kind": "path", "path": path, "title": os.path.basename(path),
                        "subtitle": "%s · %s" % (_("Son belge"), _short(os.path.dirname(path))),
                        "icon": "folder" if os.path.isdir(path) else "text-x-generic", "mono": False,
                        "score": s - 12 - min(8, i / 25)})
        if len(out) >= 4:
            break
    return out


BROWSERS = ["BraveSoftware/Brave-Browser", "google-chrome", "chromium", "vivaldi", "microsoft-edge"]


def _bookmark_files():
    return [p for b in BROWSERS for p in glob.glob(os.path.join(HOME, ".config", b, "*", "Bookmarks"))]


def _load_bookmarks():
    out = []

    def walk(node):
        if node.get("type") == "url":
            out.append((node.get("name", ""), node.get("url", "")))
        for c in node.get("children", []):
            walk(c)

    for path in _bookmark_files():
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
            for root in data.get("roots", {}).values():
                if isinstance(root, dict):
                    walk(root)
        except (OSError, ValueError):
            continue
    return out


BOOKMARKS = Cached(_load_bookmarks, ttl=600, watch=_bookmark_files)


def bookmarks(q, score):
    out = []
    for name, url in BOOKMARKS.get():
        s = max(score(q, name), score(q, url.split("//")[-1]) * 0.8)
        if s >= 60:
            out.append({"kind": "url", "url": url, "title": name or url, "subtitle": "%s · %s" % (_("Yer imi"), url[:60]),
                        "icon": "isle-link", "score": s - 10})
    out.sort(key=lambda r: -r["score"])
    return out[:3]


def konsole_profiles(q, score):
    out = []
    for p in glob.glob(os.path.join(HOME, ".local/share/konsole/*.profile")):
        name = os.path.basename(p)[:-len(".profile")]
        s = max(score(q, name), score(q, "konsole " + name) * 0.9)
        if s >= 60:
            out.append({"kind": "shell", "argv": ["konsole", "--profile", name], "title": "Konsole: " + name,
                        "subtitle": _("Konsole profili"), "icon": "isle-terminal-symbolic", "score": s - 5})
    return out


# ---------------------------------------------------------------------------------------------
# Saat/tarih, renk, karakter, yazım
# ---------------------------------------------------------------------------------------------
_ZONES = None


def _zones():
    global _ZONES
    if _ZONES is None:
        _ZONES = sorted(z for z in available_timezones() if "/" in z and not z.startswith(("Etc/", "SystemV/", "posix/", "right/")))
    return _ZONES


CITY_ALIASES = {"istanbul": "Europe/Istanbul", "ankara": "Europe/Istanbul", "izmir": "Europe/Istanbul",
                "londra": "Europe/London", "new york": "America/New_York", "nyc": "America/New_York",
                "san francisco": "America/Los_Angeles", "sf": "America/Los_Angeles", "berlin": "Europe/Berlin",
                "paris": "Europe/Paris", "tokyo": "Asia/Tokyo", "pekin": "Asia/Shanghai", "beijing": "Asia/Shanghai",
                "moskova": "Europe/Moscow", "dubai": "Asia/Dubai", "sydney": "Australia/Sydney", "utc": "UTC"}


def datetime_runner(q, fold):
    m = re.match(r"^\s*(saat|time|tarih|date|zaman)\b\s*(.*)$", q, re.I)
    if not m:
        return []
    word, place = m.group(1).lower(), fold(m.group(2).strip())
    tz, label = None, ""
    if place:
        z = CITY_ALIASES.get(place)
        if not z:
            key = place.replace(" ", "_")
            z = next((x for x in _zones() if fold(x.split("/")[-1]) == key), None) or \
                next((x for x in _zones() if key in fold(x)), None)
        if not z:
            return []
        tz, label = ZoneInfo(z), z.split("/")[-1].replace("_", " ")
    now = datetime.now(tz) if tz else datetime.now().astimezone()
    if word in ("tarih", "date"):
        text = now.strftime("%d.%m.%Y")
        sub = "%s %d" % (_("Hafta"), now.isocalendar()[1])
    else:
        text = now.strftime("%H:%M")
        off = now.utcoffset()
        h = int(off.total_seconds() // 3600) if off is not None else 0
        sub = (label + " · " if label else "") + "UTC%+d" % h
    return [{"kind": "copy", "text": text, "title": text, "subtitle": sub, "icon": "isle-timer", "score": 990}]


def color(q):
    s = q.strip().lower()
    rgb = None
    m = re.fullmatch(r"#?([0-9a-f]{6}|[0-9a-f]{3})", s)
    if m and (s.startswith("#") or re.search(r"[a-f]", s)):
        h = m.group(1)
        if len(h) == 3:
            h = "".join(c * 2 for c in h)
        rgb = tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
    m = re.fullmatch(r"rgba?\(\s*(\d{1,3})[\s,]+(\d{1,3})[\s,]+(\d{1,3}).*\)", s)
    if m:
        rgb = tuple(min(255, int(x)) for x in m.groups())
    if not rgb:
        return []
    hexs = "#%02x%02x%02x" % rgb
    h, l, sat = colorsys.rgb_to_hls(*(c / 255 for c in rgb))
    forms = [hexs, "rgb(%d, %d, %d)" % rgb, "hsl(%d, %d%%, %d%%)" % (h * 360, sat * 100, l * 100)]
    return [{"kind": "copy", "text": f, "title": f, "subtitle": _("Renk · kopyalamak için Enter"),
             "swatch": hexs, "icon": "", "score": 975 - i} for i, f in enumerate(forms)]


def characters(q):
    s = q.strip()
    out = []
    # "#2192", "u+1F49A", "0x41"; altı haneli "#…" renk sayılır (bkz. color)
    m = re.fullmatch(r"(?:#([0-9a-fA-F]{2,5})|(?:u\+|0x)([0-9a-fA-F]{2,6}))", s, re.I)
    if m:
        try:
            ch = chr(int(m.group(1) or m.group(2), 16))
            name = unicodedata.name(ch, "")
            if name:                      # atanmamış kod noktası değil
                out.append((ch, name))
        except (ValueError, OverflowError):
            pass
    m = re.fullmatch(r"(?:u|char|karakter):\s*(.{2,})", s, re.I)
    if m:
        words = m.group(1).upper().split()
        for cp in range(0x20, 0x1FAFF):
            name = unicodedata.name(chr(cp), "")
            if name and all(w in name for w in words):
                out.append((chr(cp), name))
                if len(out) >= 60:
                    break
        out.sort(key=lambda c: len(c[1]))     # en kısa ad en yaygın karakterdir ("→" önce)
        out = out[:6]
    return [{"kind": "copy", "text": ch, "title": name.title(), "subtitle": "U+%04X · %s" % (ord(ch), _("kopyalamak için Enter")),
             "icon": "", "glyph": ch, "score": 970} for ch, name in out]


def spell(q):
    m = re.match(r"^\s*(spell|yazım|yaz)\s+(\S+)\s*$", q, re.I)
    if not m or not shutil.which("hunspell"):
        return []
    word = m.group(2)
    lang = "tr_TR" if i18n.current() == "tr" else "en_US"
    try:
        res = subprocess.run(["hunspell", "-d", lang, "-a"], input=word + "\n", capture_output=True,
                             text=True, timeout=1.5).stdout.splitlines()
    except Exception:
        return []
    line = next((r for r in res if r[:1] in "*&#+-"), "")
    if line.startswith(("*", "+", "-")):
        return [{"kind": "copy", "text": word, "title": word, "subtitle": _("Doğru yazılmış"), "icon": "isle-check-symbolic", "score": 990}]
    sugg = line.split(":", 1)[1].split(",") if ":" in line else []
    return [{"kind": "copy", "text": w.strip(), "title": w.strip(), "subtitle": _("Öneri · kopyalamak için Enter"),
             "icon": "isle-text", "score": 990 - i} for i, w in enumerate(sugg[:5])]


# ---------------------------------------------------------------------------------------------
# Dosyalar (Baloo kapalıyken): plocate ev klasörünü görüyorsa o, görmüyorsa kendi küçük dizinimiz
# ---------------------------------------------------------------------------------------------
SKIP_DIRS = {"node_modules", "__pycache__", "venv", "site-packages", "target", "dist", "build", "Steam",
             "steamapps", "snap", "go", "OneDrive"}


class HomeIndex:
    """Ev klasöründeki dosya/klasör adları (gizliler ve geliştirme çöplükleri hariç), yalnızca bellekte.
    İlk aramada arka planda kurulur; 15 dk'da bir yenilenir. Baloo ve plocate ev klasörünü
    görmediğinde (ör. btrfs alt birimi) dosya araması buradan yapılır."""
    MAX = 250_000
    TTL = 900

    def __init__(self, root=HOME):
        self.root = root
        self.items = []          # (küçük harf ad, yol)
        self.built = 0
        self._busy = False
        self._lock = threading.Lock()

    def _build(self):
        items = []
        for base, dirs, files in os.walk(self.root):
            dirs[:] = [d for d in dirs if not d.startswith(".") and d not in SKIP_DIRS]
            for n in dirs + files:
                if not n.startswith("."):
                    items.append((n.lower(), os.path.join(base, n)))
            if len(items) >= self.MAX:
                break
        with self._lock:
            self.items, self.built, self._busy = items, time.time(), False

    def ensure(self):
        with self._lock:
            if self._busy or (self.items and time.time() - self.built < self.TTL):
                return
            self._busy = True
        threading.Thread(target=self._build, daemon=True).start()

    def search(self, q, limit=5):
        self.ensure()
        needle = q.lower()
        hits = [(n, p) for n, p in self.items if needle in n]
        hits.sort(key=lambda h: (not h[0].startswith(needle), len(h[0]), len(h[1])))
        return [p for _n, p in hits[:limit]]


HOME_INDEX = HomeIndex()
_plocate_home = None


def _plocate_sees_home():
    global _plocate_home
    if _plocate_home is None:
        try:
            out = subprocess.run(["plocate", "-c", HOME + "/"], capture_output=True, text=True, timeout=1).stdout
            _plocate_home = int(out.strip() or 0) > 0
        except Exception:
            _plocate_home = False
    return _plocate_home


def locate(q):
    q = q.strip()
    if len(q) < 3:
        return []
    paths = []
    if shutil.which("plocate") and _plocate_sees_home():
        try:
            res = subprocess.run(["plocate", "-i", "-l", "300", HOME + "/", q], capture_output=True,
                                 text=True, timeout=0.6).stdout
        except Exception:
            res = ""
        needle = q.lower()
        for path in res.splitlines():
            if ("/." not in path[len(HOME):] and "/node_modules/" not in path
                    and needle in os.path.basename(path).lower()):
                paths.append(path)
    else:
        paths = HOME_INDEX.search(q, limit=8)
    out = []
    for path in paths:
        if not os.path.exists(path):
            continue
        out.append({"kind": "path", "path": path, "title": os.path.basename(path),
                    "subtitle": _short(os.path.dirname(path)),
                    "icon": "folder" if os.path.isdir(path) else "text-x-generic", "mono": False, "score": 38})
        if len(out) >= 5:
            break
    return out


# ---------------------------------------------------------------------------------------------
# KRunner D-Bus eklentileri (org.kde.krunner1): pencereler, sekmeler, geçmiş, etkinlikler, Baloo
# ---------------------------------------------------------------------------------------------
PLUGIN_DIRS = ["/usr/share/krunner/dbusplugins", os.path.join(HOME, ".local/share/krunner/dbusplugins")]
# eklenti -> (gösterilen ad, ikon yoksa)
RUNNER_LABELS = {"/WindowsRunner": "Pencere", "/TabsRunner": "Sekme", "/HistoryRunner": "Geçmiş"}
RUNNER_WEIGHT = {"/WindowsRunner": 1.0, "/TabsRunner": 0.9, "/HistoryRunner": 0.7}


class DBusRunners:
    def __init__(self):
        from gi.repository import Gio, GLib   # yalnızca arka uçta (testler D-Bus'sız çalışsın)
        self.Gio, self.GLib = Gio, GLib
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.dead = {}          # (servis, yol) -> ne zamana kadar sorma
        self.plugins = self._plugins()

    def _plugins(self):
        out = []
        for d in PLUGIN_DIRS:
            for f in sorted(glob.glob(os.path.join(d, "*.desktop"))):
                vals = {}
                try:
                    with open(f, encoding="utf-8") as fh:
                        for line in fh:
                            if "=" in line:
                                k, v = line.strip().split("=", 1)
                                vals[k] = v
                except OSError:
                    continue
                svc, path = vals.get("X-Plasma-DBusRunner-Service"), vals.get("X-Plasma-DBusRunner-Path")
                if svc and path and "activit" not in f:
                    out.append((svc, path, vals.get("Name", "")))
        return out

    def _services(self, pattern):
        if "*" not in pattern:
            return [pattern]
        try:
            names = self.bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                                       "ListNames", None, None, self.Gio.DBusCallFlags.NONE, 300, None)[0]
        except Exception:
            return []
        return [n for n in names if fnmatch.fnmatch(n, pattern)]

    def _match(self, svc, path, q, out):
        key = (svc, path)
        if self.dead.get(key, 0) > time.time():
            return
        try:
            res = self.bus.call_sync(svc, path, "org.kde.krunner1", "Match", self.GLib.Variant("(s)", (q,)),
                                     self.GLib.VariantType("(a(sssida{sv}))"), self.Gio.DBusCallFlags.NONE, 400, None)[0]
        except Exception:
            self.dead[key] = time.time() + 60     # yok ya da kapalı (ör. Baloo): bir dakika sorma
            return
        label = _(RUNNER_LABELS.get(path, "KRunner"))
        weight = RUNNER_WEIGHT.get(path, 0.6)
        for mid, text, icon, _cat, relevance, props in res[:5]:
            sub = props.get("subtext", "") if isinstance(props, dict) else ""
            out.append({"kind": "runner", "service": svc, "path": path, "match": mid, "title": text,
                        "subtitle": (label + (" · " + sub if sub else "")), "icon": icon or "window",
                        "mono": False, "score": 45 + 40 * float(relevance) * weight})

    def search(self, q):
        if len(q.strip()) < 2:
            return []
        out, threads = [], []
        for pattern, path, _name in self.plugins:
            for svc in self._services(pattern):
                t = threading.Thread(target=self._match, args=(svc, path, q, out), daemon=True)
                t.start()
                threads.append(t)
        for t in threads:
            t.join(0.45)
        return list(out)

    def run(self, svc, path, match):
        if not any(svc == s or fnmatch.fnmatch(svc, s) for s, p, _n in self.plugins if p == path):
            return False
        try:
            self.bus.call_sync(svc, path, "org.kde.krunner1", "Run", self.GLib.Variant("(ss)", (match, "")),
                               None, self.Gio.DBusCallFlags.NONE, 1000, None)
            return True
        except Exception:
            return False


def kill_pid(pid):
    """Yalnızca bu kullanıcının süreçleri; önce SIGTERM."""
    try:
        if os.stat("/proc/%d" % pid).st_uid != os.getuid() or pid == os.getpid():
            return False
        os.kill(pid, signal.SIGTERM)
        return True
    except (OSError, ValueError):
        return False


def open_path(path):
    subprocess.Popen(["xdg-open", path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


def open_kcm(name):
    if re.fullmatch(r"[A-Za-z0-9_.-]+", name):
        subprocess.Popen(["systemsettings", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
