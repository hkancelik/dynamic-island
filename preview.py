"""Hızlı Bakış: bir dosyanın önizlemesi için bilgi ve küçük resim üretir.

  resim            doğrudan dosyanın kendisi (arayüz küçültür)
  metin / kod      ilk ~1,5 KB (ikili dosyalar metin sayılmaz)
  PDF              ilk sayfa (pdftoppm) + sayfa sayısı (pdfinfo)
  video            1. saniyeden bir kare + süre (ffmpeg / ffprobe)
  ses              süre, başlık/sanatçı ve gömülü kapak (ffprobe / ffmpeg)
  klasör           öğe sayısı

Küçük resimler ~/.cache/dynamic-island/preview altında (yol + değişme zamanı + boyuttan türeyen
adla) tutulur; en yeni 80 dosya saklanır. Hiçbir şey dışarı gönderilmez.
"""
import hashlib
import json
import mimetypes
import os
import shutil
import subprocess
import time
from pathlib import Path

CACHE = os.path.expanduser("~/.cache/dynamic-island/preview")
KEEP = 80
TEXT_BYTES = 1536
TIMEOUT = 5

IMAGE = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp", ".svg", ".avif", ".ico"}
VIDEO = {".mp4", ".mkv", ".webm", ".mov", ".avi", ".m4v", ".flv", ".wmv"}
AUDIO = {".mp3", ".flac", ".ogg", ".oga", ".opus", ".wav", ".m4a", ".aac", ".wma"}
TEXT_EXT = {".txt", ".md", ".py", ".js", ".ts", ".qml", ".json", ".yml", ".yaml", ".toml", ".ini", ".cfg",
            ".conf", ".sh", ".fish", ".c", ".h", ".cpp", ".hpp", ".rs", ".go", ".java", ".kt", ".css", ".html",
            ".xml", ".csv", ".log", ".sql", ".desktop", ".service", ".rst", ".tex", ".dart"}


def human_size(n):
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024 or unit == "TB":
            return ("%d %s" % (n, unit)) if unit == "B" else ("%.1f %s" % (n, unit)).replace(".0 ", " ")
        n /= 1024.0


def duration_text(sec):
    sec = int(round(float(sec)))
    h, m, s = sec // 3600, sec // 60 % 60, sec % 60
    return "%d:%02d:%02d" % (h, m, s) if h else "%d:%02d" % (m, s)


def kind_of(path):
    p = Path(path)
    if p.is_dir():
        return "folder"
    ext = p.suffix.lower()
    if ext in IMAGE:
        return "image"
    if ext == ".pdf":
        return "pdf"
    if ext in VIDEO:
        return "video"
    if ext in AUDIO:
        return "audio"
    if ext in TEXT_EXT or (mimetypes.guess_type(path)[0] or "").startswith("text/"):
        return "text"
    return "other"


def read_text(path):
    """İlk TEXT_BYTES bayt, ikili değilse; (metin, kesildi mi)."""
    try:
        with open(path, "rb") as f:
            raw = f.read(TEXT_BYTES + 1)
    except OSError:
        return "", False
    if b"\0" in raw[:1024]:
        return "", False
    cut = len(raw) > TEXT_BYTES
    return raw[:TEXT_BYTES].decode("utf-8", errors="replace"), cut


def _run(args, timeout=TIMEOUT):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def _thumb_path(path, st):
    key = hashlib.sha1(("%s|%d|%d" % (path, st.st_mtime_ns, st.st_size)).encode()).hexdigest()[:20]
    return os.path.join(CACHE, key + ".png")


def _prune():
    try:
        files = sorted((os.path.join(CACHE, f) for f in os.listdir(CACHE)), key=os.path.getmtime, reverse=True)
        for old in files[KEEP:]:
            os.remove(old)
    except OSError:
        pass


