import QtQuick

// Label for desktop widgets. Widgets can be scaled; hinted (native) glyphs are rasterised
// at the base size and go soft when scaled, curve-rendered glyphs stay sharp at any size.
Label {
    renderType: Text.CurveRendering
}
