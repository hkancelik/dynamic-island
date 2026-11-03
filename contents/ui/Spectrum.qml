import QtQuick

// Gerçek ses spektrumu (arka uç /spectrum, 0..100 değerler). mirror: bas ortada, tizler kenarlarda;
// centerGap > 0 ise ortada boşluk kalır (kontrollerin iki yanında akar, bas kontrollere yakın).
// Çubuklar alttan yükselir; değerler arasında kısa yumuşatma var, böylece 30 Hz'lik veri akıcı görünür.
Item {
    id: sp

    property var levels: []
    property bool mirror: true
    property color color: "white"
    property real gap: 3
    property real minBar: 1.5
    property real centerGap: 0
    readonly property var shown: {
        var l = levels || []
        if (!mirror) return l
        return l.slice().reverse().concat(l)
    }
    readonly property real barW: shown.length > 0
        ? Math.max(1.5, (width - centerGap - gap * (shown.length - 1)) / shown.length) : 0

    Row {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: sp.gap
        Repeater {
            model: sp.shown.length
            Item {
                required property int index
                // sol yarının son çubuğundan sonra ortadaki boşluk
                readonly property real extra: sp.centerGap > 0 && sp.mirror && index === sp.shown.length / 2 - 1 ? sp.centerGap : 0
                width: sp.barW + extra
                height: sp.height
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: sp.barW
                    radius: width / 2
                    height: Math.max(sp.minBar, sp.height * (sp.shown[parent.index] || 0) / 100)
                    Behavior on height { NumberAnimation { duration: 70; easing.type: Easing.OutQuad } }
                    gradient: Gradient {
                        GradientStop { position: 0; color: sp.color }
                        GradientStop { position: 1; color: Qt.rgba(sp.color.r, sp.color.g, sp.color.b, 0.25) }
                    }
                }
            }
        }
    }
}
