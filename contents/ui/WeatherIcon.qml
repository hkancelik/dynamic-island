import QtQuick

// Hava durumu simgesi: arka uçtaki freedesktop adını (weather-clear…) kendi çizdiğimiz,
// temadan bağımsız simgelere eşler (contents/icons/weather).
Image {
    id: wi

    property string name
    readonly property var map: ({
        "weather-clear": "sun", "weather-clear-night": "moon",
        "weather-few-clouds": "sun-cloud", "weather-few-clouds-night": "moon-cloud",
        "weather-clouds": "cloud", "weather-clouds-night": "moon-cloud", "weather-overcast": "overcast",
        "weather-fog": "fog", "weather-showers-scattered": "rain", "weather-showers": "rain",
        "weather-freezing-rain": "sleet", "weather-snow": "snow", "weather-storm": "storm"
    })

    source: Qt.resolvedUrl("../icons/weather/" + (map[name] || "cloud") + ".svg")
    sourceSize: Qt.size(Math.max(1, width) * 2, Math.max(1, height) * 2)
    fillMode: Image.PreserveAspectFit
    smooth: true
    asynchronous: true
}
