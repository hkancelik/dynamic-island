"""Kullanıcı yapılandırması: ~/.config/dynamic-island/config.json"""
import json
import os
import re
import secrets
import tempfile

PATH = os.path.expanduser("~/.config/dynamic-island/config.json")

# API belirteci: yalnızca bu kullanıcı okuyabilir (0600, 0700 klasörde). Betikler de buradan okur.
TOKEN_PATH = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or os.path.join(tempfile.gettempdir(), "dynamic-island-%d" % os.getuid()),
                          "dynamic-island", "token")


def make_token():
    """Her başlatmada yeni belirteç üretip TOKEN_PATH'e yazar."""
    token = secrets.token_hex(32)
    d = os.path.dirname(TOKEN_PATH)
    os.makedirs(d, mode=0o700, exist_ok=True)
    os.chmod(d, 0o700)
    tmp = TOKEN_PATH + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(token)
    os.replace(tmp, TOKEN_PATH)
    return token


def private_open(path, mode="w"):
    """Kullanıcı verisi (parola/not içerebilir) için yalnızca sahibin okuyabildiği dosya."""
    return os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), mode)

# Paneldeki sekmeler (arayüzdeki sayfa numarası = bu listedeki sıra)
TABS = ("music", "notifications", "focus", "calendar", "controls", "apps", "system", "tools", "weather")
# Ekrandaki varsayılan sıra (sayfa numaralarından ayrı): Hava, Sistem'in yanında
DEFAULT_ORDER = ("music", "notifications", "focus", "calendar", "controls", "apps", "system", "weather", "tools")

DEFAULTS = {
    # Google Takvim → Ayarlar → takvimi seç → "iCal biçimindeki gizli adres"
    # ya da .ics dosyası / .ics dosyaları içeren klasör yolu.
    "calendars": [],
    # CalDAV hesapları (Apple iCloud, Nextcloud...). iCloud için:
    #   {"name": "iCloud", "url": "https://caldav.icloud.com", "user": "apple-kimliğin@icloud.com",
    #    "password_cmd": "secret-tool lookup service dynamic-island account icloud"}
    # Parola: account.apple.com → Uygulamaya özel parolalar (Apple ID parolası ÇALIŞMAZ).
    # "password" alanına düz yazmak da olur ama secret-tool (KWallet) daha güvenli.
    # "calendars": ["Ev", "İş"] ile yalnızca bazı takvimler gösterilir (boş: hepsi).
    "caldav": [],
    # Odak sayacı (Pomodoro) varsayılan süreleri, dakika
    "focus": {"work": 25, "break": 5},
    # Adadan eklenen etkinliklerin gideceği takvimin adı (boş: ilk yazılabilir takvim)
    "caldav_default": "",
    # Bildirimleri adada gösterilmeyecek uygulama adları
    "ignore_apps": [],
    # true: ada açıkken Plasma'nın kendi bildirim pencereleri bastırılır
    # (ada kapanınca otomatik normale döner)
    "suppress_plasma_popups": True,
    # true: tam ekran uygulama (oyun, video) açıkken ada tamamen gizlenir
    "hide_in_fullscreen": True,
    # Pano geçmişi (yalnızca bellekte tutulur, diske yazılmaz)
    "clipboard_history": True,
    # Şarkı sözleri (LRCLIB'e yalnızca söz görünümü açıkken sorulur)
    "lyrics": True,
    # Takvimdeki toplantıdan 5 dk önce uyarı
    "meeting_alerts": True,
    # Müzik çubukları gerçek sese göre (hoparlöre giden ses yalnızca bellekte çözümlenir)
    "spectrum": True,
    # Arayüz sesleri (yumuşak, sentezlenmiş); zamanlayıcı alarmı her zaman çalar
    "sounds": False,
    "sound_volume": 0.45,
    # İkinci bir şey olunca (ör. müzik + zamanlayıcı) ada ikiye bölünür, küçük bir daire ayrılır
    "split_island": True,
    # Ekran görüntüsü alınınca küçük önizleme: sürükleyip bırak, aç, kopyala
    "screenshot_preview": True,
    # Spectacle dışındaki araçların kayıt klasörleri de izlensin (ör. ["~/Resimler/Flameshot"])
    "screenshot_dirs": [],
    # Bildirimdeki doğrulama kodlarını adada büyük göster, dokununca kopyala
    "otp_capture": True,
    # Kamera / mikrofon / ekran paylaşımı noktaları
    "privacy_dots": True,
    # Hava durumu (Open-Meteo). Konum: {"city": "İstanbul"} ya da {"lat": 41.0, "lon": 29.0, "name": "Ev"};
    # boşsa IP adresinden yaklaşık konum bulunur.
    "weather_enabled": True,
    "weather": {"city": ""},
    # Telefon (KDE Connect): pil, gelen arama, telefonu çaldır
    "phone": True,
    # Panel düzeni ve görünüm (adanın Ayarlar → Sekmeler / Görünüm bölümünden değişir)
    #   tabs: sekme sırası, hidden: gizli sekmeler, open: "last" (son sekme) | "first" (ilk sekme)
    #   position: "center" | "left" | "right", accent: "auto" (albüm kapağından) | "#rrggbb"
    #   material: "minimal" (sade derinlik: kısık albüm ışığı, nötr kenar ışığı) | "ambient" (canlı albüm
    #             renkleri, vurgu renginde bas ve kenar ışığı) | "black" (düz siyah) | "glass" (sıvı cam:
    #             mercek, buzlu bulanıklık, özel parlama); glass: "frosted" | "balanced" | "clear"
    "layout": {"tabs": list(DEFAULT_ORDER), "hidden": [], "open": "last", "position": "center", "accent": "auto",
               "material": "minimal", "glass": "balanced"},
    # Arayüz dili: "auto" (sistem dili), "en" ya da "tr"
    "language": "auto",
    # Genel klavye kısayolları (KWin üzerinden). Boş bırakırsan o kısayol kapanır.
    "shortcuts": {
        "toggle_hide": "Meta+Alt+H",
        "toggle_panel": "Meta+Alt+I",
        "toggle_dnd": "Meta+Alt+D",
        "record": "Meta+Alt+R",
        "palette": "Meta+Alt+Space",
    },
}


