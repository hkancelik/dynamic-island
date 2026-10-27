import QtQuick
import QtQuick.Layouts

// Dosya rafı: dosyaları sürükleyip bırak, başka bir uygulamaya sürükleyerek çıkar.
// Raf yalnızca dosya yollarını tutar (kopyalamaz); dosya silinirse soluk görünür.
Item {
    id: page

    property var sh

    function urlsOf(drop) {
        var out = []
        for (var i = 0; i < drop.urls.length; i++) out.push(drop.urls[i].toString())
        return out
    }

    DropArea {
        id: drop
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: d => {
            sh.send("shelf_add", page.urlsOf(d))
            sh.toast("Rafa eklendi", "folder-download")
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 20
            Text {
                renderType: Text.CurveRendering
                font.family: "Inter"
                text: sh.shelf.length > 0 ? sh.shelf.length + " dosya" : "Dosya rafı"
                color: "#8e8e93"
                font.pixelSize: 11
                font.weight: Font.Medium
            }
            Item { Layout.fillWidth: true }
            Text {
                renderType: Text.CurveRendering
                font.family: "Inter"
                visible: sh.shelf.length > 0
                text: "Rafı boşalt"
                color: clrMa.containsMouse ? "white" : sh.accent
                font.pixelSize: 11
                font.weight: Font.Medium
                MouseArea {
                    id: clrMa
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    onClicked: sh.send("shelf_clear")
                }
            }
        }

        GridView {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            cellWidth: Math.floor(width / 4)
            cellHeight: 96
            model: sh.shelf
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
                id: chip
                required property var modelData
                width: grid.cellWidth
                height: grid.cellHeight
                opacity: modelData.exists ? 1 : 0.4

                // Başka uygulamaya sürükleyerek bırakma
                Drag.active: dragMa.drag.active
                Drag.dragType: Drag.Automatic
                Drag.supportedActions: Qt.CopyAction
                Drag.mimeData: ({ "text/uri-list": modelData.url + "\r\n" })
                Drag.onActiveChanged: sh.draggingOut = Drag.active

                Item { id: dragProxy; width: 1; height: 1 }

                Rectangle {
                    id: tile
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 4
                    width: 58; height: 58; radius: 16
                    color: dragMa.containsMouse ? "#2c2c2e" : "#1c1c1e"
                    scale: dragMa.pressed ? 0.94 : 1
                    Behavior on scale { NumberAnimation { duration: 100 } }

                    Image {
                        visible: modelData.image
                        anchors.fill: parent
                        anchors.margins: 4
                        source: modelData.image ? modelData.url : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 128
                        sourceSize.height: 128
                    }
                    AppIcon {
                        visible: !modelData.image
                        anchors.centerIn: parent
                        size: 34
                        source: modelData.icon
                    }
                }
                Text {
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    anchors.top: tile.bottom
                    anchors.topMargin: 5
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - 8
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData.name
                    color: "#aeaeb2"
                    font.pixelSize: 10
                    elide: Text.ElideMiddle
                }

                MouseArea {
                    id: dragMa
                    anchors.fill: parent
                    hoverEnabled: true
                    drag.target: dragProxy
                    onClicked: sh.send("shelf_open", modelData.id)
                }

                // Raftan kaldır (dosyaya dokunmaz)
                Rectangle {
                    visible: dragMa.containsMouse
                    anchors.right: tile.right
                    anchors.top: tile.top
                    anchors.margins: -4
                    width: 20; height: 20; radius: 10
                    color: "#3a3a3c"
                    Ico { anchors.centerIn: parent; source: "window-close"; size: 10; tint: "white" }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: sh.send("shelf_del", modelData.id)
                    }
                }
            }
        }
    }

    // Boş durum + bırakma ipucu
    Rectangle {
        visible: sh.shelf.length === 0 || drop.containsDrag
        anchors.fill: parent
        anchors.topMargin: 28
        radius: 20
        color: drop.containsDrag ? Qt.rgba(sh.accent.r, sh.accent.g, sh.accent.b, 0.16) : "transparent"
        border.width: 1.5
        border.color: drop.containsDrag ? sh.accent : "#3a3a3c"
        Behavior on color { ColorAnimation { duration: 140 } }

        Column {
            anchors.centerIn: parent
            spacing: 10
            Ico {
                anchors.horizontalCenter: parent.horizontalCenter
                source: "folder-download"
                size: 34
                tint: drop.containsDrag ? sh.accent : "#6c6c70"
            }
            Text {
                renderType: Text.CurveRendering
                font.family: "Inter"
                anchors.horizontalCenter: parent.horizontalCenter
                text: drop.containsDrag ? "Bırak" : "Dosyaları buraya sürükle"
                color: drop.containsDrag ? "white" : "#8e8e93"
                font.pixelSize: 13
                font.weight: Font.Medium
            }
            Text {
                renderType: Text.CurveRendering
                font.family: "Inter"
                visible: !drop.containsDrag
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Sonra başka bir uygulamaya sürükleyip bırakabilirsin"
                color: "#8e8e93"
                font.pixelSize: 10
            }
        }
    }
}
