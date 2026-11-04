"""Maç takibi: ESPN'in herkese açık spor verisi (anahtarsız). Takip edilen takımın sıradaki maçları,
son sonuçları, canlı skoru ve açıklanan kadrosu. Config'te:
  "football": {"team": {"id": "364", "name": "Liverpool", "league": "eng.1"}}
Takımın kendi ligine ek olarak Avrupa kupaları da (Şampiyonlar Ligi, Avrupa Ligi, Konferans Ligi)
taranır; takım orada yoksa o kupa sessizce atlanır. Veri yalnızca bellekte tutulur.

Kadro, ESPN yayınlayınca (genellikle maçtan ~1 saat önce) fark edilir: maçtan 3 saat önceden
dakikada bir bakılır. Gol, kadro ve maç başlangıcı/bitişi için `on_event` çağrılır.
"""
import gzip
import json
import re
import threading
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone

from i18n import _

BASE = "https://site.api.espn.com/apis/site/v2/sports/soccer"
SEARCH = "https://site.web.api.espn.com/apis/common/v3/search"
CUPS = ("uefa.champions", "uefa.europa", "uefa.europa.conf")
CUP_NAMES = {"uefa.champions": "Şampiyonlar Ligi", "uefa.europa": "Avrupa Ligi",
             "uefa.europa.conf": "Konferans Ligi"}
LEAGUE_NAMES = {"eng.1": "Premier Lig", "tur.1": "Süper Lig", "esp.1": "La Liga", "ger.1": "Bundesliga",
                "ita.1": "Serie A", "fra.1": "Ligue 1", "ned.1": "Eredivisie", "por.1": "Liga Portugal",
                "eng.fa": "FA Cup", "eng.league_cup": "Lig Kupası"}
DEFAULT_TEAM = {"id": "364", "name": "Liverpool", "league": "eng.1"}

SCHEDULE_EVERY = 30 * 60          # fikstür 30 dakikada bir
LINEUP_WINDOW = 3 * 3600          # maçtan bu kadar önce kadro aranır
LINE_ORDER = {"G": 0, "D": 1, "M": 2, "F": 3}


