// Focus mode's one source of truth on the bar. The bar engine makes exactly
// one (tools/omabar-patch.py), shared by the bar on every monitor, so the
// phase-change sound plays once and the state file is watched once.
//
// bin/omabar-focus does everything with side effects (Do Not Disturb, music)
// and writes the state file; this reads it, works out the phase from the
// clock (OmabarFocusModel.js) and tells the bar when to slim down.
//
// It never animates: `now` moves only as often as the Pomodoro ring would
// move by a pixel (about every 15 s in a 25 minute round), or every second
// while someone is looking at the Focus card.
import QtQuick
import Quickshell
import Quickshell.Io
import "OmabarFocusModel.js" as Model

Item {
  id: focus

  property var bar: null

  readonly property string helper: String(Qt.resolvedUrl("../bin/omabar-focus")).replace(/^file:\/\//, "")
  readonly property string stateFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omabar/focus.json"

  property var state: ({})
  property double now: Date.now()
  readonly property var info: Model.at(state, now)
  readonly property bool active: info.active
  readonly property bool paused: info.paused
  // The bar folds every widget but the tile, workspaces, clock and timer.
  readonly property bool slim: active
  // False until the state file has been read once, so a shell restart in the
  // middle of Focus mode comes back slim without playing the fold.
  property bool ready: false

  // Seconds-level updates while a Focus card is open (it counts how many).
  property int watchers: 0
  // The ring's length in pixels, so a tick moves it by about one pixel.
  property real ringLength: 100

  // A few seconds of "Break · 5 min" after a phase changes (the timer chip
  // shows it), and a pulse on the Omarchy tile.
  property string cue: ""
  signal phaseChanged(string phase)

  function run(args) {
    Quickshell.execDetached([helper].concat(args))
  }
  function toggle() { run(["toggle"]) }
  function start() { run(["start"]) }
  function stop() { run(["stop"]) }
  function pause() { run(["pause"]) }
  function resume() { run(["resume"]) }
  function skip() { run(["skip"]) }

  function tick() { now = Date.now() }

  FileView {
    id: store
    path: focus.stateFile
    printErrors: false
    watchChanges: true
    blockLoading: true
    onFileChanged: reload()
    onLoaded: focus.read(text())
    onLoadFailed: focus.read("")
  }

  function read(text) {
    var next = {}
    try { next = JSON.parse(text || "{}") || {} } catch (e) { next = {} }
    if (typeof next !== "object" || Array.isArray(next)) next = {}
    now = Date.now()
    lastTick = now
    // A change of phase from a file change is one somebody asked for (Skip):
    // it shows, but without the chime.
    quiet = true
    state = next
    quiet = false
    if (!ready) {
      lastPhase = Model.at(next, now).cycleIndex
      Qt.callLater(function() { focus.ready = true })
    }
  }

  // A drop-down left open by a widget that is folding away would hang under
  // nothing; close it.
  onSlimChanged: {
    var open = slim && bar ? bar.activePopout : null
    if (open && typeof open.close === "function") open.close()
  }

  // ── phase changes ───────────────────────────────────────────────────
  property int lastPhase: -1
  property bool ending: false
  property bool quiet: false
  onInfoChanged: {
    if (!info.active) {
      lastPhase = -1
      ending = false
      return
    }
    if (info.finished) {
      // The long break has run: end Focus mode, once.
      if (!ending) {
        ending = true
        chime()
        stop()
      }
      return
    }
    if (lastPhase === -1) {
      lastPhase = info.cycleIndex
      return
    }
    if (info.cycleIndex === lastPhase) return
    lastPhase = info.cycleIndex
    cue = Model.phaseName(info) + " · " + Model.timeLeft(info.remainingMs)
    cueTimer.restart()
    if (!quiet) chime()
    phaseChanged(info.phase)
  }

  Timer {
    id: cueTimer
    interval: 4000
    onTriggered: focus.cue = ""
  }

  function chime() {
    if (state.sound === false) return
    Quickshell.execDetached(["sh", "-c",
      'for f in /usr/share/sounds/freedesktop/stereo/complete.oga /usr/share/sounds/freedesktop/stereo/bell.oga; do ' +
      '[ -f "$f" ] || continue; command -v pw-play >/dev/null && exec pw-play --volume 0.6 "$f"; ' +
      'command -v paplay >/dev/null && exec paplay "$f"; exit 0; done'])
  }

  // ── the clock ───────────────────────────────────────────────────────
  // A laptop that sleeps through a round shouldn't wake to find the round
  // (and the break after it) gone: a tick that comes far later than it was
  // due means the machine was asleep, so Focus pauses at the last tick.
  property double lastTick: Date.now()
  readonly property int sleepGap: 120000
  // A Focus session left paused for 8 hours is a forgotten one; end it, so
  // Do Not Disturb isn't left on for good.
  readonly property double staleMs: 8 * 3600 * 1000

  Timer {
    id: clock
    running: focus.active
    repeat: true
    interval: focus.watchers > 0 && !focus.paused ? 1000 : Model.nextTick(focus.info, focus.ringLength, 1)
    onTriggered: {
      var t = Date.now()
      if (!focus.paused && t - focus.lastTick > interval + focus.sleepGap) {
        var asleepAt = focus.lastTick
        focus.lastTick = t
        focus.run(["pause", "--at", String(Math.round(asleepAt))])
        return
      }
      if (focus.paused && focus.state.pausedAt && t - focus.state.pausedAt > focus.staleMs) {
        focus.stop()
        return
      }
      focus.lastTick = t
      focus.now = t
    }
  }
}
