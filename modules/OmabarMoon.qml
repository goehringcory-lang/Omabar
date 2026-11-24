// Omabar moon: a small disc after the clock's date, lit the way tonight's moon
// is. The phase is worked out on this computer from the date (see
// OmabarMoonModel.js); nothing is fetched. The lit part is drawn as vector
// curves, so its edge stays smooth, and both sides take the theme's
// foreground color, kept a step quieter than the clock.
// Hover it for the phase name, how much is lit, and when the next full or new
// moon is.
import QtQuick
import QtQuick.Shapes
import "OmabarMoonModel.js" as Model

Item {
  id: root

  property var bar
  // The time to show; the clock passes its own minute-ticking date.
  property date when: new Date()
  property color ink: "white"
  property bool south: false
  property bool twelveHour: true
  // While the clock's calendar is open the tooltip stays away.
  property bool suppressTooltip: false
  // Kept even, so the disc's center falls on a pixel corner.
  property int diameter: 12

  // The moon's elongation moves about half a degree an hour, so it is
  // recomputed every ten minutes rather than every tick of the clock.
  readonly property real stamp: Math.floor(when.getTime() / 600000) * 600000
  readonly property real elongation: Model.elongation(stamp)
  readonly property int phase: Model.phaseIndex(elongation)
  readonly property var geometry: Model.shape(elongation, south)

  // The item is as tall as the bar, so the tooltip lands below the bar and
  // the hover target is generous; the disc sits centered in it.
  implicitWidth: diameter
  implicitHeight: diameter

  function tint(alpha) { return Qt.rgba(ink.r, ink.g, ink.b, alpha) }

  // The lit part as an SVG path: the limb (half the disc's edge) from top to
  // bottom, then the terminator (half an ellipse) back up. Within a day of new
  // moon nothing is lit and within a day of full the whole disc is; between,
  // the crescent or the dark sliver is kept at least a pixel wide so it never
  // smears into a sub-pixel haze.
  readonly property string litPath: {
    var r = diameter / 2
    var c = r
    var top = (c - r) + "", bottom = (c + r) + ""
    if (phase === 0) return ""
    if (phase === 4) {
      return "M " + c + " " + top + " A " + r + " " + r + " 0 1 1 " + c + " " + bottom
        + " A " + r + " " + r + " 0 1 1 " + c + " " + top + " Z"
    }
    var rx = Math.min(r - 1, r * geometry.terminatorRx)
    var limbSweep = geometry.litRight ? 1 : 0
    var termSweep = geometry.litRight === geometry.bulgeOut ? 0 : 1
    var path = "M " + c + " " + top + " A " + r + " " + r + " 0 0 " + limbSweep + " " + c + " " + bottom
    if (rx < 0.3) path += " L " + c + " " + top
    else path += " A " + rx + " " + r + " 0 0 " + termSweep + " " + c + " " + top
    return path + " Z"
  }

  Shape {
    id: disc
    width: root.diameter
    height: root.diameter
    x: Math.round((root.width - width) / 2)
    y: Math.round((root.height - height) / 2)
    preferredRendererType: Shape.CurveRenderer

    // The dark side: a faint full disc, no rim.
    ShapePath {
      fillColor: root.tint(0.20)
      strokeColor: "transparent"
      strokeWidth: 0
      PathAngleArc {
        centerX: root.diameter / 2; centerY: root.diameter / 2
        radiusX: root.diameter / 2; radiusY: root.diameter / 2
        startAngle: 0; sweepAngle: 360
      }
    }

    ShapePath {
      fillColor: root.litPath === "" ? "transparent" : root.tint(0.80)
      strokeColor: "transparent"
      strokeWidth: 0
      PathSvg { path: root.litPath === "" ? "M 0 0" : root.litPath }
    }
  }

  // English names, like the clock's own date text.
  readonly property var dayNames: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  readonly property var monthNames: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

  function timeText(d) {
    var m = (d.getMinutes() < 10 ? "0" : "") + d.getMinutes()
    if (!twelveHour) return (d.getHours() < 10 ? "0" : "") + d.getHours() + ":" + m
    var h = d.getHours() % 12 === 0 ? 12 : d.getHours() % 12
    return h + ":" + m + (d.getHours() < 12 ? " AM" : " PM")
  }

  function dayText(d) {
    var now = new Date(stamp)
    if (d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() && d.getDate() === now.getDate())
      return "today"
    return dayNames[d.getDay()] + " " + d.getDate() + " " + monthNames[d.getMonth()]
  }

  readonly property string tooltipText: {
    var lit = Math.round(geometry.lit * 100)
    var line = Model.phaseName(elongation) + ", " + lit + "% lit"
    var waxing = elongation < 180
    // Just before an exact new or full moon, say when it is exact; otherwise
    // name the next full (while waxing) or new (while waning) moon.
    var exactAhead = (phase === 4 && waxing) || (phase === 0 && !waxing)
    var next = Model.nextReach(stamp, waxing ? 180 : 0)
    if (next < 0) return line
    var d = new Date(next)
    var label = exactAhead ? "Exact " : (waxing ? "Full moon " : "New moon ")
    return line + "\n" + label + dayText(d) + " at " + timeText(d)
  }

  readonly property bool tooltipHovered: hover.hovered
  function syncTooltip() {
    if (!bar || typeof bar.showTooltip !== "function") return
    if (hover.hovered && !suppressTooltip) bar.showTooltip(root, tooltipText)
    else bar.hideTooltip(root)
  }
  onTooltipTextChanged: if (hover.hovered) syncTooltip()
  onSuppressTooltipChanged: syncTooltip()

  HoverHandler {
    id: hover
    onHoveredChanged: root.syncTooltip()
  }
}
