#!/usr/bin/env bash
# Claude Code'un izin isteklerini adaya yönlendiren hook'ları ~/.claude/settings.json'a ekler.
#   ./install-claude-hooks.sh           ekle (önce settings.json.bak-island yedeği alınır)
#   ./install-claude-hooks.sh --remove  kaldır
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] && cp "$SETTINGS" "$SETTINGS.bak-island"

python3 - "$SETTINGS" "python3 $DIR/agent_hook.py" "${1:-}" <<'EOF'
import json, os, sys
path, command, mode = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path) as f:
        s = json.load(f)
except FileNotFoundError:
    s = {}
hooks = s.setdefault("hooks", {})
ours = lambda h: h.get("command", "").endswith("/agent_hook.py")
for event, timeout in (("PermissionRequest", 600), ("Stop", 10)):
    groups = [g for g in hooks.get(event, [])
              if not any(ours(h) for h in g.get("hooks", []))]
    if mode != "--remove":
        groups.append({"hooks": [{"type": "command", "command": command, "timeout": timeout}]})
    if groups:
        hooks[event] = groups
    else:
        hooks.pop(event, None)
if not hooks:
    s.pop("hooks")
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(s, f, indent=2, ensure_ascii=False)
    f.write("\n")
os.replace(tmp, path)
print(("kaldırıldı: " if mode == "--remove" else "eklendi: ") + path)
EOF
