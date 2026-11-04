"""Şarkı sözü bulma: başlık temizliği, aday puanlama, yedek yollar, hata ayrımı, önbellek."""
import json
import os
import tempfile
import time
import unittest

from tests import helpers  # noqa: F401  (ortamı yalıtır)

import lyrics
from lyrics import LyricsNetworkError, clean_artist, clean_title, lookup, norm, sim, split_title


def rec(rid, track, artist, dur, synced=True, plain=True, album=""):
    return {"id": rid, "trackName": track, "artistName": artist, "albumName": album, "duration": dur,
            "instrumental": False,
            "syncedLyrics": "[00:01.00] %s bir\n[00:05.00] iki\n[00:09.50] üç" % track if synced else None,
            "plainLyrics": "%s bir\niki\nüç" % track if plain else None}


class FakeLrclib:
    """LRCLIB'in davranışının kabaca taklidi: get = tam eşleşme (süre ±2 sn), search = bulanık içerir."""

    def __init__(self, records=(), busy=(), offline=False):
        self.records, self.busy, self.offline, self.calls = list(records), set(busy), offline, []

    def __call__(self, kind, params):
        self.calls.append((kind, dict(params)))
        if self.offline or kind in self.busy:
            raise LyricsNetworkError("meşgul")
        if kind == "get":
            tn, an, dur = norm(params.get("track_name")), norm(params.get("artist_name")), params.get("duration")
            for r in self.records:
                if norm(r["trackName"]) == tn and norm(r["artistName"]) == an and (dur is None or abs(r["duration"] - dur) <= 2):
                    return r
            return None
        q, tn, an = norm(params.get("q", "")), norm(params.get("track_name", "")), norm(params.get("artist_name", ""))
        out = []
        for r in self.records:
            hay = norm(r["trackName"]) + " " + norm(r["artistName"])
            if q and not all(tok in hay for tok in q.split()):
                continue
            if tn and tn not in norm(r["trackName"]):
                continue
            if an and an not in norm(r["artistName"]):
                continue
            out.append(r)
        return out[:20]


def media(title, artist="", length=200, album="", url=""):
    return {"title": title, "artist": artist, "album": album, "length": length * 1000, "url": url}


class TextCleaningTest(unittest.TestCase):
    def test_clean_title(self):
        cases = {
            "Let It Be - Remastered 2009": "Let It Be",
            "Let It Be (Remastered 2009)": "Let It Be",
            "Bohemian Rhapsody - 2011 Mix": "Bohemian Rhapsody",
            "Levitating (feat. DaBaby)": "Levitating",
            "Levitating feat. DaBaby": "Levitating",
            "Song Name [Official Video]": "Song Name",
            "Song Name (Live at Wembley)": "Song Name",
            "Hey Jude - Radio Edit": "Hey Jude",
            "Blinding Lights - Single Version": "Blinding Lights",
            "(I Can't Get No) Satisfaction": "(I Can't Get No) Satisfaction",   # gerçek parantez korunur
            "Smells Like Teen Spirit": "Smells Like Teen Spirit",
            "Hold On - Pt. 2": "Hold On - Pt. 2",
            "Lovers Rock (Remix)": "Lovers Rock (Remix)",                        # remix ayrı bir kayıt olabilir
            "Live": "Live",                                                      # tamamı "gürültü" ise boş bırakma
        }
        for raw, want in cases.items():
            with self.subTest(raw=raw):
                self.assertEqual(clean_title(raw), want)

    def test_artists(self):
        self.assertEqual(clean_artist("TV Girl - Topic"), "TV Girl")
        self.assertEqual(clean_artist("TVGirlVEVO"), "TVGirl")
        self.assertEqual(lyrics.artist_variants("Dua Lipa, DaBaby"), ["Dua Lipa, DaBaby", "Dua Lipa"])
        self.assertEqual(lyrics.artist_variants("Queen"), ["Queen"])
        self.assertEqual(lyrics.artist_variants(""), [])

    def test_title_split_and_similarity(self):
        self.assertEqual(split_title("TV Girl - Lovers Rock (Official Audio)"), ("TV Girl", "Lovers Rock"))
        self.assertIsNone(split_title("Lovers Rock"))
        self.assertEqual(norm("DÖNENCE!"), "donence")
        self.assertEqual(sim("Dönence", "DONENCE"), 1.0)
        self.assertGreater(sim("The Beatles", "Beatles"), 0.9)
        self.assertLess(sim("Savoir Adore", "Mapa"), 0.4)
        # gerçek yazım varyantları eşiğin rahatça üstünde, kısa farklı adlar altında kalmalı
        for a, b in (("TV Girl", "TVGirl"), ("AC/DC", "ACDC"), ("Jay-Z", "JAY Z"), ("Sezen Aksu", "SEZEN AKSU")):
            self.assertGreaterEqual(sim(a, b), lyrics.ARTIST_MIN + 0.2, (a, b))
        self.assertLess(sim("Sade", "Savoir Adore"), lyrics.ARTIST_MIN)


