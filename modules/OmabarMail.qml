// Omabar mail: a Thunderbird button. It matches the other bar icons until new
// mail arrives in any of Thunderbird's inboxes, then lights up in the theme's
// accent color. Opening Thunderbird (click, or focusing its window) clears it.
//
// New mail is noticed from Thunderbird's own desktop notifications, so keep
// Thunderbird running (it can sit in the background) with new-mail alerts on,
// which is its default. Right-click marks it seen without opening.
//
// Settings (inline on the shell.json entry):
//   app    - window class / command to open (default "thunderbird")
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: root

  property var bar
  property string moduleName
  property var settings: ({})

  readonly property string app: String(settings && settings.app ? settings.app : "thunderbird")
  property int unseen: 0
  readonly property bool hasNew: unseen > 0

  // Survives a shell restart, so a mail that arrived meanwhile isn't lost.
  readonly property string stateFile: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/omabar/mail-unseen"

  FileView {
    id: state
    path: root.stateFile
    printErrors: false
    onLoaded: root.unseen = parseInt(text(), 10) || 0
  }

  function remember() {
    state.setText(String(root.unseen))
  }

  function clear() {
    if (root.unseen === 0) return
    root.unseen = 0
    pulse.stop()
    glow.opacity = 0
    remember()
  }

  function open() {
    clear()
    if (bar) bar.run("omarchy-launch-or-focus " + Util.shellQuote(root.app) + " " + Util.shellQuote("uwsm-app -- " + root.app))
  }

  // Watch the session bus for Thunderbird's new-mail notifications.
  property bool expectAppName: false
  Process {
    id: watcher
    running: true
    command: ["dbus-monitor", "--session", "type='method_call',interface='org.freedesktop.Notifications',member='Notify'"]
    stdout: SplitParser {
      onRead: function(line) {
        if (line.indexOf("member=Notify") !== -1) {
          root.expectAppName = true
          return
        }
        if (!root.expectAppName) return
        var match = line.match(/^\s*string "(.*)"\s*$/)
        if (!match) return
        root.expectAppName = false
        if (match[1].toLowerCase().indexOf(root.app.toLowerCase()) !== -1) {
          root.unseen += 1
          root.remember()
          pulse.restart()
        }
      }
    }
    // dbus-monitor shouldn't exit; if it does, try again shortly.
    onExited: restart.start()
  }
  Timer { id: restart; interval: 5000; onTriggered: watcher.running = true }

  // Looking at Thunderbird counts as reading the news.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || String(event.name) !== "activewindow") return
      var windowClass = String(event.data || "").split(",")[0].toLowerCase()
      if (windowClass.indexOf(root.app.toLowerCase()) !== -1) root.clear()
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.hasNew ? "\u{F01EE}" : "\u{F01F0}"
    active: root.hasNew
    activeColor: Commons.Color.accent
    tooltipText: root.hasNew
      ? (root.unseen === 1 ? "1 new message" : root.unseen + " new messages") + "\nClick to open Thunderbird · Right-click to mark seen"
      : "Thunderbird"
    onPressed: function(pressedButton) {
      if (pressedButton === Qt.RightButton) root.clear()
      else root.open()
    }
  }

  // A soft accent glow that breathes once when mail lands.
  Rectangle {
    id: glow
    anchors.centerIn: button
    width: Math.round((root.bar ? root.bar.barSize : 34) * 0.62)
    height: width
    radius: width / 2
    color: Commons.Color.accent
    opacity: 0
    z: -1
    SequentialAnimation on opacity {
      id: pulse
      running: false
      NumberAnimation { to: 0.35; duration: Style.duration(260); easing.type: Easing.OutQuad }
      NumberAnimation { to: 0.12; duration: Style.duration(900); easing.type: Easing.InOutQuad }
    }
  }
}
