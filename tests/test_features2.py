"""Doğrulama kodu, arayüz sesleri, ekran görüntüsü izleyicisi ve Hızlı Bakış arka ucu."""
import math
import os
import struct
import tempfile
import time
import unittest
import wave
from unittest import mock

from tests import helpers  # noqa: F401  (ortamı yalıtır)

import otp
import preview
import shots
import sounds

PNG_1x1 = (b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x01\x40\x00\x00\x00\xf0\x08\x06\x00\x00\x00"
           b"\x00\x00\x00\x00")           # başlık: 320 x 240 (gerisi önemsiz)


def put(path, data, mode="wb"):
    with open(path, mode) as f:
        f.write(data)


class OtpTest(unittest.TestCase):
    def test_codes_are_found(self):
        cases = {
            "Kodunuz: 482913. Kimseyle paylaşmayın.": "482913",
            "G-123456 is your Google verification code": "123456",
            "Your Uber code is 4821": "4821",
            "Doğrulama kodunuz 123 456": "123456",
            "Giriş kodu: 123-456": "123456",
            "Teslimat kodu 1234. Tutar 250 TL": "1234",
            "Bakiyeniz 1.250,00 TL. Güvenlik kodu: 7788": "7788",
            "Your PIN is 0042": "0042",
            "Code: AB12CD": "AB12CD",
            "PIN is 2026": "2026",
        }
        for text, want in cases.items():
            with self.subTest(text=text):
                self.assertEqual(otp.extract(text), want)

    def test_false_positives_are_rejected(self):
        for text in ("Hesabınıza 2500 TL yatırıldı", "Toplantı 2026 planı hazır", "Sipariş 123456 kargoya verildi",
                     "Your verification code is 12:45", "Kod yenilendi, 2026 yılı için geçerli",
                     "Your code is hello", "", "just words"):
            with self.subTest(text=text):
                self.assertEqual(otp.extract(text), "")

    def test_title_and_body_are_combined_and_pretty(self):
        self.assertEqual(otp.extract("Mesajlar", "Doğrulama kodunuz: 556677"), "556677")
        self.assertEqual(otp.pretty("556677"), "556 677")
        self.assertEqual(otp.pretty("4821"), "4821")


def goertzel(samples, freq, rate):
    """Tek bir frekanstaki enerji (FFT'siz)."""
    k = 2 * math.cos(2 * math.pi * freq / rate)
    s1 = s2 = 0.0
    for x in samples:
        s1, s2 = x + k * s1 - s2, s1
    return s1 * s1 + s2 * s2 - k * s1 * s2


class SoundsTest(unittest.TestCase):
    def setUp(self):
        self.old_cache = sounds.CACHE
        sounds.CACHE = tempfile.mkdtemp()

    def tearDown(self):
        sounds.CACHE = self.old_cache

    def test_every_sound_is_clean(self):
        for name in sounds.SOUNDS:
            with self.subTest(name=name):
                s = sounds.render(name)
                self.assertGreater(len(s), sounds.RATE * 0.05)
                self.assertLess(len(s), sounds.RATE * 2.0)                  # hepsi kısa
                self.assertAlmostEqual(max(abs(x) for x in s), sounds.PEAK, places=3)
                self.assertLess(abs(s[0]), 0.02)                            # başta/sonda tık yok
                self.assertLess(abs(s[-1]), 0.02)

    def test_notes_have_the_intended_pitch(self):
        # "copy" 1900 Hz, "done" 784 Hz ile başlar
        for name, freq, other in (("copy", 1900, 700), ("done", 784, 1500), ("palette", 700, 3000)):
            with self.subTest(name=name):
                s = sounds.render(name)[: int(0.06 * sounds.RATE)]
                self.assertGreater(goertzel(s, freq, sounds.RATE), 20 * goertzel(s, other, sounds.RATE))

    def test_wav_file_is_written_once_and_valid(self):
        p = sounds.ensure("notify")
        self.assertEqual(p, sounds.ensure("notify"))                        # yeniden üretmez
        with wave.open(p) as w:
            self.assertEqual((w.getnchannels(), w.getsampwidth(), w.getframerate()), (1, 2, sounds.RATE))
            data = struct.unpack("<%dh" % w.getnframes(), w.readframes(w.getnframes()))
        self.assertLessEqual(max(abs(x) for x in data), 32767)

    def test_rendering_is_deterministic(self):
        self.assertEqual(sounds.render("shot"), sounds.render("shot"))      # gürültü sabit tohumlu

    def test_setting_gates_playback_and_force_overrides(self):
        with mock.patch.object(sounds.subprocess, "Popen") as popen, \
                mock.patch.object(sounds.shutil, "which", return_value="/usr/bin/pw-play"):
            on = {"v": False}
            snd = sounds.Sounds(lambda: on["v"], lambda: 0.4)
            self.assertFalse(snd.play("copy"))                              # ayar kapalı
            self.assertFalse(snd.play("nope", force=True))                  # bilinmeyen ad
            self.assertTrue(snd.play("timer", force=True))                  # alarm her zaman
            on["v"] = True
            self.assertTrue(snd.play("copy"))
            self.assertFalse(snd.play("copy"))                              # çok sık: yok sayılır
            deadline = time.time() + 3
            while popen.call_count < 2 and time.time() < deadline:
                time.sleep(0.02)
            self.assertEqual(popen.call_count, 2)
            args = popen.call_args_list[0][0][0]
            self.assertEqual(args[0], "/usr/bin/pw-play")
            self.assertIn("--volume=0.40", args)


