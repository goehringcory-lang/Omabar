// Omabar workspaces: a row of dots, with the workspace on screen stretched into
// an accent pill. Workspace numbering and focusing follow Omarchy's built-in
// workspaces widget (one block of ten per monitor).
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
  readonly property int persistent: settings && settings.persistent ? Number(settings.persistent) : 5
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
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/monitors/workspaces"
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

  readonly property var ids: {
    var base = root.block * root.slots
    var list = []
    for (var n = 1; n <= Math.min(root.persistent, root.slots); n++) list.push(base + n)
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && root.blockOf(id) === root.block && list.indexOf(id) === -1) list.push(id)
    }
    list.sort(function(a, b) { return a - b })
    return list
  }

  function focus(id) {
    if (!root.bar) return
    var expr = "o.workspaces.focus(" + root.slotOf(id) + ", \"" + root.monitorName + "\")"
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
    if (target !== root.ids[index]) root.focus(target)
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
      model: root.ids

      Item {
        id: cell
        required property int modelData
        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool shown: root.activeId() === modelData
        readonly property bool urgent: workspace !== null && workspace.urgent === true

        // A slightly larger hit area than the dot itself.
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

          Behavior on width { NumberAnimation { duration: Style.duration(280); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }
          Behavior on height { NumberAnimation { duration: Style.duration(280); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }
          Behavior on opacity { NumberAnimation { duration: Style.duration(180) } }
          Behavior on color { ColorAnimation { duration: Style.duration(220) } }
        }

        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.focus(cell.modelData) }
      }
    }
  }
}
