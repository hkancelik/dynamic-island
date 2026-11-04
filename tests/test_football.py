"""Maç takibi: ESPN yanıtlarından durum çıkarma (ağsız; tests/fixtures'daki kayıtlarla)."""
import json
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import football  # noqa: E402

FIX = os.path.join(os.path.dirname(__file__), "fixtures")


def load(name):
    with open(os.path.join(FIX, name), encoding="utf-8") as f:
        return json.load(f)


class ScheduleTest(unittest.TestCase):
    def test_upcoming_match(self):
        ms = football.parse_schedule(load("espn_schedule_pre.json"), "364", "uefa.champions")
        m = ms[0]
        self.assertEqual(m["state"], "pre")
        self.assertEqual(m["home"]["name"], "Fenerbahce")
        self.assertEqual(m["away"]["short"], "LIV")
        self.assertEqual(m["us"], "away")
        self.assertEqual(m["leagueName"], "Şampiyonlar Ligi")
        self.assertGreater(m["date"], 1_700_000_000_000)
        self.assertIsNone(m["home"]["score"])
        self.assertEqual(m["result"], "")


class SummaryTest(unittest.TestCase):
    def setUp(self):
        self.match, self.goals, self.lineup = football.parse_summary(
            load("espn_summary_post.json"), "364", "uefa.champions")

    def test_final_score_and_result(self):
        self.assertEqual(self.match["state"], "post")
        self.assertEqual((self.match["home"]["score"], self.match["away"]["score"]), (3, 6))
        self.assertEqual(self.match["us"], "away")
        self.assertEqual(self.match["result"], "W")

    def test_goals_are_listed_in_order(self):
        self.assertEqual(self.goals[0]["min"], "22'")
        self.assertEqual(self.goals[0]["team"], "Liverpool")
        self.assertNotIn("Goal", self.goals[0]["text"])

    def test_lineup_has_formation_rows(self):
        ours = self.lineup["away"]
        self.assertTrue(ours["ours"])
        self.assertEqual(ours["formation"], "4-2-3-1")
        self.assertEqual([len(r) for r in ours["rows"]], [1, 4, 2, 3, 1])
        self.assertEqual(sum(len(r) for r in ours["rows"]), 11)

    def test_full_backs_are_on_the_flanks(self):
        defence = self.lineup["away"]["rows"][1]
        self.assertEqual(defence[0]["pos"], "LB")
        self.assertEqual(defence[-1]["pos"], "RB")

    def test_no_lineup_before_it_is_published(self):
        d = load("espn_summary_post.json")
        for r in d["rosters"]:
            r["roster"] = []
        self.assertIsNone(football.parse_lineup(d, "364"))


class StandingsTest(unittest.TestCase):
    def test_table_rows(self):
        (table,) = football.parse_standings(load("espn_standings.json"))
        self.assertEqual(table["rows"][0]["rank"], 1)
        self.assertGreater(table["rows"][0]["pts"], 0)
        self.assertEqual([r["rank"] for r in table["rows"]], sorted(r["rank"] for r in table["rows"]))
        r = table["rows"][0]
        self.assertEqual(r["w"] * 3 + r["d"], r["pts"])
        self.assertTrue(r["logo"].startswith("http"))

    def test_zones_are_translated_and_colours_normalised(self):
        (table,) = football.parse_standings({"standings": {"entries": [
            {"team": {"id": "1", "displayName": "A"}, "note": {"color": "##B5E7CE", "description": "Europa League"},
             "stats": [{"name": "rank", "displayValue": "5"}]},
            {"team": {"id": "2", "displayName": "B"}, "stats": [{"name": "rank", "displayValue": "6"}]}]}})
        self.assertEqual(table["rows"][0]["zone"], "#B5E7CE")
        self.assertIn(table["rows"][0]["zoneName"], ("Avrupa Ligi", "Europa League"))     # arayüz diline göre
        self.assertEqual(table["rows"][1]["zone"], "")

    def test_signed_goal_difference(self):
        d = {"standings": {"entries": [{"team": {"id": "1", "displayName": "A"}, "stats": [
            {"name": "rank", "displayValue": "1"}, {"name": "pointDifferential", "displayValue": "-4"}]}]}}
        (table,) = football.parse_standings(d)
        self.assertEqual(table["rows"][0]["gd"], -4)


class SearchTest(unittest.TestCase):
    def test_only_top_flight_senior_teams_are_listed(self):
        items = [{"id": "1", "displayName": "Manchester United", "league": "eng.1"},
                 {"id": "2", "displayName": "Manchester United U21", "league": "eng.trophy"},
                 {"id": "3", "displayName": "Chelsea Women", "league": "eng.w.1"},
                 {"id": "4", "displayName": "Man City", "league": "uefa.champions"}]
        orig = football._get
        football._get = lambda url, timeout=8: {"items": items}
        try:
            got = football.search_teams("manchester")
        finally:
            football._get = orig
        self.assertEqual([t["id"] for t in got], ["1"])
        self.assertEqual(got[0]["leagueName"], "Premier Lig")


class LayoutTest(unittest.TestCase):
    def test_falls_back_to_positions_when_formation_is_odd(self):
        starters = [{"n": str(i), "name": "P%d" % i, "pos": p} for i, p in enumerate(
            ["G", "LB", "CD-L", "CD-R", "RB", "CM-L", "CM-R", "LM", "RM", "F", "F"])]
        rows = football.layout_rows(starters, "")
        self.assertEqual([len(r) for r in rows], [1, 4, 4, 2])


