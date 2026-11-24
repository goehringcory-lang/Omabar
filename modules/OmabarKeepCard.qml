// The Google Keep card the drawer's Keep tile opens: your pinned notes and
// lists, each tinted in its Keep color, with a button that opens all of them
// in Keep on the web. Fed by bin/omabar-keep through OmabarKeep.qml.
import QtQuick
import qs.Commons
import qs.Commons as Commons

Item {
  id: card

  property color ink: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property color urgent: Commons.Color.urgent
  property string fontName: "monospace"

  property bool connected: false
  property bool loading: false      // a sync is running
  property bool loaded: false       // something (cache or sync) has answered
  property string error: ""
  property var notes: []
  property real synced: 0           // seconds since the epoch
  property date now: new Date()

  // How many open items a list shows before "+ 4 more".
  property int itemsShown: 6

  signal openNote(string url)
  signal openKeep()
  signal connectRequested()
  signal refreshRequested()

  readonly property int pad: Style.space(2)
  readonly property int gap: Style.space(8)
  implicitWidth: Style.space(340)
  implicitHeight: column.implicitHeight

  // Keep's own note colors.
  readonly property var keepColors: ({
    "RED": "#f28b82", "ORANGE": "#fbbc04", "YELLOW": "#fff475", "GREEN": "#ccff90",
    "TEAL": "#a7ffeb", "BLUE": "#cbf0f8", "CERULEAN": "#aecbfa", "PURPLE": "#d7aefb",
    "PINK": "#fdcfe8", "BROWN": "#e6c9a8", "GRAY": "#e8eaed"
  })
  function hasColor(name) { return !!keepColors[String(name || "")] }
  function noteColor(name) { return hasColor(name) ? keepColors[name] : ink }
  function tint(value, alpha) { var c = Qt.color(value); return Qt.rgba(c.r, c.g, c.b, alpha) }

  function syncedText() {
    if (card.loading) return "Syncing…"
    if (!card.synced) return ""
    var minutes = Math.floor((card.now.getTime() / 1000 - card.synced) / 60)
    if (minutes < 1) return "Just now"
    if (minutes < 60) return minutes + "m ago"
    var hours = Math.floor(minutes / 60)
    return hours < 24 ? hours + "h ago" : Math.floor(hours / 24) + "d ago"
  }

  Column {
    id: column
    width: parent.width
    spacing: card.gap

    // ── heading ──────────────────────────────────────────────────────
    Item {
      width: parent.width
      height: Math.max(heading.implicitHeight, refresh.implicitHeight)

      Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "\u{F06DC}"
          color: card.accent
          font.family: card.fontName
          font.pixelSize: Style.font.title
        }
        Text {
          id: heading
          anchors.verticalCenter: parent.verticalCenter
          text: card.connected ? "Pinned in Keep" : "Google Keep"
          color: card.ink
          opacity: 0.55
          font.family: card.fontName
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1.2
          font.capitalization: Font.AllUppercase
        }
      }

      Row {
        id: refresh
        visible: card.connected
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: card.syncedText()
          color: card.ink
          opacity: 0.45
          font.family: card.fontName
          font.pixelSize: Style.font.caption
        }
        Text {
          id: refreshGlyph
          anchors.verticalCenter: parent.verticalCenter
          text: "\u{F0450}"
          color: refreshArea.containsMouse ? card.accent : card.ink
          opacity: refreshArea.containsMouse || card.loading ? 1 : 0.55
          font.family: card.fontName
          font.pixelSize: Style.font.body
          // Turns only while a sync runs, and only in this card's own window.
          RotationAnimator on rotation {
            running: card.loading
            from: 0; to: 360
            duration: 900
            loops: Animation.Infinite
            onRunningChanged: if (!running) refreshGlyph.rotation = 0
          }
          MouseArea {
            id: refreshArea
            anchors.fill: parent
            anchors.margins: -Style.space(6)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: !card.loading
            onClicked: card.refreshRequested()
          }
        }
      }
    }

    // ── not connected yet ───────────────────────────────────────────
    Rectangle {
      visible: !card.connected && card.loaded
      width: parent.width
      height: setupColumn.implicitHeight + Style.space(28)
      radius: Style.space(14)
      color: card.tint(card.ink, 0.06)

      Column {
        id: setupColumn
        anchors.centerIn: parent
        width: parent.width - Style.space(28)
        spacing: Style.space(8)

        Text {
          width: parent.width
          text: "See your pinned notes and lists here"
          wrapMode: Text.WordWrap
          color: card.ink
          font.family: card.fontName
          font.pixelSize: Style.font.subtitle
          font.weight: Font.DemiBold
        }
        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "Google has no Keep API for personal accounts, so setup signs in the way Keep's phone app does. It takes one cookie from your browser and about two minutes. The token stays in your keyring."
          color: card.ink
          opacity: 0.65
          font.family: card.fontName
          font.pixelSize: Style.font.bodySmall
          lineHeight: 1.1
        }
        PillButton {
          label: "Set up Keep"
          glyph: "\u{F0339}"
          strong: true
          onPicked: card.connectRequested()
        }
      }
    }

    // ── a sync that failed ──────────────────────────────────────────
    Text {
      visible: card.error !== ""
      width: parent.width
      wrapMode: Text.WordWrap
      text: card.error
      color: card.urgent
      font.family: card.fontName
      font.pixelSize: Style.font.caption
    }

    // ── first sync ──────────────────────────────────────────────────
    Text {
      visible: card.connected && card.notes.length === 0 && (card.loading || !card.loaded)
      width: parent.width
      text: "Getting your notes from Keep…"
      color: card.ink
      opacity: 0.55
      font.family: card.fontName
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      visible: card.connected && card.loaded && !card.loading && card.notes.length === 0 && card.error === ""
      width: parent.width
      wrapMode: Text.WordWrap
      text: "Nothing pinned yet. Pin a note or list in Keep and it shows up here."
      color: card.ink
      opacity: 0.55
      font.family: card.fontName
      font.pixelSize: Style.font.bodySmall
    }

    // ── the pinned notes ────────────────────────────────────────────
    Flickable {
      id: scroller
      visible: card.notes.length > 0
      width: parent.width
      height: Math.min(contentHeight, Style.space(430))
      contentHeight: notesColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: notesColumn
        width: scroller.width
        spacing: Style.space(8)
        Repeater {
          model: card.notes
          NoteTile { required property var modelData; note: modelData; width: notesColumn.width }
        }
      }
    }

    // ── all the rest, on the web ────────────────────────────────────
    PillButton {
      width: parent.width
      label: "Open all notes in Keep"
      glyph: "\u{F03CC}"
      strong: card.connected
      onPicked: card.openKeep()
    }
  }

  // ── pieces ──────────────────────────────────────────────────────────
  component NoteTile: Rectangle {
    id: tile
    property var note: ({})
    readonly property bool isList: note.kind === "list"
    readonly property bool colored: card.hasColor(note.color)
    readonly property color hue: card.noteColor(note.color)
    readonly property var openItems: {
      // A plain loop: the items can arrive as a Qt list, not a JS array.
      var list = note && note.items ? note.items : []
      var open = []
      for (var i = 0; i < (list.length || 0); i++) if (list[i] && !list[i].checked) open.push(list[i])
      return open
    }

    height: body.implicitHeight + Style.space(22)
    radius: Style.space(12)
    color: colored ? card.tint(hue, noteArea.containsMouse ? 0.22 : 0.15) : card.tint(card.ink, noteArea.containsMouse ? 0.11 : 0.06)
    border.width: 1
    border.color: colored ? card.tint(hue, 0.35) : card.tint(card.ink, 0.08)
    scale: noteArea.pressed ? 0.985 : 1
    Behavior on color { ColorAnimation { duration: Style.duration(120) } }
    Behavior on scale { NumberAnimation { duration: Style.duration(140); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }

    MouseArea {
      id: noteArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: card.openNote(String(tile.note.url || ""))
    }

    Column {
      id: body
      x: Style.space(12)
      y: Style.space(11)
      width: parent.width - Style.space(24)
      spacing: Style.space(5)

      Row {
        width: parent.width
        spacing: Style.space(6)
        visible: titleText.text !== ""
        Rectangle {
          visible: tile.colored
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(7); height: width; radius: width / 2
          color: tile.hue
        }
        Text {
          id: titleText
          width: parent.width - (tile.colored ? Style.space(13) : 0)
          text: String(tile.note.title || "")
          elide: Text.ElideRight
          color: card.ink
          font.family: card.fontName
          font.pixelSize: Style.font.body
          font.weight: Font.DemiBold
        }
      }

      // A note's text.
      Text {
        visible: !tile.isList && text !== ""
        width: parent.width
        text: String(tile.note.text || "")
        wrapMode: Text.Wrap
        maximumLineCount: 5
        elide: Text.ElideRight
        textFormat: Text.PlainText
        color: card.ink
        opacity: 0.8
        font.family: card.fontName
        font.pixelSize: Style.font.bodySmall
        lineHeight: 1.1
      }

      // A list's open items, then how many more and how many are done.
      Repeater {
        model: tile.isList ? tile.openItems.slice(0, card.itemsShown) : []
        Row {
          required property var modelData
          width: body.width
          spacing: Style.space(6)
          leftPadding: modelData.indented ? Style.space(16) : 0
          Text {
            id: box
            text: "\u{F0131}"
            color: tile.colored ? tile.hue : card.ink
            opacity: tile.colored ? 0.9 : 0.5
            font.family: card.fontName
            font.pixelSize: Style.font.body
          }
          Text {
            width: parent.width - box.width - parent.spacing - parent.leftPadding
            anchors.verticalCenter: box.verticalCenter
            text: String(modelData.text || "")
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            textFormat: Text.PlainText
            color: card.ink
            opacity: 0.85
            font.family: card.fontName
            font.pixelSize: Style.font.bodySmall
          }
        }
      }

      Text {
        readonly property int more: Math.max(0, tile.openItems.length - card.itemsShown)
        readonly property int done: Number(tile.note.checked) || 0
        visible: tile.isList && (more > 0 || done > 0 || tile.openItems.length === 0)
        width: parent.width
        text: {
          var parts = []
          if (more > 0) parts.push("+ " + more + " more")
          if (done > 0) parts.push(done + " checked")
          if (tile.openItems.length === 0 && done === 0) parts.push("Empty list")
          return parts.join("  ·  ")
        }
        color: card.ink
        opacity: 0.5
        font.family: card.fontName
        font.pixelSize: Style.font.caption
      }
    }
  }

  component PillButton: Rectangle {
    id: pill
    property string label: ""
    property string glyph: ""
    property bool strong: false
    signal picked()

    implicitWidth: pillRow.implicitWidth + Style.space(28)
    height: Style.space(36)
    radius: height / 2
    color: strong
      ? card.tint(card.accent, pillArea.containsMouse ? 0.30 : 0.20)
      : card.tint(card.ink, pillArea.containsMouse ? 0.13 : 0.07)
    scale: pillArea.pressed ? 0.97 : 1
    Behavior on color { ColorAnimation { duration: Style.duration(120) } }
    Behavior on scale { NumberAnimation { duration: Style.duration(140); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }

    Row {
      id: pillRow
      anchors.centerIn: parent
      spacing: Style.space(7)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: pill.label
        color: pill.strong || pillArea.containsMouse ? card.accent : card.ink
        font.family: card.fontName
        font.pixelSize: Style.font.bodySmall
        font.weight: Font.DemiBold
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: pill.glyph
        color: pill.strong || pillArea.containsMouse ? card.accent : card.ink
        font.family: card.fontName
        font.pixelSize: Style.font.body
      }
    }

    MouseArea {
      id: pillArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: pill.picked()
    }
  }
}
