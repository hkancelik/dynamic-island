"""Hava durumu: Open-Meteo (anahtarsız). Konum config.json "weather" bölümünden:
  {"city": "İstanbul"}  ya da  {"lat": 41.01, "lon": 28.97, "name": "Evim"}
Konum verilmezse IP adresinden yaklaşık konum bulunur (ipwho.is). Sonuç 30 dk'da bir yenilenir
ve yalnızca bellekte tutulur.
"""
import json
import threading
import time
import urllib.parse
import urllib.request
from datetime import date

REFRESH = 30 * 60
RAIN_POP = 50          # bu yağış ihtimalinden itibaren "yağmur geliyor" uyarısı (%)

# WMO hava kodu -> (açıklama, ikon adı)
CODES = {
    0: ("Açık", "weather-clear"), 1: ("Çoğunlukla açık", "weather-few-clouds"),
    2: ("Parçalı bulutlu", "weather-clouds"), 3: ("Kapalı", "weather-overcast"),
    45: ("Sisli", "weather-fog"), 48: ("Kırağılı sis", "weather-fog"),
    51: ("Çisenti", "weather-showers-scattered"), 53: ("Çisenti", "weather-showers-scattered"),
    55: ("Yoğun çisenti", "weather-showers-scattered"),
    56: ("Donan çisenti", "weather-freezing-rain"), 57: ("Donan çisenti", "weather-freezing-rain"),
    61: ("Hafif yağmur", "weather-showers"), 63: ("Yağmur", "weather-showers"),
    65: ("Kuvvetli yağmur", "weather-showers"),
    66: ("Donan yağmur", "weather-freezing-rain"), 67: ("Donan yağmur", "weather-freezing-rain"),
    71: ("Hafif kar", "weather-snow"), 73: ("Kar", "weather-snow"), 75: ("Yoğun kar", "weather-snow"),
    77: ("Kar taneleri", "weather-snow"),
    80: ("Sağanak", "weather-showers"), 81: ("Sağanak", "weather-showers"),
    82: ("Şiddetli sağanak", "weather-showers"),
    85: ("Kar sağanağı", "weather-snow"), 86: ("Kar sağanağı", "weather-snow"),
    95: ("Gök gürültülü fırtına", "weather-storm"), 96: ("Dolulu fırtına", "weather-storm"),
    99: ("Dolulu fırtına", "weather-storm"),
}


def _icon(code, is_day=1):
    """WMO kodu -> (açıklama, ikon adı); geceyse açık/bulutlu simgelerin gece sürümü."""
    text, icon = CODES.get(code, ("", "weather-none-available"))
    if not is_day:
        icon = icon.replace("weather-clear", "weather-clear-night") \
                   .replace("weather-few-clouds", "weather-few-clouds-night") \
                   .replace("weather-clouds", "weather-clouds-night")
    return text, icon


def _at(arr, i, default=None):
    try:
        v = arr[i]
    except (IndexError, TypeError):
        return default
    return default if v is None else v


