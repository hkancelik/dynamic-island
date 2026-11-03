# Maintainer: Hakan <nailhakann@gmail.com>
# Yerel kaynaktan paket: bu klasörde `makepkg -si`
pkgname=dynamic-island
pkgver=0.2.0
pkgrel=1
pkgdesc="Dynamic Island for KDE Plasma 6 (Wayland): music, focus, notifications, calendar, controls"
arch=('any')
url="https://github.com/hkancelik/dynamic-island"
license=('GPL3')   # ikonlar Isle projesinden (GPL-3.0)
depends=('qt6-declarative' 'layer-shell-qt' 'kirigami' 'python' 'python-gobject' 'python-dbus'
         'libkscreen' 'networkmanager' 'wireplumber' 'libpulse')
optdepends=('kdeconnect: telefon pili, gelen arama, telefonu çaldır'
            'spectacle: ekran görüntüsü aracı'
            'ffmpeg: ekran kaydı'
            'bluez-utils: Bluetooth denetimi'
            'libsecret: iCloud parolası için secret-tool'
            'xdg-utils: bağlantıları ve klasörleri açmak için')
install=dynamic-island.install
source=()

package() {
    local src="$startdir" dest="$pkgdir/usr/share/$pkgname"
    install -dm755 "$dest"
    cp -r "$src"/*.py "$src"/*.sh "$src/island" "$src/contents" "$dest/"
    rm -rf "$dest/__pycache__"

    # Kullanıcı servisi (kurulu yol sabit)
    install -dm755 "$pkgdir/usr/lib/systemd/user"
    sed "s|@DIR@|/usr/share/$pkgname|g" "$src/dynamic-island.service" \
        > "$pkgdir/usr/lib/systemd/user/dynamic-island.service"
    install -dm755 "$pkgdir/usr/share/applications"
    sed "s|@DIR@|/usr/share/$pkgname|g" "$src/dynamic-island.desktop" \
        > "$pkgdir/usr/share/applications/dynamic-island.desktop"

    install -dm755 "$pkgdir/usr/bin"
    ln -s "/usr/share/$pkgname/launch.sh" "$pkgdir/usr/bin/dynamic-island"
    ln -s "/usr/share/$pkgname/ctl.sh" "$pkgdir/usr/bin/dynamic-island-ctl"
    ln -s "/usr/share/$pkgname/island" "$pkgdir/usr/bin/island"
    install -Dm644 "$src/LICENSE" "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
    install -Dm644 "$src/contents/icons/LICENSE-isle-GPL3.txt" \
        "$pkgdir/usr/share/licenses/$pkgname/LICENSE-isle-GPL3.txt"
}
