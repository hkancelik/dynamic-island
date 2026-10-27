import QtQuick
import org.kde.kirigami as Kirigami

// Tema ikonunu tek renge boyayan küçük sarmalayıcı.
Kirigami.Icon {
    property color tint: "white"
    property int size: 16

    width: size
    height: size
    isMask: true
    color: tint
}
