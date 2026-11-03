import math
import os
import tempfile
import unittest

from tests import helpers  # noqa: F401  (ortamı yalıtır)

import apps
import palette
import spectrum

DESKTOP = """[Desktop Entry]
Type=Application
Name=Visual Studio Code
Name[tr]=Görsel Stüdyo
GenericName=Text Editor
Keywords=code;editor;
Icon=vscode
"""


class ScoreTest(unittest.TestCase):
    def test_fold_turkish(self):
        self.assertEqual(palette.fold("Çalışma İŞİ Ğüö"), "calisma isi guo")

    def test_ranking(self):
        s = palette.score
        self.assertEqual(s("firefox", "Firefox"), 100)
        self.assertGreater(s("fire", "Firefox"), s("fox", "Firefox"))          # baştan > içerir
        self.assertGreater(s("stu", "Visual Studio Code"), s("dio", "Visual Studio Code"))   # kelime başı
        self.assertGreaterEqual(s("vsc", "Visual Studio Code"), 70)            # baş harfler
        self.assertGreater(s("calis", "Çalışma Alanı"), 80)                    # Türkçe duyarsız
        self.assertGreater(s("ffx", "firefox"), 0)                             # sırayla harfler
        self.assertEqual(s("fxf", "firefox"), 0)                               # sıra bozuksa yok
        self.assertEqual(s("zzz", "Firefox"), 0)


class PaletteAppsTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        with open(os.path.join(self.dir, "code.desktop"), "w") as f:
            f.write(DESKTOP)
        with open(os.path.join(self.dir, "hidden.desktop"), "w") as f:
            f.write(DESKTOP.replace("Icon=vscode", "NoDisplay=true"))
        self.old = apps.DIRS
        apps.DIRS = [self.dir]
        palette.STATE = os.path.join(self.dir, "palette.json")
        self.p = palette.Palette(dbus=False)

    def tearDown(self):
        apps.DIRS = self.old

    def test_search_by_name_generic_keyword(self):
        for q in ("visual", "vsc", "text editor", "code"):
            with self.subTest(q=q):
                r = self.p.search_apps(q)
                self.assertEqual([x["id"] for x in r], ["code"])
                self.assertEqual(r[0]["icon"], "vscode")

    def test_nodisplay_is_skipped(self):
        self.assertNotIn("hidden", [e["id"] for e in self.p._index()])

    def test_usage_boost_and_suggestions(self):
        self.assertEqual(self.p.search(""), [])
        before = self.p.search_apps("code")[0]["score"]
        self.p.used("code")
        self.assertGreater(self.p.search_apps("code")[0]["score"], before)
        self.assertEqual([x["id"] for x in self.p.search("")], ["code"])
        self.assertTrue(os.path.exists(palette.STATE))


class SpectrumTest(unittest.TestCase):
    def test_tones_land_in_right_bands(self):
        for freq in (100, 1000, 5000):
            with self.subTest(freq=freq):
                x = [0.5 * math.sin(2 * math.pi * freq * i / spectrum.RATE) for i in range(spectrum.N)]
                b = spectrum.bands(x)
                lo, hi = spectrum._BINS[b.index(max(b))]
                res = spectrum.RATE / spectrum.N
                self.assertTrue(lo * res - res <= freq <= hi * res + res, (freq, lo * res, hi * res))

    def test_bands_are_increasing_and_cover_range(self):
        self.assertEqual(len(spectrum._BINS), spectrum.BANDS)
        for (lo, hi), (lo2, _) in zip(spectrum._BINS, spectrum._BINS[1:]):
            self.assertLess(lo, hi)
            self.assertLessEqual(lo, lo2)

    def test_silence_without_capture(self):
        sp = spectrum.Spectrum(device="no-such-device")
        sp.available = False          # parec çalıştırma
        self.assertEqual(sp.levels(), [0] * spectrum.BANDS)


if __name__ == "__main__":
    unittest.main()
