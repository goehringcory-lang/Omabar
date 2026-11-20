// Omabar menu button: the Omarchy logo on a bright tile in the theme's accent
// color, with a soft glow of the same color. Click opens the Omarchy menu;
// right-click opens a terminal, like the built-in button.
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Commons as Commons

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

  implicitWidth: tile + Style.space(6)
  implicitHeight: barSize

  RectangularShadow {
    anchors.fill: face
    radius: face.radius
    blur: hover.hovered ? Style.space(14) : Style.space(9)
    spread: 0
    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, hover.hovered ? 0.65 : 0.4)
    scale: face.scale
    Behavior on blur { NumberAnimation { duration: Style.duration(200) } }
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
