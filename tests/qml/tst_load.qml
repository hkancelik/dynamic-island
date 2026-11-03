import QtQuick
import QtTest

// Her QML dosyası derlenip yüklenebiliyor mu? (ör. yerleşik bir türle ad çakışması: "Palette")
TestCase {
    name: "Load"

    function test_main_compiles() {
        var c = Qt.createComponent(Qt.resolvedUrl("../../contents/ui/main.qml"))
        compare(c.status, Component.Ready, c.errorString())
    }

    function test_components_compile_data() {
        return ["ActRing", "Ambient", "AppearanceEditor", "CommandPalette", "IslandTabs", "PageMusic",
                "PageSettings", "PageSystem", "Spectrum", "TabsEditor"].map(function (n) { return { tag: n, name: n } })
    }
    function test_components_compile(data) {
        var c = Qt.createComponent(Qt.resolvedUrl("../../contents/ui/" + data.name + ".qml"))
        compare(c.status, Component.Ready, c.errorString())
    }
}