class EventTest(unittest.TestCase):
    """Football._events: kadro, başlangıç, gol ve bitiş olayları (ağsız)."""

    def make(self):
        fb = football.Football.__new__(football.Football)
        fb._goals_seen, fb._lineup_seen, fb._live_ids = {}, set(), set()
        fb.log = []
        fb._on_event = lambda kind, data: fb.log.append((kind, data))
        return fb

    def match(self, state, h, a, mid="1"):
        side = lambda i, n, s: {"id": i, "name": n, "short": n[:3].upper(), "logo": "", "score": s}
        return {"id": mid, "state": state, "us": "away", "league": "eng.1", "leagueName": "",
                "home": side("1", "Home", h), "away": side("364", "Liverpool", a)}

    def test_lineup_is_announced_once(self):
        fb, m = self.make(), self.match("pre", None, None)
        lineup = {"away": {"team": "Liverpool", "ours": True, "formation": "4-3-3", "rows": [], "subs": []}}
        fb._events(m, [], lineup, {"id": "364"})
        fb._events(m, [], lineup, {"id": "364"})
        self.assertEqual([k for k, _ in fb.log], ["lineup"])

    def test_no_event_without_a_lineup(self):
        fb = self.make()
        fb._events(self.match("pre", None, None), [], None, {"id": "364"})
        self.assertEqual(fb.log, [])

    def test_goal_for_us_and_against_us(self):
        fb = self.make()
        fb._events(self.match("in", 0, 0), [], None, {"id": "364"})
        fb._events(self.match("in", 0, 1), [], None, {"id": "364"})
        fb._events(self.match("in", 1, 1), [], None, {"id": "364"})
        goals = [d["ours"] for k, d in fb.log if k == "goal"]
        self.assertEqual(goals, [True, False])
        self.assertEqual([k for k, _ in fb.log].count("start"), 1)

    def test_end_is_reported_after_a_live_match(self):
        fb = self.make()
        fb._events(self.match("in", 0, 0), [], None, {"id": "364"})
        fb._events(self.match("post", 0, 2), [], None, {"id": "364"})
        self.assertEqual(fb.log[-1][0], "end")
        fb.log.clear()
        fb._events(self.match("post", 0, 2), [], None, {"id": "364"})
        self.assertEqual(fb.log, [])                       # tekrar bildirilmez

    def test_focus_prefers_a_live_match_then_a_near_kickoff(self):
        fb = self.make()
        now = 1_800_000_000_000
        far = {**self.match("pre", None, None, "far"), "date": now + 3 * 86400 * 1000}
        near = {**self.match("pre", None, None, "near"), "date": now + 3600 * 1000}
        live = {**self.match("in", 1, 0, "live"), "date": now - 1800 * 1000}
        fb._fixtures = [live, near, far]
        self.assertEqual(fb._focus(now)["id"], "live")
        fb._fixtures = [near, far]
        self.assertEqual(fb._focus(now)["id"], "near")
        fb._fixtures = [far]
        self.assertIsNone(fb._focus(now))


class ActivityTest(unittest.TestCase):
    def match(self, clock="62'"):
        side = lambda n, s: {"name": n, "short": n[:3].upper(), "score": s}
        return {"home": side("Fenerbahce", 1), "away": side("Liverpool", 2), "clock": clock,
                "leagueName": "Şampiyonlar Ligi", "detail": ""}

    def test_live_card_shows_score_and_minute(self):
        ((op, msg),) = football.activity_ops("tick", {"match": self.match()}, "#d11317")
        self.assertEqual(op, "set")
        self.assertEqual(msg["id"], "football")
        self.assertEqual(msg["title"], "FEN 1–2 LIV")
        self.assertEqual(msg["value"], "1–2")
        self.assertIn("62'", msg["subtitle"])
        self.assertAlmostEqual(msg["progress"], 62 / 90)

    def test_live_card_has_scoreboard_fields(self):
        ((_, msg),) = football.activity_ops("tick", {"match": self.match()}, "#d11317")
        self.assertEqual((msg["left"], msg["right"], msg["center"]), ("1", "2", "62'"))
        self.assertIn("left_icon", msg)
        self.assertIn("right_icon", msg)

    def test_stoppage_time_does_not_exceed_full_progress(self):
        ((_, msg),) = football.activity_ops("tick", {"match": self.match("90'+4'")}, "#d11317")
        self.assertEqual(msg["progress"], 1.0)

    def test_goal_and_lineup_and_end(self):
        goal = football.activity_ops("goal", {"match": self.match(), "ours": True,
                                              "goals": [{"text": "Salah", "min": "62'"}]}, "#fff000")
        self.assertEqual(goal[0][0], "notify")
        self.assertIn("Salah", goal[0][1]["body"])
        ln = {"team": "Liverpool", "formation": "4-3-3"}
        lineup = football.activity_ops("lineup", {"match": self.match(), "lineup": ln, "opponent": "Fenerbahce"}, "#fff000")
        self.assertIn("4-3-3", lineup[0][1]["body"])
        end = football.activity_ops("end", {"match": self.match()}, "#fff000")
        self.assertEqual(end[0][0], "end")
        self.assertEqual(football.activity_ops("start", {"match": self.match()}, "#fff000"), [])


class ConfigTest(unittest.TestCase):
    def test_football_is_a_tab_and_a_switch(self):
        import config
        self.assertIn("football", config.TABS)
        self.assertIn("football_enabled", config.SWITCHES)
        self.assertEqual(config.DEFAULTS["football"]["team"]["id"], "364")


if __name__ == "__main__":
    unittest.main()
