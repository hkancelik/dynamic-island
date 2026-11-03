"""Çalışan uygulamalar (systemd kullanıcı birimleri) ve .desktop dosyalarından ad/ikon okuma."""
import glob
import locale
import os
import re
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


SELF_ID = "dynamic-island"


def _unit_app_id(unit):
    """app-[başlatıcı-]<kimlik>[@rastgele].service|scope birim adından .desktop kimliği."""
    name = re.sub(r"\\x([0-9a-f]{2})", lambda m: chr(int(m.group(1), 16)), unit)
    name = re.sub(r"^app-", "", name)
    name = re.sub(r"\.(service|scope)$", "", name)
    name = re.sub(r"@.*$", "", name) if "@" in name else re.sub(r"-\d+$", "", name)
    cands = [name]
    if "-" in name:
        cands.append(name.split("-", 1)[1])   # başlatıcı öneki (ör. app-gnome-...)
    for c in cands:
        if _find(c):
            return c
    return None


def running():
    """Arka planda çalışan uygulamalar: [{id, name, icon, units}] (adanın kendisi hariç)."""
    try:
        out = subprocess.run(
            ["systemctl", "--user", "list-units", "--type=service,scope", "--state=running",
             "--no-legend", "--plain", "--full", "app-*"],
            capture_output=True, text=True, timeout=4).stdout
    except (OSError, subprocess.SubprocessError):
        return []
    found = {}
    for line in out.splitlines():
        parts = line.split()
        if not parts:
            continue
        app_id = _unit_app_id(parts[0])
        if not app_id or app_id == SELF_ID:
            continue
        if app_id not in found:
            name, icon = _parse(_find(app_id))
            found[app_id] = {"id": app_id, "name": name or app_id,
                             "icon": icon or "application-x-executable", "units": []}
        found[app_id]["units"].append(parts[0])
    return sorted(found.values(), key=lambda a: a["name"].lower())


def close(app_id, known):
    """Yalnızca çalışan (bilinen) uygulamanın birimlerini durdurur (SIGTERM)."""
    for a in known:
        if a["id"] == app_id:
            subprocess.Popen(
                ["systemctl", "--user", "stop", *a["units"]],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            return


def launch(app_id, known):
    """Yalnızca çalışan (bilinen) uygulamalar açılır/öne alınır."""
    if app_id in {a["id"] for a in known}:
        launch_desktop(app_id)


_by_name = None


def guess(app_name, icon=""):
    """Bildirimde desktop-entry ipucu yoksa uygulama adı/ikonundan .desktop kimliği tahmin et."""
    global _by_name
    app_name = str(app_name or "")
    for c in (app_name, app_name.lower(), app_name.lower().replace(" ", "-"), str(icon or "")):
        if exists(c):
            return c
    if _by_name is None:
        _by_name = {}
        for d in DIRS:
            for path in glob.glob(os.path.join(d, "*.desktop")):
                _by_name.setdefault(_parse(path)[0].lower(), os.path.basename(path)[:-8])
    return _by_name.get(app_name.lower(), "")


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
