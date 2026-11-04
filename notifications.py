"""Bildirimler.

İki çalışma modu (açılışta otomatik seçilir):
  * sunucu  — org.freedesktop.Notifications adını kimse tutmuyorsa (ör. panelde sistem
              tepsisi yoksa) ada bu servisi kendisi sunar; böylece uygulamalar bildirim
              gönderebilir ve hepsi adada görünür.
  * izleme  — ad başka bir süreçteyse (Plasma vb.) servisin yerine geçmez, D-Bus
              monitörüyle Notify çağrılarını izler. İstenirse Inhibit ile Plasma'nın kendi
              açılır pencereleri bastırılır; bu engel arka uç kapanınca kalkar.
"""
import html
import os
import re
import time

import apps
import otp
import dbus
import dbus.bus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop

IFACE = "org.freedesktop.Notifications"
PATH = "/org/freedesktop/Notifications"
MAX_ITEMS = 30

DBusGMainLoop(set_as_default=True)


def _clean(text, limit):
    text = html.unescape(re.sub(r"<[^>]+>", "", str(text))).strip()
    return text if len(text) <= limit else text[: limit - 1] + "…"


def _icon(app_icon, hints):
    icon = str(app_icon or "")
    if not icon:
        icon = str(hints.get("image-path", "") or hints.get("desktop-entry", ""))
    if icon.startswith("/"):
        icon = "file://" + icon
    return icon or "notifications"


class _Server(dbus.service.Object):
    """org.freedesktop.Notifications uygulaması (yalnızca sunucu modunda)."""

    def __init__(self, bus, owner):
        super().__init__(bus, PATH)
        self.owner = owner
        self.next_id = 1

    @dbus.service.method(IFACE, in_signature="", out_signature="as")
    def GetCapabilities(self):
        return ["actions", "body", "icon-static", "persistence"]

    @dbus.service.method(IFACE, in_signature="susssasa{sv}i", out_signature="u")
    def Notify(self, app, replaces, icon, summary, body, actions, hints, timeout):
        nid = int(replaces) or self.next_id
        if not replaces:
            self.next_id += 1
        entry = self.owner._add(app, int(replaces), icon, summary, body, hints, nid)
        if entry is not None:
            # "default" eylemi: bildirime tıklanınca uygulama ilgili sohbeti/e-postayı açar
            entry["default"] = "default" in [str(a) for a in actions[::2]]
        return nid if entry is not None else 0

    @dbus.service.method(IFACE, in_signature="u", out_signature="")
    def CloseNotification(self, nid):
        self.owner.items = [i for i in self.owner.items if i.get("nid") != int(nid)]
        self.owner._publish()
        self.NotificationClosed(nid, 3)

    @dbus.service.method(IFACE, in_signature="", out_signature="ssss")
    def GetServerInformation(self):
        return ("Dynamic Island", "dynamic-island", "1.0", "1.2")

    @dbus.service.signal(IFACE, signature="uu")
    def NotificationClosed(self, nid, reason):
        pass

    @dbus.service.signal(IFACE, signature="us")
    def ActionInvoked(self, nid, action):
        pass


