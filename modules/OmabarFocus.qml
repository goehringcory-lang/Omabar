// Omabar Focus timer: what is left of the round, beside the clock, shown only
// while Focus mode runs (it takes no room otherwise). Start Focus mode from
// the Focus tile in the drawer, or bin/omabar-focus.
//
// Click: the Focus card (time left, pause, skip, end). Middle-click: end
// Focus mode. When a round or break begins it reads "Break · 5 min" for a few
// seconds, so the change is seen even with the sound off.
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "OmabarFocusModel.js" as Model

Item {
  id: root

  property var bar
  property string moduleName
  property var settings: ({})

  readonly property var focusMode: bar && bar.omabarFocus ? bar.omabarFocus : null
  readonly property var info: focusMode ? focusMode.info : null
  readonly property bool active: !!info && info.active
  readonly property bool paused: active && info.paused
  readonly property bool onBreak: active && info.phase === "break"
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : 34
  readonly property color ink: bar ? bar.barForeground : Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property string fontName: bar && bar.fontFamily ? bar.fontFamily : "monospace"

  // "18m": whole minutes, rounded up, so it never reads 0m with time left.
  readonly property string shortLeft: {
    if (!active) return ""
    var s = Math.max(0, Math.ceil(info.remainingMs / 1000))
    return s < 60 ? s + "s" : Math.ceil(s / 60) + "m"
  }
  readonly property string label: focusMode && focusMode.cue ? focusMode.cue : shortLeft

  property bool cardOpen: false
  function close() { cardOpen = false }
  onActiveChanged: if (!active) cardOpen = false
  onCardOpenChanged: {
    if (focusMode) focusMode.watchers = Math.max(0, focusMode.watchers + (cardOpen ? 1 : -1))
    syncTooltip()
  }
  Component.onDestruction: if (cardOpen && focusMode) focusMode.watchers = Math.max(0, focusMode.watchers - 1)

  readonly property string tooltipText: active
    ? Model.summary(info) + "\nClick for focus controls · Middle-click to end"
    : ""
  function syncTooltip() {
    if (!bar || typeof bar.showTooltip !== "function") return
    if (hover.hovered && !cardOpen && tooltipText !== "") bar.showTooltip(root, tooltipText)
    else bar.hideTooltip(root)
  }
  onTooltipTextChanged: if (hover.hovered) syncTooltip()

  visible: active
  implicitWidth: !active ? 0 : vertical ? barSize : pill.implicitWidth + Style.space(2)
  implicitHeight: !active ? 0 : vertical ? pill.implicitHeight + Style.space(4) : barSize

  Rectangle {
    id: pill
    anchors.centerIn: parent
    implicitWidth: root.vertical ? root.barSize - Style.space(4) : row.implicitWidth + Style.space(12)
    implicitHeight: root.vertical ? row.implicitHeight + Style.space(8) : Math.round(root.barSize * 0.72)
    width: implicitWidth
    height: implicitHeight
    radius: root.vertical ? Style.space(8) : height / 2
    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b,
      clickTarget.held ? 0.18 : root.cardOpen ? 0.14 : hover.hovered ? 0.09 : 0.0)
    Behavior on color { ColorAnimation { duration: Style.duration(120) } }

    Row {
      id: row
      anchors.centerIn: parent
      spacing: Style.space(4)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.paused
        text: "\u{F03E4}"
        color: root.ink
        opacity: 0.6
        font.family: root.fontName
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        textFormat: Text.PlainText
        // Quiet: a number to glance at, not something calling for attention.
        // The phase-change cue is in the accent color while it shows.
        color: root.focusMode && root.focusMode.cue ? root.accent : root.ink
        opacity: root.focusMode && root.focusMode.cue ? 1 : (root.paused ? 0.45 : 0.62)
        font.family: root.fontName
        font.pixelSize: Style.font.bodySmall
        font.features: { "tnum": 1 }
      }
    }
  }

  PopupCard {
    id: popup
    anchorItem: pill
    bar: root.bar
    owner: root
    open: root.cardOpen && root.active
    contentWidth: popup.fittedContentWidth(Style.space(260))
    contentHeight: popup.fittedContentHeight(card.implicitHeight)

    Column {
      id: card
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.space(12)

      readonly property color text: Commons.Color.popups.text

      // Phase, then the time left, large.
      Column {
        width: parent.width
        spacing: Style.space(2)
        Text {
          text: root.active ? (root.paused ? "Paused · " : "") + (root.onBreak ? Model.phaseName(root.info) : "Focus " + root.info.round + " of " + root.info.rounds) : ""
          color: card.text
          opacity: 0.6
          font.family: root.fontName
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1.2
          font.capitalization: Font.AllUppercase
        }
        Text {
          text: root.active ? Model.clock(root.info.remainingMs) : ""
          color: root.onBreak ? card.text : root.accent
          opacity: root.paused ? 0.55 : 1
          font.family: root.fontName
          font.pixelSize: Math.round(Style.font.bodySmall * 2.6)
          font.weight: Font.DemiBold
          font.features: { "tnum": 1 }
        }
      }

      // One dot for each round: done, under way, to come.
      Row {
        spacing: Style.space(6)
        Repeater {
          model: root.active ? root.info.rounds : 0
          Rectangle {
            required property int index
            readonly property int round: index + 1
            readonly property bool done: root.active && (round < root.info.round || (round === root.info.round && root.onBreak))
            readonly property bool current: root.active && round === root.info.round && !root.onBreak
            width: current ? Style.space(18) : Style.space(7)
            height: Style.space(7)
            radius: height / 2
            color: done || current ? root.accent : Qt.rgba(card.text.r, card.text.g, card.text.b, 0.18)
            opacity: current && root.paused ? 0.55 : 1
          }
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(8)
        readonly property real buttonWidth: (width - spacing * 2) / 3

        CardButton {
          width: parent.buttonWidth
          icon: root.paused ? "\u{F040A}" : "\u{F03E4}"
          label: root.paused ? "Resume" : "Pause"
          onPicked: if (root.focusMode) { if (root.paused) root.focusMode.resume(); else root.focusMode.pause() }
        }
        CardButton {
          width: parent.buttonWidth
          icon: "\u{F04AD}"
          label: root.onBreak ? "End break" : "Skip"
          onPicked: if (root.focusMode) root.focusMode.skip()
        }
        CardButton {
          width: parent.buttonWidth
          icon: "\u{F04DB}"
          label: "End focus"
          strong: true
          onPicked: {
            root.cardOpen = false
            if (root.focusMode) root.focusMode.stop()
          }
        }
      }
    }
  }

  component CardButton: Rectangle {
    id: button
    property string icon: ""
    property string label: ""
    property bool strong: false
    signal picked()

    height: Style.space(52)
    radius: Style.space(12)
    readonly property color text: Commons.Color.popups.text
    color: strong && buttonArea.containsMouse
      ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
      : Qt.rgba(text.r, text.g, text.b, buttonArea.containsMouse ? 0.14 : 0.07)
    scale: buttonArea.pressed ? 0.96 : 1
    Behavior on color { ColorAnimation { duration: Style.duration(120) } }
    Behavior on scale { NumberAnimation { duration: Style.duration(140); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }

    Column {
      anchors.centerIn: parent
      spacing: Style.space(3)
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: button.icon
        color: buttonArea.containsMouse || button.strong ? root.accent : button.text
        font.family: root.fontName
        font.pixelSize: Style.font.icon
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: button.label
        color: button.text
        opacity: 0.85
        font.family: root.fontName
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      id: buttonArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: button.picked()
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
    pressable: root.active
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    onPressed: function(button) {
      if (button === Qt.MiddleButton) {
        root.cardOpen = false
        if (root.focusMode) root.focusMode.stop()
      } else {
        root.cardOpen = !root.cardOpen
      }
    }
  }
}
