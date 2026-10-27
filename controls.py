"""Hızlı ayarlar: Wi-Fi, Bluetooth, güç profili, parlaklık, Gece Işığı.

Güç profili, parlaklık ve Gece Işığı D-Bus sinyalleriyle olay tabanlı izlenir
(süreç başlatılmaz). Wi-Fi ve Bluetooth yavaş döngüde okunur.
"""
import os
import subprocess
import threading
import time

from gi.repository import Gio, GLib

ENV = {**os.environ, "LC_ALL": "C"}
PROPS = "org.freedesktop.DBus.Properties"

# Ayar sayfaları: yalnızca bu listedekiler açılabilir
SETTINGS_PAGES = {
    "network": "kcm_networkmanagement",
    "bluetooth": "kcm_bluetooth",
    "power": "kcm_powerdevilprofilesconfig",
    "notifications": "kcm_notifications",
    "nightlight": "kcm_nightlight",
}


def _run(*args, timeout=4):
    try:
        return subprocess.run(args, capture_output=True, text=True,
                              timeout=timeout, env=ENV).stdout
    except Exception:
        return ""


def open_settings(page):
    module = SETTINGS_PAGES.get(page)
    if module:
        subprocess.Popen(["kcmshell6", module], stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)


# -- Wi-Fi -------------------------------------------------------------------
def wifi_enabled():
    return _run("nmcli", "radio", "wifi").strip() == "enabled"


def set_wifi(on):
    _run("nmcli", "radio", "wifi", "on" if on else "off")


# -- Bluetooth ---------------------------------------------------------------
def bt_state():
    out = _run("rfkill", "list", "bluetooth")
    if not out.strip():
        return {"present": False, "on": False, "device": ""}
    if "Soft blocked: yes" in out:
        return {"present": True, "on": False, "device": ""}
    powered = "Powered: yes" in _run("bluetoothctl", "show")
    device = ""
    if powered:
        for line in _run("bluetoothctl", "devices", "Connected").splitlines():
            parts = line.split(" ", 2)
            if len(parts) == 3:
                device = parts[2]
                break
    return {"present": True, "on": powered, "device": device}


def set_bt(on):
    if on:
        _run("rfkill", "unblock", "bluetooth")
        time.sleep(0.4)
        _run("bluetoothctl", "power", "on")
    else:
        _run("bluetoothctl", "power", "off")


# -- D-Bus yardımcıları ----------------------------------------------------------------
class _DBusProps:
    """Bir D-Bus nesnesinin özelliklerini okur ve değişimini sinyalle bildirir."""

    def __init__(self, bus, name, path, iface, on_change):
        self.bus, self.name, self.path, self.iface = bus, name, path, iface
        self.on_change = on_change
        self.props = {}
        bus.signal_subscribe(name, PROPS, "PropertiesChanged", path, iface,
                             Gio.DBusSignalFlags.NONE, lambda *_: self.refresh())
        self.refresh(notify=False)

    def refresh(self, notify=True):
        try:
            self.props = self.bus.call_sync(
                self.name, self.path, PROPS, "GetAll", GLib.Variant("(s)", (self.iface,)),
                GLib.VariantType("(a{sv})"), Gio.DBusCallFlags.NONE, 500, None,
            ).unpack()[0]
        except Exception:
            self.props = {}
        if notify:
            self.on_change()

    def set(self, prop, variant):
        self.bus.call(
            self.name, self.path, PROPS, "Set",
            GLib.Variant("(ssv)", (self.iface, prop, variant)),
            None, Gio.DBusCallFlags.NONE, 1000, None, None,
        )


# -- Güç profili (power-profiles-daemon) -----------------------------------------------
class PowerProfiles:
    NAME = "org.freedesktop.UPower.PowerProfiles"
    PATH = "/org/freedesktop/UPower/PowerProfiles"
    ORDER = ["power-saver", "balanced", "performance"]

    def __init__(self, on_change):
        bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        self._cb = on_change
        self.obj = _DBusProps(bus, self.NAME, self.PATH, self.NAME, self._changed)
        self._changed()

    def _changed(self):
        self._cb(self.value())

    def profiles(self):
        names = [p.get("Profile") for p in self.obj.props.get("Profiles", [])]
        return [p for p in self.ORDER if p in names]

    def value(self):
        return {"profile": self.obj.props.get("ActiveProfile", ""), "profiles": self.profiles()}

    def cycle(self):
        avail, cur = self.profiles(), self.obj.props.get("ActiveProfile", "")
        if not avail:
            return
        nxt = avail[(avail.index(cur) + 1) % len(avail)] if cur in avail else avail[0]
        self.obj.set("ActiveProfile", GLib.Variant("s", nxt))


