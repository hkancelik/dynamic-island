#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pkill -f "python3 $DIR/backend.py" 2>/dev/null
pkill -f "qml6 $DIR/contents/ui/main.qml" 2>/dev/null
echo "Dynamic Island durduruldu."
