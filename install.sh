#!/usr/bin/env bash
# Dynamic Island'ı kullanıcı servisi olarak kurar: oturum açılınca kendiliğinden başlar.
#   ./install.sh            kur ve başlat (systemd --user)
#   ./install.sh --remove   servisi ve başlatıcıyı kaldır
set -euo pipefail
DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"

if [ "${1:-}" = "--remove" ]; then
    systemctl --user disable --now dynamic-island.service 2>/dev/null || true
    rm -f "$UNIT_DIR/dynamic-island.service" "$APPS_DIR/dynamic-island.desktop"
    systemctl --user daemon-reload
    echo "Dynamic Island servisi kaldırıldı."
    exit 0
fi

for cmd in python3 qml6 kscreen-doctor nmcli; do
    command -v "$cmd" >/dev/null || echo "Uyarı: '$cmd' bulunamadı (README'deki gereksinimlere bak)." >&2
done

mkdir -p "$UNIT_DIR" "$APPS_DIR"
sed "s|@DIR@|$DIR|g" "$DIR/dynamic-island.service" > "$UNIT_DIR/dynamic-island.service"
sed "s|@DIR@|$DIR|g" "$DIR/dynamic-island.desktop" > "$APPS_DIR/dynamic-island.desktop"
systemctl --user daemon-reload
systemctl --user enable --now dynamic-island.service
echo "Kuruldu. Durum: systemctl --user status dynamic-island   Günlük: journalctl --user -u dynamic-island"
