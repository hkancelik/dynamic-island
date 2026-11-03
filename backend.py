#!/usr/bin/env python3
"""Dynamic Island backend.

Olay tabanlı: MPRIS (D-Bus) ve PipeWire/Pulse olaylarını dinler, değişiklik
olduğunda durumu günceller. QML tarafı 127.0.0.1 üzerinden
  GET  /state?v=N   -> durum değişene kadar bekler (long-poll)
  POST /cmd         -> {"cmd": "...", "arg": ...}
ile konuşur.
"""
import hmac
import json
import os
import re
import signal
import subprocess
import sys
import threading
import time
from datetime import datetime, timedelta
from datetime import time as dtime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, quote_plus, urlparse

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

try:  # GLib >= 2.78
    from gi.repository import GLibUnix
    _signal_add = GLibUnix.signal_add
except ImportError:
    _signal_add = GLib.unix_signal_add

import activities as activities_mod  # noqa: E402
import apps  # noqa: E402
import audio  # noqa: E402
import calendar_ics  # noqa: E402
import caldav  # noqa: E402
import config  # noqa: E402
import i18n  # noqa: E402
from i18n import _  # noqa: E402
import focus  # noqa: E402
import lyrics as lyrics_mod  # noqa: E402
import privacy  # noqa: E402
import phone as phone_mod  # noqa: E402
import weather as weather_mod  # noqa: E402
from alerts import Alerts  # noqa: E402
from agents import Agents  # noqa: E402
import controls  # noqa: E402
import palette as palette_mod  # noqa: E402
import preview as preview_mod  # noqa: E402
import shots as shots_mod  # noqa: E402
import sounds as sounds_mod  # noqa: E402
import spectrum as spectrum_mod  # noqa: E402
import sysinfo  # noqa: E402
from clipboard import Clipboard  # noqa: E402
from record import Recorder  # noqa: E402
from store import Store  # noqa: E402
from fullscreen import Fullscreen  # noqa: E402
from notifications import Notifications  # noqa: E402

PORT = 47615
TOKEN = config.make_token()
MPRIS_PREFIX = "org.mpris.MediaPlayer2."
MPRIS_PATH = "/org/mpris/MediaPlayer2"
PLAYER_IFACE = "org.mpris.MediaPlayer2.Player"
PROPS_IFACE = "org.freedesktop.DBus.Properties"


# --------------------------------------------------------------------------
# Paylaşılan durum
# --------------------------------------------------------------------------
class State:
    """Anahtar başına sürüm tutar; istemciye yalnızca değişen anahtarlar gönderilir."""

    def __init__(self):
        self.cond = threading.Condition()
        self.version = 1
        self.data = {
            "volume": {"level": 50, "muted": False},
            "media": {"active": False},
            "battery": {"present": False, "level": 100, "charging": False},
            "wifi": {"connected": False, "ssid": "", "signal": 0, "type": "none"},
            "notifs": {"seq": 0, "items": []},
            "calendar": {"configured": False, "events": [], "errors": []},
            "apps": [],
            "controls": {"wifiOn": True, "bt": {"present": False, "on": False, "device": ""}},
            "power": {"profile": "", "profiles": []},
            "night": {"available": False, "enabled": False, "running": False,
                      "inhibited": False, "mine": False, "temp": 0},
            "displays": [],
            "fullscreen": False,
            "ui": {"hidden": False, "dnd": False},
            "stats": {},
            "audio": {"default": "", "sinks": []},
            "clip": [],
            "clipOn": False,
            "notes": [],
            "shelf": [],
            "docs": [],
            "docNew": {"seq": 0, "id": 0},
            "weather": {"ok": False},
            "phone": {"present": False, "devices": []},
            "rec": {"state": "idle", "since": 0, "error": "", "last": ""},
            "panelReq": 0,
            "tabReq": {"seq": 0},
            "activities": {"items": [], "done": {"seq": 0}},
            "paletteReq": {"seq": 0, "q": ""},
            "shot": {"seq": 0},
            "quickReq": {"seq": 0, "path": ""},
        }
        self.kv = {k: 1 for k in self.data}  # anahtar -> son değiştiği sürüm

    def update(self, key, value):
        with self.cond:
            if self.data.get(key) == value:
                return
            self.data[key] = value
            self.version += 1
            self.kv[key] = self.version
            self.cond.notify_all()

    def wait(self, since, timeout=25):
        with self.cond:
            if self.version == since:
                self.cond.wait(timeout)
            changed = {k: v for k, v in self.data.items() if self.kv.get(k, 0) > since}
            return self.version, changed


state = State()


def run(*args, timeout=3):
    try:
        return subprocess.run(
            args, capture_output=True, text=True, timeout=timeout,
            env={**os.environ, "LC_ALL": "C"},  # nmcli/wpctl çıktısı yerelleşmesin
        ).stdout
    except Exception:
        return ""


