import QtQuick
import QtQuick.Layouts

// Panel başlığındaki sekme çubuğu: seçili sekme etiketiyle birlikte hap, diğerleri yalnızca ikon.
// Sıra ve gizli sekmeler ayardan (sh.tabOrder). Bir sekmeyi basılı tutup sürükleyerek yerini
// değiştirebilirsin: diğerleri kayarak yer açar, bırakınca yeni sıra kaydedilir.
Item {
    id: tabBar

    property var sh
    Layout.fillHeight: true
    Layout.preferredWidth: width
    width: (order.length - 1) * otherW + (order.indexOf(sh.tab) >= 0 ? selW : otherW)
    Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

    // Sayfa numarasına göre (sh.tabKeys ile aynı sıra)
    readonly property var tabs: [
        { icon: sh.ic("isle-music"), label: sh.t("Müzik") },
        { icon: sh.ic("isle-bell"), label: sh.t("Bildirim") },
        { icon: sh.ic("isle-timer"), label: sh.t("Odak") },
        { icon: sh.ic("isle-calendar"), label: sh.t("Takvim") },
        { icon: sh.ic("isle-sun-symbolic"), label: sh.t("Kontrol") },
        { icon: "view-app-grid-symbolic", label: sh.t("Uygulama") },
        { icon: sh.ic("isle-gauge"), label: sh.t("Sistem") },
        { icon: sh.ic("isle-shelf"), label: sh.t("Araçlar") },
        { icon: sh.ic("isle-weather"), label: sh.t("Hava") }
    ]

    // Sürüklerken geçici sıra; yoksa ayardaki sıra
    property var draft: null
    property int dragId: -1
    readonly property var order: draft || sh.tabOrder
    readonly property real otherW: 32
    // Seçili sekmenin genişliği etiketine göre (10 px iç boşluk + 16 ikon + 6 ara)
    readonly property real selW: 20 + 16 + 6 + selMeasure.implicitWidth
    Text {
        id: selMeasure
        visible: false
        text: sh.tab >= 0 && sh.tab < tabBar.tabs.length ? tabBar.tabs[sh.tab].label : ""
        font.family: "Inter"
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }

    function widthOf(id) { return id === sh.tab ? selW : otherW }
    function xOf(id) {
        var x = 0
        for (var i = 0; i < order.length && order[i] !== id; i++) x += widthOf(order[i])
        return x
    }

    // Seçili sekmenin sıvı cam hapı (sürüklenirken sekmeyi doğrudan izler)
    LiquidPill {
        readonly property Item target: tabRep.count > sh.tab && sh.tab >= 0 && sh.tab < tabBar.tabs.length ? tabRep.itemAt(sh.tab) : null
        visible: target !== null && target.visible
        width: tabBar.width
        height: 36
        goalX: target ? tabBar.xOf(sh.tab) : 0
        goalW: tabBar.selW
        follow: target !== null && target.dragging
        glassLayer: sh.glassLayer
        glassFrost: sh.glassFrost || 0.3
        x: follow ? target.x - goalX : 0
    }

    Repeater {
        id: tabRep
        model: tabBar.tabs
        Item {
            id: cell
            required property var modelData
            required property int index
            readonly property bool selected: sh.tab === index
            readonly property bool dragging: tabBar.dragId === index
            property real dragX: 0

            visible: tabBar.order.indexOf(index) >= 0
            width: tabBar.widthOf(index)
            height: 36
            x: dragging ? dragX : tabBar.xOf(index)
            z: dragging ? 2 : 0
            scale: dragging ? 1.12 : 1
            Behavior on x { enabled: !cell.dragging; NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 0.6 } }
            Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            Rectangle {
                visible: tabMa.containsMouse && !cell.selected && !cell.dragging
                anchors.centerIn: parent
                width: parent.width; height: 28; radius: 14
                color: Qt.rgba(1, 1, 1, 0.05)
            }
            // Sürüklenen sekme: hafif parlak halka
            Rectangle {
                visible: cell.dragging && !cell.selected
                anchors.centerIn: parent
                width: parent.width; height: 28; radius: 14
                color: Qt.rgba(1, 1, 1, 0.14)
            }

            Row {
                anchors.centerIn: parent
                spacing: 6
                Ico {
                    anchors.verticalCenter: parent.verticalCenter
                    source: cell.modelData.icon
                    size: 16
                    tint: "white"
                    opacity: cell.selected || cell.dragging ? 1 : (tabMa.containsMouse ? 0.9 : 0.55)
                }
                Text {
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    opacity: cell.selected ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    anchors.verticalCenter: parent.verticalCenter
                    text: cell.modelData.label
                    color: "white"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
            }
            // rozetler: okunmamış bildirim, kayıt sürüyor
            Rectangle {
                visible: (cell.index === 1 && sh.unread > 0) || (cell.index === 5 && sh.rec.state !== "idle")
                x: parent.width / 2 + 3; y: 7
                width: 6; height: 6; radius: 3
                color: "#ff453a"
            }

            MouseArea {
                id: tabMa
                anchors.fill: parent
                hoverEnabled: true
                pressAndHoldInterval: 220
                property real grab: 0
                onClicked: if (!cell.dragging) sh.tab = cell.index
                onPressAndHold: m => {
                    grab = m.x
                    cell.dragX = cell.x
                    tabBar.draft = sh.tabOrder.slice()
                    tabBar.dragId = cell.index
                }
                onPositionChanged: m => {
                    if (!cell.dragging) return
                    var p = mapToItem(tabBar, m.x, 0)
                    cell.dragX = Math.max(-8, Math.min(tabBar.width - cell.width + 8, p.x - grab))
                    // Sürüklenen sekmenin ortası hangi sekmelerin ortasını geçtiyse onların arkasına
                    var center = cell.dragX + cell.width / 2
                    var rest = tabBar.draft.filter(function (id) { return id !== cell.index })
                    var pos = 0, acc = 0
                    for (var i = 0; i < rest.length; i++) {
                        var w = tabBar.widthOf(rest[i])
                        if (center > acc + w / 2) pos = i + 1
                        acc += w
                    }
                    var next = rest.slice(0, pos).concat([cell.index]).concat(rest.slice(pos))
                    if (next.join() !== tabBar.draft.join()) tabBar.draft = next
                }
                onReleased: finish()
                onCanceled: finish()
                function finish() {
                    if (!cell.dragging) return
                    var changed = tabBar.draft.join() !== sh.tabOrder.join()
                    if (changed) sh.saveTabs(tabBar.draft, sh.hiddenTabIds())
                    tabBar.dragId = -1
                    tabBar.draft = null
                }
            }
        }
    }
}
