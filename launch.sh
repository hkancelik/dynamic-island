#!/usr/bin/env bash
# Dynamic Island'ı başlatır: önce arka uç (HTTP, 127.0.0.1:47615), sonra QML arayüz.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$DIR/stop.sh" >/dev/null 2>&1

python3 "$DIR/backend.py" &
BACKEND=$!
trap 'kill $BACKEND 2>/dev/null' EXIT

# Arka ucun hazır olmasını bekle (en fazla ~3 sn)
for _ in $(seq 30); do
    (exec 3<>/dev/tcp/127.0.0.1/47615) 2>/dev/null && break
    sleep 0.1
done

# Ana ekran (KDE'de en yüksek öncelikli çıkış); bulunamazsa Qt'nin birincil ekranı kullanılır.
# Ekran takılıp çıkarılınca arayüz 3 koduyla çıkar; ana ekran yeniden bulunup arayüz yeniden başlatılır.
while true; do
    PRIMARY="$(kscreen-doctor -j 2>/dev/null | python3 -c "
import json,sys
o=[x for x in json.load(sys.stdin)['outputs'] if x['enabled']]
print(min(o,key=lambda x:x['priority'])['name'])" 2>/dev/null)"

    qml6 "$DIR/contents/ui/main.qml" -- "$PRIMARY"
    [ $? -eq 3 ] || break
done
