// Omabar clock: a split-flap board, like an old departures sign. Each digit is
// a small tile in the theme's accent color; when it changes, the top flap
// falls to show the new number, left to right in a short cascade.
// Click drops down a calendar with your Google calendars (see bin/omabar-gcal);
// right-click flips the board to the date and back.
//
// Settings (inline on the shell.json entry):
//   twelveHour - 12-hour time with AM/PM beside the tiles (default true)
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

  readonly property bool twelveHour: setting("twelveHour", true) !== false
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
    // 12-hour time drops the leading zero: 9:47, not 09:47.
    var hh = root.twelveHour && h < 10 ? " " + h : root.pad(h)
    var mm = root.pad(d.getMinutes())
    return [hh[0], hh[1], ":", mm[0], mm[1]]
  }

  readonly property string dateText: {
    var d = clock.date
    var date = root.days[d.getDay()] + " " + d.getDate() + " " + root.months[d.getMonth()].charAt(0) + root.months[d.getMonth()].slice(1).toLowerCase()
    return root.twelveHour ? (d.getHours() < 12 ? "AM" : "PM") + "  " + date : date
  }

  readonly property int tileHeight: Math.round(barSize * 0.66)

  implicitWidth: vertical ? barSize : board.implicitWidth + (dateLabel.visible ? dateLabel.implicitWidth + Style.space(10) : 0) + Style.space(8)
  implicitHeight: vertical ? board.implicitHeight + Style.space(8) : barSize

  OmabarFlapText {
    id: board
    anchors.verticalCenter: parent.verticalCenter
    x: Style.space(4)
    text: root.slots.join("")
    tileHeight: root.tileHeight
    accent: root.accent
    base: root.base
    fontName: root.fontName
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

  property bool calendarOpen: false
  // Called by the bar when another popup opens or a click lands outside.
  function close() { calendarOpen = false }

  OmabarCalendar {
    anchorItem: board
    bar: root.bar
    owner: root
    open: root.calendarOpen
    onDismissed: root.calendarOpen = false
  }

  HoverHandler { cursorShape: Qt.PointingHandCursor }
  TapHandler {
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onTapped: function(eventPoint, button) {
      if (button === Qt.RightButton) root.dateMode = !root.dateMode
      else root.calendarOpen = !root.calendarOpen
    }
  }
}
