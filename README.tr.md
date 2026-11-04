# Dynamic Island (KDE Plasma)

[English](README.md) · **Türkçe**

KDE Plasma 6 (Wayland) için ekranın üstünde duran, Apple'ın Dynamic Island'ından esinlenen bir ada.

- **Canlı Etkinlikler:** betikler ve uygulamalar adaya kalıcı kart koyar: derleme, indirme, zamanlayıcı.
  Kapalı adada ilerleme halkası + kalan süre/yüzde, fare üstündeyken en yeni 3 etkinlik, bitince ✓/✗.
  Gizli modda ilerleme ince bir çizgi olarak görünür. `island` komutu:

  ```bash
  island run -- cargo build --release   # sürerken adada, bitince ✓ / ✗ (çıkış kodu korunur)
  island timer 25m Çay                   # geri sayım, bitince ses
  island progress yedek 42% -t "Yedekleme" -i upload
  island notify "Yedek bitti" "42 GB"
  ```
- **Kabuk entegrasyonu:** 10 sn'den uzun süren her komut bitince adada haber (`ISLAND_MIN_SECS`):
  `eval "$(island hook zsh)"`, `eval "$(island hook bash)"` ya da `island hook fish | source`
- **Bildirime dokun → uygulama açılır:** uygulama destekliyorsa doğrudan ilgili sohbet / e-posta / sekme
- **Komut paleti:** Meta+Alt+Space (ya da `island palette`), KRunner'ın yaptığı her şey adanın içinde:
  uygulamalar, açık pencereler, tarayıcı sekmeleri ve geçmişi, dosyalar (Baloo / plocate / yerleşik dizin),
  hesap ve birim (`10 km mi`, `72 f to c`), zamanlayıcı (`5m çay`), web kısayolları (`gg:` `yt:` `wp:` `gh:`
  `aur:`), konumlar (`~/Belgeler`, `github.com/kde`), kabuk (`> htop`), süreç sonlandırma (`kill firefox`),
  kapat / yeniden başlat / oturumu kapat (ikinci Enter ile onay), sistem ayarları sayfaları, son belgeler,
  yer imleri, dünya saati (`saat tokyo`), renk (`#0a84ff`), Unicode ve emoji (`u:heart`), pano, ada komutları.
  ↑/↓ seç, Enter çalıştır, Esc kapat
- **Malzeme (Ayarlar → Görünüm):** Minimal (varsayılan: derin siyah, albüm renginin yalnızca bir iması,
  ince kenar ışığı, buzlu cam kartlar), Sıvı cam (mercek kırılması, buzlu cam, özel parlama; imleci izleyen ışık, dokunma dalgası, duvar kağıdı yansıması, maddeleşme; bkz. docs/liquid-glass.md), Ambiyans (kapak renkleri panele yayılır, ışık müzikle nefes alır),
  Klasik siyah
- **Gerçek ses spektrumu:** müzik çubukları hoparlöre giden sesin frekanslarına göre (saf Python FFT,
  yalnızca bellekte, yalnızca çubuklar görünürken)
- **Sıvı geçişler:** seçim hapı gideceği sekmeye doğru damla gibi uzar, toplanır ve hafifçe sallanarak
  oturur; yeni sayfa hafif bir bulanıklıktan netleşerek kayar
- **Ada ikiye bölünür:** müzik çalarken bir zamanlayıcı başlatınca ince bir boyunla küçük bir daire
  damla gibi ayrılır, albüm kapağı onun içine süzülür; iş bitince geri erir. İki etkinlikte de bölünür
- **Tek kapak:** albüm kapağı tek bir nesne olarak kapalı ada, ayrılan daire, üzerine gelince açılan görünüm
  ve müzik sayfası arasında yaylanarak akar
- **Doğrulama kodları:** bildirimdeki kod (telefondan SMS, e-posta, 2FA) adada büyük görünür; dokununca
  kopyalanır. Yalnızca "kod / OTP / PIN / doğrulama" gibi sözcüklerin yakınındaki sayıları alır
