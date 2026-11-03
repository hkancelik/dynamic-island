import QtQuick

// Kaydırılan bir listenin üst ve alt kenarında satırları eritir: satır, görünümün kenarına
// yaklaştıkça saydamlaşır ve kenara varınca tamamen kaybolur.
//
// Neden satır başına saydamlık? Kenara siyah → saydam bir şerit çizmek yalnızca düz siyah zeminde
// işe yarar; arkada albüm ışığı gibi bir şey varsa koyu bir leke bırakır. Maske (MultiEffect) ise
// kademeli saydamlığı uygulamıyor. Satır saydamlığı her zeminde doğru görünür, katman da gerekmez.
//
//   ListView { id: list ... delegate: Item { opacity: fade.factor(this) } }
//   FadeEdges { id: fade; view: list; fadeTop: 26; fadeBottom: 34 }
QtObject {
    id: fe

    property Flickable view
    property real fadeTop: 0             // üst kenardan itibaren erime yüksekliği (px); 0 = kapalı
    property real fadeBottom: 0

    // item: view'ın içeriğindeki bir satır. 0..1 döndürür (1 = tam görünür).
    // Satırın ortası kenardayken 0, fadeTop/fadeBottom kadar içerideyken 1.
    function factor(item) {
        if (!view || !item) return 1
        var c = item.y - view.contentY + item.height / 2        // satır ortasının görünümdeki yeri
        var t = fadeTop > 0 ? c / fadeTop : 1
        var b = fadeBottom > 0 ? (view.height - c) / fadeBottom : 1
        return Math.max(0, Math.min(1, Math.min(t, b)))
    }
}
