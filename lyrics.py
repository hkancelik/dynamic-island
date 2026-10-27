"""Senkron şarkı sözleri: LRCLIB (https://lrclib.net), ücretsiz ve anahtarsız.

Yalnızca söz görünümü açıkken sorulur; sonuç diskte saklanır (her şarkı bir kez,
sözü olmayan şarkı haftada bir yeniden sorulur). Bağlantı hataları saklanmaz.
"""
import hashlib
import json
import os
import re
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://lrclib.net/api"
UA = "dynamic-island/1.0 (KDE Plasma; github.com/zickrian/isle inspired)"
CACHE = os.path.expanduser("~/.cache/dynamic-island/lyrics")
NOT_FOUND_RETRY = 7 * 86400
DURATION_TOLERANCE = 3        # saniye: arama sonucunun süresi bu kadar farklı olabilir
LONGEST = 3600                # LRCLIB daha uzununu reddeder (mix, podcast, yayın)

LRC_RE = re.compile(r"\[(\d+):(\d+(?:\.\d+)?)\]")


def key_of(m):
    return "\x1f".join([m.get("artist", ""), m.get("title", ""), m.get("album", ""),
                        str(round(m.get("length", 0) / 1000))])


def parse_lrc(text):
    """'[01:02.50] söz' satırları -> [[ms, söz], ...] (zamana göre sıralı)."""
    out = []
    for line in text.splitlines():
        stamps = LRC_RE.findall(line)
        if not stamps:
            continue
        words = LRC_RE.sub("", line).strip()
        for mm, ss in stamps:
            out.append([int((int(mm) * 60 + float(ss)) * 1000), words])
    out.sort(key=lambda x: x[0])
    return out


def _get(path, params):
    url = f"{API}/{path}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                return json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            if e.code in (429, 503) and attempt < 2:   # meşgul: kısa bekle, yeniden dene
                time.sleep(min(5, int(e.headers.get("Retry-After") or 1)))
                continue
            raise


def _from_record(rec):
    if rec.get("instrumental"):
        return {"status": "instrumental", "lines": []}
    if rec.get("syncedLyrics"):
        lines = parse_lrc(rec["syncedLyrics"])
        if lines:
            return {"status": "synced", "lines": lines}
    if rec.get("plainLyrics"):
        return {"status": "plain", "lines": [[-1, l.strip()] for l in rec["plainLyrics"].splitlines()]}
    return None


def lookup(m):
    title, artist = m.get("title", "").strip(), m.get("artist", "").strip()
    length_s = m.get("length", 0) / 1000
    if not title or length_s > LONGEST:
        return {"status": "not_found", "lines": []}
    params = {"track_name": title, "artist_name": artist}
    if m.get("album"):
        params["album_name"] = m["album"]
    if length_s > 0:
        params["duration"] = round(length_s)
    rec = _get("get", params)
    found = _from_record(rec) if rec else None
    if found:
        return found
    # Tam eşleşme yok: ara, süresi tutan ilk sonucu al (önce senkronlu olanlar)
    results = _get("search", {"track_name": title, "artist_name": artist}) or []
    ok = [r for r in results
          if length_s <= 0 or abs((r.get("duration") or 0) - length_s) <= DURATION_TOLERANCE]
    ok.sort(key=lambda r: (not r.get("syncedLyrics"), not r.get("plainLyrics")))
    for r in ok:
        found = _from_record(r)
        if found:
            return found
    return {"status": "not_found", "lines": []}


class Lyrics:
    def __init__(self, publish):
        self._publish = publish
        self.want = False
        self._media = None
        self._key = None
        self._failed = (None, 0)   # (şarkı, yeniden deneme zamanı): çevrimdışıyken sunucuyu yormasın
        self._lock = threading.Lock()
        os.makedirs(CACHE, exist_ok=True)

    def _cache_path(self, key):
        return os.path.join(CACHE, hashlib.sha1(key.encode()).hexdigest() + ".json")

    def _cached(self, key):
        try:
            with open(self._cache_path(key)) as f:
                d = json.load(f)
            if d["status"] == "not_found" and time.time() - d.get("at", 0) > NOT_FOUND_RETRY:
                return None
            return d
        except Exception:
            return None

    def set_want(self, on):
        self.want = bool(on)
        if self.want:
            self._maybe_fetch()

    def on_media(self, media):
        self._media = media if media.get("active") else None
        if self._media is None:
            self._key = None
            self._publish({"track": "", "status": "none", "lines": []})
            return
        self._maybe_fetch()

    def _maybe_fetch(self):
        m = self._media
        if not self.want or m is None:
            return
        key = key_of(m)
        if key == self._key or (key == self._failed[0] and time.time() < self._failed[1]):
            return
        self._key = key
        hit = self._cached(key)
        if hit:
            self._publish({"track": key, "status": hit["status"], "lines": hit["lines"]})
            return
        self._publish({"track": key, "status": "loading", "lines": []})
        threading.Thread(target=self._fetch, args=(key, dict(m)), daemon=True).start()

    def _fetch(self, key, m):
        try:
            res = lookup(m)
            try:
                with open(self._cache_path(key), "w") as f:
                    json.dump({**res, "at": time.time()}, f, ensure_ascii=False)
            except OSError:
                pass
        except Exception as e:
            print("şarkı sözü alınamadı:", e, flush=True)
            res = {"status": "error", "lines": []}
            with self._lock:
                self._failed = (key, time.time() + 30)
                if self._key == key:
                    self._key = None   # 30 sn sonra yeniden denensin
        if self._media and key_of(self._media) == key:
            self._publish({"track": key, **res})