def _get(url, timeout=8):
    req = urllib.request.Request(url, headers={"User-Agent": "dynamic-island", "Accept-Encoding": "gzip"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        raw = r.read()
    if raw[:2] == b"\x1f\x8b":
        raw = gzip.decompress(raw)
    return json.loads(raw.decode())


def _ms(iso):
    """ESPN tarihi ('2026-11-04T17:45Z') -> epoch ms."""
    try:
        return int(datetime.strptime(iso, "%Y-%m-%dT%H:%MZ").replace(tzinfo=timezone.utc).timestamp() * 1000)
    except (TypeError, ValueError):
        return 0


def _score(c):
    s = c.get("score")
    if isinstance(s, dict):
        s = s.get("displayValue", s.get("value"))
    try:
        return int(float(s))
    except (TypeError, ValueError):
        return None


def _side(c):
    t = c.get("team", {})
    logo = t.get("logo") or ((t.get("logos") or [{}])[0].get("href"))
    return {"id": str(t.get("id", "")), "name": t.get("displayName") or t.get("name") or "",
            "short": t.get("abbreviation", ""), "logo": logo or "", "score": _score(c)}


def parse_match(e, team_id, league):
    """Takvim ya da özet 'event' kaydından arayüzün maç sözlüğü."""
    comp = (e.get("competitions") or [e])[0]
    st = (comp.get("status") or e.get("status") or {}).get("type", {})
    comps = comp.get("competitors") or []
    home = next((c for c in comps if c.get("homeAway") == "home"), comps[0] if comps else {})
    away = next((c for c in comps if c.get("homeAway") == "away"), comps[-1] if comps else {})
    h, a = _side(home), _side(away)
    ours = "home" if h["id"] == str(team_id) else "away"
    state = st.get("state", "pre")
    result = ""
    if state == "post" and h["score"] is not None and a["score"] is not None:
        mine, theirs = (h["score"], a["score"]) if ours == "home" else (a["score"], h["score"])
        result = "W" if mine > theirs else "L" if mine < theirs else "D"
    return {
        "id": str(e.get("id", "")), "league": league,
        "leagueName": CUP_NAMES.get(league) or LEAGUE_NAMES.get(league) or "",
        "date": _ms(e.get("date") or comp.get("date")), "state": state,
        "detail": st.get("shortDetail", ""), "home": h, "away": a, "us": ours, "result": result,
        "venue": ((comp.get("venue") or {}).get("fullName")) or "",
    }


def parse_schedule(d, team_id, league):
    return [parse_match(e, team_id, league) for e in (d.get("events") or [])]


def _line_of(abbr):
    a = (abbr or "").upper()
    if a in ("G", "GK"):
        return "G"
    if a.startswith(("CD", "LB", "RB", "SW", "WB", "LWB", "RWB", "D")):
        return "D"
    if a.startswith(("CM", "DM", "AM", "LM", "RM", "M", "CAM", "CDM")):
        return "M"
    return "F"


def _side_rank(abbr):
    """Soldan sağa sıra: kanat/bek -2 / +2, -L / -R son ekli ya da L/R ile başlayan -1 / +1, orta 0."""
    a = (abbr or "").upper()
    if a in ("LB", "LWB", "LM", "LW"):
        return -2
    if a in ("RB", "RWB", "RM", "RW"):
        return 2
    if a.endswith("-L") or a in ("LF", "LCM", "LDM", "LAM"):
        return -1
    if a.endswith("-R") or a in ("RF", "RCM", "RDM", "RAM"):
        return 1
    return 0


def layout_rows(starters, formation):
    """İlk 11'i diziliş satırlarına böler: [kaleci], [defans], [orta saha], ... soldan sağa sıralı.
    starters: [{"n", "name", "pos"}]. Formasyon '4-2-3-1' gibi; tutmazsa pozisyonlardan çıkarılır."""
    gk = [p for p in starters if _line_of(p["pos"]) == "G"][:1]
    field = [p for p in starters if p not in gk]
    field.sort(key=lambda p: (LINE_ORDER[_line_of(p["pos"])], _side_rank(p["pos"])))
    try:
        counts = [int(x) for x in str(formation).split("-")]
    except ValueError:
        counts = []
    if sum(counts) != len(field) or not counts:
        by = {}
        for p in field:
            by.setdefault(_line_of(p["pos"]), []).append(p)
        counts = [len(by[k]) for k in ("D", "M", "F") if k in by]
    rows, i = ([gk] if gk else []), 0
    for n in counts:
        row = sorted(field[i:i + n], key=lambda p: _side_rank(p["pos"]))
        rows.append(row)
        i += n
    return rows


def parse_lineup(d, team_id):
    """Özetten {home, away, ours}: her takım için diziliş, ilk 11 satırları, yedekler. Kadro yoksa None."""
    out = {}
    for r in d.get("rosters") or []:
        roster = r.get("roster") or []
        starters = [{"n": str(p.get("jersey", "")), "name": (p.get("athlete") or {}).get("shortName")
                     or (p.get("athlete") or {}).get("displayName", ""),
                     "full": (p.get("athlete") or {}).get("displayName", ""),
                     "pos": (p.get("position") or {}).get("abbreviation", "")}
                    for p in roster if p.get("starter")]
        if len(starters) < 11:
            continue
        subs = [{"n": str(p.get("jersey", "")), "name": (p.get("athlete") or {}).get("shortName")
                 or (p.get("athlete") or {}).get("displayName", "")}
                for p in roster if not p.get("starter")][:12]
        t = r.get("team") or {}
        out[r.get("homeAway", "home")] = {
            "team": t.get("displayName", ""), "id": str(t.get("id", "")), "formation": r.get("formation", ""),
            "rows": layout_rows(starters, r.get("formation", "")), "subs": subs,
            "ours": str(t.get("id", "")) == str(team_id)}
    return out or None


def parse_goals(d):
    goals = []
    for k in d.get("keyEvents") or []:
        if not (k.get("scoringPlay") or "goal" in (k.get("type") or {}).get("text", "").lower()):
            continue
        goals.append({"min": (k.get("clock") or {}).get("displayValue", ""),
                      "team": (k.get("team") or {}).get("displayName", ""),
                      "text": (k.get("shortText") or "").replace(" Goal - Header", "").replace(" Goal", "")
                      .replace(" - Header", "").strip()})
    return goals


def parse_summary(d, team_id, league):
    """Özetten canlı durum: maç, dakika, gol listesi, kadro."""
    h = (d.get("header") or {})
    match = parse_match({"id": h.get("id"), "date": h.get("competitions", [{}])[0].get("date"),
                         "competitions": h.get("competitions")}, team_id, league)
    comp = (h.get("competitions") or [{}])[0]
    match["clock"] = comp.get("status", {}).get("displayClock", "")
    match["venue"] = ((d.get("gameInfo") or {}).get("venue") or {}).get("fullName") or match["venue"]
    return match, parse_goals(d), parse_lineup(d, team_id)


ZONES = {"Champions League": "Şampiyonlar Ligi", "Europa League": "Avrupa Ligi",
         "Conference League": "Konferans Ligi", "Europa Conference League": "Konferans Ligi",
         "Relegation": "Küme düşme", "Promotion": "Yükselme", "Promotion Playoff": "Yükselme play-off",
         "Relegation Playoff": "Düşme play-off", "Round of 16": "Son 16",
         "Knockout Round Playoff": "Eleme play-off", "Eliminated": "Elendi",
         "Qualification for Champions League": "Şampiyonlar Ligi'ne katılım"}


def _zone_color(c):
    c = str(c or "").lstrip("#")
    return "#" + c if re.fullmatch(r"[0-9a-fA-F]{6}", c) else ""


def parse_standings(d):
    """ESPN puan durumundan tablolar: [{"name", "rows": [{rank, id, name, short, logo, p, w, d, l, gd, pts}]}]."""
    tables = []
    for ch in d.get("children") or [d]:
        entries = (ch.get("standings") or {}).get("entries") or []
        rows = []
        for e in entries:
            st = {s.get("name"): s.get("displayValue", s.get("value")) for s in e.get("stats") or []}
            t = e.get("team") or {}
            logo = t.get("logo") or ((t.get("logos") or [{}])[0].get("href"))

            def num(k, st=st):
                try:
                    return int(float(str(st.get(k, "0")).replace("+", "")))
                except ValueError:
                    return 0
            note = e.get("note") or {}
            zone = note.get("description", "")
            rows.append({"zone": _zone_color(note.get("color")), "zoneName": _(ZONES.get(zone, zone)),
                         "rank": num("rank"), "id": str(t.get("id", "")), "name": t.get("displayName", ""),
                         "short": t.get("abbreviation", ""), "logo": logo or "", "p": num("gamesPlayed"),
                         "w": num("wins"), "d": num("ties"), "l": num("losses"),
                         "gd": num("pointDifferential"), "pts": num("points")})
        if rows:
            rows.sort(key=lambda r: r["rank"] or 99)
            tables.append({"name": ch.get("name", ""), "rows": rows})
    return tables


def search_teams(q):
    """Takım ara: [{id, name, league, logo}] (futbol takımları)."""
    q = (q or "").strip()
    if len(q) < 2:
        return []
    url = SEARCH + "?" + urllib.parse.urlencode({"query": q, "limit": 12, "type": "team", "sport": "soccer"})
    out = []
    for i in _get(url).get("items", []):
        lg = i.get("league") or ""
        name = i.get("displayName", "")
        # yalnızca ana lig takımları: gençler, yedekler ve kadınlar ile alt kupa kayıtları elenir
        if not re.fullmatch(r"[a-z]{3}\.[12]", lg) or re.search(r"\bU\d\d\b|Women|Reserve|II$", name):
            continue
        out.append({"id": str(i.get("id")), "name": i.get("displayName", ""), "league": lg,
                    "leagueName": LEAGUE_NAMES.get(lg, lg)})
    return out[:8]


def _versus(m):
    h, a = m.get("home", {}), m.get("away", {})
    sh = lambda s: s if s is not None else 0
    return "%s %s–%s %s" % (h.get("short") or h.get("name", ""), sh(h.get("score")),
                             sh(a.get("score")), a.get("short") or a.get("name", ""))


def activity_ops(kind, d, color):
    """Maç olayını adadaki karşılığına çevirir: [("set"|"notify"|"end", sözlük)]. Ağsız, test edilebilir."""
    m = d.get("match") or {}
    versus = _versus(m)
    if kind == "lineup":
        ln = d["lineup"]
        return [("notify", {"title": _("%s kadrosu açıklandı") % ln["team"],
                            "body": "%s · %s" % (ln["formation"], _("rakip: %s") % d["opponent"]),
                            "icon": "football", "color": color})]
    if kind == "tick":
        mins = str(m.get("clock", ""))
        digits = "".join(ch for ch in mins.split("'")[0].split("+")[0] if ch.isdigit())
        minute = int(digits or 0)
        sc = versus.split(" ")[1] if " " in versus else ""
        h, a = m.get("home", {}), m.get("away", {})
        return [("set", {"op": "set", "id": "football", "title": versus, "icon": "football",
                         "subtitle": " · ".join(x for x in (m.get("leagueName", ""), mins or m.get("detail", "")) if x),
                         "value": sc, "progress": min(1.0, minute / 90.0), "color": color, "ttl": 90,
                         # kapalı adada skor tabelası: [logo ev] dakika [deplasman logo]
                         "left": str(h.get("score") if h.get("score") is not None else 0),
                         "right": str(a.get("score") if a.get("score") is not None else 0),
                         "center": mins, "left_icon": h.get("logo", ""), "right_icon": a.get("logo", "")})]
    if kind == "goal":
        scorers = [g for g in d.get("goals", []) if g.get("text")]
        last = scorers[-1] if scorers else {}
        return [("notify", {"title": (_("GOL! %s") if d.get("ours") else _("Gol: %s")) % versus,
                            "body": ("%s %s" % (last.get("text", ""), last.get("min", ""))).strip(),
                            "icon": "check" if d.get("ours") else "warning", "color": color})]
    if kind == "end":
        return [("end", {"id": "football", "state": "done", "message": _("Maç sona erdi: %s") % versus})]
    return []


class Football:
    def __init__(self, emit, get_cfg, on_event=None):
        self._emit = emit
        self._cfg = get_cfg
        self._on_event = on_event or (lambda kind, data: None)
        self._wake = threading.Event()
        self._team_key = None
        self._fixtures = []            # tüm yarışmalardan, tarihe göre
        self._fixtures_at = 0
        self._logo = ""
        self._color = ""
        self._goals_seen = {}          # maç -> (ev, deplasman) skoru
        self._lineup_seen = set()
        self._live_ids = set()
        self._tables = []
        self._tables_at = 0
        self._state = {"ok": False}
        threading.Thread(target=self._loop, daemon=True).start()

    def refresh(self):
        self._fixtures_at = 0
        self._tables_at = 0
        self._wake.set()

    # -- veri
    def _team(self):
        t = (self._cfg() or {}).get("team") or DEFAULT_TEAM
        return {"id": str(t.get("id") or DEFAULT_TEAM["id"]), "name": str(t.get("name") or ""),
                "league": str(t.get("league") or DEFAULT_TEAM["league"])}

    def _load_fixtures(self, team):
        matches, logo, color = [], "", ""
        for lg in (team["league"],) + tuple(c for c in CUPS if c != team["league"]):
            for q in ("", "?fixture=true"):
                try:
                    d = _get("%s/%s/teams/%s/schedule%s" % (BASE, lg, team["id"], q))
                except Exception:
                    continue               # takım bu yarışmada yok / ağ hatası
                t = d.get("team") or {}
                logo = logo or t.get("logo", "")
                color = color or t.get("color", "")
                matches += parse_schedule(d, team["id"], lg)
        seen, uniq = set(), []
        for m in sorted(matches, key=lambda m: m["date"]):
            if m["id"] and m["id"] not in seen:
                seen.add(m["id"])
                uniq.append(m)
        self._fixtures, self._logo, self._color = uniq, logo, color
        self._fixtures_at = time.time()

    def _load_tables(self, team):
        """Takımın oynadığı yarışmaların puan durumu (takımın bulunduğu tablolar)."""
        out = []
        for lg in (team["league"],) + tuple(c for c in CUPS if c != team["league"]):
            try:
                d = _get("https://site.api.espn.com/apis/v2/sports/soccer/%s/standings" % lg)
            except Exception:
                continue
            for t in parse_standings(d):
                idx = next((i for i, r in enumerate(t["rows"]) if r["id"] == team["id"]), -1)
                if idx >= 0:
                    out.append({"league": lg, "name": CUP_NAMES.get(lg) or LEAGUE_NAMES.get(lg) or t["name"],
                                "idx": idx, "rows": t["rows"]})
        self._tables, self._tables_at = out, time.time()

    def _focus(self, now_ms):
        """Üzerinde durulacak maç: oynanan, yoksa en yakın ve 3 saat içindeki, yoksa son biten (3 saat)."""
        for m in self._fixtures:
            if m["state"] == "in":
                return m
        nxt = next((m for m in self._fixtures if m["state"] == "pre"), None)
        if nxt and nxt["date"] - now_ms <= LINEUP_WINDOW * 1000:
            return nxt
        last = next((m for m in reversed(self._fixtures) if m["state"] == "post"), None)
        if last and now_ms - last["date"] <= 5 * 3600 * 1000:
            return last
        return None

    def _step(self):
        team = self._team()
        key = json.dumps(team, sort_keys=True)
        if key != self._team_key:
            self._team_key = key
            self._fixtures_at = 0
            self._tables_at = 0
            self._goals_seen.clear()
            self._lineup_seen.clear()
        if time.time() - self._fixtures_at > SCHEDULE_EVERY:
            self._load_fixtures(team)
        if time.time() - self._tables_at > SCHEDULE_EVERY:
            self._load_tables(team)
        now_ms = int(time.time() * 1000)
        live = None
        lineup = None
        goals = []
        fm = self._focus(now_ms)
        if fm:
            try:
                d = _get("%s/%s/summary?event=%s" % (BASE, fm["league"], fm["id"]))
                sm, goals, lineup = parse_summary(d, team["id"], fm["league"])
                self._merge(sm)
                fm = sm
            except Exception as e:
                print("maç özeti alınamadı:", e, flush=True)
        self._events(fm, goals, lineup, team)
        upcoming = [m for m in self._fixtures if m["state"] == "pre"][:6]
        past = [m for m in reversed([m for m in self._fixtures if m["state"] == "post"])][:5]
        live = fm if fm and fm["state"] == "in" else None
        self._state = {
            "ok": True, "team": {"id": team["id"], "name": team["name"] or self._name_from_fixtures(team),
                                 "logo": self._logo, "color": ("#" + self._color) if self._color else ""},
            "live": live, "focus": fm, "goals": goals, "lineup": lineup,
            "next": upcoming, "last": past, "tables": self._tables, "ts": now_ms}
        self._emit(self._state)
        if live:
            return 20
        if fm and fm["state"] == "pre":
            return 60
        return 5 * 60

    def _name_from_fixtures(self, team):
        for m in self._fixtures:
            for side in (m["home"], m["away"]):
                if side["id"] == team["id"]:
                    return side["name"]
        return ""

    def _merge(self, sm):
        """Özetten gelen güncel maç bilgisini fikstüre işler (ağ çağrısı tasarrufu)."""
        for i, m in enumerate(self._fixtures):
            if m["id"] == sm["id"]:
                self._fixtures[i] = {**m, **{k: sm[k] for k in ("state", "detail", "home", "away", "result")}}

    def _events(self, fm, goals, lineup, team):
        if not fm:
            return
        mid = fm["id"]
        mine = fm["home"] if fm["us"] == "home" else fm["away"]
        theirs = fm["away"] if fm["us"] == "home" else fm["home"]
        if lineup and mid not in self._lineup_seen and fm["state"] != "post":
            self._lineup_seen.add(mid)
            ours = next((v for v in lineup.values() if v["ours"]), None)
            if ours:
                self._on_event("lineup", {"match": fm, "lineup": ours, "opponent": theirs["name"]})
        if fm["state"] == "in":
            if mid not in self._live_ids:
                self._live_ids.add(mid)
                self._on_event("start", {"match": fm})
            sc = (fm["home"]["score"] or 0, fm["away"]["score"] or 0)
            prev = self._goals_seen.get(mid)
            if prev is not None and sum(sc) > sum(prev):
                i = 0 if fm["us"] == "home" else 1
                self._on_event("goal", {"match": fm, "ours": sc[i] > prev[i], "goals": goals})
            self._goals_seen[mid] = sc
            self._on_event("tick", {"match": fm})
        elif fm["state"] == "post" and mid in self._live_ids:
            self._live_ids.discard(mid)
            self._on_event("end", {"match": fm, "mine": mine, "theirs": theirs})

    def _loop(self):
        while True:
            wait = 60
            cfg = self._cfg() or {}
            if cfg.get("enabled", True) is False:
                self._emit({"ok": False, "off": True})
                wait = 300
            else:
                try:
                    wait = self._step()
                except Exception as e:
                    print("maç verisi alınamadı:", e, flush=True)
                    self._emit({**self._state, "ok": bool(self._state.get("ok")), "error": str(e)})
                    wait = 120
            self._wake.wait(wait)
            self._wake.clear()
