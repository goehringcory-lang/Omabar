// Omabar Keep: your pinned Google Keep notes and lists in a glass card,
// editable in place.
//
// It lives in the drawer (the layout's tray section): the drawer's Keep tile
// calls open(), and the card drops below the drawer handle. Placed on the bar
// itself instead, it is a Keep icon that opens the same card.
//
// bin/omabar-keep does the talking to Google. Opening the card shows the last
// sync at once, then syncs again. An edit is queued on disk the moment you
// make it (so it survives closing the card, a restart or being offline) and
// sent to Keep a moment later; edits that couldn't be sent are retried every
// minute until they go through, card open or not.
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

  // ── what the card shows ─────────────────────────────────────────────
  property bool connected: false
  property bool loaded: false
  property bool loading: false
  property string error: ""
  property var notes: []
  property real synced: 0
  property int pending: 0
  property var conflicts: []
  property date now: new Date()

  readonly property var card: panel.loadedContent
  readonly property bool typing: !!card && card.typing
  // A sync's answer that came back while you were typing; shown once you stop.
  property var heldAnswer: null
  onTypingChanged: if (!typing && heldAnswer) { var held = heldAnswer; heldAnswer = null; take(held, false) }

  property bool cardOpen: false
  function open() { cardOpen = true }
  function close() { if (card) card.leaveFields(); cardOpen = false }
  function toggle() { if (cardOpen) close(); else open() }

  onCardOpenChanged: {
    if (!cardOpen) return
    root.now = new Date()
    run(["cached"], function(data) { if (data && !syncProc.running) take(data, true) })
    sync()
  }

  function take(data, fromCache) {
    root.connected = data.connected === true
    root.notes = Array.isArray(data.notes) ? data.notes : []
    root.synced = Number(data.synced) || 0
    root.pending = Number(data.pending) || 0
    root.conflicts = Array.isArray(data.conflicts) ? data.conflicts : []
    if (!fromCache) root.error = String(data.error || "")
    root.loaded = true
  }

  // ── syncing ─────────────────────────────────────────────────────────
  property bool syncAgain: false
  function sync() {
    if (syncProc.running) { syncAgain = true; return }
    syncAgain = false
    root.loading = true
    syncProc.running = true
  }

  Process {
    id: syncProc
    command: [root.helper, "pinned"]
    stdout: StdioCollector {
      onStreamFinished: {
        var data = null
        try { data = JSON.parse(text) } catch (e) {}
        root.loading = false
        root.now = new Date()
        if (!data) { root.error = "Couldn't reach Google Keep."; root.loaded = true }
        else if (root.typing) root.heldAnswer = data
        else root.take(data, false)
        // Edits made while this sync ran go out now.
        if (root.syncAgain || (data && !data.error && Number(data.pending) > 0)) sendSoon.restart()
      }
    }
    onRunningChanged: if (!running) root.loading = false
  }

  // Edits go out shortly after the last one, so a burst of ticks is one sync.
  Timer { id: sendSoon; interval: 1200; onTriggered: root.sync() }

  // Anything that couldn't be sent (offline, Google hiccup) is retried.
  Timer {
    interval: 60000
    repeat: true
    running: root.pending > 0
    onTriggered: if (!syncProc.running) root.sync()
  }

  function edit(change) {
    run(["edit", JSON.stringify(change)], function(data) {
      // Held while you type elsewhere, except a new item, whose list takes
      // the keyboard straight back for the next one.
      if (data && !data.error) {
        if (root.typing && change.op !== "addItem") root.heldAnswer = data
        else root.take(data, true)
      }
      else if (data && data.error) root.error = String(data.error)
      sendSoon.restart()
    })
  }

  function dismissConflicts() {
    root.conflicts = []
    run(["dismiss"], function() {})
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

  // After the shell starts: warm the cache, and send any edits left over.
  Timer {
    interval: 20000
    running: true
    onTriggered: root.run(["status"], function(data) {
      if (!data || !data.connected) return
      root.pending = Number(data.pending) || 0
      root.sync()
    })
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

  // A KeyboardPanel, not a PopupCard, so the card can take typing.
  KeyboardPanel {
    id: panel
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.cardOpen
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)
    focusTarget: panel.loadedContent

    content: Component {
      OmabarKeepCard {
        ink: Commons.Color.popups.text
        fontName: root.fontName
        itemsShown: Math.max(1, Number(root.setting("itemsShown", 6)) || 6)
        connected: root.connected
        loaded: root.loaded
        loading: root.loading
        error: root.error
        notes: root.notes
        synced: root.synced
        pending: root.pending
        conflicts: root.conflicts
        now: root.now

        onEdit: function(change) { root.edit(change) }
        onDismissConflicts: root.dismissConflicts()
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
}
