"""KWin köprüsü: tam ekran algılama + genel (global) klavye kısayolları.

Wayland'da başka pencerelerin durumu ve global kısayollar doğrudan alınamaz; bu yüzden küçük
bir KWin betiği yüklenir. Betik, etkin pencere tam ekran olunca ve kısayollara basılınca bu
D-Bus nesnesini çağırır. Betik her açılışta yapılandırmadaki tuşlarla yeniden üretilir.
"""
import json
import os
import subprocess

import dbus
import dbus.service

BUS_NAME = "org.dynamicisland.Backend"
OBJ_PATH = "/Fullscreen"
PLUGIN = "dynamic-island-fullscreen"
SCRIPT = os.path.expanduser("~/.cache/dynamic-island/kwin.js")

# yapılandırma anahtarı -> (kısayol başlığı, komut)
SHORTCUTS = {
    "toggle_hide": ("Gizle/Göster", "toggle_hide"),
    "toggle_panel": ("Paneli aç/kapat", "toggle_panel"),
    "toggle_dnd": ("Rahatsız Etme", "toggle_dnd"),
    "record": ("Ekran kaydını başlat/durdur", "rec_toggle"),
}

TEMPLATE = """// Dynamic Island KWin köprüsü (otomatik üretilir, elle düzenlemeyin)
var hooked = {};
function call(method, arg) {
    callDBus("%(name)s", "%(path)s", "%(name)s", method, arg);
}
function report() {
    var w = workspace.activeWindow;
    call("SetFullscreen", !!(w && w.fullScreen));
}
function hook(w) {
    if (!w || hooked[w.internalId]) return;
    hooked[w.internalId] = true;
    if (w.fullScreenChanged) w.fullScreenChanged.connect(report);
}
workspace.windowActivated.connect(function (w) { hook(w); report(); });
workspace.windowAdded.connect(hook);
workspace.windowRemoved.connect(report);
workspace.windowList().forEach(hook);
report();
%(shortcuts)s
"""


def _kwin(*args):
    try:
        return subprocess.run(["qdbus6", "org.kde.KWin", "/Scripting", *args],
                              capture_output=True, text=True, timeout=4).stdout.strip()
    except Exception:
        return ""


def _script(keys):
    lines = []
    for key, (title, cmd) in SHORTCUTS.items():
        seq = keys.get(key)
        if seq:
            label = json.dumps("Dynamic Island: " + title, ensure_ascii=False)
            lines.append(f'registerShortcut({label}, {label}, {json.dumps(seq)}, '
                         f'function () {{ call("Command", {json.dumps(cmd)}); }});')
    return TEMPLATE % {"name": BUS_NAME, "path": OBJ_PATH, "shortcuts": "\n".join(lines)}


class Fullscreen(dbus.service.Object):
    def __init__(self, on_fullscreen, on_command, shortcuts):
        bus = dbus.SessionBus()
        # not: dbus.service.Object kendi `_name` özelliğini kullanır, çakışmasın
        self._busname = dbus.service.BusName(BUS_NAME, bus)
        super().__init__(bus, OBJ_PATH)
        self.on_fullscreen, self.on_command, self.shortcuts = on_fullscreen, on_command, shortcuts

    @dbus.service.method(BUS_NAME, in_signature="b", out_signature="")
    def SetFullscreen(self, fullscreen):
        self.on_fullscreen(bool(fullscreen))

    @dbus.service.method(BUS_NAME, in_signature="s", out_signature="")
    def Command(self, command):
        self.on_command(str(command))

    def load(self):
        os.makedirs(os.path.dirname(SCRIPT), exist_ok=True)
        with open(SCRIPT, "w") as f:
            f.write(_script(self.shortcuts))
        _kwin("unloadScript", PLUGIN)  # önceki çalıştırmadan kaldıysa
        if _kwin("loadScript", SCRIPT, PLUGIN):
            _kwin("start")

    def unload(self):
        _kwin("unloadScript", PLUGIN)
