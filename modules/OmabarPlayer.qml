// Omabar player: a small Spotify player for the middle of the bar.
// Controls, round album art that turns slowly while music plays, the track,
// and a hairline of progress. It hides itself when Spotify isn't running.
//
// Settings (inline on the shell.json entry):
//   player     - which MPRIS player to follow (default "spotify")
//   anyPlayer  - fall back to whatever is playing when that one isn't open (default false)
//   maxWidth   - widest the track text may grow, in px (default 220)
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Mpris
import qs.Commons
import qs.Commons as Commons

Item {
  id: root

  property var bar
  property string moduleName
  property var settings: ({})

  function setting(name, fallback) {
    var v = settings ? settings[name] : undefined
    return v === undefined || v === null ? fallback : v
  }

  readonly property string wanted: String(setting("player", "spotify")).toLowerCase()
  readonly property bool anyPlayer: setting("anyPlayer", false) === true
  readonly property int maxTextWidth: Number(setting("maxWidth", 220))

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : 34
  readonly property color ink: bar ? bar.barForeground : Commons.Color.foreground
  readonly property string fontName: bar && bar.fontFamily ? bar.fontFamily : "monospace"
  readonly property string dimInk: Qt.rgba(ink.r, ink.g, ink.b, 0.55).toString()

  function escape(text) {
    return String(text || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }

  function matches(p) {
    if (!p) return false
    var names = [p.identity, p.desktopEntry, p.dbusName]
    for (var i = 0; i < names.length; i++)
      if (String(names[i] || "").toLowerCase().indexOf(root.wanted) !== -1) return true
    return false
  }

  readonly property var player: {
    var list = Mpris.players.values
    var fallback = null
    for (var i = 0; i < list.length; i++) {
      if (root.matches(list[i])) return list[i]
      if (root.anyPlayer && list[i].isPlaying && !fallback) fallback = list[i]
    }
    return fallback
  }

  readonly property bool active: player !== null && !!(player.trackTitle || player.trackArtist)
  readonly property bool playing: active && player.isPlaying
  readonly property string title: active ? (player.trackTitle || "") : ""
  readonly property string artist: active ? (player.trackArtist || "") : ""
  readonly property string artUrl: active && player.trackArtUrl ? player.trackArtUrl : ""
  readonly property real progress: active && player.lengthSupported && player.length > 0
    ? Math.max(0, Math.min(1, player.position / player.length)) : 0

  // MPRIS doesn't announce position as it moves; ask once a second while playing.
  Timer {
    interval: 1000
    repeat: true
    running: root.playing && root.visible
    onTriggered: if (root.player) root.player.positionChanged()
  }

  function openApp() {
    if (bar) bar.run(root.wanted === "spotify" ? "omarchy-launch-spotify" : "omarchy-launch-or-focus " + Util.shellQuote(root.wanted))
  }

  visible: active
  implicitWidth: !active ? 0 : (vertical ? barSize : content.implicitWidth + Style.space(6))
  implicitHeight: !active ? 0 : (vertical ? content.implicitHeight + Style.space(6) : barSize)

  // ── pieces ─────────────────────────────────────────────────────────────
  component Glyph: Item {
    id: glyph
    property string icon: ""
    property real size: Style.font.icon
    property bool enabledAction: true
    signal clicked()

    implicitWidth: Math.round(root.barSize * 0.62)
    implicitHeight: root.barSize

    Text {
      anchors.centerIn: parent
      text: glyph.icon
      color: root.ink
      font.family: root.fontName
      font.pixelSize: glyph.size
      opacity: !glyph.enabledAction ? 0.3 : (tap.pressed ? 0.55 : (hover.hovered ? 1.0 : 0.78))
      scale: tap.pressed ? 0.88 : (hover.hovered ? 1.08 : 1.0)
      Behavior on scale { NumberAnimation { duration: Style.duration(160); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }
      Behavior on opacity { NumberAnimation { duration: Style.duration(140) } }
    }
    HoverHandler { id: hover; cursorShape: glyph.enabledAction ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler { id: tap; enabled: glyph.enabledAction; onTapped: glyph.clicked() }
  }

  component Disc: Item {
    id: disc
    implicitWidth: Math.round(root.barSize * 0.72)
    implicitHeight: implicitWidth

    // The cover, masked to a circle.
    Image {
      id: cover
      anchors.fill: parent
      source: root.artUrl
      sourceSize: Qt.size(disc.width * 2, disc.height * 2)
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      smooth: true
      visible: false
      layer.enabled: true
    }
    Rectangle {
      id: circleMask
      anchors.fill: parent
      radius: width / 2
      visible: false
      layer.enabled: true
    }
    MultiEffect {
      id: art
      anchors.fill: parent
      source: cover
      maskEnabled: true
      maskSource: circleMask
      maskThresholdMin: 0.5
      maskSpreadAtMin: 1.0
      visible: cover.status === Image.Ready
      // Turns like a record while playing and rests where it stopped.
      RotationAnimator on rotation {
        from: 0; to: 360
        duration: 24000
        loops: Animation.Infinite
        running: root.playing && !Style.reduceMotion
      }
    }
    // No cover yet: a quiet disc in the accent color.
    Rectangle {
      anchors.fill: parent
      radius: width / 2
      visible: cover.status !== Image.Ready
      color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.35)
      Text {
        anchors.centerIn: parent
        text: "\u{F075A}"
        color: root.ink
        font.family: root.fontName
        font.pixelSize: Style.font.iconSmall
      }
    }
    // Spindle and rim, so it reads as a disc.
    Rectangle {
      anchors.centerIn: parent
      width: Math.max(3, Math.round(parent.width * 0.16)); height: width; radius: width / 2
      color: root.bar ? root.bar.background : Commons.Color.background
      opacity: 0.85
      visible: art.visible
    }
    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: "transparent"
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.18)
    }

    HoverHandler { cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: if (root.player && root.player.canTogglePlaying) root.player.togglePlaying() }
  }

  // ── layout ─────────────────────────────────────────────────────────────
  Item {
    id: content
    anchors.centerIn: parent
    implicitWidth: root.vertical ? root.barSize : rowLayout.implicitWidth
    implicitHeight: root.vertical ? columnLayout.implicitHeight : root.barSize

    Row {
      id: rowLayout
      visible: !root.vertical
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Glyph {
        icon: "\u{F04AE}"
        enabledAction: !!root.player && root.player.canGoPrevious
        onClicked: root.player.previous()
      }
      Glyph {
        icon: root.playing ? "\u{F03E4}" : "\u{F040A}"
        size: Style.font.iconLarge
        enabledAction: !!root.player && root.player.canTogglePlaying
        onClicked: root.player.togglePlaying()
      }
      Glyph {
        icon: "\u{F04AD}"
        enabledAction: !!root.player && root.player.canGoNext
        onClicked: root.player.next()
      }

      Item { width: Style.space(4); height: 1 }

      Disc { anchors.verticalCenter: parent.verticalCenter }

      Item { width: Style.space(6); height: 1 }

      // Track and a hairline of progress beneath it.
      Item {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: Math.min(root.maxTextWidth, label.implicitWidth)
        implicitHeight: root.barSize

        Text {
          id: label
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: -1
          width: parent.width
          elide: Text.ElideRight
          textFormat: Text.StyledText
          text: root.artist
            ? root.escape(root.title) + "<font color='" + root.dimInk + "'>  ·  " + root.escape(root.artist) + "</font>"
            : root.escape(root.title)
          color: root.ink
          font.family: root.fontName
          font.pixelSize: Style.font.bodySmall
        }
        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: label.bottom
          anchors.topMargin: Style.space(2)
          height: 2
          radius: 1
          color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.14)
          Rectangle {
            height: parent.height
            radius: 1
            width: parent.width * root.progress
            color: Commons.Color.accent
            Behavior on width { NumberAnimation { duration: Style.duration(900) } }
          }
        }

        HoverHandler { id: trackHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { acceptedButtons: Qt.LeftButton; onTapped: root.openApp() }
        TapHandler { acceptedButtons: Qt.RightButton; onTapped: if (root.player && root.player.canGoNext) root.player.next() }
        WheelHandler {
          onWheel: function(event) {
            var p = root.player
            if (!p || !p.volumeSupported || !p.canControl) return
            var step = event.angleDelta.y > 0 ? 0.05 : -0.05
            p.volume = Math.max(0, Math.min(1, p.volume + step))
          }
        }
      }

      Item { width: Style.space(4); height: 1 }

      Glyph {
        icon: "\u{F02CB}"
        size: Style.font.iconSmall
        onClicked: root.openApp()
      }
    }

    // Vertical bar: just the disc and play/pause.
    Column {
      id: columnLayout
      visible: root.vertical
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(4)
      Disc { anchors.horizontalCenter: parent.horizontalCenter }
      Glyph {
        anchors.horizontalCenter: parent.horizontalCenter
        icon: root.playing ? "\u{F03E4}" : "\u{F040A}"
        onClicked: if (root.player) root.player.togglePlaying()
      }
    }
  }

  HoverHandler {
    id: wholeHover
    onHoveredChanged: {
      if (!root.bar) return
      if (hovered && root.active) root.bar.showTooltip(root, root.title + (root.artist ? "\n" + root.artist : "") + (root.player && root.player.trackAlbum ? "\n" + root.player.trackAlbum : ""))
      else root.bar.hideTooltip(root)
    }
  }
}
