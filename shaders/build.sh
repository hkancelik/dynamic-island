#!/usr/bin/env bash
# Shader'ları Qt'nin okuyacağı .qsb biçimine derler (Qt 6 qsb aracı gerekir). Çıktı contents/shaders'a gider.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
QSB="${QSB:-$(command -v qsb || echo /usr/lib/qt6/bin/qsb)}"
mkdir -p ../contents/shaders
for f in *.frag; do
    "$QSB" --glsl "100 es,120,150" --hlsl 50 --msl 12 -o "../contents/shaders/$f.qsb" "$f"
    echo "derlendi: contents/shaders/$f.qsb"
done
