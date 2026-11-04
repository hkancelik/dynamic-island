import QtQuick
import QtQuick.Layouts

// Ayarlar → Maç: takip edilen takımı ara ve seç.
Item {
    id: page

    property var sh
    readonly property var f: sh.football
    readonly property var team: f && f.team ? f.team : ({})

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // seçili takım
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Rectangle {
                Layout.preferredWidth: 44; Layout.preferredHeight: 44
                radius: 12
                color: Qt.rgba(1, 1, 1, 0.08)
                Image {
                    anchors.centerIn: parent
                    width: 32; height: 32
                    source: page.team.logo || ""
                    sourceSize: Qt.size(64, 64)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
            }
            Column {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    text: sh.t("Favori takım")
                    color: Qt.rgba(1, 1, 1, 0.55)
                    font.pixelSize: 11
                }
                Text {
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    text: page.team.name || "…"
                    color: "white"
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }
            }
        }

        // arama
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            radius: 16
            color: Qt.rgba(1, 1, 1, 0.11)
            TextInput {
                id: search
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                verticalAlignment: TextInput.AlignVCenter
                color: "white"
                font.family: "Inter"
                font.pixelSize: 13
                selectByMouse: true
                clip: true
                onTextChanged: searchTimer.restart()
                Text {
                    visible: search.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    text: sh.t("Takım ara (ör. Galatasaray, Barcelona)")
                    color: Qt.rgba(1, 1, 1, 0.4)
                    font.pixelSize: 13
                }
            }
            Timer { id: searchTimer; interval: 350; onTriggered: page.sh.send("football_search", search.text) }
        }

        // sonuçlar
        Flow {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8
            clip: true
            Repeater {
                model: page.sh.footballSearch.items || []
                Rectangle {
                    required property var modelData
                    readonly property bool current: modelData.id === page.team.id
                    width: label.implicitWidth + 28
                    height: 30
                    radius: 15
                    color: current ? Qt.rgba(1, 1, 1, 0.22) : hov.hovered ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.1)
                    Text {
                        id: label
                        anchors.centerIn: parent
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        text: modelData.name + "  ·  " + modelData.leagueName
                        color: "white"
                        font.pixelSize: 12
                    }
                    HoverHandler { id: hov }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: page.sh.send("football_team", { id: modelData.id, name: modelData.name, league: modelData.league })
                    }
                }
            }
        }
        Text {
            visible: (page.sh.footballSearch.items || []).length === 0
            Layout.fillWidth: true
            renderType: Text.CurveRendering
            font.family: "Inter"
            wrapMode: Text.WordWrap
            text: sh.t("Seçtiğin takımın maçları, kadrosu ve puan durumu Maç sekmesinde görünür; Avrupa kupaları da dahil.")
            color: Qt.rgba(1, 1, 1, 0.4)
            font.pixelSize: 11
        }
    }
}
