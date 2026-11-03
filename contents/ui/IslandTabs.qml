import QtQuick
import QtQuick.Layouts

// Panel başlığındaki sekme çubuğu: seçili sekme etiketiyle birlikte hap, diğerleri yalnızca ikon.
Item {
    id: tabBar

    property var sh
    Layout.fillHeight: true
    Layout.preferredWidth: selW + (tabs.length - 1) * otherW

    readonly property var tabs: [
        { icon: sh.ic("isle-music"), label: "Müzik" },
        { icon: sh.ic("isle-bell"), label: "Bildirim" },
        { icon: sh.ic("isle-timer"), label: "Odak" },
        { icon: sh.ic("isle-calendar"), label: "Takvim" },
        { icon: sh.ic("isle-sun-symbolic"), label: "Kontrol" },
        { icon: "view-app-grid-symbolic", label: "Uygulama" },
        { icon: sh.ic("isle-gauge"), label: "Sistem" },
        { icon: sh.ic("isle-shelf"), label: "Araçlar" }
    ]
    // Seçili sekme etiketiyle birlikte hap; diğerleri yalnızca ikon
    // Seçili sekmenin genişliği etiketine göre (10 px iç boşluk, 6 px ikon arası)
    readonly property var labelW: [42, 52, 34, 46, 50, 62, 44, 50]
    // Ayarlar (8) bir sekme değil: o açıkken hiçbir sekme seçili görünmez
    readonly property real selW: sh.tab < 8 ? 20 + 16 + 6 + labelW[sh.tab] : otherW
    readonly property real otherW: 32

    Rectangle {
        width: tabBar.selW
        height: 28
        y: 4
        x: sh.tab * tabBar.otherW
        visible: sh.tab < 8
        radius: 14
        color: Qt.rgba(1, 1, 1, 0.09)
        Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 0.7 } }
    }

    Row {
        anchors.fill: parent
        Repeater {
            model: tabBar.tabs
            Item {
                required property var modelData
                required property int index
                width: sh.tab === index ? tabBar.selW : tabBar.otherW
                Rectangle {
                    visible: tabMa.containsMouse && sh.tab !== index
                    anchors.centerIn: parent
                    width: parent.width; height: 28; radius: 14
                    color: Qt.rgba(1, 1, 1, 0.05)
                }
                height: 36
                Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Ico {
                        anchors.verticalCenter: parent.verticalCenter
                        source: modelData.icon
                        size: 16
                        tint: "white"
                        opacity: sh.tab === index ? 1 : (tabMa.containsMouse ? 0.9 : 0.55)
                    }
                    Text {
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        opacity: sh.tab === index ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label
                        color: "white"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                }
                // rozetler: okunmamış bildirim, kayıt sürüyor
                Rectangle {
                    visible: (index === 1 && sh.unread > 0) || (index === 5 && sh.rec.state !== "idle")
                    x: parent.width / 2 + 3; y: 7
                    width: 6; height: 6; radius: 3
                    color: "#ff453a"
                }
                MouseArea {
                    id: tabMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: sh.tab = index
                }
            }
        }
    }
}