# --------------------------------------------------------------------------
# Ses
# --------------------------------------------------------------------------
def on_brightness(displays):
    """Parlaklık değişince durumu güncelle ve nedenini araştırmak için günlüğe yaz."""
    global last_br
    state.update("displays", displays)
    # günlük yalnızca yerleşik ekranı (yoksa ilk ekranı) izler
    main = next((d for d in displays if d["internal"]), displays[0] if displays else None)
    percent = main["percent"] if main else -1
    if last_br is not None and percent != last_br and percent >= 0:
        who = "ada" if time.time() - last_br_cmd < 1.5 else "sistem"
        ctx = []
        try:
            ctx.append("AC=" + (open("/sys/class/power_supply/AC/online").read().strip()))
            ctx.append(open("/sys/class/power_supply/BAT0/status").read().strip())
            ctx.append(open("/sys/class/power_supply/BAT0/capacity").read().strip() + "%")
        except OSError:
            pass
        if power:
            ctx.append("profil=" + power.value()["profile"])
        try:
            os.makedirs(os.path.dirname(BR_LOG), exist_ok=True)
            if os.path.exists(BR_LOG) and os.path.getsize(BR_LOG) > 200_000:
                os.replace(BR_LOG, BR_LOG + ".1")
            with open(BR_LOG, "a") as f:
                f.write(f"{time.strftime('%d.%m %H:%M:%S')}  %{last_br} -> %{percent}  [{who}]  {' '.join(ctx)}\n")
        except OSError:
            pass
    if percent >= 0:
        last_br = percent


def refresh_volume():
    out = run("wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@")
    try:
        level = int(round(float(out.split()[1]) * 100))
        state.update("volume", {"level": level, "muted": "[MUTED]" in out})
    except Exception:
        pass


_vol_dirty = threading.Event()


def refresh_audio():
    state.update("audio", audio.snapshot())


def volume_refresher():
    """pactl olayları art arda gelir; kısa süre bekleyip tek seferde okur."""
    while True:
        _vol_dirty.wait()
        time.sleep(0.04)
        _vol_dirty.clear()
        refresh_volume()
        refresh_audio()


def _die_with_parent():
    """Alt süreç, arka uç kapanınca (çökse bile) onunla birlikte kapansın.
    Yoksa her yeniden başlatmada bir `pactl subscribe` artar ve PipeWire'ın
    istemci sınırı dolunca ses olayları hiç gelmez."""
    import ctypes
    ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGTERM)   # PR_SET_PDEATHSIG


