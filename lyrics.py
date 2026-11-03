"""Senkron şarkı sözleri: LRCLIB (https://lrclib.net), ücretsiz ve anahtarsız.

Yalnızca söz görünümü açıkken sorulur; sonuç diskte saklanır (her şarkı bir kez, sözü olmayan
şarkı haftada bir yeniden sorulur). Bağlantı hataları saklanmaz.

Bulma sırası (ilk "iyi" sonuçta durur):
  0. Şarkının yanındaki .lrc dosyası (yerel oynatıcılar; ağ yok)
  1. Tam eşleşme (get): ham başlık + sanatçı + albüm + süre
  2. Temizlenmiş başlık ("- Remastered 2011", "(feat. X)", "[Official Video]" atılır) ve ilk sanatçı
  3. Arama: ham, temizlenmiş, serbest metin (q), yalnız başlık
  4. YouTube tarzı "Sanatçı - Şarkı" başlıkları ayrıştırılır
Arama sonuçları başlık/sanatçı benzerliği ve süreyle puanlanır; sanatçısı tutmayan ("Dreamers" adlı
başka şarkı) ya da süresi çok farklı sonuçlar elenir. Bir uç meşgulse (503) öbürleri denenir.
"""
import difflib
import hashlib
import json
import os
import re
import threading
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request

API = "https://lrclib.net/api"
UA = "dynamic-island/1.0 (KDE Plasma)"
CACHE = os.path.expanduser("~/.cache/dynamic-island/lyrics")
CACHE_VERSION = 2             # arttırılınca eski "bulunamadı" kayıtları yeniden aranır
NOT_FOUND_RETRY = 7 * 86400
LONGEST = 3600                # LRCLIB daha uzununu reddeder (mix, podcast, yayın)
TIGHT, LOOSE = 3, 9           # saniye: süre farkı sınırları (sıkı / gevşek)
ARTIST_MIN = 0.62             # sanatçı benzerliği alt sınırı (varyantlar: "TV Girl"/"TVGirl", "AC/DC" ≥ 0,89)
MAX_FAILS = 3                 # hiç yanıt alınamadan bu kadar hata: çevrimdışı say

LRC_RE = re.compile(r"\[(\d+):(\d+(?:\.\d+)?)\]")


class LyricsNetworkError(Exception):
    """Sunucuya ulaşılamadı ya da meşgul (kalıcı bir "yok" cevabı değil)."""


# --------------------------------------------------------------------------- biçim

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


# --------------------------------------------------------------------------- metin temizliği

_TR = str.maketrans({"ı": "i", "İ": "i", "ş": "s", "Ş": "s", "ğ": "g", "Ğ": "g",
                     "ü": "u", "Ü": "u", "ö": "o", "Ö": "o", "ç": "c", "Ç": "c"})


def norm(s):
    """Karşılaştırma için: küçük harf, aksansız, noktalamasız, tek boşluk ("Dönence!" -> "donence")."""
    s = str(s or "").translate(_TR).lower().replace("&", " and ")
    s = "".join(c for c in unicodedata.normalize("NFKD", s) if not unicodedata.combining(c))
    return " ".join(re.sub(r"[^\w\s]", " ", s).split())


# şarkıyı tanımlamayan "süs" sözcükleri: parantez içinde ya da " - " ile sonda geliyorlarsa atılır
NOISE = re.compile(
    r"\b(?:re-?master(?:ed)?|mono|stereo|version|ver|edit|mix|live|acoustic|session|official|video|audio|"
    r"lyrics?|visuali[sz]er|mv|hd|hq|4k|explicit|clean|bonus|deluxe|expanded|anniversary|single|album|"
    r"radio|extended|original|feat|ft|featuring|with|prod|karaoke|demo|from|soundtrack|ost|"
    r"slowed|reverb|sped up|8d|remaster)\b", re.I)
_BRACKETS = re.compile(r"[\(\[\{]([^()\[\]{}]*)[\)\]\}]")
_SEPARATORS = re.compile(r"\s+[-–—|]\s+")


def clean_title(title):
    """"Let It Be - Remastered 2009" -> "Let It Be"; "Levitating (feat. DaBaby)" -> "Levitating"."""
    t = " ".join(str(title or "").split())
    t = _BRACKETS.sub(lambda m: " " if NOISE.search(m.group(1)) else m.group(0), t)
    t = re.split(r"\s+(?:feat\.?|ft\.?|featuring)\s+", t, maxsplit=1, flags=re.I)[0]
    parts = _SEPARATORS.split(t)
    while len(parts) > 1 and NOISE.search(parts[-1]):
        parts.pop()
    t = " - ".join(parts)
    t = " ".join(t.split()).strip(" -–—|")
    return t or " ".join(str(title or "").split())


def clean_artist(artist):
    a = " ".join(str(artist or "").split())
    a = re.sub(r"\s*[-–—]\s*topic$", "", a, flags=re.I)
    a = re.sub(r"\s*vevo$", "", a, flags=re.I)
    return a.strip(" -–—,;")


