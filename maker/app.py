"""sigil-widgets: the widget maker (GTK 4 + libadwaita).

    Desktop       every placed widget: style, size, opacity and its options, live
    Widget types  built-in and your own types: preview, add to the desktop, edit the options
                  they offer, edit their QML, duplicate one as a starting point
    Builder       make a widget without writing QML: data sources (sensors, commands, files)
                  and blocks (big text, stats with graphs, bars, command output, buttons);
                  the live preview window redraws as you type

Files
    <repo>/quickshell/widgets/types/<name>.qml          the widget (what the shell loads)
    <repo>/quickshell/widgets/types/<name>.widget.json  the builder's spec for it
    <repo>/quickshell/widgets/types/registry.json       label, description, options per type
    ~/.config/sigil/widgets.json                        the widgets on the desktop
    ~/.cache/sigil/preview/                             preview drafts and log
"""
import copy
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gio, GLib, Gtk, Pango  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
TYPES = REPO / "quickshell" / "widgets" / "types"
REGISTRY = TYPES / "registry.json"
PREVIEW_DIR = REPO / "preview"
HOME = Path.home()
INSTANCES = HOME / ".config" / "sigil" / "widgets.json"
CACHE = HOME / ".cache" / "sigil" / "preview"
SPEC_FILE = CACHE / "spec.json"
LOG_FILE = CACHE / "log"
STYLES = ["frost", "card", "glass", "bare"]
APP_ID = "dev.sigil.widgets"


# ── files ───────────────────────────────────────────────────────────────
def write_atomic(path, text):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name("." + path.name + ".tmp")
    tmp.write_text(text)
    os.replace(tmp, path)


def dump(obj):
    return json.dumps(obj, indent=2, ensure_ascii=False) + "\n"


def load_json(path, default):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return default


def load_registry():
    return load_json(REGISTRY, [])


def save_registry(reg):
    write_atomic(REGISTRY, dump(reg))


def load_instances():
    return load_json(INSTANCES, [])


def save_instances(items):
    write_atomic(INSTANCES, dump(items))


def spec_path(name):
    return TYPES / f"{name}.widget.json"


