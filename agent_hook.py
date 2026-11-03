#!/usr/bin/env python3
"""Claude Code hook'u: izin isteklerini Dynamic Island'a sorar, iş bitince haber verir.

~/.claude/settings.json içinde (install-claude-hooks.sh ekler):
  PermissionRequest -> python3 agent_hook.py   (adada Reddet / İzin ver / Her zaman)
  Stop              -> python3 agent_hook.py   (adada "bitti")

Ada çalışmıyorsa, istek gösterilemeyecek kadar uzunsa ya da cevap gelmezse
hiçbir şey yazmaz: Claude Code terminalde her zamanki gibi sorar. Terminalden
cevaplanırsa (konuşma kaydına sonuç düşer) adadaki soru kaldırılır.
"""
import json
import os
import sys
import time
import urllib.request

URL = "http://127.0.0.1:47615/agent/"
MAX_SHOWN = 300          # bundan uzun / çok satırlı istekler terminalde sorulur
ANSWER_WITHIN = 590      # Claude Code hook süresi 600 sn


def token():
    base = os.environ.get("XDG_RUNTIME_DIR") or "/tmp/dynamic-island-%d" % os.getuid()
    with open(os.path.join(base, "dynamic-island", "token")) as f:
        return f.read().strip()


def post(what, body, timeout=12):
    req = urllib.request.Request(URL + what, data=json.dumps(body).encode(), method="POST",
                                 headers={"X-Island": token(), "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read() or b"{}")


def shown_line(tool_input):
    for key in ("command", "file_path", "path", "url", "pattern", "query"):
        v = tool_input.get(key) if isinstance(tool_input, dict) else None
        if isinstance(v, str):
            return v
    if isinstance(tool_input, dict):
        return ", ".join(f"{k}: {v}" for k, v in tool_input.items())
    return str(tool_input or "")


def rule_suggestions(p):
    """Claude'un "bir dahakine sorma" için önerdiği kurallar (yalnızca komut/klasör kuralları)."""
    return [r for r in p.get("permission_suggestions") or []
            if r.get("type") in ("addRules", "addDirectories")]


def answered_in_terminal(path, offset):
    """Hook başladıktan sonra konuşma kaydına bir araç sonucu düştü mü?"""
    try:
        with open(path, "rb") as f:
            f.seek(offset)
            return b"tool_result" in f.read(1 << 20)
    except OSError:
        return False


def permission(p):
    line = shown_line(p.get("tool_input"))
    if not line or "\n" in line or len(line) > MAX_SHOWN:
        return
    transcript = p.get("transcript_path") or ""
    try:
        offset = os.path.getsize(transcript) if transcript else 0
    except OSError:
        offset = 0
    try:
        aid = post("ask", {"provider": "claude", "cwd": p.get("cwd") or os.getcwd(),
                           "tool": p.get("tool_name", ""), "input": line,
                           "always": bool(rule_suggestions(p))}).get("id")
    except Exception:
        return   # ada çalışmıyor
    if not aid:
        return
    end = time.time() + ANSWER_WITHIN
    answer = ""
    try:
        while time.time() < end:
            answer = post("wait", {"id": aid, "timeout": 2}).get("answer", "")
            if answer:
                break
            if transcript and answered_in_terminal(transcript, offset):
                break
    except Exception:
        answer = ""
    finally:
        if not answer:
            try:
                post("cancel", {"id": aid}, timeout=3)
            except Exception:
                pass
    if answer == "deny":
        decision = {"behavior": "deny", "message": "Kullanıcı bunu Dynamic Island'dan reddetti."}
    elif answer == "always":
        decision = {"behavior": "allow", "updatedPermissions": rule_suggestions(p)}
    elif answer == "allow":
        decision = {"behavior": "allow"}
    else:
        return
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": decision}}))


def main():
    try:
        p = json.loads(sys.stdin.read(1 << 20) or "{}")
    except ValueError:
        return
    event = p.get("hook_event_name")
    if event == "PermissionRequest":
        permission(p)
    elif event == "Stop":
        try:
            post("done", {"provider": "claude", "cwd": p.get("cwd") or os.getcwd(),
                          "message": p.get("last_assistant_message", "")}, timeout=3)
        except Exception:
            pass


if __name__ == "__main__":
    main()
