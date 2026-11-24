// Focus mode logic for Omabar, kept free of QML so it can be tested with node
// (tests/test_focus_model.py). bin/omabar-focus has the same schedule in
// Python; the tests check that the two agree.
//
// Focus mode is a Pomodoro: focus, short break, focus, short break ... and a
// long break after the last round, then it starts over. Its state is a few
// timestamps in a JSON file (bin/omabar-focus writes it), so the phase is
// worked out from the clock and a shell restart picks up where it was:
//
//   { active: true, startedAt: <ms>, pausedAt: <ms> | null, pausedMs: <ms>,
//     focus: 25, shortBreak: 5, longBreak: 15, rounds: 4, repeat: false }
//
// Minutes. pausedMs is the time the clock leaves out: time spent paused,
// less any time skipped, so it can go below zero.

var DEFAULTS = { focus: 25, shortBreak: 5, longBreak: 15, rounds: 4 }

function num(value, fallback, low, high) {
  var n = Number(value)
  if (!isFinite(n) || n < low) return fallback
  return Math.min(high, n)
}

function config(state) {
  var s = state || {}
  return {
    focus: num(s.focus, DEFAULTS.focus, 1, 240),
    shortBreak: num(s.shortBreak, DEFAULTS.shortBreak, 1, 120),
    longBreak: num(s.longBreak, DEFAULTS.longBreak, 1, 120),
    rounds: Math.round(num(s.rounds, DEFAULTS.rounds, 1, 12)),
    repeat: s.repeat === true
  }
}

// One cycle of phases: [{ phase: "focus" | "break", round, long, ms }].
function cycle(state) {
  var c = config(state)
  var out = []
  for (var r = 1; r <= c.rounds; r++) {
    out.push({ phase: "focus", round: r, long: false, ms: c.focus * 60000 })
    var last = r === c.rounds
    out.push({ phase: "break", round: r, long: last, ms: (last ? c.longBreak : c.shortBreak) * 60000 })
  }
  return out
}

// Focus time that has run, paused time left out.
function elapsed(state, now) {
  if (!state || !state.active) return 0
  var started = Number(state.startedAt) || 0
  var until = state.pausedAt ? Number(state.pausedAt) : Number(now)
  return Math.max(0, until - started - (Number(state.pausedMs) || 0))
}

// Where Focus mode is at `now` (ms since the epoch):
//   { active, paused, finished, phase, round, rounds, long, lengthMs, elapsedMs,
//     remainingMs, progress (0..1 of the phase gone), cycleIndex }
function at(state, now) {
  if (!state || !state.active || !state.startedAt) {
    return { active: false, paused: false, finished: false, phase: "", round: 0, rounds: 0, long: false,
             lengthMs: 0, elapsedMs: 0, remainingMs: 0, progress: 0, cycleIndex: 0 }
  }
  var phases = cycle(state)
  var total = 0
  for (var i = 0; i < phases.length; i++) total += phases[i].ms
  var t = elapsed(state, now)
  var cycles = Math.floor(t / total)
  // Unless it repeats, Focus mode is over once the long break has run.
  var finished = !config(state).repeat && cycles >= 1
  if (finished) { cycles = 0; t = total }
  var inCycle = t - cycles * total
  var index = 0
  while (index < phases.length - 1 && inCycle >= phases[index].ms) {
    inCycle -= phases[index].ms
    index++
  }
  var p = phases[index]
  return {
    active: true,
    paused: !!state.pausedAt,
    finished: finished,
    phase: p.phase,
    round: p.round,
    rounds: phases.length / 2,
    long: p.long,
    lengthMs: p.ms,
    elapsedMs: inCycle,
    remainingMs: Math.max(0, p.ms - inCycle),
    progress: Math.max(0, Math.min(1, inCycle / p.ms)),
    // Counts every phase since Focus began, so a change of phase is a change
    // of this number, even when the cycle wraps round.
    cycleIndex: cycles * phases.length + index
  }
}

// "18 min", or "45 s" in the last minute.
function timeLeft(ms) {
  var s = Math.max(0, Math.ceil(ms / 1000))
  if (s < 60) return s + " s"
  return Math.ceil(s / 60) + " min"
}

// "18:42", for the card's big number.
function clock(ms) {
  var s = Math.max(0, Math.ceil(ms / 1000))
  var m = Math.floor(s / 60)
  var r = s % 60
  return m + ":" + (r < 10 ? "0" : "") + r
}

function phaseName(info) {
  if (!info || !info.active) return "Focus"
  if (info.phase === "focus") return "Focus"
  return info.long ? "Long break" : "Break"
}

// "Focus 2 of 4 · 18 min left", "Break · 4 min left", "Paused · Focus 2 of 4".
function summary(info) {
  if (!info || !info.active) return "Focus mode is off"
  var name = info.phase === "focus" ? "Focus " + info.round + " of " + info.rounds : phaseName(info)
  if (info.paused) return "Paused · " + name + " · " + timeLeft(info.remainingMs) + " left"
  return name + " · " + timeLeft(info.remainingMs) + " left"
}

