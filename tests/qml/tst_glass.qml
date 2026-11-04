import QtQuick
import QtTest
import "../../contents/ui"

// Cam bileşenleri yüklenir; konum ve bulanıklık girdileri doğru türetilir.
Item {
    id: host
    width: 300; height: 200

    GlassBackdrop { id: bd; width: 300; height: 200; Rectangle { anchors.fill: parent; color: "red" } }
    GlassSurface { id: gs; glassLayer: bd; x: 30; y: 20; width: 100; height: 50; radius: 25; thin: true }

    TestCase {
        name: "Glass"
        when: windowShown

        function test_back_rect_maps_into_backdrop() {
            var r = gs.backRect
            fuzzyCompare(r.x, 0.1, 1e-6); fuzzyCompare(r.y, 0.1, 1e-6)
            fuzzyCompare(r.z, 1 / 3, 1e-6); fuzzyCompare(r.w, 0.25, 1e-6)
        }
        function test_thin_glass_has_weaker_lens_and_rim() {
            verify(gs.lens < 0.5)
            verify(gs.rim < 1)
        }
        function test_samplers_come_from_backdrop() {
            verify(gs.backdrop === bd.sharp)
            verify(gs.backdropBlur === bd.soft)
        }
    }
}
