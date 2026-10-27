"""Bağımlılıksız minimal CalDAV istemcisi (iCloud, Nextcloud, Radicale...).

Hesap → takvim listesi (ad, renk) → zaman aralığındaki etkinliklerin ham .ics metni.
Etkinlik ekleme: seçili takvime PUT. Ayrıştırma calendar_ics'te yapılır.
"""
import base64
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

NS = {
    "d": "DAV:",
    "c": "urn:ietf:params:xml:ns:caldav",
    "a": "http://apple.com/ns/ical/",
    "cs": "http://calendarserver.org/ns/",
}
DISCOVER_EVERY = 3600   # takvim listesi saatte bir yenilenir


class CalDAVError(Exception):
    pass


def _xml(body):
    return ('<?xml version="1.0" encoding="utf-8"?>' + body).encode()


def _color(v):
    """iCloud renkleri #RRGGBBAA gelir; QML için #RRGGBB."""
    v = (v or "").strip()
    if v.startswith("#") and len(v) in (7, 9):
        return v[:7].lower()
    return ""


class Account:
    def __init__(self, conf):
        self.name = conf.get("name") or "CalDAV"
        self.url = conf.get("url") or "https://caldav.icloud.com"
        self.user = conf.get("user", "")
        self._password = conf.get("password", "")
        self._password_cmd = conf.get("password_cmd", "")
        self.only = [n.lower() for n in conf.get("calendars", [])]
        self.calendars = []      # [{href, name, color, writable}]
        self._found_at = 0

    # -- HTTP -----------------------------------------------------------------
    def _secret(self):
        if self._password:
            return self._password
        if self._password_cmd:
            r = subprocess.run(self._password_cmd, shell=True, capture_output=True, text=True, timeout=10)
            if r.returncode == 0 and r.stdout.strip():
                return r.stdout.strip()
            raise CalDAVError("parola komutu sonuç vermedi (password_cmd)")
        raise CalDAVError("parola yok: config'e password ya da password_cmd ekle")

    def _req(self, method, url, body=None, depth=None, ctype="application/xml; charset=utf-8", hops=5):
        auth = base64.b64encode(f"{self.user}:{self._secret()}".encode()).decode()
        headers = {"Authorization": "Basic " + auth, "User-Agent": "dynamic-island"}
        if body is not None:
            headers["Content-Type"] = ctype
        if depth is not None:
            headers["Depth"] = str(depth)
        req = urllib.request.Request(url, data=body, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                return r.status, r.read().decode("utf-8", errors="replace"), r.geturl()
        except urllib.error.HTTPError as e:
            # urllib PROPFIND/REPORT yönlendirmelerini izlemez: elle izle
            if e.code in (301, 302, 307, 308) and hops > 0 and e.headers.get("Location"):
                return self._req(method, urllib.parse.urljoin(url, e.headers["Location"]),
                                 body, depth, ctype, hops - 1)
            if e.code == 401:
                raise CalDAVError("giriş reddedildi: kullanıcı adı ya da uygulamaya özel parola yanlış")
            raise CalDAVError(f"{method} {e.code} {e.reason}")
        except urllib.error.URLError as e:
            raise CalDAVError(f"sunucuya ulaşılamadı ({e.reason})")

    def _propfind(self, url, props, depth):
        body = _xml('<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" '
                    'xmlns:a="http://apple.com/ns/ical/" xmlns:cs="http://calendarserver.org/ns/">'
                    f'<d:prop>{props}</d:prop></d:propfind>')
        _st, text, final = self._req("PROPFIND", url, body, depth)
        return ET.fromstring(text), final

    # -- keşif ----------------------------------------------------------------
    def discover(self, force=False):
        if self.calendars and not force and time.time() - self._found_at < DISCOVER_EVERY:
            return self.calendars
        root, base = self._propfind(self.url, "<d:current-user-principal/>", 0)
        href = root.find(".//d:current-user-principal/d:href", NS)
        if href is None:
            raise CalDAVError("hesap bulunamadı (current-user-principal yok)")
        principal = urllib.parse.urljoin(base, href.text.strip())

        root, base = self._propfind(principal, "<c:calendar-home-set/>", 0)
        href = root.find(".//c:calendar-home-set/d:href", NS)
        if href is None:
            raise CalDAVError("takvim klasörü bulunamadı (calendar-home-set yok)")
        home = urllib.parse.urljoin(base, href.text.strip())

        root, base = self._propfind(
            home,
            "<d:resourcetype/><d:displayname/><a:calendar-color/>"
            "<c:supported-calendar-component-set/><d:current-user-privilege-set/>",
            1)
        cals = []
        for resp in root.findall("d:response", NS):
            if resp.find(".//d:resourcetype/c:calendar", NS) is None:
                continue
            comps = [c.get("name") for c in resp.findall(".//c:supported-calendar-component-set/c:comp", NS)]
            if comps and "VEVENT" not in comps:
                continue   # yalnızca anımsatıcı (VTODO) listeleri
            name = (resp.findtext(".//d:displayname", "", NS) or "").strip() or "Takvim"
            if self.only and name.lower() not in self.only:
                continue
            privs = resp.find(".//d:current-user-privilege-set", NS)
            writable = privs is None or any(
                privs.find(f".//d:privilege/d:{p}", NS) is not None for p in ("write", "write-content", "all"))
            cals.append({
                "href": urllib.parse.urljoin(base, resp.findtext("d:href", "", NS).strip()),
                "name": name,
                "color": _color(resp.findtext(".//a:calendar-color", "", NS)),
                "writable": writable,
            })
        self.calendars = cals
        self._found_at = time.time()
        return cals

    # -- okuma ----------------------------------------------------------------
    def events(self, cal, start, end):
        """start/end: aware datetime -> ham VCALENDAR metinleri."""
        fmt = lambda d: d.astimezone(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        body = _xml(
            '<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
            '<d:prop><c:calendar-data/></d:prop>'
            '<c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT">'
            f'<c:time-range start="{fmt(start)}" end="{fmt(end)}"/>'
            '</c:comp-filter></c:comp-filter></c:filter></c:calendar-query>')
        _st, text, _u = self._req("REPORT", cal["href"], body, 1)
        root = ET.fromstring(text)
        return [el.text for el in root.findall(".//c:calendar-data", NS) if el.text]

    # -- yazma ----------------------------------------------------------------
    def add(self, cal, title, start, end, all_day):
        uid = str(uuid.uuid4()).upper()
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        esc = title.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\n", "\\n")
        if all_day:
            when = f"DTSTART;VALUE=DATE:{start:%Y%m%d}\r\nDTEND;VALUE=DATE:{end:%Y%m%d}"
        else:
            u = lambda d: d.astimezone(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
            when = f"DTSTART:{u(start)}\r\nDTEND:{u(end)}"
        ics = ("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//dynamic-island//TR\r\n"
               f"BEGIN:VEVENT\r\nUID:{uid}\r\nDTSTAMP:{stamp}\r\n{when}\r\nSUMMARY:{esc}\r\n"
               "END:VEVENT\r\nEND:VCALENDAR\r\n")
        url = cal["href"].rstrip("/") + "/" + uid + ".ics"
        self._req("PUT", url, ics.encode(), ctype="text/calendar; charset=utf-8")
        return uid

    def writable_calendar(self, name=""):
        cals = [c for c in self.calendars if c["writable"]]
        for c in cals:
            if name and c["name"].lower() == name.lower():
                return c
        return cals[0] if cals else None
