// The Ask box's drop-down: a row of chat sites to pick from, a text box for
// the question, a mic for dictation and a send button. Enter asks, Shift+Enter
// starts a new line, Up brings back the last question, Escape closes. Ctrl+V
// with a screenshot or photo on the clipboard adds it as a small thumbnail at
// the top of the box (up to four); hover one and click its × to take it out.
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import qs.Commons
import qs.Commons as Commons
import "OmabarAskModel.js" as Model

FocusScope {
  id: card

  property color ink: Commons.Color.popups.text
  property color accent: Commons.Color.accent
  property string fontName: "monospace"
  property var providers: Model.PROVIDERS
  property string providerId: "claude"
  property bool listening: false
  property bool dictationReady: true
  property var history: []
  // Paths of the pictures pasted in (saved by bin/omabar-ask-image).
  property var pictures: []
  // A short note under the box for a moment, e.g. when it's full.
  property string note: ""

  readonly property var current: Model.provider(card.providerId)
  readonly property bool hasText: Model.clean(field.text) !== ""
  readonly property bool hasPictures: card.pictures.length > 0
  readonly property bool canAsk: card.hasText || card.hasPictures
  readonly property bool typing: field.activeFocus
  property alias text: field.text
  // Ink that reads on the accent color, as on the Omarchy button's tile.
  readonly property bool lightAccent: (0.2126 * accent.r + 0.7152 * accent.g + 0.0722 * accent.b) > 0.5
  readonly property color onAccent: lightAccent ? Qt.rgba(0.06, 0.06, 0.08, 0.92) : Qt.rgba(1, 1, 1, 0.95)

  signal ask(string providerId, string text)
  signal pickProvider(string providerId)
  signal toggleDictation()
  signal closeRequested()
  // Ctrl+V: the owner looks for a picture on the clipboard, and calls
  // pasteText() if there is none.
  signal pasteRequested()
  signal removePicture(string path)

  property int recall: -1

  function focusField() {
    field.forceActiveFocus()
    field.cursorPosition = field.length
  }

  function clear() {
    field.text = ""
    card.recall = -1
  }

  function submit() {
    if (!card.canAsk) return
    card.ask(card.providerId, field.text)
  }

  function pasteText() {
    field.paste()
  }

  function flash(text) {
    card.note = text
    noteTimer.restart()
  }

  Timer {
    id: noteTimer
    interval: 2400
    onTriggered: card.note = ""
  }

  // Built on the first open, after the panel has asked for focus.
  Component.onCompleted: Qt.callLater(card.focusField)

  implicitWidth: Style.space(440)
  implicitHeight: body.implicitHeight

  Column {
    id: body
    width: card.width
    spacing: Style.space(10)

    // ── which chat ───────────────────────────────────────────────────
    Flow {
      width: parent.width
      spacing: Style.space(4)
      Repeater {
        model: card.providers
        delegate: Rectangle {
          id: chip
          required property var modelData
          readonly property bool chosen: modelData.id === card.providerId
          height: Style.space(26)
          width: chipText.implicitWidth + Style.space(20)
          radius: height / 2
          color: chosen ? card.accent
            : Qt.rgba(card.ink.r, card.ink.g, card.ink.b, chipTap.pressed ? 0.20 : chipHover.hovered ? 0.14 : 0.07)
          scale: chipTap.pressed ? 0.95 : 1
          Behavior on color { ColorAnimation { duration: Style.duration(140) } }
          Behavior on scale { NumberAnimation { duration: Style.duration(140); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }
          Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.modelData.name
            color: chip.chosen ? card.onAccent : card.ink
            font.family: card.fontName
            font.pixelSize: Style.font.bodySmall
            font.weight: chip.chosen ? Font.DemiBold : Font.Normal
          }
          HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
          TapHandler {
            id: chipTap
            onTapped: { card.pickProvider(chip.modelData.id); card.focusField() }
          }
        }
      }
    }

    // ── the question ─────────────────────────────────────────────────
    Rectangle {
      id: box
      width: parent.width
      // Room for the thumbnails; it opens smoothly when the first one lands.
      property real stripHeight: card.hasPictures ? Style.space(52) + Style.space(10) : 0
      Behavior on stripHeight { NumberAnimation { duration: Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }
      height: stripHeight + Math.min(Math.max(field.implicitHeight, Style.space(44)), Style.space(150))
      radius: Style.cornerRadius
      color: Qt.rgba(card.ink.r, card.ink.g, card.ink.b, field.activeFocus ? 0.10 : 0.06)
      border.width: Math.max(1, Style.space(1))
      border.color: field.activeFocus ? Qt.rgba(card.accent.r, card.accent.g, card.accent.b, 0.75)
        : Qt.rgba(card.ink.r, card.ink.g, card.ink.b, 0.12)
      Behavior on color { ColorAnimation { duration: Style.duration(140) } }
      Behavior on border.color { ColorAnimation { duration: Style.duration(140) } }

      // The pasted pictures, as small rounded thumbnails.
      Row {
        id: strip
        x: Style.space(10)
        y: Style.space(10)
        spacing: Style.space(6)
        visible: card.hasPictures
        Repeater {
          model: card.pictures
          delegate: Thumb {}
        }
      }

      Flickable {
        id: scroller
        anchors.fill: parent
        anchors.topMargin: box.stripHeight
        contentWidth: width
        contentHeight: field.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        onContentHeightChanged: if (contentHeight > height) contentY = contentHeight - height

        TextArea.flickable: TextArea {
          id: field
          focus: true
          wrapMode: TextEdit.Wrap
          color: card.ink
          selectionColor: Qt.rgba(card.accent.r, card.accent.g, card.accent.b, 0.35)
          selectedTextColor: card.ink
          placeholderText: card.listening ? "Listening… speak your question"
            : card.hasPictures ? "Ask " + card.current.full + " about " + (card.pictures.length > 1 ? "these" : "this")
            : "Ask " + card.current.full + " anything"
          placeholderTextColor: Qt.rgba(card.ink.r, card.ink.g, card.ink.b, 0.45)
          font.family: card.fontName
          font.pixelSize: Style.font.body
          leftPadding: Style.space(12)
          rightPadding: Style.space(12)
          topPadding: Style.space(12)
          bottomPadding: Style.space(12)
          background: null

          Keys.onPressed: function(event) {
            if (event.matches(StandardKey.Paste)) {
              card.pasteRequested()
              event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
              card.closeRequested()
              event.accepted = true
            } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
              card.submit()
              event.accepted = true
            } else if (event.key === Qt.Key_Up && (field.text === "" || card.recall >= 0) && card.history.length > 0) {
              card.recall = Math.min(card.recall + 1, card.history.length - 1)
              field.text = card.history[card.recall]
              field.cursorPosition = field.length
              event.accepted = true
            } else if (event.key === Qt.Key_Down && card.recall >= 0) {
              card.recall -= 1
              field.text = card.recall >= 0 ? card.history[card.recall] : ""
              field.cursorPosition = field.length
              event.accepted = true
            }
          }
        }
      }
    }

    // ── mic, hint, send ──────────────────────────────────────────────
    Item {
      width: parent.width
      height: Style.space(32)

      RoundButton {
        id: mic
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        glyph: card.listening ? "\u{F04DB}" : "\u{F036C}"
        lit: card.listening
        onPicked: { card.toggleDictation(); card.focusField() }
      }

      Text {
        anchors.left: mic.right
        anchors.leftMargin: Style.space(10)
        anchors.right: send.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        color: Qt.rgba(card.ink.r, card.ink.g, card.ink.b, 0.5)
        font.family: card.fontName
        font.pixelSize: Style.font.bodySmall
        text: card.note !== "" ? card.note
          : card.listening ? "Listening · click the mic or press Alt+Space to stop"
          : !card.dictationReady ? "Click the mic to set up dictation"
          : card.hasPictures ? "Enter to ask · Ctrl+V adds another picture"
          : "Enter to ask · Ctrl+V pastes a screenshot"
      }

      RoundButton {
        id: send
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        glyph: "\u{F048A}"
        lit: card.canAsk
        enabled: card.canAsk
        opacity: card.canAsk ? 1 : 0.45
        onPicked: card.submit()
      }
    }
  }

  // One pasted picture: a rounded thumbnail that eases in, with a × to take
  // it out on hover.
  component Thumb: Item {
    id: thumb
    required property var modelData
    readonly property int size: Style.space(52)
    width: size
    height: size
    opacity: 0
    scale: 0.85
    Component.onCompleted: { opacity = 1; scale = 1 }
    Behavior on opacity { NumberAnimation { duration: Style.duration(160) } }
    Behavior on scale { NumberAnimation { duration: Style.duration(200); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }

    Image {
      id: pic
      anchors.fill: parent
      source: "file://" + thumb.modelData
      // Fixed, so the picture is read once at thumbnail size.
      sourceSize: Qt.size(thumb.size * 2, thumb.size * 2)
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      smooth: true
      mipmap: true
      visible: false
      layer.enabled: true; layer.smooth: true
    }
    Rectangle {
      id: picMask
      anchors.fill: parent
      radius: Math.max(Style.space(8), Style.cornerRadius * 0.75)
      visible: false
      layer.enabled: true; layer.smooth: true
    }
    MultiEffect {
      anchors.fill: parent
      source: pic
      maskEnabled: true
      maskSource: picMask
      maskThresholdMin: 0.5
      maskSpreadAtMin: 1.0
      visible: pic.status === Image.Ready
    }
    // While it loads (or if it can't be read): a soft tile with a picture glyph.
    Rectangle {
      anchors.fill: parent
      radius: picMask.radius
      visible: pic.status !== Image.Ready
      color: Qt.rgba(card.ink.r, card.ink.g, card.ink.b, 0.08)
      Text {
        anchors.centerIn: parent
        text: "\u{F02E9}"
        color: Qt.rgba(card.ink.r, card.ink.g, card.ink.b, 0.5)
        font.family: card.fontName
        font.pixelSize: Style.font.body
      }
    }
    // A hairline edge so a light screenshot doesn't melt into the glass.
    Rectangle {
      anchors.fill: parent
      radius: picMask.radius
      color: "transparent"
      border.width: Math.max(1, Style.space(1))
      border.color: Qt.rgba(card.ink.r, card.ink.g, card.ink.b, 0.14)
    }

    HoverHandler { id: thumbHover }

    Rectangle {
      id: remove
      width: Style.space(20)
      height: width
      radius: width / 2
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: Style.space(3)
      color: Qt.rgba(0.06, 0.06, 0.08, removeTap.pressed ? 0.92 : 0.72)
      opacity: thumbHover.hovered ? 1 : 0
      visible: opacity > 0
      Behavior on opacity { NumberAnimation { duration: Style.duration(120) } }
      Text {
        anchors.centerIn: parent
        text: "\u{F0156}"
        color: Qt.rgba(1, 1, 1, 0.95)
        font.family: card.fontName
        font.pixelSize: Style.font.bodySmall
      }
      HoverHandler { cursorShape: Qt.PointingHandCursor }
      TapHandler {
        id: removeTap
        onTapped: { card.removePicture(thumb.modelData); card.focusField() }
      }
    }
  }

  component RoundButton: Rectangle {
    id: button
    property string glyph: ""
    property bool lit: false
    signal picked()
    width: Style.space(32)
    height: width
    radius: width / 2
    color: lit ? card.accent
      : Qt.rgba(card.ink.r, card.ink.g, card.ink.b, tap.pressed ? 0.20 : hover.hovered ? 0.14 : 0.07)
    scale: tap.pressed ? 0.92 : 1
    Behavior on color { ColorAnimation { duration: Style.duration(140) } }
    Behavior on scale { NumberAnimation { duration: Style.duration(140); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }
    Behavior on opacity { NumberAnimation { duration: Style.duration(140) } }
    Text {
      anchors.centerIn: parent
      text: button.glyph
      color: button.lit ? card.onAccent : card.ink
      font.family: card.fontName
      font.pixelSize: Style.font.body
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: tap; onTapped: button.picked() }
  }
}
