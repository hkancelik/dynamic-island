import QtQuick
import org.kde.kirigami as Kirigami

// Renkli (maskelenmemiş) uygulama ikonu.
Kirigami.Icon {
    property int size: 32

    width: size
    height: size
    fallback: "application-x-executable"
}
