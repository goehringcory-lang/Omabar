// The Google Keep card the drawer's Keep tile opens: your pinned notes and
// lists, each tinted in its Keep color, and editable right here. Tick an
// item, click any text to change it, add items at the bottom of a list,
// or remove one with the × that shows on hover. Changes show at once and
// are queued and sent to Keep by OmabarKeep.qml (bin/omabar-keep).
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
  property int pending: 0           // edits waiting to reach Keep
  property var conflicts: []        // [{ message }] edits Keep's version won over
  property date now: new Date()

  // How many open items a list shows before "+ 4 more".
  property int itemsShown: 6

  // After an item is added, the add field of that list takes the keyboard
  // again, so items can be typed one after another.
  property string refocusNote: ""

  // A text field has the keyboard. OmabarKeep holds back a sync's answer
  // until it doesn't, so nothing is redrawn under your typing.
  readonly property bool typing: {
    var focused = card.Window.activeFocusItem
    return !!focused && focused.objectName === "keepField"
  }

  signal openNote(string url)
  signal openKeep()
  signal connectRequested()
  signal refreshRequested()
  signal edit(var change)            // one change, as bin/omabar-keep edit takes it
  signal dismissConflicts()

  // Ends any typing: the field loses the keyboard and saves.
  function leaveFields() { card.forceActiveFocus() }

  readonly property int gap: Style.space(8)
  implicitWidth: Style.space(360)
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

  function statusText() {
    if (card.loading) return card.pending > 0 ? "Saving…" : "Syncing…"
    if (card.pending > 0) return card.pending === 1 ? "1 change waiting" : card.pending + " changes waiting"
    if (!card.synced) return ""
    var minutes = Math.floor((card.now.getTime() / 1000 - card.synced) / 60)
    if (minutes < 1) return "Synced just now"
    if (minutes < 60) return "Synced " + minutes + "m ago"
    var hours = Math.floor(minutes / 60)
    return "Synced " + (hours < 24 ? hours + "h" : Math.floor(hours / 24) + "d") + " ago"
  }

  // A click on the card's background ends typing.
  MouseArea { anchors.fill: parent; onPressed: card.leaveFields() }

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
          text: card.statusText()
          color: card.pending > 0 && !card.loading ? card.accent : card.ink
          opacity: card.pending > 0 && !card.loading ? 0.9 : 0.45
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
            onClicked: { card.leaveFields(); card.refreshRequested() }
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
          text: "See and edit your pinned notes and lists here"
          wrapMode: Text.WordWrap
          color: card.ink
          font.family: card.fontName
          font.pixelSize: Style.font.subtitle
          font.weight: Font.DemiBold
        }
        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "A browser window opens on Google's sign-in page. Sign in, click I agree, and Omabar finishes on its own. Your Keep token stays in your keyring."
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
      text: card.error + (card.pending > 0 ? " Your changes are saved here and will be sent when Keep can be reached." : "")
      color: card.urgent
      font.family: card.fontName
      font.pixelSize: Style.font.caption
    }

    // ── edits Keep's version won over ───────────────────────────────
    Rectangle {
      visible: card.conflicts.length > 0
      width: parent.width
      height: conflictColumn.implicitHeight + Style.space(20)
      radius: Style.space(12)
      color: card.tint(card.urgent, 0.12)
      border.width: 1
      border.color: card.tint(card.urgent, 0.35)

      Column {
        id: conflictColumn
        x: Style.space(12)
        y: Style.space(10)
        width: parent.width - Style.space(24)
        spacing: Style.space(6)

        Repeater {
          model: card.conflicts
          Text {
            required property var modelData
            width: conflictColumn.width
            wrapMode: Text.WordWrap
            text: "\u{F002A}  " + String(modelData.message || "")
            color: card.ink
            opacity: 0.85
            font.family: card.fontName
            font.pixelSize: Style.font.caption
          }
        }
        Text {
          text: "Got it"
          color: card.accent
          font.family: card.fontName
          font.pixelSize: Style.font.caption
          font.weight: Font.DemiBold
          MouseArea {
            anchors.fill: parent
            anchors.margins: -Style.space(6)
            cursorShape: Qt.PointingHandCursor
            onClicked: card.dismissConflicts()
          }
        }
      }
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
      height: Math.min(contentHeight, Style.space(470))
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
    readonly property string noteId: String(note.id || "")
    readonly property bool isList: note.kind === "list"
    readonly property bool colored: card.hasColor(note.color)
    readonly property color hue: card.noteColor(note.color)
    property bool showAll: false
    property bool showDone: false
    // A plain loop: the items can arrive as a Qt list, not a JS array.
    function itemsWhere(checked) {
      var list = note && note.items ? note.items : []
      var out = []
      for (var i = 0; i < (list.length || 0); i++) if (list[i] && !!list[i].checked === checked) out.push(list[i])
      return out
    }
    readonly property var openItems: itemsWhere(false)
    readonly property var doneItems: itemsWhere(true)

    height: body.implicitHeight + Style.space(22)
    radius: Style.space(12)
    color: colored ? card.tint(hue, tileHover.hovered ? 0.19 : 0.15) : card.tint(card.ink, tileHover.hovered ? 0.09 : 0.06)
    border.width: 1
    border.color: colored ? card.tint(hue, 0.35) : card.tint(card.ink, 0.08)
    Behavior on color { ColorAnimation { duration: Style.duration(120) } }

    HoverHandler { id: tileHover }

    Column {
      id: body
      x: Style.space(12)
      y: Style.space(11)
      width: parent.width - Style.space(24)
      spacing: Style.space(5)

      // Title, and a link to the note in Keep.
      Item {
        width: parent.width
        height: Math.max(titleField.implicitHeight, openGlyph.implicitHeight)
        Rectangle {
          id: dot
          visible: tile.colored
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(7); height: width; radius: width / 2
          color: tile.hue
        }
        Field {
          id: titleField
          anchors.left: tile.colored ? dot.right : parent.left
          anchors.leftMargin: tile.colored ? Style.space(6) : 0
          anchors.right: openGlyph.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          original: String(tile.note.title || "")
          placeholder: "Title"
          single: true
          strong: true
          onCommitted: function(value) {
            card.edit({ op: "title", note: tile.noteId, before: original, after: value })
          }
        }
        Text {
          id: openGlyph
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: "\u{F03CC}"
          color: openArea.containsMouse ? card.accent : card.ink
          opacity: tileHover.hovered ? (openArea.containsMouse ? 1 : 0.55) : 0
          font.family: card.fontName
          font.pixelSize: Style.font.bodySmall
          Behavior on opacity { NumberAnimation { duration: Style.duration(120) } }
          MouseArea {
            id: openArea
            anchors.fill: parent
            anchors.margins: -Style.space(5)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.openNote(String(tile.note.url || ""))
          }
        }
      }

      // A note's text, edited in place (Ctrl+Enter or clicking away saves).
      Field {
        visible: !tile.isList
        width: parent.width
        original: String(tile.note.text || "")
        placeholder: "Note"
        readOnly: !!tile.note.readOnly
        dim: 0.8
        onCommitted: function(value) {
          card.edit({ op: "noteText", note: tile.noteId, before: original, after: value })
        }
      }

      // A list's open items.
      Repeater {
        model: tile.isList ? (tile.showAll ? tile.openItems : tile.openItems.slice(0, card.itemsShown)) : []
        ItemRow { required property var modelData; item: modelData; noteId: tile.noteId; colored: tile.colored; hue: tile.hue; width: body.width }
      }

      Text {
        readonly property int more: tile.openItems.length - card.itemsShown
        visible: tile.isList && !tile.showAll && more > 0
        text: "+ " + more + " more"
        color: moreArea.containsMouse ? card.accent : card.ink
        opacity: moreArea.containsMouse ? 1 : 0.5
        font.family: card.fontName
        font.pixelSize: Style.font.caption
        MouseArea { id: moreArea; anchors.fill: parent; anchors.margins: -Style.space(4); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tile.showAll = true }
      }

      // Add an item: Enter adds it and stays here for the next one.
      Item {
        visible: tile.isList
        width: parent.width
        height: Math.max(plus.implicitHeight, addField.implicitHeight)
        Text {
          id: plus
          anchors.verticalCenter: parent.verticalCenter
          text: "\u{F0415}"
          color: tile.colored ? tile.hue : card.ink
          opacity: addField.activeFocus ? 0.9 : 0.45
          font.family: card.fontName
          font.pixelSize: Style.font.body
        }
        TextInput {
          id: addField
          objectName: "keepField"
          anchors.left: plus.right
          anchors.leftMargin: Style.space(6)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          color: card.ink
          selectionColor: card.tint(card.accent, 0.45)
          font.family: card.fontName
          font.pixelSize: Style.font.bodySmall
          clip: true
          Text {
            visible: !addField.text && !addField.activeFocus
            text: "List item"
            color: card.ink
            opacity: 0.4
            font: addField.font
          }
          Keys.onReturnPressed: function(event) { add(); event.accepted = true }
          Keys.onEnterPressed: function(event) { add(); event.accepted = true }
          Keys.onEscapePressed: function(event) { text = ""; card.leaveFields(); event.accepted = true }
          function add() {
            var value = text.trim()
            if (!value) { card.leaveFields(); return }
            text = ""
            card.refocusNote = tile.noteId
            card.edit({ op: "addItem", note: tile.noteId, text: value })
          }
          Component.onCompleted: if (card.refocusNote !== "" && card.refocusNote === tile.noteId) {
            card.refocusNote = ""
            Qt.callLater(addField.forceActiveFocus)
          }
          HoverHandler { cursorShape: Qt.IBeamCursor }
        }
      }

      // Ticked items: folded into a count; click it to see and untick them.
      Text {
        visible: tile.isList && tile.doneItems.length > 0
        topPadding: Style.space(2)
        text: tile.doneItems.length + " checked " + (tile.showDone ? "\u{F0143}" : "\u{F0140}")
        color: doneArea.containsMouse ? card.accent : card.ink
        opacity: doneArea.containsMouse ? 1 : 0.5
        font.family: card.fontName
        font.pixelSize: Style.font.caption
        MouseArea { id: doneArea; anchors.fill: parent; anchors.margins: -Style.space(4); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tile.showDone = !tile.showDone }
      }

      Repeater {
        model: tile.isList && tile.showDone ? tile.doneItems : []
        ItemRow { required property var modelData; item: modelData; noteId: tile.noteId; colored: tile.colored; hue: tile.hue; width: body.width }
      }
    }
  }

  // One list item: the box ticks it, the text edits it, × removes it.
  component ItemRow: Item {
    id: row
    property var item: ({})
    property string noteId: ""
    property bool colored: false
    property color hue: card.ink
    readonly property bool checked: !!item.checked

    height: Math.max(box.implicitHeight, field.implicitHeight)
    HoverHandler { id: rowHover }

    Text {
      id: box
      x: row.item.indented ? Style.space(16) : 0
      text: row.checked ? "\u{F0132}" : "\u{F0131}"
      color: boxArea.containsMouse ? card.accent : (row.colored ? row.hue : card.ink)
      opacity: row.checked ? 0.5 : (row.colored ? 0.9 : 0.55)
      font.family: card.fontName
      font.pixelSize: Style.font.body
      scale: boxArea.pressed ? 0.85 : 1
      Behavior on scale { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutBack } }
      MouseArea {
        id: boxArea
        anchors.fill: parent
        anchors.margins: -Style.space(4)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          card.leaveFields()
          card.edit({ op: "check", note: row.noteId, item: String(row.item.id || ""), checked: !row.checked })
        }
      }
    }

    Field {
      id: field
      anchors.left: box.right
      anchors.leftMargin: Style.space(6)
      anchors.right: remove.left
      anchors.rightMargin: Style.space(4)
      anchors.top: parent.top
      original: String(row.item.text || "")
      single: true
      struck: row.checked
      dim: row.checked ? 0.45 : 0.88
      onCommitted: function(value) {
        if (value === "") card.edit({ op: "deleteItem", note: row.noteId, item: String(row.item.id || "") })
        else card.edit({ op: "itemText", note: row.noteId, item: String(row.item.id || ""), before: original, after: value })
      }
    }

    Text {
      id: remove
      anchors.right: parent.right
      anchors.top: parent.top
      text: "\u{F0156}"
      color: removeArea.containsMouse ? card.urgent : card.ink
      opacity: rowHover.hovered ? (removeArea.containsMouse ? 1 : 0.45) : 0
      font.family: card.fontName
      font.pixelSize: Style.font.bodySmall
      Behavior on opacity { NumberAnimation { duration: Style.duration(100) } }
      MouseArea {
        id: removeArea
        anchors.fill: parent
        anchors.margins: -Style.space(4)
        hoverEnabled: true
        enabled: rowHover.hovered
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          card.leaveFields()
          card.edit({ op: "deleteItem", note: row.noteId, item: String(row.item.id || "") })
        }
      }
    }
  }

  // Text you can click into and change. Single-line fields save on Enter;
  // a note's text takes Enter as a new line and saves on Ctrl+Enter. Both
  // save when you click away, and Escape puts the text back.
  component Field: TextEdit {
    id: field
    property string original: ""
    property string placeholder: ""
    property bool single: false
    property bool strong: false
    property bool struck: false
    property real dim: 0.85
    property bool saved: false
    signal committed(string value)

    objectName: "keepField"
    text: original
    onOriginalChanged: if (!activeFocus) text = original
    wrapMode: TextEdit.Wrap
    textFormat: TextEdit.PlainText
    selectByMouse: true
    color: card.ink
    opacity: activeFocus ? 1 : dim
    selectionColor: card.tint(card.accent, 0.45)
    font.family: card.fontName
    font.pixelSize: strong ? Style.font.body : Style.font.bodySmall
    font.weight: strong ? Font.DemiBold : Font.Normal
    font.strikeout: struck

    Text {
      visible: field.text === "" && field.placeholder !== "" && !field.readOnly
      text: field.placeholder
      color: card.ink
      opacity: 0.35
      font: field.font
    }

    HoverHandler { cursorShape: field.readOnly ? Qt.ArrowCursor : Qt.IBeamCursor }

    function save() {
      if (saved || readOnly) return
      saved = true
      var value = single ? text.replace(/\s*\n\s*/g, " ").trim() : text.replace(/\s+$/, "")
      if (value !== original) committed(value)
    }

    onActiveFocusChanged: {
      if (activeFocus) saved = false
      else save()
    }
    Keys.onReturnPressed: function(event) {
      if (single || (event.modifiers & Qt.ControlModifier)) { card.leaveFields(); event.accepted = true }
      else event.accepted = false
    }
    Keys.onEnterPressed: function(event) {
      if (single || (event.modifiers & Qt.ControlModifier)) { card.leaveFields(); event.accepted = true }
      else event.accepted = false
    }
    Keys.onEscapePressed: function(event) {
      saved = true
      text = original
      card.leaveFields()
      event.accepted = true
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
      onClicked: { card.leaveFields(); pill.picked() }
    }
  }
}
