pragma ComponentBehavior: Bound

// Widgets: place, restyle and configure desktop widgets, add new ones and
// scaffold new widget types. Everything goes through the Widgets singleton,
// which saves ~/.config/sigil/widgets.json and updates the desktop live.
// The options form is generated from widgets/types/registry.json.

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components
import qs.settings.controls
import qs.settings.lib

PageView {
    id: page
    property bool pageActive: false
    maxWidth: 900

    property int sel: -1
    readonly property var selEntry: { const id = sel; return Widgets.items.find(w => w.id === id) || null; }
    readonly property var selInfo: selEntry ? Widgets.typeInfo(selEntry.type) : null
    property var formOptions: []       // rebuilt only on selection / registry change, not on every save
    property bool confirmReset: false
    property int confirmRemove: -1
    property string newName: ""
    property string createOut: ""
    property bool creating: false

    // outline the selected widget on the desktop only while this page is on screen
    onPageActiveChanged: { Widgets.pageOpen = pageActive; Widgets.selected = pageActive ? sel : -1; }
    Component.onDestruction: { Widgets.pageOpen = false; Widgets.selected = -1; }
    Component.onCompleted: if (Widgets.items.length) select(Widgets.items[0].id)

    function select(id) {
        sel = id;
        if (pageActive) Widgets.selected = id;
        confirmRemove = -1;
        rebuildForm();
        syncControls();
    }
    function rebuildForm() {
        const e = selEntry;
        formOptions = e ? (Widgets.typeInfo(e.type).options || []).map(o => Object.assign({ wid: e.id }, o)) : [];
    }
    function syncControls() {
        const e = selEntry;
        if (!e) return;
        styleSeg.current = e.style || "card";
        opacitySlider.value = e.opacity !== undefined ? e.opacity : 1;
        scaleSlider.value = e.scale !== undefined ? e.scale : 1;
        xField.value = e.x || 0;
        yField.value = e.y || 0;
    }
    Connections {
        target: Widgets
        function onTypesChanged() { page.rebuildForm(); }
        function onItemsChanged() {
            if (page.sel >= 0 && !page.selEntry) page.select(Widgets.items.length ? Widgets.items[0].id : -1);
            else if (page.selEntry) {           // dragged on the desktop: follow x / y
                xField.value = page.selEntry.x || 0;
                yField.value = page.selEntry.y || 0;
            }
        }
    }

    property string geoStatus: ""
    function geocode(city) {
        city = city.trim();
        if (!city) return;
        geoStatus = "looking up " + city + "…";
        Sh.run(["curl", "-fsS", "--max-time", "8",
                "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(city) + "&count=1"], (out, rc) => {
            let r = null;
            try { r = (JSON.parse(out).results || [])[0] || null; } catch (e) {}
            if (rc !== 0 || !r) {
                page.geoStatus = rc !== 0 ? "lookup failed (offline?)" : "no place called \"" + city + "\"";
                return;
            }
            const lat = Math.round(r.latitude * 10000) / 10000, lon = Math.round(r.longitude * 10000) / 10000;
            page.geoStatus = r.name + (r.admin1 ? ", " + r.admin1 : "") + (r.country ? ", " + r.country : "") + " · " + lat + ", " + lon;
            Theme.patchSettings({ weather: { city: r.name, lat: lat, lon: lon } });
            Sh.toast("Weather: " + r.name);
        }, 12);
    }

    function label(e) { return Widgets.typeInfo(e.type).label || e.type; }
    function createType() {
        const n = newName.trim();
        if (!/^[a-z][a-z0-9-]*$/.test(n)) { createOut = "name: lowercase letters, digits and dashes, starting with a letter"; return; }
        creating = true;
        createOut = "creating " + n + "…";
        Sh.runAll([Sh.home + "/.local/bin/sigil-new-widget", n], (o, rc) => {
            page.creating = false;
            page.createOut = (o || (rc === 0 ? "done" : "failed (exit " + rc + ")"));
            if (rc === 0) { Sh.toast("Widget type " + n + " created"); page.newName = ""; nameField.text = ""; }
        }, 20);
    }

    // ── top bar ──────────────────────────────────────────────────────
    Section {
        title: "Desktop"
        description: "Drag widgets around in arrange mode (SUPER+SHIFT+W); the outline marks the one selected below."
        SettingRow {
            title: "Arrange on desktop"
            subtitle: "drag mode on the desktop; this window hides"
            ActionButton {
                text: "Arrange"
                accent: true
                onClicked: { if (!Widgets.editing) Widgets.toggleEdit(); Sh.hideWindow(); }
            }
        }
        SettingRow {
            title: "Widget maker"
            subtitle: "build your own widgets without code, or edit a type's options and QML (sigil-widgets)"
            ActionButton { text: "Open"; onClicked: { Sh.spawn([Sh.home + "/.local/bin/sigil-widgets"]); Sh.hideWindow(); } }
        }
        SettingRow {
            title: "Show widgets"
            subtitle: "raise them above windows while you edit here"
            Toggle { checked: Widgets.peek; onToggled: on => { if (on !== Widgets.peek) Widgets.togglePeek(); } }
        }
        SettingRow {
            title: "Reset layout"
            subtitle: page.confirmReset ? "removes every widget and puts the three defaults back" : "back to calendar, weather and performance"
            ActionButton { visible: !page.confirmReset; text: "Reset layout…"; danger: true; onClicked: page.confirmReset = true }
            ActionButton { visible: page.confirmReset; text: "Cancel"; onClicked: page.confirmReset = false }
            ActionButton {
                visible: page.confirmReset
                text: "Reset"; danger: true
                onClicked: { page.confirmReset = false; Widgets.resetLayout(); page.select(Widgets.items.length ? Widgets.items[0].id : -1); Sh.toast("Widget layout reset"); }
            }
        }
    }

    // ── placed widgets | selected widget ─────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 16

        Section {
            Layout.preferredWidth: 300
            Layout.fillWidth: false
            Layout.alignment: Qt.AlignTop
            title: "On the desktop"
            description: Widgets.items.length + " widget(s) · later in the list = drawn on top"
            Repeater {
                model: Widgets.items
                delegate: Item {
                    id: wrow
                    required property var modelData
                    required property int index
                    readonly property bool on: wrow.modelData.id === page.sel
                    Layout.fillWidth: true
                    implicitHeight: 52
                    Rectangle {
                        anchors { fill: parent; margins: 4 }
                        radius: Math.min(Theme.radius * 0.7, 10)
                        color: wrow.on ? Theme.alpha(Theme.a1, 0.08) : wm.containsMouse ? Theme.alpha(Theme.fg, 0.04) : "transparent"
                        Rectangle {
                            visible: wrow.on
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; topMargin: 8; bottomMargin: 8 }
                            width: 2
                            color: Theme.a1
                        }
                    }
                    MouseArea {
                        id: wm
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { Sh.snd("click"); page.select(wrow.modelData.id); }
                    }
                    Column {
                        anchors { left: parent.left; leftMargin: 16; right: btns.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                        spacing: 2
                        Label {
                            width: parent.width
                            text: page.label(wrow.modelData)
                            color: wrow.on ? Theme.a1 : Theme.fg
                            elide: Text.ElideRight
                        }
                        Label {
                            width: parent.width
                            text: (wrow.modelData.style || "card") + " · " + (wrow.modelData.ay || "top") + "-" + (wrow.modelData.ax || "left") + " · " + Math.round(wrow.modelData.x || 0) + ", " + Math.round(wrow.modelData.y || 0)
                            color: Theme.dim
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }
                    Row {
                        id: btns
                        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        spacing: 0
                        visible: page.confirmRemove !== wrow.modelData.id
                        IconButton { glyph: "\u{F0143}"; hint: "Earlier"; enabled: wrow.index > 0; onClicked: Widgets.reorder(wrow.modelData.id, -1) }
                        IconButton { glyph: "\u{F0140}"; hint: "Later (on top)"; enabled: wrow.index < Widgets.items.length - 1; onClicked: Widgets.reorder(wrow.modelData.id, 1) }
                        IconButton { glyph: "\u{F018F}"; hint: "Duplicate"; onClicked: page.select(Widgets.duplicate(wrow.modelData.id)) }
                        IconButton { glyph: "\u{F01B4}"; hint: "Remove"; tint: Theme.crit; onClicked: page.confirmRemove = wrow.modelData.id }
                    }
                    Row {
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 6
                        visible: page.confirmRemove === wrow.modelData.id
                        ActionButton { text: "Keep"; onClicked: page.confirmRemove = -1 }
                        ActionButton {
                            text: "Remove"; danger: true
                            onClicked: { page.confirmRemove = -1; Widgets.remove(wrow.modelData.id); Sh.toast(page.label(wrow.modelData) + " removed"); }
                        }
                    }
                }
            }
            Label {
                visible: Widgets.items.length === 0
                Layout.fillWidth: true
                Layout.margins: 14
                text: "No widgets. Add one below."
                color: Theme.dim
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 22

            Section {
                title: page.selEntry ? page.label(page.selEntry) + "  #" + page.selEntry.id : "Nothing selected"
                description: page.selInfo ? (page.selInfo.description || "") : "Select a widget on the left."
                visible: true
                enabled: page.selEntry !== null
                SettingRow {
                    title: "Style"
                    Segmented {
                        id: styleSeg
                        options: Widgets.styles
                        onActivated: v => Widgets.update(page.sel, { style: v })
                    }
                }
                SettingRow {
                    title: "Opacity"
                    Slider {
                        id: opacitySlider
                        trackWidth: 160
                        from: 0.2; to: 1; stepSize: 0.05
                        format: v => Math.round(v * 100) + "%"
                        onCommitted: v => Widgets.update(page.sel, { opacity: v })
                    }
                }
                SettingRow {
                    title: "Scale"
                    Slider {
                        id: scaleSlider
                        trackWidth: 160
                        from: 0.5; to: 2; stepSize: 0.05
                        format: v => v.toFixed(2) + "x"
                        onCommitted: v => Widgets.update(page.sel, { scale: v })
                    }
                }
                SettingRow {
                    title: "Position"
                    subtitle: page.selEntry ? "px from the " + ({ left: "left edge", center: "centre", right: "right edge" })[page.selEntry.ax || "left"]
                                            + " / " + ({ top: "top", center: "centre", bottom: "bottom" })[page.selEntry.ay || "top"]
                                            + " (anchor follows where you drop it)" : ""
                    Label { text: "x"; color: Theme.dim }
                    SpinField { id: xField; from: -4000; to: 8000; stepSize: 10; onValueModified: v => Widgets.update(page.sel, { x: v }) }
                    Label { text: "y"; color: Theme.dim }
                    SpinField { id: yField; from: -4000; to: 8000; stepSize: 10; onValueModified: v => Widgets.update(page.sel, { y: v }) }
                }
            }

            Section {
                visible: page.selEntry !== null
                title: "Options"
                description: page.formOptions.length ? "" : "This widget type has no options (add some to registry.json)."
                actions: [
                    ActionButton {
                        text: "Reset options"
                        enabled: page.formOptions.length > 0
                        onClicked: { Widgets.resetOpts(page.sel); page.rebuildForm(); }
                    }
                ]
                Repeater {
                    model: page.formOptions
                    delegate: SettingRow {
                        id: optRow
                        required property var modelData
                        readonly property var value: Widgets.opt(page.selEntry, modelData.key)
                        readonly property real span: ((modelData.max ?? 100) - (modelData.min ?? 0)) / (modelData.step || 1)
                        function commit(v) { Widgets.setOpt(modelData.wid, modelData.key, v); }
                        title: modelData.label || modelData.key
                        subtitle: modelData.kind === "string" ? "Enter or leaving the field saves" : ""

                        Toggle {
                            visible: optRow.modelData.kind === "bool"
                            checked: optRow.value === true
                            onToggled: on => optRow.commit(on)
                        }
                        Slider {
                            visible: optRow.modelData.kind === "int" && optRow.span <= 200
                            trackWidth: 160
                            from: optRow.modelData.min ?? 0
                            to: optRow.modelData.max ?? 100
                            stepSize: optRow.modelData.step || 1
                            value: Number(optRow.value) || 0
                            format: v => String(Math.round(v))
                            onCommitted: v => optRow.commit(Math.round(v))
                        }
                        SpinField {
                            visible: optRow.modelData.kind === "int" && optRow.span > 200
                            from: optRow.modelData.min ?? -1e9
                            to: optRow.modelData.max ?? 1e9
                            stepSize: optRow.modelData.step || 1
                            value: Number(optRow.value) || 0
                            onValueModified: v => optRow.commit(Math.round(v))
                        }
                        TextField {
                            id: strField
                            visible: optRow.modelData.kind === "string"
                            implicitWidth: 240
                            text: optRow.modelData.kind === "string" ? String(optRow.value ?? "") : ""
                            onAccepted: if (text !== String(optRow.value ?? "")) optRow.commit(text)
                            input.onActiveFocusChanged: if (!input.activeFocus && visible && text !== String(optRow.value ?? "")) optRow.commit(text)
                        }
                        Segmented {
                            visible: optRow.modelData.kind === "enum" && (optRow.modelData.choices || []).length <= 4
                            options: optRow.modelData.choices || []
                            current: String(optRow.value)
                            onActivated: v => optRow.commit(v)
                        }
                        Dropdown {
                            visible: optRow.modelData.kind === "enum" && (optRow.modelData.choices || []).length > 4
                            model: optRow.modelData.choices || []
                            currentIndex: Math.max(0, (optRow.modelData.choices || []).indexOf(optRow.value))
                            onActivated: i => optRow.commit(optRow.modelData.choices[i])
                        }
                    }
                }
            }
        }
    }

    // ── catalogue ────────────────────────────────────────────────────
    Section {
        title: "Add a widget"
        description: Widgets.types.length + " type(s) in widgets/types/registry.json"
        card: false
        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: 10
            rowSpacing: 10
            uniformCellWidths: true
            Repeater {
                model: Widgets.types
                delegate: Rectangle {
                    id: tc
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 84
                    radius: Theme.radius
                    color: Theme.s1
                    border.width: 1
                    border.color: tcm.hovered ? Theme.a2 : Theme.line
                    HoverHandler { id: tcm }
                    Column {
                        anchors { left: parent.left; right: addBtn.left; top: parent.top; margins: 12; rightMargin: 8 }
                        spacing: 4
                        Label { width: parent.width; text: tc.modelData.label || tc.modelData.type; elide: Text.ElideRight }
                        Label {
                            width: parent.width
                            text: tc.modelData.description || ""
                            color: Theme.dim
                            font.pixelSize: 10
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }
                    }
                    ActionButton {
                        id: addBtn
                        anchors { right: parent.right; top: parent.top; margins: 10 }
                        text: "Add"
                        onClicked: {
                            const id = Widgets.add(tc.modelData.type, {});
                            page.select(id);
                            Sh.toast((tc.modelData.label || tc.modelData.type) + " added");
                        }
                    }
                }
            }
        }
    }

    Section {
        title: "Create a new widget type"
        description: "sigil-new-widget <name> creates quickshell/widgets/types/<name>.qml from a commented template plus its entry in registry.json. "
                   + "The type then appears in the list above on its own; edit the QML and its options, and changes apply on save."
        SettingRow {
            title: "sigil-new-widget <name>"
            subtitle: "in a terminal, or right here"
            ActionButton {
                text: "Copy command"
                onClicked: Sh.sh('printf "%s" "$1" | wl-copy', () => Sh.toast("Copied"), 4,
                                 ["sigil-new-widget " + (page.newName.trim() || "<name>")])
            }
        }
        SettingRow {
            title: "Name"
            subtitle: "lowercase letters, digits, dashes"
            TextField {
                id: nameField
                implicitWidth: 180
                placeholder: "e.g. battery-ring"
                onEdited: t => page.newName = t
                onAccepted: page.createType()
            }
            ActionButton { text: page.creating ? "Creating…" : "Create"; accent: true; enabled: !page.creating && page.newName.trim() !== ""; onClicked: page.createType() }
        }
        Label {
            visible: page.createOut !== ""
            Layout.fillWidth: true
            Layout.margins: 14
            Layout.topMargin: 2
            text: page.createOut
            color: Theme.dim
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }
    }

    Section {
        title: "Weather location"
        description: "Used by the weather widget and the forecast in the bar."
        SettingRow {
            title: "Location"
            subtitle: page.geoStatus || ((Theme.weather.city || "?") + " · " + Theme.weather.lat + ", " + Theme.weather.lon)
            TextField {
                id: cityField
                implicitWidth: 180
                placeholder: "city"
                text: Theme.weather.city || ""
                onAccepted: page.geocode(text)
            }
            ActionButton { text: "Look up"; onClicked: page.geocode(cityField.text) }
        }
    }
}