_ARTIST_SPLIT = re.compile(r"\s*(?:,|;|/|\bfeat\.?|\bft\.?|\bfeaturing\b|\bx\b|&|\band\b|\bwith\b|\bve\b)\s*", re.I)


def artist_variants(artist):
    """Tam ad ve ilk sanatçı: "Dua Lipa, DaBaby" -> ["Dua Lipa, DaBaby", "Dua Lipa"]."""
    full = clean_artist(artist)
    if not full:
        return []
    first = _ARTIST_SPLIT.split(full)[0].strip()
    return [full] + ([first] if first and first != full else [])


def split_title(title):
    """YouTube tarzı "Sanatçı - Şarkı (Official Audio)" -> (sanatçı, şarkı); yoksa None."""
    parts = _SEPARATORS.split(" ".join(str(title or "").split()), maxsplit=1)
    if len(parts) != 2 or not parts[0].strip() or not parts[1].strip():
        return None
    left, right = clean_artist(parts[0]), clean_title(parts[1])
    return (left, right) if left and right else None


def sim(a, b):
    """0..1 benzerlik (normalleştirilmiş metinler üzerinde)."""
    a, b = norm(a), norm(b)
    if not a or not b:
        return 0.0
    if a == b:
        return 1.0
    if min(len(a), len(b)) >= 4 and (a in b or b in a):
        return 0.92
    return difflib.SequenceMatcher(None, a, b).ratio()


# --------------------------------------------------------------------------- aday seçimi

def grade(rec, want):
    """Aday kayıt için (puan, süre farkı) ya da elenirse None."""
    if not (rec.get("syncedLyrics") or rec.get("plainLyrics") or rec.get("instrumental")):
        return None
    tsim = max((sim(rec.get("trackName"), t) for t in want["titles"]), default=0.0)
    if tsim < 0.72:
        return None
    if want["artists"]:
        asim = max(sim(rec.get("artistName"), a) for a in want["artists"])
        if asim < ARTIST_MIN:       # "Sade" ≈ "Savoir Adore" (0,50) gibi kısa adlar yanlış eşleşmesin
            return None
        artist_part = 1.6 * asim
    else:
        artist_part = 0.8
    dur_part, diff = 0.0, None
    if want["length"] > 0 and rec.get("duration"):
        diff = abs(rec["duration"] - want["length"])
        if diff <= 1:
            dur_part = 1.2
        elif diff <= TIGHT:
            dur_part = 1.0
        elif diff <= LOOSE:
            dur_part = 0.4
        else:
            return None
    synced = 0.6 if rec.get("syncedLyrics") else (0.1 if rec.get("plainLyrics") else 0.3)
    return 3.0 * tsim + artist_part + dur_part + synced, diff


def local_lrc(url):
    """Şarkının yanındaki aynı adlı .lrc dosyası (yerel oynatıcılar için)."""
    if not url or not str(url).startswith("file://"):
        return None
    path = urllib.parse.unquote(urllib.parse.urlparse(url).path)
    stem = os.path.splitext(path)[0]
    for ext in (".lrc", ".LRC", ".Lrc"):
        try:
            if os.path.getsize(stem + ext) > 400_000:
                continue
            with open(stem + ext, encoding="utf-8", errors="replace") as f:
                lines = parse_lrc(f.read())
        except OSError:
            continue
        if len(lines) >= 2:
            return {"status": "synced", "lines": lines, "match": os.path.basename(stem + ext)}
    return None


def plan(m):
    """Sırayla denenecek (uç, parametreler) listesi."""
    title, artist, album = m.get("title", "").strip(), m.get("artist", "").strip(), m.get("album", "").strip()
    length = m.get("length", 0) / 1000
    ct = clean_title(title)
    arts = artist_variants(artist)
    a0 = arts[0] if arts else ""
    steps = []

    def add(kind, **params):
        params = {k: v for k, v in params.items() if v not in ("", None)}
        if (kind, params) not in steps:
            steps.append((kind, params))

    dur = round(length) if length > 0 else None
    if artist:
        add("get", track_name=title, artist_name=artist, album_name=album, duration=dur)
        add("get", track_name=ct, artist_name=a0, duration=dur)
        add("search", track_name=title, artist_name=artist)
        add("search", track_name=ct, artist_name=a0)
    add("search", q=" ".join(x for x in (ct, a0) if x))
    if len(arts) > 1:
        add("search", track_name=ct, artist_name=arts[1])
    add("search", track_name=ct)
    parsed = split_title(title)
    if parsed:
        add("search", track_name=parsed[1], artist_name=parsed[0])
        add("search", q=" ".join(parsed))
    return steps


