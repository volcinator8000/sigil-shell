"""Builder spec → widget QML, for sigil-widgets (the widget maker).

A spec is what the builder edits and what is saved next to the type as <name>.widget.json:

    {
      "name": "gpu_fan", "label": "GPU fan", "description": "…", "width": 260,
      "corner": "{fan} rpm",                       # small label in the corner ("" = none)
      "sources": [                                 # where the numbers / text come from
        {"id": "fan",  "kind": "command", "command": "cat /sys/…/fan1_input", "interval": 2},
        {"id": "cpu",  "kind": "sensor",  "sensor": "cpu"},
        {"id": "todo", "kind": "file",    "path": "~/todo.txt"}
      ],
      "blocks": [                                  # drawn top to bottom
        {"kind": "big",  "text": "{fan} rpm"},
        {"kind": "stat", "label": "cpu", "value": "{cpu:0}%", "graph": "cpu", "min": 0, "max": 100},
        …
      ],
      "options": [{"key": "path", "label": "File", "kind": "string", "default": "~/todo.txt"}]
    }

Text fields are templates: {id} is a source's value, {id:1} rounds a number to 1 decimal,
{opt.key} is one of the widget's options (also inside commands and file paths).
"""
import json
import re

# sensor key → (QML expression, description, needs) ; needs: "sys" | "weather" | "players" | "clock"
SENSORS = {
    "cpu":        ("Sys.cpu", "CPU load, %", "sys"),
    "ram":        ("Sys.ramUsed", "RAM used, GiB", "sys"),
    "ram_pct":    ("100 * Sys.ramUsed / Sys.ramTotal", "RAM used, %", "sys"),
    "ram_total":  ("Sys.ramTotal", "RAM total, GiB", "sys"),
    "cpu_temp":   ("Sys.temp", "CPU temperature, °C", "sys"),
    "igpu":       ("(Sys.gpus.find(g => g.label !== 'dgpu') || { busy: 0 }).busy", "integrated GPU load, %", "sys"),
    "dgpu":       ("(Sys.gpus.find(g => g.label === 'dgpu') || { busy: 0 }).busy", "dedicated GPU load, %", "sys"),
    "dgpu_temp":  ("(Sys.gpus.find(g => g.label === 'dgpu') || { temp: 0 }).temp", "dedicated GPU temperature, °C", "sys"),
    "vram":       ("(Sys.gpus.find(g => g.label === 'dgpu') || { vramUsed: 0 }).vramUsed", "dedicated GPU memory used, GiB", "sys"),
    "fan":        ("(Sys.fans[0] || 0)", "first fan, rpm", "sys"),
    "ssd_temp":   ("Sys.nvmeTemp", "SSD temperature, °C", "sys"),
    "disk":       ("Sys.diskPct", "root disk used, %", "sys"),
    "battery":    ("Sys.batPct", "battery, %", "sys"),
    "watts":      ("Math.abs(Sys.batWatts)", "battery power, W", "sys"),
    "charging":   ("(Sys.batStatus === 'Charging' ? 'charging' : Sys.batStatus === 'Discharging' ? 'on battery' : Sys.batStatus.toLowerCase())", "battery state, text", "sys"),
    "down":       ("Sys.rxRate / 1024", "download, KiB/s", "sys"),
    "up":         ("Sys.txRate / 1024", "upload, KiB/s", "sys"),
    "ip":         ("Sys.netIp", "local IP address", "sys"),
    "weather_temp": ("Weather.temp", "outside temperature, °C", "weather"),
    "weather":    ("Weather.description", "weather, text", "weather"),
    "weather_icon": ("Weather.glyph", "weather icon", "weather"),
    "city":       ("Weather.city", "weather location", "weather"),
    "track":      ("(Players.active ? Players.active.trackTitle || '' : '')", "playing track title", "players"),
    "artist":     ("(Players.active ? Players.active.trackArtist || '' : '')", "playing artist", "players"),
    "time":       ("Qt.formatDateTime(clock.date, 'HH:mm')", "time, HH:mm", "clock"),
    "seconds":    ("Qt.formatDateTime(clock.date, 'ss')", "seconds", "clock"),
    "date":       ("Qt.formatDate(clock.date, 'dddd d MMMM')", "date", "clock"),
    "uptime_h":   ("clock.date && 0", "(placeholder)", "clock"),
}
SENSORS.pop("uptime_h")