def parse(d, name=""):
    """Open-Meteo yanıtından arayüzün kullandığı durum sözlüğü (ağsız, test edilebilir)."""
    cur, hourly, daily = d["current"], d.get("hourly") or {}, d.get("daily") or {}
    text, icon = _icon(cur["weather_code"], cur.get("is_day", 1))
    hours = []
    for i, t in enumerate((hourly.get("time") or [])[:13]):
        _tx, ic = _icon(_at(hourly.get("weather_code"), i, 0), _at(hourly.get("is_day"), i, 1))
        hours.append({"h": int(t[11:13]), "temp": round(_at(hourly.get("temperature_2m"), i, 0)),
                      "pop": int(_at(hourly.get("precipitation_probability"), i, 0)), "icon": ic})
    days = []
    for i, dt in enumerate((daily.get("time") or [])[:6]):
        tx, ic = _icon(_at(daily.get("weather_code"), i, 0))
        days.append({"date": dt, "dow": date.fromisoformat(dt[:10]).weekday(),     # 0 = Pazartesi
                     "hi": round(_at(daily.get("temperature_2m_max"), i, 0)),
                     "lo": round(_at(daily.get("temperature_2m_min"), i, 0)),
                     "pop": int(_at(daily.get("precipitation_probability_max"), i, 0)),
                     "text": tx, "icon": ic})
    today = days[0] if days else {"hi": round(cur["temperature_2m"]), "lo": round(cur["temperature_2m"])}
    rain_in = next((i for i, h in enumerate(hours) if h["pop"] >= RAIN_POP), -1)    # kaç saat sonra (0 = bu saat)
    return {
        "ok": True, "place": name, "temp": round(cur["temperature_2m"]),
        "feels": round(cur["apparent_temperature"]), "text": text, "icon": icon,
        "wind": round(cur["wind_speed_10m"]), "wind_dir": int(_at([cur.get("wind_direction_10m")], 0, 0)),
        "humidity": int(_at([cur.get("relative_humidity_2m")], 0, 0)),
        "hi": today["hi"], "lo": today["lo"],
        "sunrise": str(_at(daily.get("sunrise"), 0, ""))[11:16], "sunset": str(_at(daily.get("sunset"), 0, ""))[11:16],
        "uv": round(_at(daily.get("uv_index_max"), 0, 0)),
        "hours": hours, "days": days, "rain_in": rain_in,
        "ts": int(time.time() * 1000),
    }


def _get(url, timeout=8):
    req = urllib.request.Request(url, headers={"User-Agent": "dynamic-island"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def _locate(wc):
    """(lat, lon, ad) döndürür; bulunamazsa None."""
    if wc.get("lat") is not None and wc.get("lon") is not None:
        return float(wc["lat"]), float(wc["lon"]), str(wc.get("name") or wc.get("city") or "")
    city = str(wc.get("city") or "").strip()
    if city:
        q = urllib.parse.urlencode({"name": city, "count": 1, "language": "tr"})
        res = _get("https://geocoding-api.open-meteo.com/v1/search?" + q).get("results") or []
        if res:
            return res[0]["latitude"], res[0]["longitude"], res[0].get("name", city)
        return None
    d = _get("https://ipwho.is/")
    if d.get("success"):
        return d["latitude"], d["longitude"], d.get("city", "")
    return None


class Weather:
    def __init__(self, emit, get_cfg):
        self._emit = emit
        self._cfg = get_cfg
        self._wake = threading.Event()
        self._loc = None       # (anahtar, konum): ayar değişince yeniden bulunur
        threading.Thread(target=self._loop, daemon=True).start()

    def refresh(self):
        self._wake.set()

    def _fetch(self, wc):
        key = json.dumps(wc, sort_keys=True)
        if not self._loc or self._loc[0] != key:
            loc = _locate(wc)
            if not loc:
                raise RuntimeError("konum bulunamadı")
            self._loc = (key, loc)
        lat, lon, name = self._loc[1]
        q = urllib.parse.urlencode({
            "latitude": lat, "longitude": lon, "timezone": "auto", "forecast_days": 6, "forecast_hours": 13,
            "current": "temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,is_day,"
                       "wind_speed_10m,wind_direction_10m",
            "hourly": "temperature_2m,precipitation_probability,weather_code,is_day",
            "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,"
                     "sunrise,sunset,uv_index_max",
        })
        return parse(_get("https://api.open-meteo.com/v1/forecast?" + q), name)

    def _loop(self):
        while True:
            wc = self._cfg() or {}
            wait = REFRESH
            if wc.get("enabled", True) is False:
                self._emit({"ok": False, "off": True})
            else:
                try:
                    self._emit(self._fetch(wc))
                except Exception as e:
                    print("hava durumu alınamadı:", e, flush=True)
                    self._emit({"ok": False, "error": str(e)})
                    wait = 5 * 60
            # ayar değişince hemen yenilenir
            self._wake.wait(wait)
            self._wake.clear()
