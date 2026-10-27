# Dynamic Island (KDE Plasma)

KDE Plasma 6 (Wayland) için ekranın üstünde duran, Apple'ın Dynamic Island'ından ve
[Isle](https://github.com/zickrian/isle)'ın tasarımından esinlenen bir ada.

- **Müzik:** MPRIS oynatıcıları, kapak, ilerleme, ses çıkışı seçimi
- **Senkron şarkı sözleri:** [LRCLIB](https://lrclib.net)'ten; söylenen satır parlak, satıra tıkla → oraya atla.
  Yalnızca söz görünümü açıkken sorulur, sonuç `~/.cache/dynamic-island/lyrics` altında saklanır
- **Odak (Pomodoro):** halka + kalan süre, odak/mola süreleri; odakta Rahatsız Etme açılır,
  süre kapalı adada da görünür
- **Kapalı ada:** saat ortada; solda kapak / odak halkası / kayıt noktası, sağda müzik çubukları ve odak süresi.
  Ses, şarj, bildirim ve uyarılar Isle tarzı kısa görünümlerle
- **Bildirimler:** Plasma bildirimleri adada toplanır, Rahatsız Etme
- **Takvim:** iCal/.ics adresleri ve CalDAV (Apple iCloud), adadan etkinlik ekleme
- **Kontrol:** ses, her ekranın ayrı parlaklığı (DDC/CI), Gece Işığı, Wi-Fi, Bluetooth, güç profili
- **Uygulamalar, Sistem (CPU, bellek, ağ, sıcaklık, pil), Araçlar (pano, notlar, dosya rafı)**
- Ada ana ekranda durur; ekran çıkarılınca diğer ekrana geçer

- **Claude Code onayları:** izin istekleri adada (Reddet / İzin ver / Her zaman), iş bitince haber.
  Kurulum: `./install-claude-hooks.sh` (kaldırma: `--remove`). Ada kapalıysa ya da cevap gelmezse
  Claude Code terminalde her zamanki gibi sorar; terminalden cevaplanınca adadaki soru kalkar
- **Gizlilik noktaları:** kamera (yeşil), mikrofon (turuncu), ekran paylaşımı (mavi)
- **Uyarılar:** Caps Lock, Bluetooth cihazı (pil yüzdesiyle), internet kesildi/bağlandı,
  toplantıdan 5 dk önce ("Katıl" ile: Meet, Zoom, Teams, Webex)
- **Anımsatıcılar:** Araçlar → Anımsatıcı (yerel; Apple'ın yeni Anımsatıcılar'ı CalDAV'dan erişilemiyor)

## Çalıştırma

```bash
./launch.sh    # arka uç + arayüz
./stop.sh      # durdur
./ctl.sh toggle
```

Gerekenler: `qml6`, `layer-shell-qt`, Kirigami, Python 3 (PyGObject, dbus-python),
`kscreen-doctor`, `nmcli`. Ayarlar: `~/.config/dynamic-island/config.json`
(adada Takvim → "Ayar dosyasını aç").

### Apple iCloud takvimi

1. account.apple.com → Oturum Açma ve Güvenlik → Uygulamaya özel parolalar
2. `secret-tool store --label="Dynamic Island iCloud" service dynamic-island account icloud`
3. config.json:

```json
"caldav": [{
  "name": "iCloud",
  "url": "https://caldav.icloud.com",
  "user": "apple-kimliginiz@icloud.com",
  "password_cmd": "secret-tool lookup service dynamic-island account icloud"
}]
```

## Yapı

- `backend.py`: durum + komut sunucusu (127.0.0.1:47615), MPRIS, ses, ağ, takvim, bildirimler
- `caldav.py`, `calendar_ics.py`: bağımlılıksız CalDAV istemcisi ve iCalendar okuyucu
- `contents/ui/`: QML arayüz (`main.qml` ada ve panel, `Page*.qml` sekmeler)
- `contents/icons/`: [Isle](https://github.com/zickrian/isle)'ın ikonları (GPL-3.0, bkz. `contents/icons/LICENSE-isle-GPL3.txt`)
