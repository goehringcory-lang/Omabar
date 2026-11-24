// Omabar player: a small Spotify player for the middle of the bar.
// Controls, round album art that turns slowly while music plays, the track,
// and a hairline of progress. The chevron opens a playlist menu with one-click
// Lofi Beats and Discover Weekly. With Spotify closed it rests as a small
// disc and chevron, so a playlist is still one click away.
//
// While a track is loaded the player bulges out of the bar: a glass capsule a
// little taller than the pill, with larger album art and the song and artist
// on two lines. It swells into the gap the bar floats in, so it never covers
// a window.
//
// Settings (inline on the shell.json entry):
//   player         - which MPRIS player to follow (default "spotify")
//   anyPlayer      - fall back to whatever is playing when that one isn't open (default false)
//   maxWidth       - widest the track text may grow, in px (default 220)
//   lofi           - link or URI behind the Lofi Beats button (default: Cory's Lofi Beats playlist)
//   discoverWeekly - your Discover Weekly link (it's different for every account)
//   shuffleLiked   - turn shuffle on when the Liked Songs button starts them (default true)
//   playlists      - extra pinned playlists: [{ "name": "…", "uri": "…" }]
//   showIdle       - keep the small disc and chevron while Spotify is closed (default true)
//   bulge          - swell out of the bar while a track is loaded (default true)
//   spin           - turn the album art while music plays (default true)
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
  readonly property bool showIdle: setting("showIdle", true) !== false
  readonly property bool spin: setting("spin", true) !== false
  readonly property string helper: String(Qt.resolvedUrl("../bin/omabar-spotify")).replace(/^file:\/\//, "")

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : 34
  readonly property color ink: bar ? bar.barForeground : Commons.Color.foreground
  readonly property string fontName: bar && bar.fontFamily ? bar.fontFamily : "monospace"
  // How far the capsule reaches past the bar on each side, eased in and out.
  readonly property bool bulging: active && !vertical && setting("bulge", true) !== false
  property real bulge: bulging ? Style.space(6) : 0
  Behavior on bulge { NumberAnimation { duration: Style.duration(320); easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
  readonly property int discSize: Math.round(barSize * 0.72 + bulge * 2)
  // The cover is decoded once, at twice the largest size the disc reaches.
  // Tying it to discSize would fetch and decode the art again on every frame
  // of the bulge.
  readonly property int coverPixels: Math.round(barSize * 0.72 + Style.space(6) * 2) * 2
  readonly property color base: bar && bar.background ? bar.background : Commons.Color.background
  readonly property bool lightBase: (0.2126 * base.r + 0.7152 * base.g + 0.0722 * base.b) > 0.55

  readonly property string dimInk: Qt.rgba(ink.r, ink.g, ink.b, 0.55).toString()

  function escapeText(text) {
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

  // What the player reports right now. Spotify clears its track for a moment
  // between songs, around ads and while it starts up.
  readonly property bool hasTrack: player !== null && !!(player.trackTitle || player.trackArtist)
  // Spotify marks an ad by its track id; ads often come with no artist or cover.
  readonly property bool isAd: {
    if (!hasTrack) return false
    var meta = player.metadata
    var id = String(meta && meta["mpris:trackid"] || "")
    return id.indexOf("/ad/") !== -1 || id.indexOf(":ad:") !== -1
  }
  readonly property string liveTitle: hasTrack ? (player.trackTitle || (isAd ? "Advertisement" : "")) : ""
  readonly property string liveArtist: hasTrack ? (player.trackArtist || (isAd && player.trackTitle ? "Advertisement" : "")) : ""
  readonly property string liveArt: hasTrack && player.trackArtUrl ? player.trackArtUrl : ""

  // What the bar shows. It keeps the last track through those short gaps, so
  // the capsule doesn't collapse and swell again on every song change.
  property bool active: false
  property string title: ""
  property string artist: ""
  property string artUrl: ""
  function settle() {
    if (hasTrack) {
      linger.stop()
      title = liveTitle; artist = liveArtist; artUrl = liveArt
      active = true
    } else if (player !== null && active) {
      linger.restart()
    } else {
      linger.stop()
      active = false
      title = ""; artist = ""; artUrl = ""
    }
  }
  // Title, artist and cover change one after another; settle once they all have.
  onHasTrackChanged: Qt.callLater(root.settle)
  onPlayerChanged: Qt.callLater(root.settle)
  onLiveTitleChanged: Qt.callLater(root.settle)
  onLiveArtistChanged: Qt.callLater(root.settle)
  onLiveArtChanged: Qt.callLater(root.settle)
  Component.onCompleted: settle()
  Timer {
    id: linger
    interval: 1500
    onTriggered: if (!root.hasTrack) { root.active = false; root.title = ""; root.artist = ""; root.artUrl = "" }
  }

  readonly property bool playing: hasTrack && player.isPlaying
  readonly property real progress: hasTrack && player.lengthSupported && player.length > 0
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

  // Shown while something plays, or resting as disc + chevron when idle.
  readonly property bool shown: active || (showIdle && !vertical)
  property bool menuOpen: false
  // Called by the bar when another popup opens or a click lands outside.
  function close() { menuOpen = false }

  function play(uri) {
    if (bar && uri) bar.run(Util.shellQuote(root.helper) + " play " + Util.shellQuote(uri))
    root.menuOpen = false
  }

  function playLiked() {
    if (bar) bar.run(Util.shellQuote(root.helper) + " liked" + (setting("shuffleLiked", true) !== false ? "" : " --no-shuffle"))
    root.menuOpen = false
  }

  visible: shown
  implicitWidth: !shown ? 0 : (vertical ? barSize : content.implicitWidth + Style.space(6) + Math.round(bulge * 3))
  implicitHeight: !shown ? 0 : (vertical ? content.implicitHeight + Style.space(6) : barSize)

  OmabarPlaylists {
    anchorItem: chevron
    player: root
    open: root.menuOpen
    onDismissed: root.menuOpen = false
  }

  // ── pieces ─────────────────────────────────────────────────────────────
  component Glyph: Item {
    id: glyph
    property string icon: ""
    property real size: Style.font.icon
    property bool enabledAction: true
    property real turn: 0
    signal clicked()

    implicitWidth: Math.round(root.barSize * 0.62)
    implicitHeight: root.barSize

    Text {
      anchors.centerIn: parent
      text: glyph.icon
      color: root.ink
      font.family: root.fontName
      font.pixelSize: glyph.size
      rotation: glyph.turn
      Behavior on rotation { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
      opacity: !glyph.enabledAction ? 0.3 : (tap.held ? 0.55 : (hover.hovered ? 1.0 : 0.78))
      scale: tap.held ? 0.88 : (hover.hovered ? 1.08 : 1.0)
      Behavior on scale { NumberAnimation { duration: Style.duration(160); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }
      Behavior on opacity { NumberAnimation { duration: Style.duration(140) } }
    }
    HoverHandler { id: hover; cursorShape: glyph.enabledAction ? Qt.PointingHandCursor : Qt.ArrowCursor }
    OmabarClickTarget { id: tap; anchors.fill: parent; bar: root.bar; enabled: glyph.enabledAction; onPressed: glyph.clicked() }
  }

  component Disc: Item {
    id: disc
    property int size: Math.round(root.barSize * 0.72)
    // True from the first cover that loads until there is no cover at all.
    property bool hasCover: false
    implicitWidth: size
    implicitHeight: size

    // The cover, masked to a circle.
    Image {
      id: cover
      anchors.fill: parent
      source: root.artUrl
      sourceSize: Qt.size(root.coverPixels, root.coverPixels)
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      // Keeps the last cover up while the next one loads, so a track change
      // swaps covers instead of flashing the logo in between.
      retainWhileLoading: true
      mipmap: true
      smooth: true
      visible: false
      layer.enabled: true; layer.smooth: true
      onStatusChanged: {
        if (status === Image.Ready) disc.hasCover = true
        else if (status === Image.Error || status === Image.Null) disc.hasCover = false
      }
    }
    Connections {
      target: root
      function onArtUrlChanged() { if (root.artUrl === "") disc.hasCover = false }
    }
    Rectangle {
      id: circleMask
      anchors.fill: parent
      radius: width / 2
      visible: false
      layer.enabled: true; layer.smooth: true
    }
    MultiEffect {
      id: art
      anchors.fill: parent
      source: cover
      maskEnabled: true
      maskSource: circleMask
      maskThresholdMin: 0.5
      maskSpreadAtMin: 1.0
      visible: disc.hasCover
    }
    // Turns like a record while playing and rests where it stopped. A record
    // turns slowly (once in 24 seconds), so fifteen small steps a second look
    // the same as sixty, and the bar and the blur behind it are redrawn a
    // quarter as often.
    Timer {
      interval: 66
      repeat: true
      running: root.playing && root.spin && art.visible && !Style.reduceMotion
      onTriggered: art.rotation = (art.rotation + 0.99) % 360
    }
    // No cover (Spotify closed, nothing loaded, or an ad): the Spotify logo in
    // its own green on a dark disc. Another player keeps a plain music note.
    Rectangle {
      id: blank
      readonly property bool spotify: root.wanted === "spotify"
      anchors.fill: parent
      radius: width / 2
      visible: !disc.hasCover
      color: spotify
        ? Qt.rgba(root.base.r * 0.5, root.base.g * 0.5, root.base.b * 0.5, 0.9)
        : Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.35)
      Text {
        anchors.centerIn: parent
        text: blank.spotify ? "\u{F04C7}" : "\u{F075A}"
        color: blank.spotify ? "#1ed760" : root.ink
        font.family: root.fontName
        // The logo fills the disc; the note sits small in the middle.
        font.pixelSize: blank.spotify ? Math.round(blank.height * 0.82) : Style.font.iconSmall
        opacity: !blank.spotify || root.hasTrack || discHover.hovered ? 1.0 : 0.85
        Behavior on opacity { NumberAnimation { duration: Style.duration(140) } }
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
      border.color: root.lightBase ? Qt.rgba(0, 0, 0, 0.12) : Qt.rgba(1, 1, 1, 0.18)
    }

    HoverHandler { id: discHover; cursorShape: Qt.PointingHandCursor }
    OmabarClickTarget {
      anchors.fill: parent
      bar: root.bar
      onPressed: {
        if (root.player && root.player.canTogglePlaying) root.player.togglePlaying()
        else root.openApp()
      }
    }
  }

  // ── the bulge ──────────────────────────────────────────────────────────
  // A glass capsule behind the player, taller than the bar by `bulge` on each
  // side. Drawn outside the widget's own bounds, which the bar doesn't clip.
  Item {
    id: capsule
    visible: root.bulge > 0.5
    z: -1
    anchors.centerIn: parent
    width: parent.width
    height: root.barSize + root.bulge * 2
    opacity: Math.min(1, root.bulge / Style.space(4))

    RectangularShadow {
      anchors.fill: capsuleGlass
      radius: capsuleGlass.radius
      offset.y: Style.space(2)
      blur: Style.space(12)
      spread: -Style.space(1)
      color: Qt.rgba(0, 0, 0, root.lightBase ? 0.16 : 0.38)
    }
    Rectangle {
      id: capsuleGlass
      anchors.fill: parent
      radius: height / 2
      color: Qt.rgba(root.base.r, root.base.g, root.base.b, 0.82)
      border.width: 1
      border.color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.30)
    }
    // Light across the top half, like the bar's own sheen.
    Rectangle {
      anchors.fill: parent
      anchors.margins: 1
      radius: height / 2
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, root.lightBase ? 0.5 : 0.12) }
        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, root.lightBase ? 0.10 : 0.02) }
        GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
      }
    }
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
        visible: root.active
        enabledAction: !!root.player && root.player.canGoPrevious
        onClicked: if (root.player) root.player.previous()
      }
      Glyph {
        icon: root.playing ? "\u{F03E4}" : "\u{F040A}"
        size: Style.font.iconLarge
        visible: root.active
        enabledAction: !!root.player && root.player.canTogglePlaying
        onClicked: if (root.player) root.player.togglePlaying()
      }
      Glyph {
        icon: "\u{F04AD}"
        visible: root.active
        enabledAction: !!root.player && root.player.canGoNext
        onClicked: if (root.player) root.player.next()
      }

      Item { width: Style.space(4); height: 1; visible: root.active }

      Disc { anchors.verticalCenter: parent.verticalCenter; size: root.discSize }

      Item { width: Style.space(6); height: 1 }

      // Track and a hairline of progress beneath it.
      Item {
        id: track
        visible: root.active
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: Math.min(root.maxTextWidth, Math.max(label.implicitWidth, artistLine.visible ? artistLine.implicitWidth : 0))
        implicitHeight: root.barSize

        Column {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width
          spacing: 1

          // Bulging: the song, with the artist on its own line beneath.
          // Flat: both on one line.
          Text {
            id: label
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.StyledText
            text: root.artist && !root.bulging
              ? root.escapeText(root.title) + "<font color='" + root.dimInk + "'>  ·  " + root.escapeText(root.artist) + "</font>"
              : root.escapeText(root.title)
            color: root.ink
            font.family: root.fontName
            font.pixelSize: Style.font.bodySmall
            font.weight: root.bulging ? Font.DemiBold : Font.Normal
          }
          Text {
            id: artistLine
            visible: root.bulging && root.artist !== ""
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: root.artist
            color: root.ink
            opacity: 0.6
            font.family: root.fontName
            font.pixelSize: Style.font.caption
          }
          Item { width: 1; height: Style.space(2) }
          Rectangle {
            width: parent.width
            height: 2
            radius: 1
            color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.14)
            Rectangle {
              id: fill
              height: parent.height
              radius: 1
              color: Commons.Color.accent
              // Moves in whole pixels, so the bar is redrawn only when the
              // line has somewhere to go, and eases only across a jump (a
              // seek or a new track) instead of animating all the time.
              readonly property int goal: Math.round(parent.width * root.progress)
              onGoalChanged: {
                if (Math.abs(goal - width) > Style.space(6) && !Style.reduceMotion) {
                  jump.to = goal
                  jump.restart()
                } else {
                  jump.stop()
                  width = goal
                }
              }
              Component.onCompleted: width = goal
              NumberAnimation { id: jump; target: fill; property: "width"; duration: Style.duration(260); easing.type: Easing.OutCubic }
            }
          }
        }

        HoverHandler { id: trackHover; cursorShape: Qt.PointingHandCursor }
        OmabarClickTarget {
          anchors.fill: parent
          bar: root.bar
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onPressed: function(button) {
            if (button === Qt.RightButton) { if (root.player && root.player.canGoNext) root.player.next() }
            else root.openApp()
          }
        }
        WheelHandler {
          onWheel: function(event) {
            var p = root.player
            if (!p || !p.volumeSupported || !p.canControl || event.angleDelta.y === 0) return
            var step = event.angleDelta.y > 0 ? 0.05 : -0.05
            p.volume = Math.max(0, Math.min(1, p.volume + step))
          }
        }
      }

      // Resting state: Spotify is closed.
      Text {
        visible: !root.active
        anchors.verticalCenter: parent.verticalCenter
        text: root.wanted === "spotify" ? "Spotify" : root.wanted.charAt(0).toUpperCase() + root.wanted.slice(1)
        color: root.ink
        opacity: restHover.hovered ? 1.0 : 0.6
        font.family: root.fontName
        font.pixelSize: Style.font.bodySmall
        // Resting: a click on the disc or the name opens Spotify.
        HoverHandler { id: restHover; cursorShape: Qt.PointingHandCursor }
        OmabarClickTarget { anchors.fill: parent; bar: root.bar; onPressed: root.openApp() }
      }

      Item { width: Style.space(2); height: 1 }

      Glyph {
        id: chevron
        icon: "\u{F0140}"
        turn: root.menuOpen ? 180 : 0
        size: Style.font.iconSmall
        onClicked: root.menuOpen = !root.menuOpen
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
        enabledAction: !root.player || root.player.canTogglePlaying
        onClicked: {
          if (root.player) root.player.togglePlaying()
          else root.openApp()
        }
      }
    }
  }

  readonly property string tooltipText: !active ? ""
    : title + (artist ? "\n" + artist : "") + (hasTrack && player.trackAlbum ? "\n" + player.trackAlbum : "")
  // The bar only shows a tooltip for a target that says it is hovered.
  readonly property bool tooltipHovered: wholeHover.hovered
  function syncTooltip() {
    if (!bar || typeof bar.showTooltip !== "function") return
    if (wholeHover.hovered && tooltipText !== "" && !menuOpen) bar.showTooltip(root, tooltipText)
    else bar.hideTooltip(root)
  }
  // Follow the song while the pointer rests on the player.
  onTooltipTextChanged: if (wholeHover.hovered) syncTooltip()
  onMenuOpenChanged: syncTooltip()

  HoverHandler {
    id: wholeHover
    onHoveredChanged: root.syncTooltip()
  }
}
