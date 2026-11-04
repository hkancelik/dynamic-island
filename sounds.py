"""Arayüz sesleri: yumuşak, kısa ve kodla sentezlenmiş (ikili dosya, telif yok).

Sesler ilk kullanımda ~/.cache/dynamic-island/sounds altına 16-bit mono WAV olarak yazılır ve
`pw-play` (yoksa `paplay`) ile çalınır. Varsayılan olarak kapalıdır (Ayarlar → Genel → Arayüz sesleri);
zamanlayıcı alarmı ayardan bağımsız her zaman çalar.

Her ses: bir ya da birkaç nota; nota = başlangıç, frekans, süre, genlik, sönüm ve ton rengi
(harmonik/çan payları). Başlangıçta 3 ms yükselme, sonda 10 ms kısılma: tık sesi çıkmaz.
"""
import math
import os
import random
import shutil
import struct
import subprocess
import threading
import time
import wave

RATE = 24000
VERSION = 2
CACHE = os.path.expanduser("~/.cache/dynamic-island/sounds")
PEAK = 0.55
MIN_GAP = 0.12          # aynı sesi bu kadar sn'den sık çalma

# ton renkleri: [(frekans çarpanı, genlik)]
SINE = [(1.0, 1.0)]
SOFT = [(1.0, 1.0), (2.0, 0.28)]
BELL = [(1.0, 1.0), (2.76, 0.38), (5.4, 0.14), (8.9, 0.05)]    # çan: tam kat olmayan üst tonlar

# ad -> [(başlangıç sn, frekans Hz, süre sn, genlik, sönüm süresi sn, ton, kayma)]
# kayma: frekansın süre boyunca oranı (1.0 = sabit; 0.9 = %10 aşağı süzülür)
SOUNDS = {
    "open": [(0.0, 540, 0.11, 1.0, 0.035, SOFT, 1.12)],
    "close": [(0.0, 470, 0.09, 0.9, 0.028, SOFT, 0.88)],
    "palette": [(0.0, 700, 0.10, 1.0, 0.03, SOFT, 1.1), (0.045, 1050, 0.09, 0.45, 0.03, SINE, 1.0)],
    "copy": [(0.0, 1900, 0.04, 1.0, 0.012, SOFT, 1.0)],
    "notify": [(0.0, 880, 0.12, 0.8, 0.05, BELL, 1.0), (0.09, 1175, 0.16, 0.7, 0.07, BELL, 1.0)],
    "done": [(0.0, 784, 0.30, 0.9, 0.11, BELL, 1.0), (0.10, 1175, 0.45, 0.8, 0.16, BELL, 1.0)],
    "fail": [(0.0, 262, 0.28, 1.0, 0.10, SOFT, 0.93), (0.12, 196, 0.38, 0.9, 0.14, SOFT, 0.93)],
    "timer": [(0.00, 659, 0.40, 0.9, 0.16, BELL, 1.0), (0.16, 784, 0.40, 0.9, 0.16, BELL, 1.0),
              (0.32, 988, 0.40, 0.9, 0.16, BELL, 1.0), (0.54, 1319, 0.90, 0.95, 0.30, BELL, 1.0)],
    "shot": "shutter",
}


def _note(buf, start, freq, dur, amp, decay, timbre, glide):
    n0 = int(start * RATE)
    n = int(dur * RATE)
    attack = max(1, int(0.003 * RATE))
    release = max(1, int(0.010 * RATE))
    phase = {i: 0.0 for i in range(len(timbre))}
    for i in range(n):
        if n0 + i >= len(buf):
            break
        t = i / RATE
        f = freq * (1 + (glide - 1) * min(1.0, t / dur))
        env = math.exp(-t / decay)
        if i < attack:
            env *= i / attack
        if i > n - release:
            env *= max(0.0, (n - i) / release)
        v = 0.0
        for k, (mult, a) in enumerate(timbre):
            phase[k] += 2 * math.pi * f * mult / RATE
            v += a * math.sin(phase[k])
        buf[n0 + i] += amp * env * v


def _shutter(buf):
    """Kamera sesi: iki kısa gürültü patlaması (kapak) + alçak tık."""
    rnd = random.Random(7)
    for start, dur, amp in ((0.0, 0.030, 0.55), (0.055, 0.045, 0.40)):
        n0, n = int(start * RATE), int(dur * RATE)
        lp = 0.0
        for i in range(n):
            lp = 0.55 * lp + 0.45 * (rnd.random() * 2 - 1)               # hafif alçak geçiren
            env = math.exp(-i / (0.35 * n)) * min(1.0, i / 24) * min(1.0, (n - i) / 60)
            buf[n0 + i] += amp * lp * env
    _note(buf, 0.0, 210, 0.05, 0.5, 0.02, SOFT, 0.8)


def render(name):
    """-> örnek listesi (-1..1)."""
    spec = SOUNDS[name]
    length = 0.25 if spec == "shutter" else max(s + d for s, _f, d, _a, _dc, _t, _g in spec) + 0.05
    buf = [0.0] * int(length * RATE)
    if spec == "shutter":
        _shutter(buf)
    else:
        for note in spec:
            _note(buf, *note)
    peak = max(abs(x) for x in buf) or 1.0
    return [x / peak * PEAK for x in buf]


def path(name):
    return os.path.join(CACHE, "%s-v%d.wav" % (name, VERSION))


def ensure(name):
    """Dosya yoksa üretir; yolunu döndürür."""
    p = path(name)
    if not os.path.exists(p):
        os.makedirs(CACHE, mode=0o700, exist_ok=True)
        samples = render(name)
        tmp = p + ".tmp"
        with wave.open(tmp, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, x)) * 32767)) for x in samples))
        os.replace(tmp, p)
    return p


class Sounds:
    def __init__(self, enabled=lambda: False, volume=lambda: 0.45):
        self._enabled, self._volume = enabled, volume
        self._last = {}
        self._lock = threading.Lock()
        self._player = shutil.which("pw-play") or shutil.which("paplay")

    def play(self, name, force=False):
        """Sesi çal (ayar kapalıysa çalma; force: alarm gibi her zaman çalmalı olanlar)."""
        if name not in SOUNDS or not self._player or not (force or self._enabled()):
            return False
        now = time.monotonic()
        with self._lock:
            if now - self._last.get(name, 0) < MIN_GAP:
                return False
            self._last[name] = now
        threading.Thread(target=self._run, args=(name,), daemon=True).start()
        return True

    def _run(self, name):
        try:
            p = ensure(name)
            vol = max(0.05, min(1.0, float(self._volume())))
            args = ([self._player, "--volume=%.2f" % vol, p] if os.path.basename(self._player) == "pw-play"
                    else [self._player, "--volume=%d" % int(vol * 65536), p])
            subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        except Exception as e:
            print("ses çalınamadı:", e, flush=True)
