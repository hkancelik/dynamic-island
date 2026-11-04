import QtQuick
import QtQuick.Layouts

// Ayarlar → Görünüm: adanın ekrandaki yeri ve vurgu rengi. Değişiklik anında görünür.
Item {
    id: ap

    property var sh

    readonly property var swatches: ["#0a84ff", "#30d158", "#ff9f0a", "#ff375f", "#bf5af2", "#64d2ff", "#ffd60a"]

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        Text {
            renderType: Text.CurveRendering
            font.family: "Inter"
            text: sh.t("Ada konumu")
            color: "white"
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }

        // Üç küçük ekran önizlemesi: adanın sol, orta ya da sağ üstte durduğu
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Repeater {
                model: [{ k: "left", l: sh.t("Sol") }, { k: "center", l: sh.t("Orta") }, { k: "right", l: sh.t("Sağ") }]
                Rectangle {
                    id: card
                    required property var modelData
                    readonly property bool sel: sh.position === modelData.k
                    Layout.fillWidth: true
                    Layout.preferredHeight: 96
                    radius: 16
                    color: cardMa.containsMouse ? Qt.rgba(1, 1, 1, 0.17) : Qt.rgba(1, 1, 1, 0.11)
                    border.width: sel ? 2 : 1
                    border.color: sel ? sh.accent : Qt.rgba(1, 1, 1, 0.08)
                    Behavior on border.color { ColorAnimation { duration: 200 } }

                    // mini ekran
                    Rectangle {
                        id: screenBox
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 12
                        width: parent.width - 36
                        height: 46
                        radius: 6
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: "#2b2e4a" }
                            GradientStop { position: 1; color: "#3d2c4e" }
                        }
                        Rectangle {    // mini ada
                            width: 34; height: 9; radius: 4.5
                            y: 0
                            color: "black"
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.12)
                            x: card.modelData.k === "left" ? 6
                             : card.modelData.k === "right" ? screenBox.width - width - 6
                             : (screenBox.width - width) / 2
                            Rectangle {
                                anchors.centerIn: parent
                                width: 12; height: 2; radius: 1
                                color: card.sel ? sh.accent : Qt.rgba(1, 1, 1, 0.5)
                            }
                        }
                    }
                    Text {
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 10
                        text: card.modelData.l
                        color: card.sel ? "white" : "#8e8e93"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: cardMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: sh.send("set_layout", { position: card.modelData.k })
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 10
            Column {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    text: sh.t("Vurgu rengi")
                    color: "white"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Text {
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    text: sh.accentFixed ? sh.t("Sabit renk") : sh.t("Otomatik · çalan şarkının kapağından")
                    color: Qt.rgba(1, 1, 1, 0.55)
                    font.pixelSize: 11
                }
            }
            // Otomatik: çok renkli halka
            Rectangle {
                readonly property bool sel: !sh.accentFixed
                width: 28; height: 28; radius: 14
                color: "transparent"
                border.width: 2
                border.color: sel ? "white" : "transparent"
                Rectangle {
                    anchors.centerIn: parent
                    width: 20; height: 20; radius: 10
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#ff375f" }
                        GradientStop { position: 0.5; color: "#bf5af2" }
                        GradientStop { position: 1; color: "#0a84ff" }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: "A"
                        color: "white"
                        font.family: "Inter"
                        font.pixelSize: 10
                        font.weight: Font.Bold
                    }
                }
                MouseArea { anchors.fill: parent; onClicked: sh.send("set_layout", { accent: "auto" }) }
            }
            Repeater {
                model: ap.swatches
                Rectangle {
                    required property string modelData
                    readonly property bool sel: sh.accentFixed && String(sh.layout.accent).toLowerCase() === modelData
                    width: 28; height: 28; radius: 14
                    color: "transparent"
                    border.width: 2
                    border.color: sel ? "white" : "transparent"
                    Rectangle {
                        anchors.centerIn: parent
                        width: 20; height: 20; radius: 10
                        color: parent.modelData
                        scale: swMa.containsMouse ? 1.12 : 1
                        Behavior on scale { NumberAnimation { duration: 120 } }
                    }
                    MouseArea {
                        id: swMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: sh.send("set_layout", { accent: parent.modelData })
                    }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Column {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 2
                Text {
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    text: sh.t("Malzeme")
                    color: "white"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Text {
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    text: sh.material === "minimal" ? sh.t("Sade derinlik: kısık albüm ışığı, ince kenar ışığı")
                        : sh.material === "ambient" ? sh.t("Canlı albüm renkleri, müzikle nefes alan ışık")
                        : sh.material === "glass" ? sh.t("Sıvı cam: arkasındakini büken mercek, buzlu cam, özel parlama")
                        : sh.t("Düz siyah çentik")
                    color: Qt.rgba(1, 1, 1, 0.55)
                    font.pixelSize: 11
                    width: parent.width
                    elide: Text.ElideRight
                }
            }
            Rectangle {
                width: matRow.implicitWidth + 6
                height: 28
                radius: 14
                color: Qt.rgba(1, 1, 1, 0.11)
                Row {
                    id: matRow
                    x: 3; y: 3
                    Repeater {
                        model: [{ k: "minimal", l: sh.t("Minimal") }, { k: "ambient", l: sh.t("Ambiyans") },
                                { k: "glass", l: sh.t("Sıvı cam") }, { k: "black", l: sh.t("Klasik siyah") }]
                        Rectangle {
                            required property var modelData
                            readonly property bool sel: sh.material === modelData.k
                            width: matText.implicitWidth + 22; height: 22; radius: 11
                            color: sel ? "#3a3a3c" : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text {
                                id: matText
                                renderType: Text.CurveRendering
                                font.family: "Inter"
                                anchors.centerIn: parent
                                text: modelData.l
                                color: parent.sel ? "white" : "#8e8e93"
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }
                            MouseArea { anchors.fill: parent; onClicked: sh.send("set_layout", { material: modelData.k }) }
                        }
                    }
                }
            }
        }
        // Sıvı cam ön ayarı: Buzlu (okunaklı) | Dengeli | Berrak (daha çok kırılma)
        RowLayout {
            visible: sh.material === "glass"
            Layout.fillWidth: true
            spacing: 12
            Text {
                renderType: Text.CurveRendering
                font.family: "Inter"
                text: sh.t("Cam stili")
                color: "white"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                Layout.fillWidth: true
            }
            Rectangle {
                width: glassRow.implicitWidth + 6
                height: 28
                radius: 14
                color: Qt.rgba(1, 1, 1, 0.11)
                Row {
                    id: glassRow
                    x: 3; y: 3
                    Repeater {
                        model: [{ k: "frosted", l: sh.t("Buzlu") }, { k: "balanced", l: sh.t("Dengeli") },
                                { k: "clear", l: sh.t("Berrak") }]
                        Rectangle {
                            required property var modelData
                            readonly property bool sel: sh.glassStyle === modelData.k
                            width: gText.implicitWidth + 22; height: 22; radius: 11
                            color: sel ? "#3a3a3c" : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text {
                                id: gText
                                renderType: Text.CurveRendering
                                font.family: "Inter"
                                anchors.centerIn: parent
                                text: modelData.l
                                color: parent.sel ? "white" : "#8e8e93"
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }
                            MouseArea { anchors.fill: parent; onClicked: sh.send("set_layout", { glass: modelData.k }) }
                        }
                    }
                }
            }
        }
        Item { Layout.fillHeight: true }
    }
}