def load():
    cfg = dict(DEFAULTS)
    try:
        with open(PATH) as f:
            cfg.update(json.load(f))
    except FileNotFoundError:
        try:
            os.makedirs(os.path.dirname(PATH), exist_ok=True)
            with private_open(PATH) as f:
                json.dump(DEFAULTS, f, indent=2, ensure_ascii=False)
        except OSError:
            pass
    except Exception as e:  # bozuk JSON: varsayılanlarla devam et
        print("config hatası:", e, flush=True)
    return cfg


# Adanın Ayarlar sayfasından değiştirilebilen açık/kapalı ayarlar
SWITCHES = ("suppress_plasma_popups", "hide_in_fullscreen", "clipboard_history",
            "lyrics", "meeting_alerts", "privacy_dots", "weather_enabled", "phone", "spectrum",
            "otp_capture", "sounds", "screenshot_preview", "split_island")


def set_switch(key, value):
    """Ayar dosyasında tek bir açık/kapalı ayarı değiştirir; dosyadaki diğer her şey korunur."""
    if key not in SWITCHES:
        return False
    return set_value(key, bool(value))


def set_value(key, value):
    """Ayar dosyasında tek bir değeri değiştirir; dosyadaki diğer her şey korunur."""
    try:
        with open(PATH) as f:
            data = json.load(f)
    except Exception:
        data = dict(DEFAULTS)
    data[key] = value
    tmp = PATH + ".tmp"
    os.makedirs(os.path.dirname(PATH), exist_ok=True)
    with private_open(tmp) as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    os.replace(tmp, PATH)
    return True


def clean_layout(d):
    """Arayüzden gelen düzeni doğrular; bilinmeyen değerler varsayılana döner."""
    base = DEFAULTS["layout"]
    d = d if isinstance(d, dict) else {}
    tabs = list(dict.fromkeys(t for t in d.get("tabs", []) if t in TABS)) or list(DEFAULT_ORDER)
    tabs += [t for t in DEFAULT_ORDER if t not in tabs]                     # eksikler (yeni sekmeler) sona
    hidden = [t for t in dict.fromkeys(d.get("hidden", [])) if t in TABS]
    if len(hidden) >= len(TABS):          # en az bir sekme görünür kalsın
        hidden = hidden[:-1]
    accent = str(d.get("accent", "auto"))
    if not re.fullmatch(r"#[0-9a-fA-F]{6}", accent):
        accent = "auto"
    return {
        "tabs": tabs,
        "hidden": hidden,
        "open": d.get("open") if d.get("open") in ("last", "first") else base["open"],
        "position": d.get("position") if d.get("position") in ("center", "left", "right") else base["position"],
        "accent": accent,
        "material": d.get("material") if d.get("material") in ("minimal", "ambient", "black", "glass") else base["material"],
        "glass": d.get("glass") if d.get("glass") in ("frosted", "balanced", "clear") else base["glass"],
    }


def mtime():
    try:
        return os.path.getmtime(PATH)
    except OSError:
        return 0


# -- Arayüz durumu (gizli mod, rahatsız etme): ayar dosyasından ayrı tutulur ----------
UI_PATH = os.path.expanduser("~/.local/state/dynamic-island/ui.json")
# focusDnd: Rahatsız Etme odak sayacı tarafından açıldı (arka uç kapanırsa açılışta geri alınır)
UI_DEFAULTS = {"hidden": False, "dnd": False, "focusDnd": False}


def load_ui():
    ui = dict(UI_DEFAULTS)
    try:
        with open(UI_PATH) as f:
            ui.update({k: bool(v) for k, v in json.load(f).items() if k in UI_DEFAULTS})
    except Exception:
        pass
    return ui


def save_ui(ui):
    try:
        os.makedirs(os.path.dirname(UI_PATH), exist_ok=True)
        with private_open(UI_PATH) as f:
            json.dump(ui, f)
    except OSError:
        pass
