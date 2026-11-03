"""Gerçek ses spektrumu: hoparlöre giden sesin frekans bantları (müzik çubukları için).

Varsayılan çıkışın monitörü `parec` ile okunur (yalnızca bellekte, hiçbir yere yazılmaz).
Bağımlılık yok: 1024 noktalı FFT saf Python'da (~1 ms). Okuyucu iş parçacığı yalnızca
baytları biriktirir; FFT arayüz istediğinde hesaplanır. Arayüz 2 sn sormazsa yakalama durur,
yani müzik çalmıyorken ya da çubuklar görünmüyorken hiç işlemci harcanmaz.
"""
import array
import cmath
import math
import subprocess
import threading
import time

RATE = 22050
N = 1024                 # FFT boyu (46 ms; bas bantları ayrışsın)
BANDS = 24
F_LO, F_HI = 50.0, 10000.0
IDLE_STOP = 2.0          # bu kadar sn istenmezse yakalama durur
MIN_GAP = 0.02           # en fazla ~50 hesap/sn

CMD = ["parec", "--format=s16le", "--rate=%d" % RATE, "--channels=1",
       "--latency-msec=25", "--raw", "--client-name=dynamic-island", "--stream-name=spectrum",
       # gizlilik noktaları bunu mikrofon saymasın (bkz. privacy.py)
       "--property=stream.capture.sink=true"]

_HANN = [0.5 - 0.5 * math.cos(2 * math.pi * i / (N - 1)) for i in range(N)]
_BITS = N.bit_length() - 1
_REV = [int(format(i, "0%db" % _BITS)[::-1], 2) for i in range(N)]
_TW = [cmath.exp(-2j * math.pi * k / N) for k in range(N // 2)]


def fft(x):
    """Yerinde olmayan, yinelemeli radix-2 FFT (len(x) == N)."""
    a = [complex(x[_REV[i]]) for i in range(N)]
    size = 2
    while size <= N:
        half, step = size // 2, N // size
        for start in range(0, N, size):
            k = 0
            for j in range(start, start + half):
                t = _TW[k] * a[j + half]
                a[j + half] = a[j] - t
                a[j] += t
                k += step
        size *= 2
    return a


def _band_bins():
    """Logaritmik aralıklı bantların FFT kutu aralıkları (her bant en az bir kutu)."""
    res = RATE / N
    edges = [F_LO * (F_HI / F_LO) ** (i / BANDS) for i in range(BANDS + 1)]
    out = []
    for i in range(BANDS):
        lo = max(1, int(edges[i] / res))
        hi = max(lo + 1, int(math.ceil(edges[i + 1] / res)))
        out.append((lo, min(hi, N // 2)))
    return out


_BINS = _band_bins()


def bands(samples):
    """N örnek (-1..1) -> BANDS adet dB değeri."""
    spec = fft([s * w for s, w in zip(samples, _HANN)])
    out = []
    for lo, hi in _BINS:
        m = max(abs(spec[i]) for i in range(lo, hi))
        out.append(20 * math.log10(m / (N / 4) + 1e-9))
    return out


class Spectrum:
    def __init__(self, device="@DEFAULT_MONITOR@"):
        self._device = device
        self._lock = threading.Lock()
        self._buf = array.array("h", [0] * N)
        self._proc = None
        self._asked = 0.0
        self._last_calc = 0.0
        self._levels = [0.0] * BANDS
        self._peak = -30.0           # otomatik kazanç: son zamanlardaki en yüksek düzey (dB)
        self.available = True

    # -- yakalama
    def _start(self):
        try:
            self._proc = subprocess.Popen(CMD + ["--device=" + self._device], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        except FileNotFoundError:
            self.available = False
            return
        threading.Thread(target=self._read, args=(self._proc,), daemon=True).start()

    def _read(self, proc):
        chunk = 256 * 2
        while True:
            data = proc.stdout.read(chunk)
            if not data:
                break
            fresh = array.array("h")
            fresh.frombytes(data[: len(data) // 2 * 2])
            with self._lock:
                self._buf = (self._buf + fresh)[-N:]
            if time.time() - self._asked > IDLE_STOP:
                break
        try:
            proc.terminate()
        except Exception:
            pass
        with self._lock:
            if self._proc is proc:
                self._proc = None
                self._levels = [0.0] * BANDS

    # -- arayüz
    def levels(self):
        """0..100 arası BANDS değer; yakalama gerekiyorsa başlatır."""
        now = time.time()
        self._asked = now
        with self._lock:
            if self._proc is None and self.available:
                self._start()
            if now - self._last_calc < MIN_GAP:
                return [round(v * 100) for v in self._levels]
            self._last_calc = now
            samples = [s / 32768.0 for s in self._buf]
        rms = math.sqrt(sum(s * s for s in samples) / N)
        if rms < 1e-4:
            new = [0.0] * BANDS
        else:
            db = bands(samples)
            top = max(db)
            # kazanç hızlı yükselir, yavaş düşer: sessiz şarkılar da dolu görünsün
            self._peak = top if top > self._peak else self._peak * 0.995 + top * 0.005
            floor = self._peak - 42
            new = [max(0.0, min(1.0, (d - floor) / (self._peak - floor))) ** 1.4 for d in db]
        with self._lock:
            # hızlı yükseliş, yumuşak düşüş
            self._levels = [n if n > o else o * 0.78 + n * 0.22 for n, o in zip(new, self._levels)]
            return [round(v * 100) for v in self._levels]
