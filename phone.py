"""Telefon (KDE Connect): pil durumu, gelen arama uyarısı, "telefonumu çaldır".

KDE Connect'in D-Bus API'sini kullanır (org.kde.kdeconnect). Telefondan gelen bildirimler
zaten Plasma bildirimi olarak adaya düşer; burada yalnızca bunlar eklenir.
Daemon kurulu değilse ya da eşleşmiş cihaz yoksa durum {"present": False} kalır.
"""
import threading
import time

from gi.repository import Gio, GLib

BUS = "org.kde.kdeconnect"
DAEMON = ("/modules/kdeconnect", "org.kde.kdeconnect.daemon")
DEV_IFACE = "org.kde.kdeconnect.device"
POLL = 15


class Phone:
    def __init__(self, publish, emit_alert):
        self._publish = publish
        self._alert = emit_alert
        self._bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self._lock = threading.Lock()
        self._last_call = ("", 0.0)
        # Arama: telephony eklentisi sinyali (tüm cihaz yollarını tek abonelikle dinle)
        self._bus.signal_subscribe(
            BUS, "org.kde.kdeconnect.device.telephony", "callReceived", None, None,
            Gio.DBusSignalFlags.NONE, self._on_call)
        threading.Thread(target=self._loop, daemon=True).start()

    # -- D-Bus yardımcıları ----------------------------------------------------------
    def _call(self, path, iface, method, params=None, reply="(v)", timeout=1500):
        v = self._bus.call_sync(BUS, path, iface, method, params,
                                GLib.VariantType(reply) if reply else None,
                                Gio.DBusCallFlags.NONE, timeout, None)
        return v.unpack() if v is not None else None

    def _prop(self, path, iface, name):
        return self._call(path, "org.freedesktop.DBus.Properties", "Get",
                          GLib.Variant("(ss)", (iface, name)))[0]

    # -- Durum ---------------------------------------------------------------------------
    def _snapshot(self):
        ids = self._call(DAEMON[0], DAEMON[1], "devices",
                         GLib.Variant("(bb)", (False, True)), "(as)")[0]   # eşleşmiş cihazlar
        devices = []
        for i in ids:
            path = f"/modules/kdeconnect/devices/{i}"
            try:
                d = {"id": i, "name": self._prop(path, DEV_IFACE, "name"),
                     "reachable": bool(self._prop(path, DEV_IFACE, "isReachable")),
                     "battery": -1, "charging": False}
                if d["reachable"]:
                    try:
                        b = path + "/battery"
                        d["battery"] = int(self._call(b, "org.kde.kdeconnect.device.battery", "charge",
                                                      None, "(i)")[0])
                        d["charging"] = bool(self._call(b, "org.kde.kdeconnect.device.battery",
                                                        "isCharging", None, "(b)")[0])
                    except Exception:
                        pass   # pil eklentisi kapalı
                devices.append(d)
            except Exception:
                continue
        return devices

    def _loop(self):
        while True:
            try:
                devs = self._snapshot()
            except Exception:   # daemon yok / kapalı
                devs = []
            # Öncelik: ulaşılabilir cihaz
            devs.sort(key=lambda d: not d["reachable"])
            self._publish({"present": bool(devs), "devices": devs})
            time.sleep(POLL)

    # -- Arama uyarısı -----------------------------------------------------------------
    def _on_call(self, _c, _s, path, _i, _sig, params):
        event, number, name = params.unpack()
        # KDE Connect aynı aramayı birkaç kez bildirebilir
        key = (event, time.time())
        if event != "ringing" or (key[0] == self._last_call[0] and key[1] - self._last_call[1] < 5):
            return
        self._last_call = key
        dev_id = path.split("/")[4] if path.count("/") >= 4 else ""
        self._alert({"kind": "call", "name": name or number or "Bilinmeyen numara",
                     "number": number if name else "", "device": dev_id})

    # -- Komutlar ----------------------------------------------------------------------
    def ring(self, dev_id):
        """Telefonu çaldır (Find My Phone eklentisi)."""
        path = f"/modules/kdeconnect/devices/{dev_id}/findmyphone"
        try:
            self._call(path, "org.kde.kdeconnect.device.findmyphone", "ring", None, None)
        except Exception as e:
            print("telefon çaldırılamadı:", e, flush=True)