class LookupTest(unittest.TestCase):
    DB = [
        rec(1, "Dreamers", "Savoir Adore", 215),
        rec(2, "Dreamers", "Mapa", 180),                         # aynı ad, başka sanatçı
        rec(3, "Dreamers", "Mohombi", 219),
        rec(4, "Let It Be", "The Beatles", 243),
        rec(5, "Levitating", "Dua Lipa", 203),
        rec(6, "Lovers Rock", "TV Girl", 213),
        rec(7, "Dönence", "Sezen Aksu", 251),
        rec(8, "Bohemian Rhapsody", "Queen", 354),
    ]

    def find(self, m, records=None, **kw):
        api = FakeLrclib(self.DB if records is None else records, **kw)
        return lookup(m, get=api), api

    def test_exact_match_stops_after_one_request(self):
        res, api = self.find(media("Dreamers", "Savoir Adore", 215))
        self.assertEqual(res["status"], "synced")
        self.assertEqual(res["match"], "Savoir Adore – Dreamers")
        self.assertEqual(len(api.calls), 1)

    def test_decoys_with_the_same_title_are_rejected(self):
        res, _ = self.find(media("Dreamers", "Sade", 215))
        self.assertEqual(res["status"], "not_found")
        res, _ = self.find(media("Dreamers", "Savoir Adore", 215), records=[self.DB[1], self.DB[2]])
        self.assertEqual(res["status"], "not_found")

    def test_remaster_and_feat_noise(self):
        for title, artist, length, want in (
                ("Let It Be - Remastered 2009", "The Beatles", 243, "The Beatles – Let It Be"),
                ("Let It Be (Remastered 2009)", "The Beatles", 243, "The Beatles – Let It Be"),
                ("Levitating (feat. DaBaby)", "Dua Lipa, DaBaby", 203, "Dua Lipa – Levitating"),
                ("Bohemian Rhapsody - 2011 Mix", "Queen", 354, "Queen – Bohemian Rhapsody")):
            with self.subTest(title=title):
                res, _ = self.find(media(title, artist, length))
                self.assertEqual(res.get("match"), want)

    def test_remaster_in_the_catalogue_title_too(self):
        db = [rec(9, "Let It Be (Remastered 2009)", "The Beatles", 243)]
        res, _ = self.find(media("Let It Be - Remastered 2009", "The Beatles", 243), records=db)
        self.assertEqual(res["status"], "synced")

    def test_youtube_style_titles(self):
        for title, artist in (("TV Girl - Lovers Rock (Official Audio)", "TVGirlVEVO"),
                              ("TV Girl - Lovers Rock", "TV Girl - Topic"),
                              ("TV Girl - Lovers Rock", "")):
            with self.subTest(title=title, artist=artist):
                res, _ = self.find(media(title, artist, 213))
                self.assertEqual(res.get("match"), "TV Girl – Lovers Rock")

    def test_turkish_characters_and_case(self):
        res, _ = self.find(media("DÖNENCE", "sezen aksu", 251))
        self.assertEqual(res.get("match"), "Sezen Aksu – Dönence")

    def test_missing_artist_still_finds_a_unique_title(self):
        res, _ = self.find(media("Lovers Rock", "", 213))
        self.assertEqual(res.get("match"), "TV Girl – Lovers Rock")

    def test_duration_tolerance(self):
        db = [rec(1, "Song", "Band", 221)]
        self.assertEqual(self.find(media("Song", "Band", 215), records=db)[0]["status"], "synced")        # 6 sn: gevşek kabul
        self.assertEqual(self.find(media("Song", "Band", 200), records=db)[0]["status"], "not_found")     # 21 sn: eleme
        self.assertEqual(self.find(media("Song", "Band", 0), records=db)[0]["status"], "synced")          # süre bilinmiyor

    def test_prefers_tight_duration_and_synced(self):
        db = [rec(1, "Song", "Band", 224, synced=False), rec(2, "Song", "Band", 218), rec(3, "Song", "Band", 215, synced=False)]
        res, _ = self.find(media("Song", "Band", 216, album="x"), records=db, busy=("get",))
        self.assertEqual(res["status"], "synced")
        self.assertEqual(res["match"], "Band – Song")

    def test_plain_lyrics_are_used_when_no_synced(self):
        res, _ = self.find(media("Song", "Band", 200), records=[rec(1, "Song", "Band", 200, synced=False)])
        self.assertEqual(res["status"], "plain")
        self.assertEqual(res["lines"][0], [-1, "Song bir"])

    def test_instrumental(self):
        db = [{"id": 1, "trackName": "Intro", "artistName": "Band", "duration": 60, "instrumental": True,
               "syncedLyrics": None, "plainLyrics": None}]
        res, _ = self.find(media("Intro", "Band", 60), records=db)
        self.assertEqual(res["status"], "instrumental")

    def test_a_busy_endpoint_does_not_stop_the_search(self):
        res, api = self.find(media("Dreamers", "Savoir Adore", 215), busy=("get",))      # get 503 verir, search çalışır
        self.assertEqual(res["status"], "synced")
        self.assertTrue(any(k == "search" for k, _ in api.calls))

    def test_offline_is_an_error_not_a_miss(self):
        api = FakeLrclib(self.DB, offline=True)
        with self.assertRaises(LyricsNetworkError):
            lookup(media("Dreamers", "Savoir Adore", 215), get=api)
        self.assertLessEqual(len(api.calls), lyrics.MAX_FAILS)                         # çevrimdışıyken sunucuyu yormaz

    def test_not_found_is_cheap_and_bounded(self):
        res, api = self.find(media("Olmayan Şarkı Adı", "Kimse", 200), records=[])
        self.assertEqual(res["status"], "not_found")
        self.assertLessEqual(len(api.calls), 9)

    def test_too_long_or_untitled_makes_no_requests(self):
        for m in (media("Mix", "DJ", 4000), media("", "DJ", 200)):
            res, api = self.find(m)
            self.assertEqual(res["status"], "not_found")
            self.assertEqual(api.calls, [])

    def test_sidecar_lrc_next_to_the_file(self):
        d = tempfile.mkdtemp()
        song = os.path.join(d, "Şarkı Adı.mp3")
        with open(os.path.join(d, "Şarkı Adı.lrc"), "w", encoding="utf-8") as f:
            f.write("[00:01.00]bir\n[00:03.00]iki\n[00:05.50]üç\n")

        def never(*_a):
            raise AssertionError("ağa çıkılmamalıydı")

        res = lookup(media("Whatever", "Anyone", 200, url="file://" + song.replace(" ", "%20")), get=never)
        self.assertEqual((res["status"], len(res["lines"]), res["match"]), ("synced", 3, "Şarkı Adı.lrc"))
        self.assertEqual(res["lines"][2], [5500, "üç"])


