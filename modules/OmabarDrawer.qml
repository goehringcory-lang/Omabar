// Omabar drawer: everything that isn't always in view, in a glass panel that
// drops below the bar, so opening it never pushes the bar's icons around or
// spills over the clock.
//
// Hover the handle (or click it to keep it open) and the panel shows a tile
// for each widget in the bar's drawer (the "tray" section of the layout:
// Bluetooth, network, sound, display, plugin widgets) and the apps' tray icons.
// A tile opens that widget's own Omarchy panel, right under the handle. A tray
// app: click to open it, right-click for its menu. "Edit" hides tiles you don't
// want; they're remembered in ~/.config/omabar/drawer-hidden.json.
//
// It stands in for Omarchy's tray widget (omarchy.tray): the bar hands the
// drawer's widgets to it through sectionHost, and it keeps them off screen,
// beneath the handle, where their panels open from.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: root

  property var bar
  property string moduleName
  property var settings: ({})

  // ── the bar's tray section ──────────────────────────────────────────
  // The bar draws the layout's tray widgets into sectionHost, as it does for
  // the stock tray. They stay hidden here; their panels anchor to them.
  property Item sectionHost: null
  readonly property var sectionShown: null
  readonly property string sectionEdge: "start"

  readonly property color ink: Commons.Color.popups.text
  readonly property string fontName: bar && bar.fontFamily ? bar.fontFamily : Style.font.family
  // The drawer's widgets, each one once however often the layout names it.
  readonly property var trayEntries: {
    var layout = bar && bar.layoutConfig ? bar.layoutConfig : null
    var listed = layout && Array.isArray(layout.tray) ? layout.tray : []
    var seen = ({})
    var result = []
    for (var i = 0; i < listed.length; i++) {
      var id = entryId(listed[i])
      if (!id || seen[id]) continue
      seen[id] = true
      result.push(listed[i])
    }
    return result
  }

  // ── open / close ────────────────────────────────────────────────────
  property bool pinned: false        // opened by a click: stays until a click elsewhere
  property bool hoverOpen: false     // opened by hovering the handle
  property bool editing: false
  readonly property bool open: pinned || hoverOpen

  function close() {
    closeTimer.stop()
    pinned = false
    hoverOpen = false
    editing = false
    hoveredApp = ""
    closeMenu()
  }

  // Editing, or reading an app's menu, shouldn't end because the pointer
  // strayed: the panel then stays until a click elsewhere, like a clicked one.
  function hold() {
    pinned = true
    hoverOpen = true
  }

  Timer {
    id: closeTimer
    interval: 320
    onTriggered: {
      if (root.pinned || handleHover.hovered || popup.containsMouse) return
      root.hoverOpen = false
    }
  }

  // ── hidden tiles ────────────────────────────────────────────────────
  property var hiddenIds: []
  readonly property string hiddenFile: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omabar/drawer-hidden.json"

  // Watched, so the drawer on every monitor hides the same tiles.
  FileView {
    id: hiddenStore
    path: root.hiddenFile
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      var list
      try {
        list = JSON.parse(text())
      } catch (e) {
        return
      }
      if (!Array.isArray(list)) list = []
      if (JSON.stringify(list) !== JSON.stringify(root.hiddenIds)) root.hiddenIds = list
    }
  }

  function isHidden(key) { return hiddenIds.indexOf(key) !== -1 }

  function toggleHidden(key) {
    var next = hiddenIds.slice()
    var at = next.indexOf(key)
    if (at === -1) next.push(key)
    else next.splice(at, 1)
    hiddenIds = next
    // Written by a shell so the folder is made first on a fresh install, and
    // moved into place so a reader never finds half a list.
    Quickshell.execDetached(["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf "%s" "$2" > "$1.tmp" && mv -f "$1.tmp" "$1"', "sh", hiddenFile, JSON.stringify(next)])
  }

  // ── widget tiles ────────────────────────────────────────────────────
  readonly property var known: ({
    "omarchy.bluetooth": { icon: "\u{F00AF}", label: "Bluetooth" },
    "omarchy.network": { icon: "\u{F05A9}", label: "Network" },
    "omarchy.audio": { icon: "\u{F057E}", label: "Sound" },
    "omarchy.monitor": { icon: "\u{F0379}", label: "Display" },
    "omarchy.keyboard-layout": { icon: "\u{F030C}", label: "Keyboard" },
    "omarchy.microphone": { icon: "\u{F036C}", label: "Microphone" },
    "omabar-omaland": { icon: "\u{F03D8}", label: "Omaland" }
  })

  function entryId(entry) {
    return String(entry && typeof entry === "object" ? (entry.id || "") : (entry || ""))
  }

  function prettyName(id) {
    var name = id.substring(id.lastIndexOf(".") + 1).replace(/[-_]+/g, " ")
    return name.replace(/\b\w/g, function(c) { return c.toUpperCase() })
  }

  function isGlyph(value) {
    var text = String(value || "")
    if (!text) return false
    var code = text.codePointAt(0)
    if (text.length !== (code > 0xffff ? 2 : 1)) return false
    return (code >= 0xe000 && code <= 0xf8ff) || code >= 0xf0000
  }

  // The widget's own icon as it stands on the bar (Bluetooth off, sound
  // muted, a plugin's mark), so a tile shows what the widget would.
  function tileIcon(entry) {
    var id = entryId(entry)
    if (entry && isGlyph(entry.text)) return String(entry.text)
    var button = pressTarget(liveItem(id))
    if (button && isGlyph(button.text)) return String(button.text)
    return known[id] ? known[id].icon : "\u{F0431}"
  }

  // What a plugin calls its widget ("Notification Center"), as the bar's
  // widget list has it.
  function displayName(id) {
    var registry = bar && bar.barWidgetRegistry ? bar.barWidgetRegistry : null
    var metadata = registry && typeof registry.metadataFor === "function" ? registry.metadataFor(id) : null
    return metadata && metadata.displayName ? String(metadata.displayName) : ""
  }

  function tileLabel(entry) {
    var id = entryId(entry)
    if (known[id]) return known[id].label
    if (entry && entry.tooltip) return String(entry.tooltip).split(":")[0]
    return displayName(id) || prettyName(id)
  }

  function within(item, ancestor) {
    for (var p = item; p; p = p.parent) if (p === ancestor) return true
    return false
  }

  // The live widget the bar made for a drawer entry, if any. Every monitor's
  // bar has its own; the one held by this drawer is the one whose panel
  // opens on this screen.
  function liveItem(id) {
    var slots = bar && bar.moduleSlots ? bar.moduleSlots : []
    var elsewhere = null
    for (var i = 0; i < slots.length; i++) {
      var slot = slots[i]
      if (!slot || slot.region !== "tray" || slot.moduleName !== id || !slot.activeItem) continue
      if (within(slot, hostArea)) return slot.activeItem
      if (!elsewhere) elsewhere = slot.activeItem
    }
    return elsewhere
  }

  // The button inside a widget that a click on the bar would press.
  function pressTarget(item) {
    if (!item) return null
    var targets = bar && bar.clickTargets ? bar.clickTargets : []
    for (var i = 0; i < targets.length; i++) {
      var target = targets[i]
      if (target && typeof target.triggerPress === "function" && within(target, item)) return target
    }
    return typeof item.triggerPress === "function" ? item : null
  }

  // A tile needs something to open. A widget that hides itself (one keyboard
  // layout, no Bluetooth adapter) gets none, nor does one that never loaded,
  // such as a plugin that has been turned off or removed.
  function tileAvailable(entry) {
    if (entry && entry.onClick) return true
    var item = liveItem(entryId(entry))
    if (!item || item.visible === false) return false
    return typeof item.open === "function" || !!pressTarget(item)
  }

  function activate(entry) {
    var id = entryId(entry)
    if (entry && entry.onClick) {
      if (bar) bar.run(String(entry.onClick))
      close()
      return
    }
    var item = liveItem(id)
    if (item && typeof item.open === "function") {
      // Its panel takes over from this one and opens under the handle.
      close()
      item.open()
      return
    }
    // Otherwise press the widget the way a click on the bar would.
    var target = pressTarget(item)
    if (!target) return
    close()
    target.triggerPress(Qt.LeftButton)
  }

  // ── tray apps ───────────────────────────────────────────────────────
  readonly property var trayApps: {
    var values = SystemTray.items.values
    var result = []
    for (var i = 0; i < values.length; i++) {
      if (values[i].status === Status.Passive) continue
      result.push(values[i])
    }
    return result
  }

  property string hoveredApp: ""
  // How many app icons the panel shows: all of them while editing.
  readonly property int shownTiles: {
    var n = 0
    for (var i = 0; i < trayEntries.length; i++) {
      var entry = trayEntries[i]
      if (tileAvailable(entry) && (editing || !isHidden(entryId(entry)))) n++
    }
    return n
  }

  readonly property int shownApps: {
    if (editing) return trayApps.length
    var n = 0
    for (var i = 0; i < trayApps.length; i++) if (!isHidden(appKey(trayApps[i]))) n++
    return n
  }

  function appKey(app) { return "app:" + String(app.id || app.title || "") }

  // The app whose menu the panel is showing, and the submenus walked into.
  property var menuItem: null
  property var submenuStack: []
  readonly property var menuEntries: submenuStack.length > 0
    ? submenuStack[submenuStack.length - 1].opener.children
    : rootOpener.children

  Component { id: openerComponent; QsMenuOpener {} }
  QsMenuOpener { id: rootOpener; menu: root.menuItem ? root.menuItem.menu : null }

  function openMenu(app) {
    closeMenu()
    if (!app || app.hasMenu === false || !app.menu) return
    root.menuItem = app
    hold()
  }

  function closeMenu() {
    var stack = submenuStack
    submenuStack = []
    for (var i = stack.length - 1; i >= 0; i--) stack[i].opener.destroy()
    menuItem = null
  }

  function enterSubmenu(entry) {
    var opener = openerComponent.createObject(root, { menu: entry })
    if (!opener) return
    var stack = submenuStack.slice()
    stack.push({ opener: opener, title: String(entry.text || "") })
    submenuStack = stack
  }

  function leaveSubmenu() {
    if (submenuStack.length === 0) { closeMenu(); return }
    var stack = submenuStack.slice()
    var top = stack.pop()
    submenuStack = stack
    top.opener.destroy()
  }

  function pressApp(app, button) {
    if (editing) { toggleHidden(appKey(app)); return }
    if (button === Qt.RightButton || app.onlyMenu) { openMenu(app); return }
    if (button === Qt.MiddleButton) app.secondaryActivate()
    else app.activate()
    close()
  }

  // ── on the bar ──────────────────────────────────────────────────────
  implicitWidth: handle.implicitWidth
  implicitHeight: handle.implicitHeight

  HoverHandler {
    id: handleHover
    onHoveredChanged: {
      if (hovered) {
        closeTimer.stop()
        // A short pause, so sweeping across the handle toward the icons
        // beside it doesn't pop the drawer. Already open stays open.
        if (root.open) root.hoverOpen = true
        else hoverIntent.restart()
      } else {
        hoverIntent.stop()
        closeTimer.restart()
      }
    }
  }

  Timer {
    id: hoverIntent
    interval: 160
    onTriggered: if (handleHover.hovered) root.hoverOpen = true
  }

  BarIconButton {
    id: handle
    anchors.fill: parent
    bar: root.bar
    text: "\u{F0140}"
    active: root.open
    activeColor: Commons.Color.accent
    tooltipText: root.open ? "" : "More"
    rotation: root.open ? 180 : 0
    Behavior on rotation { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
    onPressed: function(button) {
      if (root.pinned) root.close()
      else {
        root.pinned = true
        root.hoverOpen = true
      }
    }
  }

  // Where the drawer's widgets live: zero-sized and clipped, so they never
  // show or take clicks, under the handle so their panels open below it.
  Item {
    x: Math.round(root.width / 2)
    width: 0
    height: root.height
    clip: true

    Item {
      id: hostArea
      implicitWidth: childrenRect.width
      implicitHeight: childrenRect.height
      Component.onCompleted: root.sectionHost = hostArea
      Component.onDestruction: if (root.sectionHost === hostArea) root.sectionHost = null
    }
  }

  // ── the panel ───────────────────────────────────────────────────────
  readonly property int columns: 3
  readonly property int tileGap: Style.space(8)
  readonly property int panelWidth: Style.space(300)
  readonly property int tileWidth: Math.floor((panelColumn.width - tileGap * (columns - 1)) / columns)

  PopupCard {
    id: popup
    anchorItem: handle
    bar: root.bar
    owner: root
    open: root.open
    triggerMode: root.pinned ? "click" : "hover"
    contentWidth: popup.fittedContentWidth(root.panelWidth)
    contentHeight: popup.fittedContentHeight((root.menuItem ? menuView.implicitHeight : panelColumn.implicitHeight), Style.space(520))
    onVisibleChanged: if (!visible) root.closeMenu()
    onContainsMouseChanged: {
      if (containsMouse) closeTimer.stop()
      else closeTimer.restart()
    }

    // ── tiles and apps ──────────────────────────────────────────────
    Column {
      id: panelColumn
      anchors.left: parent.left
      anchors.right: parent.right
      visible: !root.menuItem
      spacing: Style.space(10)

      Item {
        width: parent.width
        height: Math.max(heading.implicitHeight, editButton.implicitHeight)
        SectionTitle { id: heading; text: "Controls"; anchors.verticalCenter: parent.verticalCenter }
        Text {
          id: editButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.editing ? "Done" : "Edit"
          color: root.editing ? Commons.Color.accent : root.ink
          opacity: editHover.hovered || root.editing ? 1 : 0.55
          font.family: root.fontName
          font.pixelSize: Style.font.caption
          MouseArea {
            id: editHover
            anchors.fill: parent
            anchors.margins: -Style.space(6)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            readonly property bool hovered: containsMouse
            onClicked: {
              root.editing = !root.editing
              if (root.editing) root.hold()
            }
          }
        }
      }

      Flow {
        width: parent.width
        spacing: root.tileGap
        Repeater {
          model: root.trayEntries
          Tile {
            required property var modelData
            readonly property string key: root.entryId(modelData)
            visible: root.tileAvailable(modelData) && (root.editing || !root.isHidden(key))
            dimmed: root.isHidden(key)
            icon: root.tileIcon(modelData)
            label: root.tileLabel(modelData)
            onPicked: function(button) {
              if (root.editing) root.toggleHidden(key)
              else root.activate(modelData)
            }
          }
        }
      }

      SectionTitle {
        text: root.hoveredApp ? "Apps · " + root.hoveredApp : "Apps"
        width: parent.width
        elide: Text.ElideRight
        visible: root.shownApps > 0
        topPadding: Style.space(2)
      }

      Flow {
        id: appFlow
        width: parent.width
        spacing: Style.space(6)
        visible: root.shownApps > 0
        Repeater {
          model: root.trayApps
          AppIcon {
            required property var modelData
            app: modelData
            visible: root.editing || !root.isHidden(root.appKey(modelData))
            dimmed: root.isHidden(root.appKey(modelData))
          }
        }
      }

      Text {
        visible: !root.editing && root.shownTiles === 0 && root.shownApps === 0
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Nothing here yet. Edit brings hidden tiles back."
        color: root.ink
        opacity: 0.5
        font.family: root.fontName
        font.pixelSize: Style.font.caption
      }

      Text {
        visible: root.editing
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Click a tile or app to hide it from the drawer. Click it again to bring it back."
        color: root.ink
        opacity: 0.5
        font.family: root.fontName
        font.pixelSize: Style.font.caption
      }
    }

    // ── a tray app's menu ───────────────────────────────────────────
    Column {
      id: menuView
      anchors.left: parent.left
      anchors.right: parent.right
      visible: !!root.menuItem
      spacing: 0

      MenuRow {
        width: parent.width
        label: root.submenuStack.length > 0
          ? root.submenuStack[root.submenuStack.length - 1].title
          : (root.menuItem ? String(root.menuItem.tooltipTitle || root.menuItem.title || root.menuItem.id || "") : "")
        leading: "\u{F0141}"
        strong: true
        onPicked: root.leaveSubmenu()
      }

      Rectangle { width: parent.width; height: 1; color: root.ink; opacity: 0.12 }

      Repeater {
        model: root.menuEntries
        Item {
          required property var modelData
          width: menuView.width
          implicitHeight: modelData.isSeparator ? Style.space(9) : row.implicitHeight
          height: implicitHeight

          Rectangle {
            visible: modelData.isSeparator
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 1
            color: root.ink
            opacity: 0.12
          }

          MenuRow {
            id: row
            visible: !modelData.isSeparator
            width: parent.width
            label: String(modelData.text || "").replace(/_(?=\S)/g, "")
            leading: modelData.checkState === Qt.Checked ? "\u{F012C}" : ""
            trailing: modelData.hasChildren ? "\u{F0142}" : ""
            enabled: modelData.enabled
            onPicked: {
              if (modelData.hasChildren) {
                root.enterSubmenu(modelData)
              } else {
                modelData.triggered()
                root.close()
              }
            }
          }
        }
      }
    }
  }

  // ── pieces ──────────────────────────────────────────────────────────
  component SectionTitle: Text {
    color: root.ink
    opacity: 0.5
    font.family: root.fontName
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1.2
    font.capitalization: Font.AllUppercase
  }

  component Tile: Rectangle {
    id: tile
    property string icon: ""
    property string label: ""
    property bool dimmed: false
    signal picked(int button)

    width: root.tileWidth
    height: Style.space(62)
    radius: Style.space(14)
    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, tileHover.hovered ? 0.14 : 0.07)
    opacity: dimmed ? 0.35 : 1
    scale: tileHover.pressed ? 0.96 : 1
    Behavior on color { ColorAnimation { duration: Style.duration(120) } }
    Behavior on scale { NumberAnimation { duration: Style.duration(140); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }
    Behavior on opacity { NumberAnimation { duration: Style.duration(140) } }

    Column {
      anchors.centerIn: parent
      spacing: Style.space(4)
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: tile.icon
        color: tileHover.hovered ? Commons.Color.accent : root.ink
        font.family: root.fontName
        font.pixelSize: Style.font.iconLarge
        Behavior on color { ColorAnimation { duration: Style.duration(120) } }
      }
      // Two words wrap onto a second line and one long word shrinks a little
      // to fit, rather than being cut off ("Notificatio…").
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        width: tile.width - Style.space(10)
        horizontalAlignment: Text.AlignHCenter
        text: tile.label
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        lineHeight: 0.95
        elide: Text.ElideRight
        fontSizeMode: tile.label.indexOf(" ") === -1 ? Text.HorizontalFit : Text.FixedSize
        minimumPixelSize: Math.max(8, Style.font.caption - 2)
        color: root.ink
        opacity: 0.85
        font.family: root.fontName
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      id: tileHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      readonly property bool hovered: containsMouse
      onClicked: tile.picked(Qt.LeftButton)
    }
  }

  component AppIcon: Rectangle {
    id: appTile
    property var app: null
    property bool dimmed: false

    width: Style.space(40)
    height: width
    radius: Style.space(10)
    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, appHover.hovered ? 0.14 : 0.07)
    opacity: dimmed ? 0.35 : 1
    scale: appHover.pressed ? 0.94 : 1
    Behavior on color { ColorAnimation { duration: Style.duration(120) } }
    Behavior on scale { NumberAnimation { duration: Style.duration(140); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }
    Behavior on opacity { NumberAnimation { duration: Style.duration(140) } }

    IconImage {
      anchors.centerIn: parent
      implicitSize: Style.space(20)
      source: appTile.app ? String(appTile.app.icon || "") : ""
      asynchronous: true
    }

    MouseArea {
      id: appHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      readonly property bool hovered: containsMouse
      onClicked: function(mouse) { root.pressApp(appTile.app, mouse.button) }
    }

    // Names the app in the section title while hovered.
    readonly property bool hovered: appHover.hovered
    onHoveredChanged: {
      if (hovered) root.hoveredApp = app ? String(app.tooltipTitle || app.title || app.id || "") : ""
      else if (root.hoveredApp === (app ? String(app.tooltipTitle || app.title || app.id || "") : "")) root.hoveredApp = ""
    }
  }

  component MenuRow: Rectangle {
    id: menuRow
    property string label: ""
    property string leading: ""
    property string trailing: ""
    property bool strong: false
    signal picked()

    implicitHeight: Style.space(32)
    height: implicitHeight
    radius: Style.space(8)
    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, !enabled ? 0 : rowHover.pressed ? 0.16 : rowHover.hovered ? 0.10 : 0)
    opacity: enabled ? 1 : 0.45
    Behavior on color { ColorAnimation { duration: Style.duration(100) } }

    Text {
      id: lead
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(18)
      text: menuRow.leading
      color: root.ink
      font.family: root.fontName
      font.pixelSize: Style.font.bodySmall
    }
    Text {
      anchors.left: lead.right
      anchors.leftMargin: Style.space(4)
      anchors.right: trail.left
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      text: menuRow.label
      elide: Text.ElideRight
      color: root.ink
      font.family: root.fontName
      font.pixelSize: Style.font.bodySmall
      font.weight: menuRow.strong ? Font.DemiBold : Font.Normal
    }
    Text {
      id: trail
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: menuRow.trailing
      color: root.ink
      opacity: 0.6
      font.family: root.fontName
      font.pixelSize: Style.font.bodySmall
    }

    MouseArea {
      id: rowHover
      anchors.fill: parent
      hoverEnabled: true
      enabled: menuRow.enabled
      cursorShape: Qt.PointingHandCursor
      readonly property bool hovered: containsMouse
      onClicked: menuRow.picked()
    }
  }
}