- **Ekran görüntüsü önizlemesi:** ekran görüntüsü alınca küçük önizleme: başka uygulamaya sürükle, **Aç**
  ya da görüntüyü **Kopyala**. Spectacle ile kutudan çıktığı gibi çalışır
- **Hızlı Bakış:** dosyayı açmadan önizle: resim, PDF'in ilk sayfası, videodan kare, metin/kod, kapaklı
  ses, klasör. Komut paletinde `Ctrl+Y`, dosya rafında üstüne gelip `Boşluk`, ya da `island quicklook DOSYA`
- **Arayüz sesleri** (isteğe bağlı, Ayarlar → Özellikler): kodla sentezlenmiş yumuşak sesler; panel açılışı,
  iş bitişi, hata, ekran görüntüsü. Zamanlayıcı alarmı her zaman çalar
- **Kendine göre düzenle:** paneldeki bir sekmeyi basılı tutup sürükle, diğerleri kayarak yer açar.
  Ayarlar → Sekmeler: sırala, kullanmadıklarını gizle, panel son sekmede mi ilk sekmede mi açılsın.
  Ayarlar → Görünüm: ada solda, ortada ya da sağda; vurgu rengi albüm kapağından ya da sabit
- **Daha iyi söz bulma:** başlık aramadan önce temizlenir (`- Remastered 2011`, `(feat. X)`, `[Official Video]`,
  "- Topic" kanalları, YouTube'un "Sanatçı - Şarkı" başlıkları); sonuçlar başlık, sanatçı ve süreye göre
  puanlanır, aynı adlı başka şarkı seçilmez; sunucu meşgulse vazgeçmek yerine başka uç denenir. Yerel
  dosyanın yanındaki `sarki.lrc` çevrimdışı kullanılır. Bulunamazsa sözlerin altına "sanatçı şarkı" yaz;
  sonuç o şarkı için saklanır
- **İngilizce ve Türkçe arayüz:** sistem diline göre; Ayarlar → Dil
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
- **Hava durumu** kendi sekmesinde: şimdiki durum, önümüzdeki 9 saat (yağış ihtimalleriyle), 5 günlük tahmin
  ve "yağmur 4 sa sonra" uyarısı (Open-Meteo, anahtarsız). Simgeler proje için çizildi, simge temasına bağlı değil.
  Konum: config.json'da `"weather": {"city": "İstanbul"}`; boşsa IP adresinden yaklaşık konum bulunur
- **Maç** sekmesi: takip ettiğin takımın (varsayılan Liverpool) canlı skoru, sahada ilk 11 ve yedekler, sıradaki maçlar ve son sonuçlar. Kadro yayınlanınca bildirim, maç sırasında kapalı adada skor ve dakika; veri ESPN'den, anahtarsız.
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

- `activities.py`, `island`: Canlı Etkinlikler ve komut satırı aracı
- `i18n.py`, `contents/ui/lang_en.js`: çeviriler (kaynak dil Türkçe)
- `tests/`: `python -m unittest discover -s tests -t .`
- `backend.py`: durum + komut sunucusu (127.0.0.1:47615), MPRIS, ses, ağ, takvim, bildirimler
- `weather.py`, `football.py`, `wallpaper.py`, `phone.py`: hava durumu (Open-Meteo), maç takibi (ESPN), duvar kağıdı yolu (cam yansıması) ve KDE Connect (D-Bus)
- `caldav.py`, `calendar_ics.py`: bağımlılıksız CalDAV istemcisi ve iCalendar okuyucu
- `contents/ui/`: QML arayüz (`main.qml` ada ve panel, `IslandTabs.qml` sekme çubuğu, `View.qml`/`Bars.qml` ortak parçalar, `Page*.qml` sekmeler)
- `contents/icons/`: ikonlar Isle projesinden (GPL-3.0, bkz. `contents/icons/LICENSE-isle-GPL3.txt`)
