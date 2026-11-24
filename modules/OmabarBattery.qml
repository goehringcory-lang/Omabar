// Omabar battery: reads each laptop battery on its own, so a ThinkPad with a
// removable pack (T480 and friends) shows the pack that is actually draining.
// The bar shows the external (removable) battery until it is spent, then the
// internal one. Click opens a card with both batteries, the combined total,
// time left and the power profile.
//
// Settings (inline on the shell.json entry):
//   external - sysfs name of the removable battery (default "BAT1"). The
//              external row only shows once that pack has been seen (or this
//              is set), so a laptop with one battery never sees an empty slot.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "OmabarBatteryModel.js" as Model

Item {
  id: root

  property var bar
  property string moduleName
  property var settings: ({})

  function setting(name, fallback) {
    var v = settings ? settings[name] : undefined
    return v === undefined || v === null ? fallback : v
  }

  readonly property string externalName: String(setting("external", "BAT1"))
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : 34
  readonly property color ink: bar ? bar.barForeground : Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property string fontName: bar && bar.fontFamily ? bar.fontFamily : "monospace"

  property bool cardOpen: false
  property var profiles: []
  property string activeProfile: ""

  function close() { cardOpen = false }

  function stateName(state) {
    switch (state) {
      case UPowerDeviceState.Charging: return "charging"
      case UPowerDeviceState.Discharging: return "discharging"
      case UPowerDeviceState.FullyCharged: return "full"
      case UPowerDeviceState.PendingCharge: return "pending"
      case UPowerDeviceState.PendingDischarge: return "discharging"
      case UPowerDeviceState.Empty: return "empty"
      default: return "unknown"
    }
  }

  // Every laptop battery that is in the machine right now, as plain objects.
  // Reading each property here makes the binding follow UPower's updates.
  readonly property var batteries: {
    var out = []
    var list = UPower.devices ? UPower.devices.values : []
    for (var i = 0; i < list.length; i++) {
      var d = list[i]
      if (!d || !d.isLaptopBattery || !d.isPresent) continue
      out.push({
        name: String(d.nativePath || ("battery" + i)),
        percent: Number(d.percentage || 0) * 100,
        energy: Number(d.energy || 0),
        capacity: Number(d.energyCapacity || 0),
        state: stateName(d.state),
        timeToEmpty: Number(d.timeToEmpty || 0),
        timeToFull: Number(d.timeToFull || 0)
      })
    }
    return out
  }

  readonly property var pair: Model.split(batteries, externalName)
  readonly property bool present: !!(pair.external || pair.internal)
  readonly property bool onBattery: UPower.onBattery
  // A laptop that has never shown a second pack has no removable slot to
  // report. Once one is seen it is remembered (a pulled pack still shows as
  // "not inserted"), and setting `external` turns the slot on from the start.
  property bool externalSeen: false
  readonly property bool expectExternal: settings && settings.external !== undefined && settings.external !== null
    || externalSeen || !!pair.external
  readonly property string seenFile: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/omabar/battery-external-seen"
  FileView {
    id: seenState
    path: root.seenFile
    printErrors: false
    onLoaded: root.externalSeen = text().trim() === "1"
  }
  onPairChanged: if (pair.external && !externalSeen) { externalSeen = true; seenState.setText("1") }
  // Low on battery: the icon turns the theme's urgent color.
  readonly property bool low: onBattery && focusPercent >= 0 && focusPercent <= 15
  readonly property color iconColor: low ? Commons.Color.urgent
    : cardOpen || charging ? accent : ink
  readonly property string focusKey: Model.focus(pair, onBattery)
  readonly property var focusBattery: focusKey === "external" ? pair.external : pair.internal
  readonly property int focusPercent: Model.percentOf(focusBattery)
  readonly property int totalPercent: Model.totalPercent(pair)
  readonly property bool charging: !onBattery && present
    && ((pair.external && pair.external.state === "charging") || (pair.internal && pair.internal.state === "charging"))
  readonly property bool full: !onBattery && present && !charging && totalPercent >= 99

  // UPower's combined device knows the time left across both packs.
  readonly property string timeText: {
    var d = UPower.displayDevice
    if (!d || !d.isPresent) return ""
    return Model.formatMinutes(onBattery ? d.timeToEmpty : d.timeToFull)
  }

  readonly property string statusText: {
    if (!present) return ""
    if (onBattery) return timeText ? timeText + " left" : "On battery"
    if (charging) return timeText ? "Charging · full in " + timeText : "Charging"
    return full ? "Fully charged" : "Plugged in"
  }

  readonly property string barIcon: Model.icon(focusPercent, !onBattery)
  readonly property string barText: focusPercent >= 0 ? focusPercent + "%" : ""

  readonly property string tooltipText: {
    if (!present) return ""
    var lines = []
    if (pair.external) lines.push("External " + Model.percentOf(pair.external) + "%" + (focusKey === "external" ? " (in use)" : ""))
    else if (root.expectExternal) lines.push("External not inserted")
    if (pair.internal) lines.push((root.expectExternal ? "Internal " : "Battery ") + Model.percentOf(pair.internal) + "%" + (focusKey === "internal" && pair.external ? " (in use)" : ""))
    if (pair.external && pair.internal) lines.push("Total " + totalPercent + "%")
    if (statusText) lines.push(statusText)
    return lines.join("\n")
  }

  // ── power profiles (same scripts as Omarchy's own power panel) ─────────
  function refreshProfiles() {
    if (!profilesProc.running) profilesProc.running = true
  }

  function parseProfiles(text) {
    var list = []
    var active = ""
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue
      var parts = line.split("\t")
      list.push(parts[0])
      if (parts[1] === "1") active = parts[0]
    }
    if (list.length === 0) return
    root.profiles = list
    root.activeProfile = active
  }

  function setProfile(profile) {
    if (!profile || actionProc.running) return
    root.activeProfile = profile
    actionProc.command = ["omarchy-powerprofiles-set", root.onBattery ? "battery" : "ac", profile]
    actionProc.running = true
  }

  Process {
    id: profilesProc
    command: ["omarchy-powerprofiles-list", "--active-state"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parseProfiles(text) }
  }

  Process {
    id: actionProc
    onExited: root.refreshProfiles()
  }

  onCardOpenChanged: {
    syncTooltip()
    if (cardOpen) refreshProfiles()
  }
  onPresentChanged: if (!present) cardOpen = false

  function syncTooltip() {
    if (!bar || typeof bar.showTooltip !== "function") return
    if (hover.hovered && !cardOpen && tooltipText !== "") bar.showTooltip(root, tooltipText)
    else bar.hideTooltip(root)
  }
  onTooltipTextChanged: if (hover.hovered) syncTooltip()

  visible: present
  implicitWidth: !present ? 0 : vertical ? barSize : pill.implicitWidth + Style.space(2)
  implicitHeight: !present ? 0 : vertical ? pill.implicitHeight + Style.space(4) : barSize

  Rectangle {
    id: pill
    anchors.centerIn: parent
    implicitWidth: root.vertical ? root.barSize - Style.space(4) : hRow.implicitWidth + Style.space(12)
    implicitHeight: root.vertical ? vCol.implicitHeight + Style.space(8) : Math.round(root.barSize * 0.72)
    width: implicitWidth
    height: implicitHeight
    radius: root.vertical ? Style.space(8) : height / 2
    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b,
      clickTarget.held ? 0.18 : root.cardOpen ? 0.14 : hover.hovered ? 0.09 : 0.0)
    Behavior on color { ColorAnimation { duration: Style.duration(120) } }

    Row {
      id: hRow
      visible: !root.vertical
      anchors.centerIn: parent
      spacing: Style.space(4)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.barIcon
        color: root.iconColor
        font.family: root.fontName
        font.pixelSize: Style.font.icon
        Behavior on color { ColorAnimation { duration: Style.duration(150) } }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.barText
        textFormat: Text.PlainText
        color: root.ink
        opacity: 0.92
        font.family: root.fontName
        font.pixelSize: Style.font.bodySmall
      }
    }

    Column {
      id: vCol
      visible: root.vertical
      anchors.centerIn: parent
      spacing: Style.space(2)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.barIcon
        color: root.iconColor
        font.family: root.fontName
        font.pixelSize: Style.font.icon
        Behavior on color { ColorAnimation { duration: Style.duration(150) } }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.focusPercent >= 0 ? String(root.focusPercent) : ""
        textFormat: Text.PlainText
        color: root.ink
        opacity: 0.92
        font.family: root.fontName
        font.pixelSize: Style.font.caption
      }
    }
  }

  PopupCard {
    id: popup
    anchorItem: pill
    bar: root.bar
    owner: root
    open: root.cardOpen && root.present
    contentWidth: popup.fittedContentWidth(card.implicitWidth)
    contentHeight: popup.fittedContentHeight(card.implicitHeight)

    OmabarBatteryCard {
      id: card
      anchors.fill: parent
      ink: Commons.Color.popups.text
      fontName: root.fontName
      external: root.pair.external
      showExternal: root.expectExternal
      internal: root.pair.internal
      focusKey: root.focusKey
      totalPercent: root.totalPercent
      statusText: root.statusText
      onBattery: root.onBattery
      profiles: root.profiles
      activeProfile: root.activeProfile
      onProfilePicked: function(name) { root.setProfile(name) }
    }
  }

  HoverHandler {
    id: hover
    cursorShape: Qt.PointingHandCursor
    onHoveredChanged: root.syncTooltip()
  }

  OmabarClickTarget {
    id: clickTarget
    anchors.fill: parent
    bar: root.bar
    pressable: root.present
    onPressed: function(button) { root.cardOpen = !root.cardOpen }
  }
}
