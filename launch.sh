#!/usr/bin/env bash
# Dynamic Island'ı başlatır: önce arka uç (HTTP, 127.0.0.1:47615), sonra QML arayüz.
DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

"$DIR/stop.sh" >/dev/null 2>&1

# Paket olarak /usr/share altına kurulunca salt okunur olabilir: .pyc yazma
export PYTHONDONTWRITEBYTECODE=1
# Arayüz API belirtecini dosyadan okur (yalnızca yerel dosya okuma)
export QML_XHR_ALLOW_FILE_READ=1
# QML hataları günlüğe düşsün (yoksa terminal dışında journald'a gider ve "Did not load" dışında iz kalmaz)
export QT_FORCE_STDERR_LOGGING=1
TOKEN_FILE="${XDG_RUNTIME_DIR:-/tmp/dynamic-island-$(id -u)}/dynamic-island/token"
rm -f "$TOKEN_FILE"

python3 "$DIR/backend.py" &
BACKEND=$!
trap 'kill $BACKEND 2>/dev/null' EXIT

# Arka ucun hazır olmasını bekle (en fazla ~3 sn)
for _ in $(seq 30); do
    [ -s "$TOKEN_FILE" ] && (exec 3<>/dev/tcp/127.0.0.1/47615) 2>/dev/null && break
    sleep 0.1
done

# Ana ekran (KDE'de en yüksek öncelikli çıkış); bulunamazsa Qt'nin birincil ekranı kullanılır.
# Ekran takılıp çıkarılınca arayüz 3 koduyla çıkar; ana ekran yeniden bulunup arayüz yeniden başlatılır.
# Ekran değişiminde arayüz çökerse de (SIGSEGV/SIGABRT vb.) yeniden başlatılır; yalnızca temiz çıkış (0)
# ve SIGTERM/SIGINT (stop.sh, oturum kapanışı) döngüyü bitirir.
while true; do
    PRIMARY="$(kscreen-doctor -j 2>/dev/null | python3 -c "
import json,sys
o=[x for x in json.load(sys.stdin)['outputs'] if x['enabled']]
print(min(o,key=lambda x:x['priority'])['name'])" 2>/dev/null)"

    qml6 "$DIR/contents/ui/main.qml" -- "$PRIMARY" "$TOKEN_FILE"
    case $? in
        0|130|143) break ;;
        *) sleep 1 ;;
    esac
done
