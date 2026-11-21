// Battery logic for OmabarBattery, kept free of QML so it can be tested with
// node (tests/test_battery_model.js).
//
// A battery here is a plain object:
//   { name: "BAT1", percent: 0..100, energy: Wh, capacity: Wh,
//     state: "charging" | "discharging" | "full" | "pending" | "empty" | "unknown" }
//
// ThinkPads with a removable pack (T480, T470, T460...) report two laptop
// batteries: BAT0 is the internal one, BAT1 the removable rear one. The
// firmware drains the removable pack first and charges the internal one first.

function percentOf(battery) {
  if (!battery) return -1
  var p = Number(battery.percent)
  if (isNaN(p)) return -1
  return Math.max(0, Math.min(100, Math.round(p)))
}

// Split the laptop batteries into { external, internal }. `externalName` is
// the sysfs name of the removable pack (BAT1 on a ThinkPad). With one
// battery, it is the internal one. With two and neither named, the second in
// name order is the external one.
function split(batteries, externalName) {
  var list = (Array.isArray(batteries) ? batteries : []).filter(function(b) { return !!b })
  list.sort(function(a, b) { return String(a.name).localeCompare(String(b.name)) })
  var wanted = String(externalName || "BAT1")
  var external = null
  for (var i = 0; i < list.length; i++) {
    if (String(list[i].name) === wanted) { external = list[i]; break }
  }
  if (!external && list.length >= 2) external = list[list.length - 1]
  var internal = null
  for (var j = 0; j < list.length; j++) {
    if (list[j] !== external) { internal = list[j]; break }
  }
  return { external: external, internal: internal }
}

// Which battery the bar shows. The removable pack leads until it is spent,
// then the internal one takes over. On battery power the one actually
// discharging wins, so a firmware that stops the external pack at a few
// percent still hands over to the internal one.
function focus(pair, onBattery) {
  var ext = pair ? pair.external : null
  var int_ = pair ? pair.internal : null
  if (!ext) return int_ ? "internal" : ""
  if (!int_) return "external"
  if (onBattery) {
    if (ext.state === "discharging") return "external"
    if (int_.state === "discharging") return "internal"
  }
  return percentOf(ext) > 0 ? "external" : "internal"
}

// Combined charge across both packs, weighted by how much each one holds.
function totalPercent(pair) {
  var list = [pair ? pair.external : null, pair ? pair.internal : null].filter(function(b) { return !!b })
  if (list.length === 0) return -1
  var energy = 0, capacity = 0
  for (var i = 0; i < list.length; i++) {
    var e = Number(list[i].energy), c = Number(list[i].capacity)
    if (!(c > 0) || isNaN(e)) { energy = -1; break }
    energy += e
    capacity += c
  }
  if (energy >= 0 && capacity > 0) return Math.max(0, Math.min(100, Math.round(energy / capacity * 100)))
  var sum = 0
  for (var j = 0; j < list.length; j++) sum += Math.max(0, percentOf(list[j]))
  return Math.round(sum / list.length)
}

function stateLabel(battery, inUse) {
  if (!battery) return "Not inserted"
  switch (battery.state) {
    case "charging": return "Charging"
    case "full": return "Full"
    case "pending": return "Holding"
    case "empty": return "Empty"
    case "discharging": return inUse ? "In use" : "Standby"
    default: return inUse ? "In use" : "Standby"
  }
}

var DISCHARGE_ICONS = ["\u{F007A}", "\u{F007B}", "\u{F007C}", "\u{F007D}", "\u{F007E}", "\u{F007F}", "\u{F0080}", "\u{F0081}", "\u{F0082}", "\u{F0079}"]
var CHARGE_ICONS = ["\u{F089C}", "\u{F0086}", "\u{F0087}", "\u{F0088}", "\u{F089D}", "\u{F0089}", "\u{F089E}", "\u{F008A}", "\u{F008B}", "\u{F0085}"]

function icon(percent, charging) {
  if (percent < 0) return "\u{F0091}"
  var index = Math.max(0, Math.min(9, Math.floor(percent / 10)))
  return (charging ? CHARGE_ICONS : DISCHARGE_ICONS)[index]
}

function formatMinutes(seconds) {
  var s = Number(seconds)
  if (!(s > 0)) return ""
  var minutes = Math.round(s / 60)
  if (minutes < 60) return minutes + " min"
  var h = Math.floor(minutes / 60), m = minutes % 60
  return m === 0 ? h + " h" : h + " h " + m + " min"
}

if (typeof module !== "undefined") {
  module.exports = {
    percentOf: percentOf,
    split: split,
    focus: focus,
    totalPercent: totalPercent,
    stateLabel: stateLabel,
    icon: icon,
    formatMinutes: formatMinutes
  }
}
