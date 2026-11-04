import time
import unittest

from tests import helpers  # noqa: F401  (ortamı yalıtır; diğer içe aktarmalardan önce)

import activities
from activities import Activities, parse_duration


class ParseDurationTest(unittest.TestCase):
    def test_formats(self):
        cases = {
            "90": 90, "90s": 90, "5m": 300, "5min": 300, "1h": 3600, "1h30m": 5400,
            "1h 30m 15s": 5415, "1:30": 90, "1:00:00": 3600, "25m": 1500,
        }
        for text, secs in cases.items():
            with self.subTest(text=text):
                self.assertEqual(parse_duration(text), secs)

    def test_invalid(self):
        for text in ("", "abc", "0", "0s", "5x", "1:2:3:4", "-5", "m"):
            with self.subTest(text=text):
                self.assertIsNone(parse_duration(text))


class ActivitiesTest(unittest.TestCase):
    def setUp(self):
        self.pub = []
        self.live = Activities(self.pub.append, play_sound=False)

    @property
    def last(self):
        return self.pub[-1]

    def test_set_creates_and_updates(self):
        aid = self.live.set({"id": "build", "title": "cargo build", "progress": "40%", "icon": "build"})
        self.assertEqual(aid, "build")
        item = self.last["items"][0]
        self.assertEqual(item["title"], "cargo build")
        self.assertAlmostEqual(item["progress"], 0.4)
        self.assertEqual(item["color"], activities.PALETTE["build"])   # ikona göre renk

        self.live.set({"id": "build", "progress": 0.9})
        item = self.last["items"][0]
        self.assertAlmostEqual(item["progress"], 0.9)
        self.assertEqual(item["title"], "cargo build")                  # diğer alanlar korunur

    def test_progress_forms(self):
        for given, want in ((0.25, 0.25), ("0.25", 0.25), (25, 0.25), ("25%", 0.25), (1, 1.0),
                            (150, 1.0), (None, -1.0), ("-1", -1.0)):
            with self.subTest(given=given):
                self.live.set({"id": "p", "progress": given})
                self.assertAlmostEqual(self.last["items"][0]["progress"], want)

    def test_auto_id(self):
        a = self.live.set({"title": "x"})
        b = self.live.set({"title": "y"})
        self.assertNotEqual(a, b)

    def test_invalid_id_and_color(self):
        with self.assertRaises(ValueError):
            self.live.set({"id": "kötü id!"})
        self.live.set({"id": "c", "color": "red; drop"})
        self.assertEqual(self.last["items"][0]["color"], "")

    def test_text_is_sanitised(self):
        self.live.set({"id": "t", "title": "a\n\tb" + "x" * 500, "value": "123456789012345"})
        item = self.last["items"][0]
        self.assertTrue(item["title"].startswith("a b"))
        self.assertLessEqual(len(item["title"]), 80)
        self.assertLessEqual(len(item["value"]), 12)

    def test_end_publishes_done(self):
        self.live.set({"id": "job", "title": "deploy"})
        seq = self.last["done"]["seq"]
        self.assertTrue(self.live.end("job", "failed", "exit 1"))
        self.assertEqual(self.last["items"], [])
        done = self.last["done"]
        self.assertEqual(done["seq"], seq + 1)
        self.assertEqual((done["state"], done["title"], done["subtitle"]), ("failed", "deploy", "exit 1"))
        self.assertFalse(self.live.end("job"))                          # ikinci kez yok

    def test_unknown_state_becomes_done(self):
        self.live.set({"id": "j"})
        self.live.end("j", "weird")
        self.assertEqual(self.last["done"]["state"], "done")

    def test_notify(self):
        self.live.notify({"title": "Backup", "body": "42 GB", "icon": "check"})
        done = self.last["done"]
        self.assertEqual((done["state"], done["title"], done["subtitle"]), ("info", "Backup", "42 GB"))
        self.assertEqual(done["color"], activities.PALETTE["check"])

    def test_capacity_evicts_stalest(self):
        for i in range(activities.MAX_ITEMS):
            self.live.set({"id": "a%d" % i})
            time.sleep(0.002)
        self.live.set({"id": "a0"})                                     # a0 tazelendi
        self.live.set({"id": "new"})
        ids = {it["id"] for it in self.last["items"]}
        self.assertEqual(len(ids), activities.MAX_ITEMS)
        self.assertIn("a0", ids)
        self.assertNotIn("a1", ids)                                     # en bayatı gitti

    def test_timer_finishes_by_itself(self):
        self.live.set({"id": "tea", "title": "Tea", "duration": "1s", "icon": "timer"})
        item = self.last["items"][0]
        self.assertAlmostEqual(item["end"] - item["start"], 1000, delta=5)
        deadline = time.time() + 4
        while time.time() < deadline and self.last["items"]:
            time.sleep(0.1)
        self.assertEqual(self.last["items"], [])
        self.assertEqual((self.last["done"]["state"], self.last["done"]["title"]), ("done", "Tea"))

    def test_ttl_expiry(self):
        self.live.set({"id": "old", "ttl": 5})
        self.live._seen["old"] -= 10                                    # 10 sn önce güncellenmiş gibi
        deadline = time.time() + 3
        while time.time() < deadline and self.last["items"]:
            time.sleep(0.1)
        self.assertEqual(self.last["items"], [])
        self.assertEqual(self.last["done"]["seq"], 0)                   # süresi dolan sessizce gider

    def test_handle_ops(self):
        self.assertEqual(self.live.handle({"op": "set", "id": "h"}), {"id": "h"})
        self.assertEqual([i["id"] for i in self.live.handle({"op": "list"})["items"]], ["h"])
        self.assertEqual(self.live.handle({"op": "end", "id": "h"}), {"ok": True})
        self.assertEqual(self.live.handle({"op": "clear"}), {"ok": True})
        with self.assertRaises(ValueError):
            self.live.handle({"op": "explode"})
        with self.assertRaises(ValueError):
            self.live.handle({"op": "set", "id": "x", "duration": "soon"})


if __name__ == "__main__":
    unittest.main()


class ScoreboardTest(unittest.TestCase):
    def test_score_fields(self):
        pub = []
        live = activities.Activities(pub.append, play_sound=False)
        live.set({"id": "m", "title": "A – B", "left": "1", "right": "0", "center": "67'",
                  "left_icon": "/tmp/a.png", "right_icon": "http://evil/x.png"})
        it = pub[-1]["items"][0]
        self.assertEqual((it["left"], it["right"], it["center"]), ("1", "0", "67'"))
        self.assertEqual(it["left_icon"], "/tmp/a.png")
        self.assertEqual(it["right_icon"], "")      # uzak adres kabul edilmez
