import QtQuick
import QtQuick.Layouts

// Ayarlar → Sekmeler: sürükleyerek sırala, dokunarak gizle/göster, panelin açılacağı sekme.
Item {
    id: ed

    property var sh

    readonly property var icons: [sh.ic("isle-music"), sh.ic("isle-bell"), sh.ic("isle-timer"), sh.ic("isle-calendar"),
                                  sh.ic("isle-sun-symbolic"), "view-app-grid-symbolic", sh.ic("isle-gauge"), sh.ic("isle-shelf")]
    readonly property var labels: [sh.t("Müzik"), sh.t("Bildirim"), sh.t("Odak"), sh.t("Takvim"),
                                   sh.t("Kontrol"), sh.t("Uygulama"), sh.t("Sistem"), sh.t("Araçlar")]

    property var draft: null
    property int dragId: -1
    readonly property var order: draft || sh.allTabIds
    readonly property var hidden: sh.hiddenTabIds()
    readonly property real gap: 6
    readonly property real cellW: (width - gap * 7) / 8

    function toggle(id) {
        var h = hidden.slice()
        var i = h.indexOf(id)
        if (i >= 0) h.splice(i, 1)
        else if (h.length < 7) h.push(id)      // en az bir sekme kalsın
        else return
        sh.saveTabOrder(order, h)
    }

    component Seg: Rectangle {
        id: seg
        property var options: []        // [{ k, l }]
        property string value
        signal picked(string k)
        width: segRow.implicitWidth + 6
        height: 28
        radius: 14
        color: Qt.rgba(1, 1, 1, 0.11)
        Row {
            id: segRow
            x: 3; y: 3
            Repeater {
                model: seg.options
                Rectangle {
                    required property var modelData
                    width: segText.implicitWidth + 22; height: 22; radius: 11
                    color: seg.value === modelData.k ? "#3a3a3c" : "transparent"
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Text {
                        id: segText
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        anchors.centerIn: parent
                        text: modelData.l
                        color: seg.value === modelData.k ? "white" : "#8e8e93"
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                    MouseArea { anchors.fill: parent; onClicked: seg.picked(modelData.k) }
                }
            }
        }
    }

    // Sekme kutucukları
    Item {
        id: strip
        width: parent.width
        height: 82

        Repeater {
            model: 8
            Rectangle {
                id: tile
                required property int index
                readonly property bool off: ed.hidden.indexOf(index) >= 0
                readonly property bool dragging: ed.dragId === index
                property real dragX: 0

                width: ed.cellW
                height: 76
                y: 3
                x: dragging ? dragX : ed.order.indexOf(index) * (ed.cellW + ed.gap)
                z: dragging ? 2 : 0
                scale: dragging ? 1.08 : 1
                radius: 16
                color: dragging ? "#3a3a3c" : tileMa.containsMouse ? Qt.rgba(1, 1, 1, 0.17) : Qt.rgba(1, 1, 1, 0.11)
                border.width: 1
                border.color: off ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.12)
                Behavior on x { enabled: !tile.dragging; NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 0.7 } }
                Behavior on scale { NumberAnimation { duration: 160 } }

                Column {
                    anchors.centerIn: parent
                    spacing: 7
                    opacity: tile.off ? 0.35 : 1
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    Ico {
                        anchors.horizontalCenter: parent.horizontalCenter
                        source: ed.icons[tile.index]
                        size: 20
                        tint: "white"
                    }
                    Text {
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: tile.width - 8
                        horizontalAlignment: Text.AlignHCenter
                        text: ed.labels[tile.index]
                        color: "white"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                }
                // Görünürlük rozeti
                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 6
                    width: 16; height: 16; radius: 8
                    color: tile.off ? "#3a3a3c" : "#30d158"
                    Behavior on color { ColorAnimation { duration: 180 } }
                    Ico {
                        anchors.centerIn: parent
                        source: tile.off ? sh.ic("isle-minus-symbolic") : sh.ic("isle-check-symbolic")
                        size: 9
                        tint: tile.off ? "#aeaeb2" : "black"
                    }
                }
                // Sıra numarası (görünenler arasında)
                Text {
                    visible: !tile.off
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: 7
                    text: sh.tabOrder.indexOf(tile.index) + 1
                    color: Qt.rgba(1, 1, 1, 0.35)
                    font.family: "Inter"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: tileMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: tile.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    property real grab: 0
                    property real startX: 0
                    property bool moved: false
                    onPressed: m => { grab = m.x; startX = mapToItem(strip, m.x, 0).x; moved = false }
                    onPositionChanged: m => {
                        if (!pressed) return
                        var px = mapToItem(strip, m.x, 0).x
                        if (!tile.dragging) {
                            if (Math.abs(px - startX) < 6) return
                            tile.dragX = tile.x
                            ed.draft = ed.order.slice()
                            ed.dragId = tile.index
                        }
                        moved = true
                        tile.dragX = Math.max(-6, Math.min(strip.width - tile.width + 6, px - grab))
                        var pos = Math.max(0, Math.min(7, Math.round(tile.dragX / (ed.cellW + ed.gap))))
                        var rest = ed.draft.filter(function (id) { return id !== tile.index })
                        var next = rest.slice(0, pos).concat([tile.index]).concat(rest.slice(pos))
                        if (next.join() !== ed.draft.join()) ed.draft = next
                    }
                    onReleased: {
                        if (tile.dragging) {
                            if (ed.draft.join() !== sh.allTabIds.join()) sh.saveTabOrder(ed.draft, ed.hidden)
                            ed.dragId = -1
                            ed.draft = null
                        } else if (!moved) {
                            ed.toggle(tile.index)
                        }
                    }
                    onCanceled: { ed.dragId = -1; ed.draft = null }
                }
            }
        }
    }

    RowLayout {
        id: optionsRow
        anchors.top: strip.bottom
        anchors.topMargin: 12
        width: parent.width
        spacing: 10

        Text {
            renderType: Text.CurveRendering
            font.family: "Inter"
            text: sh.t("Panel açılınca")
            color: "white"
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
        Seg {
            options: [{ k: "last", l: sh.t("Son sekme") }, { k: "first", l: sh.t("İlk sekme") }]
            value: sh.layout.open || "last"
            onPicked: k => sh.send("set_layout", { open: k })
        }
        Item { Layout.fillWidth: true }
        Rectangle {
            width: resetText.implicitWidth + 24; height: 26; radius: 13
            color: resetMa.pressed ? "#48484a" : resetMa.containsMouse ? "#3a3a3c" : Qt.rgba(1, 1, 1, 0.17)
            Text {
                id: resetText
                renderType: Text.CurveRendering
                font.family: "Inter"
                anchors.centerIn: parent
                text: sh.t("Varsayılan")
                color: "white"
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            MouseArea {
                id: resetMa
                anchors.fill: parent
                hoverEnabled: true
                onClicked: sh.saveTabOrder([0, 1, 2, 3, 4, 5, 6, 7], [])
            }
        }
    }

    Text {
        anchors.top: optionsRow.bottom
        anchors.topMargin: 16
        width: parent.width
        renderType: Text.CurveRendering
        font.family: "Inter"
        text: sh.t("Sürükleyerek sırala · dokunarak gizle ya da göster · üst çubukta da bir sekmeyi basılı tutup sürükleyebilirsin")
        color: Qt.rgba(1, 1, 1, 0.45)
        font.pixelSize: 11
        wrapMode: Text.WordWrap
    }
}
