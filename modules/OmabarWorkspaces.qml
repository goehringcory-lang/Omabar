// Omabar workspaces: a row of dots, with the workspace on screen stretched into
// a glossy accent pill. Workspace numbering and focusing follow Omarchy's
// built-in workspaces widget (one block of ten per monitor).
//
// Switching workspaces pulls a glossy drop of water out of the old pill: a
// liquid neck stretches and pinches off, the teardrop glides along the row
// shedding fine wake beads, and impact throws a directional splash crown,
// arcing droplets, dual ripples and a damped liquid slosh into the new pill.
// All liquid shades derive from the active theme's accent color; Omarchy's
// "reduce motion" setting turns the motion off.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons

Item {
  id: root

  property var bar
  property string moduleName
  property var settings: ({})

  readonly property int slots: 10
  // How many of the monitor's own workspaces always show, used or not.
  readonly property int persistent: {
    var n = settings ? Number(settings.persistent) : NaN
    return isFinite(n) && n >= 1 ? Math.min(Math.floor(n), slots) : 5
  }
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : 34
  readonly property color ink: bar ? bar.barForeground : Commons.Color.foreground

  // Theme accent and derived water shades so the liquid looks glossy and
  // dimensional on every Omarchy theme (light, dark, warm or cool).
  property color accent: Commons.Color.accent
  Behavior on accent { ColorAnimation { duration: Style.duration(250); easing.type: Easing.OutCubic } }
  readonly property real accentLuma: 0.2126 * accent.r + 0.7152 * accent.g + 0.0722 * accent.b
  readonly property color accentDeep: Qt.darker(accent, accentLuma > 0.65 ? 1.28 : 1.38)
  readonly property color accentBright: Qt.lighter(accent, accentLuma > 0.70 ? 1.18 : 1.35)
  readonly property color accentCaustic: Qt.rgba(
    Math.min(1, accent.r * 0.55 + 0.45),
    Math.min(1, accent.g * 0.55 + 0.45),
    Math.min(1, accent.b * 0.55 + 0.45),
    1.0
  )
  readonly property color accentSpec: Qt.rgba(
    Math.min(1, accent.r * 0.14 + 0.86),
    Math.min(1, accent.g * 0.14 + 0.86),
    Math.min(1, accent.b * 0.14 + 0.86),
    1.0
  )
  onAccentChanged: if (root.fxActive) liquidCanvas.requestPaint()

  readonly property int dot: Math.max(6, Math.round(barSize * 0.2))
  readonly property int pillLength: dot * 3 + Style.space(2)
  readonly property int gap: Style.space(7)

  readonly property var monitor: {
    var window = root.QsWindow.window
    var screen = window ? window.screen : null
    return screen ? Hyprland.monitorFor(screen) : Hyprland.focusedMonitor
  }
  readonly property string monitorName: monitor ? monitor.name : ""

  property var blocks: ({})

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/monitor-workspaces"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.readBlocks(text())
    onLoadFailed: root.readBlocks("")
  }

  function readBlocks(text) {
    var next = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var fields = lines[i].split("\t")
      if (fields.length >= 3 && fields[1] !== "") next[fields[1]] = parseInt(fields[0], 10)
    }
    root.blocks = next
  }

  function blockOf(id) { return Math.floor((id - 1) / root.slots) }
  function slotOf(id) { return (id - 1) % root.slots + 1 }

  function activeId() {
    return root.monitor && root.monitor.activeWorkspace ? root.monitor.activeWorkspace.id : -1
  }

  readonly property int block: {
    var b = root.blocks[root.monitorName]
    if (b !== undefined) return b
    var active = root.activeId()
    return active > 0 ? root.blockOf(active) : 0
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) if (values[i].id === id) return values[i]
    return null
  }

  // The monitor's own first few, and any of the rest that exist. After them
  // come workspaces that are only visiting: those of an unplugged monitor,
  // which Hyprland parks on this one.
  readonly property var ids: {
    var base = root.block * root.slots
    var list = []
    var guests = []
    for (var n = 1; n <= root.persistent; n++) list.push(base + n)
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id <= 0) continue
      if (root.blockOf(id) === root.block) {
        if (list.indexOf(id) === -1) list.push(id)
      } else if (values[i].monitor && values[i].monitor.name === root.monitorName) {
        guests.push(id)
      }
    }
    list.sort(function(a, b) { return a - b })
    guests.sort(function(a, b) { return a - b })
    return list.concat(guests)
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    var expr = root.blockOf(id) === root.block
      ? "o.workspaces.focus(" + root.slotOf(id) + ", \"" + root.monitorName + "\")"
      : "hl.dsp.focus({ workspace = \"" + id + "\" })"
    root.bar.run("hyprctl dispatch " + Util.shellQuote(expr))
  }

  property real wheelAccumulator: 0
  function scroll(delta) {
    var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
    root.wheelAccumulator = wheel.remainder
    if (wheel.steps === 0) return
    var index = root.ids.indexOf(root.activeId())
    if (index === -1) return
    var target = root.ids[Util.clamp(index - wheel.steps, 0, root.ids.length - 1)]
    if (target !== root.ids[index]) root.focusWorkspace(target)
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      var switched = name === "workspacev2" && root.monitor !== null && root.monitor.focused
      if (switched || name === "moveworkspacev2" || name === "changeworkspaceid") {
        Hyprland.refreshMonitors()
        Hyprland.refreshWorkspaces()
      }
    }
  }

  // ── liquid water drop & splash simulation ─────────────────────────────
  // The pill is drawn on the workspace the drop has landed on, which trails
  // the real active workspace by one flight. All transient liquid effects
  // (metaball takeoff neck, glossy teardrop, wake beads, splash crown,
  // ballistic droplets and dual ripples) render in one Canvas driven at the
  // display's refresh rate only while motion is active.
  readonly property int currentId: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
  property int landedId: -1
  property bool fxActive: false
  property bool flightActive: false
  property int flightFrom: -1
  property int flightTo: -1
  property point flightStart: Qt.point(0, 0)
  property point flightLastEnd: Qt.point(0, 0)
  property real flightElapsed: 0
  property real flightDuration: 0.22
  property real flightMomentum: 1.0
  property real dropX: 0
  property real dropY: 0
  property real dropDir: 1
  property real dropSpeed: 0
  property real dropU: 0
  property bool neckPinched: false
  property real wakeTimer: 0
  property var _particles: []
  property var _ripples: []
  property var _crowns: []

  onCurrentIdChanged: launch(currentId)
  Component.onCompleted: landedId = currentId
  onVisibleChanged: if (!visible && root.fxActive) root.resetFx()

  function clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v) }

  function smoothstep(e0, e1, x) {
    var t = clamp((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)
  }

  function rgba(c, a) {
    return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + clamp(a, 0, 1) + ")"
  }

  function centerOf(id) {
    var index = root.ids.indexOf(id)
    var item = index >= 0 ? cells.itemAt(index) : null
    return item ? item.mapToItem(root, item.width / 2, item.height / 2) : null
  }

  function updateFxActive() {
    var active = root.flightActive || root._particles.length > 0 || root._ripples.length > 0 || root._crowns.length > 0
    if (root.fxActive !== active) root.fxActive = active
  }

  function resetFx() {
    root.flightActive = false
    root.flightFrom = -1
    root.flightTo = -1
    root._particles = []
    root._ripples = []
    root._crowns = []
    root.landedId = root.currentId
    root.fxActive = false
  }

  function launch(target) {
    if (target < 0 || Style.reduceMotion || !root.visible) {
      root.resetFx()
      root.landedId = target
      return
    }
    var end = root.centerOf(target)

    // Mid-flight redirect: steer the live drop smoothly toward the new target
    // without snapping or double-splashing intermediate workspaces.
    if (root.flightActive) {
      if (target === root.flightTo) return
      if (!end) {
        root.resetFx()
        root.landedId = target
        return
      }
      var dist = Math.hypot(end.x - root.dropX, end.y - root.dropY)
      root.flightFrom = -1
      root.flightTo = target
      root.flightStart = Qt.point(root.dropX, root.dropY)
      root.flightLastEnd = end
      root.flightElapsed = 0
      root.flightDuration = root.clamp(0.14 + dist / Math.max(1, root.dot * 28), 0.15, 0.30)
      root.flightMomentum = root.clamp(0.92 + dist / Math.max(1, root.dot * 16), 0.92, 1.42)
      root.dropDir = root.vertical
        ? (end.y >= root.dropY ? 1 : -1)
        : (end.x >= root.dropX ? 1 : -1)
      root.dropU = 0
      root.neckPinched = true
      root.wakeTimer = 0
      root.updateFxActive()
      liquidCanvas.requestPaint()
      return
    }

    var from = root.landedId
    var start = root.centerOf(from)
    if (from < 0 || from === target || !start || !end) {
      root.landedId = target
      return
    }

    var hops = Math.max(1, Math.abs(root.ids.indexOf(target) - root.ids.indexOf(from)))
    root.flightFrom = from
    root.flightTo = target
    root.flightStart = start
    root.flightLastEnd = end
    root.flightElapsed = 0
    root.flightDuration = Math.min(0.32, 0.175 + hops * 0.028)
    root.flightMomentum = Math.min(1.42, 0.88 + hops * 0.15)
    root.dropX = start.x
    root.dropY = start.y
    root.dropDir = root.vertical
      ? (end.y >= start.y ? 1 : -1)
      : (end.x >= start.x ? 1 : -1)
    root.dropSpeed = 0.25
    root.dropU = 0
    root.neckPinched = false
    root.wakeTimer = 0
    root.landedId = -1                 // the old pill lets go of its water
    root.flightActive = true
    root.updateFxActive()
    liquidCanvas.requestPaint()
  }

  function spawnWakeBead(x, y, dir, scale) {
    var cross = (Math.random() - 0.5) * root.dot * 0.36
    var driftBack = -dir * (root.dot * (1.2 + Math.random() * 1.4))
    var crossVel = (Math.random() - 0.5) * root.dot * 1.1
    root._particles.push({
      x: root.vertical ? x + cross : x - dir * root.dot * 0.65,
      y: root.vertical ? y - dir * root.dot * 0.65 : y + cross,
      vx: root.vertical ? crossVel : driftBack,
      vy: root.vertical ? driftBack : crossVel + 4,
      g: root.vertical ? 0 : 28,
      drag: 2.2,
      r: root.dot * (0.14 + Math.random() * 0.11) * scale,
      age: 0,
      life: 0.28 + Math.random() * 0.16,
      alpha: 0.85
    })
  }

  function land() {
    var targetId = root.flightTo
    var dir = root.dropDir
    var mom = root.flightMomentum
    root.flightActive = false
    root.flightFrom = -1
    root.landedId = targetId

    var index = root.ids.indexOf(targetId)
    var item = index >= 0 ? cells.itemAt(index) : null
    var at = root.centerOf(targetId) || root.flightLastEnd
    if (item) item.splash(dir)
    if (!at) {
      root.updateFxActive()
      return
    }

    // 1. Directional liquid splash crown right at impact.
    root._crowns.push({
      x: at.x,
      y: at.y,
      dir: dir,
      momentum: mom,
      age: 0,
      life: 0.23
    })

    // 2. Dual concentric ripples (primary crisp wave + delayed soft echo),
    // bounded cleanly inside the bar's cross-axis thickness.
    var maxCross = Math.max(root.dot * 0.9, root.barSize * 0.5 - 2.2)
    root._ripples.push({
      x: at.x, y: at.y,
      age: 0, delay: 0, life: 0.35,
      rAxis0: root.dot * 0.72, rCross0: root.dot * 0.52,
      rAxis1: root.dot * (2.45 + 0.25 * mom),
      rCross1: Math.min(maxCross, root.dot * 1.52),
      lineWidth: 1.75, alpha: 0.78, bright: true
    })
    root._ripples.push({
      x: at.x, y: at.y,
      age: 0, delay: 0.065, life: 0.43,
      rAxis0: root.dot * 0.62, rCross0: root.dot * 0.46,
      rAxis1: root.dot * (3.0 + 0.3 * mom),
      rCross1: Math.min(maxCross + 0.4, root.dot * 1.82),
      lineWidth: 1.2, alpha: 0.48, bright: false
    })

    // 3. Expressive directional spray droplets with ballistic gravity.
    // Forward-upper fan (5 beads), forward-lower fan (3 beads), rear mist (2 beads).
    function addSplashBead(angleRad, speed, r, life, gravity) {
      var along = Math.cos(angleRad) * speed * dir
      var across = Math.sin(angleRad) * speed
      root._particles.push({
        x: at.x + (root.vertical ? across : along) * 0.015,
        y: at.y + (root.vertical ? along : across) * 0.015,
        vx: root.vertical ? across : along,
        vy: root.vertical ? along : across,
        g: root.vertical ? 0 : gravity,
        drag: 1.35,
        r: r,
        age: 0,
        life: life,
        alpha: 0.94
      })
    }

    for (var i = 0; i < 5; i++) {
      var upDeg = 18 + i * 14.5 + (Math.random() - 0.5) * 7
      var upSpd = root.dot * (3.5 + Math.random() * 2.5) * mom
      var upR = root.dot * (0.16 + Math.random() * 0.16)
      addSplashBead(-upDeg * Math.PI / 180, upSpd, upR, 0.29 + Math.random() * 0.14, 128)
    }
    for (var j = 0; j < 3; j++) {
      var dnDeg = 18 + j * 16 + (Math.random() - 0.5) * 6
      var dnSpd = root.dot * (2.6 + Math.random() * 1.8) * mom
      var dnR = root.dot * (0.14 + Math.random() * 0.13)
      addSplashBead(dnDeg * Math.PI / 180, dnSpd, dnR, 0.25 + Math.random() * 0.12, 34)
    }
    for (var m = 0; m < 2; m++) {
      var backDeg = 116 + m * 24 + (Math.random() - 0.5) * 10
      var backSpd = root.dot * (2.1 + Math.random() * 1.2) * mom
      var backR = root.dot * (0.13 + Math.random() * 0.09)
      addSplashBead(-backDeg * Math.PI / 180, backSpd, backR, 0.23 + Math.random() * 0.10, 96)
    }

    root.updateFxActive()
  }

  function stepFx(rawDt) {
    if (Style.reduceMotion) {
      root.resetFx()
      return
    }
    var dt = root.clamp(rawDt, 0.001, 0.05)

    // Advance drop flight along a momentum-preserving cubic curve:
    // p(u) = 0.25u + 1.55u^2 - 0.80u^3  -> leaves promptly, glides fast, impacts with speed.
    if (root.flightActive) {
      root.flightElapsed += dt
      var u = root.clamp(root.flightElapsed / root.flightDuration, 0, 1)
      var end = root.centerOf(root.flightTo)
      if (end) root.flightLastEnd = end
      else end = root.flightLastEnd

      var anchor = root.flightFrom >= 0 ? root.centerOf(root.flightFrom) : null
      var startPt = anchor ? anchor : root.flightStart

      var pos = 0.25 * u + 1.55 * u * u - 0.80 * u * u * u
      var vel = 0.25 + 3.10 * u - 2.40 * u * u

      root.dropU = u
      root.dropSpeed = vel
      root.dropX = startPt.x + (end.x - startPt.x) * pos
      root.dropY = startPt.y + (end.y - startPt.y) * pos
      if (Math.abs(end.x - startPt.x) > 0.5 || Math.abs(end.y - startPt.y) > 0.5) {
        root.dropDir = root.vertical
          ? (end.y >= startPt.y ? 1 : -1)
          : (end.x >= startPt.x ? 1 : -1)
      }

      // Rayleigh-Plateau pinch-off bead right as the takeoff neck snaps.
      if (!root.neckPinched && root.flightFrom >= 0 && u >= 0.34) {
        root.neckPinched = true
        var pinchX = (startPt.x + root.dropX) * 0.5
        var pinchY = (startPt.y + root.dropY) * 0.5
        root.spawnWakeBead(pinchX, pinchY, root.dropDir, 0.95)
      }

      // Shed fine wake droplets along the glide.
      root.wakeTimer += dt
      if (u > 0.22 && u < 0.86 && root.wakeTimer >= 0.052) {
        root.wakeTimer = 0
        root.spawnWakeBead(root.dropX, root.dropY, root.dropDir, 0.85)
      }

      if (u >= 1) root.land()
    }

    // Advance particles with air drag, gravity, and bar-edge containment.
    var nextP = []
    var minCross = 2.6
    var maxCross = Math.max(minCross + 2, root.barSize - 2.6)
    for (var i = 0; i < root._particles.length; i++) {
      var p = root._particles[i]
      p.age += dt
      if (p.age >= p.life) continue
      var damp = Math.max(0, 1 - p.drag * dt)
      p.vx *= damp
      p.vy = p.vy * damp + p.g * dt
      p.x += p.vx * dt
      p.y += p.vy * dt
      var rNow = p.r * (1 - 0.55 * (p.age / p.life))
      if (root.vertical) {
        if (p.x < minCross + rNow) { p.x = minCross + rNow; p.vx = Math.abs(p.vx) * 0.25 }
        else if (p.x > maxCross - rNow) { p.x = maxCross - rNow; p.vx = -Math.abs(p.vx) * 0.25 }
      } else {
        if (p.y < minCross + rNow) { p.y = minCross + rNow; p.vy = Math.abs(p.vy) * 0.25 }
        else if (p.y > maxCross - rNow) { p.y = maxCross - rNow; p.vy = -Math.abs(p.vy) * 0.25 }
      }
      nextP.push(p)
    }
    root._particles = nextP

    // Advance ripples.
    var nextR = []
    for (var r = 0; r < root._ripples.length; r++) {
      var rp = root._ripples[r]
      rp.age += dt
      if (rp.age < rp.delay + rp.life) nextR.push(rp)
    }
    root._ripples = nextR

    // Advance splash crowns.
    var nextC = []
    for (var c = 0; c < root._crowns.length; c++) {
      var cr = root._crowns[c]
      cr.age += dt
      if (cr.age < cr.life) nextC.push(cr)
    }
    root._crowns = nextC

    root.updateFxActive()
    if (root.fxActive) liquidCanvas.requestPaint()
  }

  FrameAnimation {
    id: fxLoop
    running: root.fxActive && root.visible && !Style.reduceMotion
    onTriggered: root.stepFx(frameTime)
  }

  Canvas {
    id: liquidCanvas
    // Extend slightly along the bar axis so splashes on the first/last dot
    // never clip abruptly; stay strictly within barSize on the cross axis.
    readonly property int padX: root.vertical ? 0 : Math.round(root.barSize * 0.55)
    readonly property int padY: root.vertical ? Math.round(root.barSize * 0.55) : 0
    x: -padX
    y: -padY
    width: root.width + padX * 2
    height: root.height + padY * 2
    z: 2
    visible: root.fxActive
    antialiasing: true
    onAvailableChanged: if (available && root.fxActive) requestPaint()

    function strokeEllipse(ctx, cx, cy, rx, ry) {
      if (rx <= 0.1 || ry <= 0.1) return
      ctx.save()
      ctx.translate(cx, cy)
      ctx.scale(rx, ry)
      ctx.beginPath()
      ctx.arc(0, 0, 1, 0, Math.PI * 2)
      ctx.restore()
      ctx.stroke()
    }

    function fillEllipse(ctx, cx, cy, rx, ry) {
      if (rx <= 0.1 || ry <= 0.1) return
      ctx.save()
      ctx.translate(cx, cy)
      ctx.scale(rx, ry)
      ctx.beginPath()
      ctx.arc(0, 0, 1, 0, Math.PI * 2)
      ctx.restore()
      ctx.fill()
    }

    function drawSplashCrown(ctx, cr) {
      var k = root.clamp(cr.age / cr.life, 0, 1)
      var grow = Math.sin(Math.min(1, k * 1.55) * Math.PI * 0.5)
      var fade = Math.pow(1 - k, 1.35)
      if (fade <= 0.01) return

      var dir = cr.dir
      var mom = cr.momentum
      var maxCross = root.barSize - 3.0
      var crests = [
        { deg: -36, reach: root.dot * 1.48 * mom, thick: 0.95, curve:  0.22 },
        { deg:  34, reach: root.dot * 1.24 * mom, thick: 0.85, curve: -0.20 },
        { deg: -68, reach: root.dot * 1.20 * mom, thick: 0.78, curve:  0.16 },
        { deg: -132, reach: root.dot * 0.78 * mom, thick: 0.60, curve: -0.14 }
      ]

      for (var i = 0; i < crests.length; i++) {
        var c = crests[i]
        var ang = c.deg * Math.PI / 180
        var len = c.reach * grow
        if (len < 0.5) continue
        var uAlong = Math.cos(ang) * dir
        var uAcross = Math.sin(ang)
        var ux = root.vertical ? uAcross : uAlong
        var uy = root.vertical ? uAlong : uAcross
        var nx = -uy
        var ny = ux

        var tipX = cr.x + ux * len + nx * len * c.curve * 0.35
        var tipY = cr.y + uy * len + ny * len * c.curve * 0.35
        var midX = cr.x + ux * len * 0.52 + nx * len * c.curve * 0.15
        var midY = cr.y + uy * len * 0.52 + ny * len * c.curve * 0.15

        if (root.vertical) {
          tipX = root.clamp(tipX, 3.0, maxCross)
          midX = root.clamp(midX, 3.0, maxCross)
        } else {
          tipY = root.clamp(tipY, 3.0, maxCross)
          midY = root.clamp(midY, 3.0, maxCross)
        }

        var bw = root.dot * 0.34 * c.thick * (1 - 0.55 * k)
        var mw = bw * 0.42
        var b1x = cr.x + nx * bw, b1y = cr.y + ny * bw
        var b2x = cr.x - nx * bw, b2y = cr.y - ny * bw

        var grad = ctx.createLinearGradient(cr.x, cr.y, tipX, tipY)
        grad.addColorStop(0.0, root.rgba(root.accent, 0.85 * fade))
        grad.addColorStop(0.7, root.rgba(root.accentCaustic, 0.92 * fade))
        grad.addColorStop(1.0, root.rgba(root.accentSpec, 0.88 * fade))

        ctx.beginPath()
        ctx.moveTo(b1x, b1y)
        ctx.quadraticCurveTo(midX + nx * mw, midY + ny * mw, tipX, tipY)
        ctx.quadraticCurveTo(midX - nx * mw, midY - ny * mw, b2x, b2y)
        ctx.closePath()
        ctx.fillStyle = grad
        ctx.fill()
      }
    }

    function drawDrop(ctx) {
      var u = root.dropU
      var dir = root.dropDir
      var mom = root.flightMomentum
      var R = root.dot * 0.68
      var spd = Math.min(1.4, root.dropSpeed / 1.15) * mom
      var wobble = Math.sin(u * Math.PI * 3.5) * 0.075 * (1 - u * 0.4)
      var tailGrow = root.smoothstep(0.10, 0.48, u)

      var nose = R * (1.08 + 0.34 * spd + wobble)
      var tail = R * (0.95 + (0.45 + 1.05 * spd) * tailGrow - wobble * 0.6)
      var ry = R * (1.02 - 0.16 * spd - wobble * 0.65)

      // 1. Concave metaball liquid neck stretching out of the old workspace.
      if (root.flightFrom >= 0 && u < 0.38) {
        var anchor = root.centerOf(root.flightFrom) || root.flightStart
        var dist = Math.hypot(root.dropX - anchor.x, root.dropY - anchor.y)
        if (dist > 1.2) {
          var np = u / 0.38
          var rA = root.dot * 0.54 * (1 - 0.68 * np)
          var pinch = Math.pow(1 - np, 1.4)
          var neckH = Math.min(rA, ry) * 0.66 * pinch

          var ux = (root.dropX - anchor.x) / dist
          var uy = (root.dropY - anchor.y) / dist
          var nx = -uy
          var ny = ux
          var midX = (anchor.x + root.dropX) * 0.5
          var midY = (anchor.y + root.dropY) * 0.5
          var neckAlpha = 0.94 * (1 - 0.25 * np)

          var neckGrad = ctx.createLinearGradient(anchor.x, anchor.y, root.dropX, root.dropY)
          neckGrad.addColorStop(0.0, root.rgba(root.accentDeep, neckAlpha))
          neckGrad.addColorStop(0.55, root.rgba(root.accent, neckAlpha))
          neckGrad.addColorStop(1.0, root.rgba(root.accentCaustic, neckAlpha))

          ctx.beginPath()
          ctx.moveTo(anchor.x + nx * rA, anchor.y + ny * rA)
          ctx.quadraticCurveTo(midX + nx * neckH, midY + ny * neckH, root.dropX + nx * ry * 0.88, root.dropY + ny * ry * 0.88)
          ctx.lineTo(root.dropX - nx * ry * 0.88, root.dropY - ny * ry * 0.88)
          ctx.quadraticCurveTo(midX - nx * neckH, midY - ny * neckH, anchor.x - nx * rA, anchor.y - ny * rA)
          ctx.closePath()
          ctx.fillStyle = neckGrad
          ctx.fill()

          ctx.fillStyle = root.rgba(root.accent, neckAlpha)
          fillEllipse(ctx, anchor.x, anchor.y, rA, rA)
        }
      }

      // 2. Organic glossy teardrop body in local travel-aligned coordinates.
      ctx.save()
      ctx.translate(root.dropX, root.dropY)
      if (root.vertical) ctx.rotate(Math.PI * 0.5)

      function traceTeardrop(scale) {
        var n = nose * scale
        var tl = tail * scale
        var h = ry * scale
        var pNoseX = dir * n
        var pTopX = dir * n * 0.12
        var pTailX = -dir * tl

        ctx.beginPath()
        ctx.moveTo(pNoseX, 0)
        ctx.bezierCurveTo(pNoseX, -h * 0.80, pTopX + dir * n * 0.48, -h, pTopX, -h)
        ctx.bezierCurveTo(pTopX - dir * tl * 0.45, -h * 0.95, pTailX + dir * tl * 0.25, -h * 0.22, pTailX, 0)
        ctx.bezierCurveTo(pTailX + dir * tl * 0.25, h * 0.22, pTopX - dir * tl * 0.45, h * 0.95, pTopX, h)
        ctx.bezierCurveTo(pTopX + dir * n * 0.48, h, pNoseX, h * 0.80, pNoseX, 0)
        ctx.closePath()
      }

      // Soft outer wet glow.
      traceTeardrop(1.22)
      ctx.fillStyle = root.rgba(root.accent, 0.22)
      ctx.fill()

      // Main liquid body gradient (deeper rim -> vivid accent -> luminous lower caustic).
      var bodyGrad = ctx.createLinearGradient(0, -ry, dir * nose * 0.2, ry)
      bodyGrad.addColorStop(0.0, root.rgba(root.accentDeep, 0.96))
      bodyGrad.addColorStop(0.45, root.rgba(root.accent, 0.97))
      bodyGrad.addColorStop(1.0, root.rgba(root.accentCaustic, 0.98))

      traceTeardrop(1.0)
      ctx.fillStyle = bodyGrad
      ctx.fill()

      // Crisp luminous rim.
      ctx.lineWidth = 0.85
      ctx.strokeStyle = root.rgba(root.accentBright, 0.48)
      ctx.stroke()

      // Internal lower-leading caustic refraction sheen.
      ctx.fillStyle = root.rgba(root.accentCaustic, 0.52)
      fillEllipse(ctx, dir * nose * 0.14, ry * 0.36, nose * 0.52, ry * 0.30)

      // Upper-leading curved specular highlight + micro pinpoint glint.
      ctx.fillStyle = root.rgba(root.accentSpec, root.accentLuma > 0.78 ? 0.92 : 0.82)
      fillEllipse(ctx, dir * nose * 0.26, -ry * 0.42, nose * 0.36, ry * 0.21)

      ctx.fillStyle = root.rgba(root.accentSpec, 0.52)
      fillEllipse(ctx, -dir * tail * 0.18, -ry * 0.26, R * 0.14, R * 0.11)

      ctx.restore()
    }

    function drawParticles(ctx) {
      for (var i = 0; i < root._particles.length; i++) {
        var p = root._particles[i]
        var k = root.clamp(p.age / p.life, 0, 1)
        var r = p.r * (1 - 0.55 * k)
        if (r <= 0.25) continue
        var alpha = p.alpha * (1 - k * k)

        var spd = Math.hypot(p.vx, p.vy)
        var stretch = 1 + Math.min(0.48, spd / Math.max(1, root.dot * 12))

        ctx.save()
        ctx.translate(p.x, p.y)
        if (spd > 6) ctx.rotate(Math.atan2(p.vy, p.vx))

        // Glossy droplet body.
        ctx.fillStyle = root.rgba(root.accent, alpha)
        fillEllipse(ctx, 0, 0, r * stretch, r / Math.sqrt(stretch))

        // Bright caustic center + tiny specular glint on larger droplets.
        if (r > 0.95) {
          ctx.fillStyle = root.rgba(root.accentCaustic, alpha * 0.55)
          fillEllipse(ctx, r * 0.12, r * 0.18, r * 0.48, r * 0.32)
          ctx.fillStyle = root.rgba(root.accentSpec, alpha * 0.82)
          fillEllipse(ctx, -r * 0.18, -r * 0.30, r * 0.34, r * 0.24)
        }
        ctx.restore()
      }
    }

    onPaint: {
      if (width <= 0 || height <= 0) return
      var ctx = getContext("2d")
      if (!ctx) return
      ctx.clearRect(0, 0, width, height)
      ctx.save()
      ctx.translate(padX, padY)

      // 1. Dual concentric water ripples (behind the crown & droplets).
      for (var i = 0; i < root._ripples.length; i++) {
        var rp = root._ripples[i]
        if (rp.age < rp.delay) continue
        var k = root.clamp((rp.age - rp.delay) / rp.life, 0, 1)
        var ek = 1 - Math.pow(1 - k, 3)
        var rAxis = rp.rAxis0 + (rp.rAxis1 - rp.rAxis0) * ek
        var rCross = rp.rCross0 + (rp.rCross1 - rp.rCross0) * ek
        var rx = root.vertical ? rCross : rAxis
        var ry = root.vertical ? rAxis : rCross

        ctx.lineWidth = Math.max(0.4, rp.lineWidth * (1 - 0.55 * k))
        ctx.strokeStyle = root.rgba(rp.bright ? root.accentCaustic : root.accent, rp.alpha * (1 - k))
        strokeEllipse(ctx, rp.x, rp.y, rx, ry)
      }

      // 2. Impact splash crowns.
      for (var c = 0; c < root._crowns.length; c++) {
        drawSplashCrown(ctx, root._crowns[c])
      }

      // 3. Traveling glossy water drop & metaball neck.
      if (root.flightActive) drawDrop(ctx)

      // 4. Wake & ballistic splash droplets.
      drawParticles(ctx)

      ctx.restore()
    }
  }

  // Keep steady-state width/height fixed during flight so adjacent bar
  // widgets never jitter while the old pill shrinks and the new one lands.
  readonly property int steadySpan: root.ids.length > 0
    ? (root.ids.length - 1) * (root.dot + root.gap) + root.pillLength
    : 0
  implicitWidth: vertical ? barSize : Math.max(row.implicitWidth, steadySpan) + Style.space(6)
  implicitHeight: vertical ? Math.max(row.implicitHeight, steadySpan) + Style.space(6) : barSize

  WheelHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: function(event) { root.scroll(event.angleDelta.y || event.angleDelta.x) }
  }

  Grid {
    id: row
    anchors.centerIn: parent
    columns: root.vertical ? 1 : Math.max(1, root.ids.length)
    spacing: root.gap
    verticalItemAlignment: Grid.AlignVCenter
    horizontalItemAlignment: Grid.AlignHCenter

    Repeater {
      id: cells
      model: root.ids

      Item {
        id: cell
        required property int modelData
        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool shown: root.landedId === modelData
        readonly property bool urgent: workspace !== null && workspace.urgent === true
        property real surgeDir: 1
        property real surgeProgress: 1

        onShownChanged: {
          if (!shown && squash.running) {
            squash.stop()
            squashScale.xScale = 1
            squashScale.yScale = 1
          }
        }

        // Liquid impact bulge, spread and damped wobble when the drop lands here.
        function splash(dir) {
          cell.surgeDir = dir >= 0 ? 1 : -1
          squash.restart()
          surgeAnim.restart()
        }

        width: root.vertical ? root.barSize : pillBox.width
        height: root.vertical ? pillBox.height : root.barSize

        Item {
          id: pillBox
          anchors.centerIn: parent
          width: root.vertical ? root.dot : (cell.shown ? root.pillLength : root.dot)
          height: root.vertical ? (cell.shown ? root.pillLength : root.dot) : root.dot

          transform: Scale {
            id: squashScale
            origin.x: pillBox.width / 2
            origin.y: pillBox.height / 2
          }

          Behavior on width { NumberAnimation { duration: Style.duration(210); easing.type: Easing.OutBack; easing.overshoot: 1.25 } }
          Behavior on height { NumberAnimation { duration: Style.duration(210); easing.type: Easing.OutBack; easing.overshoot: 1.25 } }

          // Soft accent liquid glow under the resting active pill.
          RectangularShadow {
            anchors.fill: pill
            radius: pill.radius
            blur: Style.space(8)
            spread: 0
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, cell.shown && !cell.urgent ? 0.36 : 0.0)
            visible: cell.shown && !cell.urgent
            Behavior on color { ColorAnimation { duration: Style.duration(200) } }
          }

          Rectangle {
            id: pill
            anchors.fill: parent
            radius: root.dot / 2
            color: cell.urgent ? Commons.Color.urgent
              : cell.shown ? root.accent
              : root.ink
            opacity: cell.shown || cell.urgent ? 1.0
              : hover.hovered ? 0.85
              : cell.occupied ? 0.6 : 0.22

            Behavior on opacity { NumberAnimation { duration: Style.duration(180) } }
            Behavior on color { ColorAnimation { duration: Style.duration(160) } }

            // Lower internal caustic sheen so the resting pill shares the same
            // liquid depth as the traveling water drop.
            Rectangle {
              anchors.fill: parent
              radius: parent.radius
              visible: cell.shown && !cell.urgent
              gradient: Gradient {
                orientation: root.vertical ? Gradient.Horizontal : Gradient.Vertical
                GradientStop { position: 0.0; color: Qt.rgba(root.accentDeep.r, root.accentDeep.g, root.accentDeep.b, 0.28) }
                GradientStop { position: 0.45; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.rgba(root.accentCaustic.r, root.accentCaustic.g, root.accentCaustic.b, 0.36) }
              }
            }

            // Soft glossy top meniscus highlight along the active liquid pill.
            Rectangle {
              visible: cell.shown && !cell.urgent
              width: root.vertical ? Math.max(1.5, parent.width * 0.28) : parent.width * 0.68
              height: root.vertical ? parent.height * 0.68 : Math.max(1.5, parent.height * 0.28)
              x: root.vertical ? parent.width * 0.16 : (parent.width - width) * 0.5
              y: root.vertical ? (parent.height - height) * 0.5 : parent.height * 0.14
              radius: Math.min(width, height) / 2
              gradient: Gradient {
                orientation: root.vertical ? Gradient.Vertical : Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Qt.rgba(root.accentSpec.r, root.accentSpec.g, root.accentSpec.b, root.accentLuma > 0.78 ? 0.68 : 0.52) }
                GradientStop { position: 1.0; color: "transparent" }
              }
            }

            // Directional impact wave surge washing across the pill on landing.
            Rectangle {
              visible: cell.shown && !cell.urgent && cell.surgeProgress < 1
              readonly property real waveSpan: (root.vertical ? parent.height : parent.width) * 0.46
              readonly property real travel: Math.max(0, (root.vertical ? parent.height : parent.width) - waveSpan)
              readonly property real k: cell.surgeDir >= 0 ? cell.surgeProgress : (1 - cell.surgeProgress)
              width: root.vertical ? parent.width * 0.72 : waveSpan
              height: root.vertical ? waveSpan : parent.height * 0.72
              x: root.vertical ? (parent.width - width) * 0.5 : travel * k
              y: root.vertical ? travel * k : (parent.height - height) * 0.5
              radius: Math.min(width, height) / 2
              opacity: Math.sin(Math.PI * cell.surgeProgress) * 0.72
              gradient: Gradient {
                orientation: root.vertical ? Gradient.Vertical : Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: root.accentSpec }
                GradientStop { position: 1.0; color: "transparent" }
              }
            }
          }
        }

        // Volume-preserving liquid slosh: impact bulge -> spread -> elastic settle.
        SequentialAnimation {
          id: squash
          ParallelAnimation {
            NumberAnimation { target: squashScale; property: root.vertical ? "yScale" : "xScale"; to: 0.84; duration: 55; easing.type: Easing.OutQuad }
            NumberAnimation { target: squashScale; property: root.vertical ? "xScale" : "yScale"; to: 1.32; duration: 55; easing.type: Easing.OutQuad }
          }
          ParallelAnimation {
            NumberAnimation { target: squashScale; property: root.vertical ? "yScale" : "xScale"; to: 1.18; duration: 85; easing.type: Easing.OutQuad }
            NumberAnimation { target: squashScale; property: root.vertical ? "xScale" : "yScale"; to: 0.76; duration: 85; easing.type: Easing.OutQuad }
          }
          ParallelAnimation {
            NumberAnimation { target: squashScale; property: "xScale"; to: 1; duration: 280; easing.type: Easing.OutElastic; easing.amplitude: 0.75; easing.period: 0.44 }
            NumberAnimation { target: squashScale; property: "yScale"; to: 1; duration: 280; easing.type: Easing.OutElastic; easing.amplitude: 0.75; easing.period: 0.44 }
          }
        }

        NumberAnimation {
          id: surgeAnim
          target: cell
          property: "surgeProgress"
          from: 0
          to: 1
          duration: 260
          easing.type: Easing.OutCubic
        }

        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        OmabarClickTarget {
          // The whole height of the bar, and half the gap either side.
          anchors.centerIn: parent
          width: root.vertical ? root.barSize : cell.width + root.gap
          height: root.vertical ? cell.height + root.gap : root.barSize
          bar: root.bar
          onPressed: root.focusWorkspace(cell.modelData)
        }
      }
    }
  }
}
