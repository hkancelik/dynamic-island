"""Gizlilik noktaları: kamera, mikrofon ya da ekran paylaşımı kullanılıyor mu?

PipeWire düğümlerinden okunur (pw-dump, ~10 ms işlemci). Kamerayı doğrudan /dev/video*
üzerinden açan uygulamalar (PipeWire'ı atlayanlar) için fuser bakılır; ama fuser pahalı
(~60 ms, tüm süreçleri tarar), bu yüzden yalnızca kamera uyanıkken çalıştırılır: USB kamera
görüntü akıtırken askıda (suspended) olamaz.
"""
import glob
import json
import os
import subprocess
import threading
import time

INTERVAL = 3
BLIND_EVERY = 15   # kameranın güç durumu bilinmiyorsa fuser en çok bu kadar sık


def _run(args):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=3).stdout
    except Exception:
        return ""


def _app(p):
    return (p.get("application.name") or p.get("application.process.binary")
            or p.get("node.description") or p.get("node.name") or "")


def _cameras():
    """(uyanık kamera var mı, güç durumu bilgi vermeyen kamera var mı)"""
    awake = blind = False
    for v in glob.glob("/sys/class/video4linux/video*"):
        usb = os.path.dirname(os.path.realpath(os.path.join(v, "device")))   # arayüz -> USB cihazı
        try:
            with open(os.path.join(usb, "power/runtime_status")) as f:
                awake = awake or f.read().strip() == "active"
            with open(os.path.join(usb, "power/control")) as f:
                blind = blind or f.read().strip() == "on"   # otomatik askıya alma kapalı
        except OSError:
            blind = True
    return awake, blind


_last_blind_check = 0


def snapshot():
    global _last_blind_check
    out = {"camera": [], "mic": [], "screen": []}
    try:
        nodes = json.loads(_run(["pw-dump"]) or "[]")
    except ValueError:
        nodes = []
    for o in nodes:
        if o.get("type") != "PipeWire:Interface:Node":
            continue
        info = o.get("info") or {}
        if info.get("state") != "running":
            continue
        p = info.get("props") or {}
        cls = p.get("media.class", "")
        if cls == "Stream/Input/Audio":
            # Ses düzeyi göstergeleri (hoparlör çıkışını dinler) mikrofon sayılmaz
            if (p.get("stream.monitor") or p.get("stream.capture.sink") or "peak" in str(p.get("node.name", "")).lower()
                    or p.get("application.name") == "dynamic-island"):   # adanın kendi spektrum akışı
                continue
            out["mic"].append(_app(p))
        elif cls == "Video/Source":
            if p.get("device.api") in ("v4l2", "libcamera") or p.get("media.role") == "Camera":
                out["camera"].append(p.get("node.nick") or "Kamera")
            else:   # KWin/portal ekran yayını
                out["screen"].append(_app(p))
        elif cls == "Stream/Input/Video":
            target = str(p.get("target.object", "")) + str(p.get("node.target", ""))
            if "v4l2" in target or "libcamera" in target:
                out["camera"].append(_app(p))
    # PipeWire'ı atlayıp kamerayı doğrudan açan uygulamalar
    vids = glob.glob("/dev/video*")
    if vids and not out["camera"]:
        awake, blind = _cameras()
        check = awake
        if blind and not awake and time.time() - _last_blind_check > BLIND_EVERY:
            _last_blind_check = time.time()
            check = True
        if check and _run(["fuser"] + vids).strip():
            out["camera"].append("Kamera")
    return {k: sorted(set(v)) for k, v in out.items()}


class Privacy:
    def __init__(self, publish):
        self._publish = publish
        threading.Thread(target=self._loop, daemon=True).start()

    def _loop(self):
        while True:
            try:
                self._publish(snapshot())
            except Exception as e:
                print("gizlilik denetimi hatası:", e, flush=True)
            time.sleep(INTERVAL)
