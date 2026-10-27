"""Pano geçmişi (Wayland ext-data-control).

Klipper/sistem tepsisi olmadan çalışır: KWin'in sunduğu ext_data_control_manager_v1
protokolüyle panodaki değişiklikleri izler. Geçmiş YALNIZCA bellekte tutulur (diske yazılmaz);
parola yöneticilerinin "gizli" işaretli girdileri hiç saklanmaz.
"""
import os
import select
import socket
import struct
import threading
import time

MAX_ITEMS = 40
MAX_CHARS = 5000
PREVIEW = 240
TEXT_MIMES = ["text/plain;charset=utf-8", "text/plain", "UTF8_STRING", "STRING", "TEXT"]
SECRET_MIME = "x-kde-passwordManagerHint"
MANAGERS = ("ext_data_control_manager_v1", "zwlr_data_control_manager_v1")


def _pstr(s):
    b = s.encode() + b"\0"
    return struct.pack("<I", len(b)) + b + b"\0" * ((4 - len(b) % 4) % 4)


def _rstr(body, off):
    n = struct.unpack_from("<I", body, off)[0]
    s = body[off + 4: off + 4 + max(0, n - 1)].decode(errors="replace")
    return s, off + 4 + ((n + 3) & ~3)


class Clipboard:
    def __init__(self, on_update):
        self.on_update = on_update
        self.items = []          # en yeni başta: {"id", "text"}
        self.counter = 0
        self.sock = None
        self.lock = threading.Lock()
        self.fds = []
        self.buf = b""
        self.offers = {}         # offer id -> [mime,...]
        self.sources = {}        # kaynak id -> metin (set_selection ile sunduklarımız)
        self.reading = set()     # okuması süren teklifler (bitene kadar yok edilmez)
        self.next_id = 6         # 1-6 kullanımda; yeni kimlikler ardışık olmalı (7, 8, ...)
        self.device = 0
        self.manager = 0
        self.ok = False

    # -- tel biçimi
    def _send(self, obj, op, payload=b"", fds=()):
        data = struct.pack("<II", obj, ((8 + len(payload)) << 16) | op) + payload
        with self.lock:
            if fds:
                socket.send_fds(self.sock, [data], list(fds))
            else:
                self.sock.sendall(data)

    def _events(self, timeout=None):
        """Bekleyen olayları döndürür: [(nesne, işlem kodu, gövde)]"""
        if timeout is not None and not select.select([self.sock], [], [], timeout)[0]:
            return []
        data, fds, _, _ = socket.recv_fds(self.sock, 65536, 8)
        if not data:
            raise ConnectionError("Wayland bağlantısı kapandı")
        self.fds += fds
        self.buf += data
        out = []
        while len(self.buf) >= 8:
            obj, w = struct.unpack("<II", self.buf[:8])
            size, op = w >> 16, w & 0xFFFF
            if len(self.buf) < size:
                break
            out.append((obj, op, self.buf[8:size]))
            self.buf = self.buf[size:]
        return out

    def _alloc(self):
        with self.lock:
            self.next_id += 1
            return self.next_id

    # -- başlatma
    def start(self):
        """Başarılıysa True; protokol yoksa False (çağıran taraf geçmişi kapalı sayar)."""
        try:
            path = os.path.join(os.environ["XDG_RUNTIME_DIR"], os.environ["WAYLAND_DISPLAY"])
            self.sock = socket.socket(socket.AF_UNIX)
            self.sock.connect(path)
            self._send(1, 1, struct.pack("<I", 2))   # get_registry -> 2
            self._send(1, 0, struct.pack("<I", 3))   # sync -> 3
            globs, done = {}, False
            while not done:
                for obj, op, body in self._events(timeout=3):
                    if obj == 2 and op == 0:
                        name = struct.unpack_from("<I", body, 0)[0]
                        iface, off = _rstr(body, 4)
                        globs[iface] = (name, struct.unpack_from("<I", body, off)[0])
                    elif obj == 3:
                        done = True
            mgr = next((m for m in MANAGERS if m in globs), None)
            if not mgr or "wl_seat" not in globs:
                return False
            seat_name, seat_ver = globs["wl_seat"]
            mgr_name, mgr_ver = globs[mgr]
            self._send(2, 0, struct.pack("<I", seat_name) + _pstr("wl_seat") + struct.pack("<II", min(seat_ver, 1), 4))
            self._send(2, 0, struct.pack("<I", mgr_name) + _pstr(mgr) + struct.pack("<II", 1, 5))
            self.manager, self.device = 5, 6
            self._send(5, 1, struct.pack("<II", 6, 4))   # get_data_device(yeni id 6, seat 4)
            self.ok = True
            threading.Thread(target=self._loop, daemon=True).start()
            return True
        except Exception as e:
            print("pano geçmişi başlatılamadı:", e, flush=True)
            return False

    # -- olay döngüsü
    def _loop(self):
        while True:
            try:
                for obj, op, body in self._events():
                    self._dispatch(obj, op, body)
            except Exception as e:
                print("pano bağlantısı koptu:", e, flush=True)
                self.ok = False
                return

    def _dispatch(self, obj, op, body):
        if obj == 1 and op == 0:                          # wl_display.error(nesne, kod, ileti)
            code = struct.unpack_from("<II", body, 0)[1]
            print(f"Wayland protokol hatası: nesne={struct.unpack_from('<I', body)[0]} kod={code} "
                  f"{_rstr(body, 8)[0]}", flush=True)
            return
        if obj == self.device:
            if op == 0:                                   # data_offer(new_id)
                self.offers[struct.unpack_from("<I", body)[0]] = []
            elif op == 1:                                 # selection(offer|0)
                oid = struct.unpack_from("<I", body)[0]
                if oid:
                    self._take(oid)
                self._drop_offers(keep=None)
            elif op == 3:                                 # primary_selection: kullanma
                self._drop_offers(keep=None)
        elif obj in self.offers and op == 0:              # offer(mime)
            self.offers[obj].append(_rstr(body, 0)[0])
        elif obj in self.sources:
            if op == 0:                                   # send(mime, fd)
                mime, _ = _rstr(body, 0)
                fd = self.fds.pop(0) if self.fds else None
                if fd is not None:
                    try:
                        with os.fdopen(fd, "wb") as f:
                            f.write(self.sources[obj].encode())
                    except OSError:
                        pass
            elif op == 1:                                 # cancelled
                self._send(obj, 1)
                self.sources.pop(obj, None)

    def _drop_offers(self, keep):
        for oid in list(self.offers):
            if oid != keep and oid not in self.reading:
                try:
                    self._send(oid, 1)                    # destroy
                except OSError:
                    pass
                self.offers.pop(oid, None)

    def _take(self, oid):
        mimes = self.offers.get(oid, [])
        if SECRET_MIME in mimes:
            return
        mime = next((m for m in TEXT_MIMES if m in mimes), None)
        if not mime:
            return
        r, w = os.pipe()
        try:
            self._send(oid, 0, _pstr(mime), fds=[w])
        finally:
            os.close(w)
        # KWin veriyi ~1 sn gecikmeyle iletir; olay döngüsünü bloklamamak için ayrı iş parçacığında oku
        self.reading.add(oid)
        threading.Thread(target=self._read, args=(oid, r), daemon=True).start()

    def _read(self, oid, r):
        chunks, total, deadline = [], 0, time.time() + 5.0
        try:
            while time.time() < deadline and total < MAX_CHARS * 4:
                if not select.select([r], [], [], 0.2)[0]:
                    continue
                chunk = os.read(r, 65536)
                if not chunk:
                    break
                chunks.append(chunk)
                total += len(chunk)
        finally:
            os.close(r)
            self.reading.discard(oid)
            try:
                self._send(oid, 1)                        # offer.destroy
            except OSError:
                pass
            self.offers.pop(oid, None)
        text = b"".join(chunks).decode(errors="replace")[:MAX_CHARS]
        # Kendi geri kopyaladığımız metni yeniden ekleme (sıra bozulmasın)
        if text.strip() and text not in self.sources.values():
            self._add(text)

    # -- geçmiş
    def _add(self, text):
        self.items = [i for i in self.items if i["text"] != text]    # aynıysa üste taşı
        self.counter += 1
        self.items.insert(0, {"id": self.counter, "text": text})
        del self.items[MAX_ITEMS:]
        self._publish()

    def _publish(self):
        self.on_update([{"id": i["id"], "text": i["text"][:PREVIEW], "len": len(i["text"])}
                        for i in self.items])

    def copy(self, item_id):
        """Geçmişteki bir öğeyi panoya geri koyar."""
        text = next((i["text"] for i in self.items if i["id"] == item_id), None)
        if text is None or not self.ok:
            return
        src = self._alloc()
        self.sources[src] = text
        self._send(self.manager, 0, struct.pack("<I", src))        # create_data_source
        for m in TEXT_MIMES[:2]:
            self._send(src, 0, _pstr(m))                           # offer
        self._send(self.device, 0, struct.pack("<I", src))         # set_selection

    def delete(self, item_id):
        self.items = [i for i in self.items if i["id"] != item_id]
        self._publish()

    def clear(self):
        self.items = []
        self._publish()
