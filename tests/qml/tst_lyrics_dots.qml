import QtQuick
import QtTest
import "../../contents/ui"

// Sözsüz aralardaki "nefes alan" üç nokta büyürken liste kenarında kırpılmamalı.
Item {
    id: host
    width: 504; height: 162

    QtObject {
        id: stub
        property var lyr: ({ track: "x", status: "synced", lines: [[0, "bir"], [2000, ""], [6000, "iki"]] })
        property real pos: 2500                       // şu anki satır: sözsüz ara
        property bool playing: false                  // animasyon çalışmasın; ölçeği elle ayarlarız
        property bool lyricsOn: true
        property var media: ({ title: "t", artist: "a", artUrl: "", canSeek: true, canNext: true, canPrev: true, length: 100000, player: "p" })
        function t(s) { return s }
        function ic(n) { return "" }
        function send() {}
        function updatePos() {}
    }

    Lyrics { id: lp; anchors.fill: parent; sh: stub }

    TestCase {
        name: "LyricsPauseDots"
        when: windowShown

        function test_dots_stay_inside_the_list_at_full_size() {
            wait(400)
            var list = findChild(lp, "lyricsList")
            verify(list !== null, "liste bulunamadı")
            for (var i = 0; i < 3; i++) {
                var dot = findChild(lp, "pauseDot" + i)
                verify(dot !== null, "nokta " + i + " bulunamadı")
                dot.scale = 1.35                                   // animasyonun en büyük hali
                var topLeft = dot.mapToItem(list, 0, 0)
                var bottomRight = dot.mapToItem(list, dot.width, dot.height)
                verify(topLeft.x >= 0, "nokta " + i + " sol kenardan taşıyor: x=" + topLeft.x)
                verify(topLeft.y >= 0 && bottomRight.y <= list.height, "nokta " + i + " dikeyde taşıyor")
                verify(bottomRight.x <= list.width, "nokta " + i + " sağdan taşıyor")
            }
        }
    }
}
