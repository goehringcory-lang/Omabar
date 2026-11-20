// Omabar workspaces: a row of dots, with the workspace on screen stretched into
// an accent pill. Workspace numbering and focusing follow Omarchy's built-in
// workspaces widget (one block of ten per monitor).
//
// Switching workspaces sends a drop of water from the old pill to the new
// one: it slides along the row, sheds small droplets behind it, and splashes into the
// new pill with a ripple. Omarchy's "reduce motion" setting turns it off.
import QtQuick
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

  // ── the water drop ─────────────────────────────────────────────────────
  // The pill is drawn on the workspace the drop has landed on, which trails
  // the real active workspace by one flight.
  readonly property int currentId: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
  property int landedId: -1
  property int flightFrom: -1
  property int flightTo: -1
  property point flightStart: Qt.point(0, 0)

  onCurrentIdChanged: launch(currentId)
  Component.onCompleted: landedId = currentId

  function centerOf(id) {
    var index = root.ids.indexOf(id)
    var item = index >= 0 ? cells.itemAt(index) : null
    return item ? item.mapToItem(root, item.width / 2, item.height / 2) : null
  }

  function launch(target) {
    if (flight.running) {
      flight.stop()
      root.land()
    }
    var from = root.landedId
    var start = root.centerOf(from)
    if (from < 0 || target < 0 || from === target || !start || Style.reduceMotion || !root.visible) {
      root.landedId = target
      return
    }
    root.flightFrom = from
    root.flightTo = target
    root.flightStart = start
    root.landedId = -1                 // the old pill lets go of its water
    var hops = Math.abs(root.ids.indexOf(target) - root.ids.indexOf(from))
    flight.duration = Math.min(320, 170 + hops * 25)
    drop.t = 0
    flight.start()
  }

  function land() {
    root.landedId = root.flightTo
    var index = root.ids.indexOf(root.flightTo)
    var item = index >= 0 ? cells.itemAt(index) : null
    var at = root.centerOf(root.flightTo)
    if (item) item.splash()
    if (at) {
      ripple.createObject(fx, { cx: at.x, cy: at.y })
      for (var i = 0; i < 6; i++) {
        // Mostly upward, like water thrown up out of a puddle.
        var angle = Math.PI + (i + 0.5) * Math.PI / 6 + (Math.random() - 0.5) * 0.35
        if (root.vertical) angle += Math.PI / 2
        var reach = root.dot * (1.1 + Math.random() * 0.9)
        droplet.createObject(fx, {
          cx: at.x, cy: at.y,
          dx: Math.cos(angle) * reach, dy: Math.sin(angle) * reach,
          size: root.dot * (0.28 + Math.random() * 0.22),
          life: 260 + Math.random() * 120
        })
      }
    }
  }

  NumberAnimation {
    id: flight
    target: drop
    property: "t"
    from: 0
    to: 1
    // Leaves at once and eases into the landing, so a switch feels snappy.
    easing.type: Easing.OutCubic
    onFinished: root.land()
  }

  // Sheds a droplet behind the drop every few frames of its flight.
  Timer {
    interval: 38
    repeat: true
    running: flight.running
    onTriggered: {
      if (drop.t < 0.08 || drop.t > 0.92) return
      droplet.createObject(fx, {
        cx: drop.cx - drop.dirX * root.dot * 0.6, cy: drop.cy - drop.dirY * root.dot * 0.6,
        dx: root.vertical ? 0 : -drop.dirX * Math.random() * 2,
        dy: root.vertical ? -drop.dirY * Math.random() * 2 : 0,
        size: root.dot * (0.22 + Math.random() * 0.25),
        life: 420 + Math.random() * 260
      })
    }
  }

  Item {
    id: fx
    anchors.fill: parent
    z: 2

    Item {
      id: drop
      property real t: 0
      readonly property point end: {
        var dummy = root.ids.length + row.width + row.height   // follow the row as pills resize
        var c = root.centerOf(root.flightTo)
        return c ? c : root.flightStart
      }
      readonly property real dirX: root.vertical ? 0 : (end.x >= root.flightStart.x ? 1 : -1)
      readonly property real dirY: root.vertical ? (end.y >= root.flightStart.y ? 1 : -1) : 0
      readonly property real arc: Math.sin(Math.PI * t)
      // Slides straight along the row; no hop.
      readonly property real cx: root.flightStart.x + (end.x - root.flightStart.x) * t
      readonly property real cy: root.flightStart.y + (end.y - root.flightStart.y) * t
      visible: flight.running

      // Body: stretched along the way it travels, rounder at the ends.
      readonly property real body: root.dot * 1.35
      readonly property real stretch: 1 + 0.75 * arc

      Rectangle {
        id: tailBead
        width: drop.body * 0.62
        height: width
        radius: width / 2
        x: drop.cx - width / 2 - drop.dirX * drop.body * 0.55 * drop.stretch
        y: drop.cy - height / 2 - drop.dirY * drop.body * 0.55 * drop.stretch
        color: Commons.Color.accent
        opacity: 0.75
      }
      Rectangle {
        width: root.vertical ? drop.body * (1 - 0.18 * drop.arc) : drop.body * drop.stretch
        height: root.vertical ? drop.body * drop.stretch : drop.body * (1 - 0.18 * drop.arc)
        radius: Math.min(width, height) / 2
        x: drop.cx - width / 2
        y: drop.cy - height / 2
        color: Commons.Color.accent
        // A glint, so it reads as water.
        Rectangle {
          width: parent.height * 0.32
          height: width
          radius: width / 2
          x: parent.width * (drop.dirX < 0 ? 0.22 : 0.5)
          y: parent.height * 0.18
          color: Qt.rgba(1, 1, 1, 0.55)
        }
      }
    }
  }

  // A droplet left behind or thrown up by the splash: drifts, shrinks, fades.
  Component {
    id: droplet
    Rectangle {
      id: bead
      property real cx: 0
      property real cy: 0
      property real dx: 0
      property real dy: 0
      property real size: 3
      property real life: 500
      property real k: 0
      width: size * (1 - 0.6 * k)
      height: width
      radius: width / 2
      x: cx + dx * k - width / 2
      y: cy + dy * k + (dy < 0 ? 3 * k * k : 0) - height / 2   // thrown droplets fall back a little
      color: Commons.Color.accent
      opacity: 0.85 * (1 - k)
      NumberAnimation on k {
        from: 0; to: 1
        duration: bead.life
        easing.type: Easing.OutQuad
        onFinished: bead.destroy()
      }
    }
  }

  // The ring that spreads when the drop lands.
  Component {
    id: ripple
    Rectangle {
      id: ring
      property real cx: 0
      property real cy: 0
      property real k: 0
      readonly property real size: root.dot * (1 + 2.4 * k)
      width: root.vertical ? size : size * 1.6
      height: root.vertical ? size * 1.6 : size
      radius: Math.min(width, height) / 2
      x: cx - width / 2
      y: cy - height / 2
      color: "transparent"
      border.width: 1.5
      border.color: Commons.Color.accent
      opacity: 0.55 * (1 - k)
      NumberAnimation on k {
        from: 0; to: 1
        duration: 360
        easing.type: Easing.OutCubic
        onFinished: ring.destroy()
      }
    }
  }

  implicitWidth: vertical ? barSize : row.implicitWidth + Style.space(4)
  implicitHeight: vertical ? row.implicitHeight + Style.space(4) : barSize

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

        // Squash and settle when the drop lands here.
        function splash() { squash.restart() }

        width: root.vertical ? root.barSize : pill.width
        height: root.vertical ? pill.height : root.barSize

        Rectangle {
          id: pill
          anchors.centerIn: parent
          width: root.vertical ? root.dot : (cell.shown ? root.pillLength : root.dot)
          height: root.vertical ? (cell.shown ? root.pillLength : root.dot) : root.dot
          radius: root.dot / 2
          color: cell.urgent ? Commons.Color.urgent
            : cell.shown ? Commons.Color.accent
            : root.ink
          opacity: cell.shown || cell.urgent ? 1.0
            : hover.hovered ? 0.85
            : cell.occupied ? 0.6 : 0.22

          transform: Scale {
            id: squashScale
            origin.x: pill.width / 2
            origin.y: pill.height / 2
          }

          Behavior on width { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
          Behavior on height { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
          Behavior on opacity { NumberAnimation { duration: Style.duration(180) } }
          Behavior on color { ColorAnimation { duration: Style.duration(160) } }
        }

        SequentialAnimation {
          id: squash
          ParallelAnimation {
            NumberAnimation { target: squashScale; property: root.vertical ? "yScale" : "xScale"; to: 1.18; duration: 60; easing.type: Easing.OutQuad }
            NumberAnimation { target: squashScale; property: root.vertical ? "xScale" : "yScale"; to: 0.62; duration: 60; easing.type: Easing.OutQuad }
          }
          ParallelAnimation {
            NumberAnimation { target: squashScale; property: "xScale"; to: 1; duration: 260; easing.type: Easing.OutElastic; easing.amplitude: 1.1; easing.period: 0.4 }
            NumberAnimation { target: squashScale; property: "yScale"; to: 1; duration: 260; easing.type: Easing.OutElastic; easing.amplitude: 1.1; easing.period: 0.4 }
          }
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
