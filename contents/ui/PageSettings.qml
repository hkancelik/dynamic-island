import QtQuick
import QtQuick.Layouts

// Ayarlar: açık/kapalı ayarlar (config.json'a yazılır, hemen geçerli olur),
// Claude Code onaylarının kurulumu, takvim hesapları.
Item {
    id: page

    property var sh
    readonly property var st: sh.settings

    component Switch: Rectangle {
        id: sw
        property bool on
        signal toggled
        width: 36; height: 22; radius: 11
        color: on ? "#30d158" : "#3a3a3c"
        Behavior on color { ColorAnimation { duration: 150 } }
        Rectangle {
            width: 18; height: 18; radius: 9
            y: 2
            x: sw.on ? sw.width - width - 2 : 2
            color: "white"
            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }
        MouseArea { anchors.fill: parent; onClicked: sw.toggled() }
    }

    component Row2: Item {
        id: r
        property string title
        property string hint
        property bool on
        signal toggled
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        Column {
            anchors.left: parent.left
            anchors.right: s2.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            Text {
                renderType: Text.CurveRendering
                font.family: "Inter"
                width: parent.width
                text: r.title
                color: "white"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                renderType: Text.CurveRendering
                font.family: "Inter"
                width: parent.width
                text: r.hint
                color: Qt.rgba(1, 1, 1, 0.45)
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }
        Switch {
            id: s2
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            on: r.on
            onToggled: r.toggled()
        }
    }

    function set(key, value) { sh.send("setting", { key: key, value: value }) }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 28
            rowSpacing: 0

            Row2 {
                title: "Plasma bildirim pencereleri"
                hint: "Kapalıyken bildirimler yalnızca adada"
                on: !page.st.suppress_plasma_popups
                onToggled: page.set("suppress_plasma_popups", on)
            }
            Row2 {
                title: "Tam ekranda gizle"
                hint: "Oyun ve videoda ada çekilir"
                on: page.st.hide_in_fullscreen
                onToggled: page.set("hide_in_fullscreen", !on)
            }
            Row2 {
                title: "Pano geçmişi"
                hint: "Yalnızca bellekte tutulur"
                on: page.st.clipboard_history
                onToggled: page.set("clipboard_history", !on)
            }
            Row2 {
                title: "Şarkı sözleri"
                hint: "LRCLIB'den, söz görünümü açıkken"
                on: page.st.lyrics
                onToggled: page.set("lyrics", !on)
            }
            Row2 {
                title: "Toplantı uyarısı"
                hint: "Etkinlikten 5 dk önce, Katıl ile"
                on: page.st.meeting_alerts
                onToggled: page.set("meeting_alerts", !on)
            }
            Row2 {
                title: "Gizlilik noktaları"
                hint: "Kamera, mikrofon, ekran paylaşımı"
                on: page.st.privacy_dots
                onToggled: page.set("privacy_dots", !on)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Qt.rgba(1, 1, 1, 0.08)
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 28
            Row2 {
                title: "Claude Code onayları"
                hint: page.st.claudeHooks ? "Kurulu · izinler adada sorulur" : "~/.claude/settings.json'a hook ekler"
                on: page.st.claudeHooks
                onToggled: sh.send("claude_hooks", !on)
            }
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                Column {
                    anchors.left: parent.left
                    anchors.right: cfgBtn.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        width: parent.width
                        text: "Takvim"
                        color: "white"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    Text {
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        width: parent.width
                        text: page.st.accounts.length > 0 ? page.st.accounts.join(", ")
                              : page.st.calendars > 0 ? page.st.calendars + " iCal adresi" : "Bağlı değil"
                        color: Qt.rgba(1, 1, 1, 0.45)
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
                Rectangle {
                    id: cfgBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: cfgText.implicitWidth + 24; height: 26; radius: 13
                    color: cfgMa.pressed ? "#48484a" : cfgMa.containsMouse ? "#3a3a3c" : "#2c2c2e"
                    Text {
                        id: cfgText
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        anchors.centerIn: parent
                        text: "Ayar dosyası"
                        color: "white"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: cfgMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: { sh.send("open_config"); sh.panelOpen = false }
                    }
                }
            }
        }
    }
}
