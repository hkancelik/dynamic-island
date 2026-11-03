"""Masaüstü duvar kağıdının dosya yolu (Plasma ayarlarından); sıvı cam bunu camın içinde yansıtır."""
import os
import re
from urllib.parse import quote

RC = os.path.expanduser("~/.config/plasma-org.kde.plasma.desktop-appletsrc")
EXT = (".png", ".jpg", ".jpeg", ".webp", ".bmp")


def parse(text):
    """appletsrc metninden duvar kağıdı dosyaları (görülme sırasıyla). Ağsız, test edilebilir."""
    out = []
    for m in re.finditer(r"^Image=(.+)$", text, re.M):
        v = m.group(1).strip()
        if v.startswith("file://"):
            v = v[7:]
        if v.startswith("/") and v.lower().endswith(EXT) and v not in out:
            out.append(v)
    return out


def current(path=RC):
    """Önce kullanıcının kendi eklediği (sistem klasörü dışı) duvar kağıdı; yoksa ilki. file:// adresi, yoksa ''."""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            files = [p for p in parse(f.read()) if os.path.isfile(p)]
    except OSError:
        return ""
    if not files:
        return ""
    own = [p for p in files if not p.startswith("/usr/")]
    return "file://" + quote((own or files)[0])


def mtime(path=RC):
    try:
        return os.stat(path).st_mtime
    except OSError:
        return 0
