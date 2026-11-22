// Omabar Ask, the bar's assistant: a sparkle in the center of the bar. Hover
// it (or click it) and a glass box drops down where you type or dictate a
// question. Enter opens it in your default browser, in the normal chat of the
// site you picked (Claude, ChatGPT, Gemini, Grok, Claude Duet or ChatGPT Dot),
// where you are already signed in. The answer is that site's own page; nothing
// is sent from the bar itself.
//
// Every site is asked for you; nothing to paste. ChatGPT and Grok take the
// question in their link. Claude's link fills it in and Enter is pressed once
// the page is up. Gemini, Claude Duet and ChatGPT Dot have no such link, so
// bin/omabar-ask pastes it into their chat box and presses Enter, only once
// the browser window's title shows that site.
//
// Dictation uses Omarchy's own (Setup > Defaults > Dictation, e.g. Voxtype):
// the mic starts and stops it, and it types into the box. Alt+Space works too.
//
// Settings (inline on the shell.json entry):
//   providers - which sites to offer, in order (default all of them:
//               ["claude", "chatgpt", "gemini", "grok", "duet", "dot"])
//   links     - a page to open for a site instead of the usual one, e.g.
//               {"duet": "https://claude.ai/…"} (the question is pasted in)
//   typeDelay - ms a site gets to load before the question is typed in
//               (default 2500); raise it if a slow page misses it
//   provider  - the one picked at first (default "claude"); the last one you
//               used is remembered in ~/.config/omabar/ask.json
//   hover     - false opens the box on click only (default true)
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "OmabarAskModel.js" as Model

