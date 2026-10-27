"""Bağımlılıksız minimal iCalendar okuyucu (VEVENT + RRULE/EXDATE/RECURRENCE-ID)."""
import calendar
import glob
import os
import re
import urllib.request
from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

# Aylık görünüm için: bir hafta geriden iki ay ileriye
PAST_DAYS = 7
WINDOW_DAYS = 62
MAX_SCAN_DAYS = 36500
URL_RE = re.compile(r'https?://[^\s<>"\\]+')
WEEKDAYS = {"MO": 0, "TU": 1, "WE": 2, "TH": 3, "FR": 4, "SA": 5, "SU": 6}


# -- ayrıştırma -------------------------------------------------------------
def _unfold(text):
    lines = []
    for raw in text.splitlines():
        if raw[:1] in (" ", "\t") and lines:
            lines[-1] += raw[1:]
        else:
            lines.append(raw)
    return lines


def _split_outside_quotes(s, sep):
    parts, cur, q = [], "", False
    for ch in s:
        if ch == '"':
            q = not q
        if ch == sep and not q:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    parts.append(cur)
    return parts


def _prop(line):
    q = False
    for i, ch in enumerate(line):
        if ch == '"':
            q = not q
        elif ch == ":" and not q:
            head, value = line[:i], line[i + 1:]
            parts = _split_outside_quotes(head, ";")
            params = {}
            for p in parts[1:]:
                if "=" in p:
                    k, v = p.split("=", 1)
                    params[k.upper()] = v.strip('"')
            return parts[0].upper(), params, value
    return None


def _text(v):
    return (v.replace("\\n", "\n").replace("\\N", "\n").replace("\\,", ",")
             .replace("\\;", ";").replace("\\\\", "\\"))


def _dt(value, params):
    """-> (wall: naive datetime, tz, all_day). tz: ZoneInfo | utc | None(yerel)"""
    v = value.strip()
    if params.get("VALUE") == "DATE" or len(v) == 8:
        return datetime.strptime(v[:8], "%Y%m%d"), None, True
    wall = datetime.strptime(v.rstrip("Z")[:15], "%Y%m%dT%H%M%S")
    if v.endswith("Z"):
        return wall, timezone.utc, False
    tzid = params.get("TZID")
    if tzid:
        try:
            return wall, ZoneInfo(tzid), False
        except Exception:
            pass
    return wall, None, False


def _attach(wall, tz):
    return wall.replace(tzinfo=tz) if tz is not None else wall.astimezone()


def _duration(v):
    m = re.fullmatch(r"([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?", v.strip())
    if not m:
        return timedelta(0)
    sign = -1 if m.group(1) == "-" else 1
    w, d, h, mi, s = (int(x or 0) for x in m.groups()[1:])
    return sign * timedelta(weeks=w, days=d, hours=h, minutes=mi, seconds=s)


def _events(text):
    out, cur, in_alarm = [], None, False
    for line in _unfold(text):
        u = line.upper()
        if u == "BEGIN:VEVENT":
            cur, in_alarm = {}, False
        elif u == "END:VEVENT":
            if cur is not None:
                out.append(cur)
            cur = None
        elif u == "BEGIN:VALARM":
            in_alarm = True
        elif u == "END:VALARM":
            in_alarm = False
        elif cur is not None and not in_alarm:
            p = _prop(line)
            if p:
                cur.setdefault(p[0], []).append((p[1], p[2]))
    return out


# -- tekrar kuralları --------------------------------------------------------
def _rule(v):
    r = {}
    for part in v.split(";"):
        if "=" in part:
            k, val = part.split("=", 1)
            r[k.upper()] = val
    return r


def _nth_ok(d, order, wd):
    if d.weekday() != wd:
        return False
    if order == 0:
        return True
    if order > 0:
        return (d.day - 1) // 7 + 1 == order
    return d.day + 7 > calendar.monthrange(d.year, d.month)[1] and order == -1


