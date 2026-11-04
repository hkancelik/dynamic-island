"""Ekran görüntüsü önizlemesi: Spectacle'ın kayıt klasörünü izler, yeni resim olunca haber verir.

Klasör, Spectacle ayarından (`~/.config/spectaclerc`: son kayıt yeri ve varsayılan konum) ve
Resimler klasöründeki "Screenshots" / "Ekran Görüntüleri" benzeri alt klasörlerden bulunur.
İzleme Gio.FileMonitor ile yapılır (yoklama yok, işlemci harcamaz). Dosyanın içeriği okunmaz;
yalnızca ad, yol ve PNG ise boyutu (başlık baytlarından) yayınlanır.
"""
import configparser
import os
import re
import struct
import subprocess
import time
from pathlib import Path
from urllib.parse import unquote, urlparse

HOME = os.path.expanduser("~")
EXTS = {".png", ".jpg", ".jpeg", ".webp"}
# Ekran görüntüsüne benzeyen dosya adları (Türkçe harfler sadeleştirilmiş)
NAME_RE = re.compile(r"screenshot|screen[ _-]?shot|ekran|spectacle|capture|snip|flameshot|scrot|grim", re.I)
DEDICATED_RE = re.compile(r"screenshot|ekran|capture|snip", re.I)
MAX_AGE = 15          # sn: bundan eski değişmiş dosya "yeni ekran görüntüsü" sayılmaz
DEBOUNCE = 3          # sn: aynı dosya için tekrar bildirim


def _dir_of(value):
    v = (value or "").strip()
    if not v:
        return None
    path = unquote(urlparse(v).path) if v.startswith("file:") else os.path.expanduser(v)
    path = path if os.path.isdir(path) else os.path.dirname(path)
    return path if os.path.isdir(path) else None


def candidate_dirs(home=HOME, rc=None, extra=()):
    """İzlenecek klasörler (var olanlar, yinelenmeden). extra: ayardaki `screenshot_dirs`
    (Flameshot vb. için); ISLAND_SCREENSHOT_DIRS ortam değişkeni de ":" ile ayrılmış klasör ekler."""
    out = []
    for d in list(extra) + os.environ.get("ISLAND_SCREENSHOT_DIRS", "").split(":"):
        d = _dir_of(str(d)) if d else None
        if d:
            out.append(d)
    rc = rc or os.path.join(home, ".config", "spectaclerc")
    cp = configparser.RawConfigParser(strict=False)
    cp.optionxform = str
    try:
        cp.read(rc, encoding="utf-8")
        for sect in cp.sections():
            for key in ("lastImageSaveLocation", "defaultSaveLocation", "imageSaveLocation"):
                d = _dir_of(cp.get(sect, key, fallback=""))
                if d:
                    out.append(d)
    except (configparser.Error, OSError):
        pass
    try:
        pics = subprocess.run(["xdg-user-dir", "PICTURES"], capture_output=True, text=True, timeout=2).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        pics = ""
    for base in {pics, os.path.join(home, "Pictures"), os.path.join(home, "Resimler")}:
        if not base or not os.path.isdir(base):
            continue
        try:
            for name in os.listdir(base):
                low = name.lower()
                full = os.path.join(base, name)
                if os.path.isdir(full) and ("screenshot" in low or "ekran" in low or "capture" in low):
                    out.append(full)
        except OSError:
            continue
    seen, uniq = set(), []
    for d in out:
        d = os.path.realpath(d)
        if d not in seen and os.path.isdir(d):
            seen.add(d)
            uniq.append(d)
    return uniq


def image_size(path):
    """PNG başlığından (genişlik, yükseklik); başka biçimlerde (0, 0)."""
    try:
        with open(path, "rb") as f:
            head = f.read(24)
        if head[:8] == b"\x89PNG\r\n\x1a\n" and head[12:16] == b"IHDR":
            return struct.unpack(">II", head[16:24])
    except (OSError, struct.error):
        pass
    return 0, 0


def is_fresh_image(path, now=None):
    p = Path(path)
    if p.suffix.lower() not in EXTS or p.name.startswith("."):
        return False
    try:
        st = p.stat()
    except OSError:
        return False
    return st.st_size > 0 and (now or time.time()) - st.st_mtime <= MAX_AGE


class Shots:
    def __init__(self, publish, dirs=None, extra=()):
        from gi.repository import Gio   # yalnızca arka uçta; testler gi olmadan çalışır
        self._Gio = Gio
        self._publish = publish
        self.seq = 0
        self.last = ""
        self._seen = {}
        self.monitors = []
        self.dirs = list(dirs) if dirs is not None else candidate_dirs(extra=extra)
        # Kullanıcının verdiği klasörler ve adı "Ekran Görüntüleri/Screenshots" gibi olanlar tamamen
        # güvenilir; Spectacle'ın "son kayıt yeri" ise herhangi bir klasör olabilir (İndirilenler…):
        # orada yalnızca adı ekran görüntüsüne benzeyen dosyalar sayılır.
        given = [_dir_of(str(d)) for d in list(extra) + os.environ.get("ISLAND_SCREENSHOT_DIRS", "").split(":") if d]
        self.trusted = {os.path.realpath(d) for d in given if d} | \
                       {os.path.realpath(d) for d in self.dirs if DEDICATED_RE.search(os.path.basename(d))}
        if dirs is not None:
            self.trusted |= {os.path.realpath(d) for d in dirs}
        for d in self.dirs:
            try:
                m = Gio.File.new_for_path(d).monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, None)
                m.connect("changed", self._changed)
                self.monitors.append(m)
            except Exception as e:
                print("ekran görüntüsü klasörü izlenemedi:", d, e, flush=True)

    def _changed(self, _mon, file, other, event):
        T = self._Gio.FileMonitorEvent
        if event == T.RENAMED and other is not None:
            path = other.get_path()
        elif event in (T.CHANGES_DONE_HINT, T.MOVED_IN):
            path = file.get_path()
        else:
            return
        self.handle(path)

    def handle(self, path):
        """Yeni bir dosya haberi: geçerli ve yeniyse yayınla."""
        now = time.time()
        if not path or now - self._seen.get(path, 0) < DEBOUNCE or not is_fresh_image(path, now):
            return False
        if os.path.realpath(os.path.dirname(path)) not in self.trusted and not NAME_RE.search(os.path.basename(path)):
            return False
        self._seen[path] = now
        if len(self._seen) > 200:
            self._seen = {p: t for p, t in self._seen.items() if now - t < 60}
        w, h = image_size(path)
        self.seq += 1
        self.last = path
        self._publish({"seq": self.seq, "path": path, "name": os.path.basename(path),
                       "url": Path(path).as_uri(), "w": w, "h": h, "ts": int(now * 1000)})
        return True