class ManualSearchTest(unittest.TestCase):
    def test_picks_synced_closest_in_duration(self):
        db = [rec(1, "Song", "A", 180, synced=False), rec(2, "Song", "B", 190), rec(3, "Song", "C", 212)]
        res = lyrics.lookup_manual("song", 210, get=FakeLrclib(db))
        self.assertEqual(res["match"], "C – Song")

    def test_nothing_usable(self):
        self.assertEqual(lyrics.lookup_manual("yok", 0, get=FakeLrclib([]))["status"], "not_found")


class CacheAndFlowTest(unittest.TestCase):
    def setUp(self):
        self.old = lyrics.CACHE
        lyrics.CACHE = tempfile.mkdtemp()
        self.out = []
        self.l = lyrics.Lyrics(self.out.append)
        self.m = dict(media("Song", "Band", 200), active=True)
        self.key = lyrics.key_of(self.m)

    def tearDown(self):
        lyrics.CACHE = self.old

    def put(self, d):
        with open(self.l._cache_path(self.key), "w") as f:
            json.dump(d, f)

    def test_old_misses_are_searched_again_but_hits_are_kept(self):
        self.put({"status": "not_found", "lines": [], "at": time.time()})                  # eski sürüm (v yok)
        self.assertIsNone(self.l._cached(self.key))
        self.put({"status": "not_found", "lines": [], "at": time.time(), "v": lyrics.CACHE_VERSION})
        self.assertEqual(self.l._cached(self.key)["status"], "not_found")
        self.put({"status": "not_found", "lines": [], "at": time.time() - 8 * 86400, "v": lyrics.CACHE_VERSION})
        self.assertIsNone(self.l._cached(self.key))                                         # bir haftayı geçti
        self.put({"status": "synced", "lines": [[0, "x"]]})                                 # bulunanlar hep geçerli
        self.assertEqual(self.l._cached(self.key)["status"], "synced")

    def test_network_failure_publishes_error_and_is_not_cached(self):
        old = lyrics.lookup
        lyrics.lookup = lambda m: (_ for _ in ()).throw(LyricsNetworkError("503"))
        try:
            self.l._media = self.m
            self.l._fetch(self.key, dict(self.m), None)
        finally:
            lyrics.lookup = old
        self.assertEqual(self.out[-1]["status"], "error")
        self.assertFalse(os.path.exists(self.l._cache_path(self.key)))
        self.assertEqual(self.l._failed[0], self.key)

    def test_manual_result_is_cached_for_the_track(self):
        old = lyrics.lookup_manual
        lyrics.lookup_manual = lambda q, length, get=None: {"status": "synced", "lines": [[0, "elle"]], "match": "X – Y"}
        try:
            self.l._media = self.m
            self.l._fetch(self.key, dict(self.m), "x y")
        finally:
            lyrics.lookup_manual = old
        self.assertEqual(self.out[-1]["match"], "X – Y")
        self.assertEqual(self.l._cached(self.key)["lines"], [[0, "elle"]])

    def test_failed_manual_search_does_not_overwrite_a_good_cache(self):
        self.put({"status": "synced", "lines": [[0, "eski"]]})
        old = lyrics.lookup_manual
        lyrics.lookup_manual = lambda q, length, get=None: {"status": "not_found", "lines": []}
        try:
            self.l._media = self.m
            self.l._fetch(self.key, dict(self.m), "bulunamaz")
        finally:
            lyrics.lookup_manual = old
        self.assertEqual(self.l._cached(self.key)["lines"], [[0, "eski"]])


if __name__ == "__main__":
    unittest.main()
