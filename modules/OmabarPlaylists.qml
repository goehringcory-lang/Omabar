// The Omabar player's playlist menu: one-click Lofi Beats, Discover Weekly and
// shuffled Liked Songs, your pinned playlists, then every playlist on your Spotify account.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: menu

  property Item anchorItem
  property var player          // the OmabarPlayer that owns this menu
  property bool open: false
  signal dismissed()

  readonly property var bar: player ? player.bar : null
  readonly property color ink: Commons.Color.popups.text
  readonly property string fontName: player ? player.fontName : "monospace"
  readonly property bool bottomBar: bar && bar.position === "bottom"

  readonly property string lofiUri: String(player ? player.setting("lofi", "spotify:playlist:0vvXsWCC9xrXsKd4FyS8kM") : "")
  readonly property string discoverUri: String(player ? player.setting("discoverWeekly", "") : "")
  readonly property bool shuffleLiked: player ? player.setting("shuffleLiked", true) !== false : true
  readonly property var pinned: {
    var list = player ? player.setting("playlists", []) : []
    return Array.isArray(list) ? list : []
  }

  property var playlists: []
  property bool connected: true
  property bool loading: false
  property string error: ""

  // Pinned playlists first, then the account's, without repeating one that is both.
  readonly property var rows: {
    var seen = ({}), out = []
    var all = menu.pinned.concat(menu.playlists)
    for (var i = 0; i < all.length; i++) {
      var item = all[i]
      if (!item || !item.uri || seen[item.uri]) continue
      seen[item.uri] = true
      out.push(item)
    }
    return out
  }

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
          menu.error = String(data.error || "")
          menu.playlists = Array.isArray(data.playlists) ? data.playlists : []
        } catch (e) {
          // The helper said nothing readable: keep what is already listed.
          menu.error = "Couldn't load your playlists."
        }
      }
    }
    onExited: menu.loading = false
  }

  // Omarchy's own popup card: placed under the bar, themed like its other
  // panels, closed by a click outside, and one popup open at a time.
  PopupCard {
    id: popup
    anchorItem: menu.anchorItem
    bar: menu.bar
    owner: menu.player
    open: menu.open
    contentWidth: popup.fittedContentWidth(Style.space(340))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(10)

        // ── one-click picks ───────────────────────────────────────────
        Row {
          width: parent.width
          spacing: Style.space(8)

          id: picks
          readonly property real tile: Math.floor((width - spacing * 2) / 3)

          QuickPick {
            width: picks.tile
            icon: "\u{F0176}"
            label: "Lofi Beats"
            filled: true
            onPicked: menu.player.play(menu.lofiUri)
          }
          QuickPick {
            width: picks.tile
            icon: "\u{F018B}"
            label: "Discover Weekly"
            // A plus until your own Discover Weekly link is saved.
            badge: menu.discoverUri ? "" : "\u{F0415}"
            onPicked: {
              if (menu.discoverUri) menu.player.play(menu.discoverUri)
              else menu.runInTerminal([menu.player.helper, "set-discover-weekly"])
            }
          }
          QuickPick {
            width: picks.tile
            icon: "\u{F02D1}"
            label: "Liked Songs"
            badge: menu.shuffleLiked ? "\u{F049D}" : ""
            onPicked: menu.player.playLiked()
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
          visible: count > 0
          model: menu.rows

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

        Text {
          visible: menu.connected && !menu.loading && menu.error === "" && list.count === 0
          text: "No playlists yet"
          color: menu.ink
          opacity: 0.55
          font.family: menu.fontName
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          visible: !menu.loading && menu.error !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          maximumLineCount: 3
          elide: Text.ElideRight
          text: menu.error
          color: menu.ink
          opacity: 0.55
          font.family: menu.fontName
          font.pixelSize: Style.font.caption
        }

        PlaylistRow {
          visible: !menu.connected && !menu.loading
          width: parent.width
          name: menu.playlists.length > 0 || menu.error !== "" ? "Reconnect Spotify" : "Connect Spotify"
          detail: "Show every playlist on your account here"
          icon: "\u{F04C7}"
          onPicked: menu.runInTerminal([menu.player.helper, "login"])
        }
      }
  }

  // ── pieces ───────────────────────────────────────────────────────────
  component QuickPick: Rectangle {
    id: pick
    property string icon: ""
    property string label: ""
    property bool filled: false
    // A small glyph in the corner that says what a click does.
    property string badge: ""
    signal picked()

    height: Style.space(68)
    radius: Style.space(14)
    readonly property color accent: Commons.Color.accent
    color: filled
      ? Qt.rgba(accent.r, accent.g, accent.b, pickHover.hovered ? 1.0 : 0.88)
      : Qt.rgba(menu.ink.r, menu.ink.g, menu.ink.b, pickHover.hovered ? 0.14 : 0.07)
    scale: pickTap.pressed ? 0.97 : 1.0
    Behavior on color { ColorAnimation { duration: Style.duration(120) } }
    Behavior on scale { NumberAnimation { duration: Style.duration(140); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }

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
        width: pick.width - Style.space(24)
        height: lineHeightProbe.implicitHeight * 2
        verticalAlignment: Text.AlignTop
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: pick.label
        color: pick.fg
        font.family: menu.fontName
        font.pixelSize: Style.font.bodySmall
        font.weight: Font.DemiBold
      }
    }

    // One line of the label's font, so every tile leaves room for two.
    Text {
      id: lineHeightProbe
      visible: false
      text: "X"
      font.family: menu.fontName
      font.pixelSize: Style.font.bodySmall
      font.weight: Font.DemiBold
    }
    Text {
      visible: pick.badge !== ""
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      text: pick.badge
      color: pick.fg
      opacity: 0.6
      font.family: menu.fontName
      font.pixelSize: Style.font.iconSmall
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
    color: Qt.rgba(menu.ink.r, menu.ink.g, menu.ink.b, rowTap.pressed ? 0.16 : rowHover.hovered ? 0.10 : 0.0)
    Behavior on color { ColorAnimation { duration: Style.duration(100) } }

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
        mipmap: true
        visible: false
        layer.enabled: true; layer.smooth: true
      }
      Rectangle { id: thumbMask; anchors.fill: parent; radius: Style.space(6); visible: false; layer.enabled: true; layer.smooth: true }
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
        textFormat: Text.PlainText   // names come from other people's playlists
        elide: Text.ElideRight
        color: menu.ink
        font.family: menu.fontName
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        width: parent.width
        visible: row.detail !== ""
        text: row.detail
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: menu.ink
        opacity: 0.5
        font.family: menu.fontName
        font.pixelSize: Style.font.caption
      }
    }

    HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: rowTap; onTapped: row.picked() }
  }
}
