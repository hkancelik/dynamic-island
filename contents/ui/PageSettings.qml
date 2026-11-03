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
        Layout.preferredHeight: 40
        Column {
            anchors.left: parent.left
            anchors.right: s2.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
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
                color: Qt.rgba(1, 1, 1, 0.62)
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

    // Bölümler: Genel | Sekmeler | Görünüm
    readonly property int section: sh.settingsSub
    readonly property var sections: [sh.t("Genel"), sh.t("Sekmeler"), sh.t("Görünüm")]
    Rectangle {
        id: seg
        width: parent.width
        height: 28
        radius: 14
        color: Qt.rgba(1, 1, 1, 0.11)
        LiquidPill {
            width: parent.width
            height: parent.height
            baseH: 22
            restAlpha: 0.17
            goalW: (parent.width - 6) / page.sections.length
            goalX: 3 + page.section * goalW
        }
        Row {
            anchors.fill: parent
            anchors.margins: 3
            Repeater {
                model: page.sections
                Item {
                    required property string modelData
                    required property int index
                    width: parent.width / page.sections.length
                    height: 22
                    Text {
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        anchors.centerIn: parent
                        text: modelData
                        color: page.section === index ? "white" : "#8e8e93"
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                    MouseArea { anchors.fill: parent; onClicked: sh.settingsSub = index }
                }
            }
        }
    }

    Item {
        id: body
        anchors.top: seg.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        TabsEditor { anchors.fill: parent; sh: page.sh; visible: page.section === 1 }
        AppearanceEditor { anchors.fill: parent; sh: page.sh; visible: page.section === 2 }

    ColumnLayout {
        visible: page.section === 0
        anchors.fill: parent
        spacing: 8

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 28
            rowSpacing: 2

            Row2 {
                title: sh.t("Plasma bildirim pencereleri")
                hint: sh.t("Kapalıyken bildirimler yalnızca adada")
                on: !page.st.suppress_plasma_popups
                onToggled: page.set("suppress_plasma_popups", on)
            }
            Row2 {
                title: sh.t("Tam ekranda gizle")
                hint: sh.t("Oyun ve videoda ada çekilir")
                on: page.st.hide_in_fullscreen
                onToggled: page.set("hide_in_fullscreen", !on)
            }
            Row2 {
                title: sh.t("Pano geçmişi")
                hint: sh.t("Yalnızca bellekte tutulur")
                on: page.st.clipboard_history
                onToggled: page.set("clipboard_history", !on)
            }
            Row2 {
                title: sh.t("Şarkı sözleri")
                hint: sh.t("LRCLIB'den, söz görünümü açıkken")
                on: page.st.lyrics
                onToggled: page.set("lyrics", !on)
            }
            Row2 {
                title: sh.t("Toplantı uyarısı")
                hint: sh.t("Etkinlikten 5 dk önce, Katıl ile")
                on: page.st.meeting_alerts
                onToggled: page.set("meeting_alerts", !on)
            }
            Row2 {
                title: sh.t("Gizlilik noktaları")
                hint: sh.t("Kamera, mikrofon, ekran paylaşımı")
                on: page.st.privacy_dots
                onToggled: page.set("privacy_dots", !on)
            }
            Row2 {
                title: sh.t("Hava durumu")
                hint: sh.t("Open-Meteo; konum ayar dosyasından")
                on: page.st.weather_enabled
                onToggled: page.set("weather_enabled", !on)
            }
            Row2 {
                title: sh.t("Telefon (KDE Connect)")
                hint: sh.t("Pil, gelen arama, telefonu çaldır")
                on: page.st.phone
                onToggled: page.set("phone", !on)
            }

            // Dil: Otomatik (sistem dili) / English / Türkçe; hemen geçerli
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                Text {
                    renderType: Text.CurveRendering
                    font.family: "Inter"
                    anchors.verticalCenter: parent.verticalCenter
                    text: sh.t("Dil")
                    color: "white"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Repeater {
                        model: [{ k: "auto", l: sh.t("Otomatik") }, { k: "en", l: "English" }, { k: "tr", l: "Türkçe" }]
                        Rectangle {
                            required property var modelData
                            readonly property bool sel: (page.st.language || "auto") === modelData.k
                            width: langText.implicitWidth + 18; height: 24; radius: 12
                            color: sel ? Qt.rgba(1, 1, 1, 0.9) : langMa.containsMouse ? "#3a3a3c" : Qt.rgba(1, 1, 1, 0.17)
                            Text {
                                id: langText
                                renderType: Text.CurveRendering
                                font.family: "Inter"
                                anchors.centerIn: parent
                                text: modelData.l
                                color: parent.sel ? "black" : "white"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                            MouseArea {
                                id: langMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: sh.send("set_language", modelData.k)
                            }
                        }
                    }
                }
            }
            Row2 {
                title: sh.t("Gerçek ses spektrumu")
                hint: sh.t("Çubuklar müziğe göre; ses yalnızca bellekte çözümlenir")
                on: page.st.spectrum !== false
                onToggled: page.set("spectrum", !on)
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
                title: sh.t("Claude Code onayları")
                hint: page.st.claudeHooks ? sh.t("Kurulu · izinler adada sorulur") : sh.t("~/.claude/settings.json'a hook ekler")
                on: page.st.claudeHooks
                onToggled: sh.send("claude_hooks", !on)
            }
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                Column {
                    anchors.left: parent.left
                    anchors.right: cfgBtn.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        width: parent.width
                        text: sh.t("Takvim")
                        color: "white"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    Text {
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        width: parent.width
                        text: page.st.accounts.length > 0 ? page.st.accounts.join(", ")
                              : page.st.calendars > 0 ? sh.t("%1 iCal adresi").arg(page.st.calendars) : sh.t("Bağlı değil")
                        color: Qt.rgba(1, 1, 1, 0.62)
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
                Rectangle {
                    id: cfgBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: cfgText.implicitWidth + 24; height: 26; radius: 13
                    color: cfgMa.pressed ? "#48484a" : cfgMa.containsMouse ? "#3a3a3c" : Qt.rgba(1, 1, 1, 0.17)
                    Text {
                        id: cfgText
                        renderType: Text.CurveRendering
                        font.family: "Inter"
                        anchors.centerIn: parent
                        text: sh.t("Ayar dosyası")
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
}
