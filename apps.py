"""Uygulama kısayolları: .desktop dosyalarından ad/ikon okur, gtk-launch ile açar."""
import glob
import locale
import os
import subprocess

DIRS = [
    os.path.expanduser("~/.local/share/applications"),
    "/usr/share/applications",
    "/usr/local/share/applications",
    "/var/lib/flatpak/exports/share/applications",
    os.path.expanduser("~/.local/share/flatpak/exports/share/applications"),
]

_lang = (locale.getlocale()[0] or "en").split("_")[0]


def _find(app_id):
    for d in DIRS:
        p = os.path.join(d, app_id + ".desktop")
        if os.path.isfile(p):
            return p
    return None


def _parse(path):
    name = name_loc = icon = ""
    in_entry = False
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if line.startswith("["):
                    in_entry = line == "[Desktop Entry]"
                elif in_entry and "=" in line:
                    k, v = line.split("=", 1)
                    if k == "Name":
                        name = v
                    elif k == f"Name[{_lang}]":
                        name_loc = v
                    elif k == "Icon":
                        icon = v
    except OSError:
        pass
    return (name_loc or name), icon


def resolve(ids):
    out = []
    for app_id in ids:
        path = _find(app_id)
        if not path:
            continue
        name, icon = _parse(path)
        out.append({"id": app_id, "name": name or app_id, "icon": icon or "application-x-executable"})
    return out


def launch(app_id, known):
    """Yalnızca yapılandırmadaki (bilinen) kimlikler açılır."""
    if app_id not in {a["id"] for a in known}:
        return
    subprocess.Popen(
        ["gtk-launch", app_id],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def exists(app_id):
    import re
    return bool(re.fullmatch(r"[A-Za-z0-9._-]+", app_id or "")) and _find(app_id) is not None


def launch_desktop(app_id):
    """Bildirimin kaynağı olan uygulamayı aç (yalnızca var olan .desktop kimlikleri)."""
    if exists(app_id):
        subprocess.Popen(
            ["gtk-launch", app_id],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
