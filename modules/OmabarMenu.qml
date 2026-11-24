// Omabar menu button: the Omarchy logo on a bright tile in the theme's accent
// color, with a soft glow of the same color. Click opens the Omarchy menu;
// right-click opens a terminal, like the built-in button.
//
// In Focus mode (bin/omabar-focus) a ring traces the tile, read like a clock
// hand sweeping clockwise from the top: during a focus round the ring starts
// full and the hand eats it away, so what is left is the time left; during a
// break the hand draws it back in a quieter color. It moves in one-pixel
// steps a few times a minute, never as a running animation.
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons
import "OmabarFocusModel.js" as FocusModel

Item {
  id: root

  property var bar
  property string moduleName
  property var settings: ({})

  readonly property int barSize: bar ? bar.barSize : 34
  readonly property int tile: Math.round(barSize * 0.66)
  readonly property color accent: Commons.Color.accent
  // Dark logo on a light accent, light logo on a dark one.
  readonly property bool lightAccent: (0.2126 * accent.r + 0.7152 * accent.g + 0.0722 * accent.b) > 0.5
  readonly property color logoColor: lightAccent ? Qt.rgba(0.06, 0.06, 0.08, 0.92) : Qt.rgba(1, 1, 1, 0.95)

  // ── Focus mode ──────────────────────────────────────────────────────
  readonly property var focusMode: bar && bar.omabarFocus ? bar.omabarFocus : null
  readonly property var focusInfo: focusMode ? focusMode.info : null
  readonly property bool focusing: !!focusInfo && focusInfo.active
  readonly property bool onBreak: focusing && focusInfo.phase === "break"
  // Where the hand is (0..1 round the tile from the top): the ring runs from
  // the hand to the top in a focus round, and from the top to the hand in a
  // break.
  readonly property real ringHand: focusing ? focusInfo.progress : 0
  readonly property real ringFraction: !focusing ? 0 : (onBreak ? ringHand : 1 - ringHand)
  readonly property real ringGap: Math.max(2, Math.round(barSize * 0.07))
  readonly property real ringStroke: Math.max(1.5, Math.round(barSize * 0.06 * 2) / 2)
  readonly property real ringSize: tile + 2 * (ringGap + ringStroke / 2)
  readonly property real ringRadius: Math.round(tile * 0.32) + ringGap + ringStroke / 2
  readonly property color ink: bar ? bar.barForeground : Commons.Color.foreground
  readonly property color ringColor: onBreak ? Qt.rgba(ink.r, ink.g, ink.b, 0.7) : accent
  onRingSizeChanged: if (focusMode) focusMode.ringLength = FocusModel.outlineLength(ringSize, ringSize, ringRadius)
  onFocusModeChanged: if (focusMode) focusMode.ringLength = FocusModel.outlineLength(ringSize, ringSize, ringRadius)

  function ringPoints() {
    var pts = onBreak
      ? FocusModel.outlineRange(0, 0, ringSize, ringSize, ringRadius, 0, ringHand, 1.5)
      : FocusModel.outlineRange(0, 0, ringSize, ringSize, ringRadius, ringHand, 1, 1.5)
    var out = []
    for (var i = 0; i < pts.length; i++) out.push(Qt.point(pts[i].x + ring.offset, pts[i].y + ring.offset))
    return out
  }

  // A soft swell of the tile's glow when a round or break begins: one
  // short animation, the only cue besides the chime.
  property real pulse: 0
  SequentialAnimation {
    id: pulseAnimation
    loops: 2
    NumberAnimation { target: root; property: "pulse"; to: 1; duration: Style.duration(260); easing.type: Easing.OutCubic }
    NumberAnimation { target: root; property: "pulse"; to: 0; duration: Style.duration(420); easing.type: Easing.InOutQuad }
  }
  Connections {
    target: root.focusMode
    ignoreUnknownSignals: true
    function onPhaseChanged(phase) { pulseAnimation.restart() }
  }

  implicitWidth: tile + Style.space(6)
  implicitHeight: barSize

  RectangularShadow {
    anchors.fill: face
    radius: face.radius
    // In Focus mode the ring is the tile's only halo, so the glow rests
    // unless the tile is hovered or pulsing.
    blur: (hover.hovered ? Style.space(14) : Style.space(9)) + root.pulse * Style.space(8)
    spread: 0
    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b,
      Math.min(0.9, (hover.hovered ? 0.65 : (root.focusing ? 0 : 0.4)) + root.pulse * 0.5))
    scale: face.scale
    Behavior on blur { NumberAnimation { duration: Style.duration(200); easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: Style.duration(200) } }
  }

  Rectangle {
    id: face
    anchors.centerIn: parent
    width: root.tile
    height: root.tile
    radius: Math.round(root.tile * 0.32)
    color: root.accent
    scale: tap.held ? 0.92 : (hover.hovered ? 1.06 : 1.0)
    Behavior on scale { NumberAnimation { duration: Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }
    Behavior on color { ColorAnimation { duration: Style.duration(250) } }

    // A touch of top light so the tile reads as glass, not flat paint.
    Rectangle {
      anchors.fill: parent
      radius: parent.radius
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.28) }
        GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0.0) }
      }
    }

    Text {
      anchors.centerIn: parent
      text: ""
      font.family: "omarchy"
      font.pixelSize: Math.round(root.tile * 0.56)
      color: root.logoColor
    }
  }

  // The ring: a faint track and the stroke over it.
  Item {
    id: ring
    readonly property real offset: -root.ringStroke / 2 - root.ringGap
    visible: root.focusing
    opacity: root.focusInfo && root.focusInfo.paused ? 0.45 : 1
    x: face.x
    y: face.y
    width: face.width
    height: face.height
    scale: face.scale

    Shape {
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        strokeColor: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.1)
        strokeWidth: root.ringStroke
        fillColor: "transparent"
        PathRectangle {
          x: ring.offset
          y: ring.offset
          width: root.ringSize
          height: root.ringSize
          radius: root.ringRadius
        }
      }
      ShapePath {
        strokeColor: root.ringFraction > 0.002 ? root.ringColor : "transparent"
        strokeWidth: root.ringStroke
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathPolyline { path: root.focusing && root.ringFraction > 0.002 ? root.ringPoints() : [] }
      }
    }
  }

  HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
  OmabarClickTarget {
    id: tap
    anchors.fill: parent
    bar: root.bar
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onPressed: function(button) {
      if (!root.bar) return
      if (button === Qt.RightButton) root.bar.run("xdg-terminal-exec")
      else root.bar.run("omarchy-shell shell toggle omarchy.menu '{\"menu\":\"root\"}'")
    }
  }
}