def _make_thumb(kind, path, out):
    """Küçük resmi `out`a yazar; başardıysa True."""
    os.makedirs(CACHE, mode=0o700, exist_ok=True)
    if kind == "pdf" and shutil.which("pdftoppm"):
        prefix = out[:-4]
        _run(["pdftoppm", "-f", "1", "-l", "1", "-png", "-singlefile", "-scale-to", "640", path, prefix])
    elif kind == "video" and shutil.which("ffmpeg"):
        _run(["ffmpeg", "-v", "error", "-y", "-ss", "1", "-i", path, "-frames:v", "1", "-vf", "scale=640:-2", out])
        if not os.path.exists(out):   # 1 sn'den kısa videolar
            _run(["ffmpeg", "-v", "error", "-y", "-i", path, "-frames:v", "1", "-vf", "scale=640:-2", out])
    elif kind == "audio" and shutil.which("ffmpeg"):
        _run(["ffmpeg", "-v", "error", "-y", "-i", path, "-an", "-frames:v", "1", "-vf", "scale=480:-2", out])
    return os.path.exists(out)


def _probe(path):
    out = _run(["ffprobe", "-v", "error", "-show_entries", "format=duration:format_tags=title,artist,album",
                "-of", "json", path]) if shutil.which("ffprobe") else ""
    try:
        fmt = json.loads(out or "{}").get("format", {})
    except ValueError:
        return {}
    tags = {k.lower(): v for k, v in (fmt.get("tags") or {}).items()}
    return {"duration": float(fmt["duration"]) if fmt.get("duration") else 0.0,
            "title": tags.get("title", ""), "artist": tags.get("artist", ""), "album": tags.get("album", "")}


def info(path):
    """Önizleme bilgisi; dosya yoksa/okunamıyorsa {"error": ...}."""
    path = os.path.abspath(str(path))
    try:
        st = os.stat(path)
    except OSError:
        return {"error": "missing", "name": os.path.basename(path)}
    kind = kind_of(path)
    d = {"path": path, "name": os.path.basename(path), "kind": kind, "size": st.st_size,
         "sizeText": human_size(st.st_size), "mtime": int(st.st_mtime * 1000),
         "mime": mimetypes.guess_type(path)[0] or ("inode/directory" if kind == "folder" else ""),
         "url": Path(path).as_uri(), "thumb": "", "text": "", "cut": False, "meta": ""}
    if kind == "folder":
        try:
            n = len(os.listdir(path))
        except OSError:
            n = 0
        d["count"], d["sizeText"] = n, ""
    elif kind == "image":
        from shots import image_size
        w, h = image_size(path)
        d["meta"] = "%d × %d" % (w, h) if w else ""
    elif kind == "text":
        d["text"], d["cut"] = read_text(path)
        if not d["text"]:
            d["kind"] = "other"
    elif kind in ("pdf", "video", "audio"):
        out = _thumb_path(path, st)
        if os.path.exists(out) or _make_thumb(kind, path, out):
            d["thumb"] = Path(out).as_uri()
            try:
                os.utime(out)             # önbellekte "yeni" kalsın
            except OSError:
                pass
            _prune()
        if kind == "pdf":
            m = [ln for ln in _run(["pdfinfo", path]).splitlines() if ln.startswith("Pages:")] if shutil.which("pdfinfo") else []
            pages = int(m[0].split()[1]) if m and m[0].split()[1].isdigit() else 0
            d["meta"] = "%d" % pages if pages else ""
            d["pages"] = pages
        else:
            pr = _probe(path)
            if pr.get("duration"):
                d["meta"] = duration_text(pr["duration"])
            d["title"], d["artist"], d["album"] = pr.get("title", ""), pr.get("artist", ""), pr.get("album", "")
    return d


def is_previewable_path(path):
    """Arayüzün istediği yol: mutlak ve var olmalı."""
    return isinstance(path, str) and os.path.isabs(path) and os.path.exists(path)


def modified_text(ms):
    return time.strftime("%d.%m.%Y %H:%M", time.localtime(ms / 1000))