class Notifications:
    def __init__(self, state, ignore_apps=(), suppress_popups=True):
        self.state = state
        self.ignore = set(ignore_apps)
        self.suppress = suppress_popups
        self.otp = True      # doğrulama kodlarını bildirimden ayıkla (ayarlardan kapatılabilir)
        self.items = []     # en yeni başta
        self.pending = {}   # Notify çağrı serial'i -> kayıt (izleme modunda yanıttaki id için)
        self.counter = 0
        self.seq = 0
        self.mode = ""
        self._server = None
        self._keep = []     # bağlantı/nesneleri canlı tut

        bus = dbus.SessionBus()
        try:
            name = dbus.service.BusName(IFACE, bus, allow_replacement=True,
                                        replace_existing=False, do_not_queue=True)
            self._server = _Server(bus, self)
            self._keep += [name, self._server]
            self.mode = "server"
            # Sonradan başka bir servis adı devralırsa izleme moduna geç
            bus.add_signal_receiver(self._owner_changed, "NameOwnerChanged",
                                    "org.freedesktop.DBus", arg0=IFACE)
            self._bus = bus
        except dbus.exceptions.NameExistsException:
            self._start_monitor()
        self._publish()
        print(f"bildirimler: {self.mode} modu", flush=True)

    # -- sunucu modundan izleme moduna geçiş
    def _owner_changed(self, name, _old, new):
        if new and new != self._bus.get_unique_name() and self.mode == "server":
            self._keep.clear()
            self._start_monitor()
            print("bildirimler: izleme moduna geçildi", flush=True)

    # -- izleme modu
    def _start_monitor(self):
        self.mode = "monitor"
        conn = dbus.bus.BusConnection(os.environ["DBUS_SESSION_BUS_ADDRESS"])
        conn.call_blocking(
            "org.freedesktop.DBus", "/org/freedesktop/DBus",
            "org.freedesktop.DBus.Monitoring", "BecomeMonitor", "asu",
            ([
                f"type='method_call',interface='{IFACE}',member='Notify'",
                f"type='method_call',interface='{IFACE}',member='CloseNotification'",
                f"type='method_return',sender='{IFACE}'",
            ], 0),
        )
        conn.add_message_filter(self._on_message)
        self._keep.append(conn)

        if self.suppress:
            try:
                bus = dbus.SessionBus()
                proxy = bus.get_object(IFACE, PATH)
                dbus.Interface(proxy, IFACE).Inhibit(
                    "dynamic-island", "Bildirimler adada gösteriliyor",
                    dbus.Dictionary({}, signature="sv"),
                )
                self._keep.append(bus)  # bağlantı açık kaldıkça engel sürer
            except Exception as e:
                print("Plasma bildirimleri bastırılamadı:", e, flush=True)

    def _on_message(self, _conn, msg):
        try:
            mtype = msg.__class__.__name__
            if mtype == "MethodCallMessage":
                member = msg.get_member()
                if member == "Notify":
                    app, replaces, icon, summary, body, _a, hints, _t = msg.get_args_list()
                    entry = self._add(app, int(replaces), icon, summary, body, hints, None)
                    if entry is not None:
                        self.pending[msg.get_serial()] = entry
                        if len(self.pending) > 50:
                            self.pending.pop(next(iter(self.pending)))
                elif member == "CloseNotification":
                    nid = int(msg.get_args_list()[0])
                    self.items = [i for i in self.items if i.get("nid") != nid]
                    self._publish()
            elif mtype == "MethodReturnMessage":
                entry = self.pending.pop(msg.get_reply_serial(), None)
                args = msg.get_args_list()
                if entry is not None and args:
                    entry["nid"] = int(args[0])
        except Exception as e:
            print("bildirim hatası:", e, flush=True)

    # -- ortak
    def _add(self, app, replaces, app_icon, summary, body, hints, nid):
        app = str(app)
        if app in self.ignore or not (str(summary) or str(body)):
            return None
        entry = None
        if replaces:
            for i in self.items:
                if i.get("nid") == replaces:
                    entry = i
                    self.items.remove(i)
                    break
        if entry is None:
            self.counter += 1
            entry = {"id": self.counter}
        if nid is not None:
            entry["nid"] = nid
        entry.update({
            "app": _clean(hints.get("x-kde-display-appname", app) or app, 40),
            "icon": _icon(app_icon, hints),
            "title": _clean(summary, 120),
            "body": _clean(body, 280),
            "ts": int(time.time() * 1000),
            "desktop": str(hints.get("desktop-entry", "")) or apps.guess(app, app_icon),
            "code": otp.extract(summary, body) if self.otp else "",
        })
        self.items.insert(0, entry)
        del self.items[MAX_ITEMS:]
        self.seq += 1
        self._publish()
        return entry

    # -- komutlar
    def dismiss(self, item_id):
        self.items = [i for i in self.items if i["id"] != item_id]
        self._publish()

    def open(self, item_id):
        """Bildirime tıklandı: uygulamanın "default" eylemi varsa onu tetikle (ilgili sohbet,
        e-posta, sekme açılır); yoksa kaynak uygulamayı başlat/öne getir. Sonra bildirimi kaldır."""
        for i in self.items:
            if i["id"] == item_id:
                nid = i.get("nid")
                if self._server is not None and nid and i.get("default"):
                    self._server.ActionInvoked(nid, "default")
                    self._server.NotificationClosed(nid, 2)   # 2: kullanıcı kapattı
                else:
                    apps.launch_desktop(i.get("desktop", ""))
                break
        self.dismiss(item_id)

    def clear(self):
        self.items = []
        self._publish()

    def _publish(self):
        shown = [{k: v for k, v in i.items() if k != "nid"} for i in self.items]
        self.state.update("notifs", {"seq": self.seq, "items": shown})
