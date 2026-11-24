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
  id: controller

  property var bar: null

  readonly property string helper: String(Qt.resolvedUrl("../bin/omabar-focus")).replace(/^file:\/\//, "")
  readonly property string stateFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omabar/focus.json"

  // The state file as last read ("session", since Item already has a state).
  property var session: ({})
  property double now: Date.now()
  readonly property var info: Model.at(session, now)
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
  signal phaseBegan(string phase)

  function run(args) {
    Quickshell.execDetached([helper].concat(args))
  }
  function toggle() { run(["toggle"]) }
  function start() { run(["start"]) }
  function stop() { run(["stop"]) }
  function pause() { run(["pause"]) }
  function resume() { run(["resume"]) }
  function skip() { run(["skip"]) }

  function showCue(text, ms) {
    cue = text
    cueTimer.interval = ms || 4000
    cueTimer.restart()
  }

  FileView {
    id: store
    path: controller.stateFile
    printErrors: false
    watchChanges: true
    blockLoading: true
    onFileChanged: reload()
    onLoaded: controller.read(text())
    onLoadFailed: controller.read("")
  }

  // `session` and `now` change together here, so the phase is checked once,
  // after both, and never against the new clock with the old file (which,
  // after a long sleep, would look like the whole set had run out).
  property bool reading: false
  function read(text) {
    var next = {}
    try { next = JSON.parse(text || "{}") || {} } catch (e) { next = {} }
    if (typeof next !== "object" || Array.isArray(next)) next = {}
    reading = true
    session = next
    now = Date.now()
    lastTick = now
    reading = false
    if (!ready) {
      lastPhase = info.active ? info.cycleIndex : -1
      Qt.callLater(function() { controller.ready = true })
      return
    }
    // A change of phase from the file is one somebody asked for (Skip): it
    // shows, but without the chime.
    checkPhase(true)
  }

  // A drop-down left open by a widget that is folding away would hang under
  // nothing; close it. The clock's calendar and the Focus card stay.
  onSlimChanged: {
    var open = slim && bar ? bar.activePopout : null
    if (!open || typeof open.close !== "function") return
    var keeps = bar.omabarFocusKeeps || []
    if (keeps.indexOf(String(open.moduleName || "")) === -1) open.close()
  }

  // ── phase changes ───────────────────────────────────────────────────
  property int lastPhase: -1
  property bool ending: false
  onInfoChanged: if (!reading && ready) checkPhase(false)

  function checkPhase(quiet) {
    if (!info.active) {
      lastPhase = -1
      ending = false
      return
    }
    if (info.finished) {
      // The long break has run: end Focus mode, once.
      if (!ending) {
        ending = true
        if (!quiet) chime()
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
    showCue(Model.phaseName(info) + " · " + Model.timeLeft(info.remainingMs), 4000)
    if (!quiet) chime()
    phaseBegan(info.phase)
  }

  Timer {
    id: cueTimer
    interval: 4000
    onTriggered: controller.cue = ""
  }

  function chime() {
    if (session.sound === false) return
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
    running: controller.active
    repeat: true
    interval: controller.watchers > 0 && !controller.paused ? 1000 : Model.nextTick(controller.info, controller.ringLength, 1)
    onTriggered: {
      var t = Date.now()
      if (!controller.paused && t - controller.lastTick > interval + controller.sleepGap) {
        // `now` stays where it was until the paused file comes back, so
        // nothing runs ahead in the meantime.
        var asleepAt = controller.lastTick
        controller.lastTick = t
        controller.showCue("Paused while away", 15000)
        controller.run(["pause", "--at", String(Math.round(asleepAt))])
        return
      }
      if (controller.paused && controller.session.pausedAt && t - controller.session.pausedAt > controller.staleMs) {
        controller.stop()
        return
      }
      controller.lastTick = t
      controller.now = t
    }
  }
}
