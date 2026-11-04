"""Arka uç ve `island` komutu için çeviri. Kaynak dil Türkçe; arayüzün çevirileri contents/ui/lang_*.js.

Dil: config.json "language" (auto|en|tr); auto ise LANGUAGE / LC_ALL / LC_MESSAGES / LANG.
"""
import json
import os

CONFIG = os.path.expanduser("~/.config/dynamic-island/config.json")

EN = {
    # island komutu
    "Dynamic Island çalışmıyor (./launch.sh)": "Dynamic Island isn't running (./launch.sh)",
    "komut gerekli": "a command is required",
    "komut bulunamadı": "command not found",
    "kesildi": "interrupted",
    "çıkış kodu %d": "exit code %d",
    "bitti": "done",
    "%d sn": "%ds",
    "%d dk %d sn": "%dm %ds",
    "%d sa %d dk": "%dh %dm",
    "Zamanlayıcı": "Timer",
    "Etkinlik yok.": "No activities.",
    "%d:%02d kaldı": "%d:%02d left",
    "sürüyor": "running",
    "böyle bir etkinlik yok: %s": "no such activity: %s",
    # etkinlik hataları
    "geçersiz id": "invalid id",
    "geçersiz süre": "invalid duration",
    "bilinmeyen işlem: %s": "unknown op: %s",
    # komut paleti (runners.py)
    "kopyalamak için Enter": "Enter to copy", "Klasörü aç": "Open folder", "Dosyayı aç": "Open file",
    "Aç": "Open", "Tarayıcıda aç": "Open in browser", "Arka planda çalıştır": "Run in background",
    "Terminalde çalıştır": "Run in terminal", "Sonlandır:": "Kill:", "Onaylamak için tekrar Enter": "Press Enter again to confirm",
    "Oturum": "Session", "Ekranı kilitle": "Lock screen", "Uyku": "Sleep", "Hazırda beklet": "Hibernate",
    "Oturumu kapat": "Log out", "Yeniden başlat": "Restart", "Bilgisayarı kapat": "Shut down",
    "Sistem Ayarları": "System Settings", "Son belge": "Recent file", "Yer imi": "Bookmark",
    "Konsole profili": "Konsole profile", "Hafta": "Week", "Renk · kopyalamak için Enter": "Colour · Enter to copy",
    "Doğru yazılmış": "Spelled correctly", "Öneri · kopyalamak için Enter": "Suggestion · Enter to copy",
    "Pencere": "Window", "Sekme": "Tab", "Geçmiş": "History",
    # maç takibi
    "%s kadrosu açıklandı": "%s lineup announced", "rakip: %s": "opponent: %s", "GOL! %s": "GOAL! %s",
    "Gol: %s": "Goal: %s", "Maç sona erdi: %s": "Full time: %s",
    "Şampiyonlar Ligi": "Champions League", "Avrupa Ligi": "Europa League", "Konferans Ligi": "Conference League",
    "Küme düşme": "Relegation", "Yükselme": "Promotion", "Yükselme play-off": "Promotion play-off",
    "Düşme play-off": "Relegation play-off", "Son 16": "Round of 16", "Eleme play-off": "Knockout play-off",
    "Elendi": "Eliminated", "Şampiyonlar Ligi'ne katılım": "Champions League qualification",
    # takvim
    "Etkinlik": "Event",
    "yazılabilir takvim yok (config'e caldav hesabı ekle)": "no writable calendar (add a caldav account to config)",
}


def lang():
    try:
        with open(CONFIG) as f:
            want = json.load(f).get("language", "auto")
    except (OSError, ValueError, AttributeError):
        want = "auto"
    if want in ("en", "tr"):
        return want
    for var in ("LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG"):
        v = os.environ.get(var, "")
        if v:
            return "tr" if v.startswith("tr") else "en"
    return "en"


_lang = None


def _(s):
    global _lang
    if _lang is None:
        _lang = lang()
    return s if _lang == "tr" else EN.get(s, s)


def current():
    """Etkin dil ("tr" ya da "en"), önbellekten."""
    global _lang
    if _lang is None:
        _lang = lang()
    return _lang


def reload():
    global _lang
    _lang = None
