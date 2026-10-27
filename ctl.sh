#!/usr/bin/env bash
# Çalışan Dynamic Island'ı komut satırından / kısayoldan denetler.
#   ./ctl.sh toggle   gizle/göster      ./ctl.sh hide | show
#   ./ctl.sh dnd      Rahatsız Etme aç/kapat
case "$1" in
    toggle) cmd=toggle_hide ;;
    hide)   cmd=hide ;;
    show)   cmd=show ;;
    dnd)    cmd=toggle_dnd ;;
    *) echo "Kullanım: $0 {toggle|hide|show|dnd}" >&2; exit 1 ;;
esac
curl -s -m 2 -X POST http://127.0.0.1:47615/cmd \
    -H 'X-Island: 1' -H 'Content-Type: application/json' \
    -d "{\"cmd\":\"$cmd\"}" >/dev/null || { echo "Dynamic Island çalışmıyor." >&2; exit 1; }
