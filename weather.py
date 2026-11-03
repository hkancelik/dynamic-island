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

REFRESH = 30 * 60

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
            "latitude": lat, "longitude": lon, "timezone": "auto", "forecast_days": 1,
            "current": "temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m",
            "daily": "temperature_2m_max,temperature_2m_min",
        })
        d = _get("https://api.open-meteo.com/v1/forecast?" + q)
        cur, day = d["current"], d["daily"]
        text, icon = CODES.get(cur["weather_code"], ("", "weather-none-available"))
        if not cur.get("is_day", 1):
            icon = icon.replace("weather-clear", "weather-clear-night") \
                       .replace("weather-few-clouds", "weather-few-clouds-night") \
                       .replace("weather-clouds", "weather-clouds-night")
        return {
            "ok": True, "place": name, "temp": round(cur["temperature_2m"]),
            "feels": round(cur["apparent_temperature"]), "text": text, "icon": icon,
            "wind": round(cur["wind_speed_10m"]),
            "hi": round(day["temperature_2m_max"][0]), "lo": round(day["temperature_2m_min"][0]),
            "ts": int(time.time() * 1000),
        }

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