def volume_watcher():
    threading.Thread(target=volume_refresher, daemon=True).start()
    while True:
        try:
            p = subprocess.Popen(
                ["pactl", "subscribe"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                preexec_fn=_die_with_parent,
            )
            for line in p.stdout:
                if "sink" in line and "server" not in line:
                    _vol_dirty.set()
        except Exception:
            pass
        time.sleep(2)


# --------------------------------------------------------------------------
# Pil ve ağ (yavaş değişenler, ayrı iş parçacığında)
# --------------------------------------------------------------------------
def read_network():
    out = run("nmcli", "-t", "-f", "ACTIVE,SSID,SIGNAL", "dev", "wifi", "list", "--rescan", "no", timeout=6)
    for line in out.splitlines():
        parts = line.split(":")
        if parts and parts[0] == "yes":
            try:
                signal = int(parts[-1])
            except ValueError:
                signal = 0
            return {
                "connected": True,
                "ssid": ":".join(parts[1:-1]),
                "signal": signal,
                "type": "wifi",
            }
    for line in run("nmcli", "-t", "-f", "TYPE,STATE", "dev").splitlines():
        if line.startswith("ethernet:connected"):
            return {"connected": True, "ssid": "Ethernet", "signal": 100, "type": "ethernet"}
    return {"connected": False, "ssid": "", "signal": 0, "type": "none"}


_net_last = None
_net_misses = 0


def read_network_stable():
    """Tarama/yoğunluk yüzünden gelen anlık "bağlı değil" okumalarını yok sayar:
    bağlıyken en az 3 ardışık başarısız okuma olmadan bağlantı kopmuş sayılmaz."""
    global _net_last, _net_misses
    net = read_network()
    if net["connected"]:
        _net_last, _net_misses = net, 0
        return net
    _net_misses += 1
    if _net_last is not None and _net_misses < 3:
        return _net_last
    _net_last = None
    return net


cfg = config.load()


_dav = {}            # hesap anahtarı -> caldav.Account (keşif önbelleği korunur)
_cal_lock = threading.Lock()


def dav_accounts():
    out = []
    for conf in cfg.get("caldav", []):
        if not conf.get("user"):
            continue
        key = (conf.get("url"), conf.get("user"), conf.get("password"), conf.get("password_cmd"),
               tuple(conf.get("calendars", [])))
        if key not in _dav:
            _dav[key] = caldav.Account(conf)
        out.append(_dav[key])
    return out


def refresh_calendar():
    with _cal_lock:
        sources = list(cfg.get("calendars", []))
        accounts = dav_accounts()
        if not sources and not accounts:
            state.update("calendar", {"configured": False, "events": [], "errors": [], "writable": False})
            return
        errors = []
        now = datetime.now().astimezone()
        start = datetime.combine(now.date(), dtime()).astimezone() - timedelta(days=calendar_ics.PAST_DAYS)
        end = start + timedelta(days=calendar_ics.WINDOW_DAYS)
        writable = False
        for acc in accounts:
            try:
                cals = acc.discover()
            except Exception as e:
                errors.append(f"{acc.name}: {e}")
                continue
            writable = writable or any(c["writable"] for c in cals)
            for c in cals:
                try:
                    sources.append({"texts": acc.events(c, start, end), "color": c["color"],
                                    "label": f"{acc.name} · {c['name']}"})
                except Exception as e:
                    errors.append(f"{acc.name} · {c['name']}: {e}")
        events, errs = calendar_ics.fetch(sources)
        state.update("calendar", {"configured": True, "events": events, "errors": errors + errs,
                                  "writable": writable})


_cal_seq = 0


def parse_quick_event(text, day_ms):
    """"Akşam yemeği 20:00", "Toplantı 14:00-15:30", "Doğum günü" (tüm gün)."""
    day = datetime.fromtimestamp(day_ms / 1000).astimezone().date()
    m = re.search(r"\b(\d{1,2})[:.](\d{2})(?:\s*[-–]\s*(\d{1,2})[:.](\d{2}))?\b", text)
    title = text
    if m and int(m.group(1)) < 24 and int(m.group(2)) < 60:
        title = (text[:m.start()] + text[m.end():]).strip(" ,-–")
        s = datetime.combine(day, dtime(int(m.group(1)), int(m.group(2)))).astimezone()
        if m.group(3) and int(m.group(3)) < 24 and int(m.group(4)) < 60:
            e = datetime.combine(day, dtime(int(m.group(3)), int(m.group(4)))).astimezone()
            if e <= s:
                e += timedelta(days=1)
        else:
            e = s + timedelta(hours=1)
        return title or _("Etkinlik"), s, e, False
    return title.strip() or _("Etkinlik"), day, day + timedelta(days=1), True


def cal_add(arg):
    global _cal_seq
    text = str(arg.get("text", "")).strip()
    if not text:
        return
    _cal_seq += 1
    try:
        title, s, e, all_day = parse_quick_event(text, float(arg.get("day", time.time() * 1000)))
        target = None
        for acc in dav_accounts():
            acc.discover()
            target = acc.writable_calendar(cfg.get("caldav_default", ""))
            if target:
                acc.add(target, title, s, e, all_day)
                break
        if target is None:
            raise caldav.CalDAVError(_("yazılabilir takvim yok (config'e caldav hesabı ekle)"))
        state.update("calAdd", {"seq": _cal_seq, "ok": True, "msg": f"{target['name']}: {title}"})
        refresh_calendar()
    except Exception as ex:
        print("takvim ekleme hatası:", ex, flush=True)
        state.update("calAdd", {"seq": _cal_seq, "ok": False, "msg": str(ex)})


CLAUDE_SETTINGS = os.path.join(os.environ.get("CLAUDE_CONFIG_DIR", os.path.expanduser("~/.claude")),
                               "settings.json")


def claude_hooks_installed():
    try:
        with open(CLAUDE_SETTINGS) as f:
            return "/agent_hook.py" in json.dumps(json.load(f).get("hooks", {}))
    except Exception:
        return False


def publish_settings():
    state.update("settings", {
        **{k: bool(cfg.get(k, config.DEFAULTS.get(k, True))) for k in config.SWITCHES},
        "claudeHooks": claude_hooks_installed(),
        "accounts": [a.get("name") or a.get("user", "") for a in cfg.get("caldav", []) if a.get("user")],
        "calendars": len(cfg.get("calendars", [])),
        "shortcuts": cfg.get("shortcuts", {}),
        "language": cfg.get("language", "auto"),
        "layout": config.clean_layout(cfg.get("layout")),
    })


def apply_switch(key, value):
    """Ayar sayfasından gelen değişikliği hemen uygula (yeniden başlatmadan)."""
    global cfg, clip
    if not config.set_switch(key, value):
        return
    cfg = config.load()
    if key == "suppress_plasma_popups" and notifs:
        notifs.suppress = bool(value)
    elif key == "clipboard_history":
        if value and clip is None:
            clip = Clipboard(lambda v: state.update("clip", v))
            state.update("clipOn", clip.start())
        elif clip is not None:
            clip.enabled = bool(value)
            if not value:   # kapatınca sabitlenenler dahil hepsi silinir
                clip.items = []
                clip._publish()
            state.update("clipOn", bool(value))
    elif key == "otp_capture" and notifs:
        notifs.otp = bool(value)
    elif key == "lyrics" and not value and lyrics:
        lyrics.set_want(False)
    elif key == "weather_enabled" and weather:
        weather.refresh()
    elif key == "phone":
        set_phone(bool(value))
    publish_settings()


def set_layout(changes):
    global cfg
    merged = {**config.clean_layout(cfg.get("layout")), **changes}
    config.set_value("layout", config.clean_layout(merged))
    cfg = config.load()
    publish_settings()


def set_language(lang):
    global cfg
    config.set_value("language", lang)
    cfg = config.load()
    i18n.reload()
    publish_settings()


def set_phone(on):
    """KDE Connect bağlantısını aç/kapat (kapalıyken D-Bus'a hiç bakılmaz)."""
    global phone
    if on and phone is None:
        try:
            phone = phone_mod.Phone(lambda v: state.update("phone", v) if cfg.get("phone", True) else None,
                                    emit_alert)
        except Exception as e:
            print("KDE Connect yok:", e, flush=True)
    elif not on:
        state.update("phone", {"present": False, "devices": []})


def set_claude_hooks(on):
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "install-claude-hooks.sh")
    run(script, *([] if on else ["--remove"]), timeout=10)
    publish_settings()


