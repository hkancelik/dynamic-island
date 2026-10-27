"""Ses çıkış cihazları: listele, varsayılanı değiştir (çalan akışlar da taşınır)."""
import json
import os
import subprocess

ENV = {**os.environ, "LC_ALL": "C"}


def _pactl(*args, timeout=3):
    try:
        return subprocess.run(["pactl", *args], capture_output=True, text=True,
                              timeout=timeout, env=ENV).stdout
    except Exception:
        return ""


def _kind(sink):
    name = sink.get("name", "").lower()
    props = sink.get("properties", {})
    form = str(props.get("device.form_factor", "")).lower()
    if "bluez" in name or props.get("device.bus") == "bluetooth":
        return "bluetooth"
    if "hdmi" in name or "displayport" in name:
        return "display"
    if form in ("headphone", "headset", "hands-free", "handset"):
        return "headphones"
    if "headphone" in str(sink.get("active_port", "")).lower():
        return "headphones"
    return "speaker"


def snapshot():
    try:
        sinks = json.loads(_pactl("-f", "json", "list", "sinks") or "[]")
    except ValueError:
        sinks = []
    return {
        "default": _pactl("get-default-sink").strip(),
        "sinks": [{"name": s["name"], "desc": s.get("description", s["name"]), "kind": _kind(s)}
                  for s in sinks],
    }


def set_default(name, known):
    """Yalnızca listedeki bir cihaza geçilir; çalan akışlar da yeni cihaza taşınır."""
    if name not in {s["name"] for s in known}:
        return
    _pactl("set-default-sink", name)
    for line in _pactl("list", "short", "sink-inputs").splitlines():
        parts = line.split("\t")
        if parts and parts[0].isdigit():
            _pactl("move-sink-input", parts[0], name)
