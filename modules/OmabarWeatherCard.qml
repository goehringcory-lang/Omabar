// The weather drop-down card: current conditions, active NWS alerts if any,
// and a 5-day forecast from weather.gov. Click any day to read its full day
// and night NWS forecast right inside the drop-down.
import QtQuick
import qs.Commons
import qs.Commons as Commons

Item {
  id: card

  property color ink: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontName: "monospace"

  property bool loading: false
  property bool stale: false
  property string error: ""
  property string location: ""
  property string unit: "F"
  property string updatedText: ""
  property var current: null
  property var days: []
  property var alerts: []

  property int expandedIndex: -1

  signal refreshRequested()

  function reset() {
    card.expandedIndex = -1
  }

  function iconFor(condition) {
    switch (String(condition || "")) {
      case "sunny": return "\u{F0599}"
      case "clear-night": return "\u{F0594}"
      case "partly-cloudy": return "\u{F0595}"
      case "partly-cloudy-night": return "\u{F0F31}"
      case "cloudy": return "\u{F0590}"
      case "fog": return "\u{F0591}"
      case "rain": return "\u{F0597}"
      case "heavy-rain": return "\u{F0596}"
      case "thunderstorm": return "\u{F067E}"
      case "snow": return "\u{F0598}"
      case "heavy-snow": return "\u{F0F36}"
      case "sleet": return "\u{F067F}"
      case "hail": return "\u{F0592}"
      case "windy": return "\u{F059D}"
      default: return "\u{F0590}"
    }
  }

  function tempText(value) {
    return value === null || value === undefined ? "—" : String(value) + "°"
  }

  function hasTemp(value) {
    return value !== null && value !== undefined && !isNaN(Number(value))
  }

  readonly property var tempBounds: {
    var lo = 999, hi = -999
    var list = card.days || []
    for (var i = 0; i < list.length; i++) {
      var d = list[i]
      if (!d) continue
      if (card.hasTemp(d.low)) {
        if (d.low < lo) lo = d.low
        if (d.low > hi) hi = d.low
      }
      if (card.hasTemp(d.high)) {
        if (d.high < lo) lo = d.high
        if (d.high > hi) hi = d.high
      }
    }
    if (lo > hi) return { min: 0, max: 1 }
    return { min: lo, max: Math.max(lo + 1, hi) }
  }

  readonly property string currentMeta: {
    if (!card.current) return ""
    var parts = []
    if (card.current.wind) parts.push(String(card.current.wind))
    if (card.current.precip !== null && card.current.precip !== undefined && Number(card.current.precip) > 0)
      parts.push("\u{F058C} " + card.current.precip + "%")
    else if (card.current.humidity !== null && card.current.humidity !== undefined)
      parts.push(card.current.humidity + "% RH")
    return parts.join("  ·  ")
  }

  readonly property string hiLoText: {
    if (!card.current) return ""
    var parts = []
    if (card.hasTemp(card.current.high)) parts.push("H " + card.current.high + "°")
    if (card.hasTemp(card.current.low)) parts.push("L " + card.current.low + "°")
    return parts.join("   ")
  }

  implicitWidth: Style.space(350)
  implicitHeight: body.implicitHeight

  Column {
    id: body
    width: card.width
    spacing: Style.space(10)

    // ── header ───────────────────────────────────────────────────────────
    Item {
      width: parent.width
      height: Style.space(26)

      Text {
        anchors.left: parent.left
        anchors.right: headerRight.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: card.location || "Weather"
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: card.ink
        font.family: card.fontName
        font.pixelSize: Style.font.title
        font.weight: Font.DemiBold
      }

      Row {
        id: headerRight
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

        Text {
          visible: card.loading || card.updatedText !== ""
          anchors.verticalCenter: parent.verticalCenter
          text: card.loading ? "Updating…" : card.updatedText
          textFormat: Text.PlainText
          color: card.ink
          opacity: 0.45
          font.family: card.fontName
          font.pixelSize: Style.font.caption
        }

        Chip {
          label: "\u{F0450}"
          square: true
          onPicked: card.refreshRequested()
        }
      }
    }

    // ── current conditions ───────────────────────────────────────────────
    Rectangle {
      visible: card.current !== null
      width: parent.width
      height: currentRow.implicitHeight + Style.space(20)
      radius: Style.space(12)
      color: Qt.rgba(card.ink.r, card.ink.g, card.ink.b, 0.06)

      Row {
        id: currentRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(14)
        anchors.rightMargin: Style.space(14)
        spacing: Style.space(12)

        Text {
          id: heroIcon
          anchors.verticalCenter: parent.verticalCenter
          text: card.current ? card.iconFor(card.current.condition) : ""
          color: card.accent
          font.family: card.fontName
          font.pixelSize: Math.round(Style.font.iconLarge * 1.55)
        }

        Item {
          id: heroTemp
          anchors.verticalCenter: parent.verticalCenter
          implicitWidth: heroTempValue.implicitWidth + Style.space(2) + heroUnit.implicitWidth
          implicitHeight: heroTempValue.implicitHeight
          width: implicitWidth
          height: implicitHeight
          Text {
            id: heroTempValue
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: card.current ? card.tempText(card.current.temp) : ""
            textFormat: Text.PlainText
            color: card.ink
            font.family: card.fontName
            font.pixelSize: Math.round(Style.font.title * 1.75)
            font.weight: Font.DemiBold
          }
          Text {
            id: heroUnit
            anchors.left: heroTempValue.right
            anchors.leftMargin: Style.space(2)
            anchors.baseline: heroTempValue.baseline
            text: card.unit
            textFormat: Text.PlainText
            color: card.ink
            opacity: 0.45
            font.family: card.fontName
            font.pixelSize: Style.font.caption
          }
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(0, currentRow.width - heroIcon.implicitWidth - heroTemp.implicitWidth - currentRow.spacing * 2)
          spacing: Style.space(2)

          Text {
            width: parent.width
            text: card.current ? String(card.current.short || "") : ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: card.ink
            font.family: card.fontName
            font.pixelSize: Style.font.bodySmall
            font.weight: Font.DemiBold
          }

          Text {
            visible: card.hiLoText !== ""
            width: parent.width
            text: card.hiLoText
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: card.ink
            opacity: 0.65
            font.family: card.fontName
            font.pixelSize: Style.font.caption
          }

          Text {
            visible: card.currentMeta !== ""
            width: parent.width
            text: card.currentMeta
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: card.ink
            opacity: 0.5
            font.family: card.fontName
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    // ── active NWS alerts ────────────────────────────────────────────────
    Column {
      visible: card.alerts && card.alerts.length > 0
      width: parent.width
      spacing: Style.space(4)

      Repeater {
        model: card.alerts || []
        Rectangle {
          required property var modelData
          width: parent.width
          height: alertCol.implicitHeight + Style.space(12)
          radius: Style.space(10)
          color: Qt.rgba(card.accent.r, card.accent.g, card.accent.b, 0.14)

          Rectangle {
            x: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: parent.height - Style.space(12)
            radius: 2
            color: card.accent
          }

          Column {
            id: alertCol
            x: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Style.space(24)
            spacing: 1
            Text {
              width: parent.width
              text: String(modelData.event || "")
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: card.ink
              font.family: card.fontName
              font.pixelSize: Style.font.bodySmall
              font.weight: Font.DemiBold
            }
            Text {
              visible: Boolean(modelData.headline)
              width: parent.width
              text: String(modelData.headline || "")
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              maximumLineCount: 2
              elide: Text.ElideRight
              color: card.ink
              opacity: 0.7
              font.family: card.fontName
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }

    // ── 5-day forecast ───────────────────────────────────────────────────
    Column {
      visible: card.days && card.days.length > 0
      width: parent.width
      spacing: Style.space(4)

      Item {
        width: parent.width
        height: Style.space(16)

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: card.days.length + "-Day Forecast"
          color: card.ink
          opacity: 0.5
          font.family: card.fontName
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1.2
          font.capitalization: Font.AllUppercase
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: "Click a day for details"
          color: card.ink
          opacity: 0.35
          font.family: card.fontName
          font.pixelSize: Style.font.caption
        }
      }

      Repeater {
        model: card.days || []

        Column {
          id: dayGroup
          required property var modelData
          required property int index
          readonly property bool expanded: card.expandedIndex === index

          width: parent.width
          spacing: Style.space(4)

          Rectangle {
            id: dayRow
            width: parent.width
            height: Style.space(38)
            radius: Style.space(10)
            color: Qt.rgba(card.ink.r, card.ink.g, card.ink.b,
              rowTap.pressed ? 0.16 : dayGroup.expanded ? 0.10 : rowHover.hovered ? 0.08 : 0.0)
            Behavior on color { ColorAnimation { duration: Style.duration(100) } }

            // Day name
            Text {
              id: dayLabel
              x: Style.space(8)
              width: Style.space(56)
              anchors.verticalCenter: parent.verticalCenter
              text: String(dayGroup.modelData.label || "")
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: card.ink
              font.family: card.fontName
              font.pixelSize: Style.font.bodySmall
              font.weight: dayGroup.index === 0 || dayGroup.expanded ? Font.DemiBold : Font.Normal
            }

            // Weather icon
            Text {
              id: dayIcon
              anchors.left: dayLabel.right
              anchors.leftMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(22)
              horizontalAlignment: Text.AlignHCenter
              text: card.iconFor(dayGroup.modelData.condition)
              color: dayGroup.index === 0 || dayGroup.expanded ? card.accent : card.ink
              font.family: card.fontName
              font.pixelSize: Style.font.icon
            }

            // Short condition + optional precip chance
            Column {
              anchors.left: dayIcon.right
              anchors.leftMargin: Style.space(8)
              anchors.right: tempCluster.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: 1

              Text {
                width: parent.width
                text: String(dayGroup.modelData.short || "")
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: card.ink
                opacity: 0.78
                font.family: card.fontName
                font.pixelSize: Style.font.caption
              }

              Text {
                visible: dayGroup.modelData.precip !== null && dayGroup.modelData.precip !== undefined && Number(dayGroup.modelData.precip) >= 15
                width: parent.width
                text: "\u{F058C} " + dayGroup.modelData.precip + "%"
                textFormat: Text.PlainText
                color: card.accent
                opacity: 0.9
                font.family: card.fontName
                font.pixelSize: Style.font.caption
              }
            }

            // Low · range bar · High
            Row {
              id: tempCluster
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Text {
                width: Style.space(28)
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: card.tempText(dayGroup.modelData.low)
                textFormat: Text.PlainText
                color: card.ink
                opacity: 0.55
                font.family: card.fontName
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                id: rangeTrack
                width: Style.space(42)
                height: 4
                radius: 2
                anchors.verticalCenter: parent.verticalCenter
                color: Qt.rgba(card.ink.r, card.ink.g, card.ink.b, 0.12)

                readonly property bool hasLow: card.hasTemp(dayGroup.modelData.low)
                readonly property bool hasHigh: card.hasTemp(dayGroup.modelData.high)
                readonly property real span: Math.max(1, card.tempBounds.max - card.tempBounds.min)
                readonly property real loFrac: hasLow ? Math.max(0, Math.min(1, (dayGroup.modelData.low - card.tempBounds.min) / span)) : 0
                readonly property real hiFrac: hasHigh ? Math.max(0, Math.min(1, (dayGroup.modelData.high - card.tempBounds.min) / span)) : loFrac

                Rectangle {
                  visible: rangeTrack.hasLow || rangeTrack.hasHigh
                  height: parent.height
                  radius: parent.radius
                  color: card.accent
                  opacity: dayGroup.index === 0 || dayGroup.expanded ? 1.0 : 0.78
                  readonly property real startX: (rangeTrack.hasLow ? rangeTrack.loFrac : rangeTrack.hiFrac) * rangeTrack.width
                  readonly property real endX: (rangeTrack.hasHigh ? rangeTrack.hiFrac : rangeTrack.loFrac) * rangeTrack.width
                  width: Math.max(Style.space(5), endX - startX)
                  x: Math.max(0, Math.min(rangeTrack.width - width, startX))
                }
              }

              Text {
                width: Style.space(28)
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: card.tempText(dayGroup.modelData.high)
                textFormat: Text.PlainText
                color: card.ink
                font.family: card.fontName
                font.pixelSize: Style.font.bodySmall
                font.weight: Font.DemiBold
              }
            }

            HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
              id: rowTap
              onTapped: card.expandedIndex = dayGroup.expanded ? -1 : dayGroup.index
            }
          }

          // Expanded day / night NWS narrative
          Rectangle {
            visible: dayGroup.expanded
            width: parent.width
            height: detailCol.implicitHeight + Style.space(16)
            radius: Style.space(10)
            color: Qt.rgba(card.ink.r, card.ink.g, card.ink.b, 0.05)

            Column {
              id: detailCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              spacing: Style.space(8)

              PeriodDetail {
                visible: Boolean(dayGroup.modelData.day)
                width: parent.width
                period: dayGroup.modelData.day
              }

              Rectangle {
                visible: Boolean(dayGroup.modelData.day) && Boolean(dayGroup.modelData.night)
                width: parent.width
                height: 1
                color: Qt.rgba(card.ink.r, card.ink.g, card.ink.b, 0.10)
              }

              PeriodDetail {
                visible: Boolean(dayGroup.modelData.night)
                width: parent.width
                period: dayGroup.modelData.night
              }
            }
          }
        }
      }
    }

    // ── loading / error states ───────────────────────────────────────────
    Text {
      visible: card.loading && (!card.days || card.days.length === 0)
      width: parent.width
      text: "Loading forecast…"
      color: card.ink
      opacity: 0.5
      font.family: card.fontName
      font.pixelSize: Style.font.bodySmall
      topPadding: Style.space(4)
      bottomPadding: Style.space(4)
    }

    Column {
      visible: !card.loading && card.error !== "" && (!card.days || card.days.length === 0)
      width: parent.width
      spacing: Style.space(8)

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: card.error
        color: card.ink
        opacity: 0.65
        font.family: card.fontName
        font.pixelSize: Style.font.bodySmall
      }

      Chip {
        label: "\u{F0450}  Retry"
        onPicked: card.refreshRequested()
      }
    }

    Text {
      visible: !card.loading && card.error !== "" && card.days && card.days.length > 0
      width: parent.width
      wrapMode: Text.WordWrap
      maximumLineCount: 3
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: card.error
      color: card.ink
      opacity: 0.5
      font.family: card.fontName
      font.pixelSize: Style.font.caption
    }
  }

  component PeriodDetail: Column {
    id: detail
    property var period: null
    spacing: Style.space(3)

    readonly property string meta: {
      if (!period) return ""
      var parts = []
      if (card.hasTemp(period.temp)) parts.push(period.temp + "°" + card.unit)
      if (period.wind) parts.push(String(period.wind))
      if (period.precip !== null && period.precip !== undefined && Number(period.precip) > 0)
        parts.push("\u{F058C} " + period.precip + "%")
      return parts.join("  ·  ")
    }

    Item {
      width: parent.width
      height: periodName.implicitHeight

      Text {
        id: periodName
        anchors.left: parent.left
        anchors.right: periodMeta.left
        anchors.rightMargin: Style.space(8)
        elide: Text.ElideRight
        text: detail.period ? card.iconFor(detail.period.condition) + "  " + String(detail.period.name || "") : ""
        textFormat: Text.PlainText
        color: card.ink
        font.family: card.fontName
        font.pixelSize: Style.font.caption
        font.weight: Font.DemiBold
      }

      Text {
        id: periodMeta
        anchors.right: parent.right
        anchors.verticalCenter: periodName.verticalCenter
        text: detail.meta
        textFormat: Text.PlainText
        color: card.ink
        opacity: 0.55
        font.family: card.fontName
        font.pixelSize: Style.font.caption
      }
    }

    Text {
      visible: Boolean(detail.period && detail.period.detail)
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: detail.period ? String(detail.period.detail || "") : ""
      color: card.ink
      opacity: 0.78
      font.family: card.fontName
      font.pixelSize: Style.font.caption
      lineHeight: 1.3
    }
  }

  component Chip: Rectangle {
    id: chip
    property string label: ""
    property bool square: false
    signal picked()
    height: Style.space(26)
    width: square ? height : chipText.implicitWidth + Style.space(20)
    radius: height / 2
    color: Qt.rgba(card.ink.r, card.ink.g, card.ink.b, chipTap.pressed ? 0.20 : chipHover.hovered ? 0.14 : 0.07)
    scale: chipTap.pressed ? 0.95 : 1
    Behavior on color { ColorAnimation { duration: Style.duration(120) } }
    Behavior on scale { NumberAnimation { duration: Style.duration(140); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }
    Text {
      id: chipText
      anchors.centerIn: parent
      text: chip.label
      color: card.ink
      font.family: card.fontName
      font.pixelSize: Style.font.bodySmall
    }
    HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: chipTap; onTapped: chip.picked() }
  }
}
