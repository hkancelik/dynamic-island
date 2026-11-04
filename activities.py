"""Canlı Etkinlikler (Live Activities): betikler ve uygulamalar adaya kalıcı bir kart koyar.

Bir etkinlik; derleme, indirme, zamanlayıcı, dağıtım gibi süren bir işi temsil eder.
`island` komutu ya da doğrudan HTTP (POST /activity) ile yönetilir:

  {"op": "set", "id": "build", "title": "cargo build", "progress": 0.4}
  {"op": "end", "id": "build", "state": "failed", "message": "exit 101"}
  {"op": "notify", "title": "Yedek bitti", "body": "42 GB"}
  {"op": "list"}

Alanlar (hepsi isteğe bağlı, id dışında):
  title, subtitle   kısa metinler
  progress          0..1; yoksa (ya da -1) belirsiz: dönen halka
  value             sağda gösterilen kısa metin ("42%", "3/10"); boşsa süre gösterilir
  icon              hazır ad (build, download, upload, timer, test, deploy, sync, terminal,
                    music, mail, check, warning) ya da freedesktop ikon adı
  color             "#rrggbb" vurgu rengi
  left, right       skor tabelası (maç): iki yanın kısa metni ("1", "0"); ikisi de varsa kapalı ada
                    [sol_ikon sol] orta [sağ sağ_ikon] biçiminde çizilir
  left_icon,        takım logosu: hazır/freedesktop ikon adı, mutlak dosya yolu ya da file:// adresi
  right_icon
  center            iki skorun ortasında kısa metin ("67'", "İY"); boşsa saat görünür
  end               bitiş anı (ms, epoch): geri sayım; süre dolunca etkinlik kendiliğinden biter
  ttl               saniye; bu kadar güncellenmezse etkinlik kaldırılır (varsayılan 900)
"""
import os
import re
import subprocess
import threading
import time

from i18n import _

MAX_ITEMS = 8
DEFAULT_TTL = 900
MAX_TTL = 7 * 86400
_ID_RE = re.compile(r"^[A-Za-z0-9_.:-]{1,48}$")
_COLOR_RE = re.compile(r"^#[0-9a-fA-F]{6}$")

PALETTE = {
    "build": "#ff9f0a", "download": "#0a84ff", "upload": "#5e5ce6", "timer": "#ff9f0a",
    "test": "#30d158", "deploy": "#bf5af2", "sync": "#64d2ff",
    "music": "#ff375f", "mail": "#0a84ff", "check": "#30d158", "warning": "#ff453a",
}

# Zamanlayıcı bitince çalınacak ses (ilk bulunan)
SOUNDS = (
    "/usr/share/sounds/ocean/stereo/completion-success.oga",
    "/usr/share/sounds/freedesktop/stereo/complete.oga",
    "/usr/share/sounds/freedesktop/stereo/bell.oga",
)


def _now_ms():
    return int(time.time() * 1000)


def _text(v, n):
    return " ".join(str(v).split())[:n] if v is not None else ""


def _logo(v):
    """İkon adı, mutlak yol ya da file:// adresi; diğer her şey (http dahil) boş sayılır."""
    v = _text(v, 256)
    if v.startswith("file://") or v.startswith("/"):
        return v
    return v if re.fullmatch(r"[A-Za-z0-9_.-]{1,64}", v) else ""


def _num(v):
    try:
        f = float(str(v).rstrip("%"))
    except (TypeError, ValueError):
        return None
    if str(v).endswith("%") or f > 1:
        f /= 100
    return max(0.0, min(1.0, f))


def parse_duration(s):
    """"90", "90s", "5m", "1h30m", "1:30" (dk:sn), "1:00:00" -> saniye. Geçersizse None."""
    s = str(s).strip().lower()
    if not s:
        return None
    if ":" in s:
        try:
            parts = [int(p) for p in s.split(":")]
        except ValueError:
            return None
        if len(parts) > 3 or any(p < 0 for p in parts):
            return None
        total = 0
        for p in parts:
            total = total * 60 + p
        return total or None
    if s.isdigit():
        return int(s) or None
    m = re.fullmatch(r"(?:(\d+)\s*h)?\s*(?:(\d+)\s*m(?:in)?)?\s*(?:(\d+)\s*s(?:ec)?)?", s)
    if not m or not any(m.groups()):
        return None
    h, mi, se = (int(g or 0) for g in m.groups())
    return h * 3600 + mi * 60 + se or None