// How long until the ring should next move by about `pixels` along a path of
// `length` pixels, or the phase ends: the bar is redrawn only that often, so
// there is no running animation. Never under a second or over a minute.
function nextTick(info, length, pixels) {
  if (!info || !info.active || info.paused) return 60000
  var per = info.lengthMs / Math.max(1, length / Math.max(0.25, pixels || 1))
  var wait = Math.min(per, info.remainingMs + 50)
  return Math.max(1000, Math.min(60000, Math.round(wait)))
}

// Points along a rounded rectangle's outline (x, y, w, h, corner radius r),
// from the middle of the top edge clockwise, for `fraction` (0..1) of the
// way round. `step` is the most a segment of a corner may span, in pixels.
function outline(x, y, w, h, r, fraction, step) {
  var f = Math.max(0, Math.min(1, Number(fraction) || 0))
  r = Math.max(0, Math.min(r, w / 2, h / 2))
  var sx = w - 2 * r
  var sy = h - 2 * r
  var arc = Math.PI * r / 2
  // Each piece: a straight edge or a quarter turn, in clockwise order from
  // the top middle.
  var cx0 = x + w - r, cy0 = y + r          // top right corner's centre
  var cx1 = x + w - r, cy1 = y + h - r      // bottom right
  var cx2 = x + r, cy2 = y + h - r          // bottom left
  var cx3 = x + r, cy3 = y + r              // top left
  var pieces = [
    { line: [x + w / 2, y, cx0, y], len: sx / 2 },
    { arc: [cx0, cy0, -Math.PI / 2], len: arc },
    { line: [x + w, cy0, x + w, cy1], len: sy },
    { arc: [cx1, cy1, 0], len: arc },
    { line: [cx1, y + h, cx2, y + h], len: sx },
    { arc: [cx2, cy2, Math.PI / 2], len: arc },
    { line: [x, cy2, x, cy3], len: sy },
    { arc: [cx3, cy3, Math.PI], len: arc },
    { line: [cx3, y, x + w / 2, y], len: sx / 2 }
  ]
  var total = 0
  for (var i = 0; i < pieces.length; i++) total += pieces[i].len
  var want = total * f
  var pts = [{ x: x + w / 2, y: y }]
  var seg = Math.max(0.5, Number(step) || 2)
  for (var j = 0; j < pieces.length && want > 0; j++) {
    var piece = pieces[j]
    var take = Math.min(piece.len, want)
    want -= take
    if (piece.len <= 0) continue
    var part = take / piece.len
    if (piece.line) {
      var l = piece.line
      pts.push({ x: l[0] + (l[2] - l[0]) * part, y: l[1] + (l[3] - l[1]) * part })
    } else {
      var a = piece.arc
      var n = Math.max(1, Math.ceil(take / seg))
      for (var k = 1; k <= n; k++) {
        var angle = a[2] + (Math.PI / 2) * part * k / n
        pts.push({ x: a[0] + r * Math.cos(angle), y: a[1] + r * Math.sin(angle) })
      }
    }
  }
  return pts
}

// The part of the outline between `from` and `to` (0..1, clockwise from the
// middle of the top edge).
function outlineRange(x, y, w, h, r, from, to, step) {
  var a = Math.max(0, Math.min(1, Number(from) || 0))
  var pts = outline(x, y, w, h, r, to, step)
  if (a <= 0 || pts.length < 2) return pts
  var skip = outlineLength(w, h, r) * a
  for (var i = 1; i < pts.length; i++) {
    var dx = pts[i].x - pts[i - 1].x
    var dy = pts[i].y - pts[i - 1].y
    var len = Math.sqrt(dx * dx + dy * dy)
    if (len >= skip) {
      var t = len > 0 ? skip / len : 0
      return [{ x: pts[i - 1].x + dx * t, y: pts[i - 1].y + dy * t }].concat(pts.slice(i))
    }
    skip -= len
  }
  return [pts[pts.length - 1]]
}

// The outline's whole length, for nextTick.
function outlineLength(w, h, r) {
  r = Math.max(0, Math.min(r, w / 2, h / 2))
  return 2 * (w - 2 * r) + 2 * (h - 2 * r) + 2 * Math.PI * r
}

if (typeof module !== "undefined") {
  module.exports = {
    DEFAULTS: DEFAULTS,
    config: config,
    cycle: cycle,
    elapsed: elapsed,
    at: at,
    timeLeft: timeLeft,
    clock: clock,
    phaseName: phaseName,
    summary: summary,
    nextTick: nextTick,
    outline: outline,
    outlineRange: outlineRange,
    outlineLength: outlineLength
  }
}
