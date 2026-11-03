import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Notlar: solda not listesi, sağda yazma alanı. Yazdıkların kendiliğinden kaydedilir.
// Başlık ilk satırdan gelir; çift tık ya da sağ tık → Yeniden adlandır ile elle verilir.
Item {
    id: page

    property var sh

    property int selId: 0           // açık not (0: yok)
    property bool dirty: false      // editördeki metin henüz kaydedilmedi
    property int seenSeq: -1
    property int renameId: 0        // başlığı düzenlenen not (0: yok)
    // Sağ tık menüsü: kind "doc" (not satırı) ya da "editor" (yazma alanı)
    property string menuKind: ""
    property int menuDoc: 0
    property real menuX: 0
    property real menuY: 0

    readonly property var docs: sh.docs

    function docOf(id) {
        for (var i = 0; i < docs.length; i++) if (docs[i].id === id) return docs[i]
        return null
    }
    function lines(text) {
        return String(text).split("\n").map(function (l) { return l.trim() }).filter(function (l) { return l.length > 0 })
    }
    function titleOf(d) {
        if (d.title) return d.title
        var l = lines(d.text)
        return l.length > 0 ? l[0] : sh.t("Yeni not")
    }
    function previewOf(d) {
        var l = lines(d.text)
        var i = d.title ? 0 : 1      // elle başlık verildiyse ilk satır da önizlemede
        return (l.length > i ? l[i] : sh.t("Ek metin yok"))
    }
    function openMenu(kind, item, mx, my, docId) {
        var p = item.mapToItem(page, mx, my)
        menuKind = kind
        menuDoc = docId || 0
        menuX = Math.min(p.x, page.width - 150)
        menuY = Math.min(p.y, page.height - (kind === "doc" ? 64 : 120))
    }
    function runMenu(act) {
        var id = menuDoc
        menuKind = ""
        if (act === "rename") renameId = id
        else if (act === "delete") {
            if (id === selId) { dirty = false; saveTimer.stop() }
            sh.send("doc_del", id)
        }
        else if (act === "cut") { editor.forceActiveFocus(); editor.cut() }
        else if (act === "copy") editor.copy()
        else if (act === "paste") { editor.forceActiveFocus(); editor.paste() }
        else if (act === "all") { editor.forceActiveFocus(); editor.selectAll() }
    }
    function ago(ts) {
        var m = Math.floor((Date.now() - ts) / 60000)
        if (m < 1) return sh.t("şimdi")
        if (m < 60) return sh.t("%1 dk.short").arg(m)
        var h = Math.floor(m / 60)
        return h < 24 ? sh.t("%1 sa.short").arg(h) : sh.t("%1 gün.short").arg(Math.floor(h / 24))
    }

    // Bekleyen yazıyı kaydet
    function flush() {
        saveTimer.stop()
        if (dirty && selId > 0 && docOf(selId) !== null) sh.send("doc_set", { id: selId, text: editor.text })
        dirty = false
    }

    function select(id) {
        if (id === selId) return
        flush()
        // Açık kalmış boş notu temizle
        var prev = docOf(selId)
        if (prev !== null && prev.text.trim() === "" && editor.text.trim() === "") sh.send("doc_del", selId)
        selId = id
        var d = docOf(id)
        editor.text = d ? d.text : ""
        dirty = false
    }

    // Liste değişince: açık not silindiyse ya da hiçbiri seçili değilse ilkini aç
    onDocsChanged: {
        if (selId === 0 || docOf(selId) === null) {
            selId = 0
            if (docs.length > 0 && !dirty) select(docs[0].id)
        }
    }
    Component.onCompleted: {
        seenSeq = sh.docNew.seq
        if (docs.length > 0) select(docs[0].id)
    }
    // "Yeni not" sonucu: yeni notu aç ve yazmaya hazır ol
    readonly property int newSeq: sh.docNew.seq
    onNewSeqChanged: {
        if (newSeq === seenSeq) return
        var fresh = seenSeq >= 0 && sh.loaded
        seenSeq = newSeq
        if (!fresh) return
        selId = 0
        select(sh.docNew.id)
        editor.forceActiveFocus()
    }
    onVisibleChanged: if (!visible) flush()
    Connections {
        target: sh
        function onPanelOpenChanged() { if (!sh.panelOpen) page.flush() }
    }

    Timer { id: saveTimer; interval: 500; onTriggered: page.flush() }

    RowLayout {
        anchors.fill: parent
        spacing: 12

        // ------------------------------------------------------------ Liste
        ColumnLayout {
            Layout.preferredWidth: 170
            Layout.maximumWidth: 170
            Layout.fillHeight: true
            spacing: 6

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 28
                radius: 14
                color: newMa.pressed ? "#48484a" : newMa.containsMouse ? "#3a3a3c" : Qt.rgba(1, 1, 1, 0.17)
                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Ico {
                        anchors.verticalCenter: parent.verticalCenter
                        source: sh.ic("isle-plus-symbolic")
                        size: 12
                        tint: "white"
                    }
                    Text {
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        anchors.verticalCenter: parent.verticalCenter
                        text: sh.t("Yeni not")
                        color: "white"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                }
                MouseArea {
                    id: newMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: { page.flush(); sh.send("doc_new") }
                }
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: page.docs
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool current: modelData.id === page.selId
                    width: list.width
                    height: 40
                    radius: 10
                    color: current ? Qt.rgba(1, 1, 1, 0.12) : (hov.hovered ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
                    HoverHandler { id: hov }

                    Column {
                        anchors.left: parent.left; anchors.leftMargin: 10
                        anchors.right: parent.right; anchors.rightMargin: hov.hovered ? 28 : 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text {
                            visible: page.renameId !== row.modelData.id
                            renderType: Text.CurveRendering
                            font.family: "Inter"
                            width: parent.width
                            text: row.current && page.dirty
                                  ? page.titleOf({ title: row.modelData.title, text: editor.text })
                                  : page.titleOf(row.modelData)
                            color: "white"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        TextField {
                            id: renameField
                            visible: page.renameId === row.modelData.id
                            width: parent.width
                            height: 20
                            padding: 0
                            topPadding: 0; bottomPadding: 0
                            font.family: "Inter"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: "white"
                            selectionColor: sh.accent
                            selectedTextColor: "black"
                            selectByMouse: true
                            maximumLength: 60
                            placeholderText: sh.t("Başlık")
                            placeholderTextColor: Qt.rgba(1, 1, 1, 0.4)
                            background: Rectangle { color: "transparent"; border.width: 0
                                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: sh.accent } }
                            onVisibleChanged: if (visible) {
                                text = row.modelData.title || page.titleOf(row.modelData)
                                forceActiveFocus()
                                selectAll()
                            }
                            // Enter: kaydet (boş bırakılırsa başlık yine ilk satırdan gelir); Esc: vazgeç
                            onAccepted: { sh.send("doc_title", { id: row.modelData.id, title: text }); page.renameId = 0 }
                            Keys.onEscapePressed: page.renameId = 0
                            onActiveFocusChanged: if (!activeFocus && page.renameId === row.modelData.id) {
                                sh.send("doc_title", { id: row.modelData.id, title: text })
                                page.renameId = 0
                            }
                        }
                        Text {
                            renderType: Text.CurveRendering
                            font.family: "Inter"
                            width: parent.width
                            text: page.ago(row.modelData.ts) + " · " + page.previewOf(row.modelData)
                            color: Qt.rgba(1, 1, 1, 0.5)
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: page.renameId !== row.modelData.id
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: m => {
                            if (m.button === Qt.RightButton) page.openMenu("doc", row, m.x, m.y, row.modelData.id)
                            else page.select(row.modelData.id)
                        }
                        onDoubleClicked: m => { if (m.button === Qt.LeftButton) page.renameId = row.modelData.id }
                    }
                    CtlButton {
                        visible: hov.hovered
                        anchors.right: parent.right; anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22; height: 22; iconSize: 10
                        icon: sh.ic("isle-close-symbolic")
                        tint: Qt.rgba(1, 1, 1, 0.7)
                        onClicked: {
                            if (row.modelData.id === page.selId) { page.dirty = false; saveTimer.stop() }
                            sh.send("doc_del", row.modelData.id)
                        }
                    }
                }
            }
        }

        // ------------------------------------------------------------ Yazma alanı
        Rectangle {
            id: editBox
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 14
            color: Qt.rgba(1, 1, 1, 0.11)

            ScrollView {
                anchors.fill: parent
                anchors.margins: 4
                visible: page.selId > 0
                clip: true
                ScrollBar.vertical.policy: ScrollBar.AsNeeded

                TextArea {
                    id: editor
                    font.family: "Inter"
                    font.pixelSize: 13
                    color: "white"
                    selectionColor: sh.accent
                    selectedTextColor: "black"
                    placeholderText: sh.t("Notunu yaz…")
                    placeholderTextColor: Qt.rgba(1, 1, 1, 0.4)
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    leftPadding: 8; rightPadding: 8; topPadding: 6; bottomPadding: 6
                    background: null
                    Keys.onEscapePressed: { page.flush(); sh.panelOpen = false }
                    onTextChanged: {
                        if (!activeFocus) return
                        page.dirty = true
                        saveTimer.restart()
                    }
                }
            }

            // Sağ tık: kes / kopyala / yapıştır (yalnızca sağ tuşu yakalar, sol tık editöre gider)
            MouseArea {
                anchors.fill: parent
                visible: page.selId > 0
                acceptedButtons: Qt.RightButton
                onClicked: m => page.openMenu("editor", editBox, m.x, m.y, 0)
            }

            // Not yokken ipucu
            Column {
                visible: page.selId === 0
                anchors.centerIn: parent
                spacing: 6
                Text {
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: sh.t("Not yok")
                    color: Qt.rgba(1, 1, 1, 0.6)
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Text {
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: sh.t("Yeni not ile başla")
                    color: Qt.rgba(1, 1, 1, 0.4)
                    font.pixelSize: 11
                }
            }
        }
    }

    // Sağ tık menüsü: dışına tıklayınca kapanır
    MouseArea {
        anchors.fill: parent
        z: 50
        visible: page.menuKind !== ""
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: page.menuKind = ""
    }
    Rectangle {
        id: ctxMenu
        z: 51
        visible: page.menuKind !== ""
        x: page.menuX; y: page.menuY
        width: 150
        height: menuCol.implicitHeight + 8
        radius: 12
        color: Qt.rgba(1, 1, 1, 0.17)
        border.width: 1
        border.color: "#3a3a3c"
        Column {
            id: menuCol
            x: 4; y: 4
            width: parent.width - 8
            Repeater {
                model: page.menuKind === "doc"
                       ? [{ t: sh.t("Yeniden adlandır"), a: "rename" }, { t: sh.t("Sil"), a: "delete", red: true }]
                       : [{ t: sh.t("Kes"), a: "cut" }, { t: sh.t("Kopyala"), a: "copy" }, { t: sh.t("Yapıştır"), a: "paste" },
                          { t: sh.t("Tümünü seç"), a: "all" }]
                Rectangle {
                    required property var modelData
                    width: menuCol.width
                    height: 28
                    radius: 8
                    color: itemMa.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                    Text {
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.t
                        color: modelData.red ? "#ff453a" : "white"
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                    MouseArea {
                        id: itemMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: page.runMenu(modelData.a)
                    }
                }
            }
        }
    }
}
