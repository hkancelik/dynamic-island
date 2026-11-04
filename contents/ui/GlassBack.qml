import QtQuick
import QtQuick.Window

// Düz dolgulu butonun/kutunun üstüne oturan ince cam. Ebeveynin `radius`unu izler; ana pencerenin camı
// kapalıysa (sade/canlı malzeme) hiç görünmez, altındaki düz dolgu olduğu gibi kalır.
//   Rectangle { radius: 14; color: ...; GlassBack { hot: ma.containsMouse; down: ma.pressed } }
GlassSurface {
    id: gb

    property bool hot: false
    property bool down: false
    property bool shown: true
    readonly property var host: Window.window
    readonly property bool on: !!(host && host.glassLayer)

    anchors.fill: parent
    opacity: shown ? 1 : 0
    visible: on && opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 140 } }

    glassLayer: on ? host.glassLayer : null
    tick: on ? host.glassTick : 0
    thin: true
    radius: parent && parent.radius !== undefined ? parent.radius : 12
    frostAmount: on ? host.glassFrost : 0
    tintAmount: down ? 0.20 : 0.10
    bezelPx: Math.max(5, Math.min(10, Math.min(width, height) / 2.4))
    glow: down ? 0.55 : hot ? 0.28 : 0
    Behavior on glow { NumberAnimation { duration: 140 } }
}
