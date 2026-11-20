// The clock's drop-down: OmabarCalendarCard in an Omarchy popup card, fed by
// bin/omabar-gcal (Google Calendar) and refreshed each time it opens.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: root

  property Item anchorItem
  property var bar
  property var owner          // the bar widget this drops from; it has close()
  property bool open: false
  property bool twelveHour: true
  signal dismissed()

  readonly property string helper: String(Qt.resolvedUrl("../bin/omabar-gcal")).replace(/^file:\/\//, "")
  readonly property color ink: Commons.Color.popups.text
  readonly property bool bottomBar: bar && bar.position === "bottom"

  // Passed on to the card.
  property int weekStart: -1

  property string month: ""
  // Counts event requests, so an answer that comes back after a newer request
  // (fast clicks through the months) is dropped instead of shown.
  property int eventsAsk: 0

  function run(args, done) {
    var proc = runner.createObject(root, { command: [root.helper].concat(args) })
    var answered = false
    function finish(text) {
      if (answered) return
      answered = true
      var data = null
      try { data = JSON.parse(text) } catch (e) {}
      done(data)
      proc.destroy()
    }
    proc.finished.connect(finish)
    // A helper that never starts or never answers must not leave "Loading…" up.
    proc.gaveUp.connect(function() { finish("") })
    proc.running = true
  }

  function loadEvents() {
    var ask = ++root.eventsAsk
    card.loading = true
    run(["events"].concat(root.month ? [root.month] : []), function(data) {
      if (ask !== root.eventsAsk) return
      card.loading = false
      if (!data) { card.error = "Couldn't read your calendars."; return }
      card.connected = data.connected === true
      card.error = String(data.error || "")
      card.events = Array.isArray(data.events) ? data.events : []
    })
  }

  function refresh() {
    run(["calendars"], function(data) {
      if (!data) return
      card.connected = data.connected === true
      card.calendars = Array.isArray(data.calendars) ? data.calendars : []
    })
    loadEvents()
  }

  onOpenChanged: {
    if (!open) return
    card.resetToToday()
    root.month = ""
    refresh()
  }

  Component {
    id: runner
    Process {
      id: proc
      signal finished(string text)
      signal gaveUp()
      stdout: StdioCollector { onStreamFinished: proc.finished(text) }
      property Timer watchdog: Timer {
        interval: 60000
        running: true
        onTriggered: { proc.running = false; proc.gaveUp() }
      }
    }
  }

  PopupCard {
    id: popup
    anchorItem: root.anchorItem
    bar: root.bar
    owner: root.owner
    open: root.open
    contentWidth: popup.fittedContentWidth(card.implicitWidth)
    contentHeight: popup.fittedContentHeight(card.implicitHeight)

      OmabarCalendarCard {
        id: card
        anchors.fill: parent
        ink: root.ink
        twelveHour: root.twelveHour
        fontName: root.bar && root.bar.fontFamily ? root.bar.fontFamily : "monospace"
        weekStart: root.weekStart

        onMonthShown: function(year, month) {
          root.month = year + "-" + (month < 10 ? "0" : "") + month
          root.loadEvents()
        }
        onToggleCalendar: function(id) {
          root.run(["toggle", id], function() { root.refresh() })
        }
        onConnectRequested: {
          if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation " + Util.shellQuote(Util.shellQuote(root.helper) + " connect"))
          root.dismissed()
        }
        onOpenEvent: function(link) {
          if (root.bar) root.bar.run("xdg-open " + Util.shellQuote(link))
          root.dismissed()
        }
      }
  }
}
