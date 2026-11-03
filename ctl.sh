#!/usr/bin/env bash
# Çalışan Dynamic Island'ı komut satırından / kısayoldan denetler.
#   ./ctl.sh toggle   gizle/göster      ./ctl.sh hide | show
#   ./ctl.sh dnd      Rahatsız Etme aç/kapat
#   ./ctl.sh panel    paneli aç/kapat
#   ./ctl.sh tab N [B] paneli N. sekmede aç (Araçlar için B: 0 Pano, 1 Anımsatıcı, 2 Raf, 3 Notlar) (0 Müzik … 6 Sistem, 7 Araçlar, 8 Ayarlar)
case "$1" in
    toggle) cmd=toggle_hide ;;
    hide)   cmd=hide ;;
    show)   cmd=show ;;
    dnd)    cmd=toggle_dnd ;;
    panel)  cmd=toggle_panel ;;
    tab)    cmd=open_tab; arg="{\"tab\":${2:-0}${3:+,\"sub\":$3}}" ;;
    *) echo "Kullanım: $0 {toggle|hide|show|dnd|panel|tab N [B]}" >&2; exit 1 ;;
esac
TOKEN_FILE="${XDG_RUNTIME_DIR:-/tmp/dynamic-island-$(id -u)}/dynamic-island/token"
curl -s -m 2 -X POST http://127.0.0.1:47615/cmd \
    -H "X-Island: $(cat "$TOKEN_FILE" 2>/dev/null)" -H 'Content-Type: application/json' \
    -d "{\"cmd\":\"$cmd\"${arg:+,\"arg\":$arg}}" >/dev/null || { echo "Dynamic Island çalışmıyor." >&2; exit 1; }
