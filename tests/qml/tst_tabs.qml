import QtQuick
import QtTest
import "../../contents/ui"

// Sekme çubuğu ve Ayarlar → Sekmeler: basılı tutup sürükleyerek sıralama, dokunarak gizleme.
// Çalıştır: qmltestrunner -input tests/qml
Item {
    id: host
    width: 700; height: 200

    // main.qml'deki kökün yerine geçen küçük taklit
    QtObject {
        id: stub
        property int tab: 0
        property int unread: 0
        property var rec: ({ state: "idle" })
        property var layout: ({ open: "last" })
        property var tabOrder: [0, 1, 2, 3, 4, 5, 6, 7]
        property var allTabIds: [0, 1, 2, 3, 4, 5, 6, 7]
        property var hiddenIds: []
        property var saved: null
        function t(s) { return s }
        function ic(n) { return "" }
        function hiddenTabIds() { return hiddenIds }
        function saveTabs(order, hidden) { saved = { order: order, hidden: hidden }; tabOrder = order }
        function saveTabOrder(full, hidden) {
            saved = { order: full, hidden: hidden }
            allTabIds = full
            hiddenIds = hidden
            tabOrder = full.filter(function (id) { return hidden.indexOf(id) < 0 })
        }
        function send() {}
    }

    IslandTabs { id: bar; sh: stub; height: 36 }
    TabsEditor { id: editor; sh: stub; y: 60; width: 544; height: 140 }

    TestCase {
        name: "Tabs"
        when: windowShown

        function init() {
            stub.tab = 0; stub.saved = null; stub.hiddenIds = []
            stub.tabOrder = [0, 1, 2, 3, 4, 5, 6, 7]; stub.allTabIds = [0, 1, 2, 3, 4, 5, 6, 7]
            wait(400)   // animasyonlar otursun
        }

        function cellCenter(id) {
            return { x: bar.xOf(id) + bar.widthOf(id) / 2, y: 18 }
        }

        function test_click_selects() {
            var c = cellCenter(3)
            mouseClick(bar, c.x, c.y)
            compare(stub.tab, 3)
            compare(stub.saved, null)
        }

        function test_hold_and_drag_moves_music_to_end() {
            var c = cellCenter(0)
            mousePress(bar, c.x, c.y)
            wait(320)                                   // basılı tut
            for (var x = c.x; x <= bar.width + 20; x += 12) { mouseMove(bar, x, c.y); wait(5) }
            mouseRelease(bar, bar.width + 20, c.y)
            verify(stub.saved !== null, "sıra kaydedilmedi")
            compare(stub.saved.order, [1, 2, 3, 4, 5, 6, 7, 0])
            compare(bar.draft, null)
        }

        function test_short_press_does_not_drag() {
            var c = cellCenter(0)
            mousePress(bar, c.x, c.y)
            mouseMove(bar, c.x + 100, c.y)
            mouseRelease(bar, c.x + 100, c.y)
            compare(stub.saved, null)
        }

        function test_editor_drag_reorders() {
            var cw = editor.cellW + editor.gap
            var y = 60 + 40
            mousePress(host, cw * 0 + 20, y)
            for (var x = 20; x <= cw * 2 + 20; x += 10) { mouseMove(host, x, y); wait(5) }
            mouseRelease(host, cw * 2 + 20, y)
            verify(stub.saved !== null)
            compare(stub.saved.order, [1, 2, 0, 3, 4, 5, 6, 7])
        }

        function test_editor_tap_hides_and_shows() {
            var cw = editor.cellW + editor.gap
            mouseClick(host, cw * 5 + 20, 100)
            compare(stub.saved.hidden, [5])
            compare(stub.tabOrder.indexOf(5), -1)
            mouseClick(host, cw * 5 + 20, 100)
            compare(stub.saved.hidden, [])
        }

        function test_last_tab_cannot_be_hidden() {
            stub.hiddenIds = [1, 2, 3, 4, 5, 6, 7]
            stub.tabOrder = [0]
            var cw = editor.cellW + editor.gap
            stub.saved = null
            mouseClick(host, 20, 100)
            compare(stub.saved, null)
        }
    }
}