def lookup(m, get=None):
    """Şarkı için en iyi sözleri bulur: {"status", "lines", "match"?}. Hiçbir uca ulaşılamazsa
    LyricsNetworkError (kalıcı olarak "yok" denmez)."""
    get = get or _http_get
    title = m.get("title", "").strip()
    length_s = m.get("length", 0) / 1000
    if not title or length_s > LONGEST:
        return {"status": "not_found", "lines": []}
    local = local_lrc(m.get("url", ""))
    if local:
        return local

    parsed = split_title(title)
    want = {
        "titles": list(dict.fromkeys(t for t in (title, clean_title(title)) + ((parsed[1],) if parsed else ()) if t)),
        "artists": list(dict.fromkeys(artist_variants(m.get("artist", "")) + ([parsed[0]] if parsed else []))),
        "length": length_s,
    }
    best, best_score, seen = None, 0.0, set()
    ok = fails = 0
    for kind, params in plan(m):
        try:
            data = get(kind, params)
            ok += 1
        except LyricsNetworkError:
            fails += 1
            if ok == 0 and fails >= MAX_FAILS:
                raise
            continue
        records = [data] if isinstance(data, dict) else (data or [])
        for rec in records:
            rid = rec.get("id") or (rec.get("trackName"), rec.get("artistName"), rec.get("duration"))
            if rid in seen:
                continue
            seen.add(rid)
            g = grade(rec, want)
            if g and g[0] > best_score:
                best, best_score = rec, g[0]
                # tam isabet: tam eşleşme, sıkı süre, senkronlu → daha fazla istek yapma
                if kind == "get" or (g[1] is not None and g[1] <= TIGHT and rec.get("syncedLyrics") and g[0] >= 6.0):
                    break
        else:
            continue
        break
    if best:
        res = _from_record(best)
        if res:
            res["match"] = "%s – %s" % (best.get("artistName", ""), best.get("trackName", ""))
            return res
    if ok == 0:
        raise LyricsNetworkError("LRCLIB'e ulaşılamadı")
    return {"status": "not_found", "lines": []}


def lookup_manual(q, length_s=0, get=None):
    """Elle yazılan arama: sonuçlardan senkronluyu (ve süreye yakını) al; eleme yapma."""
    get = get or _http_get
    results = get("search", {"q": q}) or []
    usable = [r for r in results if _from_record(r)]
    if not usable:
        return {"status": "not_found", "lines": []}

    def order(r):
        diff = abs((r.get("duration") or 0) - length_s) if length_s > 0 else 0
        return (not r.get("syncedLyrics"), diff)

    best = min(usable, key=order)
    res = _from_record(best)
    res["match"] = "%s – %s" % (best.get("artistName", ""), best.get("trackName", ""))
    return res


def _http_get(kind, params):
    """LRCLIB isteği. 404 -> None; meşgul (429/503…) kısa beklemeyle yeniden denenir, sonra LyricsNetworkError."""
    url = "%s/%s?%s" % (API, kind, urllib.parse.urlencode(params))
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=8) as r:
                return json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            if e.code in (429, 502, 503, 504) and attempt < 2:
                try:
                    wait = int(e.headers.get("Retry-After") or 1)
                except (TypeError, ValueError):
                    wait = 1
                time.sleep(min(3, max(1, wait)))
                continue
            raise LyricsNetworkError("HTTP %d" % e.code) from e
        except (urllib.error.URLError, TimeoutError, OSError, ValueError) as e:
            raise LyricsNetworkError(str(e)) from e


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
            if d["status"] == "not_found" and (time.time() - d.get("at", 0) > NOT_FOUND_RETRY
                                               or d.get("v", 1) < CACHE_VERSION):
                return None            # eski/yetersiz aramayla bulunamadı denmiş: yeniden ara
            return d
        except Exception:
            return None

    def _store(self, key, res):
        try:
            with open(self._cache_path(key), "w") as f:
                json.dump({**res, "at": time.time(), "v": CACHE_VERSION}, f, ensure_ascii=False)
        except OSError:
            pass

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
            self._publish({"track": key, "status": hit["status"], "lines": hit["lines"], "match": hit.get("match", "")})
            return
        self._publish({"track": key, "status": "loading", "lines": []})
        threading.Thread(target=self._fetch, args=(key, dict(m), None), daemon=True).start()

    def manual(self, query):
        """Kullanıcı elle arama yazdı: bu şarkı için sonucu al ve sakla (sonraki açılışlarda otomatik)."""
        q = " ".join(str(query or "").split())[:120]
        m = self._media
        if not q or m is None:
            return
        key = key_of(m)
        self._key = key
        self._publish({"track": key, "status": "loading", "lines": []})
        threading.Thread(target=self._fetch, args=(key, dict(m), q), daemon=True).start()

    def _fetch(self, key, m, manual):
        try:
            res = lookup_manual(manual, m.get("length", 0) / 1000) if manual else lookup(m)
            if res["status"] != "not_found" or not manual:
                self._store(key, res)
        except LyricsNetworkError as e:
            print("şarkı sözü alınamadı:", e, flush=True)
            res = {"status": "error", "lines": []}
            with self._lock:
                self._failed = (key, time.time() + 30)
                if self._key == key:
                    self._key = None   # 30 sn sonra yeniden denensin
        except Exception as e:
            print("şarkı sözü hatası:", e, flush=True)
            res = {"status": "error", "lines": []}
        if self._media and key_of(self._media) == key:
            self._publish({"track": key, **res})