BLOCKS = {
    "big":     "Big text",
    "text":    "Text",
    "stat":    "Label + value (+ graph)",
    "bar":     "Progress bar",
    "graph":   "Graph",
    "lines":   "Command / file output (lines)",
    "divider": "Divider",
    "button":  "Button (runs a command)",
    "spacer":  "Space",
}
BLOCK_DEFAULTS = {
    "big":     {"text": "{cpu:0}%", "size": 34, "color": "fg", "align": "left"},
    "text":    {"text": "Hello", "size": 13, "color": "dim", "bold": False, "align": "left"},
    "stat":    {"label": "cpu", "value": "{cpu:0}%", "graph": "", "min": 0, "max": 100},
    "bar":     {"label": "disk", "value": "{disk:0}%", "source": "disk", "min": 0, "max": 100},
    "graph":   {"source": "cpu", "min": 0, "max": 100, "height": 40, "color": "a1"},
    "lines":   {"source": "", "max": 8, "size": 12, "color": "fg"},
    "divider": {},
    "button":  {"text": "Run", "command": "notify-send hi"},
    "spacer":  {"height": 8},
}
COLORS = {"fg": "Theme.fg", "dim": "Theme.widgetDim", "a1": "Theme.a1", "a2": "Theme.a2",
          "ok": "Theme.ok", "warn": "Theme.warn", "crit": "Theme.crit"}
ALIGN = {"left": "Text.AlignLeft", "center": "Text.AlignHCenter", "right": "Text.AlignRight"}

NAME_RE = re.compile(r"^[a-z][a-z0-9_]{1,31}$")
ID_RE = re.compile(r"^[a-z][a-z0-9_]{0,23}$")


def q(s):
    """A JS string literal."""
    return json.dumps(str(s), ensure_ascii=False)


def num(x, d=0):
    try:
        return float(x)
    except (TypeError, ValueError):
        return d


def new_spec(name="my_widget"):
    return {
        "name": name, "label": "My widget", "description": "", "width": 260, "corner": "",
        "sources": [{"id": "cpu", "kind": "sensor", "sensor": "cpu"}],
        "blocks": [
            {"kind": "text", "text": "CPU", "size": 12, "color": "dim", "bold": False, "align": "left"},
            {"kind": "big", "text": "{cpu:0}%", "size": 34, "color": "fg", "align": "left"},
            {"kind": "graph", "source": "cpu", "min": 0, "max": 100, "height": 40, "color": "a1"},
        ],
        "options": [],
    }


def validate(spec, builtin_names=()):
    """List of problems (empty = fine)."""
    errs = []
    if not NAME_RE.match(spec.get("name", "")):
        errs.append("Name: lowercase letters, digits and _ only, 2–32 characters, starting with a letter")
    ids = [s.get("id", "") for s in spec.get("sources", [])]
    for i in ids:
        if not ID_RE.match(i):
            errs.append(f"Data “{i}”: ids are lowercase letters, digits and _")
    if len(set(ids)) != len(ids):
        errs.append("Two data sources share an id")
    for s in spec.get("sources", []):
        if s.get("kind") == "sensor" and s.get("sensor") not in SENSORS:
            errs.append(f"Data “{s.get('id')}”: pick a sensor")
        if s.get("kind") == "command" and not s.get("command", "").strip():
            errs.append(f"Data “{s.get('id')}”: the command is empty")
    for o in spec.get("options", []):
        if not ID_RE.match(o.get("key", "")):
            errs.append(f"Option “{o.get('key')}”: keys are lowercase letters, digits and _")
    return errs


