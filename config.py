"""Kullanıcı yapılandırması: ~/.config/dynamic-island/config.json"""
import json
import os

PATH = os.path.expanduser("~/.config/dynamic-island/config.json")

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
    # Uygulamalar sekmesindeki kısayollar (.desktop dosya kimlikleri)
    "apps": [
        "firefox", "org.kde.konsole", "org.kde.dolphin", "org.kde.kate",
        "systemsettings", "org.kde.spectacle", "org.kde.kcalc", "org.kde.discover",
    ],
    # Bildirimleri adada gösterilmeyecek uygulama adları
    "ignore_apps": [],
    # true: ada açıkken Plasma'nın kendi bildirim pencereleri bastırılır
    # (ada kapanınca otomatik normale döner)
    "suppress_plasma_popups": True,
    # true: tam ekran uygulama (oyun, video) açıkken ada tamamen gizlenir
    "hide_in_fullscreen": True,
    # Pano geçmişi (yalnızca bellekte tutulur, diske yazılmaz)
    "clipboard_history": True,
    # Genel klavye kısayolları (KWin üzerinden). Boş bırakırsan o kısayol kapanır.
    "shortcuts": {
        "toggle_hide": "Meta+Alt+H",
        "toggle_panel": "Meta+Alt+I",
        "toggle_dnd": "Meta+Alt+D",
        "record": "Meta+Alt+R",
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
            with open(PATH, "w") as f:
                json.dump(DEFAULTS, f, indent=2, ensure_ascii=False)
        except OSError:
            pass
    except Exception as e:  # bozuk JSON: varsayılanlarla devam et
        print("config hatası:", e, flush=True)
    return cfg


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
        with open(UI_PATH, "w") as f:
            json.dump(ui, f)
    except OSError:
        pass