def refresh_controls():
    state.update("controls", {
        "wifiOn": controls.wifi_enabled(),
        "bt": controls.bt_state(),
    })


def bg(fn):
    threading.Thread(target=fn, daemon=True).start()


_alert_seq = 0
_alert_lock = threading.Lock()


def emit_alert(d):
    """Kısa sistem uyarısı (Caps Lock, Bluetooth, internet): arayüz seq değişince gösterir."""
    global _alert_seq
    with _alert_lock:
        _alert_seq += 1
        state.update("alert", {**d, "seq": _alert_seq})


def slow_poller():
    global cfg
    last_cfg = config.mtime()
    last_cal = 0
    last_ctl = 0
    first_net = True
    while True:
        state.update("battery", sysinfo.battery_info())
        prev_net = state.data["wifi"]
        net = read_network_stable()
        state.update("wifi", net)
        if first_net:   # ilk okumada uyarı yok
            first_net = False
        else:
            if prev_net.get("connected") and not net["connected"]:
                emit_alert({"kind": "net", "connected": False})
            elif not prev_net.get("connected") and net["connected"]:
                emit_alert({"kind": "net", "connected": True, "ssid": net.get("ssid", ""),
                            "wired": net.get("type") == "ethernet"})

        if time.time() - last_ctl > 15:
            last_ctl = time.time()
            refresh_controls()

        changed = config.mtime() != last_cfg
        if changed:
            last_cfg = config.mtime()
            cfg = config.load()
            publish_settings()
            if weather:
                weather.refresh()
        if changed or time.time() - last_cal > 600:
            last_cal = time.time()
            try:
                refresh_calendar()
            except Exception as e:
                print("takvim hatası:", e, flush=True)
        time.sleep(5)


# --------------------------------------------------------------------------
# MPRIS
# --------------------------------------------------------------------------
class Mpris:
    def __init__(self):
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.players = {}  # bus name -> son oynatma zamanı
        self.current = None
        self._pending = False
        self.bus.signal_subscribe(
            "org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged",
            "/org/freedesktop/DBus", None, Gio.DBusSignalFlags.NONE,
            self.on_name_owner,
        )
        self.bus.signal_subscribe(
            None, PROPS_IFACE, "PropertiesChanged", MPRIS_PATH, PLAYER_IFACE,
            Gio.DBusSignalFlags.NONE, self.on_props,
        )
        self.bus.signal_subscribe(
            None, PLAYER_IFACE, "Seeked", MPRIS_PATH, None,
            Gio.DBusSignalFlags.NONE, self.on_props,
        )
        names = self.bus.call_sync(
            "org.freedesktop.DBus", "/org/freedesktop/DBus",
            "org.freedesktop.DBus", "ListNames", None, GLib.VariantType("(as)"),
            Gio.DBusCallFlags.NONE, -1, None,
        )[0]
        for n in names:
            if n.startswith(MPRIS_PREFIX):
                self.players[n] = 0
        self.refresh()
        GLib.timeout_add_seconds(10, self.resync)

    # -- olaylar
    def on_name_owner(self, _c, _s, _p, _i, _sig, params):
        name, _old, new = params.unpack()
        if not name.startswith(MPRIS_PREFIX):
            return
        if new:
            self.players.setdefault(name, 0)
        else:
            self.players.pop(name, None)
        self.refresh()

    def on_props(self, *_):
        # Tarayıcılar kısa sürede onlarca sinyal gönderir: tek yenilemede birleştir
        if not self._pending:
            self._pending = True
            GLib.timeout_add(60, self._flush)

    def _flush(self):
        self._pending = False
        self.refresh()
        return False

    def resync(self):
        if self.players:
            self.refresh()  # Position sinyal göndermediği için ara sıra eşitle
        return True

    # -- okuma
    def get_all(self, name):
        try:
            res = self.bus.call_sync(
                name, MPRIS_PATH, PROPS_IFACE, "GetAll",
                GLib.Variant("(s)", (PLAYER_IFACE,)), GLib.VariantType("(a{sv})"),
                Gio.DBusCallFlags.NONE, 500, None,
            )
            return res[0]
        except Exception:
            return None

    def refresh(self):
        infos = {}
        for name in list(self.players):
            props = self.get_all(name)
            if props is not None:
                infos[name] = props
        # Tarayıcı eklentisi (plasma-browser-integration) varken tarayıcının kendi MPRIS kaydı
        # yinelenir: başlığı genel ("... Web Player"), ama konumu eklentininkinden daha doğru.
        # Kaydı listeden çıkar, konumunu eklentiye ver.
        sibling = {}
        for name, props in list(infos.items()):
            pid = props.get("Metadata", {}).get("kde:pid")
            if pid is None:
                continue
            for other in list(infos):
                if other != name and other.endswith(f".instance{pid}"):
                    sibling[name] = infos.pop(other)
        playing =[n for n, p in infos.items() if p.get("PlaybackStatus") == "Playing"]
        paused = [n for n, p in infos.items() if p.get("PlaybackStatus") == "Paused"]
        if playing:
            if self.current in playing:
                pick = self.current
            else:
                pick = max(playing, key=lambda n: self.players.get(n, 0))
            self.players[pick] = time.time()
        elif self.current in paused:
            pick = self.current
        elif paused:
            pick = max(paused, key=lambda n: self.players.get(n, 0))
        else:
            pick = None
        self.current = pick

        if pick is None:
            state.update("media", {"active": False})
            if lyrics:
                lyrics.on_media({"active": False})
            return
        p = infos[pick]
        md = p.get("Metadata", {})
        artists = md.get("xesam:artist", [])
        if isinstance(artists, str):
            artists = [artists]
        pos = sibling.get(pick, p).get("Position", 0)
        status = p.get("PlaybackStatus", "Stopped")
        state.update("media", {
            "active": True,
            "player": pick[len(MPRIS_PREFIX):].split(".instance")[0],
            "status": status,
            "title": md.get("xesam:title", ""),
            "artist": ", ".join(artists),
            "album": md.get("xesam:album", ""),
            "artUrl": md.get("mpris:artUrl", ""),
            "url": str(md.get("xesam:url", "")),          # yerel dosyaysa yanındaki .lrc aranır
            "length": int(md.get("mpris:length", 0)) // 1000,  # ms
            "position": int(pos) // 1000,  # ms
            "stamp": int(time.time() * 1000),
            "canNext": bool(p.get("CanGoNext", True)),
            "canPrev": bool(p.get("CanGoPrevious", True)),
            "canSeek": bool(p.get("CanSeek", False)),
        })
        if lyrics:
            lyrics.on_media(state.data["media"])

    # -- komutlar
    def call(self, method, params=None, sig=None):
        if not self.current:
            return
        try:
            self.bus.call_sync(
                self.current, MPRIS_PATH, PLAYER_IFACE, method,
                GLib.Variant(sig, params) if sig else None, None,
                Gio.DBusCallFlags.NONE, 800, None,
            )
        except Exception:
            pass
        self.refresh()

    def raise_player(self):
        if not self.current:
            return
        try:
            self.bus.call_sync(
                self.current, MPRIS_PATH, "org.mpris.MediaPlayer2", "Raise", None, None,
                Gio.DBusCallFlags.NONE, 800, None,
            )
        except Exception:
            pass

    def seek_to(self, ms):
        if not self.current:
            return
        md = (self.get_all(self.current) or {}).get("Metadata", {})
        track = md.get("mpris:trackid")
        if track:
            self.call("SetPosition", (track, int(ms) * 1000), "(ox)")


