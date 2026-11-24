// Omabar weather: current condition and temperature from weather.gov (NWS)
// right beside the clock and plugin manager. Click opens a 5-day forecast
// drop-down (staying right in the bar instead of opening a browser);
// right-click refreshes the forecast.
//
// Settings (inline on the shell.json entry):
//   url      - a forecast.weather.gov/MapClick.php?lat=...&lon=... link
//   lat      - latitude when url is not set (default 37.67552934366611)
//   lon      - longitude when url is not set (default -119.78244423866272)
//   days     - number of forecast days to show, 1..7 (default 5)
//   units    - "F" or "C" (default "F")
//   radarUrl - radar link to open (defaults to the location's weather.gov radar)
//   twelveHour - "Updated" time as 9:30 AM (default true) or 09:30 (false)
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: root

  property var bar
  property string moduleName
  property var settings: ({})

  function setting(name, fallback) {
    var v = settings ? settings[name] : undefined
    return v === undefined || v === null ? fallback : v
  }

  readonly property string weatherUrl: String(setting("url", "")).trim()
  readonly property real lat: Number(setting("lat", 37.67552934366611))
  readonly property real lon: Number(setting("lon", -119.78244423866272))
  readonly property int daysCount: Math.max(1, Math.min(7, Number(setting("days", 5)) || 5))
  // "Updated 9:30 AM", or 09:30 with twelveHour set to false.
  readonly property bool twelveHour: setting("twelveHour", true) !== false
  readonly property string units: String(setting("units", "F")).toUpperCase() === "C" ? "C" : "F"
  readonly property string defaultRadarUrl: "https://radar.weather.gov/station/khnx/standard"
  readonly property string configuredRadarUrl: String(setting("radarUrl", "")).trim()

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : 34
  readonly property color ink: bar ? bar.barForeground : Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property string fontName: bar && bar.fontFamily ? bar.fontFamily : "monospace"
  readonly property string helper: String(Qt.resolvedUrl("../bin/omabar-weather")).replace(/^file:\/\//, "")

  property bool forecastOpen: false
  property bool loading: false
  property bool stale: false
  property string error: ""
  property string location: ""
  property string unit: units
  property string updatedText: ""
  property string fetchedRadarUrl: ""
  readonly property string radarUrl: configuredRadarUrl !== "" ? configuredRadarUrl : (fetchedRadarUrl !== "" ? fetchedRadarUrl : defaultRadarUrl)
  property var current: null
  property var daysData: []
  property var alerts: []
  property int askSerial: 0
  property double lastLoadedMs: 0

  // Called by the bar when another popup opens or a click lands outside.
  function close() {
    forecastOpen = false
  }

  function openRadar() {
    if (!root.radarUrl) return
    if (root.bar) root.bar.run("xdg-open " + Util.shellQuote(root.radarUrl))
    root.forecastOpen = false
  }

  function helperArgs(force) {
    var args = []
    if (root.weatherUrl !== "") {
      args.push("--url", root.weatherUrl)
    } else {
      args.push("--lat", String(root.lat), "--lon", String(root.lon))
    }
    args.push("--days", String(root.daysCount), "--units", root.units)
    if (force) args.push("--force")
    return args
  }

  function formatUpdated(iso) {
    if (!iso) return ""
    var d = new Date(iso)
    if (isNaN(d.getTime())) return ""
    return Qt.formatTime(d, root.twelveHour ? "h:mm AP" : "HH:mm")
  }

  function load(force) {
    var ask = ++root.askSerial
    root.loading = true
    var proc = runner.createObject(root, { command: [root.helper].concat(helperArgs(!!force)) })
    var answered = false
    function finish(text) {
      if (answered) return
      answered = true
      proc.destroy()
      if (ask !== root.askSerial) return
      root.loading = false
      var data = null
      try { data = JSON.parse(text) } catch (e) {}
      if (!data) {
        root.error = "Couldn't read weather.gov forecast."
        return
      }
      root.location = String(data.location || root.location || "")
      root.unit = String(data.unit || root.units)
      root.stale = data.stale === true
      root.error = String(data.error || "")
      if (data.ok) {
        root.current = data.current || null
        root.daysData = Array.isArray(data.days) ? data.days : []
        root.alerts = Array.isArray(data.alerts) ? data.alerts : []
        root.updatedText = root.formatUpdated(data.updated)
        root.fetchedRadarUrl = String(data.radarUrl || "").trim()
        root.lastLoadedMs = Date.now()
      }
    }
    proc.finished.connect(finish)
    proc.gaveUp.connect(function() { finish("") })
    proc.running = true
  }

  Component {
    id: runner
    Process {
      id: proc
      signal finished(string text)
      signal gaveUp()
      stdout: StdioCollector { onStreamFinished: proc.finished(text) }
      property Timer watchdog: Timer {
        interval: 30000
        running: true
        onTriggered: { proc.running = false; proc.gaveUp() }
      }
    }
  }

  property bool ready: false
  Component.onCompleted: {
    ready = true
    load(false)
  }

  // Refresh every 15 minutes (matching bin/omabar-weather's cache window).
  Timer {
    interval: 900000
    running: true
    repeat: true
    onTriggered: root.load(false)
  }

  onSettingsChanged: if (ready) {
    fetchedRadarUrl = ""
    load(false)
  }

  onForecastOpenChanged: {
    syncTooltip()
    if (!forecastOpen) return
    card.reset()
    if (!current || stale || error !== "" || (Date.now() - lastLoadedMs) > 300000)
      load(false)
  }

  readonly property string barIcon: current ? card.iconFor(current.condition) : "\u{F0590}"
  readonly property string barTemp: current && card.hasTemp(current.temp) ? String(current.temp) + "°" : "—"
  readonly property bool hasAlert: alerts && alerts.length > 0

  readonly property string tooltipText: {
    if (!current) return error || "Weather\nClick for " + daysCount + "-day forecast"
    var lines = []
    var head = (location ? location + " · " : "") + barTemp + unit
    if (current.short) head += " " + current.short
    lines.push(head)
    if (card.hiLoText) lines.push(card.hiLoText)
    lines.push("Click for " + daysCount + "-day forecast · Right-click to refresh")
    return lines.join("\n")
  }

  readonly property bool tooltipHovered: hover.hovered
  function syncTooltip() {
    if (!bar || typeof bar.showTooltip !== "function") return
    if (hover.hovered && !forecastOpen && tooltipText !== "") bar.showTooltip(root, tooltipText)
    else bar.hideTooltip(root)
  }
  onTooltipTextChanged: if (hover.hovered) syncTooltip()

  implicitWidth: vertical ? barSize : pill.implicitWidth + Style.space(2)
  implicitHeight: vertical ? pill.implicitHeight + Style.space(4) : barSize

  Rectangle {
    id: pill
    anchors.centerIn: parent
    implicitWidth: root.vertical ? root.barSize - Style.space(4) : hRow.implicitWidth + Style.space(12)
    implicitHeight: root.vertical ? vCol.implicitHeight + Style.space(8) : Math.round(root.barSize * 0.72)
    width: implicitWidth
    height: implicitHeight
    radius: root.vertical ? Style.space(8) : height / 2
    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b,
      clickTarget.held ? 0.18 : root.forecastOpen ? 0.14 : hover.hovered ? 0.09 : 0.0)
    Behavior on color { ColorAnimation { duration: Style.duration(120) } }

    Row {
      id: hRow
      visible: !root.vertical
      anchors.centerIn: parent
      spacing: Style.space(5)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.barIcon
        color: root.forecastOpen || root.hasAlert ? root.accent : root.ink
        opacity: root.current ? 1.0 : 0.65
        font.family: root.fontName
        font.pixelSize: Style.font.icon
        Behavior on color { ColorAnimation { duration: Style.duration(150) } }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.barTemp
        textFormat: Text.PlainText
        color: root.ink
        opacity: root.current ? 0.92 : 0.55
        font.family: root.fontName
        font.pixelSize: Style.font.bodySmall
      }
    }

    Column {
      id: vCol
      visible: root.vertical
      anchors.centerIn: parent
      spacing: Style.space(2)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.barIcon
        color: root.forecastOpen || root.hasAlert ? root.accent : root.ink
        opacity: root.current ? 1.0 : 0.65
        font.family: root.fontName
        font.pixelSize: Style.font.icon
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.barTemp
        textFormat: Text.PlainText
        color: root.ink
        opacity: root.current ? 0.92 : 0.55
        font.family: root.fontName
        font.pixelSize: Style.font.caption
      }
    }
  }

  PopupCard {
    id: popup
    anchorItem: pill
    bar: root.bar
    owner: root
    open: root.forecastOpen
    contentWidth: popup.fittedContentWidth(card.implicitWidth)
    contentHeight: popup.fittedContentHeight(card.implicitHeight)

    OmabarWeatherCard {
      id: card
      anchors.fill: parent
      ink: Commons.Color.popups.text
      fontName: root.fontName
      loading: root.loading
      stale: root.stale
      error: root.error
      location: root.location
      unit: root.unit
      updatedText: root.updatedText
      radarUrl: root.radarUrl
      current: root.current
      days: root.daysData
      alerts: root.alerts
      onRefreshRequested: root.load(true)
      onRadarRequested: root.openRadar()
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
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onPressed: function(button) {
      if (button === Qt.RightButton) root.load(true)
      else root.forecastOpen = !root.forecastOpen
    }
  }
}