class ShotsTest(unittest.TestCase):
    def watcher(self, dirs, extra=()):
        """gi gerektirmeden: izleyicinin saf mantığı."""
        published = []
        s = object.__new__(shots.Shots)
        s._publish, s.seq, s.last, s._seen, s.monitors = published.append, 0, "", {}, []
        s.dirs = list(dirs)
        s.trusted = {os.path.realpath(d) for d in dirs if shots.DEDICATED_RE.search(os.path.basename(d))}
        s.trusted |= {os.path.realpath(d) for d in extra}
        return s, published

    def test_png_size_and_freshness(self):
        d = tempfile.mkdtemp()
        p = os.path.join(d, "a.png")
        with open(p, "wb") as f:
            f.write(PNG_1x1)
        self.assertEqual(shots.image_size(p), (320, 240))
        self.assertTrue(shots.is_fresh_image(p))
        os.utime(p, (time.time() - 60, time.time() - 60))
        self.assertFalse(shots.is_fresh_image(p))                           # eski dosya
        txt = os.path.join(d, "n.txt")
        put(txt, "x", "w")
        self.assertFalse(shots.is_fresh_image(txt))
        self.assertFalse(shots.is_fresh_image(os.path.join(d, ".gizli.png")))

    def test_dedicated_folder_accepts_any_image(self):
        d = os.path.join(tempfile.mkdtemp(), "Ekran Görüntüleri")
        os.makedirs(d)
        w, published = self.watcher([d])
        p = os.path.join(d, "x.png")
        put(p, PNG_1x1)
        self.assertTrue(w.handle(p))
        self.assertEqual((published[0]["seq"], published[0]["w"], published[0]["h"]), (1, 320, 240))
        self.assertTrue(published[0]["url"].startswith("file:///"))
        self.assertFalse(w.handle(p))                                       # aynı dosya hemen tekrar sayılmaz

    def test_ordinary_folder_needs_a_screenshot_like_name(self):
        d = tempfile.mkdtemp()                                              # "İndirilenler" gibi sıradan klasör
        w, published = self.watcher([d])
        junk, shot = os.path.join(d, "foto.png"), os.path.join(d, "Ekran Görüntüsü_2026.png")
        for p in (junk, shot):
            put(p, PNG_1x1)
        self.assertFalse(w.handle(junk))                                    # indirilen resim önizleme açmaz
        self.assertTrue(w.handle(shot))

    def test_user_given_folder_is_trusted(self):
        d = tempfile.mkdtemp()
        w, _ = self.watcher([d], extra=[d])
        p = os.path.join(d, "foto.png")
        put(p, PNG_1x1)
        self.assertTrue(w.handle(p))

    def test_directory_discovery_from_spectacle_config(self):
        home = tempfile.mkdtemp()
        shotdir = os.path.join(home, "Resimler", "Ekran Görüntüleri")
        os.makedirs(shotdir)
        rc = os.path.join(home, "spectaclerc")
        put(rc, "[ImageSave]\nlastImageSaveLocation=file://%s/a.png\n" % shotdir.replace(" ", "%20"), "w")
        self.assertIn(os.path.realpath(shotdir), shots.candidate_dirs(home=home, rc=rc))


class PreviewTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.old_cache = preview.CACHE
        preview.CACHE = os.path.join(self.dir, "cache")

    def tearDown(self):
        preview.CACHE = self.old_cache

    def write(self, name, data, mode="wb"):
        p = os.path.join(self.dir, name)
        with open(p, mode) as f:
            f.write(data)
        return p

    def test_kinds_and_basic_info(self):
        text = self.write("n.py", "print('merhaba')\n" * 5, "w")
        d = preview.info(text)
        self.assertEqual((d["kind"], d["name"]), ("text", "n.py"))
        self.assertIn("merhaba", d["text"])
        self.assertTrue(d["url"].startswith("file:///"))

        d = preview.info(self.write("r.png", PNG_1x1))
        self.assertEqual((d["kind"], d["meta"]), ("image", "320 × 240"))

        d = preview.info(self.dir)
        self.assertEqual(d["kind"], "folder")
        self.assertGreaterEqual(d["count"], 2)

        self.assertEqual(preview.info(os.path.join(self.dir, "yok"))["error"], "missing")

    def test_binary_files_are_not_shown_as_text(self):
        d = preview.info(self.write("veri.log", b"abc\x00\x01\x02" * 200))
        self.assertEqual(d["kind"], "other")
        self.assertEqual(d["text"], "")

    def test_long_text_is_cut(self):
        d = preview.info(self.write("uzun.txt", "satır\n" * 2000, "w"))
        self.assertTrue(d["cut"])
        self.assertLessEqual(len(d["text"]), preview.TEXT_BYTES)

    def test_human_sizes_and_durations(self):
        self.assertEqual(preview.human_size(512), "512 B")
        self.assertEqual(preview.human_size(1536), "1.5 KB")
        self.assertEqual(preview.human_size(5 * 1024 * 1024), "5 MB")
        self.assertEqual(preview.duration_text(65), "1:05")
        self.assertEqual(preview.duration_text(3725), "1:02:05")

    @unittest.skipUnless(preview.shutil.which("pdftoppm"), "poppler yok")
    def test_pdf_first_page_thumbnail(self):
        # en küçük geçerli PDF (tek boş sayfa)
        pdf = (b"%PDF-1.1\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n"
               b"3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 300]>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF")
        d = preview.info(self.write("k.pdf", pdf))
        self.assertEqual(d["kind"], "pdf")
        if d["thumb"]:                                   # bozuk-ama-okunabilir PDF'yi poppler kabul etmeyebilir
            self.assertTrue(os.path.exists(d["thumb"][len("file://"):]))

    def test_thumbnail_cache_is_pruned(self):
        os.makedirs(preview.CACHE)
        for i in range(preview.KEEP + 15):
            p = os.path.join(preview.CACHE, "%03d.png" % i)
            put(p, b"x")
            os.utime(p, (1000 + i, 1000 + i))
        preview._prune()
        left = os.listdir(preview.CACHE)
        self.assertEqual(len(left), preview.KEEP)
        self.assertIn("%03d.png" % (preview.KEEP + 14), left)       # en yeniler kalır
        self.assertNotIn("000.png", left)

    def test_previewable_path_validation(self):
        self.assertTrue(preview.is_previewable_path(self.dir))
        self.assertFalse(preview.is_previewable_path("relative/path"))
        self.assertFalse(preview.is_previewable_path("/yok/dosya"))
        self.assertFalse(preview.is_previewable_path(None))


if __name__ == "__main__":
    unittest.main()