mpris = None
notifs = None
brightness = None
last_br_cmd = 0.0      # adanın en son parlaklık komutu verdiği an
last_br = None
BR_LOG = os.path.expanduser("~/.local/state/dynamic-island/brightness.log")
power = None
night = None
fs_watch = None
shot_watch = None
store = None
stats = None
clip = None
recorder = None
focus_timer = None
lyrics = None
weather = None
phone = None
agents = Agents(lambda v: state.update("agents", v))
snd = sounds_mod.Sounds(lambda: bool(cfg.get("sounds", False)), lambda: cfg.get("sound_volume", 0.45))
live = activities_mod.Activities(lambda v: state.update("activities", v),
                                 play_sound=lambda: snd.play("timer", force=True))
spectrum = spectrum_mod.Spectrum()
palette = palette_mod.Palette(copy=lambda text: clip.copy_text(text[:2000]) if clip else None)
ui = config.load_ui()


# --------------------------------------------------------------------------
# Komutlar
# --------------------------------------------------------------------------
def set_dnd(on):
    """Odak sayacı için: Rahatsız Etme'yi ayarla, önceki değeri döndür."""
    prev = ui["dnd"]
    if prev != on:
        ui["dnd"] = on
        ui["focusDnd"] = on
        config.save_ui(ui)
        state.update("ui", dict(ui))
    return prev