class Activities:
    def __init__(self, publish, play_sound=True):
        self._publish = publish
        self._lock = threading.Lock()
        self._items = {}               # id -> etkinlik
        self._seen = {}                # id -> son güncelleme (sn, monotonic)
        self._done = {"seq": 0}
        self._auto = 0
        self._play_sound = play_sound
        self._emit()
        threading.Thread(target=self._tick, daemon=True).start()

    # -- yayın
    def _emit(self):
        items = sorted(self._items.values(), key=lambda a: a["start"])
        self._publish({"items": items, "done": dict(self._done)})

    def snapshot(self):
        with self._lock:
            return sorted(self._items.values(), key=lambda a: a["start"])

    # -- işlemler
    def handle(self, msg):
        """HTTP gövdesini işler; istemciye dönecek sözlüğü verir. Hatalarda ValueError."""
        op = str(msg.get("op", "set"))
        if op == "set":
            return {"id": self.set(msg)}
        if op == "end":
            return {"ok": self.end(str(msg.get("id", "")), str(msg.get("state", "done")),
                                   msg.get("message"))}
        if op == "notify":
            self.notify(msg)
            return {"ok": True}
        if op == "list":
            return {"items": self.snapshot()}
        if op == "clear":
            with self._lock:
                self._items.clear()
                self._seen.clear()
                self._emit()
            return {"ok": True}
        raise ValueError(_("bilinmeyen işlem: %s") % op)

    def set(self, d):
        aid = str(d.get("id") or "")
        with self._lock:
            if not aid:
                self._auto += 1
                aid = "a%d" % self._auto
            if not _ID_RE.match(aid):
                raise ValueError(_("geçersiz id"))
            cur = self._items.get(aid)
            new = cur is None
            if new:
                if len(self._items) >= MAX_ITEMS:
                    # en eski ve en uzun süredir güncellenmeyen yer açar
                    oldest = min(self._items, key=lambda k: self._seen.get(k, 0))
                    self._items.pop(oldest)
                    self._seen.pop(oldest, None)
                cur = {"id": aid, "title": aid, "subtitle": "", "progress": -1.0, "value": "",
                       "icon": "", "color": "", "left": "", "right": "", "left_icon": "",
                       "right_icon": "", "center": "", "start": _now_ms(), "end": 0, "ttl": DEFAULT_TTL}
            a = dict(cur)
            if "title" in d:
                a["title"] = _text(d["title"], 80) or aid
            if "subtitle" in d:
                a["subtitle"] = _text(d["subtitle"], 120)
            if "value" in d:
                a["value"] = _text(d["value"], 12)
            if "icon" in d:
                a["icon"] = _text(d["icon"], 64)
            for k in ("left", "right", "center"):
                if k in d:
                    a[k] = _text(d[k], 12)
            for k in ("left_icon", "right_icon"):
                if k in d:
                    a[k] = _logo(d[k])
            if "progress" in d:
                p = d["progress"]
                if p is None or str(p).strip() in ("", "-1"):
                    a["progress"] = -1.0
                elif _num(p) is not None:
                    a["progress"] = _num(p)
            if "color" in d:
                c = str(d["color"] or "")
                a["color"] = c if _COLOR_RE.match(c) else ""
            if not a["color"]:
                a["color"] = PALETTE.get(a["icon"], "")
            if "end" in d:
                try:
                    a["end"] = max(0, int(float(d["end"])))
                except (TypeError, ValueError):
                    pass
            if "duration" in d:
                secs = parse_duration(d["duration"])
                if secs is None:
                    raise ValueError(_("geçersiz süre"))
                a["start"] = _now_ms()
                a["end"] = a["start"] + secs * 1000
            if "ttl" in d:
                try:
                    a["ttl"] = max(5, min(MAX_TTL, int(d["ttl"])))
                except (TypeError, ValueError):
                    pass
            if a["end"]:   # geri sayım en az kendi süresi kadar yaşar
                a["ttl"] = max(a["ttl"], int((a["end"] - _now_ms()) / 1000) + 60)
            self._items[aid] = a
            self._seen[aid] = time.monotonic()
            if new or a != cur:
                self._emit()
            return aid

    def end(self, aid, state="done", message=None):
        with self._lock:
            a = self._items.pop(aid, None)
            self._seen.pop(aid, None)
            if a is None:
                return False
            self._finish(a, state if state in ("done", "failed", "cancelled") else "done", message)
            return True

    def notify(self, d):
        with self._lock:
            icon = _text(d.get("icon", ""), 64)
            c = str(d.get("color") or "")
            self._done = {
                "seq": self._done["seq"] + 1,
                "state": "info",
                "title": _text(d.get("title", ""), 80) or "Dynamic Island",
                "subtitle": _text(d.get("body", ""), 160),
                "icon": icon,
                "color": c if _COLOR_RE.match(c) else PALETTE.get(icon, ""),
            }
            self._emit()

    def _finish(self, a, state, message):
        # kilit tutulurken çağrılır
        secs = max(0, (_now_ms() - a["start"]) // 1000)
        took = "%d:%02d" % (secs // 60, secs % 60) if secs < 3600 else "%d:%02d:%02d" % (
            secs // 3600, secs // 60 % 60, secs % 60)
        self._done = {
            "seq": self._done["seq"] + 1,
            "id": a["id"],
            "state": state,
            "title": a["title"],
            "subtitle": _text(message, 160) if message else a["subtitle"],
            "took": took,
            "icon": a["icon"],
            "color": a["color"],
        }
        self._emit()

    # -- zaman
    def _tick(self):
        while True:
            time.sleep(1)
            fired = False
            with self._lock:
                now_ms, now = _now_ms(), time.monotonic()
                for aid, a in list(self._items.items()):
                    if a["end"] and now_ms >= a["end"]:
                        self._items.pop(aid)
                        self._seen.pop(aid, None)
                        self._finish(a, "done", a["subtitle"] or None)
                        fired = True
                    elif now - self._seen.get(aid, now) > a["ttl"]:
                        self._items.pop(aid)
                        self._seen.pop(aid, None)
                        self._emit()
            if fired and self._play_sound:
                _chime()


def _chime():
    for path in SOUNDS:
        if os.path.exists(path):
            for player in (("pw-play", path), ("paplay", path)):
                try:
                    subprocess.Popen(player, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                     start_new_session=True)
                    return
                except FileNotFoundError:
                    continue
            return
