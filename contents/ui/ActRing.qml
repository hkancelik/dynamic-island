import QtQuick
import QtQuick.Shapes

// Canlı Etkinlik halkası: frac 0..1 ise dolan halka, < 0 ise belirsiz (dönen yay).
// İçinde isteğe bağlı ikon.
Item {
    id: ring

    property real frac: -1
    property color color: "white"
    property string icon: ""
    property real thickness: 2.5
    property bool live: true            // görünmüyorken dönme animasyonu dursun
    readonly property real r: width / 2 - thickness / 2

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: Qt.rgba(1, 1, 1, 0.16)
            strokeWidth: ring.thickness
            fillColor: "transparent"
            PathAngleArc { centerX: ring.width / 2; centerY: ring.height / 2; radiusX: ring.r; radiusY: ring.r; startAngle: 0; sweepAngle: 360 }
        }
        ShapePath {
            strokeColor: ring.color
            strokeWidth: ring.thickness
            capStyle: ShapePath.RoundCap
            fillColor: "transparent"
            PathAngleArc {
                id: arc
                centerX: ring.width / 2; centerY: ring.height / 2; radiusX: ring.r; radiusY: ring.r
                startAngle: ring.frac < 0 ? spin.angle : -90
                sweepAngle: ring.frac < 0 ? 90 : 360 * Math.max(0, Math.min(1, ring.frac))
                Behavior on sweepAngle { enabled: ring.frac >= 0; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            }
        }
    }

    Item {
        id: spin
        property real angle: -90
        NumberAnimation on angle {
            running: ring.frac < 0 && ring.live && ring.visible
            from: -90; to: 270
            duration: 900
            loops: Animation.Infinite
        }
    }

    Ico {
        visible: ring.icon !== ""
        anchors.centerIn: parent
        source: ring.icon
        size: Math.round(ring.width * 0.42)
        tint: "white"
    }
}
