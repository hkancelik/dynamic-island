import QtQuick
import QtTest
import "../../contents/ui"

// Alt bas ışığı şeridi, adanın köşesinin dışına taşmamalı. QML Rectangle köşe yarıçapını
// yüksekliğinin yarısıyla sınırlar; şerit yarıçapın iki katı kadar yüksek olmalı.
Item {
    id: host
    width: 600; height: 224

    Ambient { id: amb; anchors.fill: parent; radius: 36; bass: 1 }

    TestCase {
        name: "AmbientGlow"
        when: windowShown

        function strip() { return findChild(amb, "glowUnder") }

        function test_strip_is_tall_enough_for_the_full_corner_radius() {
            verify(strip() !== null)
            verify(strip().height >= 2 * amb.radius, "yükseklik " + strip().height + " < " + 2 * amb.radius)
            compare(strip().bottomLeftRadius, 36)
            compare(strip().bottomRightRadius, 36)
        }

        function test_follows_a_smaller_radius_and_never_exceeds_the_island() {
            amb.radius = 16                       // kapalı ada: çentik yarıçapı 16
            host.height = 32
            verify(strip().height >= 32 || strip().height >= 2 * amb.radius)
            verify(strip().height <= host.height, "ada yüksekliğini aşmamalı")
            amb.radius = 36
            host.height = 224
            verify(strip().height >= 72)
        }
    }
}