def execute(cmd, arg):
    if cmd == "play_pause":
        mpris.call("PlayPause")
    elif cmd == "next":
        mpris.call("Next")
    elif cmd == "prev":
        mpris.call("Previous")
    elif cmd == "seek":
        mpris.seek_to(float(arg))
    elif cmd == "vol_set":
        v = max(0, min(100, float(arg)))
        bg(lambda: run("wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", f"{v / 100:.2f}"))
    elif cmd == "vol_delta":
        d = int(float(arg))
        bg(lambda: run("wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@",
                       f"{abs(d)}%{'+' if d > 0 else '-'}"))
    elif cmd == "vol_mute":
        bg(lambda: run("wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"))
    elif cmd in ("toggle_hide", "hide", "show"):
        ui["hidden"] = (not ui["hidden"]) if cmd == "toggle_hide" else cmd == "hide"
        config.save_ui(ui)
        state.update("ui", dict(ui))
    elif cmd == "set_language" and isinstance(arg, str) and re.fullmatch(r"auto|[a-z]{2}", arg):
        set_language(arg)
    elif cmd == "set_layout" and isinstance(arg, dict):
        # Kısmi güncelleme: yalnızca gönderilen alanlar değişir
        set_layout(arg)
    elif cmd == "setting" and isinstance(arg, dict):
        apply_switch(str(arg.get("key", "")), bool(arg.get("value")))
    elif cmd == "phone_ring" and phone:
        bg(lambda: phone.ring(str(arg)))
    elif cmd == "claude_hooks":
        bg(lambda: set_claude_hooks(bool(arg)))
    elif cmd == "quicklook" and isinstance(arg, str) and (arg == "" or preview_mod.is_previewable_path(arg)):
        # boş yol: açık önizlemeyi kapat
        state.update("quickReq", {"seq": state.data["quickReq"]["seq"] + 1, "path": arg})
    elif cmd == "shot_open" and shot_watch and shot_watch.last:
        subprocess.Popen(["xdg-open", shot_watch.last], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    elif cmd == "shot_copy" and shot_watch and shot_watch.last and clip:
        bg(lambda: clip.copy_image(shot_watch.last))
    elif cmd == "sound" and isinstance(arg, str):
        snd.play(arg)
    elif cmd == "activity_end":
        live.end(str(arg), "cancelled")
    elif cmd == "agent_answer" and isinstance(arg, dict):
        agents.answer(int(arg.get("id", 0)), str(arg.get("answer", "")))
    elif cmd == "lyrics_want" and lyrics:
        lyrics.set_want(bool(arg) and cfg.get("lyrics", True))
    elif cmd == "lyrics_search" and lyrics and isinstance(arg, str):
        lyrics.manual(arg)            # elle yazılan arama (bulunamayan / yanlış çıkan şarkılar için)
    elif cmd.startswith("focus_") and focus_timer:
        if cmd == "focus_toggle":
            focus_timer.toggle()
        elif cmd == "focus_reset":
            focus_timer.reset()
        elif cmd == "focus_skip":
            focus_timer.skip()
        elif cmd == "focus_set" and isinstance(arg, dict):
            focus_timer.set_lengths(arg.get("work"), arg.get("brk"))
    elif cmd == "toggle_dnd":
        ui["dnd"] = not ui["dnd"]
        ui["focusDnd"] = False
        config.save_ui(ui)
        state.update("ui", dict(ui))
    elif cmd == "wifi_toggle":
        bg(lambda: (controls.set_wifi(not state.data["controls"]["wifiOn"]), refresh_controls()))
    elif cmd == "bt_toggle":
        bg(lambda: (controls.set_bt(not state.data["controls"]["bt"]["on"]), refresh_controls()))
    elif cmd == "profile_cycle" and power:
        power.cycle()
    elif cmd == "night_toggle" and night:
        bg(night.toggle)
    elif cmd == "brightness_set" and brightness and isinstance(arg, dict):
        global last_br_cmd
        last_br_cmd = time.time()
        d, pct = str(arg.get("id", "")), arg.get("pct", 0)
        bg(lambda: brightness.set_percent(d, pct))
    elif cmd == "open_settings":
        controls.open_settings(str(arg))
    elif cmd == "raise":
        mpris.raise_player()
    elif cmd == "open_url":
        urls = {e.get("url") for e in state.data["calendar"]["events"]}
        if arg in urls and str(arg).startswith(("http://", "https://")):
            subprocess.Popen(["xdg-open", str(arg)], stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=True)
    elif cmd == "open_tab" and isinstance(arg, dict):
        # Paneli belirli bir sekmede aç (betikler / kısayollar için): {"tab": 0-8, "lyrics": bool, "sub": Araçlar bölümü 0-3}
        req = {"seq": state.data["tabReq"]["seq"] + 1, "tab": int(arg.get("tab", 0))}
        if "lyrics" in arg:
            req["lyrics"] = bool(arg["lyrics"])
        if "sub" in arg:
            req["sub"] = int(arg["sub"])
        state.update("tabReq", req)
    elif cmd == "palette":
        # arg: isteğe bağlı başlangıç araması (island palette "5m çay")
        state.update("paletteReq", {"seq": state.data["paletteReq"]["seq"] + 1,
                                    "q": str(arg)[:120] if isinstance(arg, str) else ""})
    elif cmd == "palette_run" and isinstance(arg, dict):
        bg(lambda: palette.run(arg))
    elif cmd == "timer_start" and isinstance(arg, dict):
        try:
            live.set({"title": str(arg.get("title", "")) or _("Zamanlayıcı"), "icon": "timer",
                      "duration": str(arg.get("duration", ""))})
        except ValueError:
            pass
    elif cmd == "web_search" and isinstance(arg, str) and arg.strip():
        url = "https://duckduckgo.com/?q=" + quote_plus(arg.strip()[:200])
        subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    elif cmd == "toggle_panel":
        state.update("panelReq", state.data["panelReq"] + 1)
    elif cmd == "stats_on" and stats:
        stats.enable()
    elif cmd == "audio_set":
        bg(lambda: (audio.set_default(str(arg), state.data["audio"]["sinks"]), refresh_audio()))
    elif cmd == "note_add" and store:
        store.add_note(arg)
    elif cmd == "note_toggle" and store:
        store.toggle_note(int(arg))
    elif cmd == "note_del" and store:
        store.delete_note(int(arg))
    elif cmd == "note_clear_done" and store:
        store.clear_done()
    elif cmd == "doc_new" and store:
        state.update("docNew", {"seq": state.data["docNew"]["seq"] + 1, "id": store.add_doc()})
    elif cmd == "doc_set" and store and isinstance(arg, dict):
        store.set_doc(int(arg.get("id", 0)), arg.get("text", ""))
    elif cmd == "doc_title" and store and isinstance(arg, dict):
        store.set_doc_title(int(arg.get("id", 0)), arg.get("title", ""))
    elif cmd == "doc_del" and store:
        store.delete_doc(int(arg))
    elif cmd == "shelf_add" and store:
        store.add_files(arg if isinstance(arg, list) else [arg])
    elif cmd == "shelf_del" and store:
        store.remove_file(int(arg))
    elif cmd == "shelf_clear" and store:
        store.clear_shelf()
    elif cmd == "shelf_open" and store:
        store.open_file(int(arg))
    elif cmd == "clip_copy" and clip:
        clip.copy(int(arg))
    elif cmd == "copy_text" and clip:
        clip.copy_text(str(arg)[:200])
    elif cmd == "clip_del" and clip:
        clip.delete(int(arg))
    elif cmd == "clip_pin" and clip:
        clip.pin(int(arg))
    elif cmd == "clip_clear" and clip:
        clip.clear()
    elif cmd == "rec_toggle" and recorder:
        recorder.toggle()
    elif cmd == "open_recording":
        last = state.data["rec"].get("last", "")
        if last and os.path.exists(last):
            subprocess.Popen(["xdg-open", os.path.dirname(last)], stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=True)
    elif cmd == "notif_open" and notifs:
        notifs.open(int(arg))
    elif cmd == "notif_dismiss" and notifs:
        notifs.dismiss(int(arg))
    elif cmd == "notif_clear" and notifs:
        notifs.clear()
    elif cmd == "apps_refresh":
        bg(lambda: state.update("apps", apps.running()))
    elif cmd == "launch":
        apps.launch(str(arg), state.data["apps"])
    elif cmd == "app_close":
        apps.close(str(arg), state.data["apps"])
        bg(lambda: (time.sleep(1.5), state.update("apps", apps.running())))
    elif cmd == "cal_add" and isinstance(arg, dict):
        bg(lambda: cal_add(arg))
    elif cmd == "cal_refresh":
        bg(refresh_calendar)
    elif cmd == "open_config":
        config.load()  # dosya yoksa oluştur
        subprocess.Popen(["xdg-open", config.PATH], stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    elif cmd == "screenshot":
        subprocess.Popen(["spectacle", "-r"], stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    elif cmd == "lock":
        bg(lambda: run("loginctl", "lock-session"))
    elif cmd == "suspend":
        bg(lambda: run("systemctl", "suspend"))
    elif cmd == "reboot":
        bg(lambda: run("systemctl", "reboot"))
    elif cmd == "poweroff":
        bg(lambda: run("systemctl", "poweroff"))
    return False  # idle_add tekrarlanmasın


# --------------------------------------------------------------------------
# HTTP
# --------------------------------------------------------------------------
class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    timeout = 15              # yarım kalan istekler iş parçacığı tutmasın
    MAX_BODY = 64 * 1024

    def log_message(self, *_):
        pass

    def host_ok(self):
        # DNS rebinding'e karşı Host + yerel süreçlere karşı belirteç (X-Island)
        return (self.headers.get("Host", "").split(":")[0] in ("127.0.0.1", "localhost")
                and hmac.compare_digest(self.headers.get("X-Island", "").encode(), TOKEN.encode()))

    def body(self):
        n = int(self.headers.get("Content-Length", 0))
        if not 0 <= n <= self.MAX_BODY:
            raise ValueError("gövde çok büyük")
        return json.loads(self.rfile.read(n) or b"{}")

    def reply(self, code, body=b"", ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        if code >= 400:
            self.close_connection = True
            self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if not self.host_ok():
            return self.reply(403)
        u = urlparse(self.path)
        if u.path == "/spectrum":
            # Müzik çubukları ~30 kez/sn sorar; yalnızca son bant değerleri (ayrı, hafif uç)
            levels = spectrum.levels() if cfg.get("spectrum", True) and spectrum.available else []
            return self.reply(200, json.dumps({"b": levels}, separators=(",", ":")).encode())
        if u.path == "/preview":
            # Hızlı Bakış: dosya bilgisi + küçük resim (PDF/video/ses için üretilir, önbelleğe alınır)
            path = parse_qs(u.query).get("path", [""])[0]
            if not preview_mod.is_previewable_path(path):
                return self.reply(404, json.dumps({"error": "missing"}).encode())
            return self.reply(200, json.dumps(preview_mod.info(path)).encode())
        if u.path == "/search":
            # Komut paleti: uygulamalar + dosyalar (hesap makinesi, komutlar arayüzde)
            qs = parse_qs(u.query)
            q, part = qs.get("q", [""])[0], qs.get("part", ["all"])[0]
            return self.reply(200, json.dumps({"q": q, "part": part,
                                               "r": palette.search(q, part if part in ("fast", "slow") else "all")}).encode())
        if u.path != "/state":
            return self.reply(404)
        try:
            since = int(parse_qs(u.query).get("v", ["0"])[0])
        except ValueError:
            return self.reply(400)
        version, changed = state.wait(since)
        self.reply(200, json.dumps({"v": version, "s": changed}).encode())

    def agent(self, what):
        """Claude Code hook'u (agent_hook.py) ile konuşma; ana döngüyü bekletmez."""
        try:
            msg = self.body()
            if what == "ask":
                out = {"id": agents.ask(msg)}
            elif what == "wait":
                out = {"answer": agents.wait(int(msg.get("id", 0)), msg.get("timeout", 2))}
            elif what == "cancel":
                agents.cancel(int(msg.get("id", 0)))
                out = {}
            elif what == "done":
                agents.done(msg)
                out = {}
            else:
                return self.reply(404)
            self.reply(200, json.dumps(out).encode())
        except Exception:
            self.reply(400)

    def activity(self):
        """Canlı Etkinlikler: island komutu ve betikler (bkz. activities.py)."""
        try:
            out = live.handle(self.body())
        except (ValueError, TypeError, AttributeError) as e:
            return self.reply(400, json.dumps({"error": str(e)}).encode())
        self.reply(200, json.dumps(out).encode())

    def do_POST(self):
        # Tarayıcılardan gelen CSRF'i engelle: özel başlık ön-kontrol (preflight)
        # gerektirir ve biz buna yanıt vermiyoruz.
        if not self.host_ok():
            return self.reply(403)
        if self.path.startswith("/agent/"):
            return self.agent(self.path[len("/agent/"):])
        if self.path == "/activity":
            return self.activity()
        if self.path != "/cmd":
            return self.reply(404)
        try:
            msg = self.body()
            GLib.idle_add(execute, str(msg.get("cmd", "")), msg.get("arg"))
            self.reply(200, b"{}")
        except Exception:
            self.reply(400)


def main():
    global mpris, notifs
    mpris = Mpris()
    try:
        notifs = Notifications(state, cfg.get("ignore_apps", []),
                               cfg.get("suppress_plasma_popups", True))
    except Exception as e:
        print("bildirim dinleyici başlatılamadı:", e, flush=True)
    if notifs:
        notifs.otp = bool(cfg.get("otp_capture", True))
    refresh_volume()
    if ui.get("focusDnd"):   # önceki çalışmada odak sayacı açık kalmıştı
        ui["dnd"] = ui["focusDnd"] = False
        config.save_ui(ui)
    state.update("ui", dict(ui))
    global brightness, power, night, fs_watch, shot_watch
    try:
        brightness = controls.Brightness(on_brightness)
    except Exception as e:
        print("parlaklık denetimi yok:", e, flush=True)
    try:
        power = controls.PowerProfiles(lambda v: state.update("power", v))
    except Exception as e:
        print("güç profili denetimi yok:", e, flush=True)
    try:
        night = controls.NightLight(lambda v: state.update("night", v))
    except Exception as e:
        print("Gece Işığı denetimi yok:", e, flush=True)
    refresh_audio()
    global store, stats, clip, recorder, focus_timer, lyrics, weather
    lyrics = lyrics_mod.Lyrics(lambda v: state.update("lyrics", v))
    privacy.Privacy(lambda v: state.update("privacy", v))
    weather = weather_mod.Weather(
        lambda v: state.update("weather", v),
        lambda: {**cfg.get("weather", {}), "enabled": cfg.get("weather_enabled", True)})
    if cfg.get("phone", True):
        set_phone(True)
    Alerts(emit_alert)
    publish_settings()
    fc = cfg.get("focus", {})
    focus_timer = focus.Focus(lambda v: state.update("focus", v), set_dnd,
                              fc.get("work", 25), fc.get("break", 5))
    store = Store(lambda v: state.update("notes", v), lambda v: state.update("shelf", v),
                  lambda v: state.update("docs", v))
    stats = sysinfo.Stats(lambda v: state.update("stats", v))
    recorder = Recorder(lambda v: state.update("rec", v))
    if cfg.get("clipboard_history", True):
        clip = Clipboard(lambda v: state.update("clip", v))
        state.update("clipOn", clip.start())
    try:
        fs_watch = Fullscreen(
            lambda b: state.update("fullscreen", b and cfg.get("hide_in_fullscreen", True)),
            lambda c: GLib.idle_add(execute, c, None),
            {**config.DEFAULTS["shortcuts"], **cfg.get("shortcuts", {})},   # yeni kısayollar eski ayarlara da gelsin
        )
        fs_watch.load()
    except Exception as e:
        print("KWin köprüsü yok:", e, flush=True)
    try:
        shot_watch = shots_mod.Shots(lambda v: state.update("shot", v), extra=cfg.get("screenshot_dirs", []))
    except Exception as e:
        print("ekran görüntüsü izleyicisi başlatılamadı:", e, flush=True)
    threading.Thread(target=volume_watcher, daemon=True).start()
    threading.Thread(target=slow_poller, daemon=True).start()

    class QuietServer(ThreadingHTTPServer):
        daemon_threads = True
        allow_reuse_address = True

        def handle_error(self, request, client_address):
            if not isinstance(sys.exc_info()[1], (BrokenPipeError, ConnectionResetError)):
                super().handle_error(request, client_address)

    server = QuietServer(("127.0.0.1", PORT), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()

    loop = GLib.MainLoop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        _signal_add(GLib.PRIORITY_HIGH, sig, loop.quit)  # temiz kapanış
    try:
        loop.run()
    finally:
        if fs_watch:
            fs_watch.unload()


if __name__ == "__main__":
    main()
