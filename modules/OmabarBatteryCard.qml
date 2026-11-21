// The battery drop-down card: the combined total up top, then one row for
// each battery (the one in use in the accent color), then the power profile.
import QtQuick
import qs.Commons
import qs.Commons as Commons
import "OmabarBatteryModel.js" as Model

Item {
  id: card

  property color ink: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontName: "monospace"

  property var external: null
  property var internal: null
  property string focusKey: ""
  property int totalPercent: -1
  property string statusText: ""
  property bool onBattery: true
  property var profiles: []
  property string activeProfile: ""

  signal profilePicked(string name)

  readonly property bool twoPacks: !!(external && internal)

  function profileIcon(name) {
    if (name === "power-saver") return "\u{F032A}"
    if (name === "balanced") return "\u{F029A}"
    if (name === "performance") return "\u{F04C5}"
    return "\u{F0085}"
  }

  function profileLabel(name) {
    if (name === "power-saver") return "Saver"
    if (name === "balanced") return "Balanced"
    if (name === "performance") return "Performance"
    var v = String(name || "")
    return v.charAt(0).toUpperCase() + v.slice(1)
  }

  implicitWidth: Style.space(330)
  implicitHeight: body.implicitHeight

  Column {
    id: body
    width: card.width
    spacing: Style.space(12)

    // ── header: total ────────────────────────────────────────────────────
    Item {
      width: parent.width
      height: Math.max(headerLabels.implicitHeight, totalText.implicitHeight)

      Column {
        id: headerLabels
        anchors.left: parent.left
        anchors.right: totalText.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          text: "Battery"
          textFormat: Text.PlainText
          color: card.ink
          font.family: card.fontName
          font.pixelSize: Style.font.title
          font.weight: Font.DemiBold
        }

        Text {
          width: parent.width
          text: card.statusText + (card.twoPacks ? "  ·  both batteries" : "")
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: card.ink
          opacity: 0.55
          font.family: card.fontName
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        id: totalText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: card.totalPercent >= 0 ? card.totalPercent + "%" : "—"
        textFormat: Text.PlainText
        color: card.ink
        font.family: card.fontName
        font.pixelSize: Math.round(Style.font.title * 1.75)
        font.weight: Font.DemiBold
      }
    }

    // ── one row per battery ──────────────────────────────────────────────
    BatteryRow {
      label: "External"
      hint: "removable"
      battery: card.external
      inUse: card.focusKey === "external"
    }

    BatteryRow {
      visible: card.internal !== null
      label: card.external ? "Internal" : "Battery"
      hint: card.external ? "built-in" : ""
      battery: card.internal
      inUse: card.focusKey === "internal"
    }

    // ── power profile ────────────────────────────────────────────────────
    Rectangle {
      visible: card.profiles.length > 0
      width: parent.width
      height: 1
      color: Qt.rgba(card.ink.r, card.ink.g, card.ink.b, 0.10)
    }

    Row {
      id: profileRow
      visible: card.profiles.length > 0
      width: parent.width
      spacing: Style.space(6)
      readonly property real cellWidth: card.profiles.length > 0
        ? (width - spacing * (card.profiles.length - 1)) / card.profiles.length : 0

      Repeater {
        model: card.profiles
        Rectangle {
          id: chip
          required property var modelData
          readonly property bool active: card.activeProfile === String(modelData)
          width: profileRow.cellWidth
          height: Style.space(30)
          radius: height / 2
          color: active ? Qt.rgba(card.accent.r, card.accent.g, card.accent.b, 0.22)
            : Qt.rgba(card.ink.r, card.ink.g, card.ink.b, chipTap.pressed ? 0.20 : chipHover.hovered ? 0.14 : 0.07)
          border.width: active ? 1 : 0
          border.color: card.accent
          scale: chipTap.pressed ? 0.96 : 1
          Behavior on color { ColorAnimation { duration: Style.duration(120) } }
          Behavior on scale { NumberAnimation { duration: Style.duration(140); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }

          Row {
            anchors.centerIn: parent
            spacing: Style.space(5)
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: card.profileIcon(String(chip.modelData))
              color: chip.active ? card.accent : card.ink
              font.family: card.fontName
              font.pixelSize: Style.font.body
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: card.profileLabel(String(chip.modelData))
              textFormat: Text.PlainText
              color: card.ink
              font.family: card.fontName
              font.pixelSize: Style.font.caption
            }
          }

          HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
          TapHandler { id: chipTap; onTapped: card.profilePicked(String(chip.modelData)) }
        }
      }
    }
  }

  component BatteryRow: Rectangle {
    id: row
    property string label: ""
    property string hint: ""
    property var battery: null
    property bool inUse: false
    readonly property int percent: Model.percentOf(battery)
    readonly property color tone: inUse ? card.accent : card.ink

    width: parent.width
    height: rowBody.implicitHeight + Style.space(20)
    radius: Style.space(12)
    color: inUse ? Qt.rgba(card.accent.r, card.accent.g, card.accent.b, 0.10)
      : Qt.rgba(card.ink.r, card.ink.g, card.ink.b, 0.06)
    Behavior on color { ColorAnimation { duration: Style.duration(200) } }

    Column {
      id: rowBody
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(14)
      anchors.rightMargin: Style.space(14)
      spacing: Style.space(8)

      Item {
        width: parent.width
        height: Math.max(rowIcon.implicitHeight, rowLabels.implicitHeight, rowPercent.implicitHeight)

        Text {
          id: rowIcon
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: Model.icon(row.percent, row.battery ? row.battery.state === "charging" : false)
          color: row.tone
          opacity: row.battery ? 1 : 0.4
          font.family: card.fontName
          font.pixelSize: Style.font.iconLarge
        }

        Column {
          id: rowLabels
          anchors.left: rowIcon.right
          anchors.leftMargin: Style.space(10)
          anchors.right: rowPercent.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(1)

          Text {
            text: row.label + (row.hint ? "  " : "")
            textFormat: Text.PlainText
            color: card.ink
            font.family: card.fontName
            font.pixelSize: Style.font.bodySmall
            font.weight: Font.DemiBold

            Text {
              anchors.left: parent.right
              anchors.baseline: parent.baseline
              text: row.hint
              textFormat: Text.PlainText
              color: card.ink
              opacity: 0.45
              font.family: card.fontName
              font.pixelSize: Style.font.caption
            }
          }

          Text {
            text: Model.stateLabel(row.battery, row.inUse).toUpperCase()
            textFormat: Text.PlainText
            color: row.inUse ? card.accent : card.ink
            opacity: row.inUse ? 1 : 0.5
            font.family: card.fontName
            font.pixelSize: Style.font.caption
            font.weight: Font.DemiBold
            font.letterSpacing: 1.1
          }
        }

        Text {
          id: rowPercent
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: row.percent >= 0 ? row.percent + "%" : "—"
          textFormat: Text.PlainText
          color: row.battery ? card.ink : Qt.rgba(card.ink.r, card.ink.g, card.ink.b, 0.4)
          font.family: card.fontName
          font.pixelSize: Style.font.title
          font.weight: Font.DemiBold
        }
      }

      Rectangle {
        id: track
        width: parent.width
        height: Style.space(6)
        radius: height / 2
        color: Qt.rgba(card.ink.r, card.ink.g, card.ink.b, 0.12)

        Rectangle {
          visible: row.percent > 0
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          height: parent.height
          radius: parent.radius
          width: Math.max(parent.height, parent.width * Math.max(0, row.percent) / 100)
          color: row.tone
          Behavior on width { NumberAnimation { duration: Style.duration(320); easing.type: Easing.OutCubic } }
        }
      }
    }
  }
}
