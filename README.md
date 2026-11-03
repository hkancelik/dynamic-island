# Dynamic Island (KDE Plasma)

KDE Plasma 6 (Wayland) için ekranın üstünde duran, Apple'ın Dynamic Island'ından esinlenen bir ada.

- **Müzik:** MPRIS oynatıcıları, kapak, ilerleme, ses çıkışı seçimi
- **Senkron şarkı sözleri:** [LRCLIB](https://lrclib.net)'ten; söylenen satır parlak, satıra tıkla → oraya atla.
  Yalnızca söz görünümü açıkken sorulur, sonuç `~/.cache/dynamic-island/lyrics` altında saklanır
- **Odak (Pomodoro):** halka + kalan süre, odak/mola süreleri; odakta Rahatsız Etme açılır,
  süre kapalı adada da görünür
- **Kapalı ada:** saat ortada; solda kapak / odak halkası / kayıt noktası, sağda müzik çubukları ve odak süresi.
  Ses, şarj, bildirim ve uyarılar kısa görünümlerle
- **Bildirimler:** Plasma bildirimleri adada toplanır, Rahatsız Etme; tıklayınca uygulama açılır
- **Takvim:** iCal/.ics adresleri ve CalDAV (Apple iCloud), adadan etkinlik ekleme
- **Kontrol:** ses, her ekranın ayrı parlaklığı (DDC/CI), Gece Işığı, Wi-Fi, Bluetooth, güç profili
- **Uygulamalar (arka planda çalışanlar, ✕ ile kapat), Sistem (CPU, bellek, ağ, sıcaklık, pil), Araçlar (pano, anımsatıcı, notlar, dosya rafı)**
- Ada ana ekranda durur; ekran çıkarılınca diğer ekrana geçer

- **Claude Code onayları:** izin istekleri adada (Reddet / İzin ver / Her zaman), iş bitince haber.
  Kurulum: `./install-claude-hooks.sh` (kaldırma: `--remove`). Ada kapalıysa ya da cevap gelmezse
  Claude Code terminalde her zamanki gibi sorar; terminalden cevaplanınca adadaki soru kalkar
- **Gizlilik noktaları:** kamera (yeşil), mikrofon (turuncu), ekran paylaşımı (mavi)
- **Uyarılar:** Caps Lock, Bluetooth cihazı (pil yüzdesiyle), internet kesildi/bağlandı,
  toplantıdan 5 dk önce ("Katıl" ile: Meet, Zoom, Teams, Webex)
- **Anımsatıcılar:** Araçlar → Anımsatıcı (yerel; Apple'ın yeni Anımsatıcılar'ı CalDAV'dan erişilemiyor)

- **Ayarlar:** saatin yanındaki dişli. Plasma bildirim pencereleri, tam ekranda gizle, pano geçmişi,
  şarkı sözleri, toplantı uyarısı, gizlilik noktaları, Claude Code onaylarını kur/kaldır
- **Hava durumu:** Sistem sekmesinde sıcaklık, durum, en yüksek/en düşük (Open-Meteo, anahtarsız).
  Konum: config.json'da `"weather": {"city": "İstanbul"}`; boşsa IP adresinden yaklaşık konum bulunur
- **Telefon (KDE Connect):** Sistem sekmesinde telefonun pil yüzdesi, dokununca telefon çalar;
  gelen aramada kapalı adada uyarı. Telefon bildirimleri zaten Plasma bildirimi olarak adaya düşer
- **Pano:** arama (Enter ilk sonucu kopyalar), sabitleme (Temizle sabitlenenleri silmez), kaç dk önce kopyalandığı;
  arama kutusuna işlem yazılırsa (`2*(3+4)`, `15%*200`, `2^10`) sonuç çıkar, dokununca kopyalanır

## Çalıştırma

```bash
./launch.sh    # arka uç + arayüz
./stop.sh      # durdur
./ctl.sh toggle
```

Oturumla birlikte başlatmak için (systemd kullanıcı servisi): `./install.sh` (kaldırma: `--remove`).
Arch/CachyOS'ta paket olarak: bu klasörde `makepkg -si`, sonra `systemctl --user enable --now dynamic-island`.
`./ctl.sh panel` ve `./ctl.sh tab 6` paneli açar (kısayol ve betikler için).

Gerekenler: `qml6`, `layer-shell-qt`, Kirigami, Python 3 (PyGObject, dbus-python),
`kscreen-doctor`, `nmcli`; telefon özelliği için `kdeconnect` (isteğe bağlı). Ayarlar: `~/.config/dynamic-island/config.json`
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
- `weather.py`, `phone.py`: hava durumu (Open-Meteo) ve KDE Connect (D-Bus)
- `caldav.py`, `calendar_ics.py`: bağımlılıksız CalDAV istemcisi ve iCalendar okuyucu
- `contents/ui/`: QML arayüz (`main.qml` ada ve panel, `IslandTabs.qml` sekme çubuğu, `View.qml`/`Bars.qml` ortak parçalar, `Page*.qml` sekmeler)
- `contents/icons/`: ikonlar Isle projesinden (GPL-3.0, bkz. `contents/icons/LICENSE-isle-GPL3.txt`)
