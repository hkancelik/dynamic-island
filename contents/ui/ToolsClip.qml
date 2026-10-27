import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Pano geçmişi (Isle düzeni): arama, sabitleme; öğeye tıkla → panoya geri konur.
Item {
    id: page

    property var sh
    property string query: ""

    onVisibleChanged: if (!visible) { query = ""; search.text = "" }

    readonly property var shown: {
        var q = query.trim().toLocaleLowerCase("tr-TR")
        if (!q) return sh.clip
        return sh.clip.filter(function (c) { return c.text.toLocaleLowerCase("tr-TR").indexOf(q) >= 0 })
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            spacing: 8

            TextField {
                id: search
                Layout.fillWidth: true
                Layout.preferredHeight: 28
                placeholderText: sh.clip.length > 0 ? sh.clip.length + " öğede ara" : "Pano geçmişi"
                placeholderTextColor: Qt.rgba(1, 1, 1, 0.4)
                color: "white"
                font.family: "Inter"
                font.pixelSize: 13
                leftPadding: 30
                rightPadding: 10
                selectByMouse: true
                enabled: sh.clip.length > 0
                onTextChanged: page.query = text
                Keys.onEscapePressed: { text = ""; sh.panelOpen = false }
                // Enter: ilk sonucu kopyala
                onAccepted: if (page.shown.length > 0) page.copy(page.shown[0])
                background: Rectangle {
                    radius: 14
                    color: "#1c1c1e"
                    border.width: search.activeFocus ? 1 : 0
                    border.color: Qt.rgba(1, 1, 1, 0.16)
                    Ico {
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        source: sh.ic("isle-search")
                        size: 13
                        tint: Qt.rgba(1, 1, 1, 0.5)
                    }
                }
            }
            Rectangle {
                visible: sh.clip.length > 0
                Layout.preferredWidth: clrText.implicitWidth + 24
                Layout.preferredHeight: 26
                radius: 13
                color: clrMa.pressed ? "#48484a" : clrMa.containsMouse ? "#3a3a3c" : "#2c2c2e"
                Text {
                    id: clrText
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    anchors.centerIn: parent
                    text: "Temizle"
                    color: "white"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                MouseArea {
                    id: clrMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: sh.send("clip_clear")
                }
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: -8
            Layout.rightMargin: -8
            model: page.shown
            spacing: 0
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: row
                required property var modelData
                width: list.width
                height: 32
                radius: 10
                color: itemMa.pressed ? Qt.rgba(1, 1, 1, 0.1) : (hov.hovered ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
                HoverHandler { id: hov }

                Ico {
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    source: sh.ic(row.modelData.link ? "isle-link" : "isle-text")
                    size: 14
                    tint: row.modelData.pinned ? "#ff9f0a" : Qt.rgba(1, 1, 1, 0.5)
                }
                Text {
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    x: 34
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 34 - (hov.hovered || row.modelData.pinned ? 64 : 12)
                    text: row.modelData.text.replace(/\s+/g, " ")
                    color: row.modelData.link ? "#64d2ff" : "white"
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }
                MouseArea {
                    id: itemMa
                    anchors.fill: parent
                    onClicked: page.copy(row.modelData)
                }
                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    CtlButton {
                        visible: hov.hovered || row.modelData.pinned
                        width: 24; height: 24; iconSize: 13
                        icon: sh.ic(row.modelData.pinned ? "isle-pin-fill" : "isle-pin")
                        tint: row.modelData.pinned ? "#ff9f0a" : Qt.rgba(1, 1, 1, 0.7)
                        onClicked: sh.send("clip_pin", row.modelData.id)
                    }
                    CtlButton {
                        visible: hov.hovered
                        width: 24; height: 24; iconSize: 10
                        icon: sh.ic("isle-close-symbolic")
                        tint: Qt.rgba(1, 1, 1, 0.7)
                        onClicked: sh.send("clip_del", row.modelData.id)
                    }
                }
            }
        }
    }

    function copy(item) {
        sh.send("clip_copy", item.id)
        sh.toast("Panoya kopyalandı", "edit-copy")
        sh.panelOpen = false
    }

    Text {
        renderType: Text.CurveRendering
        font.family: "Inter"
        visible: sh.clip.length === 0 || page.shown.length === 0
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 14
        width: parent.width - 48
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: !sh.clipOn ? "Pano geçmişi bu oturumda kullanılamıyor"
            : sh.clip.length === 0 ? "Kopyaladıkların burada görünür"
            : "Sonuç yok"
        color: Qt.rgba(1, 1, 1, 0.55)
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }
}