def used_tokens(spec):
    """Source ids referenced anywhere (templates, graph/bar/lines sources)."""
    text = json.dumps(spec.get("blocks", [])) + spec.get("corner", "")
    ids = set(re.findall(r"\{([a-z][a-z0-9_]*)(?::\d)?\}", text))
    for b in spec.get("blocks", []):
        for k in ("graph", "source"):
            if b.get(k):
                ids.add(b[k])
    return ids


def generate(spec):
    name = spec["name"]
    sources = [s for s in spec.get("sources", []) if ID_RE.match(s.get("id", ""))]
    by_id = {s["id"]: s for s in sources}
    blocks = spec.get("blocks", [])
    width = int(num(spec.get("width"), 260))
    hist_ids = sorted({b.get("graph") or b.get("source") for b in blocks
                       if b.get("kind") in ("graph", "stat") and (b.get("graph") or b.get("source")) in by_id})
    needs = {SENSORS[s["sensor"]][2] for s in sources if s.get("kind") == "sensor" and s.get("sensor") in SENSORS}

    L = []
    w = L.append
    w("pragma ComponentBehavior: Bound")
    w("")
    w(f"// {spec.get('label') or name}: {spec.get('description') or 'made with the widget maker'}")
    w(f"// Generated by sigil-widgets from {name}.widget.json. Saving from the builder rewrites this")
    w("// file; to edit the QML by hand, use “Edit code” → “Detach from builder” first.")
    w("import QtQuick")
    w("import Quickshell")
    w("import Quickshell.Io")
    w("import qs.services")
    w("import qs.components")
    w("")
    w("Column {")
    w("    id: root")
    w("    spacing: 6")
    w("    property var entry: ({})")
    w("    function o(k) { return entry.opts && entry.opts[k] !== undefined ? entry.opts[k] : Widgets.opt(entry, k); }")
    w(f"    readonly property int w: Math.max(120, entry.w || {width})")
    w("    width: w")
    w("")
    if "sys" in needs:
        w("    // live sensors run only while the desktop is in view")
        w("    property bool counted: false")
        w("    function sync() {")
        w("        if (Widgets.desktopVisible && !counted) { Sys.users++; counted = true; }")
        w("        else if (!Widgets.desktopVisible && counted) { Sys.users--; counted = false; }")
        w("    }")
        w("    Connections { target: Widgets; function onDesktopVisibleChanged() { root.sync(); } }")
    on_complete, on_destroy = [], []
    if "sys" in needs:
        on_complete.append("root.sync();")
        on_destroy.append("if (root.counted) Sys.users--;")
    if "weather" in needs:
        on_complete.append("Weather.users++;")
        on_destroy.append("Weather.users--;")
    if on_complete:
        w(f"    Component.onCompleted: {{ {' '.join(on_complete)} }}")
        w(f"    Component.onDestruction: {{ {' '.join(on_destroy)} }}")
    if "clock" in needs:
        w("    SystemClock { id: clock; precision: SystemClock.Seconds }")
    w("")

    # ── sources ──
    w("    // ── data ──")
    for s in sources:
        sid, kind = s["id"], s.get("kind")
        if kind == "sensor":
            expr = SENSORS.get(s.get("sensor"), ("0",))[0]
            w(f"    readonly property var s_{sid}: {expr}")
        elif kind == "command":
            iv = max(1, int(num(s.get("interval"), 5)))
            w(f"    property string s_{sid}: \"\"")
            w("    Process {")
            w(f"        id: p_{sid}")
            w(f"        command: [\"sh\", \"-c\", root.fmt({q(s.get('command', ''))})]")
            w("        stdout: StdioCollector {")
            w(f"            onStreamFinished: {{ root.s_{sid} = text.replace(/\\s+$/, \"\");"
              + (f" root.h_{sid} = root.push(root.h_{sid}, root.s_{sid});" if sid in hist_ids else "") + " }")
            w("        }")
            w("    }")
            w(f"    Timer {{ interval: {iv * 1000} * (Theme.rich ? 1 : 3); running: true; repeat: true; triggeredOnStart: true;"
              f" onTriggered: if (!p_{sid}.running) p_{sid}.running = true }}")
        elif kind == "file":
            w(f"    property string s_{sid}: \"\"")
            path = s.get("path", "")
            pexpr = f"Theme.home + root.fmt({q(path[1:])})" if path.startswith("~") else f"root.fmt({q(path)})"
            w(f"    FileView {{ path: {pexpr}; watchChanges: true; printErrors: false; onFileChanged: reload();"
              f" onLoaded: root.s_{sid} = text().replace(/\\s+$/, \"\") }}")
    for hid in hist_ids:
        w(f"    property var h_{hid}: []")
    if hist_ids:
        w("    function push(a, v) { const n = Number(v); const b = a.slice(-119); b.push(isNaN(n) ? 0 : n); return b; }")
        sensor_hist = [h for h in hist_ids if by_id[h].get("kind") != "command"]
        if sensor_hist:
            pushes = " ".join(f"root.h_{h} = root.push(root.h_{h}, root.s_{h});" for h in sensor_hist)
            w(f"    Timer {{ interval: Theme.rich ? 1000 : 4000; running: true; repeat: true; triggeredOnStart: true; onTriggered: {{ {pushes} }} }}")
    vals = ", ".join(f"{q(s['id'])}: root.s_{s['id']}" for s in sources)
    w(f"    readonly property var v: ({{ {vals} }})")
    w("    // template text: {id}, {id:1} (decimals), {opt.key}")
    w("    function fmt(t) {")
    w("        return String(t).replace(/\\{(opt\\.)?([a-z][a-z0-9_]*)(?::(\\d))?\\}/g, (m, opt, k, d) => {")
    w("            let x = opt ? root.o(k) : root.v[k];")
    w("            if (x === undefined || x === null) return opt ? \"\" : m;")
    w("            if (d !== undefined && x !== \"\" && !isNaN(Number(x))) return Number(x).toFixed(parseInt(d));")
    w("            if (typeof x === \"number\") return String(Math.round(x * 10) / 10);")
    w("            return String(x);")
    w("        });")
    w("    }")
    w("    function n(k) { const x = Number(root.v[k]); return isNaN(x) ? 0 : x; }")
    w("    function runAll() { " + " ".join(f"if (!p_{s['id']}.running) p_{s['id']}.running = true;" for s in sources if s.get("kind") == "command") + " }")
    w("")
    corner = spec.get("corner", "")
    w(f"    WidgetHeader {{ title: {q(spec.get('label') or name)}; detail: {('root.fmt(' + q(corner) + ')') if corner else q('')} }}")
    w("")

    # ── blocks ──
    for i, b in enumerate(blocks):
        k = b.get("kind")
        col = COLORS.get(b.get("color", "fg"), "Theme.fg")
        if k in ("big", "text"):
            size = int(num(b.get("size"), 34 if k == "big" else 13))
            bold = "true" if (k == "big" or b.get("bold")) else "false"
            w("    WLabel {")
            w("        width: root.w")
            w("        wrapMode: Text.Wrap")
            w(f"        horizontalAlignment: {ALIGN.get(b.get('align', 'left'), 'Text.AlignLeft')}")
            w(f"        text: root.fmt({q(b.get('text', ''))})")
            w(f"        font.pixelSize: {size}")
            w(f"        font.bold: {bold}")
            w(f"        color: {col}")
            w("    }")
        elif k == "stat":
            g = b.get("graph") if b.get("graph") in hist_ids else ""
            w("    Column {")
            w("        width: root.w")
            w("        spacing: 3")
            w("        Item {")
            w("            width: root.w; height: 18")
            w(f"            WLabel {{ anchors.verticalCenter: parent.verticalCenter; text: root.fmt({q(b.get('label', ''))}); color: Theme.widgetDim; font.pixelSize: 12 }}")
            w(f"            WLabel {{ anchors {{ right: parent.right; verticalCenter: parent.verticalCenter }} text: root.fmt({q(b.get('value', ''))}); font.pixelSize: 13; font.bold: true }}")
            w("        }")
            if g:
                w(f"        Sparkline {{ width: root.w; height: 22; values: root.h_{g}; minValue: {num(b.get('min'), 0)}; maxValue: {num(b.get('max'), 100)} }}")
            w("    }")
        elif k == "bar":
            src = b.get("source", "")
            frac = (f"Math.max(0, Math.min(1, (root.n({q(src)}) - {num(b.get('min'), 0)}) / {max(1e-6, num(b.get('max'), 100) - num(b.get('min'), 0))}))"
                    if src in by_id else "0")
            w("    Column {")
            w("        width: root.w")
            w("        spacing: 4")
            w("        Item {")
            w("            width: root.w; height: 16")
            w(f"            WLabel {{ anchors.verticalCenter: parent.verticalCenter; text: root.fmt({q(b.get('label', ''))}); color: Theme.widgetDim; font.pixelSize: 12 }}")
            w(f"            WLabel {{ anchors {{ right: parent.right; verticalCenter: parent.verticalCenter }} text: root.fmt({q(b.get('value', ''))}); font.pixelSize: 12 }}")
            w("        }")
            w("        Rectangle {")
            w("            width: root.w; height: 6; radius: 3")
            w("            color: Theme.alpha(Theme.fg, 0.08)")
            w(f"            Rectangle {{ readonly property real f: {frac}; width: parent.width * f; height: parent.height; radius: 3;"
              " color: f >= 0.9 ? Theme.crit : f >= 0.8 ? Theme.warn : Theme.a1 }")
            w("        }")
            w("    }")
        elif k == "graph":
            src = b.get("source", "")
            if src in hist_ids:
                w(f"    Sparkline {{ width: root.w; height: {int(num(b.get('height'), 40))}; values: root.h_{src};"
                  f" minValue: {num(b.get('min'), 0)}; maxValue: {num(b.get('max'), 100)}; lineColor: {COLORS.get(b.get('color', 'a1'), 'Theme.a1')} }}")
        elif k == "lines":
            src = b.get("source", "")
            if src in by_id:
                w("    Column {")
                w("        width: root.w")
                w("        Repeater {")
                w(f"            model: String(root.v[{q(src)}] || \"\").split(\"\\n\").slice(0, {int(num(b.get('max'), 8))})")
                w("            delegate: WLabel {")
                w("                required property string modelData")
                w("                width: root.w")
                w("                elide: Text.ElideRight")
                w("                text: modelData")
                w(f"                font.pixelSize: {int(num(b.get('size'), 12))}")
                w(f"                color: {col}")
                w("            }")
                w("        }")
                w("    }")
        elif k == "divider":
            w("    Rectangle { width: root.w; height: 1; color: Theme.alpha(Theme.fg, 0.1) }")
        elif k == "spacer":
            w(f"    Item {{ width: 1; height: {int(num(b.get('height'), 8))} }}")
        elif k == "button":
            w("    ChipButton {")
            w(f"        text: root.fmt({q(b.get('text', 'Run'))})")
            w("        anchors.verticalCenter: undefined")
            w(f"        onClicked: {{ if (Widgets.editing) return; Quickshell.execDetached([\"sh\", \"-c\", {q(b.get('command', ''))}]); refresh.restart(); }}")
            w("    }")
    if any(b.get("kind") == "button" for b in blocks):
        w("    Timer { id: refresh; interval: 600; onTriggered: root.runAll() }")
    w("}")
    return "\n".join(L) + "\n"


def registry_entry(spec):
    opts = []
    for o in spec.get("options", []):
        e = {"key": o["key"], "label": o.get("label") or o["key"], "kind": o.get("kind", "string")}
        d = o.get("default", "")
        if e["kind"] == "bool":
            d = bool(d)
        elif e["kind"] == "int":
            d = int(num(d))
            e.update({"min": int(num(o.get("min"), 0)), "max": int(num(o.get("max"), 100)), "step": 1})
        e["default"] = d
        opts.append(e)
    return {"type": spec["name"], "label": spec.get("label") or spec["name"],
            "description": spec.get("description") or "Made with the widget maker", "options": opts, "maker": True}
