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
  signal dismissed()

  readonly property string helper: String(Qt.resolvedUrl("../bin/omabar-gcal")).replace(/^file:\/\//, "")
  readonly property color ink: Commons.Color.popups.text
  readonly property bool bottomBar: bar && bar.position === "bottom"

  property string month: ""

  function run(args, done) {
    var proc = runner.createObject(root, { command: [root.helper].concat(args) })
    proc.finished.connect(function(text) {
      try { done(JSON.parse(text)) } catch (e) { done(null) }
      proc.destroy()
    })
    proc.running = true
  }

  function refresh() {
    card.loading = true
    run(["calendars"], function(data) {
      if (!data) return
      card.connected = data.connected === true
      card.calendars = data.calendars || []
    })
    run(["events"].concat(root.month ? [root.month] : []), function(data) {
      card.loading = false
      if (!data) { card.error = "unreadable"; return }
      card.connected = data.connected === true
      card.error = data.error || ""
      card.events = data.events || []
    })
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
      stdout: StdioCollector { onStreamFinished: proc.finished(text) }
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
        fontName: root.bar && root.bar.fontFamily ? root.bar.fontFamily : "monospace"

        onMonthShown: function(year, month) {
          root.month = year + "-" + (month < 10 ? "0" : "") + month
          root.run(["events", root.month], function(data) {
            if (data) card.events = data.events || []
          })
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
