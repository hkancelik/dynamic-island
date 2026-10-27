"""Ekran kaydı: ScreenCast portalı (PipeWire) + GStreamer, bitince ffmpeg ile mp4'e çevirir.

İlk kullanımda KDE'nin "ekranı paylaş" penceresi bir kez çıkar; seçim hatırlanır (restore_token),
sonraki kayıtlar sormadan başlar. Yalnızca görüntü kaydedilir (ses yok).
"""
import itertools
import os
import signal
import subprocess
import threading
import time

import dbus
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

DBusGMainLoop(set_as_default=True)

PORTAL = "org.freedesktop.portal.Desktop"
PORTAL_PATH = "/org/freedesktop/portal/desktop"
TOKEN_FILE = os.path.expanduser("~/.local/share/dynamic-island/portal_token")


def _videos_dir():
    try:
        d = subprocess.run(["xdg-user-dir", "VIDEOS"], capture_output=True, text=True,
                           timeout=2).stdout.strip()
    except Exception:
        d = ""
    return d if d and os.path.isdir(d) else os.path.expanduser("~")


class Recorder:
    def __init__(self, on_change):
        self.on_change = on_change
        self.state = "idle"       # idle | starting | recording | saving
        self.since = 0
        self.error = ""
        self.last = ""
        self.proc = None
        self.session = None
        self.ts_path = self.mp4_path = ""
        self._tok = itertools.count(1)
        self._publish()

    def _publish(self):
        self.on_change({"state": self.state, "since": self.since, "error": self.error, "last": self.last})

    def _set(self, **kw):
        for k, v in kw.items():
            setattr(self, k, v)
        self._publish()

    def toggle(self):
        if self.state == "idle":
            self.start()
        elif self.state == "starting":
            self.cancel()          # paylaşım penceresi açıkken tekrar basınca iptal
        elif self.state == "recording":
            self.stop()

    def cancel(self):
        self._close_session()
        self._set(state="idle", error="")

    # -- portal ----------------------------------------------------------------------
    def _request(self, call, handler):
        """Portal isteği: Response sinyali gelince handler(kod, sonuçlar) çağrılır."""
        bus = dbus.SessionBus()
        token = f"di{next(self._tok)}"
        sender = bus.get_unique_name()[1:].replace(".", "_")
        path = f"/org/freedesktop/portal/desktop/request/{sender}/{token}"
        match = []

        def on_response(code, results):
            match[0].remove()
            handler(int(code), results)

        match.append(bus.add_signal_receiver(on_response, "Response",
                                             "org.freedesktop.portal.Request", path=path))
        call(token)

    def start(self):
        self._set(state="starting", error="")
        try:
            bus = dbus.SessionBus()
            portal = dbus.Interface(bus.get_object(PORTAL, PORTAL_PATH), "org.freedesktop.portal.ScreenCast")
            self._portal, self._bus = portal, bus

            def create(token):
                portal.CreateSession({"handle_token": token, "session_handle_token": f"disess{next(self._tok)}"})

            self._request(create, self._on_session)
        except Exception as e:
            self._fail(f"Portal yok: {e}")

    def _fail(self, msg):
        print("ekran kaydı:", msg, flush=True)
        self._set(state="idle", error=str(msg)[:120])

    def _on_session(self, code, results):
        if self.state != "starting":
            return
        if code != 0:
            return self._fail("Oturum açılamadı")
        self.session = str(results["session_handle"])
        opts = {"types": dbus.UInt32(1), "multiple": False, "cursor_mode": dbus.UInt32(2),
                "persist_mode": dbus.UInt32(2)}
        try:
            with open(TOKEN_FILE) as f:
                opts["restore_token"] = f.read().strip()
        except OSError:
            pass

        def select(token):
            self._portal.SelectSources(dbus.ObjectPath(self.session), {"handle_token": token, **opts})

        self._request(select, self._on_selected)

    def _on_selected(self, code, results):
        if self.state != "starting":
            return
        if code != 0:
            return self._fail("Kaynak seçilemedi")

        def go(token):
            self._portal.Start(dbus.ObjectPath(self.session), "", {"handle_token": token})

        self._request(go, self._on_started)

    def _on_started(self, code, results):
        if self.state != "starting":
            return
        if code != 0:
            self._close_session()
            return self._fail("Paylaşım iptal edildi" if code == 1 else "Kayıt başlatılamadı")
        try:
            token = str(results.get("restore_token", ""))
            if token:
                os.makedirs(os.path.dirname(TOKEN_FILE), exist_ok=True)
                with open(TOKEN_FILE, "w") as f:
                    f.write(token)
            node = int(results["streams"][0][0])
            fd = self._portal.OpenPipeWireRemote(dbus.ObjectPath(self.session), {}).take()
        except Exception as e:
            self._close_session()
            return self._fail(f"Akış açılamadı: {e}")

        stamp = time.strftime("%Y%m%d-%H%M%S")
        out_dir = _videos_dir()
        self.mp4_path = os.path.join(out_dir, f"Ekran-Kaydi-{stamp}.mp4")
        self.ts_path = os.path.join(out_dir, f".Ekran-Kaydi-{stamp}.ts")
        cmd = ["gst-launch-1.0", "-e", "pipewiresrc", f"fd={fd}", f"path={node}", "do-timestamp=true",
               "!", "videoconvert", "!", "x264enc", "tune=zerolatency", "speed-preset=ultrafast",
               "bitrate=8000", "key-int-max=60", "!", "h264parse", "!", "mpegtsmux",
               "!", "filesink", f"location={self.ts_path}"]
        try:
            self.proc = subprocess.Popen(cmd, pass_fds=[fd], stdout=subprocess.DEVNULL,
                                         stderr=subprocess.DEVNULL, start_new_session=True)
        except OSError as e:
            os.close(fd)
            self._close_session()
            return self._fail(f"GStreamer başlamadı: {e}")
        os.close(fd)
        self._set(state="recording", since=int(time.time() * 1000))
        threading.Thread(target=self._watch, daemon=True).start()

    def _close_session(self):
        if self.session:
            try:
                dbus.Interface(self._bus.get_object(PORTAL, self.session),
                               "org.freedesktop.portal.Session").Close()
            except Exception:
                pass
            self.session = None

    # -- bitirme ---------------------------------------------------------------------
    def stop(self):
        if self.proc and self.proc.poll() is None:
            self._set(state="saving")
            self.proc.send_signal(signal.SIGINT)       # -e: EOS gönder, dosyayı kapat

    def _watch(self):
        """gst-launch bitince (durdurma ya da hata) mp4'e çevirir."""
        self.proc.wait()
        GLib.idle_add(self._close_session)
        ok = False
        if os.path.exists(self.ts_path) and os.path.getsize(self.ts_path) > 1024:
            self._set(state="saving")
            r = subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", self.ts_path,
                                "-c", "copy", "-movflags", "+faststart", self.mp4_path],
                               capture_output=True, timeout=300)
            ok = r.returncode == 0 and os.path.exists(self.mp4_path)
        try:
            os.remove(self.ts_path)
        except OSError:
            pass
        if ok:
            self._set(state="idle", last=self.mp4_path, error="")
        else:
            self._set(state="idle", error="Kayıt dosyası oluşturulamadı")
