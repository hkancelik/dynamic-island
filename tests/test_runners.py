import os
import tempfile
import unittest

from tests import helpers  # noqa: F401  (ortamı yalıtır; dil İngilizce)

import palette
import runners


class ConvertTest(unittest.TestCase):
    def conv(self, q):
        return [r["text"] for r in runners.convert(q)]

    def test_units(self):
        self.assertEqual(self.conv("10 km in mi"), ["6.2137 mi"])
        self.assertEqual(self.conv("10 km"), ["6.2137 mi"])               # varsayılan karşılık
        self.assertEqual(self.conv("72 f to c"), ["22.2222 °C"])
        self.assertEqual(self.conv("100 c"), ["212 °F"])
        self.assertEqual(self.conv("10 in cm"), ["25.4 cm"])              # "in" hem inç hem bağlaç
        self.assertEqual(self.conv("2 saat dk"), ["120 dk"])
        self.assertEqual(self.conv("1,5 kg g"), ["1,500 g"])

    def test_rejects(self):
        for q in ("10 km kg", "5 xyz", "km", "hello 10", "10"):
            with self.subTest(q=q):
                self.assertEqual(self.conv(q), [])


class SmallRunnersTest(unittest.TestCase):
    def test_web_shortcut(self):
        r = runners.web_shortcut("gg: kde plasma")[0]
        self.assertEqual(r["url"], "https://www.google.com/search?q=kde+plasma")
        self.assertEqual(runners.web_shortcut("zz: x"), [])
        self.assertTrue(runners.web_shortcut("wp ankara")[0]["url"].startswith("https://en.wikipedia.org"))

    def test_locations(self):
        d = tempfile.mkdtemp()
        os.mkdir(os.path.join(d, "Projects"))
        self.assertEqual(runners.locations(d)[0]["path"], d)
        self.assertEqual([r["title"] for r in runners.locations(os.path.join(d, "Proj"))], [os.path.join(d, "Projects")])
        self.assertEqual(runners.locations("github.com/kde")[0]["url"], "https://github.com/kde")
        self.assertEqual(runners.locations("just words"), [])

    def test_shell(self):
        self.assertTrue(runners.shell("> htop")[0]["terminal"])
        self.assertFalse(runners.shell(">> notify-send hi")[0]["terminal"])
        self.assertEqual(runners.shell("htop"), [])

    def test_color_and_chars(self):
        self.assertEqual([r["text"] for r in runners.color("#ff6a00")][:2], ["#ff6a00", "rgb(255, 106, 0)"])
        self.assertEqual(runners.color("abc")[0]["swatch"], "#aabbcc")
        self.assertEqual(runners.color("123456"), [])                    # harfsiz sayı renk sayılmaz
        self.assertEqual(runners.characters("#2192")[0]["text"], "→")
        self.assertEqual(runners.characters("#0a84ff"), [])               # renk, karakter değil
        self.assertEqual(runners.characters("u:rightwards arrow")[0]["text"], "→")

    def test_datetime(self):
        r = runners.datetime_runner("time tokyo", palette.fold)[0]
        self.assertIn("UTC+9", r["subtitle"])
        self.assertEqual(runners.datetime_runner("time atlantis-nowhere", palette.fold), [])

    def test_session_needs_confirm_for_destructive(self):
        r = {x["action"]: x for x in runners.session("restart", palette.score)}
        self.assertTrue(r["reboot"]["confirm"])
        self.assertFalse(runners.session("lock", palette.score)[0]["confirm"])

    def test_kill_only_own_processes(self):
        self.assertFalse(runners.kill_pid(1))                            # init: başkasının
        self.assertFalse(runners.kill_pid(os.getpid()))                  # kendimiz değil
        hits = runners.kill("kill python")
        self.assertTrue(all(h["confirm"] for h in hits))


class HomeIndexTest(unittest.TestCase):
    def test_skips_hidden_and_junk(self):
        d = tempfile.mkdtemp()
        for p in ("Docs/report.pdf", ".cache/report-cache.pdf", "proj/node_modules/report.js", "Report notes.txt"):
            os.makedirs(os.path.dirname(os.path.join(d, p)) or d, exist_ok=True)
            open(os.path.join(d, p), "w").close()
        idx = runners.HomeIndex(d)
        idx._build()
        found = [os.path.relpath(p, d) for p in idx.search("report", limit=10)]
        self.assertEqual(sorted(found), ["Docs/report.pdf", "Report notes.txt"])


class PaletteRunValidationTest(unittest.TestCase):
    def test_unknown_or_bad_payloads_are_refused(self):
        copied = []
        p = palette.Palette(copy=copied.append, dbus=False)
        self.assertFalse(p.run({"kind": "rm -rf"}))
        self.assertFalse(p.run({"kind": "url", "url": "javascript:alert(1)"}))
        self.assertFalse(p.run({"kind": "path", "path": "/no/such/file"}))
        self.assertFalse(p.run({"kind": "kill", "pid": 1}))
        self.assertTrue(p.run({"kind": "copy", "text": "36"}))
        self.assertEqual(copied, ["36"])


if __name__ == "__main__":
    unittest.main()
