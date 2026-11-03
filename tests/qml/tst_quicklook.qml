import QtQuick
import QtTest
import "../../contents/ui"

// Komut paleti (Ctrl+Y) ve Hızlı Bakış'ın klavye davranışı, simüle edilmiş tuşlarla.
Item {
    id: host
    width: 700; height: 500

    QtObject {
        id: stub
        property string lang: "tr"
        property string token: ""
        property string endpoint: ""
        property var clip: []
        property bool paletteOpen: true
        property int tab: 0
        property int toolsSub: 0
        property int settingsSub: 0
        property bool panelOpen: false
        property var quickInfo: ({})
        property string quickPath: ""
        property int closed: 0
        property var sent: []
        function t(s) { return s }
        function ic(n) { return "" }
        function send(cmd, arg) { sent = sent.concat([{ cmd: cmd, arg: arg }]) }
        function sound(n) {}
        function toast(a, b) {}
        function fmtDate(ms) { return "01.01.2026 10:00" }
        function openQuickLook(p) { quickPath = p }
        function closeQuickLook() { closed++ }
    }

    CommandPalette { id: pal; sh: stub; width: 640; height: 400; open: false }
    QuickLook { id: ql; sh: stub; width: 520; height: 340; y: 0 }

    TestCase {
        name: "QuickLook"
        when: windowShown

        function init() { stub.quickPath = ""; stub.closed = 0; stub.sent = [] }

        function openPalette() {
            pal.open = false
            pal.open = true
            var input = findChild(pal, "paletteInput")
            verify(input !== null, "arama kutusu bulunamadı")
            tryVerify(function () { return input.activeFocus }, 2000)
            return input
        }

        function test_ctrl_y_previews_selected_file() {
            openPalette()
            pal.remote = [{ kind: "path", path: "/tmp/demo.png", title: "demo.png", subtitle: "", icon: "text-x-generic", score: 50 }]
            pal.remoteFor = pal.query
            compare(pal.results[0].title, "demo.png")
            keyClick(Qt.Key_Y, Qt.ControlModifier)
            compare(stub.quickPath, "/tmp/demo.png")
        }

        function test_ctrl_space_also_works() {
            openPalette()
            pal.remote = [{ kind: "path", path: "/tmp/a.pdf", title: "a.pdf", subtitle: "", icon: "x", score: 50 }]
            pal.remoteFor = pal.query
            keyClick(Qt.Key_Space, Qt.ControlModifier)
            compare(stub.quickPath, "/tmp/a.pdf")
        }

        function test_ctrl_y_ignores_non_files() {
            openPalette()
            pal.remote = [{ kind: "app", id: "firefox", title: "Firefox", subtitle: "", icon: "firefox", score: 50 }]
            pal.remoteFor = pal.query
            keyClick(Qt.Key_Y, Qt.ControlModifier)
            compare(stub.quickPath, "")
        }

        function test_plain_space_still_types_in_search() {
            var input = openPalette()
            keyClick(Qt.Key_A)
            keyClick(Qt.Key_Space)
            keyClick(Qt.Key_B)
            compare(input.text, "a b")
            compare(stub.quickPath, "")
        }

        function test_height_follows_content_kind() {
            var cases = { image: 338, pdf: 338, video: 338, text: 296, audio: 196, folder: 196 }
            for (var k in cases) {
                stub.quickInfo = { kind: k, name: "x" }
                compare(ql.wantH, cases[k], k)
            }
            stub.quickInfo = { name: "yükleniyor" }
            compare(ql.kind, "loading")
            compare(ql.wantH, 196)
        }

        function test_space_and_escape_close_enter_opens() {
            stub.quickInfo = { kind: "text", name: "a.txt", path: "/tmp/dir/a.txt", text: "merhaba" }
            pal.open = false
            pal.visible = false                       // palet arama kutusu odağı almasın
            pal.enabled = false                       // devre dışı öğe tuş almaz (odak yarışı olmasın)
            ql.focusMe()
            var keysItem = findChild(ql, "qlKeys")
            tryVerify(function () { return keysItem.activeFocus }, 2000)
            keyClick(Qt.Key_Space)
            compare(stub.closed, 1)
            keyClick(Qt.Key_Escape)
            compare(stub.closed, 2)
            keyClick(Qt.Key_Return)
            compare(stub.sent.length, 1)
            compare(stub.sent[0].cmd, "palette_run")
            compare(stub.sent[0].arg.path, "/tmp/dir/a.txt")
            compare(stub.closed, 3)           // açınca kapanır
            pal.enabled = true
            pal.visible = true
        }

        function test_meta_line() {
            stub.quickInfo = { kind: "pdf", name: "r.pdf", sizeText: "443 KB", pages: 5, mtime: 1 }
            compare(ql.metaLine(), "PDF · 443 KB · 5 sayfa · 01.01.2026 10:00")
        }
    }
}
