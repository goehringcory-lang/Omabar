// Omabar clock: a split-flap board, like an old departures sign. Each digit is
// a small tile in the theme's accent color; when it changes, the top flap
// falls to show the new number, left to right in a short cascade.
// Click flips the board to the date and back.
//
// Settings (inline on the shell.json entry):
//   twelveHour - 12-hour time (default false)
//   showDate   - the date as quiet text beside the tiles (default true)
import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons

Item {
  id: root

  property var bar
  property string moduleName
  property var settings: ({})

  function setting(name, fallback) {
    var v = settings ? settings[name] : undefined
    return v === undefined || v === null ? fallback : v
  }

  readonly property bool twelveHour: setting("twelveHour", false) === true
  readonly property bool showDate: setting("showDate", true) !== false
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : 34
  readonly property color ink: bar ? bar.barForeground : Commons.Color.foreground
  readonly property string fontName: bar && bar.fontFamily ? bar.fontFamily : "monospace"
  readonly property color accent: Commons.Color.accent
  readonly property color base: bar ? bar.background : Commons.Color.background

  property bool dateMode: false

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  readonly property var months: ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
  readonly property var days: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

  function pad(n) { return (n < 10 ? "0" : "") + n }

  // Five slots: two, a separator, two.
  readonly property var slots: {
    var d = clock.date
    if (root.dateMode) {
      var m = root.months[d.getMonth()]
      return [root.pad(d.getDate())[0], root.pad(d.getDate())[1], " ", m[0], m[1], m[2]]
    }
    var h = d.getHours()
    if (root.twelveHour) h = h % 12 === 0 ? 12 : h % 12
    var hh = root.pad(h)
    var mm = root.pad(d.getMinutes())
    return [hh[0], hh[1], ":", mm[0], mm[1]]
  }

  readonly property string dateText: {
    var d = clock.date
    return root.days[d.getDay()] + " " + d.getDate() + " " + root.months[d.getMonth()].charAt(0) + root.months[d.getMonth()].slice(1).toLowerCase()
  }

  readonly property int tileHeight: Math.round(barSize * 0.66)
  readonly property int tileWidth: Math.round(tileHeight * 0.68)
  readonly property int tileRadius: Math.max(2, Math.round(tileHeight * 0.12))
  // A recess a shade darker than the bar, so the tiles read as hardware.
  readonly property color tileFace: Qt.rgba(base.r * 0.55, base.g * 0.55, base.b * 0.55, 1)

  implicitWidth: vertical ? barSize : board.implicitWidth + (dateLabel.visible ? dateLabel.implicitWidth + Style.space(10) : 0) + Style.space(8)
  implicitHeight: vertical ? board.implicitHeight + Style.space(8) : barSize

  Row {
    id: board
    anchors.verticalCenter: parent.verticalCenter
    x: Style.space(4)
    spacing: Style.space(2)

    Repeater {
      model: root.slots.length

      Item {
        id: slot
        required property int index
        readonly property string ch: root.slots[index] || " "
        readonly property bool separator: ch === ":" || ch === " "

        width: separator ? Math.round(root.tileWidth * 0.42) : root.tileWidth
        height: root.tileHeight

        // The colon between hours and minutes.
        Column {
          visible: slot.ch === ":"
          anchors.centerIn: parent
          spacing: Math.round(root.tileHeight * 0.2)
          Repeater {
            model: 2
            Rectangle {
              width: Math.max(3, Math.round(root.tileHeight * 0.12)); height: width; radius: width / 2
              color: root.accent
              opacity: 0.9
            }
          }
        }

        Flap {
          visible: !slot.separator
          anchors.fill: parent
          value: slot.ch
          delay: slot.index * 70
        }
      }
    }
  }

  Text {
    id: dateLabel
    visible: root.showDate && !root.dateMode && !root.vertical
    anchors.left: board.right
    anchors.leftMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    text: root.dateText
    color: root.ink
    opacity: 0.55
    font.family: root.fontName
    font.pixelSize: Style.font.bodySmall
  }

  HoverHandler { cursorShape: Qt.PointingHandCursor }
  TapHandler { onTapped: root.dateMode = !root.dateMode }

  component Half: Item {
    id: halfItem
    property bool upper: true
    property string text: " "
    property real shade: 0
    width: root.tileWidth
    height: root.tileHeight / 2
    clip: true

    Rectangle {
      width: parent.width
      height: root.tileHeight
      y: halfItem.upper ? 0 : -root.tileHeight / 2
      radius: root.tileRadius
      color: root.tileFace
      // Light from above: the top flap a touch brighter than the bottom.
      Rectangle {
        anchors.fill: parent
        radius: parent.radius
        gradient: Gradient {
          GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
          GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.03) }
          GradientStop { position: 0.5001; color: Qt.rgba(0, 0, 0, 0.10) }
          GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.04) }
        }
      }
      Text {
        anchors.centerIn: parent
        text: halfItem.text
        color: root.accent
        font.family: root.fontName
        font.pixelSize: Math.round(root.tileHeight * 0.74)
        font.weight: Font.Bold
      }
    }
    // Darkens a flap as it turns away from the light.
    Rectangle {
      anchors.fill: parent
      color: "black"
      opacity: halfItem.shade
    }
  }

  // ── one split-flap tile ────────────────────────────────────────────────
  component Flap: Item {
    id: flap
    property string value: " "
    property int delay: 0
    // What the halves show: the old character until the flip passes them.
    property string shownTop: value
    property string shownBottom: value
    property string oldValue: value
    property bool ready: false

    Component.onCompleted: ready = true

    onValueChanged: {
      if (!ready || Style.reduceMotion) {
        shownTop = shownBottom = oldValue = value
        return
      }
      flip.stop()
      shownBottom = oldValue
      fallingTop.text = oldValue
      risingBottom.text = value
      shownTop = value
      flip.start()
    }

    readonly property real half: height / 2

    // Still halves: the new top, and the old bottom until the flip lands.
    Half { upper: true; text: flap.shownTop }
    Half { upper: false; y: flap.half; text: flap.shownBottom }

    // The old top flap falls away…
    Half {
      id: fallingTop
      upper: true
      visible: flip.running && fallScale.yScale > 0.01
      shade: (1 - fallScale.yScale) * 0.5
      transform: Scale { id: fallScale; origin.y: flap.half; yScale: 1 }
    }
    // …and the new bottom flap swings down over the old one.
    Half {
      id: risingBottom
      upper: false
      y: flap.half
      visible: flip.running && riseScale.yScale > 0.01
      shade: (1 - riseScale.yScale) * 0.35
      transform: Scale { id: riseScale; origin.y: 0; yScale: 0 }
    }

    // The hinge line across the middle of the tile.
    Rectangle {
      width: parent.width
      height: 1
      y: Math.round(flap.half)
      color: Qt.rgba(0, 0, 0, 0.55)
    }

    SequentialAnimation {
      id: flip
      PropertyAction { target: fallScale; property: "yScale"; value: 1 }
      PropertyAction { target: riseScale; property: "yScale"; value: 0 }
      PauseAnimation { duration: flap.delay }
      NumberAnimation { target: fallScale; property: "yScale"; to: 0; duration: 120; easing.type: Easing.InQuad }
      NumberAnimation { target: riseScale; property: "yScale"; to: 1; duration: 140; easing.type: Easing.OutBounce }
      ScriptAction { script: { flap.shownBottom = flap.value; flap.oldValue = flap.value } }
    }
  }
}
