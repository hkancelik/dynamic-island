import json
import os
import re
import unittest
from datetime import datetime, timedelta

from tests import helpers

import calendar_ics
import config
import i18n

ICS = """BEGIN:VCALENDAR
BEGIN:VEVENT
UID:standup
SUMMARY:Standup
DTSTART:{day}T090000
DTEND:{day}T091500
RRULE:FREQ=DAILY;COUNT=5
EXDATE:{day2}T090000
URL:https://meet.google.com/abc-defg-hij
END:VEVENT
BEGIN:VEVENT
UID:cancelled
SUMMARY:Gone
STATUS:CANCELLED
DTSTART:{day}T120000
END:VEVENT
BEGIN:VEVENT
UID:holiday
SUMMARY:Holi\\, day
DTSTART;VALUE=DATE:{day}
END:VEVENT
END:VCALENDAR
"""


class CalendarTest(unittest.TestCase):
    def test_recurrence_exdate_cancelled_allday(self):
        now = datetime.now().astimezone()
        day = now.strftime("%Y%m%d")
        day2 = (now + timedelta(days=1)).strftime("%Y%m%d")
        events, errors = calendar_ics.fetch([{"texts": [ICS.format(day=day, day2=day2)], "color": "#ff0000"}], now)
        self.assertEqual(errors, [])
        standups = [e for e in events if e["title"] == "Standup"]
        self.assertEqual(len(standups), 4)                         # 5 tekrar - 1 EXDATE
        self.assertEqual(standups[0]["end"] - standups[0]["start"], 15 * 60 * 1000)
        self.assertEqual(standups[0]["url"], "https://meet.google.com/abc-defg-hij")
        self.assertFalse(any(e["title"] == "Gone" for e in events))
        holiday = next(e for e in events if e["allDay"])
        self.assertEqual(holiday["title"], "Holi, day")             # kaçış çözülür
        self.assertTrue(all(e["cal"] == "#ff0000" for e in events))

    def test_bad_source_is_reported(self):
        events, errors = calendar_ics.fetch(["/does/not/exist.ics"])
        self.assertEqual(events, [])
        self.assertEqual(len(errors), 1)


class ConfigTest(unittest.TestCase):
    def test_set_value_keeps_other_keys(self):
        cfg = config.load()                                         # varsayılanlarla dosya oluşur
        self.assertEqual(cfg["language"], "auto")
        self.assertTrue(config.set_value("language", "tr"))
        self.assertTrue(config.set_switch("lyrics", False))
        self.assertFalse(config.set_switch("not_a_switch", True))
        with open(config.PATH) as f:
            data = json.load(f)
        self.assertEqual((data["language"], data["lyrics"]), ("tr", False))
        self.assertIn("shortcuts", data)
        self.assertEqual(os.stat(config.PATH).st_mode & 0o777, 0o600)   # yalnızca sahibi okur
        config.set_value("language", "auto")
        config.set_switch("lyrics", True)


class LayoutTest(unittest.TestCase):
    def test_clean_layout(self):
        got = config.clean_layout({"tabs": ["tools", "music", "bogus", "music"], "hidden": list(config.TABS),
                                   "open": "sideways", "position": "left", "accent": "#FF375F"})
        self.assertEqual(got["tabs"][:2], ["tools", "music"])
        self.assertEqual(sorted(got["tabs"]), sorted(config.TABS))       # eksikler sona eklenir
        self.assertEqual(len(got["hidden"]), len(config.TABS) - 1)       # en az bir sekme görünür
        self.assertEqual((got["open"], got["position"], got["accent"]), ("last", "left", "#FF375F"))

    def test_bad_values_fall_back(self):
        got = config.clean_layout({"position": "top", "accent": "red; x"})
        self.assertEqual((got["position"], got["accent"]), ("center", "auto"))
        self.assertEqual(config.clean_layout(None)["tabs"], list(config.TABS))


class I18nTest(unittest.TestCase):
    def tearDown(self):
        i18n.reload()

    def test_follows_environment(self):
        i18n.reload()
        self.assertEqual(i18n.lang(), "en")
        self.assertEqual(i18n._("bitti"), "done")
        os.environ["LANG"] = "tr_TR.UTF-8"
        try:
            i18n.reload()
            self.assertEqual(i18n._("bitti"), "bitti")
        finally:
            os.environ["LANG"] = "en_US.UTF-8"

    def test_python_format_placeholders_match(self):
        for tr, en in i18n.EN.items():
            with self.subTest(tr=tr):
                self.assertEqual(re.findall(r"%\S", tr), re.findall(r"%\S", en))

    def test_qml_dictionary_covers_ui_and_placeholders_match(self):
        ui = os.path.join(helpers.ROOT, "contents", "ui")
        with open(os.path.join(ui, "lang_en.js"), encoding="utf-8") as f:
            src = f.read()
        body = re.sub(r"//[^\n]*", "", src[src.index("{"):])
        body = re.sub(r",\s*}", "}", body.strip().rstrip(";"))
        en = json.loads(body)
        used = set()
        for name in os.listdir(ui):
            if name.endswith(".qml"):
                with open(os.path.join(ui, name), encoding="utf-8") as f:
                    text = f.read()
                used |= {json.loads('"%s"' % m) for m in re.findall(r'\bt\("((?:[^"\\]|\\.)*)"\)', text)}
        self.assertEqual(sorted(used - set(en)), [], "lang_en.js'de çevirisi olmayan metinler")
        for tr, val in en.items():
            with self.subTest(tr=tr):
                self.assertEqual(sorted(re.findall(r"%\d", tr)), sorted(re.findall(r"%\d", val)))


if __name__ == "__main__":
    unittest.main()
