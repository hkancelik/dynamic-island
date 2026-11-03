import QtQuick
import QtQuick.Layouts

// Hızlı Bakış: bir dosyanın önizlemesi (resim, PDF ilk sayfa, video karesi, metin, ses, klasör).
// Boşluk / Esc kapatır, Enter açar. Açıldığı yer: komut paleti (Ctrl+Y), dosya rafı (üstüne
// gelip Boşluk ya da göz düğmesi), `island quicklook DOSYA`.
Item {
    id: ql

    property var sh
    readonly property var d: sh.quickInfo
    readonly property string kind: d.kind || (d.error ? "other" : "loading")
    readonly property bool tall: kind === "image" || kind === "pdf" || kind === "video"
    readonly property int wantH: tall ? 338 : kind === "text" ? 296 : 196

    function kindLabel() {
        var k = ql.kind
        return k === "image" ? sh.t("Resim") : k === "pdf" ? "PDF" : k === "video" ? "Video" : k === "audio" ? sh.t("Ses")
             : k === "text" ? sh.t("Metin") : k === "folder" ? sh.t("Klasör") : (d.mime || sh.t("Dosya"))
    }
    function metaLine() {
        var parts = [kindLabel()]
        if (d.kind === "folder") parts.push(sh.t("%1 öğe").arg(d.count || 0))
        else if (d.sizeText) parts.push(d.sizeText)
        if (d.kind === "pdf" && d.pages) parts.push(sh.t("%1 sayfa").arg(d.pages))
        else if (d.meta) parts.push(d.meta)
        if (d.mtime) parts.push(sh.fmtDate(d.mtime))
        return parts.join(" · ")
    }

    function focusMe() { keys.forceActiveFocus() }

    // Klavye: Boşluk ve Esc kapatır, Enter açar
    Item {
        id: keys
        objectName: "qlKeys"
        focus: true
        Keys.onSpacePressed: sh.closeQuickLook()
        Keys.onEscapePressed: sh.closeQuickLook()
        Keys.onReturnPressed: ql.openFile()
        Keys.onEnterPressed: ql.openFile()
    }
    function openFile() { if (d.path) { sh.send("palette_run", { kind: "path", path: d.path }); sh.closeQuickLook() } }
    function openFolder() {
        if (!d.path) return
        var dir = d.path.substring(0, d.path.lastIndexOf("/")) || "/"
        sh.send("palette_run", { kind: "path", path: dir }); sh.closeQuickLook()
    }

    // ---- içerik
    Item {
        id: content
        x: 16; y: 14
        width: parent.width - 32
        height: parent.height - 14 - 66

        // yükleniyor
        ActRing {
            visible: ql.kind === "loading"
            anchors.centerIn: parent
            width: 28; height: 28
            thickness: 3
            frac: -1
            color: "white"
            live: ql.visible
        }
        Text {
            visible: !!ql.d.error
            anchors.centerIn: parent
            renderType: Text.CurveRendering
            text: sh.t("Dosya bulunamadı")
            color: Qt.rgba(1, 1, 1, 0.55)
            font.family: "Inter"
            font.pixelSize: 13
        }

        // resim / PDF / video karesi
        Rectangle {
            visible: ql.tall
            anchors.fill: parent
            radius: 14
            color: Qt.rgba(1, 1, 1, 0.06)
            clip: true
            Image {
                anchors.fill: parent
                anchors.margins: ql.kind === "pdf" ? 6 : 0
                source: !ql.visible ? "" : ql.kind === "image" ? (ql.d.url || "") : (ql.d.thumb || "")
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                sourceSize: Qt.size(1040, 560)
                smooth: true
            }
            Rectangle {   // video: oynat simgesi
                visible: ql.kind === "video" && !!ql.d.thumb
                anchors.centerIn: parent
                width: 46; height: 46; radius: 23
                color: Qt.rgba(0, 0, 0, 0.45)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.3)
                Ico { anchors.centerIn: parent; source: sh.ic("isle-play-symbolic"); size: 20; tint: "white" }
            }
        }

        // metin / kod
        Rectangle {
            visible: ql.kind === "text"
            anchors.fill: parent
            radius: 14
            color: Qt.rgba(1, 1, 1, 0.06)
            clip: true
            Text {
                anchors.fill: parent
                anchors.margins: 12
                text: ql.d.text || ""
                textFormat: Text.PlainText      // HTML gibi görünen dosyalar çizilmesin, satır sonları korunsun
                color: Qt.rgba(1, 1, 1, 0.88)
                font.family: "monospace"
                font.pixelSize: 11
                wrapMode: Text.WrapAnywhere
                elide: Text.ElideRight
                lineHeight: 1.15
                renderType: Text.NativeRendering
            }
            Rectangle {   // alttan solma
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: 34
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.7) }
                }
            }
        }

        // ses / klasör / diğer: büyük simge ya da kapak + metin
        RowLayout {
            visible: ql.kind === "audio" || ql.kind === "folder" || ql.kind === "other"
            anchors.fill: parent
            spacing: 18
            Rectangle {
                Layout.preferredWidth: 100; Layout.preferredHeight: 100
                Layout.alignment: Qt.AlignVCenter
                radius: 18
                color: Qt.rgba(1, 1, 1, 0.07)
                clip: true
                Image {
                    visible: ql.kind === "audio" && !!ql.d.thumb
                    anchors.fill: parent
                    source: ql.visible && ql.kind === "audio" ? (ql.d.thumb || "") : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize: Qt.size(240, 240)
                }
                AppIcon {
                    visible: !(ql.kind === "audio" && !!ql.d.thumb)
                    anchors.centerIn: parent
                    size: 56
                    source: ql.kind === "folder" ? "folder" : ql.kind === "audio" ? "audio-x-generic" : "text-x-generic"
                }
            }
            Column {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 3
                Text {
                    renderType: Text.CurveRendering
                    width: parent.width
                    text: ql.kind === "audio" && ql.d.title ? ql.d.title : (ql.d.name || "")
                    color: "white"
                    font.family: "Inter"
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    renderType: Text.CurveRendering
                    visible: text !== ""
                    width: parent.width
                    text: ql.kind === "audio" ? [ql.d.artist, ql.d.album].filter(function (x) { return !!x }).join(" · ") : ""
                    color: Qt.rgba(1, 1, 1, 0.55)
                    font.family: "Inter"
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }
                Text {
                    renderType: Text.CurveRendering
                    visible: ql.kind === "audio" && !!ql.d.meta
                    text: ql.d.meta || ""
                    color: Qt.rgba(1, 1, 1, 0.8)
                    font.family: "Inter"
                    font.pixelSize: 22
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }
            }
        }
    }

    // ---- alt çubuk: ad, bilgi, düğmeler
    Item {
        id: bar
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: 66
        Rectangle {
            x: 16; width: parent.width - 32; height: 1
            color: Qt.rgba(1, 1, 1, 0.08)
        }
        Column {
            anchors.left: parent.left
            anchors.leftMargin: 20
            anchors.right: btns.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 1
            spacing: 2
            Text {
                renderType: Text.CurveRendering
                width: parent.width
                text: ql.d.name || ""
                color: "white"
                font.family: "Inter"
                font.pixelSize: 14
                font.weight: Font.DemiBold
                elide: Text.ElideMiddle
            }
            Text {
                renderType: Text.CurveRendering
                width: parent.width
                text: ql.d.error ? "" : ql.metaLine()
                color: Qt.rgba(1, 1, 1, 0.5)
                font.family: "Inter"
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }
        Row {
            id: btns
            anchors.right: parent.right
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 1
            spacing: 8
            Repeater {
                model: [{ k: "open", l: sh.t("Aç") }, { k: "folder", l: sh.t("Klasör") }]
                Rectangle {
                    required property var modelData
                    readonly property bool primary: modelData.k === "open"
                    width: qlBtnText.implicitWidth + 26; height: 28; radius: 14
                    color: primary ? (qlBtnMa.pressed ? "#d1d1d6" : "white")
                                   : (qlBtnMa.pressed ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(1, 1, 1, qlBtnMa.containsMouse ? 0.22 : 0.15))
                    Text {
                        id: qlBtnText
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        anchors.centerIn: parent
                        text: modelData.l
                        color: parent.primary ? "black" : "white"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: qlBtnMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: modelData.k === "open" ? ql.openFile() : ql.openFolder()
                    }
                }
            }
        }
    }
}
