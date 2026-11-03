import QtQuick

// "Sıvı cam" seçim hapı (sekme çubukları ve bölüm seçiciler).
// Sol ve sağ kenar ayrı yaylarla hareket eder: gidilen yöndeki kenar önden fırlar, arkadaki
// geriden gelir; hap bir su damlası gibi uzar, hacmini korumak için incelir, sonra hafifçe
// sallanarak yerine oturur. Hareket halindeyken cam "kalınlaşır": daha parlak, kenarı belirgin.
// Fizik fikri: sdegenaar/liquid_glass_widgets (jelly / squash & stretch), QML'e uyarlandı.
Item {
    id: lp

    property real goalX: 0
    property real goalW: 40
    property real baseH: 28
    property real restAlpha: 0.09        // durgunken dolgu (siyah üzerinde)
    property bool follow: false          // sürüklerken: yay yok, doğrudan izle

    property real l: goalX
    property real r: goalX + goalW
    property int dir: 1
    onGoalXChanged: dir = goalX >= l ? 1 : -1

    // önde giden kenar sert ve sönümlü, arkadaki yumuşak ve esnek
    Behavior on l {
        enabled: !lp.follow
        SpringAnimation { spring: lp.dir < 0 ? 6.0 : 2.6; damping: lp.dir < 0 ? 0.48 : 0.26; epsilon: 0.15 }
    }
    Behavior on r {
        enabled: !lp.follow
        SpringAnimation { spring: lp.dir > 0 ? 6.0 : 2.6; damping: lp.dir > 0 ? 0.48 : 0.26; epsilon: 0.15 }
    }

    readonly property real w: Math.max(baseH * 0.8, r - l)
    readonly property real stretch: Math.max(0, w / Math.max(1, goalW) - 1)
    readonly property real thick: Math.min(1, stretch * 4)        // 0 durgun .. 1 akıyor

    Rectangle {
        id: body
        x: lp.l
        width: lp.w
        height: lp.baseH * (1 - 0.14 * Math.min(1, lp.stretch * 2))
        anchors.verticalCenter: parent.verticalCenter
        radius: height / 2
        color: Qt.rgba(1, 1, 1, lp.restAlpha + 0.07 * lp.thick)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.07 + 0.13 * lp.thick)

        // üst parlama (speküler): camın kalınlığını hissettirir
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 1
            height: parent.height * 0.5
            radius: parent.radius - 1
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.10 + 0.12 * lp.thick) }
                GradientStop { position: 1; color: "transparent" }
            }
        }
    }
}
