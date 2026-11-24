// Omabar Keep: your pinned Google Keep notes and lists in a glass card.
//
// It lives in the drawer (the layout's tray section): the drawer's Keep tile
// calls open(), and the card drops below the drawer handle. Placed on the bar
// itself instead, it is a Keep icon that opens the same card.
//
// bin/omabar-keep does the talking to Google. Opening the card shows the last
// sync at once, then syncs again; nothing runs while the card is closed,
// except one quiet sync a little after the shell starts so the first open
// is already current.
//
// Settings (inline on the shell.json entry):
//   itemsShown - open list items shown per list before "+ N more" (default 6)
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: root

  property var bar
  property string moduleName
  property var settings: ({})

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  readonly property string helper: String(Qt.resolvedUrl("../bin/omabar-keep")).replace(/^file:\/\//, "")
  readonly property string fontName: bar && bar.fontFamily ? bar.fontFamily : "monospace"

  property bool cardOpen: false
  function open() { cardOpen = true }
  function close() { cardOpen = false }
  function toggle() { cardOpen = !cardOpen }

  onCardOpenChanged: {
    if (!cardOpen) return
    card.now = new Date()
    run(["cached"], function(data) { if (data && !syncProc.running) take(data, true) })
    sync()
  }

  function take(data, fromCache) {
    card.connected = data.connected === true
    card.notes = Array.isArray(data.notes) ? data.notes : []
    card.synced = Number(data.synced) || 0
    if (!fromCache) card.error = String(data.error || "")
    card.loaded = true
  }

  function sync() {
    if (syncProc.running) return
    card.loading = true
    syncProc.running = true
  }

  Process {
    id: syncProc
    command: [root.helper, "pinned"]
    stdout: StdioCollector {
      onStreamFinished: {
        var data = null
        try { data = JSON.parse(text) } catch (e) {}
        card.loading = false
        card.now = new Date()
        if (data) root.take(data, false)
        else { card.error = "Couldn't reach Google Keep."; card.loaded = true }
      }
    }
    onRunningChanged: if (!running) card.loading = false
  }

  function run(args, done) {
    var proc = runner.createObject(root, { command: [root.helper].concat(args) })
    proc.finished.connect(function(text) {
      var data = null
      try { data = JSON.parse(text) } catch (e) {}
      done(data)
      proc.destroy()
    })
    proc.running = true
  }

  Component {
    id: runner
    Process {
      id: proc
      signal finished(string text)
      stdout: StdioCollector { onStreamFinished: proc.finished(text) }
    }
  }

  // Warm the cache once, after the shell has settled.
  Timer {
    interval: 20000
    running: true
    onTriggered: root.run(["status"], function(data) { if (data && data.connected) root.sync() })
  }

  // ── on the bar (when placed there rather than in the drawer) ────────
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\u{F06DC}"
    active: root.cardOpen
    activeColor: Commons.Color.accent
    tooltipText: root.cardOpen ? "" : "Google Keep"
    onPressed: function(pressedButton) { root.toggle() }
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.cardOpen
    contentWidth: popup.fittedContentWidth(card.implicitWidth)
    contentHeight: popup.fittedContentHeight(card.implicitHeight)

    OmabarKeepCard {
      id: card
      anchors.fill: parent
      ink: Commons.Color.popups.text
      fontName: root.fontName
      itemsShown: Math.max(1, Number(root.setting("itemsShown", 6)) || 6)

      onOpenNote: function(url) {
        root.close()
        Quickshell.execDetached([root.helper, "open", url || "https://keep.google.com/"])
      }
      onOpenKeep: {
        root.close()
        Quickshell.execDetached([root.helper, "open"])
      }
      onConnectRequested: {
        root.close()
        if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation " + Util.shellQuote(Util.shellQuote(root.helper) + " connect"))
      }
      onRefreshRequested: root.sync()
    }
  }
}