Item {
  id: root

  property var bar
  property string moduleName
  property var settings: ({})

  function setting(name, fallback) {
    var v = settings ? settings[name] : undefined
    return v === undefined || v === null ? fallback : v
  }

  readonly property var providers: Model.shown(setting("providers", ["claude", "chatgpt", "gemini", "grok", "duet", "dot"]))
  readonly property bool hoverOpens: setting("hover", true) !== false
  readonly property string fontName: bar && bar.fontFamily ? bar.fontFamily : Style.font.family
  readonly property string helper: String(Qt.resolvedUrl("../bin/omabar-ask")).replace(/^file:\/\//, "")
  // How long a site gets to load before the question is typed in, in ms.
  readonly property int typeDelay: Math.max(500, Number(setting("typeDelay", 2500)) || 2500)
  readonly property string storeFile: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omabar/ask.json"

  property string providerId: {
    var first = String(setting("provider", "claude")).toLowerCase()
    for (var i = 0; i < providers.length; i++) if (providers[i].id === first) return first
    return providers.length ? providers[0].id : "claude"
  }
  property var history: []

  // ── open / close ────────────────────────────────────────────────────
  property bool open: false
  // Set once the pointer reaches the box, so leaving the icon on the way
  // there doesn't close it.
  property bool reached: false
  property bool listening: false
  property bool dictationReady: true

  function show() {
    if (root.open) return
    root.reached = false
    root.open = true
    checkDictation()
  }

  function close() {
    openTimer.stop()
    leaveTimer.stop()
    if (root.listening) stopDictation()
    root.open = false
  }

  // Stays open while there's a question in the box or dictation is running,
  // so a stray pointer never throws away what you typed.
  readonly property bool busy: (panel.loadedContent && panel.loadedContent.hasText) || root.listening

  Timer {
    id: openTimer
    interval: 160
    onTriggered: if (iconHover.hovered) root.show()
  }

  Timer {
    id: leaveTimer
    interval: root.reached ? 450 : 1600
    onTriggered: {
      if (!root.open || root.busy) return
      if (panel.loadedContent && panel.loadedContent.hovered) return
      root.close()
    }
  }

  // ── remembered choice and recent questions ──────────────────────────
  FileView {
    id: store
    path: root.storeFile
    printErrors: false
    onLoaded: {
      var data
      try { data = JSON.parse(text()) } catch (e) { return }
      if (!data || typeof data !== "object") return
      var id = String(data.provider || "")
      for (var i = 0; i < root.providers.length; i++) if (root.providers[i].id === id) root.providerId = id
      if (Array.isArray(data.history)) root.history = data.history.filter(function(q) { return typeof q === "string" })
    }
  }

  function save() {
    var json = JSON.stringify({ provider: root.providerId, history: root.history })
    // Made private (the questions are yours), and moved into place whole.
    Quickshell.execDetached(["sh", "-c", 'umask 077; mkdir -p "$(dirname "$1")" && printf "%s" "$2" > "$1.tmp" && mv -f "$1.tmp" "$1"', "sh", root.storeFile, json])
  }

  // ── asking ──────────────────────────────────────────────────────────
  function ask(id, text) {
    var plan = Model.plan(id, text, root.setting("links", null))
    if (!plan) return
    root.providerId = id
    root.history = Model.remember(root.history, text, 20)
    save()
    if (panel.loadedContent) panel.loadedContent.clear()
    close()
    // The question and link travel as arguments, never inside command text.
    Quickshell.execDetached([root.helper, plan.mode, plan.url, plan.title, plan.name, Model.clean(text), String(root.typeDelay)])
  }

  // ── dictation ───────────────────────────────────────────────────────
  Process {
    id: dictationCheck
    command: ["omarchy-default-dictation"]
    onExited: function(code) { root.dictationReady = code === 0 }
  }

  function checkDictation() {
    if (!dictationCheck.running) dictationCheck.running = true
  }

  function toggleDictation() {
    if (!root.dictationReady) {
      // Omarchy's dictation picker (Setup > Defaults > Dictation).
      Quickshell.execDetached(["omarchy-menu", "toggle", "setup"])
      close()
      return
    }
    root.listening = !root.listening
    Quickshell.execDetached(["omarchy-dictation", root.listening ? "start" : "stop"])
  }

  function stopDictation() {
    root.listening = false
    Quickshell.execDetached(["omarchy-dictation", "stop"])
  }

  // ── on the bar ──────────────────────────────────────────────────────
  implicitWidth: icon.implicitWidth
  implicitHeight: icon.implicitHeight

  HoverHandler {
    id: iconHover
    enabled: root.hoverOpens
    onHoveredChanged: {
      if (hovered) openTimer.restart()
      else openTimer.stop()
    }
  }

  BarIconButton {
    id: icon
    anchors.fill: parent
    bar: root.bar
    text: "\u{F0674}"
    active: root.open
    activeColor: Commons.Color.accent
    tooltipText: root.open ? "" : "Assistant\nAsk " + Model.provider(root.providerId).full + " anything"
    onPressed: function(button) {
      if (root.open) root.close()
      else root.show()
    }
  }

  // ── the box ─────────────────────────────────────────────────────────
  // A KeyboardPanel, not a PopupCard: it takes the keyboard the moment it
  // opens, so you can type (or dictate) straight away.
  KeyboardPanel {
    id: panel
    anchorItem: icon
    bar: root.bar
    owner: root
    open: root.open
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)
    focusTarget: panel.loadedContent

    content: Component {
      OmabarAskCard {
        id: card
        property alias hovered: cardHover.hovered
        ink: Commons.Color.popups.text
        fontName: root.fontName
        providers: root.providers
        providerId: root.providerId
        history: root.history
        listening: root.listening
        dictationReady: root.dictationReady

        onAsk: function(id, text) { root.ask(id, text) }
        onPickProvider: function(id) { root.providerId = id; root.save() }
        onToggleDictation: root.toggleDictation()
        onCloseRequested: root.close()
        onActiveFocusChanged: if (activeFocus) card.focusField()

        HoverHandler {
          id: cardHover
          onHoveredChanged: {
            if (hovered) { root.reached = true; leaveTimer.stop() }
            else if (root.open) leaveTimer.restart()
          }
        }
      }
    }
  }

  onOpenChanged: {
    if (open) {
      leaveTimer.restart()
      if (panel.loadedContent) Qt.callLater(function() { if (root.open && panel.loadedContent) panel.loadedContent.focusField() })
    }
  }
}
