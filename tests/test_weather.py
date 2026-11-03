import json
import os
import re
import unittest

from tests import helpers

import config
import weather

FIXTURE = os.path.join(os.path.dirname(__file__), "fixtures", "open_meteo_sample.json")
ROOT = helpers.ROOT


def load():
    with open(FIXTURE) as f:
        return json.load(f)


class ParseTest(unittest.TestCase):
    def test_real_response_is_parsed(self):
        w = weather.parse(load(), "İstanbul")
        self.assertTrue(w["ok"])
        self.assertEqual(w["place"], "İstanbul")
        self.assertEqual(len(w["hours"]), 13)
        self.assertEqual(len(w["days"]), 6)
        for key in ("temp", "feels", "text", "icon", "wind", "wind_dir", "humidity", "hi", "lo", "sunrise", "sunset", "uv", "rain_in"):
            self.assertIn(key, w)
        self.assertRegex(w["sunrise"], r"^\d\d:\d\d$")
        h = w["hours"][0]
        self.assertEqual(set(h), {"h", "temp", "pop", "icon"})
        d = w["days"][0]
        self.assertEqual(set(d), {"date", "dow", "hi", "lo", "pop", "text", "icon"})
        self.assertTrue(0 <= d["dow"] <= 6)
        self.assertEqual((w["hi"], w["lo"]), (d["hi"], d["lo"]))               # bugünün aralığı
        json.dumps(w)                                                           # yayınlanabilir

    def test_rain_warning_points_at_first_wet_hour(self):
        d = load()
        d["hourly"]["precipitation_probability"] = [0] * 13
        self.assertEqual(weather.parse(d)["rain_in"], -1)
        d["hourly"]["precipitation_probability"][5] = weather.RAIN_POP
        self.assertEqual(weather.parse(d)["rain_in"], 5)
        d["hourly"]["precipitation_probability"][0] = 90
        self.assertEqual(weather.parse(d)["rain_in"], 0)

    def test_missing_optional_fields_do_not_break(self):
        d = load()
        del d["hourly"], d["daily"]
        w = weather.parse(d)
        self.assertEqual((w["hours"], w["days"], w["rain_in"]), ([], [], -1))
        self.assertEqual(w["hi"], w["lo"])                                      # tahmin yoksa şimdiki sıcaklık
        d = load()
        d["hourly"]["precipitation_probability"][2] = None                      # API bazen boş (null) gönderir
        self.assertEqual(weather.parse(d)["hours"][2]["pop"], 0)

    def test_night_icons(self):
        self.assertEqual(weather._icon(0, 0)[1], "weather-clear-night")
        self.assertEqual(weather._icon(1, 0)[1], "weather-few-clouds-night")
        self.assertEqual(weather._icon(61, 0)[1], "weather-showers")           # yağmurun gecesi yok


class IconAndTabTest(unittest.TestCase):
    def test_every_backend_icon_has_a_drawn_glyph(self):
        with open(os.path.join(ROOT, "contents", "ui", "WeatherIcon.qml"), encoding="utf-8") as f:
            qml = f.read()
        mapping = dict(re.findall(r'"(weather-[\w-]+)": "([\w-]+)"', qml))
        names = {icon for _t, icon in weather.CODES.values()}
        for code in weather.CODES:
            names.add(weather._icon(code, 0)[1])
        for name in sorted(names):
            with self.subTest(icon=name):
                self.assertIn(name, mapping)
                self.assertTrue(os.path.exists(os.path.join(ROOT, "contents", "icons", "weather", mapping[name] + ".svg")))

    def test_every_description_is_translated(self):
        with open(os.path.join(ROOT, "contents", "ui", "lang_en.js"), encoding="utf-8") as f:
            js = f.read()
        for text, _icon in weather.CODES.values():
            with self.subTest(text=text):
                self.assertIn('"%s":' % text, js)

    def test_weather_tab_is_registered_everywhere(self):
        self.assertIn("weather", config.TABS)
        self.assertEqual(set(config.DEFAULT_ORDER), set(config.TABS))
        self.assertEqual(config.TABS[8], "weather")                             # sayfa numarası 8; Ayarlar 9
        with open(os.path.join(ROOT, "contents", "ui", "main.qml"), encoding="utf-8") as f:
            main = f.read()
        keys = re.search(r"readonly property var tabKeys: \[(.*?)\]", main).group(1)
        self.assertEqual(re.findall(r'"(\w+)"', keys), list(config.TABS))       # QML ve Python aynı sırada

    def test_new_tab_is_appended_for_existing_layouts(self):
        old = {"tabs": ["tools", "music", "notifications", "focus", "calendar", "controls", "apps", "system"], "hidden": ["apps"]}
        got = config.clean_layout(old)
        self.assertEqual(got["tabs"][:2], ["tools", "music"])
        self.assertEqual(got["tabs"][-1], "weather")                            # eski düzenin sonuna eklenir
        self.assertEqual(got["hidden"], ["apps"])


if __name__ == "__main__":
    unittest.main()
