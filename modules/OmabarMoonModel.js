// Moon phase math for OmabarMoon, kept free of QML so it can be tested with
// node (tests/test_moon_model.py). Everything is computed locally from the
// date; there is no network call.
//
// The phase comes from Meeus, "Astronomical Algorithms" (2nd ed.), chapter 48:
// the Moon's phase angle from the mean elongation D and the Sun's and Moon's
// mean anomalies M and M', with the six largest periodic terms. That is good to
// about a quarter of a degree, so the lit share is right to well under 1% and
// the moments of new and full moon to within about half an hour.

var SYNODIC_DAYS = 29.530588853
var DAY_MS = 86400000

function rad(deg) { return deg * Math.PI / 180 }

function norm360(deg) {
  var d = deg % 360
  return d < 0 ? d + 360 : d
}

// Julian Ephemeris Day for a JavaScript time in milliseconds (UTC). The ~70 s
// between UT and TT moves the phase by a hundredth of a degree, so it is left
// out.
function julianDay(ms) { return ms / DAY_MS + 2440587.5 }

// Elongation of the Moon from the Sun, in degrees from 0 to 360: 0 is new,
// 90 first quarter, 180 full, 270 last quarter. Under 180 it is waxing.
function elongation(ms) {
  var t = (julianDay(ms) - 2451545.0) / 36525
  var d = norm360(297.8501921 + 445267.1114034 * t - 0.0018819 * t * t + t * t * t / 545868)
  var m = norm360(357.5291092 + 35999.0502909 * t - 0.0001536 * t * t)
  var mp = norm360(134.9633964 + 477198.8675055 * t + 0.0087414 * t * t + t * t * t / 69699)
  // Phase angle i (Sun-Moon-Earth); the elongation is its supplement, taken
  // on the side of D so waxing and waning stay apart.
  var i = 180 - d
    - 6.289 * Math.sin(rad(mp))
    + 2.100 * Math.sin(rad(m))
    - 1.274 * Math.sin(rad(2 * d - mp))
    - 0.658 * Math.sin(rad(2 * d))
    - 0.214 * Math.sin(rad(2 * mp))
    - 0.110 * Math.sin(rad(d))
  return norm360(180 - i)
}

// Share of the disc that is lit, 0..1.
function illumination(elong) { return (1 - Math.cos(rad(elong))) / 2 }

// The next moment after `ms` at which the elongation reaches `target` degrees
// (0 for new moon, 180 for full). Steps a quarter day, then bisects to the
// minute.
function nextReach(ms, target) {
  function ahead(t) { return norm360(elongation(t) - target) }
  var step = DAY_MS / 4
  var a = ms
  var prev = ahead(a)
  for (var n = 0; n < 4 * 32; n++) {
    var b = a + step
    var cur = ahead(b)
    // `ahead` climbs toward 360 and wraps to near 0 at the moment we want.
    if (cur < prev) {
      for (var k = 0; k < 20 && b - a > 60000; k++) {
        var mid = (a + b) / 2
        if (ahead(mid) < prev) b = mid
        else { a = mid; prev = ahead(a) }
      }
      return b
    }
    a = b
    prev = cur
  }
  return -1
}

// One of the eight phase names. New, first quarter, full and last quarter are
// moments; they are named for the day either side of them (about 12 degrees),
// and the stretches between get the crescent and gibbous names.
var NAMES = ["New moon", "Waxing crescent", "First quarter", "Waxing gibbous",
             "Full moon", "Waning gibbous", "Last quarter", "Waning crescent"]
var WINDOW = 360 / SYNODIC_DAYS  // one day of elongation, about 12.2 degrees

function phaseIndex(elong) {
  for (var q = 0; q < 4; q++) {
    var dist = Math.abs(norm360(elong - q * 90 + 180) - 180)
    if (dist <= WINDOW) return q * 2
  }
  return Math.floor(elong / 90) * 2 + 1
}

function phaseName(elong) { return NAMES[phaseIndex(elong)] }

// Geometry of the lit part for a disc of radius 1, drawn as two half-ellipse
// arcs from the top of the disc to the bottom and back:
//   litRight     - the limb (the outer half circle) is on the right
//   terminatorRx - the terminator's horizontal radius, 0..1
//   bulgeOut     - the terminator bows toward the limb (a crescent)
//                  rather than away from it (gibbous)
// In the northern hemisphere a waxing moon is lit on the right; south of the
// equator it is mirrored.
function shape(elong, south) {
  var waxing = elong < 180
  return {
    litRight: waxing !== !!south,
    terminatorRx: Math.abs(Math.cos(rad(elong))),
    bulgeOut: Math.cos(rad(elong)) > 0,
    lit: illumination(elong)
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    julianDay: julianDay,
    elongation: elongation,
    illumination: illumination,
    nextReach: nextReach,
    phaseIndex: phaseIndex,
    phaseName: phaseName,
    shape: shape
  }
}
