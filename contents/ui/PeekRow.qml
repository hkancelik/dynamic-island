import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

// Kapalı adadaki kısa uyarı satırı: renkli yuvarlak rozet (isteğe bağlı seviye
// halkasıyla), başlık + alt yazı, sağda değer ya da ek içerik (trailing).
RowLayout {
    id: row

    property string icon
    property color badgeColor: "#2c2c2e"
    property color iconTint: "white"
    property real level: -1            // 0..1: rozetin çevresinde seviye halkası
    property color levelColor: "white"
    property string title
    property string subtitle
    property string value
    property color valueColor: "white"
    default property alias trailing: tail.data

    spacing: 10

    Item {
        Layout.preferredWidth: 32
        Layout.preferredHeight: 32
        Layout.alignment: Qt.AlignVCenter

        Shape {
            visible: row.level >= 0
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Qt.rgba(1, 1, 1, 0.14)
                strokeWidth: 3
                fillColor: "transparent"
                PathAngleArc { centerX: 16; centerY: 16; radiusX: 14.5; radiusY: 14.5; startAngle: 0; sweepAngle: 360 }
            }
            ShapePath {
                strokeColor: row.levelColor
                strokeWidth: 3
                capStyle: ShapePath.RoundCap
                fillColor: "transparent"
                PathAngleArc {
                    centerX: 16; centerY: 16; radiusX: 14.5; radiusY: 14.5
                    startAngle: -90
                    sweepAngle: 360 * Math.max(0, Math.min(1, row.level))
                    Behavior on sweepAngle { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                }
            }
        }
        Rectangle {
            anchors.centerIn: parent
            width: row.level >= 0 ? 22 : 32
            height: width
            radius: width / 2
            color: row.badgeColor
            Rectangle {   // üstte ince ışık çizgisi
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)
            }
            Ico {
                anchors.centerIn: parent
                source: row.icon
                size: row.level >= 0 ? 12 : 16
                tint: row.iconTint
            }
        }
    }

    Column {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: 1
        Text {
            renderType: Text.CurveRendering
            font.family: "Inter"
            width: parent.width
            text: row.title
            color: "white"
            font.pixelSize: 14
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Text {
            renderType: Text.CurveRendering
            font.family: "Inter"
            visible: row.subtitle !== ""
            width: parent.width
            text: row.subtitle
            color: Qt.rgba(1, 1, 1, 0.5)
            font.pixelSize: 12
            elide: Text.ElideRight
        }
    }

    Text {
        renderType: Text.CurveRendering
        font.family: "Inter"
        visible: row.value !== ""
        Layout.alignment: Qt.AlignVCenter
        text: row.value
        color: row.valueColor
        font.pixelSize: 20
        font.weight: Font.DemiBold
        font.letterSpacing: -0.5
        font.features: { "tnum": 1 }
    }

    Item {
        id: tail
        visible: children.length > 0
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: childrenRect.width
        Layout.preferredHeight: childrenRect.height
    }
}
