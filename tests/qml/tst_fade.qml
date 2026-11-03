import QtQuick
import QtTest
import "../../contents/ui"

// FadeEdges: satır, görünümün kenarına yaklaştıkça saydamlaşır ve kenarda kaybolur.
Item {
    id: host
    width: 200; height: 120

    Flickable { id: view; width: 100; height: 100; contentWidth: 100; contentHeight: 1000 }
    FadeEdges { id: fade; view: view; fadeTop: 30; fadeBottom: 40 }
    Item { id: row; height: 20 }          // satır: y değiştirilerek konumlandırılır

    TestCase {
        name: "FadeEdges"

        function factorAt(y) { row.y = y; return fade.factor(row) }

        function init() { view.contentY = 0; fade.fadeTop = 30; fade.fadeBottom = 40 }

        function test_middle_is_fully_visible() {
            compare(factorAt(40), 1)                                // ortası 50
        }
        function test_fades_linearly_towards_the_top() {
            fuzzyCompare(factorAt(5), 0.5, 1e-6)                    // orta 15 → 15/30
            compare(factorAt(-10), 0)                               // ortası kenarda → kayıp
            compare(factorAt(-50), 0)                               // görünümün dışı: negatif olmaz
        }
        function test_fades_linearly_towards_the_bottom() {
            fuzzyCompare(factorAt(70), 0.5, 1e-6)                   // orta 80 → (100-80)/40
            compare(factorAt(90), 0)                                // orta 100 → kenar
            compare(factorAt(300), 0)
        }
        function test_follows_scrolling() {
            view.contentY = 200
            compare(factorAt(240), 1)                               // satır görünümde 40'ta
            compare(factorAt(190), 0)                               // üst kenarın üstünde
        }
        function test_zero_means_off() {
            fade.fadeTop = 0
            fade.fadeBottom = 0
            compare(factorAt(-5), 1)
            compare(factorAt(95), 1)
        }
        function test_missing_view_or_item_is_harmless() {
            compare(fade.factor(null), 1)
            var empty = Qt.createQmlObject('import QtQuick; import "../../contents/ui"; FadeEdges {}', host)
            compare(empty.factor(row), 1)
        }
    }
}
