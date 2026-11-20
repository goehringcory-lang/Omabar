// The Omabar player's playlist menu: one-click Lofi Beats and Discover Weekly,
// your pinned playlists, then every playlist on your Spotify account.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons

Item {
  id: menu

  property Item anchorItem
  property var player          // the OmabarPlayer that owns this menu
  property bool open: false
  signal dismissed()

  readonly property var bar: player ? player.bar : null
  readonly property color ink: player ? player.ink : Commons.Color.foreground
  readonly property string fontName: player ? player.fontName : "monospace"
  readonly property bool bottomBar: bar && bar.position === "bottom"

  readonly property string lofiUri: String(player ? player.setting("lofi", "spotify:playlist:37i9dQZF1DWWQRwui0ExPn") : "")
  readonly property string discoverUri: String(player ? player.setting("discoverWeekly", "") : "")
  readonly property var pinned: {
    var list = player ? player.setting("playlists", []) : []
    return Array.isArray(list) ? list : []
  }

  property var playlists: []
  property bool connected: true
  property bool loading: false

  function refresh() {
    if (!player || loader.running) return
    menu.loading = true
    loader.command = [player.helper, "playlists"]
    loader.running = true
  }

  function runInTerminal(args) {
    if (!bar) return
    var command = args.map(function(a) { return Util.shellQuote(a) }).join(" ")
    bar.run("omarchy-launch-floating-terminal-with-presentation " + Util.shellQuote(command))
    menu.dismissed()
  }

  onOpenChanged: if (open) refresh()

  Process {
    id: loader
    stdout: StdioCollector {
      onStreamFinished: {
        menu.loading = false
        try {
          var data = JSON.parse(text)
          menu.connected = data.connected === true
          menu.playlists = Array.isArray(data.playlists) ? data.playlists : []
        } catch (e) {
          menu.connected = false
        }
      }
    }
    onExited: menu.loading = false
  }

  PopupWindow {
    id: popup
    visible: menu.open && menu.anchorItem !== null
    color: "transparent"
    anchor.item: menu.anchorItem
    anchor.rect.x: menu.anchorItem ? menu.anchorItem.width / 2 : 0
    anchor.rect.y: menu.bottomBar ? -Style.space(10) : (menu.anchorItem ? menu.anchorItem.height + Style.space(10) : 0)
    anchor.rect.width: 1
    anchor.rect.height: 1
    anchor.edges: Edges.Top
    anchor.gravity: menu.bottomBar ? Edges.Top : Edges.Bottom
    implicitWidth: card.width + shadowRoom * 2
    implicitHeight: card.height + shadowRoom * 2

    readonly property int shadowRoom: Style.space(18)

    HyprlandFocusGrab {
      windows: [popup]
      active: popup.visible
      onCleared: menu.dismissed()
    }

    RectangularShadow {
      anchors.fill: card
      radius: card.radius
      offset.y: Style.space(6)
      blur: Style.space(18)
      color: Qt.rgba(0, 0, 0, 0.35)
    }

    Rectangle {
      id: card
      x: popup.shadowRoom
      y: popup.shadowRoom
      width: Style.space(300)
      height: column.implicitHeight + Style.space(16) * 2
      radius: Style.space(18)
      color: Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b, 0.92)
      border.width: 1
      border.color: Qt.rgba(menu.ink.r, menu.ink.g, menu.ink.b, 0.10)

      // Entrance: a short drop and fade.
      opacity: popup.visible ? 1 : 0
      transform: Translate { y: popup.visible ? 0 : (menu.bottomBar ? 6 : -6) }
      Behavior on opacity { NumberAnimation { duration: Style.duration(160) } }

      Rectangle {
        anchors.fill: parent
        radius: parent.radius
        gradient: Gradient {
          GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.06) }
          GradientStop { position: 0.3; color: Qt.rgba(1, 1, 1, 0.0) }
        }
      }

      Column {
        id: column
        x: Style.space(16)
        y: Style.space(16)
        width: card.width - Style.space(32)
        spacing: Style.space(10)

        // ── one-click picks ───────────────────────────────────────────
        Row {
          width: parent.width
          spacing: Style.space(8)

          QuickPick {
            width: (parent.width - parent.spacing) / 2
            icon: "\u{F0176}"
            label: "Lofi Beats"
            filled: true
            onPicked: menu.player.play(menu.lofiUri)
          }
          QuickPick {
            width: (parent.width - parent.spacing) / 2
            icon: "\u{F018B}"
            label: menu.discoverUri ? "Discover Weekly" : "Add Discover Weekly"
            onPicked: {
              if (menu.discoverUri) menu.player.play(menu.discoverUri)
              else menu.runInTerminal([menu.player.helper, "set-discover-weekly"])
            }
          }
        }

        // ── playlists ─────────────────────────────────────────────────
        Text {
          text: "Playlists"
          color: menu.ink
          opacity: 0.5
          font.family: menu.fontName
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1.2
          font.capitalization: Font.AllUppercase
          topPadding: Style.space(4)
        }

        ListView {
          id: list
          width: parent.width
          height: Math.min(contentHeight, Style.space(44) * 7)
          clip: true
          spacing: Style.space(2)
          boundsBehavior: Flickable.StopAtBounds
          model: menu.pinned.concat(menu.playlists)

          delegate: PlaylistRow {
            required property var modelData
            width: list.width
            name: modelData.name || ""
            detail: modelData.owner ? modelData.owner + (modelData.tracks ? " · " + modelData.tracks + " songs" : "") : (modelData.tracks ? modelData.tracks + " songs" : "")
            image: modelData.image || ""
            onPicked: menu.player.play(modelData.uri)
          }
        }

        Text {
          visible: menu.loading && list.count === 0
          text: "Loading your playlists…"
          color: menu.ink
          opacity: 0.55
          font.family: menu.fontName
          font.pixelSize: Style.font.bodySmall
        }

        PlaylistRow {
          visible: !menu.connected && !menu.loading
          width: parent.width
          name: "Connect Spotify"
          detail: "Show every playlist on your account here"
          icon: "\u{F04C7}"
          onPicked: menu.runInTerminal([menu.player.helper, "login"])
        }
      }
    }
  }

  // ── pieces ───────────────────────────────────────────────────────────
  component QuickPick: Rectangle {
    id: pick
    property string icon: ""
    property string label: ""
    property bool filled: false
    signal picked()

    height: Style.space(52)
    radius: Style.space(14)
    readonly property color accent: Commons.Color.accent
    color: filled
      ? Qt.rgba(accent.r, accent.g, accent.b, pickHover.hovered ? 1.0 : 0.88)
      : Qt.rgba(menu.ink.r, menu.ink.g, menu.ink.b, pickHover.hovered ? 0.14 : 0.07)
    scale: pickTap.pressed ? 0.97 : 1.0
    Behavior on color { ColorAnimation { duration: Style.duration(140) } }
    Behavior on scale { NumberAnimation { duration: Style.duration(140) } }

    readonly property bool lightFill: filled && (0.2126 * accent.r + 0.7152 * accent.g + 0.0722 * accent.b) > 0.5
    readonly property color fg: lightFill ? Qt.rgba(0.06, 0.06, 0.08, 0.92) : (filled ? "white" : menu.ink)

    Column {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      Text {
        text: pick.icon
        color: pick.fg
        font.family: menu.fontName
        font.pixelSize: Style.font.iconLarge
      }
      Text {
        text: pick.label
        color: pick.fg
        font.family: menu.fontName
        font.pixelSize: Style.font.bodySmall
        font.weight: Font.DemiBold
      }
    }

    HoverHandler { id: pickHover; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: pickTap; onTapped: pick.picked() }
  }

  component PlaylistRow: Rectangle {
    id: row
    property string name: ""
    property string detail: ""
    property string image: ""
    property string icon: "\u{F0CB8}"
    signal picked()

    height: Style.space(44)
    radius: Style.space(10)
    color: Qt.rgba(menu.ink.r, menu.ink.g, menu.ink.b, rowHover.hovered ? 0.09 : 0.0)
    Behavior on color { ColorAnimation { duration: Style.duration(120) } }

    Item {
      id: thumb
      anchors.left: parent.left
      anchors.leftMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(32)
      height: width

      Rectangle {
        anchors.fill: parent
        radius: Style.space(6)
        color: Qt.rgba(menu.ink.r, menu.ink.g, menu.ink.b, 0.08)
        visible: cover.status !== Image.Ready
        Text {
          anchors.centerIn: parent
          text: row.icon
          color: menu.ink
          opacity: 0.7
          font.family: menu.fontName
          font.pixelSize: Style.font.icon
        }
      }
      Image {
        id: cover
        anchors.fill: parent
        source: row.image
        sourceSize: Qt.size(64, 64)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
        layer.enabled: true
      }
      Rectangle { id: thumbMask; anchors.fill: parent; radius: Style.space(6); visible: false; layer.enabled: true }
      MultiEffect {
        anchors.fill: parent
        source: cover
        visible: cover.status === Image.Ready
        maskEnabled: true
        maskSource: thumbMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
      }
    }

    Column {
      anchors.left: thumb.right
      anchors.leftMargin: Style.space(10)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: 1
      Text {
        width: parent.width
        text: row.name
        elide: Text.ElideRight
        color: menu.ink
        font.family: menu.fontName
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        width: parent.width
        visible: row.detail !== ""
        text: row.detail
        elide: Text.ElideRight
        color: menu.ink
        opacity: 0.5
        font.family: menu.fontName
        font.pixelSize: Style.font.caption
      }
    }

    HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: row.picked() }
  }
}