def _matches(d, sd, r, interval, byday, bymonthday, bymonth):
    freq = r.get("FREQ")
    if bymonth and d.month not in bymonth:
        return False
    if freq == "DAILY":
        if (d - sd).days % interval:
            return False
        return not byday or any(_nth_ok(d, 0, wd) for _, wd in byday)
    if freq == "WEEKLY":
        monday = sd - timedelta(days=sd.weekday())
        if ((d - monday).days // 7) % interval:
            return False
        return d.weekday() in ({wd for _, wd in byday} or {sd.weekday()})
    if freq == "MONTHLY":
        if ((d.year - sd.year) * 12 + d.month - sd.month) % interval:
            return False
        if bymonthday:
            last = calendar.monthrange(d.year, d.month)[1]
            return d.day in bymonthday or (d.day - last - 1) in bymonthday
        if byday:
            return any(_nth_ok(d, o, wd) for o, wd in byday)
        return d.day == sd.day
    if freq == "YEARLY":
        if (d.year - sd.year) % interval:
            return False
        months = bymonth or [sd.month]
        if d.month not in months:
            return False
        if byday:
            return any(_nth_ok(d, o, wd) for o, wd in byday)
        return d.day in (bymonthday or [sd.day])
    return False


def _occurrences(start_wall, tz, r, dur, win_start, win_end, exclude):
    sd = start_wall.date()
    until = None
    if "UNTIL" in r:
        try:
            uw, utz, _ = _dt(r["UNTIL"], {})
            until = _attach(uw, utz if utz is not None else tz)
        except Exception:
            pass
    count = int(r["COUNT"]) if r.get("COUNT", "").isdigit() else None
    interval = max(1, int(r.get("INTERVAL", "1") or 1))
    byday = []
    for t in filter(None, r.get("BYDAY", "").split(",")):
        m = re.fullmatch(r"([+-]?\d+)?(MO|TU|WE|TH|FR|SA|SU)", t)
        if m:
            byday.append((int(m.group(1) or 0), WEEKDAYS[m.group(2)]))
    bymonthday = [int(x) for x in filter(None, r.get("BYMONTHDAY", "").split(","))]
    bymonth = [int(x) for x in filter(None, r.get("BYMONTH", "").split(","))]

    last_day = win_end.date()
    d, n = sd, 0
    for _ in range(MAX_SCAN_DAYS):
        if d > last_day:
            break
        if _matches(d, sd, r, interval, byday, bymonthday, bymonth):
            n += 1
            if count is not None and n > count:
                break
            wall = datetime.combine(d, start_wall.time())
            s = _attach(wall, tz)
            if until is not None and s > until:
                break
            if s + dur > win_start and s not in exclude:
                yield s
        d += timedelta(days=1)


# -- ana işlev ---------------------------------------------------------------
def _load(source):
    # CalDAV'dan önceden çekilmiş metinler: {"texts": [...], "color": "#rrggbb", "label": "..."}
    if isinstance(source, dict):
        return source["texts"]
    src = os.path.expanduser(source.strip())
    if src.startswith("webcal://"):
        src = "https://" + src[len("webcal://"):]
    if src.startswith(("http://", "https://")):
        req = urllib.request.Request(src, headers={"User-Agent": "dynamic-island"})
        with urllib.request.urlopen(req, timeout=15) as r:
            return [r.read().decode("utf-8", errors="replace")]
    paths = glob.glob(os.path.join(src, "**", "*.ics"), recursive=True) if os.path.isdir(src) else [src]
    out = []
    for p in paths:
        with open(p, encoding="utf-8", errors="replace") as f:
            out.append(f.read())
    return out


def fetch(sources, now=None):
    """-> (etkinlik listesi, hata listesi). Zamanlar epoch milisaniye."""
    now = now or datetime.now().astimezone()
    win_start = datetime.combine(now.date(), time()).astimezone() - timedelta(days=PAST_DAYS)
    win_end = win_start + timedelta(days=WINDOW_DAYS)
    events, errors = [], []

    for idx, source in enumerate(sources):
        try:
            texts = _load(source)
        except Exception as e:
            label = source.get("label", "CalDAV") if isinstance(source, dict) else source[:40] + "…"
            errors.append(f"{label}: {e}")
            continue

        # Etkinlik rengi: takvimin kendi rengi (CalDAV) ya da sıra numarası (QML paleti)
        cal = (source.get("color") if isinstance(source, dict) else None) or idx
        raw = [ev for t in texts for ev in _events(t)]
        overrides = set()
        for ev in raw:
            if "RECURRENCE-ID" in ev:
                p, v = ev["RECURRENCE-ID"][0]
                try:
                    w, tz, _ = _dt(v, p)
                    overrides.add((ev.get("UID", [({}, "")])[0][1], _attach(w, tz)))
                except Exception:
                    pass

        for ev in raw:
            try:
                if ev.get("STATUS", [({}, "")])[0][1].upper() == "CANCELLED" or "DTSTART" not in ev:
                    continue
                uid = ev.get("UID", [({}, "")])[0][1]
                p, v = ev["DTSTART"][0]
                wall, tz, all_day = _dt(v, p)
                start = _attach(wall, tz)
                if "DTEND" in ev:
                    ew, etz, _ = _dt(ev["DTEND"][0][1], ev["DTEND"][0][0])
                    dur = _attach(ew, etz) - start
                elif "DURATION" in ev:
                    dur = _duration(ev["DURATION"][0][1])
                else:
                    dur = timedelta(days=1) if all_day else timedelta(0)

                title = _text(ev.get("SUMMARY", [({}, "(Başlıksız)")])[0][1]) or "(Başlıksız)"
                loc = _text(ev.get("LOCATION", [({}, "")])[0][1])
                url = ""
                for key in ("URL", "LOCATION", "DESCRIPTION"):
                    m = URL_RE.search(_text(ev.get(key, [({}, "")])[0][1]))
                    if m:
                        url = m.group(0).rstrip(".,);")
                        break

                starts = [start]
                if "RRULE" in ev and "RECURRENCE-ID" not in ev:
                    exclude = set(o for u, o in overrides if u == uid)
                    for _p, ex in ev.get("EXDATE", []):
                        for part in ex.split(","):
                            try:
                                w2, tz2, _ = _dt(part, _p)
                                exclude.add(_attach(w2, tz2 if tz2 is not None else tz))
                            except Exception:
                                pass
                    starts = list(_occurrences(wall, tz, _rule(ev["RRULE"][0][1]), dur,
                                               win_start, win_end, exclude))
                for s in starts:
                    e = s + dur
                    if s < win_end and (e > win_start or (dur == timedelta(0) and s >= win_start)):
                        events.append({
                            "id": f"{idx}:{uid}:{int(s.timestamp())}",
                            "title": title,
                            "start": int(s.timestamp() * 1000),
                            "end": int(e.timestamp() * 1000),
                            "allDay": all_day,
                            "location": loc,
                            "url": url,
                            "cal": cal,
                        })
            except Exception:
                continue

    events.sort(key=lambda e: (e["start"], not e["allDay"]))
    return events, errors
