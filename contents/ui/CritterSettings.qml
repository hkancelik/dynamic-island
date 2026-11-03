import QtQuick
import QtQuick.Layouts

// Ayarlar → Karakter: adanın küçük sakinini büyük görüp tüm tepkilerini dene.
Item {
    id: page

    property var sh
    property string demo: ""              // boş: gerçek duruma göre; yoksa denenen ruh hâli

    // 128 bpm'lik sahte vuruş: dans önizlemesi için
    property real beat: 0
    SequentialAnimation on beat {
        running: page.demo === "music" && page.visible
        loops: Animation.Infinite
        NumberAnimation { to: 0.95; duration: 70; easing.type: Easing.OutQuad }
        NumberAnimation { to: 0.05; duration: 400; easing.type: Easing.OutCubic }
    }

    readonly property var moods: [
        { key: "music", label: sh.t("Dans") },
        { key: "focus", label: sh.t("Çalış") },
        { key: "sleep", label: sh.t("Uyu") },
        { key: "cheer", label: sh.t("Sevin") },
        { key: "love", label: sh.t("Sev") },
        { key: "surprise", label: sh.t("Şaşır") }
    ]

    RowLayout {
        anchors.fill: parent
        spacing: 18

        // sahne
        Rectangle {
            Layout.preferredWidth: 220
            Layout.fillHeight: true
            radius: 18
            color: Qt.rgba(1, 1, 1, 0.045)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.07)
            clip: true

            Rectangle {   // zemin ışığı
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -40
                width: parent.width * 1.1; height: 120; radius: 60
                color: Qt.rgba(page.sh.accent.r, page.sh.accent.g, page.sh.accent.b, 0.16)
            }

            Critter {
                id: big
                anchors.centerIn: parent
                size: Math.max(32, Math.floor(Math.min(parent.width - 20, parent.height - 10) / 32) * 32)
                mood: page.demo === "cheer" || page.demo === "love" || page.demo === "surprise" ? page.sh.critterMood
                      : page.demo !== "" ? page.demo : page.sh.critterMood
                bass: page.demo === "music" ? page.beat : 0
                pointerOn: hover.hovered
                pointerX: hover.hovered ? mapFromItem(hover.parent, hover.point.position.x, hover.point.position.y).x : 0
                pointerY: hover.hovered ? mapFromItem(hover.parent, hover.point.position.x, hover.point.position.y).y : 0
                HoverHandler { id: hover; parent: big.parent }
                TapHandler { parent: big; onTapped: big.love() }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            Text {
                renderType: Text.CurveRendering
                font.family: "Inter"
                Layout.fillWidth: true
                text: page.sh.t("Adanın sakini")
                color: "white"
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }
            Text {
                renderType: Text.CurveRendering
                font.family: "Inter"
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: page.sh.t("Müzikte dans eder, odakta çalışır, geceleri uyur, iş bitince sevinir. Fareni izler; ona dokun.")
                color: Qt.rgba(1, 1, 1, 0.62)
                font.pixelSize: 11
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: page.moods
                    Rectangle {
                        required property var modelData
                        readonly property bool sel: page.demo === modelData.key
                        width: lbl.implicitWidth + 24; height: 28; radius: 14
                        color: sel ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.07)
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Text {
                            id: lbl
                            renderType: Text.CurveRendering
                            font.family: "Inter"
                            anchors.centerIn: parent
                            text: parent.modelData.label
                            color: "white"
                            font.pixelSize: 12
                            font.weight: Font.Medium
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                var k = parent.modelData.key
                                if (k === "cheer") big.cheer()
                                else if (k === "love") big.love()
                                else if (k === "surprise") big.startle()
                                else page.demo = page.demo === k ? "" : k
                            }
                        }
                    }
                }
            }
            Item { Layout.fillHeight: true }
        }
    }
}
