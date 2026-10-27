"""Pil ayrıntıları (sysfs) ve sistem istatistikleri (/proc, hwmon).

İstatistikler yalnızca ilgili sekme açıkken toplanır (enable() her çağrıda süreyi uzatır);
böylece boşta hiç CPU harcanmaz.
"""
import glob
import os
import threading
import time
from collections import deque

POWER = "/sys/class/power_supply"
HIST = 30


def _read(path, default=None):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return default


def _num(path, default=0.0):
    try:
        return float(_read(path, default))
    except (TypeError, ValueError):
        return default


# -- Pil -----------------------------------------------------------------------
def battery_info():
    bats = sorted(glob.glob(f"{POWER}/BAT*"))
    if not bats:
        return {"present": False, "level": 100, "charging": False}
    b = bats[0]
    status = _read(f"{b}/status", "Unknown")
    level = int(_num(f"{b}/capacity", 0))

    # Enerji (µWh/µW) ya da şarj (µAh/µA) tabanlı sürücüler
    if os.path.exists(f"{b}/energy_now"):
        now, full, design = (_num(f"{b}/energy_now"), _num(f"{b}/energy_full"),
                             _num(f"{b}/energy_full_design"))
        rate_w = _num(f"{b}/power_now") / 1e6
        flow = _num(f"{b}/power_now")
    else:
        now, full, design = (_num(f"{b}/charge_now"), _num(f"{b}/charge_full"),
                             _num(f"{b}/charge_full_design"))
        cur = _num(f"{b}/current_now")
        rate_w = cur * _num(f"{b}/voltage_now") / 1e12
        flow = cur

    seconds = -1
    if flow > 0:
        if status == "Discharging":
            seconds = int(now / flow * 3600)
        elif status == "Charging":
            seconds = int(max(0, full - now) / flow * 3600)

    return {
        "present": True,
        "level": level,
        "charging": status in ("Charging", "Full"),
        "state": status,
        "time": (seconds // 60) * 60 if seconds >= 0 else -1,   # dakikaya yuvarla (gereksiz güncelleme olmasın)
        "rate": round(rate_w, 1),
        "health": int(full / design * 100) if design else 0,
        "limit": int(_num(f"{b}/charge_control_end_threshold", 0)),
        "cycles": int(_num(f"{b}/cycle_count", 0)),
    }


# -- Sistem istatistikleri ---------------------------------------------------------
def _cpu_times():
    parts = _read("/proc/stat", "cpu 0 0 0 0").splitlines()[0].split()[1:]
    vals = [int(x) for x in parts]
    idle = vals[3] + (vals[4] if len(vals) > 4 else 0)
    return sum(vals), idle


def _net_bytes():
    rx = tx = 0
    for line in (_read("/proc/net/dev", "") or "").splitlines()[2:]:
        name, _, data = line.partition(":")
        if name.strip() == "lo" or not data:
            continue
        f = data.split()
        rx += int(f[0])
        tx += int(f[8])
    return rx, tx


def _hwmon(name):
    for d in glob.glob("/sys/class/hwmon/hwmon*"):
        if _read(f"{d}/name") == name:
            return d
    return None


class Stats:
    def __init__(self, on_update):
        self.on_update = on_update
        self.until = 0.0
        self.running = False
        self.lock = threading.Lock()
        self.cpu_hist = deque([0] * HIST, maxlen=HIST)
        self.down_hist = deque([0] * HIST, maxlen=HIST)
        self.up_hist = deque([0] * HIST, maxlen=HIST)
        self.coretemp = _hwmon("coretemp")
        self.fan = _hwmon("dell_smm") or _hwmon("thinkpad")

    def enable(self):
        with self.lock:
            self.until = time.time() + 15
            if self.running:
                return
            self.running = True
        threading.Thread(target=self._loop, daemon=True).start()

    def _temp(self):
        if not self.coretemp:
            return 0
        t = _num(f"{self.coretemp}/temp1_input", 0) / 1000
        if not t:
            temps = [_num(p) for p in glob.glob(f"{self.coretemp}/temp*_input")]
            t = max(temps) / 1000 if temps else 0
        return int(round(t))

    def _loop(self):
        total0, idle0 = _cpu_times()
        rx0, tx0 = _net_bytes()
        t0 = time.time()
        while time.time() < self.until:
            time.sleep(1)
            total1, idle1 = _cpu_times()
            rx1, tx1 = _net_bytes()
            t1 = time.time()
            dt = max(0.001, t1 - t0)
            dtot = max(1, total1 - total0)
            cpu = int(round(100 * (1 - (idle1 - idle0) / dtot)))
            down, up = int((rx1 - rx0) / dt), int((tx1 - tx0) / dt)
            total0, idle0, rx0, tx0, t0 = total1, idle1, rx1, tx1, t1

            mem = {}
            for line in (_read("/proc/meminfo", "") or "").splitlines()[:6]:
                k, _, v = line.partition(":")
                mem[k] = int(v.split()[0]) if v.split() else 0
            total_kb = mem.get("MemTotal", 1)
            used_kb = total_kb - mem.get("MemAvailable", 0)

            self.cpu_hist.append(cpu)
            self.down_hist.append(down)
            self.up_hist.append(up)
            self.on_update({
                "cpu": cpu,
                "mem": int(round(100 * used_kb / total_kb)),
                "memUsed": round(used_kb / 1048576, 1),
                "memTotal": round(total_kb / 1048576, 1),
                "temp": self._temp(),
                "fan": int(_num(f"{self.fan}/fan1_input")) if self.fan else 0,
                "down": down,
                "up": up,
                "uptime": int(float((_read("/proc/uptime", "0") or "0").split()[0])),
                "cpuHist": list(self.cpu_hist),
                "downHist": list(self.down_hist),
                "upHist": list(self.up_hist),
            })
        with self.lock:
            self.running = False