# -- Gece Işığı (KWin) -----------------------------------------------------------------
class NightLight:
    NAME = "org.kde.KWin"
    PATH = "/org/kde/KWin/NightLight"
    IFACE = "org.kde.KWin.NightLight"

    def __init__(self, on_change):
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self._cb = on_change
        self.cookie = None  # bizim duraklatma çerezimiz (bağlantı kapanınca kendiliğinden kalkar)
        self._lock = threading.Lock()  # hızlı çift tıkta istekler sırayla işlensin
        self.obj = _DBusProps(self.bus, self.NAME, self.PATH, self.IFACE, self._changed)
        self._changed()

    def _changed(self):
        self._cb(self.value())

    def value(self):
        p = self.obj.props
        return {
            "available": bool(p.get("available", False)),
            "enabled": bool(p.get("enabled", False)),
            "running": bool(p.get("running", False)),
            "inhibited": bool(p.get("inhibited", False)),
            "mine": self.cookie is not None,
            "temp": int(p.get("currentTemperature", 0)),
        }

    def toggle(self):
        with self._lock:
            self._toggle()

    def _toggle(self):
        self.obj.refresh(notify=False)   # güncel durumu oku (önbellek eski olabilir)
        v = self.value()
        if not v["available"]:
            return
        if not v["enabled"]:
            # Kapalıysa ayarda etkinleştir
            _run("kwriteconfig6", "--file", "kwinrc", "--group", "NightColor", "--key", "Active", "true")
            _run("qdbus6", "org.kde.KWin", "/KWin", "reconfigure")
        elif self.cookie is not None:
            self._call("uninhibit", GLib.Variant("(u)", (self.cookie,)))
            self.cookie = None
        elif not v["inhibited"]:
            res = self._call("inhibit", None, GLib.VariantType("(u)"))
            if res:
                self.cookie = res[0]
        self.obj.refresh()

    def _call(self, method, params=None, reply=None):
        try:
            res = self.bus.call_sync(self.NAME, self.PATH, self.IFACE, method, params, reply,
                                     Gio.DBusCallFlags.NONE, 800, None)
            return res.unpack() if reply else True
        except Exception:
            return None


# -- Parlaklık (PowerDevil ScreenBrightness, ekran başına; olay tabanlı) -----------
SB_NAME = "org.kde.ScreenBrightness"
SB_ROOT = "/org/kde/ScreenBrightness"
SB_IFACE = "org.kde.ScreenBrightness"
SB_DISPLAY = "org.kde.ScreenBrightness.Display"
PROPS_IFACE = "org.freedesktop.DBus.Properties"


class Brightness:
    """Her ekran (yerleşik panel, DDC/CI'lı monitör) ayrı ayrı okunur ve ayarlanır."""

    def __init__(self, on_change):
        self.on_change = on_change  # on_change(displays: list[dict])
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.displays = {}  # id -> {"id", "label", "internal", "max", "raw"}
        for sig in ("BrightnessChanged", "BrightnessRangeChanged", "DisplayAdded", "DisplayRemoved"):
            self.bus.signal_subscribe(
                SB_NAME, SB_IFACE, sig, SB_ROOT, None,
                Gio.DBusSignalFlags.NONE, lambda *_: GLib.idle_add(self.refresh),
            )
        self.refresh()

    def _prop(self, path, name):
        try:
            return self.bus.call_sync(
                SB_NAME, path, PROPS_IFACE, "Get",
                GLib.Variant("(ss)", (SB_DISPLAY, name)), GLib.VariantType("(v)"),
                Gio.DBusCallFlags.NONE, 800, None,
            )[0]
        except Exception:
            return None

    def refresh(self):
        try:
            names = self.bus.call_sync(
                SB_NAME, SB_ROOT, PROPS_IFACE, "Get",
                GLib.Variant("(ss)", (SB_IFACE, "DisplaysDBusNames")), GLib.VariantType("(v)"),
                Gio.DBusCallFlags.NONE, 800, None,
            )[0]
        except Exception:
            names = []
        found = {}
        for n in names:
            path = f"{SB_ROOT}/{n}"
            mx, raw = self._prop(path, "MaxBrightness"), self._prop(path, "Brightness")
            if not mx or raw is None:
                continue
            found[n] = {
                "id": n,
                "label": self._prop(path, "Label") or n,
                "internal": bool(self._prop(path, "IsInternal")),
                "max": mx,
                "raw": raw,
            }
        self.displays = found
        self.on_change(self.snapshot())
        return False

    def snapshot(self):
        # yerleşik ekran önce, sonra ada göre
        items = sorted(self.displays.values(), key=lambda d: (not d["internal"], d["label"]))
        return [
            {"id": d["id"], "label": d["label"], "internal": d["internal"],
             "percent": round(d["raw"] * 100 / d["max"])}
            for d in items
        ]

    def set_percent(self, display_id, pct):
        d = self.displays.get(display_id)
        if not d:
            return
        raw = max(1, int(d["max"] * max(1, min(100, float(pct))) / 100))  # 0'a inip ekranı kapatma
        d["raw"] = raw
        self.bus.call(
            SB_NAME, f"{SB_ROOT}/{display_id}", SB_DISPLAY, "SetBrightness",
            GLib.Variant("(iu)", (raw, 0)), None, Gio.DBusCallFlags.NONE, 3000, None, None,
        )
