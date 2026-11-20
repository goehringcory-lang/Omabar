// The clock's drop-down: OmabarCalendarCard in a glass popup, fed by
// bin/omabar-gcal (Google Calendar) and refreshed each time it opens.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons

Item {
  id: root

  property Item anchorItem
  property var bar
  property bool open: false
  signal dismissed()

  readonly property string helper: String(Qt.resolvedUrl("../bin/omabar-gcal")).replace(/^file:\/\//, "")
  readonly property color ink: bar ? bar.barForeground : Commons.Color.foreground
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

  PopupWindow {
    id: popup
    visible: root.open && root.anchorItem !== null
    color: "transparent"
    anchor.item: root.anchorItem
    anchor.rect.x: root.anchorItem ? root.anchorItem.width / 2 : 0
    anchor.rect.y: root.bottomBar ? -Style.space(10) : (root.anchorItem ? root.anchorItem.height + Style.space(10) : 0)
    anchor.rect.width: 1
    anchor.rect.height: 1
    anchor.edges: Edges.Top
    anchor.gravity: root.bottomBar ? Edges.Top : Edges.Bottom
    implicitWidth: glass.width + shadowRoom * 2
    implicitHeight: glass.height + shadowRoom * 2

    readonly property int shadowRoom: Style.space(18)

    HyprlandFocusGrab {
      windows: [popup]
      active: popup.visible
      onCleared: root.dismissed()
    }

    RectangularShadow {
      anchors.fill: glass
      radius: glass.radius
      offset.y: Style.space(6)
      blur: Style.space(18)
      color: Qt.rgba(0, 0, 0, 0.35)
    }

    Rectangle {
      id: glass
      x: popup.shadowRoom
      y: popup.shadowRoom
      width: card.implicitWidth + Style.space(18) * 2
      height: card.implicitHeight + Style.space(18) * 2
      radius: Style.space(20)
      color: Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b, 0.93)
      border.width: 1
      border.color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.10)
      opacity: popup.visible ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Style.duration(160) } }
      Behavior on height { NumberAnimation { duration: Style.duration(220); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }

      Rectangle {
        anchors.fill: parent
        radius: parent.radius
        gradient: Gradient {
          GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.06) }
          GradientStop { position: 0.25; color: Qt.rgba(1, 1, 1, 0.0) }
        }
      }

      OmabarCalendarCard {
        id: card
        x: Style.space(18)
        y: Style.space(18)
        width: implicitWidth
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
          if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation " + Util.shellQuote(Util.shellQuote(root.helper) + " login"))
          root.dismissed()
        }
        onOpenEvent: function(link) {
          if (root.bar) root.bar.run("xdg-open " + Util.shellQuote(link))
          root.dismissed()
        }
      }
    }
  }
}