def qs_ipc(*args):
    try:
        return subprocess.run(["qs", "-c", "sigil", "ipc", "call", *args], capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


# ── live preview (bin/../preview, a second Quickshell drawing one widget) ──
class Preview:
    def __init__(self):
        self.proc = None
        self.n = 0
        CACHE.mkdir(parents=True, exist_ok=True)

    @property
    def running(self):
        return self.proc is not None and self.proc.poll() is None

    def show(self, spec):
        """spec: dict for preview.json (type, style, opts, w, h, scale, source?)."""
        write_atomic(SPEC_FILE, json.dumps(spec))
        if not self.running:
            env = dict(os.environ, SIGIL_PREVIEW=str(SPEC_FILE))
            self.log = open(LOG_FILE, "w")
            self.proc = subprocess.Popen(["qs", "-p", str(PREVIEW_DIR)], env=env, stdout=self.log, stderr=subprocess.STDOUT,
                                         stdin=subprocess.DEVNULL, start_new_session=True)

    def draft(self, qml):
        """Write a draft QML file under a fresh name (a new URL makes the preview reload it)."""
        self.n += 1
        for old in CACHE.glob("draft-*.qml"):
            try:
                if old.stat().st_mtime < time.time() - 5:
                    old.unlink()
            except OSError:
                pass
        p = CACHE / f"draft-{os.getpid()}-{self.n}.qml"
        p.write_text(qml)
        return str(p)

    def errors(self, since=0):
        """Warnings / errors about the widget from the preview log (after byte offset `since`)."""
        try:
            with open(LOG_FILE, errors="replace") as f:
                f.seek(since)
                text = f.read()
        except OSError:
            return []
        out = []
        for line in text.splitlines():
            line = re.sub(r"\x1b\[[0-9;]*m", "", line)
            if ("draft-" in line or "/types/" in line or "ERROR" in line) and ("WARN" in line or "ERROR" in line):
                out.append(re.sub(r"file://\S*/(draft-\S*?\.qml|types/\S*?\.qml)", r"\1", line.strip()))
        return out[-6:]

    def log_size(self):
        try:
            return LOG_FILE.stat().st_size
        except OSError:
            return 0

    def stop(self):
        if self.running:
            try:
                os.killpg(self.proc.pid, 15)
            except OSError:
                pass
        self.proc = None


# ── small row helpers ───────────────────────────────────────────────────
def plain(cls, **props):
    """A row whose title / subtitle are plain text (markup off before any text is set)."""
    r = cls()
    r.set_use_markup(False)
    for k, v in props.items():
        r.set_property(k, v)
    return r


def entry_row(title, value, on_change, tooltip=None):
    r = plain(Adw.EntryRow, title=title)
    r.set_text(str(value if value is not None else ""))
    r.connect("changed", lambda w: on_change(w.get_text()))
    if tooltip:
        r.set_tooltip_text(tooltip)
    return r


def spin_row(title, value, lo, hi, step, on_change, digits=0, subtitle=None):
    r = Adw.SpinRow.new_with_range(lo, hi, step)
    r.set_use_markup(False)
    r.set_title(title)
    if subtitle:
        r.set_subtitle(subtitle)
    r.set_digits(digits)
    try:
        r.set_value(float(value))
    except (TypeError, ValueError):
        r.set_value(lo)
    r.connect("notify::value", lambda w, _p: on_change(w.get_value() if digits else int(round(w.get_value()))))
    return r


def switch_row(title, value, on_change, subtitle=None):
    r = plain(Adw.SwitchRow, title=title)
    if subtitle:
        r.set_subtitle(subtitle)
    r.set_active(bool(value))
    r.connect("notify::active", lambda w, _p: on_change(w.get_active()))
    return r


def combo_row(title, choices, value, on_change, labels=None, subtitle=None):
    r = plain(Adw.ComboRow, title=title)
    if subtitle:
        r.set_subtitle(subtitle)
    r.set_model(Gtk.StringList.new([str(x) for x in (labels or choices)]))
    try:
        r.set_selected(choices.index(value))
    except ValueError:
        r.set_selected(0)
    r.connect("notify::selected", lambda w, _p: on_change(choices[w.get_selected()]) if w.get_selected() < len(choices) else None)
    return r


def icon_button(icon, tooltip, cb, css=None):
    b = Gtk.Button(icon_name=icon, tooltip_text=tooltip, valign=Gtk.Align.CENTER)
    b.add_css_class("flat")
    if css:
        b.add_css_class(css)
    b.connect("clicked", lambda *_: cb())
    return b


def option_rows(opt_schema, values, on_change):
    """Rows for a type's options (registry schema), reading `values`, calling on_change(key, value)."""
    rows = []
    for o in opt_schema:
        k, kind, cur = o["key"], o.get("kind", "string"), values.get(o["key"], o.get("default"))
        cb = (lambda key: (lambda v: on_change(key, v)))(k)
        if kind == "bool":
            rows.append(switch_row(o.get("label", k), cur, cb))
        elif kind == "int":
            rows.append(spin_row(o.get("label", k), cur if cur is not None else 0, o.get("min", 0), o.get("max", 100), o.get("step", 1), cb))
        elif kind == "enum":
            ch = o.get("choices", [])
            rows.append(combo_row(o.get("label", k), ch, cur, cb))
        else:
            rows.append(entry_row(o.get("label", k), cur, cb))
    return rows


class Debounce:
    def __init__(self, ms, fn):
        self.ms, self.fn, self.id = ms, fn, 0

    def __call__(self, *_):
        if self.id:
            GLib.source_remove(self.id)
        self.id = GLib.timeout_add(self.ms, self._fire)

    def _fire(self):
        self.id = 0
        self.fn()
        return False


# ── pages ───────────────────────────────────────────────────────────────
class DesktopPage(Gtk.Box):
    """Every widget on the desktop, with its look and options."""

    def __init__(self, win):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.win = win
        self.page = Adw.PreferencesPage()
        self.append(self.page)
        self.page.set_vexpand(True)
        self.items = []
        self.groups = []
        self.save_later = Debounce(250, self._save)
        self.reload()

    def reload(self):
        self.items = load_instances()
        reg = {t["type"]: t for t in load_registry()}
        for g in self.groups:
            self.page.remove(g)
        self.groups = []

        top = Adw.PreferencesGroup(title="On your desktop",
                                   description="Changes apply as you make them. Drag widgets around with “Arrange” (or SUPER+SHIFT+W).")
        bar = Gtk.Box(spacing=6)
        arrange = Gtk.Button(label="Arrange")
        arrange.connect("clicked", lambda *_: qs_ipc("widgets", "edit"))
        peek = Gtk.Button(label="Show")
        peek.set_tooltip_text("Raise the widgets over your windows (SUPER+W)")
        peek.connect("clicked", lambda *_: qs_ipc("widgets", "peek"))
        add = Gtk.MenuButton(label="Add…")
        add.add_css_class("suggested-action")
        menu = Gio.Menu()
        for t in load_registry():
            menu.append(t.get("label", t["type"]), f"win.add-widget::{t['type']}")
        add.set_menu_model(menu)
        for b in (peek, arrange, add):
            bar.append(b)
        bar.set_valign(Gtk.Align.CENTER)
        top.set_header_suffix(bar)
        if not self.items:
            top.add(plain(Adw.ActionRow, title="No widgets yet", subtitle="Add one with “Add…”"))
        self.page.add(top)
        self.groups.append(top)

        for it in self.items:
            t = reg.get(it.get("type"), {})
            g = Adw.PreferencesGroup()
            ex = plain(Adw.ExpanderRow, title=t.get("label", it.get("type")),
                                 subtitle=f"{it.get('style', 'glass')} · {it.get('ax', '?')}/{it.get('ay', '?')} · ×{it.get('scale', 1)}")
            iid = it["id"]
            ex.add_row(combo_row("Style", STYLES, it.get("style", "glass"), lambda v, i=iid: self.set(i, "style", v),
                                 subtitle="frost = tinted glass over the wallpaper, bare = no background"))
            ex.add_row(spin_row("Size", it.get("scale", 1), 0.5, 3, 0.05, lambda v, i=iid: self.set(i, "scale", round(v, 2)), digits=2))
            ex.add_row(spin_row("Opacity", it.get("opacity", 1), 0.1, 1, 0.05, lambda v, i=iid: self.set(i, "opacity", round(v, 2)), digits=2))
            for r in option_rows(t.get("options", []), dict(it.get("opts") or {}), lambda k, v, i=iid: self.set_opt(i, k, v)):
                ex.add_row(r)
            acts = Gtk.Box(spacing=4)
            acts.append(icon_button("view-reveal-symbolic", "Preview this widget", lambda i=it: self.win.preview_instance(i)))
            acts.append(icon_button("edit-copy-symbolic", "Duplicate", lambda i=iid: self.duplicate(i)))
            acts.append(icon_button("user-trash-symbolic", "Remove from the desktop", lambda i=iid: self.remove(i), "error"))
            ex.add_suffix(acts)
            g.add(ex)
            self.page.add(g)
            self.groups.append(g)

    def find(self, iid):
        return next((x for x in self.items if x["id"] == iid), None)

    def set(self, iid, key, value):
        it = self.find(iid)
        if it is not None:
            it[key] = value
            self.save_later()

    def set_opt(self, iid, key, value):
        it = self.find(iid)
        if it is not None:
            it.setdefault("opts", {})[key] = value
            self.save_later()

    def _save(self):
        # merge into what is on disk: positions may have moved on the desktop meanwhile
        disk = {x["id"]: x for x in load_instances()}
        out = []
        for it in self.items:
            d = disk.get(it["id"])
            if d is None:
                continue
            for k in ("style", "scale", "opacity", "opts"):
                if k in it:
                    d[k] = it[k]
            out.append(d)
        known = {x["id"] for x in self.items}
        out += [x for i, x in disk.items() if i not in known]
        save_instances(out)

    def duplicate(self, iid):
        it = self.find(iid)
        if not it:
            return
        items = load_instances()
        c = copy.deepcopy(next((x for x in items if x["id"] == iid), it))
        c["id"] = max([x["id"] for x in items] + [0]) + 1
        c["x"] = c.get("x", 0) + 40
        c["y"] = c.get("y", 0) + 40
        items.append(c)
        save_instances(items)
        self.reload()
        self.win.toast("Duplicated")

    def remove(self, iid):
        items = [x for x in load_instances() if x["id"] != iid]
        save_instances(items)
        self.reload()
        self.win.toast("Removed from the desktop")


class TypePage(Gtk.Box):
    """A widget type: about, the options it offers, its code."""

    def __init__(self, win, tname):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.win, self.tname = win, tname
        reg = load_registry()
        self.info = copy.deepcopy(next((t for t in reg if t["type"] == tname), {"type": tname, "options": []}))
        self.qml_path = TYPES / f"{tname}.qml"
        stack = Adw.ViewStack()
        sw = Adw.ViewSwitcher(stack=stack, policy=Adw.ViewSwitcherPolicy.WIDE)
        sw.set_halign(Gtk.Align.CENTER)
        sw.set_margin_top(6)
        self.append(sw)
        self.append(stack)
        stack.set_vexpand(True)

        # about + options
        page = Adw.PreferencesPage()
        about = Adw.PreferencesGroup(title=GLib.markup_escape_text(self.info.get("label", tname)), description=GLib.markup_escape_text(self.info.get("description", "")))
        acts = Gtk.Box(spacing=6)
        b = Gtk.Button(label="Preview")
        b.connect("clicked", lambda *_: self.win.preview_type(tname))
        acts.append(b)
        b = Gtk.Button(label="Add to desktop")
        b.add_css_class("suggested-action")
        b.connect("clicked", lambda *_: self.win.add_widget(tname))
        acts.append(b)
        acts.set_valign(Gtk.Align.CENTER)
        about.set_header_suffix(acts)
        about.add(entry_row("Name in lists", self.info.get("label", tname), lambda v: self.info.__setitem__("label", v)))
        about.add(entry_row("Description", self.info.get("description", ""), lambda v: self.info.__setitem__("description", v)))
        dup = plain(Adw.ActionRow, title="Duplicate as a new type", subtitle="Copy this widget's code under a new name to change it freely")
        db = Gtk.Button(label="Duplicate…", valign=Gtk.Align.CENTER)
        db.connect("clicked", lambda *_: self.win.ask_name("Name for the copy", tname + "_copy", self.duplicate))
        dup.add_suffix(db)
        about.add(dup)
        if self.info.get("maker") or spec_path(tname).with_suffix(".json.detached").exists():
            rm = plain(Adw.ActionRow, title="Delete this widget type", subtitle="Removes its files and any copies on the desktop")
            rb = Gtk.Button(label="Delete", valign=Gtk.Align.CENTER)
            rb.add_css_class("destructive-action")
            rb.connect("clicked", lambda *_: self.win.delete_type(tname))
            rm.add_suffix(rb)
            about.add(rm)
        page.add(about)

        self.opt_group = Adw.PreferencesGroup(title="Options it offers",
                                              description="What appears in each copy's settings. Read them in QML with o(\"key\").")
        addb = Gtk.Button(label="Add option")
        addb.connect("clicked", lambda *_: self.add_option())
        addb.set_valign(Gtk.Align.CENTER)
        self.opt_group.set_header_suffix(addb)
        self.opt_rows = []
        page.add(self.opt_group)
        self.fill_options()
        save = Adw.PreferencesGroup()
        sb = Gtk.Button(label="Save type settings", halign=Gtk.Align.END)
        sb.add_css_class("suggested-action")
        sb.connect("clicked", lambda *_: self.save_info())
        save.add(sb)
        page.add(save)
        stack.add_titled_with_icon(page, "about", "Settings", "preferences-system-symbolic")

        # code
        stack.add_titled_with_icon(self.code_view(), "code", "Code", "text-x-script-symbolic")

    def fill_options(self):
        for r in self.opt_rows:
            self.opt_group.remove(r)
        self.opt_rows = []
        for i, o in enumerate(self.info.get("options", [])):
            ex = plain(Adw.ExpanderRow, title=o.get("label") or o.get("key"), subtitle=f"{o.get('key')} · {o.get('kind')} · default {json.dumps(o.get('default'), ensure_ascii=False)}")
            ex.add_row(entry_row("Key", o.get("key", ""), lambda v, o=o: o.__setitem__("key", v)))
            ex.add_row(entry_row("Label", o.get("label", ""), lambda v, o=o: o.__setitem__("label", v)))
            kinds = ["string", "int", "bool", "enum"]
            ex.add_row(combo_row("Kind", kinds, o.get("kind", "string"), lambda v, o=o: o.__setitem__("kind", v)))
            ex.add_row(entry_row("Default", json.dumps(o.get("default")) if not isinstance(o.get("default"), str) else o.get("default"),
                                 lambda v, o=o: o.__setitem__("default", self.parse_default(o, v))))
            if o.get("kind") == "int":
                ex.add_row(entry_row("Min / max", f"{o.get('min', 0)} {o.get('max', 100)}", lambda v, o=o: self.set_range(o, v)))
            if o.get("kind") == "enum":
                ex.add_row(entry_row("Choices (space separated)", " ".join(o.get("choices", [])),
                                     lambda v, o=o: o.__setitem__("choices", v.split())))
            ex.add_suffix(icon_button("user-trash-symbolic", "Remove option", lambda i=i: self.remove_option(i), "error"))
            self.opt_group.add(ex)
            self.opt_rows.append(ex)
        if not self.opt_rows:
            r = plain(Adw.ActionRow, title="No options")
            self.opt_group.add(r)
            self.opt_rows.append(r)

    @staticmethod
    def parse_default(o, v):
        k = o.get("kind")
        if k == "bool":
            return v.strip().lower() in ("true", "1", "yes", "on")
        if k == "int":
            try:
                return int(float(v))
            except ValueError:
                return 0
        return v

    @staticmethod
    def set_range(o, v):
        p = v.split()
        try:
            o["min"], o["max"], o["step"] = int(p[0]), int(p[1]), 1
        except (IndexError, ValueError):
            pass

    def add_option(self):
        self.info.setdefault("options", []).append({"key": f"opt{len(self.info['options']) + 1}", "label": "New option", "kind": "string", "default": ""})
        self.fill_options()

    def remove_option(self, i):
        del self.info["options"][i]
        self.fill_options()

    def save_info(self):
        reg = load_registry()
        for i, t in enumerate(reg):
            if t["type"] == self.tname:
                reg[i] = self.info
                break
        else:
            reg.append(self.info)
        save_registry(reg)
        self.win.toast("Saved. The shell picks up the new options right away")
        self.win.refresh_sidebar()

    def code_view(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        for m in ("top", "bottom", "start", "end"):
            getattr(box, f"set_margin_{m}")(10)
        bar = Gtk.Box(spacing=6)
        spec = spec_path(self.tname)
        lbl = Gtk.Label(xalign=0, hexpand=True, wrap=True)
        lbl.add_css_class("dim-label")
        lbl.set_text(str(self.qml_path.relative_to(REPO)) + ("  ·  made in the builder: saving from the builder overwrites this file" if spec.exists() else ""))
        bar.append(lbl)
        if spec.exists():
            det = Gtk.Button(label="Detach from builder")
            det.set_tooltip_text("Keep this code as yours; the builder will no longer open this widget")
            det.connect("clicked", lambda *_: self.detach())
            bar.append(det)
        pv = Gtk.Button(label="Preview")
        pv.connect("clicked", lambda *_: self.win.preview_source(self.tname, self.buf_text()))
        bar.append(pv)
        sv = Gtk.Button(label="Save")
        sv.add_css_class("suggested-action")
        sv.connect("clicked", lambda *_: self.save_code())
        bar.append(sv)
        box.append(bar)
        self.buf = Gtk.TextBuffer()
        try:
            self.buf.set_text(self.qml_path.read_text())
        except OSError:
            self.buf.set_text("")
        tv = Gtk.TextView(buffer=self.buf, monospace=True, wrap_mode=Gtk.WrapMode.NONE, top_margin=8, left_margin=8, bottom_margin=8)
        tv.add_css_class("card")
        sc = Gtk.ScrolledWindow(vexpand=True, child=tv)
        box.append(sc)
        self.live = Debounce(700, lambda: self.win.preview_source(self.tname, self.buf_text()) if self.win.preview.running else None)
        self.buf.connect("changed", self.live)
        return box

    def buf_text(self):
        return self.buf.get_text(self.buf.get_start_iter(), self.buf.get_end_iter(), False)

    def save_code(self):
        write_atomic(self.qml_path, self.buf_text())
        self.win.toast("Saved. Widgets of this type on the desktop reload")

    def detach(self):
        p = spec_path(self.tname)
        if p.exists():
            p.rename(p.with_suffix(".json.detached"))
        self.win.toast("Detached: this widget is plain QML now")
        self.win.refresh_sidebar(select=f"type:{self.tname}")

    def duplicate(self, new):
        if not gen.NAME_RE.match(new) or (TYPES / f"{new}.qml").exists():
            self.win.toast("Pick another name: lowercase letters, digits and _, not taken")
            return
        shutil.copy(self.qml_path, TYPES / f"{new}.qml")
        sp = spec_path(self.tname)
        if sp.exists():
            s = load_json(sp, {})
            s["name"] = new
            s["label"] = (s.get("label") or new) + " copy"
            write_atomic(spec_path(new), dump(s))
        info = copy.deepcopy(self.info)
        info["type"] = new
        info["label"] = self.info.get("label", self.tname) + " copy"
        info["maker"] = True
        reg = load_registry()
        reg.append(info)
        save_registry(reg)
        self.win.toast(f"Created “{new}”")
        self.win.refresh_sidebar(select=f"maker:{new}" if sp.exists() else f"type:{new}")


class BuilderPage(Gtk.Box):
    """Make a widget from data sources and blocks; generates the QML."""

    def __init__(self, win, spec, is_new):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.win, self.spec, self.is_new = win, spec, is_new
        self.page = Adw.PreferencesPage()
        self.page.set_vexpand(True)
        self.append(self.page)
        self.live = Debounce(450, self.update_preview)
        self.groups = []
        self.build()

    # every edit goes through here
    def changed(self, rebuild=False):
        if rebuild:
            GLib.idle_add(lambda: (self.build(), False)[1])
        self.live()

    def build(self):
        for g in self.groups:
            self.page.remove(g)
        self.groups = []
        s = self.spec

        # about
        g = Adw.PreferencesGroup(title="Widget", description="Text fields take {id} for a data source's value, {id:1} for a rounded number, {opt.key} for an option.")
        acts = Gtk.Box(spacing=6)
        pv = Gtk.ToggleButton(label="Live preview", active=self.win.preview.running)
        pv.connect("toggled", lambda b: self.update_preview() if b.get_active() else self.win.preview.stop())
        acts.append(pv)
        sv = Gtk.Button(label="Save")
        sv.add_css_class("suggested-action")
        sv.connect("clicked", lambda *_: self.save())
        acts.append(sv)
        acts.set_valign(Gtk.Align.CENTER)
        g.set_header_suffix(acts)
        name = entry_row("Type name (for files)", s["name"], lambda v: (s.__setitem__("name", v.strip()), self.changed()))
        name.set_editable(self.is_new)
        if not self.is_new:
            name.set_tooltip_text("Duplicate the widget to use another name")
        g.add(name)
        g.add(entry_row("Name in lists", s.get("label", ""), lambda v: (s.__setitem__("label", v), self.changed())))
        g.add(entry_row("Description", s.get("description", ""), lambda v: (s.__setitem__("description", v), self.changed())))
        g.add(spin_row("Width", s.get("width", 260), 120, 900, 10, lambda v: (s.__setitem__("width", v), self.changed()),
                       subtitle="Content width in px before the desktop's scale"))
        g.add(entry_row("Corner label", s.get("corner", ""), lambda v: (s.__setitem__("corner", v), self.changed()),
                        tooltip="Small text in the bottom-right corner, e.g. {city} or {up}"))
        self.status = plain(Adw.ActionRow, title="Ready", subtitle="")
        self.status.add_css_class("property")
        g.add(self.status)
        self.add_group(g)

        # data
        g = Adw.PreferencesGroup(title="Data", description="Where the numbers and text come from. Each gets an id to use in the blocks.")
        add = Gtk.MenuButton(label="Add data…")
        m = Gio.Menu()
        m.append("Sensor (CPU, RAM, GPU, battery, network, weather, music, time…)", "win.add-source::sensor")
        m.append("Shell command (output, refreshed on a timer)", "win.add-source::command")
        m.append("Text file (watched)", "win.add-source::file")
        add.set_menu_model(m)
        add.set_valign(Gtk.Align.CENTER)
        g.set_header_suffix(add)
        sensors = list(gen.SENSORS)
        for i, src in enumerate(s["sources"]):
            kind = src.get("kind")
            sub = {"sensor": gen.SENSORS.get(src.get("sensor"), ("", "pick a sensor"))[1], "command": src.get("command", ""), "file": src.get("path", "")}.get(kind, "")
            ex = plain(Adw.ExpanderRow, title=f"{{{src.get('id')}}}  ·  {kind}", subtitle=sub[:80])
            ex.add_row(entry_row("Id", src.get("id", ""), lambda v, src=src: (src.__setitem__("id", v.strip()), self.changed())))
            if kind == "sensor":
                ex.add_row(combo_row("Sensor", sensors, src.get("sensor", "cpu"), lambda v, src=src: (src.__setitem__("sensor", v), self.changed(True)),
                                     labels=[f"{k}  —  {gen.SENSORS[k][1]}" for k in sensors]))
            elif kind == "command":
                ex.add_row(entry_row("Command", src.get("command", ""), lambda v, src=src: (src.__setitem__("command", v), self.changed()),
                                     tooltip="Runs with sh -c; its output (trimmed) is the value"))
                ex.add_row(spin_row("Every (seconds)", src.get("interval", 5), 1, 86400, 1, lambda v, src=src: (src.__setitem__("interval", v), self.changed())))
                test = plain(Adw.ActionRow, title="Test the command")
                tb = Gtk.Button(label="Run", valign=Gtk.Align.CENTER)
                tb.connect("clicked", lambda *_b, src=src, row=test: self.test_command(src, row))
                test.add_suffix(tb)
                ex.add_row(test)
            elif kind == "file":
                ex.add_row(entry_row("File", src.get("path", ""), lambda v, src=src: (src.__setitem__("path", v), self.changed())))
            ex.add_suffix(self.move_buttons(s["sources"], i))
            g.add(ex)
        if not s["sources"]:
            g.add(plain(Adw.ActionRow, title="No data yet", subtitle="Text-only widgets don't need any"))
        self.add_group(g)

        # blocks
        g = Adw.PreferencesGroup(title="Layout", description="Blocks, top to bottom.")
        add = Gtk.MenuButton(label="Add block…")
        m = Gio.Menu()
        for k, label in gen.BLOCKS.items():
            m.append(label, f"win.add-block::{k}")
        add.set_menu_model(m)
        add.set_valign(Gtk.Align.CENTER)
        g.set_header_suffix(add)
        ids = [x.get("id") for x in s["sources"]]
        colors = list(gen.COLORS)
        for i, b in enumerate(s["blocks"]):
            k = b.get("kind")
            summary = b.get("text") or b.get("value") or b.get("label") or b.get("source") or ""
            ex = plain(Adw.ExpanderRow, title=gen.BLOCKS.get(k, k), subtitle=str(summary)[:80])
            ch = lambda key, b=b, rebuild=False: (lambda v: (b.__setitem__(key, v), self.changed(rebuild)))
            if k in ("big", "text"):
                ex.add_row(entry_row("Text", b.get("text", ""), ch("text")))
                ex.add_row(spin_row("Size", b.get("size", 13), 8, 160, 1, ch("size")))
                ex.add_row(combo_row("Colour", colors, b.get("color", "fg"), ch("color")))
                ex.add_row(combo_row("Align", ["left", "center", "right"], b.get("align", "left"), ch("align")))
                if k == "text":
                    ex.add_row(switch_row("Bold", b.get("bold", False), ch("bold")))
            elif k == "stat":
                ex.add_row(entry_row("Label", b.get("label", ""), ch("label")))
                ex.add_row(entry_row("Value", b.get("value", ""), ch("value")))
                ex.add_row(combo_row("Graph of", [""] + ids, b.get("graph", ""), ch("graph"), labels=["no graph"] + ids))
                ex.add_row(entry_row("Graph range (min max)", f"{b.get('min', 0)} {b.get('max', 100)}", lambda v, b=b: (self.set_range(b, v), self.changed())))
            elif k == "bar":
                ex.add_row(entry_row("Label", b.get("label", ""), ch("label")))
                ex.add_row(entry_row("Value text", b.get("value", ""), ch("value")))
                ex.add_row(combo_row("Fill from", ids or [""], b.get("source", ""), ch("source")))
                ex.add_row(entry_row("Range (min max)", f"{b.get('min', 0)} {b.get('max', 100)}", lambda v, b=b: (self.set_range(b, v), self.changed())))
            elif k == "graph":
                ex.add_row(combo_row("Graph of", ids or [""], b.get("source", ""), ch("source")))
                ex.add_row(entry_row("Range (min max)", f"{b.get('min', 0)} {b.get('max', 100)}", lambda v, b=b: (self.set_range(b, v), self.changed())))
                ex.add_row(spin_row("Height", b.get("height", 40), 12, 300, 2, ch("height")))
                ex.add_row(combo_row("Colour", colors, b.get("color", "a1"), ch("color")))
            elif k == "lines":
                ex.add_row(combo_row("Show", ids or [""], b.get("source", ""), ch("source")))
                ex.add_row(spin_row("Lines at most", b.get("max", 8), 1, 60, 1, ch("max")))
                ex.add_row(spin_row("Size", b.get("size", 12), 8, 40, 1, ch("size")))
                ex.add_row(combo_row("Colour", colors, b.get("color", "fg"), ch("color")))
            elif k == "button":
                ex.add_row(entry_row("Text", b.get("text", ""), ch("text")))
                ex.add_row(entry_row("Command", b.get("command", ""), ch("command")))
            elif k == "spacer":
                ex.add_row(spin_row("Height", b.get("height", 8), 1, 200, 1, ch("height")))
            ex.add_suffix(self.move_buttons(s["blocks"], i))
            g.add(ex)
        if not s["blocks"]:
            g.add(plain(Adw.ActionRow, title="Empty", subtitle="Add a block to start"))
        self.add_group(g)

        # options
        g = Adw.PreferencesGroup(title="Options", description="Settings each copy of the widget gets on the desktop page. Use them as {opt.key} in text, commands and file paths.")
        ab = Gtk.Button(label="Add option")
        ab.connect("clicked", lambda *_: (s["options"].append({"key": f"opt{len(s['options']) + 1}", "label": "Option", "kind": "string", "default": ""}), self.changed(True)))
        ab.set_valign(Gtk.Align.CENTER)
        g.set_header_suffix(ab)
        for i, o in enumerate(s["options"]):
            ex = plain(Adw.ExpanderRow, title=o.get("label") or o.get("key"), subtitle=f"{{opt.{o.get('key')}}}")
            ex.add_row(entry_row("Key", o.get("key", ""), lambda v, o=o: (o.__setitem__("key", v.strip()), self.changed())))
            ex.add_row(entry_row("Label", o.get("label", ""), lambda v, o=o: (o.__setitem__("label", v), self.changed())))
            ex.add_row(combo_row("Kind", ["string", "int", "bool"], o.get("kind", "string"), lambda v, o=o: (o.__setitem__("kind", v), self.changed(True))))
            ex.add_row(entry_row("Default", str(o.get("default", "")), lambda v, o=o: (o.__setitem__("default", TypePage.parse_default(o, v)), self.changed())))
            ex.add_suffix(self.move_buttons(s["options"], i))
            g.add(ex)
        self.add_group(g)

        # generated code (read only)
        g = Adw.PreferencesGroup(title="Generated QML", description="Read only here. To hand-edit, save, then open the type's Code tab and detach it from the builder.")
        self.code = Gtk.TextView(monospace=True, editable=False, wrap_mode=Gtk.WrapMode.NONE, top_margin=8, left_margin=8, bottom_margin=8)
        self.code.add_css_class("card")
        sc = Gtk.ScrolledWindow(child=self.code, min_content_height=220, max_content_height=420, propagate_natural_height=True)
        exp = Gtk.Expander(label="Show code", child=sc)
        g.add(exp)
        self.add_group(g)
        self.refresh_code()

    def add_group(self, g):
        self.page.add(g)
        self.groups.append(g)

    def move_buttons(self, lst, i):
        box = Gtk.Box(spacing=0)
        up = icon_button("go-up-symbolic", "Move up", lambda: self.move(lst, i, -1))
        up.set_sensitive(i > 0)
        dn = icon_button("go-down-symbolic", "Move down", lambda: self.move(lst, i, 1))
        dn.set_sensitive(i < len(lst) - 1)
        rm = icon_button("user-trash-symbolic", "Remove", lambda: (lst.pop(i), self.changed(True)), "error")
        for b in (up, dn, rm):
            box.append(b)
        return box

    def move(self, lst, i, d):
        j = i + d
        if 0 <= j < len(lst):
            lst[i], lst[j] = lst[j], lst[i]
            self.changed(True)

    @staticmethod
    def set_range(b, v):
        p = v.split()
        try:
            b["min"], b["max"] = float(p[0]), float(p[1])
        except (IndexError, ValueError):
            pass

    def add_source(self, kind):
        ids = {x.get("id") for x in self.spec["sources"]}
        base = {"sensor": "cpu", "command": "cmd", "file": "file"}[kind]
        sid, n = base, 2
        while sid in ids:
            sid, n = f"{base}{n}", n + 1
        src = {"id": sid, "kind": kind}
        if kind == "sensor":
            src["sensor"] = "cpu"
        elif kind == "command":
            src.update({"command": "uptime -p", "interval": 30})
        else:
            src["path"] = "~/notes.md"
        self.spec["sources"].append(src)
        self.changed(True)

    def add_block(self, kind):
        b = {"kind": kind, **copy.deepcopy(gen.BLOCK_DEFAULTS.get(kind, {}))}
        ids = [x.get("id") for x in self.spec["sources"]]
        if ids:
            for k in ("source", "graph"):
                if k in b and b[k] not in ids and (kind != "stat" or b[k]):
                    b[k] = ids[0]
        self.spec["blocks"].append(b)
        self.changed(True)

    def test_command(self, src, row):
        try:
            r = subprocess.run(["sh", "-c", src.get("command", "")], capture_output=True, text=True, timeout=10)
            out = (r.stdout.strip() or r.stderr.strip() or "(no output)").splitlines()
            row.set_subtitle(" ⏎ ".join(out[:3])[:200] + ("" if r.returncode == 0 else f"  (exit {r.returncode})"))
        except subprocess.TimeoutExpired:
            row.set_subtitle("took longer than 10 s")

    def refresh_code(self):
        try:
            self.code.get_buffer().set_text(gen.generate(self.spec))
        except Exception as e:  # noqa: BLE001 - shown to the user
            self.code.get_buffer().set_text(f"// cannot generate: {e}")

    def problems(self):
        errs = gen.validate(self.spec)
        ids = {x.get("id") for x in self.spec["sources"]}
        missing = sorted(gen.used_tokens(self.spec) - ids - {""})
        if missing:
            errs.append("Unknown data: " + ", ".join("{" + m + "}" for m in missing) + " (add a source with that id)")
        return errs

    def update_preview(self):
        self.refresh_code()
        errs = self.problems()
        self.status.set_title("Check these" if errs else "Ready")
        self.status.set_subtitle("\n".join(errs))
        if not self.win.preview_wanted:
            return
        src = self.win.preview.draft(gen.generate(self.spec))
        opts = {o["key"]: o.get("default") for o in self.spec.get("options", [])}
        self.win.show_preview({"type": self.spec["name"], "style": self.win.preview_style, "opts": opts, "source": src}, self.status)

    def save(self):
        errs = gen.validate(self.spec)
        if errs:
            self.win.toast(errs[0])
            return
        name = self.spec["name"]
        if self.is_new and ((TYPES / f"{name}.qml").exists() or any(t["type"] == name for t in load_registry())):
            self.win.toast(f"“{name}” is taken; pick another type name")
            return
        write_atomic(TYPES / f"{name}.qml", gen.generate(self.spec))
        write_atomic(spec_path(name), dump(self.spec))
        reg = load_registry()
        entry = gen.registry_entry(self.spec)
        for i, t in enumerate(reg):
            if t["type"] == name:
                reg[i] = entry
                break
        else:
            reg.append(entry)
        save_registry(reg)
        was_new = self.is_new
        self.is_new = False
        self.win.toast(f"Saved “{self.spec.get('label') or name}”" + (". Add it from the Desktop page or here" if was_new else ""),
                       action=("Add to desktop", lambda: self.win.add_widget(name)))
        if was_new:
            self.win.refresh_sidebar(select=f"maker:{name}")


# ── window ──────────────────────────────────────────────────────────────
class Window(Adw.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Widget maker", default_width=1080, default_height=760)
        self.preview = Preview()
        self.preview_wanted = False
        self.preview_style = "frost"
        self.current = None
        self.connect("close-request", lambda *_: (self.preview.stop(), False)[1])

        for name, cb in (("add-widget", self.on_add_widget), ("add-source", self.on_add_source), ("add-block", self.on_add_block)):
            a = Gio.SimpleAction.new(name, GLib.VariantType.new("s"))
            a.connect("activate", cb)
            self.add_action(a)

        self.toasts = Adw.ToastOverlay()
        split = Adw.NavigationSplitView(min_sidebar_width=230, max_sidebar_width=280)
        self.toasts.set_child(split)
        self.set_content(self.toasts)

        # sidebar
        sb_view = Adw.ToolbarView()
        sb_head = Adw.HeaderBar()
        newb = Gtk.Button(icon_name="list-add-symbolic", tooltip_text="New widget")
        newb.connect("clicked", lambda *_: self.new_widget())
        sb_head.pack_start(newb)
        sb_view.add_top_bar(sb_head)
        self.sidebar = Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE)
        self.sidebar.add_css_class("navigation-sidebar")
        self.sidebar.connect("row-selected", self.on_select)
        sb_view.set_content(Gtk.ScrolledWindow(child=self.sidebar, vexpand=True))
        split.set_sidebar(Adw.NavigationPage(title="Widgets", child=sb_view))

        # content
        self.content_view = Adw.ToolbarView()
        head = Adw.HeaderBar()
        self.style_dd = Gtk.DropDown.new_from_strings(STYLES)
        self.style_dd.set_tooltip_text("Style used in the preview")
        self.style_dd.connect("notify::selected", self.on_preview_style)
        head.pack_end(self.style_dd)
        lbl = Gtk.Label(label="Preview style")
        lbl.add_css_class("dim-label")
        head.pack_end(lbl)
        self.content_view.add_top_bar(head)
        self.content_page = Adw.NavigationPage(title="", child=self.content_view)
        split.set_content(self.content_page)

        self.refresh_sidebar(select="desktop")
        GLib.timeout_add(1500, self.poll_errors)
        self.err_since = 0
        self.err_row = None

    # sidebar
    def refresh_sidebar(self, select=None):
        keep = select or (self.current_key if self.current else "desktop")
        while (r := self.sidebar.get_row_at_index(0)) is not None:
            self.sidebar.remove(r)
        reg = load_registry()

        def header(text):
            r = Gtk.ListBoxRow(selectable=False, activatable=False)
            l = Gtk.Label(label=text, xalign=0, margin_top=12, margin_start=8)
            l.add_css_class("heading")
            l.add_css_class("dim-label")
            r.set_child(l)
            self.sidebar.append(r)

        def item(key, title, icon, sub=None):
            r = Gtk.ListBoxRow()
            r.key = key
            b = Gtk.Box(spacing=10, margin_top=4, margin_bottom=4, margin_start=4)
            b.append(Gtk.Image(icon_name=icon))
            l = Gtk.Label(label=title, xalign=0, ellipsize=Pango.EllipsizeMode.END, hexpand=True)
            b.append(l)
            if sub:
                s = Gtk.Label(label=sub)
                s.add_css_class("dim-label")
                s.add_css_class("caption")
                b.append(s)
            r.set_child(b)
            self.sidebar.append(r)
            return r

        rows = {}
        rows["desktop"] = item("desktop", "On your desktop", "user-desktop-symbolic", str(len(load_instances())))
        mine = [t for t in reg if spec_path(t["type"]).exists()]
        header("Made by you")
        for t in mine:
            rows[f"maker:{t['type']}"] = item(f"maker:{t['type']}", t.get("label", t["type"]), "applications-graphics-symbolic")
        rows["new"] = item("new", "New widget…", "list-add-symbolic")
        header("Widget types")
        for t in reg:
            if t in mine:
                continue
            rows[f"type:{t['type']}"] = item(f"type:{t['type']}", t.get("label", t["type"]), "text-x-script-symbolic",
                                             "yours" if t.get("maker") else None)
        target = rows.get(keep) or rows["desktop"]
        self.sidebar.select_row(target)

    def on_select(self, _lb, row):
        if row is None or not hasattr(row, "key"):
            return
        key = row.key
        if key == "new":
            self.new_widget()
            return
        self.current_key = key
        if key == "desktop":
            self.show_page(DesktopPage(self), "On your desktop")
        elif key.startswith("maker:"):
            name = key.split(":", 1)[1]
            spec = load_json(spec_path(name), None)
            if spec is None:
                self.show_page(TypePage(self, name), name)
            else:
                spec["name"] = name
                for k, d in gen.new_spec(name).items():
                    spec.setdefault(k, d)
                self.show_page(BuilderPage(self, spec, False), spec.get("label") or name)
        elif key.startswith("type:"):
            name = key.split(":", 1)[1]
            self.show_page(TypePage(self, name), name)

    def show_page(self, widget, title):
        self.current = widget
        self.content_view.set_content(widget)
        self.content_page.set_title(title)
        if isinstance(widget, BuilderPage) and self.preview_wanted:
            widget.update_preview()

    def new_widget(self):
        taken = {t["type"] for t in load_registry()}
        n, name = 1, "my_widget"
        while name in taken or (TYPES / f"{name}.qml").exists():
            n += 1
            name = f"my_widget{n}"
        self.current_key = "new"
        self.show_page(BuilderPage(self, gen.new_spec(name), True), "New widget")
        self.preview_wanted = True
        self.current.update_preview()

    # actions
    def on_add_widget(self, _a, param):
        self.add_widget(param.get_string())

    def add_widget(self, tname):
        r = qs_ipc("widgets", "add", tname)
        if not r:
            # shell not answering: add it to the file directly
            items = load_instances()
            items.append({"id": max([x["id"] for x in items] + [0]) + 1, "type": tname, "ax": "center", "x": 0, "ay": "center", "y": 0,
                          "style": "frost", "opacity": 1, "scale": 1, "opts": {}})
            save_instances(items)
        self.toast("Added to the desktop (centre of the screen). Arrange to move it",
                   action=("Arrange", lambda: qs_ipc("widgets", "edit")))
        if isinstance(self.current, DesktopPage):
            GLib.timeout_add(400, lambda: (self.current.reload(), False)[1])

    def on_add_source(self, _a, param):
        if isinstance(self.current, BuilderPage):
            self.current.add_source(param.get_string())

    def on_add_block(self, _a, param):
        if isinstance(self.current, BuilderPage):
            self.current.add_block(param.get_string())

    def on_preview_style(self, dd, _p):
        self.preview_style = STYLES[dd.get_selected()]
        if self.preview.running:
            try:
                spec = json.loads(SPEC_FILE.read_text())
                spec["style"] = self.preview_style
                self.preview.show(spec)
            except (OSError, ValueError):
                pass

    # preview
    def show_preview(self, spec, status_row=None):
        self.preview_wanted = True
        self.err_since = self.preview.log_size()
        self.err_row = status_row
        self.preview.show(spec)

    def preview_type(self, tname):
        self.show_preview({"type": tname, "style": self.preview_style})

    def preview_source(self, tname, qml):
        self.show_preview({"type": tname, "style": self.preview_style, "source": self.preview.draft(qml)})

    def preview_instance(self, it):
        self.show_preview({"type": it["type"], "style": it.get("style", "frost"), "opts": it.get("opts", {}), "w": it.get("w", 0),
                           "h": it.get("h", 0), "scale": 1})

    def poll_errors(self):
        if self.preview.running and self.err_row is not None:
            errs = self.preview.errors(self.err_since)
            if errs:
                self.err_row.set_title("Preview reports")
                self.err_row.set_subtitle("\n".join(errs))
        elif self.preview_wanted and not self.preview.running and self.preview.proc is not None:
            self.preview.proc = None
            self.preview_wanted = False
        return True

    # misc
    def toast(self, text, action=None):
        t = Adw.Toast(title=GLib.markup_escape_text(text), timeout=4)
        if action:
            t.set_button_label(action[0])
            t.connect("button-clicked", lambda *_: action[1]())
        self.toasts.add_toast(t)

    def ask_name(self, heading, default, cb):
        d = Adw.AlertDialog(heading=heading, body="Lowercase letters, digits and _.")
        e = Gtk.Entry(text=default, activates_default=True)
        d.set_extra_child(e)
        d.add_response("cancel", "Cancel")
        d.add_response("ok", "Create")
        d.set_response_appearance("ok", Adw.ResponseAppearance.SUGGESTED)
        d.set_default_response("ok")
        d.connect("response", lambda _d, r: cb(e.get_text().strip()) if r == "ok" else None)
        d.present(self)

    def delete_type(self, tname):
        n = sum(1 for x in load_instances() if x.get("type") == tname)
        d = Adw.AlertDialog(heading=f"Delete “{tname}”?",
                            body="Its QML and builder files are deleted" + (f", and the {n} cop{'y' if n == 1 else 'ies'} on the desktop removed." if n else "."))
        d.add_response("cancel", "Cancel")
        d.add_response("delete", "Delete")
        d.set_response_appearance("delete", Adw.ResponseAppearance.DESTRUCTIVE)

        def go(_d, r):
            if r != "delete":
                return
            save_instances([x for x in load_instances() if x.get("type") != tname])
            save_registry([t for t in load_registry() if t["type"] != tname])
            for p in (TYPES / f"{tname}.qml", spec_path(tname)):
                try:
                    p.unlink()
                except OSError:
                    pass
            self.toast(f"Deleted “{tname}”")
            self.refresh_sidebar(select="desktop")
        d.connect("response", go)
        d.present(self)


def selftest(win, outdir):
    """SIGIL_WIDGETS_SELFTEST=dir: render each kind of page to PNGs, then quit (for development)."""
    os.makedirs(outdir, exist_ok=True)
    win.set_default_size(1080, 1900)
    keys = ["desktop", "type:perf", "new"]
    def shot(name):
        w = win.get_content()
        paintable = Gtk.WidgetPaintable.new(w)
        snap = Gtk.Snapshot()
        paintable.snapshot(snap, w.get_width(), w.get_height())
        node = snap.to_node()
        if node is not None:
            win.get_renderer().render_texture(node, None).save_to_png(os.path.join(outdir, name + ".png"))
    def step(i=[0]):
        if i[0] > 0:
            shot(keys[i[0] - 1].replace(":", "_"))
        if i[0] >= len(keys):
            win.preview.stop()
            win.get_application().quit()
            return False
        k = keys[i[0]]
        if k == "new":
            win.new_widget()
            win.preview.stop()
            win.preview_wanted = False
        else:
            for j in range(100):
                r = win.sidebar.get_row_at_index(j)
                if r is None:
                    break
                if getattr(r, "key", None) == k:
                    win.sidebar.select_row(r)
        i[0] += 1
        return True
    GLib.timeout_add(1200, step)


class App(Adw.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.DEFAULT_FLAGS)
        self.win = None

    def do_activate(self):
        if self.win is None:
            self.win = Window(self)
        self.win.present()
        if os.environ.get("SIGIL_WIDGETS_SELFTEST"):
            selftest(self.win, os.environ["SIGIL_WIDGETS_SELFTEST"])

    def do_shutdown(self):
        if self.win:
            self.win.preview.stop()
        Adw.Application.do_shutdown(self)


def main():
    return App().run(sys.argv[:1])
