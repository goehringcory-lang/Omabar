#!/usr/bin/env python3
"""Build Omabar's Bar.qml from Omarchy's built-in bar.

Omabar is the stock Omarchy bar engine (so every built-in widget, panel,
drag-and-drop and theme hook keeps working) drawn as a floating glass pill.
This script reads `$OMARCHY_PATH/shell/plugins/bar/{Bar.qml,BarModel.js}`,
applies a handful of small, anchored edits, and writes OmabarEngine.qml and
BarModel.js to the output directory. bin/omabar-setup runs it against the
Omarchy installed on the machine, into engine/, which Bar.qml loads. Each edit must match exactly
once, so an Omarchy update that moves the code fails loudly instead of
producing a half-patched bar.

    tools/omabar-patch.py <omarchy bar dir> <output dir>
"""
import pathlib
import shutil
import sys

PATCHES = [
    (
        "pill size and spacing",
        "  readonly property int barSize: vertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal\n",
        """  readonly property int barSize: vertical ? Math.max(Style.bar.sizeVertical, Style.space(34)) : Math.max(Style.bar.sizeHorizontal, Style.space(34))

  // ── Omabar ─────────────────────────────────────────────────────────────
  // The bar floats as a glass pill. omabarGap is the space between the pill and
  // the screen edge it hangs from; omabarInset is its distance from the two
  // side edges. Toasts, panels and tiled windows clear both (screenBarSizes).
  readonly property int omabarGap: Style.space(7)
  readonly property int omabarInset: Style.space(12)
  // Light themes get a whiter sheen, dark themes a quieter one.
  readonly property bool omabarLightTheme: (0.2126 * background.r + 0.7152 * background.g + 0.0722 * background.b) > 0.55
""",
    ),
    (
        "published thickness includes the float gap",
        "    for (var i = 0; i < screens.length; i++) sizes[screens[i].name] = root.thicknessFor(screens[i])\n",
        "    for (var i = 0; i < screens.length; i++) sizes[screens[i].name] = root.thicknessFor(screens[i]) + root.omabarGap\n",
    ),
    (
        "reserve room for the gap",
        "    exclusiveZone: thickness\n",
        "    exclusiveZone: thickness + root.omabarGap\n",
    ),
    (
        "float the strip off the edge",
        """      x: root.position === "right" ? parent.width - barWindow.thickness : 0
      y: root.position === "bottom" ? parent.height - barWindow.thickness : 0
      width: root.vertical ? barWindow.thickness : parent.width
      height: root.vertical ? parent.height : barWindow.thickness
""",
        """      x: root.vertical ? (root.position === "right" ? parent.width - barWindow.thickness - root.omabarGap : root.omabarGap) : root.omabarInset
      y: root.vertical ? root.omabarInset : (root.position === "bottom" ? parent.height - barWindow.thickness - root.omabarGap : root.omabarGap)
      width: root.vertical ? barWindow.thickness : Math.max(0, parent.width - root.omabarInset * 2)
      height: root.vertical ? Math.max(0, parent.height - root.omabarInset * 2) : barWindow.thickness
""",
    ),
    (
        "glass pill surface",
        """      Rectangle {
        anchors.fill: parent
        color: root.transparent ? "transparent" : (root.glassy ? root.glassBackground : root.background)
      }
""",
        """      // Omabar: a flattened glass oval. Every color comes from the active
      // theme, so it follows theme switches with the rest of the shell.
      Item {
        id: omabarPill
        anchors.fill: parent

        readonly property real radius: Math.min(width, height) / 2
        // Opaque, glassy and clear map to how much of the theme background
        // fills the glass; Hyprland blurs what is behind a glassy bar.
        property real fillAlpha: root.transparent ? 0.0 : (root.glassy ? 0.48 : 0.9)
        readonly property color edge: root.omabarLightTheme ? Qt.rgba(0, 0, 0, 0.10) : Qt.rgba(1, 1, 1, 0.10)
        Behavior on fillAlpha { NumberAnimation { duration: Style.duration(250); easing.type: Easing.OutCubic } }

        RectangularShadow {
          anchors.fill: glass
          radius: glass.radius
          offset.y: Style.space(3)
          blur: Style.space(16)
          spread: -Style.space(2)
          color: Qt.rgba(0, 0, 0, root.transparent ? 0.0 : (root.omabarLightTheme ? 0.14 : 0.32))
        }

        Rectangle {
          id: glass
          anchors.fill: parent
          radius: omabarPill.radius
          color: Qt.rgba(root.background.r, root.background.g, root.background.b, omabarPill.fillAlpha)
          border.width: 1
          border.color: omabarPill.edge
        }

        // A soft sheen across the top half, like light on curved glass.
        Rectangle {
          anchors.fill: parent
          anchors.margins: 1
          radius: Math.max(0, omabarPill.radius - 1)
          gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, root.omabarLightTheme ? 0.45 : 0.09) }
            GradientStop { position: 0.48; color: Qt.rgba(1, 1, 1, root.omabarLightTheme ? 0.10 : 0.02) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
          }
        }

        // A hairline of accent light along the bottom lip.
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 1
          visible: !root.vertical && !root.transparent
          width: parent.width * 0.42
          height: 1
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.35) }
            GradientStop { position: 1.0; color: "transparent" }
          }
        }
      }
""",
    ),
    (
        "keep left widgets clear of the rounded end",
        "          anchors.leftMargin: Style.space(8)\n",
        "          anchors.leftMargin: Math.round(root.barSize * 0.42)\n",
    ),
    (
        "keep right widgets clear of the rounded end",
        "          anchors.rightMargin: Style.space(8)\n",
        "          anchors.rightMargin: Math.round(root.barSize * 0.42)\n",
    ),
    (
        "vertical: top end",
        "          anchors.topMargin: Style.space(8)\n",
        "          anchors.topMargin: Math.round(root.barSize * 0.42)\n",
    ),
    (
        "vertical: bottom end",
        "          anchors.bottomMargin: Style.space(8)\n",
        "          anchors.bottomMargin: Math.round(root.barSize * 0.42)\n",
    ),
    (
        "Omabar's own modules get the bar itself",
        # Custom modules normally get a sandboxed PluginBarApi, which can't see
        # the bar's widgets. Omabar's drawer must, to open the panels of the
        # widgets it holds, so modules shipped in this plugin get the bar.
        """      if ("bar" in target) target.bar = firstParty
        ? root : root.pluginBarApiFor(pluginApiId, moduleName, registered)
""",
        """      var omabarOwn = qmlCustom && String(entry && entry.source || "").indexOf("/goehringcory.omabar/modules/") !== -1
      if ("bar" in target) target.bar = (firstParty || omabarOwn)
        ? root : root.pluginBarApiFor(pluginApiId, moduleName, registered)
""",
    ),
]

HEADER = """// Omabar — generated by tools/omabar-patch.py from Omarchy's built-in bar
// (shell/plugins/bar/Bar.qml, MIT, Copyright (c) David Heinemeier Hansson).
// Do not edit by hand: change tools/omabar-patch.py and run bin/omabar-setup.
"""


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    src = pathlib.Path(sys.argv[1])
    out = pathlib.Path(sys.argv[2])
    text = (src / "Bar.qml").read_text()
    failed = []
    for name, old, new in PATCHES:
        count = text.count(old)
        if count != 1:
            failed.append(f"  {name}: expected 1 match, found {count}")
            continue
        text = text.replace(old, new)
    if failed:
        print("omabar-patch: this Omarchy bar has changed; patches need updating:", file=sys.stderr)
        print("\n".join(failed), file=sys.stderr)
        return 1
    out.mkdir(parents=True, exist_ok=True)
    (out / "OmabarEngine.qml").write_text(HEADER + text)
    shutil.copyfile(src / "BarModel.js", out / "BarModel.js")
    print(f"omabar-patch: wrote {out / 'OmabarEngine.qml'} ({len(PATCHES)} edits)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
