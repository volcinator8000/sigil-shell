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
    // the next 24 hours, every hour: [{ label: "15h", temp: 9, code: 61, glyph: "…", rain: 40 }, ...]
    property var hours: []
    // [{ label: "Tue", high: 12, low: 4, code: 61, glyph: "…", text, rain: 70 }, ...] (7, today first)
    property var days: []
    property int rainToday: 0  // % chance, today

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
            "&current=temperature_2m,weather_code,is_day&hourly=temperature_2m,weather_code,precipitation_probability,is_day" +
            "&daily=temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max" +
            "&timezone=auto&forecast_days=7"]
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
            const H = j.hourly;
            for (let k = 1; k <= 24 && start >= 0; k++) {
                const i = start + k;
                if (i >= H.time.length) break;
                const c = H.weather_code ? H.weather_code[i] : 0;
                out.push({ label: H.time[i].slice(11, 13) + "h", temp: Math.round(H.temperature_2m[i]), code: c,
                           glyph: icon(c, H.is_day ? H.is_day[i] === 1 : true),
                           rain: H.precipitation_probability ? (H.precipitation_probability[i] || 0) : 0 });
            }
            hours = out;
            const dl = [];
            for (let i = 0; i < j.daily.time.length; i++) {
                const d = new Date(j.daily.time[i] + "T12:00:00");
                const c = j.daily.weather_code ? j.daily.weather_code[i] : 0;
                dl.push({ label: i === 0 ? "Today" : Qt.formatDate(d, "ddd"), high: Math.round(j.daily.temperature_2m_max[i]),
                          low: Math.round(j.daily.temperature_2m_min[i]), code: c, glyph: icon(c, true), text: describe(c),
                          rain: j.daily.precipitation_probability_max ? (j.daily.precipitation_probability_max[i] || 0) : 0 });
            }
            days = dl;
            rainToday = dl.length ? dl[0].rain : 0;
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
