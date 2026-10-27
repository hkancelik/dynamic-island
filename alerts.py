"""Sistem uyarıları: Caps Lock, Bluetooth cihazı bağlandı/ayrıldı (pil yüzdesiyle).

Her uyarı emit(dict) ile yayınlanır; arayüz "seq" değişince kısa görünüm açar.
İnternet kesildi/bağlandı uyarısı backend'in ağ yoklamasından gelir.
"""
import glob
import threading
import time

from gi.repository import Gio, GLib

BLUEZ = "org.bluez"


class Alerts:
    def __init__(self, emit):
        self._emit = emit
        threading.Thread(target=self._caps_loop, daemon=True).start()
        try:
            self._bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
            self._bus.signal_subscribe(
                BLUEZ, "org.freedesktop.DBus.Properties", "PropertiesChanged", None,
                "org.bluez.Device1", Gio.DBusSignalFlags.NONE, self._on_bt)
        except Exception as e:
            print("Bluetooth uyarıları yok:", e, flush=True)

    # -- Caps Lock: klavye LED'i (Wayland'de en ucuz, izinsiz yol) -----------------
    def _caps_loop(self):
        last = None
        while True:
            on = False
            for p in glob.glob("/sys/class/leds/*::capslock/brightness"):
                try:
                    with open(p) as f:
                        on = on or f.read().strip() not in ("", "0")
                except OSError:
                    pass
            if last is not None and on != last:
                self._emit({"kind": "caps", "on": on})
            last = on
            time.sleep(0.2)

    # -- Bluetooth ---------------------------------------------------------------------
    def _prop(self, path, iface, name):
        try:
            v = self._bus.call_sync(BLUEZ, path, "org.freedesktop.DBus.Properties", "Get",
                                    GLib.Variant("(ss)", (iface, name)), GLib.VariantType("(v)"),
                                    Gio.DBusCallFlags.NONE, 1500, None)
            return v.unpack()[0]
        except Exception:
            return None

    def _on_bt(self, _conn, _sender, path, _iface, _signal, params):
        iface, changed, _inv = params.unpack()
        if "Connected" not in changed:
            return
        connected = bool(changed["Connected"])
        name = self._prop(path, "org.bluez.Device1", "Alias") or "Bluetooth cihazı"
        icon = self._prop(path, "org.bluez.Device1", "Icon") or ""

        def report(battery):
            self._emit({"kind": "bt", "connected": connected, "name": name, "icon": icon,
                        "battery": -1 if battery is None else int(battery)})

        if not connected:
            report(None)
            return
        # Pil bilgisi bağlantıdan biraz sonra gelir
        def later():
            report(self._prop(path, "org.bluez.Battery1", "Percentage"))
            return False
        GLib.timeout_add(1500, later)
