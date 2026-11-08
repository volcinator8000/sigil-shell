pragma Singleton
pragma ComponentBehavior: Bound

// Open-Meteo (no API key). Location comes from settings.json → weather.{city,lat,lon}.
// Refreshes every 30 min on AC, every 60 min on battery, only while a widget uses it.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property int users: 0
    property bool ready: false
    property string error: ""
    property real temp: 0
    property int code: 0
    property bool isDay: true
    property real high: 0
    property real low: 0
    property var hours: []     // [{ label: "15h", temp: 9 }, ...]

    readonly property string city: Theme.weather.city || ""
    readonly property string description: describe(code)
    readonly property string glyph: icon(code, isDay)

    function describe(c) {
        if (c === 0) return "Clear";
        if (c <= 2) return "Partly cloudy";
        if (c === 3) return "Overcast";
        if (c <= 48) return "Fog";
        if (c <= 57) return "Drizzle";
        if (c <= 67) return c >= 65 ? "Heavy rain" : "Rain";
        if (c <= 77) return "Snow";
        if (c <= 82) return "Showers";
        if (c <= 86) return "Snow showers";
        return "Thunderstorm";
    }
    function icon(c, day) {
        const g = cp => String.fromCodePoint(cp);
        if (c === 0) return day ? g(0xF0599) : g(0xF0594);       // sunny / night
        if (c <= 2) return day ? g(0xF0595) : g(0xF0F31);        // partly cloudy
        if (c === 3) return g(0xF0590);                           // cloudy
        if (c <= 48) return g(0xF0591);                           // fog
        if (c <= 67 || (c >= 80 && c <= 82)) return g(0xF0597);  // rainy
        if (c <= 77 || c <= 86) return g(0xF0598);                // snowy
        return g(0xF0593);                                        // lightning
    }

    Process {
        id: fetch
        command: ["curl", "-sf", "--max-time", "15",
            "https://api.open-meteo.com/v1/forecast?latitude=" + Theme.weather.lat + "&longitude=" + Theme.weather.lon +
            "&current=temperature_2m,weather_code,is_day&hourly=temperature_2m&daily=temperature_2m_max,temperature_2m_min" +
            "&timezone=auto&forecast_days=2"]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
        onExited: (codeOut) => { if (codeOut !== 0) root.error = "offline"; }
    }

    function parse(t) {
        if (!t) return;
        try {
            const j = JSON.parse(t);
            temp = j.current.temperature_2m;
            code = j.current.weather_code;
            isDay = j.current.is_day === 1;
            high = j.daily.temperature_2m_max[0];
            low = j.daily.temperature_2m_min[0];
            const now = j.current.time.slice(0, 13);
            const start = j.hourly.time.findIndex(x => x.slice(0, 13) === now);
            const out = [];
            for (let k = 3; k <= 12 && start >= 0; k += 3) {
                const i = start + k;
                if (i < j.hourly.time.length) out.push({ label: j.hourly.time[i].slice(11, 13) + "h", temp: Math.round(j.hourly.temperature_2m[i]) });
            }
            hours = out;
            ready = true;
            error = "";
        } catch (e) {
            error = "bad response";
        }
    }

    Timer {
        interval: (Theme.rich ? 30 : 60) * 60 * 1000
        running: root.users > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: fetch.running = true
    }
    Connections {
        target: Theme
        function onWeatherChanged() { if (root.users > 0) fetch.running = true; }
    }
}
