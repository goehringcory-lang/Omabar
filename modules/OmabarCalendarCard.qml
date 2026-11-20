// The calendar card the split-flap clock drops down: a month grid with a dot
// for each calendar that has something on a day, the chosen day's agenda, and
// a picker for which Google calendars show, each in its Google color.
import QtQuick
import qs.Commons
import qs.Commons as Commons

Item {
  id: card

  property color ink: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontName: "monospace"

  property bool connected: false
  property bool loading: false
  property string error: ""
  property var events: []
  property var calendars: []

  signal toggleCalendar(string id)
  signal connectRequested()
  signal openEvent(string link)
  signal monthShown(int year, int month)   // month is 1-12

  readonly property var monthNames: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
  readonly property var dayLetters: ["M", "T", "W", "T", "F", "S", "S"]

  property date today: new Date()
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()          // 0-11
  property date selected: new Date(today.getFullYear(), today.getMonth(), today.getDate())
  property bool pickingCalendars: false

  function resetToToday() {
    card.today = new Date()
    card.viewYear = card.today.getFullYear()
    card.viewMonth = card.today.getMonth()
    card.selected = new Date(card.today.getFullYear(), card.today.getMonth(), card.today.getDate())
    card.pickingCalendars = false
  }

  function step(delta) {
    var m = card.viewMonth + delta
    card.viewYear += Math.floor(m / 12)
    card.viewMonth = ((m % 12) + 12) % 12
    card.monthShown(card.viewYear, card.viewMonth + 1)
  }

  // ── dates ──────────────────────────────────────────────────────────────
  function parseWhen(value, allDay) {
    if (!value) return null
    if (allDay) {
      var p = String(value).split("-")
      return new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]))
    }
    return new Date(value)
  }

  function dayKey(d) { return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate() }

  function sameDay(a, b) {
    return a && b && a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
  }

  // day key -> list of events touching that day
  readonly property var byDay: {
    var map = ({})
    var list = card.events || []
    for (var i = 0; i < list.length; i++) {
      var e = list[i]
      var start = card.parseWhen(e.start, e.allDay)
      var end = card.parseWhen(e.end, e.allDay)
      if (!start) continue
      var day = new Date(start.getFullYear(), start.getMonth(), start.getDate())
      // All-day ends are exclusive; timed events end the moment they end.
      var last = end ? new Date(end.getTime() - (e.allDay ? 1 : 1000)) : start
      for (var n = 0; n < 62 && day <= last; n++) {
        var key = card.dayKey(day)
        if (!map[key]) map[key] = []
        map[key].push(e)
        day = new Date(day.getFullYear(), day.getMonth(), day.getDate() + 1)
      }
      if (n === 0) {
        var only = card.dayKey(start)
        if (!map[only]) map[only] = []
        map[only].push(e)
      }
    }
    return map
  }

  // 42 cells, Monday first.
  readonly property var cells: {
    var first = new Date(card.viewYear, card.viewMonth, 1)
    var offset = (first.getDay() + 6) % 7
    var out = []
    for (var i = 0; i < 42; i++) out.push(new Date(card.viewYear, card.viewMonth, 1 - offset + i))
    return out
  }

  function timeLabel(e) {
    if (e.allDay) return "All day"
    var d = new Date(e.start)
    return Qt.formatTime(d, "HH:mm")
  }

  readonly property var agenda: {
    var list = card.byDay[card.dayKey(card.selected)] || []
    return list.slice().sort(function(a, b) {
      if (a.allDay !== b.allDay) return a.allDay ? -1 : 1
      return String(a.start).localeCompare(String(b.start))
    })
  }

  readonly property string agendaTitle: {
    if (card.sameDay(card.selected, card.today)) return "Today"
    var tomorrow = new Date(card.today.getFullYear(), card.today.getMonth(), card.today.getDate() + 1)
    if (card.sameDay(card.selected, tomorrow)) return "Tomorrow"
    return Qt.formatDate(card.selected, "dddd d MMMM")
  }

  implicitWidth: Style.space(320)
  implicitHeight: body.implicitHeight

  Column {
    id: body
    width: card.width
    spacing: Style.space(12)

    // ── header ───────────────────────────────────────────────────────────
    Item {
      width: parent.width
      height: Style.space(26)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: card.monthNames[card.viewMonth] + "  <font color='" + Qt.rgba(card.ink.r, card.ink.g, card.ink.b, 0.45) + "'>" + card.viewYear + "</font>"
        textFormat: Text.StyledText
        color: card.ink
        font.family: card.fontName
        font.pixelSize: Style.font.title
        font.weight: Font.DemiBold
      }

      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)
        Chip { label: "Today"; visible: card.viewMonth !== card.today.getMonth() || card.viewYear !== card.today.getFullYear() || !card.sameDay(card.selected, card.today); onPicked: { card.resetToToday(); card.monthShown(card.viewYear, card.viewMonth + 1) } }
        Chip { label: "\u{F0141}"; square: true; onPicked: card.step(-1) }
        Chip { label: "\u{F0142}"; square: true; onPicked: card.step(1) }
      }
    }

    // ── month grid ───────────────────────────────────────────────────────
    Grid {
      id: grid
      visible: !card.pickingCalendars
      columns: 7
      width: parent.width
      readonly property real cell: width / 7

      Repeater {
        model: card.dayLetters
        Text {
          required property string modelData
          width: grid.cell
          height: Style.space(20)
          horizontalAlignment: Text.AlignHCenter
          text: modelData
          color: card.ink
          opacity: 0.4
          font.family: card.fontName
          font.pixelSize: Style.font.caption
        }
      }

      Repeater {
        model: card.cells
        Item {
          id: dayCell
          required property var modelData
          readonly property bool inMonth: modelData.getMonth() === card.viewMonth
          readonly property bool isToday: card.sameDay(modelData, card.today)
          readonly property bool isSelected: card.sameDay(modelData, card.selected)
          readonly property var dayEvents: card.byDay[card.dayKey(modelData)] || []
          // One dot per calendar with something that day, in its color.
          readonly property var dots: {
            var seen = [], out = []
            for (var i = 0; i < dayEvents.length && out.length < 3; i++) {
              if (seen.indexOf(dayEvents[i].color) !== -1) continue
              seen.push(dayEvents[i].color)
              out.push(dayEvents[i].color)
            }
            return out
          }

          width: grid.cell
          height: Style.space(34)

          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: Style.space(2)
            width: Style.space(26)
            height: width
            radius: width / 2
            color: dayCell.isToday ? card.accent
              : dayCell.isSelected ? Qt.rgba(card.ink.r, card.ink.g, card.ink.b, 0.14)
              : dayHover.hovered ? Qt.rgba(card.ink.r, card.ink.g, card.ink.b, 0.07) : "transparent"
            border.width: dayCell.isSelected && dayCell.isToday ? 2 : 0
            border.color: Qt.rgba(card.ink.r, card.ink.g, card.ink.b, 0.6)
            Behavior on color { ColorAnimation { duration: Style.duration(120) } }

            Text {
              anchors.centerIn: parent
              text: dayCell.modelData.getDate()
              color: dayCell.isToday ? Commons.Color.background : card.ink
              opacity: dayCell.inMonth || dayCell.isToday ? 1 : 0.3
              font.family: card.fontName
              font.pixelSize: Style.font.bodySmall
              font.weight: dayCell.isToday ? Font.Bold : Font.Normal
            }
          }

          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(1)
            spacing: 2
            Repeater {
              model: dayCell.dots
              Rectangle {
                required property string modelData
                width: 4; height: 4; radius: 2
                color: modelData
                opacity: dayCell.inMonth ? 1 : 0.4
              }
            }
          }

          HoverHandler { id: dayHover; cursorShape: Qt.PointingHandCursor }
          TapHandler {
            onTapped: {
              card.selected = new Date(dayCell.modelData.getFullYear(), dayCell.modelData.getMonth(), dayCell.modelData.getDate())
              if (!dayCell.inMonth) {
                card.viewYear = dayCell.modelData.getFullYear()
                card.viewMonth = dayCell.modelData.getMonth()
                card.monthShown(card.viewYear, card.viewMonth + 1)
              }
            }
          }
        }
      }
    }

    // ── agenda ───────────────────────────────────────────────────────────
    Column {
      visible: !card.pickingCalendars && card.connected
      width: parent.width
      spacing: Style.space(4)

      Text {
        text: card.agendaTitle
        color: card.ink
        opacity: 0.5
        font.family: card.fontName
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1.2
        font.capitalization: Font.AllUppercase
      }

      Text {
        visible: card.agenda.length === 0
        text: card.loading ? "Loading…" : (card.error ? "Couldn't reach Google Calendar" : "Nothing scheduled")
        color: card.ink
        opacity: 0.45
        font.family: card.fontName
        font.pixelSize: Style.font.bodySmall
        topPadding: Style.space(2)
        bottomPadding: Style.space(2)
      }

      Repeater {
        model: card.agenda.slice(0, 6)
        Rectangle {
          id: eventRow
          required property var modelData
          width: parent.width
          height: Style.space(40)
          radius: Style.space(10)
          color: Qt.rgba(card.ink.r, card.ink.g, card.ink.b, rowHover.hovered ? 0.08 : 0.0)

          Rectangle {
            x: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            width: 4
            height: parent.height - Style.space(12)
            radius: 2
            color: eventRow.modelData.color
          }
          Column {
            x: Style.space(18)
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Style.space(26)
            spacing: 1
            Text {
              width: parent.width
              text: eventRow.modelData.title
              elide: Text.ElideRight
              color: card.ink
              font.family: card.fontName
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              width: parent.width
              text: card.timeLabel(eventRow.modelData) + "  ·  " + eventRow.modelData.calendar
              elide: Text.ElideRight
              color: card.ink
              opacity: 0.5
              font.family: card.fontName
              font.pixelSize: Style.font.caption
            }
          }
          HoverHandler { id: rowHover; cursorShape: eventRow.modelData.link ? Qt.PointingHandCursor : Qt.ArrowCursor }
          TapHandler { onTapped: if (eventRow.modelData.link) card.openEvent(eventRow.modelData.link) }
        }
      }
    }

    // ── calendar picker ──────────────────────────────────────────────────
    Column {
      visible: card.pickingCalendars
      width: parent.width
      spacing: Style.space(2)

      Repeater {
        model: [
          { title: "My calendars", owned: true },
          { title: "Shared with me", owned: false }
        ]
        Column {
          id: group
          required property var modelData
          readonly property var members: (card.calendars || []).filter(function(c) { return !!c.owned === group.modelData.owned })
          visible: members.length > 0
          width: parent.width
          spacing: Style.space(2)

          Text {
            text: group.modelData.title
            color: card.ink
            opacity: 0.5
            font.family: card.fontName
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1.2
            font.capitalization: Font.AllUppercase
            topPadding: Style.space(6)
            bottomPadding: Style.space(2)
          }

          Repeater {
            model: group.members
            Rectangle {
              id: calRow
              required property var modelData
              width: parent.width
              height: Style.space(32)
              radius: Style.space(8)
              color: Qt.rgba(card.ink.r, card.ink.g, card.ink.b, calHover.hovered ? 0.08 : 0.0)

              Rectangle {
                id: box
                x: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(16)
                height: width
                radius: Style.space(4)
                color: calRow.modelData.shown ? calRow.modelData.color : "transparent"
                border.width: 2
                border.color: calRow.modelData.color
                Text {
                  anchors.centerIn: parent
                  visible: calRow.modelData.shown
                  text: "\u{F012C}"
                  color: "white"
                  font.family: card.fontName
                  font.pixelSize: Style.font.caption
                }
              }
              Text {
                anchors.left: box.right
                anchors.leftMargin: Style.space(10)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: calRow.modelData.name
                elide: Text.ElideRight
                color: card.ink
                opacity: calRow.modelData.shown ? 1 : 0.6
                font.family: card.fontName
                font.pixelSize: Style.font.bodySmall
              }
              HoverHandler { id: calHover; cursorShape: Qt.PointingHandCursor }
              TapHandler { onTapped: card.toggleCalendar(calRow.modelData.id) }
            }
          }
        }
      }
    }

    // ── footer ───────────────────────────────────────────────────────────
    Item {
      width: parent.width
      height: Style.space(34)

      Chip {
        visible: card.connected
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        label: card.pickingCalendars ? "\u{F0141}  Back" : "\u{F00ED}  Calendars"
        onPicked: card.pickingCalendars = !card.pickingCalendars
      }

      Rectangle {
        visible: !card.connected && !card.loading
        anchors.fill: parent
        radius: Style.space(12)
        color: Qt.rgba(card.accent.r, card.accent.g, card.accent.b, connectHover.hovered ? 1.0 : 0.88)
        Text {
          anchors.centerIn: parent
          text: "\u{F02AD}  Connect Google Calendar"
          color: Commons.Color.background
          font.family: card.fontName
          font.pixelSize: Style.font.bodySmall
          font.weight: Font.DemiBold
        }
        HoverHandler { id: connectHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: card.connectRequested() }
      }
    }
  }

  component Chip: Rectangle {
    id: chip
    property string label: ""
    property bool square: false
    signal picked()
    height: Style.space(26)
    width: square ? height : chipText.implicitWidth + Style.space(20)
    radius: height / 2
    color: Qt.rgba(card.ink.r, card.ink.g, card.ink.b, chipHover.hovered ? 0.14 : 0.07)
    Behavior on color { ColorAnimation { duration: Style.duration(120) } }
    Text {
      id: chipText
      anchors.centerIn: parent
      text: chip.label
      color: card.ink
      font.family: card.fontName
      font.pixelSize: Style.font.bodySmall
    }
    HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: chip.picked() }
  }
}
