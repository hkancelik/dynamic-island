"""Bildirim metninden doğrulama (tek kullanımlık) kodu ayıklar.

Yalnızca "kod / code / OTP / doğrulama / şifre / PIN…" gibi bir anahtar sözcüğün yakınındaki
sayıları alır; böylece "2500 TL yatırıldı" gibi bildirimler kod sayılmaz. Hiçbir yere kaydedilmez.
"""
import re

KEYWORDS = (
    "kod", "code", "otp", "doğrulama", "dogrulama", "verification", "verify", "şifre", "sifre",
    "password", "passcode", "pin", "güvenlik", "guvenlik", "security", "onay", "confirm", "2fa",
    "tek kullanımlık", "one-time", "one time", "login", "giriş", "giris", "sign in", "sign-in",
)
_KEY_RE = re.compile("|".join(re.escape(k) for k in KEYWORDS), re.I)
# 482913 · 123-456 · 123 456 · G-123456 · 4821
_NUM_RE = re.compile(r"(?<![\w.,:+#/-])(?:G-)?(\d{3}[ -]\d{3}|\d{4,8})(?![\w]|[.,]\d|:\d|\s?(?:%|TL|₺|\$|€|USD|EUR|km|kg|dk|sn|saat|gün|min|sec|hours?|days?)\b)",
                     re.I)
# anahtar sözcükten hemen sonra gelen harf-rakam kodları: "kod: AB12CD", "code is X7K9Q2"
_ALNUM_RE = re.compile(r"(?:kod\w*|code|otp|pin)\s*(?:[:=\-–—]|is|ise|budur)\s*([A-Za-z0-9]{5,8})\b", re.I)
YEAR = re.compile(r"^(19|20)\d{2}$")


def extract(*texts):
    """-> "482913" ya da "" (kod yok). Boşluk ve tireler atılır."""
    text = " ".join(str(t) for t in texts if t)
    if not text or not _KEY_RE.search(text):
        return ""
    keys = [m.span() for m in _KEY_RE.finditer(text)]
    best, best_d = "", 10 ** 6
    for m in _NUM_RE.finditer(text):
        digits = re.sub(r"\D", "", m.group(1))
        near = None
        for a, b in keys:
            d = m.start(1) - b if m.start(1) >= b else a - m.end(1)   # anahtardan sonra / önce
            d = d if m.start(1) >= b else d + 25                       # önce gelen biraz daha zayıf
            if near is None or d < near:
                near = d
        if near is None or near > 70:
            continue
        # tek başına yıl gibi duran 4 haneli sayı, anahtardan hemen sonra gelmedikçe kod değildir
        if YEAR.match(digits) and near > 6:
            continue
        if near < best_d:
            best, best_d = digits, near
    if best:
        return best
    m = _ALNUM_RE.search(text)
    if m and re.search(r"\d", m.group(1)) and re.search(r"[A-Za-z]", m.group(1)):
        return m.group(1).upper()
    return ""


def pretty(code):
    """Okunaklı gösterim: 482913 -> "482 913"."""
    return code[:3] + " " + code[3:] if len(code) == 6 and code.isdigit() else code
