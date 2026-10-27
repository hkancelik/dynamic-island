"""Odak sayacı (Pomodoro): odak → mola → odak ... Süre arka uçta tutulur,
arayüz yeniden başlasa da kaldığı yerden sürer. Odak sırasında Rahatsız Etme açılır."""
import subprocess
import threading
import time

SOUND = "/usr/share/sounds/ocean/stereo/alarm-clock-elapsed.oga"


def _now_ms():
    return int(time.time() * 1000)


class Focus:
    def __init__(self, publish, set_dnd, work=25, brk=5):
        """publish(dict): durumu yayınla. set_dnd(bool|None) -> önceki değer."""
        self._publish = publish
        self._set_dnd = set_dnd
        self.lock = threading.Lock()
        self.s = {"phase": "idle", "running": False, "end": 0, "left": work * 60000,
                  "work": work, "brk": brk, "round": 0, "seq": 0}
        self._dnd_prev = None     # odak başlarken DND'nin eski hali (biz açtıysak geri alınır)
        self._emit()
        threading.Thread(target=self._tick, daemon=True).start()

    def _emit(self):
        self._publish(dict(self.s))

    def _dnd(self, on):
        if on and self._dnd_prev is None:
            self._dnd_prev = self._set_dnd(True)
        elif not on and self._dnd_prev is not None:
            self._set_dnd(self._dnd_prev)
            self._dnd_prev = None

    def _length(self, phase):
        return (self.s["work"] if phase == "work" else self.s["brk"]) * 60000

    def _tick(self):
        while True:
            time.sleep(0.5)
            with self.lock:
                if not self.s["running"] or _now_ms() < self.s["end"]:
                    continue
                # aşama bitti: odak → mola ya da mola → odak
                nxt = "break" if self.s["phase"] == "work" else "work"
                if self.s["phase"] == "work":
                    self.s["round"] += 1
                self.s.update(phase=nxt, end=_now_ms() + self._length(nxt), left=self._length(nxt),
                              seq=self.s["seq"] + 1)
                self._dnd(nxt == "work")
                self._emit()
            subprocess.Popen(["pw-play", SOUND], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # -- komutlar -------------------------------------------------------------
    def start(self):
        with self.lock:
            if self.s["running"]:
                return
            if self.s["phase"] == "idle":
                self.s.update(phase="work", left=self._length("work"))
            self.s.update(running=True, end=_now_ms() + self.s["left"])
            self._dnd(self.s["phase"] == "work")
            self._emit()

    def pause(self):
        with self.lock:
            if not self.s["running"]:
                return
            self.s.update(running=False, left=max(0, self.s["end"] - _now_ms()), end=0)
            self._dnd(False)
            self._emit()

    def toggle(self):
        if self.s["running"]:
            self.pause()
        else:
            self.start()

    def reset(self):
        with self.lock:
            self.s.update(phase="idle", running=False, end=0, left=self._length("work"), round=0)
            self._dnd(False)
            self._emit()

    def skip(self):
        """Aşamayı hemen bitir (mola atla ya da odağı erken bitir)."""
        with self.lock:
            if self.s["phase"] == "idle":
                return
            if not self.s["running"]:
                self.s["running"] = True
            self.s["end"] = _now_ms()

    def set_lengths(self, work=None, brk=None):
        with self.lock:
            if work is not None:
                self.s["work"] = max(1, min(120, int(work)))
            if brk is not None:
                self.s["brk"] = max(1, min(60, int(brk)))
            if self.s["phase"] == "idle":
                self.s["left"] = self._length("work")
            self._emit()
