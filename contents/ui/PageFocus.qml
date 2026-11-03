import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

// Odak: solda kalan süre halkası, ortada odak/mola süreleri, sağda başlat ve sıfırla.
Item {
    id: page

    property var sh

    readonly property var f: sh.pomo
    readonly property bool idle: f.phase === "idle"

    function mmss(ms) {
        var t = Math.ceil(ms / 1000)
        return String(Math.floor(t / 60)).padStart(2, "0") + ":" + String(t % 60).padStart(2, "0")
    }

    component Stepper: Rectangle {
        id: st
        property string label
        property int value
        property int step: 5
        property int min: 5
        property int max: 120
        signal changed(int v)
        width: 168; height: 36; radius: 18
        color: Qt.rgba(1, 1, 1, 0.11)
        Text {
            renderType: Text.CurveRendering
            font.family: "Inter"
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            text: st.label
            color: Qt.rgba(1, 1, 1, 0.55)
            font.pixelSize: 13
            font.weight: Font.Medium
        }
        Text {
            renderType: Text.CurveRendering
            font.family: "Inter"
            x: 70
            width: 28
            horizontalAlignment: Text.AlignHCenter
            anchors.verticalCenter: parent.verticalCenter
            text: st.value
            color: "white"
            font.pixelSize: 15
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            CtlButton {
                width: 28; height: 28; iconSize: 12
                icon: sh.ic("isle-minus-symbolic")
                enabledBtn: st.value > st.min
                onClicked: st.changed(Math.max(st.min, st.value - (st.value <= st.step ? 1 : st.step)))
            }
            CtlButton {
                width: 28; height: 28; iconSize: 12
                icon: sh.ic("isle-plus-symbolic")
                enabledBtn: st.value < st.max
                onClicked: st.changed(Math.min(st.max, st.value < st.step ? st.value + 1 : st.value + st.step))
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 24

        // Halka
        Item {
            Layout.preferredWidth: 124
            Layout.preferredHeight: 124
            Layout.alignment: Qt.AlignVCenter

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: Qt.rgba(1, 1, 1, 0.14)
                    strokeWidth: 4
                    fillColor: "transparent"
                    PathAngleArc { centerX: 62; centerY: 62; radiusX: 58; radiusY: 58; startAngle: 0; sweepAngle: 360 }
                }
                ShapePath {
                    strokeColor: sh.focusColor
                    strokeWidth: 4
                    capStyle: ShapePath.RoundCap
                    fillColor: "transparent"
                    PathAngleArc {
                        centerX: 62; centerY: 62; radiusX: 58; radiusY: 58
                        startAngle: -90
                        sweepAngle: page.idle ? 0 : 360 * sh.focusFrac
                        Behavior on sweepAngle { enabled: page.visible && !page.f.running; NumberAnimation { duration: 400 } }
                    }
                }
            }
            // başlangıç noktası
            Rectangle {
                visible: page.idle
                x: 62 - 3; y: 4 - 3 + 0.5
                width: 6; height: 6; radius: 3
                color: "white"
            }
            Column {
                anchors.centerIn: parent
                spacing: 1
                Text {
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: page.mmss(sh.focusLeft)
                    color: "white"
                    font.pixelSize: 24
                    font.weight: Font.DemiBold
                    font.letterSpacing: -0.5
                    font.features: { "tnum": 1 }
                }
                Text {
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: page.idle ? sh.t("Odak") : (page.f.phase === "break" ? sh.t("Mola") : sh.t("Odak"))
                          + (!page.idle && !page.f.running ? sh.t(" · duraklatıldı") : "")
                    color: page.idle ? Qt.rgba(1, 1, 1, 0.55) : sh.focusColor
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }
            }
        }

        // Süreler
        Column {
            Layout.alignment: Qt.AlignVCenter
            spacing: 8
            Stepper {
                label: sh.t("Odak")
                value: page.f.work
                onChanged: v => sh.send("focus_set", { work: v })
            }
            Stepper {
                label: sh.t("Mola")
                value: page.f.brk
                step: 5
                min: 1
                max: 60
                onChanged: v => sh.send("focus_set", { brk: v })
            }
            Text {
                renderType: Text.CurveRendering
                font.family: "Inter"
                x: 14
                text: page.f.round > 0 ? sh.t("%1 odak tamamlandı").arg(page.f.round) : sh.t("Odakta Rahatsız Etme açılır")
                color: Qt.rgba(1, 1, 1, 0.45)
                font.pixelSize: 11
            }
        }

        Item { Layout.fillWidth: true }

        // Kontroller
        Row {
            Layout.alignment: Qt.AlignVCenter
            spacing: 8
            CtlButton {
                width: 36; height: 36; iconSize: 15
                visible: !page.idle
                filled: true; fillColor: Qt.rgba(1, 1, 1, 0.17); tint: "white"
                icon: sh.ic("isle-forward-symbolic")
                onClicked: sh.send("focus_skip")
            }
            CtlButton {
                width: 36; height: 36; iconSize: 15
                visible: !page.idle
                filled: true; fillColor: Qt.rgba(1, 1, 1, 0.17); tint: "white"
                icon: sh.ic("isle-reset")
                onClicked: sh.send("focus_reset")
            }
            Rectangle {
                width: startText.implicitWidth + 50
                height: 36; radius: 18
                color: startMa.pressed ? "#48484a" : startMa.containsMouse ? "#3a3a3c" : Qt.rgba(1, 1, 1, 0.17)
                Row {
                    anchors.centerIn: parent
                    spacing: 7
                    Ico {
                        anchors.verticalCenter: parent.verticalCenter
                        source: page.f.running ? sh.ic("isle-pause-symbolic") : sh.ic("isle-play-symbolic")
                        size: 13
                        tint: "white"
                    }
                    Text {
                        id: startText
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        anchors.verticalCenter: parent.verticalCenter
                        text: page.f.running ? sh.t("Duraklat") : (page.idle ? sh.t("Başlat") : sh.t("Sürdür"))
                        color: "white"
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                }
                MouseArea {
                    id: startMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: sh.send("focus_toggle")
                }
            }
        }
    }
}
