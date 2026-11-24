// Omabar mail: a Thunderbird button. It matches the other bar icons until any
// of Thunderbird's inboxes (every account) has unread mail, then lights up in
// the theme's accent color, and stays lit until the mail is read.
//
// Unread counts come from Thunderbird's own folder summaries (bin/omabar-mail-
// unread). Nothing polls: the count is taken again when Thunderbird saves one
// of those summaries, shows a new-mail alert, or loses focus. An alert also
// lights it on its own, until you open Thunderbird or right-click the icon.
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
  property int unread: 0
  property var inboxes: []
  // False once the counter finds no Thunderbird at all: the button then hides.
  property bool installed: true
  readonly property bool hasNew: unseen > 0 || unread > 0
  readonly property string counter: String(Qt.resolvedUrl("../bin/omabar-mail-unread")).replace(/^file:\/\//, "")

  function recount() {
    if (!counterProc.running) counterProc.running = true
  }

  Process {
    id: counterProc
    command: [root.counter]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          var before = root.unread
          root.unread = Math.max(0, Number(data.unread) || 0)
          root.inboxes = Array.isArray(data.inboxes) ? data.inboxes : []
          root.installed = data.installed !== false
          var files = root.inboxes.map(function(inbox) { return String(inbox.file || "") })
            .filter(function(file) { return file !== "" })
          if (files.join("\n") !== root.inboxFiles.join("\n")) root.inboxFiles = files
          if (root.unread > before) pulse.restart()
          // Read somewhere else (a phone, webmail): nothing is left to light up for.
          else if (root.unread === 0 && before > 0) root.clear()
        } catch (e) {}
      }
    }
  }
  // Thunderbird saves a folder's summary shortly after mail changes. Each
  // inbox's summary is watched (never read into the shell), and the counter
  // runs once Thunderbird has finished writing.
  property var inboxFiles: []
  Instantiator {
    model: root.inboxFiles
    delegate: FileView {
      required property string modelData
      preload: false
      path: modelData
      watchChanges: true
      printErrors: false
      onFileChanged: recountSoon.restart()
    }
  }
  Timer { id: recountSoon; interval: 2000; onTriggered: root.recount() }
  // A safety net, which also finds an account added since the last look.
  Timer { interval: 300000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.recount() }

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
    pulse.stop()
    glowOut.restart()
    if (root.unseen === 0) return
    root.unseen = 0
    remember()
  }
  // Nothing is left to light up for (read here or elsewhere): let the glow go.
  onHasNewChanged: if (!hasNew) { pulse.stop(); glowOut.restart() }

  // "imap.gmail.com 2, imap.gmail-1.com 1" when more than one inbox has mail.
  function breakdown() {
    var parts = []
    for (var i = 0; i < inboxes.length; i++)
      if (inboxes[i].unread > 0) parts.push(inboxes[i].account + " " + inboxes[i].unread)
    return parts.length > 1 ? "\n" + parts.join(", ") : ""
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
          recountSoon.restart()
        }
      }
    }
    // dbus-monitor shouldn't exit; if it does, try again, backing off up to
    // five minutes so a missing dbus-monitor doesn't respawn every few seconds.
    onExited: {
      restart.interval = Math.min(300000, restart.interval * 2)
      restart.start()
    }
    onStarted: settle.restart()
  }
  Timer { id: restart; interval: 2500; onTriggered: watcher.running = true }
  // Running for a minute counts as healthy again.
  Timer { id: settle; interval: 60000; onTriggered: restart.interval = 2500 }

  // Looking at Thunderbird counts as reading the news, and leaving it is a
  // good moment to count what is still unread.
  property bool appFocused: false
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || String(event.name) !== "activewindow") return
      var windowClass = String(event.data || "").split(",")[0].toLowerCase()
      var focused = windowClass.indexOf(root.app.toLowerCase()) !== -1
      if (focused) root.clear()
      if (focused !== root.appFocused) recountSoon.restart()
      root.appFocused = focused
    }
  }

  visible: installed
  implicitWidth: installed ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.hasNew ? "\u{F01EE}" : "\u{F01F0}"
    active: root.hasNew
    activeColor: Commons.Color.accent
    tooltipText: root.unread > 0
      ? (root.unread === 1 ? "1 unread message" : root.unread + " unread messages") + root.breakdown() + "\nClick to open Thunderbird"
      : root.unseen > 0
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
    NumberAnimation {
      id: glowOut
      target: glow
      property: "opacity"
      to: 0
      duration: Style.duration(260)
      easing.type: Easing.OutQuad
    }
  }
}
