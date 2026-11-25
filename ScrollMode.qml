import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui as Ui
import qs.Commons
import qs.Commons as Commons

// Scroll modes: pointer, scroll, sniper. Left click opens the settings panel;
// the daemon also turns a held side button into a temporary sniper trigger.
//
// The daemon reports every pointing device in /run/omarchy-scrollmode/status.json.
// Settings stay hidden until the device picked in the dropdown is actually
// active in the daemon ("Use this device"), so nothing is applied to a device
// that has not been grabbed yet.
Ui.Panel {
  id: root
  moduleName: "anton.scrollmode"
  manageIpc: false

  readonly property string statePath: "/run/omarchy-scrollmode/state"
  readonly property string statusPath: "/run/omarchy-scrollmode/status.json"
  readonly property string cfgPath: Quickshell.env("HOME") + "/.config/omarchy/scrollmode.json"
  readonly property string cli: "/usr/local/bin/omarchy-scrollmode"

  readonly property string mode: String(stateFile.text() || "").trim()
  readonly property bool scrolling: mode === "scroll" || mode === "sniper"
  readonly property bool sniper: mode === "sniper"
  readonly property color idleColor: "#8f9aa3"
  readonly property color modeColor: root.sniper ? "#d9a441" : (root.scrolling ? "#5f87d9" : "#d95f5f")
  readonly property bool hasDevice: root.present && root.serviceState === "active"
  readonly property color ballColor: root.hasDevice ? root.modeColor : root.idleColor
  readonly property string modeLabel: !root.hasDevice
    ? strings.t("mode.none")
    : (root.sniper
      ? strings.t("mode.sniper")
      : (root.scrolling ? strings.t("mode.scroll") : strings.t("mode.pointer")))

  property Component ballIcon: Component {
    Item {
      implicitWidth: Style.bar.iconSize
      implicitHeight: Style.bar.iconSize

      DeviceIcon {
        anchors.fill: parent
        size: Style.bar.iconSize
        color: root.ballColor
        kind: root.deviceKind
      }

      Canvas {
        id: batteryRing
        visible: root.batteryShowBar && root.batteryAvailable && root.batteryPercent >= 0
        width: root.batteryDotSize
        height: width
        anchors.right: parent.right
        anchors.rightMargin: -3
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -3
        antialiasing: true
        opacity: root.batteryStale ? 0.65 : 1

        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var w = width
          var h = height
          var cx = w / 2
          var cy = h / 2
          var stroke = Math.max(1.2, w * 0.18)
          var r = Math.max(1, w / 2 - 1)
          ctx.beginPath()
          ctx.arc(cx, cy, r, 0, Math.PI * 2)
          ctx.fillStyle = Qt.rgba(0, 0, 0, 0.72)
          ctx.fill()
          ctx.lineWidth = stroke
          ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.18)
          ctx.beginPath()
          ctx.arc(cx, cy, r - stroke / 2, 0, Math.PI * 2)
          ctx.stroke()
          var pct = Math.max(0, Math.min(100, root.batteryPercent))
          if (pct > 0) {
            ctx.strokeStyle = root.batteryColor
            ctx.beginPath()
            ctx.arc(cx, cy, r - stroke / 2, -Math.PI / 2,
              -Math.PI / 2 + Math.PI * 2 * pct / 100)
            ctx.stroke()
          } else {
            ctx.fillStyle = root.batteryColor
            ctx.beginPath()
            ctx.arc(cx, cy, Math.max(1, r * 0.4), 0, Math.PI * 2)
            ctx.fill()
          }
        }

        Connections {
          target: root
          function onBatteryPercentChanged() { batteryRing.requestPaint() }
          function onBatteryColorChanged() { batteryRing.requestPaint() }
          function onBatteryAvailableChanged() { batteryRing.requestPaint() }
          function onBatteryShowBarChanged() { batteryRing.requestPaint() }
        }
      }
    }
  }

  readonly property var status: {
    var text = statusFile.text() || ""
    if (!text) return ({})
    try {
      return JSON.parse(text)
    } catch (error) {
      return ({})
    }
  }
  readonly property var devices: (status && status.devices) ? status.devices : []
  readonly property string activeId: (status && status.activeId) ? String(status.activeId) : ""
  readonly property string selectedId: (status && status.selectedId) ? String(status.selectedId) : ""
  readonly property bool present: !!(status && status.present === true)
  readonly property string activeName: (status && status.name) ? String(status.name) : ""
  readonly property string deviceKind: (status && status.kind) ? String(status.kind) : ""
  readonly property string deviceCode: (status && status.code) ? String(status.code) : "UN"
  readonly property string connection: (status && status.connection) ? String(status.connection) : "unknown"
  readonly property string deviceTitle: root.deviceKindLabel(root.deviceKind)
  readonly property bool supportsScroll: status && status.supportsScroll !== undefined
    ? status.supportsScroll === true
    : (root.deviceKind === "" || root.deviceKind === "trackball" || root.deviceKind === "unknown")
  readonly property bool supportsStats: status && status.supportsStats !== undefined
    ? status.supportsStats === true
    : (root.deviceKind === "" || root.deviceKind === "trackball" || root.deviceKind === "mouse")
  readonly property bool supportsButtons: status && status.supportsButtons !== undefined
    ? status.supportsButtons === true
    : (root.deviceKind === "" || root.deviceKind === "trackball" || root.deviceKind === "unknown")
  // Scroll and Feel are only real for devices that support scroll mode. The
  // content also has to check this: after switching to a mouse `tab` may still
  // hold its old value for one frame while tabOptions is rebuilt.
  readonly property bool scrollTabVisible: root.supportsScroll && root.tab === 0
  readonly property bool feelTabVisible: root.supportsScroll && root.tab === 1

  function deviceKindLabel(kind) {
    if (kind === "trackball") return strings.t("device.kind.trackball")
    if (kind === "mouse") return strings.t("device.kind.mouse")
    if (kind === "trackpad") return strings.t("device.kind.trackpad")
    if (kind === "tablet") return strings.t("device.kind.tablet")
    return strings.t("device.kind.unknown")
  }

  function deviceCodeForKind(kind) {
    if (kind === "trackball") return "TB"
    if (kind === "mouse") return "MS"
    if (kind === "trackpad") return "TP"
    if (kind === "tablet") return "TA"
    return "UN"
  }
  function connectionShort(value) {
    if (value === "usb") return strings.t("connection.shortUsb")
    if (value === "receiver") return strings.t("connection.shortReceiver")
    if (value === "bluetooth") return strings.t("connection.shortBluetooth")
    return strings.t("connection.shortUnknown")
  }
  readonly property int hiddenCount: (status && status.hidden) ? Number(status.hidden) : 0
  readonly property bool sniperAvailable: !!(status && status.sniperAvailable === true)
  readonly property int sniperCode: (status && Number(status.sniperCode)) ? Number(status.sniperCode) : 0
  readonly property bool learning: !!(status && status.learning === true)
  readonly property string learnError: (status && status.learnError) ? String(status.learnError) : ""
  readonly property string sniperButtonName: {
    var code = root.sniperCode
    if (code === 279) return strings.t("button.task")
    if (code === 280) return strings.t("button.extra")
    if (code > 0) return strings.t("button.number").arg(code)
    return strings.t("button.none")
  }
  readonly property string learnErrorText: {
    if (root.learnError === "reserved") return strings.t("menu.sniperReserved")
    if (root.learnError === "timeout") return strings.t("menu.sniperTimeout")
    return ""
  }

  readonly property var batteryInfo: (status && status.battery && typeof status.battery === "object")
    ? status.battery : ({})
  readonly property bool batteryWireless: !!(batteryInfo && batteryInfo.wireless === true)
  readonly property bool deviceWireless: !!(status && status.wireless === true)
  readonly property bool batteryAvailable: root.present && root.deviceWireless
    && root.batteryWireless && !!(batteryInfo && batteryInfo.available === true)
  readonly property int batteryPercent: batteryAvailable
    && batteryInfo.percent !== null && batteryInfo.percent !== undefined
    ? Math.max(0, Math.min(100, Number(batteryInfo.percent))) : -1
  readonly property string batteryLevel: (batteryInfo && batteryInfo.level)
    ? String(batteryInfo.level) : ""
  readonly property string batteryState: (batteryInfo && batteryInfo.state)
    ? String(batteryInfo.state) : ""
  readonly property bool batteryCharging: !!(batteryInfo && batteryInfo.charging === true)
  readonly property bool batteryStale: !!(batteryInfo && batteryInfo.stale === true)
  readonly property int batteryLowPercent: Math.max(0, Number(root.value("battery.low_percent", 20)))
  readonly property bool batteryShowBar: root.value("battery.show_bar", true) === true
  readonly property int batteryDotSize: Math.max(10, Math.round(Style.bar.iconSize * 0.60))
  readonly property color batteryColor: {
    if (!root.batteryAvailable) return root.idleColor
    if (root.batteryCharging) return "#5f87d9"
    if (root.batteryPercent >= 0) {
      if (root.batteryPercent <= root.batteryLowPercent) return "#d95f5f"
      if (root.batteryPercent <= root.batteryLowPercent + 15) return "#d9a441"
      return "#a7c080"
    }
    if (root.batteryLevel === "critical") return "#d95f5f"
    if (root.batteryLevel === "low") return "#d9a441"
    return "#a7c080"
  }
  readonly property string batteryPercentText: root.batteryPercent >= 0
    ? root.batteryPercent + "%" : "—"
  readonly property string batteryStateLabel: root.batteryStateText(root.batteryState)
  readonly property string batteryIcon: {
    if (root.batteryCharging) return "\uf0e7"
    if (root.batteryPercent < 0) {
      if (root.batteryLevel === "critical" || root.batteryLevel === "low") return "\uf244"
      if (root.batteryLevel === "good") return "\uf242"
      return "\uf240"
    }
    if (root.batteryPercent >= 90) return "\uf240"
    if (root.batteryPercent >= 65) return "\uf241"
    if (root.batteryPercent >= 40) return "\uf242"
    if (root.batteryPercent >= 15) return "\uf243"
    return "\uf244"
  }
  readonly property string batteryTooltip: !root.batteryAvailable ? ""
    : " · " + root.batteryPercentText
      + (root.batteryCharging ? " " + strings.t("battery.chargingSuffix") : "")

  function batteryStateText(state) {
    if (state === "charging") return strings.t("battery.state.charging")
    if (state === "nearly-full") return strings.t("battery.state.nearlyFull")
    if (state === "full") return strings.t("battery.state.full")
    if (state === "slow-charging") return strings.t("battery.state.slowCharging")
    if (state === "invalid") return strings.t("battery.state.invalid")
    if (state === "thermal-error") return strings.t("battery.state.thermalError")
    if (state === "charging-error") return strings.t("battery.state.chargingError")
    if (state === "discharging") return strings.t("battery.state.discharging")
    return ""
  }

  // Historical statistics are aggregated by the daemon in the system state
  // directory; the panel only reads the result.
  readonly property real countsPerTurn: 1600
  readonly property real ballCircumference: 0.1068  // metres, ~34 mm ball

  readonly property var statsInfo: {
    var text = statsFile.text() || ""
    if (!text) return ({})
    try {
      return JSON.parse(text)
    } catch (error) {
      return ({})
    }
  }
  readonly property var trackballInfo: {
    if (statsInfo && statsInfo.trackball) return statsInfo.trackball
    if (statsInfo && statsInfo.counts !== undefined) return statsInfo
    return ({})
  }
  readonly property var mouseInfo: (statsInfo && statsInfo.mouse) ? statsInfo.mouse : ({})
  readonly property real statCounts: Number(trackballInfo.counts || 0)
  readonly property real statNotches: Number(trackballInfo.notches || 0)
  readonly property int statFlicks: Number(trackballInfo.flicks || 0)
  readonly property int statCoasted: Number(trackballInfo.coasted || 0)
  readonly property real statScrollMs: Number(trackballInfo.scroll_ms || 0)
  readonly property real statPeak: Number(trackballInfo.max_peak_notches || 0)
  readonly property real statPeakCounts: Number(trackballInfo.max_peak_counts || 0)
  readonly property real statLongestCoast: Number(trackballInfo.max_coast_notches || 0)
  readonly property real statLongestFlick: Number(trackballInfo.max_flick_ms || 0)
  readonly property var statDays: (trackballInfo && trackballInfo.days) ? trackballInfo.days : ({})
  readonly property string statTodayKey: Qt.formatDate(new Date(), "yyyy-MM-dd")
  readonly property var statToday: statDays[root.statTodayKey] || ({})
  readonly property real statTodayKm: root.dayKm(statToday)
  readonly property int statActiveDays: Object.keys(statDays).length
  readonly property string statBestKey: {
    var best = ""
    var bestValue = -1
    for (var key in statDays) {
      var value = Number((statDays[key] || {}).notches || 0)
      if (value > bestValue) {
        bestValue = value
        best = key
      }
    }
    return best
  }
  readonly property real statBestKm: root.dayKm(statDays[root.statBestKey] || ({}))
  readonly property string statBestLabel: {
    if (root.statBestKey === "") return "—"
    var date = new Date(root.statBestKey + "T12:00:00")
    return Qt.formatDate(date, "d MMM yyyy")
  }
  readonly property string statDirection: {
    var up = Number(trackballInfo.up || 0)
    var down = Number(trackballInfo.down || 0)
    var left = Number(trackballInfo.left || 0)
    var right = Number(trackballInfo.right || 0)
    var top = Math.max(up, down, left, right)
    if (top <= 0) return "—"
    if (up === top) return strings.t("stats.up")
    if (down === top) return strings.t("stats.down")
    if (left === top) return strings.t("stats.left")
    return strings.t("stats.right")
  }
  readonly property real statTurns: statCounts / countsPerTurn
  readonly property real statKm: statTurns * ballCircumference / 1000
  readonly property real statRpm: statPeakCounts / countsPerTurn * 60
  readonly property real statCoastPct: statFlicks > 0 ? 100 * statCoasted / statFlicks : 0

  readonly property real mouseCounts: Number(mouseInfo.counts || 0)
  readonly property real mouseWheel: Number(mouseInfo.wheel || 0)
  readonly property int mouseClicks: Number(mouseInfo.clicks || 0)
  readonly property real mouseActiveMs: Number(mouseInfo.active_ms || 0)
  readonly property real mousePeak: Number(mouseInfo.max_speed || 0)
  readonly property real mouseDpi: Number(mouseInfo.dpi || 0)
  readonly property var mouseDays: (mouseInfo && mouseInfo.days) ? mouseInfo.days : ({})
  readonly property var mouseToday: mouseDays[root.statTodayKey] || ({})
  readonly property real mouseKm: root.mouseDpi > 0
    ? root.mouseCounts / root.mouseDpi * 0.0254 / 1000 : 0
  readonly property bool mouseHasDistance: root.mouseDpi > 0
  readonly property int mouseActiveDays: Object.keys(mouseDays).length
  readonly property string mouseBestKey: {
    var best = ""
    var bestValue = -1
    for (var key in mouseDays) {
      var value = Number((mouseDays[key] || {}).counts || 0)
      if (value > bestValue) {
        bestValue = value
        best = key
      }
    }
    return best
  }
  readonly property real mouseBestCounts: root.mouseBestKey !== ""
    ? Number((mouseDays[root.mouseBestKey] || {}).counts || 0) : 0
  readonly property real mouseBestKm: root.mouseBestKey !== ""
    ? root.mouseDayKm(mouseDays[root.mouseBestKey] || ({})) : 0
  readonly property string mouseBestLabel: root.mouseBestKey === "" ? "—"
    : Qt.formatDate(new Date(root.mouseBestKey + "T12:00:00"), "d MMM yyyy")
  readonly property string mouseDirection: {
    var up = Number(mouseInfo.up || 0)
    var down = Number(mouseInfo.down || 0)
    var left = Number(mouseInfo.left || 0)
    var right = Number(mouseInfo.right || 0)
    var top = Math.max(up, down, left, right)
    if (top <= 0) return "—"
    if (up === top) return strings.t("stats.up")
    if (down === top) return strings.t("stats.down")
    if (left === top) return strings.t("stats.left")
    return strings.t("stats.right")
  }
  readonly property bool mouseEmpty: mouseCounts <= 0 && mouseWheel <= 0 && mouseClicks <= 0
  readonly property string mouseMovementText: root.mouseHasDistance
    ? root.fmtDistance(root.mouseKm)
    : root.fmtNumber(root.mouseCounts, 0) + " " + strings.t("stats.countsUnit")

  function mouseDayKm(day) {
    if (root.mouseDpi <= 0) return 0
    return Number(day.counts || 0) / root.mouseDpi * 0.0254 / 1000
  }

  function mouseDayText(day) {
    if (root.mouseHasDistance) return root.fmtDistance(root.mouseDayKm(day))
    return root.fmtNumber(Number(day.counts || 0), 0) + " "
      + strings.t("stats.countsUnit")
  }

  function cosmicProgressKm(km, targetKm) {
    return statProgressPercent(km, targetKm)
      + " (" + fmtNumber(statCompleted(km, targetKm), 0) + ")"
  }

  function fmtNumber(value, digits) {
    var number = Number(value)
    if (!isFinite(number)) return "—"
    var text = number.toFixed(digits === undefined ? 0 : digits)
    var parts = text.split(".")
    parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, " ")
    return parts.join(".")
  }

  function fmtDistance(km) {
    var value = Number(km)
    if (!isFinite(value)) return "—"
    if (value >= 1) return fmtNumber(value, 2) + " km"
    var metres = value * 1000
    if (metres >= 1) return fmtNumber(metres, 1) + " m"
    return fmtNumber(metres * 100, 1) + " cm"
  }

  function fmtDuration(ms) {
    var seconds = Math.max(0, Number(ms)) / 1000
    if (seconds < 60) return fmtNumber(seconds, 1) + " s"
    var minutes = Math.floor(seconds / 60)
    var rest = Math.round(seconds % 60)
    if (rest === 60) { minutes += 1; rest = 0 }
    if (minutes < 60) return minutes + " m " + rest + " s"
    var hours = Math.floor(minutes / 60)
    minutes = minutes % 60
    return hours + " h " + minutes + " m"
  }

  function statTurnsFor(km) {
    return Number(km) * 1000 / root.ballCircumference
  }

  function statCompleted(turns, target) {
    var value = Number(turns)
    var goal = Number(target)
    if (!(value > 0) || !(goal > 0)) return 0
    return Math.floor(value / goal + 1e-12)
  }

  function statProgressPercent(turns, target) {
    var value = Number(turns)
    var goal = Number(target)
    if (!(value > 0) || !(goal > 0)) return "0 %"
    var percent = (value / goal * 100) % 100
    var digits = percent >= 1 ? 2 : percent >= 0.01 ? 4
      : percent >= 0.0001 ? 6 : percent >= 0.000001 ? 8 : 10
    var text = percent.toFixed(digits)
    if (text.indexOf(".") >= 0) {
      text = text.replace(/0+$/, "").replace(/\.$/, "")
    }
    return text + " %"
  }

  function cosmicProgress(turns, targetKm) {
    var target = root.statTurnsFor(targetKm)
    return statProgressPercent(turns, target)
      + " (" + fmtNumber(statCompleted(turns, target), 0) + ")"
  }

  function fmtMultiple(value) {
    var number = Number(value)
    if (!isFinite(number)) return "—"
    if (number >= 100) return fmtNumber(number, 0)
    var text
    if (number >= 10) text = number.toFixed(1)
    else if (number >= 1) text = number.toFixed(2)
    else if (number >= 0.01) text = number.toFixed(3)
    else if (number >= 0.0001) text = number.toFixed(5)
    else if (number >= 0.000001) text = number.toFixed(7)
    else text = number.toFixed(9)
    text = text.replace(/0+$/, "").replace(/\.$/, "")
    return text
  }

  function dayKm(day) {
    var entry = day || {}
    var counts = Number(entry.counts || 0)
    if (counts > 0) return counts / countsPerTurn * ballCircumference / 1000
    var notches = Number(entry.notches || 0)
    var cpn = root.statNotches > 0 ? root.statCounts / root.statNotches : 85
    return notches * cpn / countsPerTurn * ballCircumference / 1000
  }

  readonly property var deviceOptions: {
    var options = []
    var list = root.devices || []
    for (var i = 0; i < list.length; i++) {
      var kind = list[i].kind ? String(list[i].kind) : "unknown"
      var code = list[i].code ? String(list[i].code) : root.deviceCodeForKind(kind)
      var conn = list[i].connection ? root.connectionShort(String(list[i].connection)) : ""
      options.push({
        value: list[i].id,
        label: list[i].name + (conn !== "" ? " · " + conn : "") + " · " + code
      })
    }
    return options
  }

  property string pendingId: ""
  readonly property bool pendingMismatch: root.devices.length > 0
    && root.pendingId !== "" && root.pendingId !== root.activeId
  readonly property bool noDevices: root.devices.length === 0
  readonly property var footerHints: strings.t("footer.keys").split("·")
  readonly property bool settingsVisible: root.serviceState === "active"
    && !root.noDevices && !root.pendingMismatch

  readonly property color doneColor: "#a7c080"
  readonly property color armedColor: "#dbbc7f"

  property int tab: 0
  readonly property var tabOptions: {
    var options = []
    if (root.supportsScroll) {
      options.push({ index: 0, label: strings.t("tab.scroll") })
      options.push({ index: 1, label: strings.t("tab.feel") })
    }
    options.push({ index: 2, label: strings.t("tab.device") })
    if (root.supportsStats)
      options.push({ index: 3, label: strings.t("tab.stats") })
    return options
  }
  function ensureTab() {
    var options = root.tabOptions
    for (var i = 0; i < options.length; i++)
      if (options[i].index === root.tab) return
    root.tab = options.length ? options[0].index : 2
  }
  function selectTab(position) {
    var slot = Number(position) - 1
    var options = root.tabOptions
    if (slot < 0 || slot >= options.length) return
    root.tab = options[slot].index
    root.cursorIndex = 0
    root.cursorActive = false
    Qt.callLater(function() { root.cursorActive = true })
    Qt.callLater(root.ensureCursorVisible)
  }
  onDeviceKindChanged: {
    if (root.deviceKind === "mouse" && (root.tab === 0 || root.tab === 1))
      root.tab = 2
    Qt.callLater(root.ensureTab)
  }
  onSupportsScrollChanged: Qt.callLater(root.ensureTab)
  onTabOptionsChanged: Qt.callLater(root.ensureTab)

  // Keyboard cursor. The row order follows the active tab and only includes
  // controls that are actually visible. Mouse hover feeds the same index.
  property bool cursorActive: false
  property int cursorIndex: 0
  readonly property var rowOrder: {
    if (!root.settingsVisible) return []
    var rows = []
    if (root.tab === 0) {
      rows = ["speed", "speedHelp", "sniper", "sniperHelp", "invertV", "invertH",
        "axisLock", "axisLockHelp", "hiRes", "hiResHelp",
        "exitOnClick", "exitOnClickHelp"]
    } else if (root.tab === 1) {
      rows = ["inertia", "inertiaHelp"]
      if (root.bool("scroll.inertia")) {
        rows.push("inertiaTrigger")
        rows.push("inertiaTriggerHelp")
        rows.push("inertiaCoast")
        rows.push("inertiaCoastHelp")
      }
      rows.push("holdThreshold")
      rows.push("holdThresholdHelp")
      rows.push("autoExit")
      rows.push("autoExitHelp")
    } else if (root.tab === 2) {
      rows = ["device", "useDevice", "rescan"]
      if (root.batteryAvailable) {
        rows.push("batteryShowBar")
        rows.push("batteryShowBarHelp")
        rows.push("batteryLow")
        rows.push("batteryLowHelp")
        rows.push("batteryPoll")
        rows.push("batteryPollHelp")
      }
      if (root.supportsButtons) {
        if (root.sniperAvailable) {
          if (root.sniperCode > 0) {
            rows.push("sniperClear")
            rows.push("sniperClearHelp")
          }
          rows.push("sniperChoose")
          if (root.sniperCode === 0) rows.push("sniperChooseHelp")
        }
        rows.push("openConfig")
        rows.push("reset")
      }
    }
    return rows
  }
  readonly property string cursorId: root.cursorActive && root.cursorIndex >= 0
    && root.cursorIndex < root.rowOrder.length ? root.rowOrder[root.cursorIndex] : ""
  onRowOrderChanged: {
    if (root.cursorIndex >= root.rowOrder.length)
      root.cursorIndex = Math.max(0, root.rowOrder.length - 1)
    Qt.callLater(root.ensureCursorVisible)
  }
  onTabChanged: {
    root.cursorIndex = 0
    root.cursorActive = false
    Qt.callLater(root.ensureCursorVisible)
  }
  onOpenedChanged: {
    if (root.opened) {
      root.cursorIndex = 0
      root.cursorActive = false
      Qt.callLater(root.ensureCursorVisible)
    }
  }
  function ensureCursorVisible() {
    var target = root.cursorTarget(root.cursorId)
    if (!target || !target.visible) return
    var y = target.mapToItem(bodyContent, 0, 0).y
    var top = bodyFlick.contentY
    var bottom = top + bodyFlick.height
    var margin = Style.space(8)
    if (y < top + margin) {
      bodyFlick.contentY = Math.max(0, y - margin)
    } else if (y + target.height > bottom - margin) {
      var limit = Math.max(0, bodyFlick.contentHeight - bodyFlick.height)
      bodyFlick.contentY = Math.min(limit,
        y + target.height - bodyFlick.height + margin)
    }
  }
  function setCursor(id) {
    var i = root.rowOrder.indexOf(id)
    if (i < 0) return
    root.cursorIndex = i
    root.cursorActive = true
    Qt.callLater(root.ensureCursorVisible)
  }
  function rowHasCursor(id) {
    return root.cursorActive && root.cursorId === id
  }
  function moveCursor(delta) {
    if (root.rowOrder.length === 0) {
      var limit = Math.max(0, bodyFlick.contentHeight - bodyFlick.height)
      bodyFlick.contentY = Math.max(0, Math.min(limit,
        bodyFlick.contentY + delta * Style.space(64)))
      return
    }
    if (!root.cursorActive) {
      root.cursorActive = true
      Qt.callLater(root.ensureCursorVisible)
      return
    }
    root.cursorIndex = Math.max(0, Math.min(root.rowOrder.length - 1,
      root.cursorIndex + delta))
    Qt.callLater(root.ensureCursorVisible)
  }
  function cursorTarget(id) {
    if (id === "speed") return speedSlider
    if (id === "speedHelp") return speedSlider.helpIcon
    if (id === "sniper") return sniperSlider
    if (id === "sniperHelp") return sniperSlider.helpIcon
    if (id === "invertV") return invertVToggle
    if (id === "invertH") return invertHToggle
    if (id === "axisLock") return axisLockToggle
    if (id === "axisLockHelp") return axisLockToggle.helpIcon
    if (id === "hiRes") return hiResToggle
    if (id === "hiResHelp") return hiResToggle.helpIcon
    if (id === "exitOnClick") return exitOnClickToggle
    if (id === "exitOnClickHelp") return exitOnClickToggle.helpIcon
    if (id === "inertia") return inertiaToggle
    if (id === "inertiaHelp") return inertiaToggle.helpIcon
    if (id === "inertiaTrigger") return inertiaTriggerSlider
    if (id === "inertiaTriggerHelp") return inertiaTriggerSlider.helpIcon
    if (id === "inertiaCoast") return inertiaCoastSlider
    if (id === "inertiaCoastHelp") return inertiaCoastSlider.helpIcon
    if (id === "holdThreshold") return holdSlider
    if (id === "holdThresholdHelp") return holdSlider.helpIcon
    if (id === "autoExit") return autoExitRow
    if (id === "autoExitHelp") return autoExitHint
    if (id === "device") return devicePicker
    if (id === "useDevice") return useButton
    if (id === "rescan") return refreshButton
    if (id === "batteryShowBar") return batteryShowToggle
    if (id === "batteryShowBarHelp") return batteryShowToggle.helpIcon
    if (id === "batteryLow") return batteryLowSlider
    if (id === "batteryLowHelp") return batteryLowSlider.helpIcon
    if (id === "batteryPoll") return batteryPollRow
    if (id === "batteryPollHelp") return pollHint
    if (id === "sniperClear") return sniperClearToggle
    if (id === "sniperClearHelp") return sniperClearToggle.helpIcon
    if (id === "sniperChoose") return sniperChooseButton
    if (id === "sniperChooseHelp") return sniperChooseHint
    if (id === "openConfig") return openConfigButton
    if (id === "reset") return resetButton
    return null
  }
  function nudgeSlider(row, delta) {
    if (!row) return
    var next = row.snap(row.sliderValue + delta * row.step)
    row.commit(row.fromSlider ? row.fromSlider(next) : next)
    row.flash = true
  }
  function cycleNumber(path, values, delta) {
    var current = Number(root.value(path, values[0]))
    var index = values.indexOf(current)
    if (index < 0) index = 0
    index = (index + delta + values.length) % values.length
    root.setValue(path, values[index])
  }
  function cyclePending(delta) {
    var options = root.deviceOptions
    if (options.length === 0) return
    var index = 0
    for (var i = 0; i < options.length; i++)
      if (options[i].value === root.pendingId) { index = i; break }
    index = (index + delta + options.length) % options.length
    root.pendingId = options[index].value
  }
  function applyPendingDevice() {
    if (root.pendingId !== root.activeId) root.useDevice(root.pendingId)
  }
  function adjustCursor(delta) {
    if (!root.cursorActive) {
      root.cursorActive = true
      Qt.callLater(root.ensureCursorVisible)
      return
    }
    var id = root.cursorId
    if (id === "speed") root.nudgeSlider(speedSlider, delta)
    else if (id === "sniper") root.nudgeSlider(sniperSlider, delta)
    else if (id === "invertV") root.setValue("scroll.invert_vertical", !root.bool("scroll.invert_vertical"))
    else if (id === "invertH") root.setValue("scroll.invert_horizontal", !root.bool("scroll.invert_horizontal"))
    else if (id === "axisLock") root.setValue("scroll.axis_lock", !root.bool("scroll.axis_lock"))
    else if (id === "hiRes") root.setValue("scroll.hi_res", !root.bool("scroll.hi_res"))
    else if (id === "exitOnClick") root.setValue("exit_on_click", !root.bool("exit_on_click"))
    else if (id === "inertia") root.setValue("scroll.inertia", !root.bool("scroll.inertia"))
    else if (id === "inertiaTrigger") root.nudgeSlider(inertiaTriggerSlider, delta)
    else if (id === "inertiaCoast") root.nudgeSlider(inertiaCoastSlider, delta)
    else if (id === "holdThreshold") root.nudgeSlider(holdSlider, delta)
    else if (id === "autoExit") root.cycleNumber("auto_exit_seconds", [0, 15, 30, 60], delta)
    else if (id === "device") root.cyclePending(delta)
    else if (id === "batteryShowBar") root.setValue("battery.show_bar", !root.batteryShowBar)
    else if (id === "batteryLow") root.nudgeSlider(batteryLowSlider, delta)
    else if (id === "batteryPoll") root.cycleNumber("battery.poll_seconds", [60, 300, 900, 1800], delta)
    else if (id === "sniperClear") root.setValue("sniper_button", 0)
  }
  function activateCursor() {
    if (!root.cursorActive) {
      root.cursorActive = true
      Qt.callLater(root.ensureCursorVisible)
      return
    }
    var id = root.cursorId
    if (id === "speed") speedSlider.flash = true
    else if (id === "sniper") sniperSlider.flash = true
    else if (id === "invertV") root.setValue("scroll.invert_vertical", !root.bool("scroll.invert_vertical"))
    else if (id === "invertH") root.setValue("scroll.invert_horizontal", !root.bool("scroll.invert_horizontal"))
    else if (id === "axisLock") root.setValue("scroll.axis_lock", !root.bool("scroll.axis_lock"))
    else if (id === "hiRes") root.setValue("scroll.hi_res", !root.bool("scroll.hi_res"))
    else if (id === "exitOnClick") root.setValue("exit_on_click", !root.bool("exit_on_click"))
    else if (id === "inertia") root.setValue("scroll.inertia", !root.bool("scroll.inertia"))
    else if (id === "inertiaTrigger") inertiaTriggerSlider.flash = true
    else if (id === "inertiaCoast") inertiaCoastSlider.flash = true
    else if (id === "holdThreshold") holdSlider.flash = true
    else if (id === "autoExit") root.cycleNumber("auto_exit_seconds", [0, 15, 30, 60], 1)
    else if (id === "device") devicePicker.open()
    else if (id === "useDevice") root.applyPendingDevice()
    else if (id === "rescan") root.rescan()
    else if (id === "batteryShowBar") root.setValue("battery.show_bar", !root.batteryShowBar)
    else if (id === "batteryLow") batteryLowSlider.flash = true
    else if (id === "batteryPoll") root.cycleNumber("battery.poll_seconds", [60, 300, 900, 1800], 1)
    else if (id === "sniperClear") root.setValue("sniper_button", 0)
    else if (id === "sniperChoose") Quickshell.execDetached([root.cli, "learn"])
    else if (id === "openConfig") Quickshell.execDetached(["omarchy-launch-editor", root.cfgPath])
    else if (id === "reset") root.triggerReset()
  }
  function triggerReset() {
    if (resetButton.done) return
    if (resetButton.armed) {
      resetButton.armed = false
      Quickshell.execDetached([root.cli, "reset"])
      resetButton.done = true
      resetDoneTimer.restart()
    } else {
      resetButton.armed = true
      resetArmedTimer.restart()
    }
  }
  property bool sniperDone: false
  property int lastSniperCode: 0

  onSniperCodeChanged: {
    if (root.sniperCode > 0 && root.sniperCode !== root.lastSniperCode
        && root.sniperCode === root.learnCode) {
      root.sniperDone = true
      sniperDoneTimer.restart()
    }
    root.lastSniperCode = root.sniperCode
  }

  Timer {
    id: sniperDoneTimer
    interval: 1500
    onTriggered: root.sniperDone = false
  }

  // The daemon lives outside the plugin (root, /usr/local, systemd). The panel
  // offers a one-click install that opens a terminal for the sudo prompt.
  property string serviceState: "active"  // active | stopped | missing

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  function value(path, fallback) {
    var node = root.cfg
    var parts = path.split(".")
    for (var i = 0; i < parts.length; i++) {
      if (node === null || node === undefined) return fallback
      node = node[parts[i]]
    }
    return node === undefined || node === null ? fallback : node
  }

  function bool(path) {
    return root.value(path, false) === true
  }

  function setValue(path, value) {
    Quickshell.execDetached([root.cli, "set", path, String(value)])
  }

  function useDevice(id) {
    if (id === "") return
    Quickshell.execDetached([root.cli, "use", id])
  }

  function rescan() {
    Quickshell.execDetached([root.cli, "rescan"])
  }

  function installService() {
    var script = decodeURIComponent(Qt.resolvedUrl("install.sh").toString().replace(/^file:\/\//, ""))
    Quickshell.execDetached(["omarchy-launch-terminal", "bash", script])
  }

  function syncPending() {
    var list = root.devices || []
    if (list.length === 0) {
      root.pendingId = ""
      return
    }
    var ids = []
    for (var i = 0; i < list.length; i++) ids.push(list[i].id)
    if (root.pendingId !== "" && ids.indexOf(root.pendingId) >= 0) return

    if (root.activeId !== "" && ids.indexOf(root.activeId) >= 0)
      root.pendingId = root.activeId
    else if (root.selectedId !== "" && ids.indexOf(root.selectedId) >= 0)
      root.pendingId = root.selectedId
    else
      root.pendingId = list[0].id
  }

  readonly property var cfg: {
    var text = configFile.text() || ""
    if (!text) return ({})
    try {
      return JSON.parse(text)
    } catch (error) {
      return ({})
    }
  }

  Component.onCompleted: {
    syncPending()
    Qt.callLater(root.ensureTab)
    installProbe.running = true
  }
  onStatusChanged: {
    syncPending()
    Qt.callLater(root.ensureTab)
  }
  onActiveIdChanged: {
    // The daemon can switch devices from the CLI while the panel is open.
    // Keep the dropdown from claiming that an older device is still pending.
    if (root.activeId !== "") root.pendingId = root.activeId
    Qt.callLater(root.ensureTab)
  }

  Process {
    id: installProbe
    command: ["/bin/sh", "-c", "if ! test -x /usr/local/bin/omarchy-scrollmode; then echo missing; elif systemctl is-active --quiet omarchy-scrollmode; then echo active; else echo stopped; fi"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var value = String(text).trim()
        if (value === "missing" || value === "stopped" || value === "active")
          root.serviceState = value
      }
    }
  }

  Timer {
    interval: 5000
    repeat: true
    running: true
    onTriggered: {
      if (!installProbe.running) installProbe.running = true
    }
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    blockLoading: true
    onFileChanged: reload()
  }

  FileView {
    id: statusFile
    path: root.statusPath
    watchChanges: true
    printErrors: false
    blockLoading: true
    onFileChanged: reload()
  }

  FileView {
    id: configFile
    path: root.cfgPath
    watchChanges: true
    printErrors: false
    blockLoading: true
    onFileChanged: reload()
  }

  FileView {
    id: statsFile
    path: "/var/lib/omarchy-scrollmode/stats.json"
    watchChanges: true
    printErrors: false
    blockLoading: true
    onFileChanged: reload()
  }

  // The daemon writes these files in place, but a service restart recreates
  // /run/omarchy-scrollmode and the inotify watch dies with the old inode.
  // A cheap periodic reload keeps the widget in sync regardless. The first
  // tick also covers a cold start where the files do not exist yet.
  Timer {
    interval: 1500
    repeat: true
    running: true
    onTriggered: {
      stateFile.reload()
      statusFile.reload()
      configFile.reload()
      statsFile.reload()
    }
  }

  Ui.BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: root.ballIcon
    tooltipText: (root.serviceState !== "active"
      ? (root.serviceState === "missing" ? strings.t("tip.uninstalled") : strings.t("tip.stopped"))
      : !root.present
      ? strings.t("tip.none")
      : root.sniper
        ? strings.t("tip.sniper")
        : root.scrolling
          ? strings.t("tip.scroll")
          : strings.t("tip.pointer")) + root.batteryTooltip
    Accessible.role: Accessible.Button
    Accessible.name: root.activeName !== "" ? root.activeName : "Trackball"
    onPressed: function(button) {
      if (button === Qt.LeftButton) root.toggle()
    }
  }

  Ui.KeyboardPanel {
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.opened
    focusTarget: keys
    contentWidth: fittedContentWidth(Style.space(340))
    contentHeight: fittedContentHeight(Math.max(keys.implicitHeight, Style.space(120)), Style.space(1030))

    Ui.PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      implicitHeight: Math.min(bodyContent.height + footerArea.height + Style.space(8),
        Style.space(900))
      blocked: devicePicker.popupOpen
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.adjustCursor(dx)
        else if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTextKey: function(t, modifiers) {
        if (t === "r" || t === "R") root.rescan()
        else if (t >= "1" && t <= "4") root.selectTab(Number(t))
      }

      Column {
        id: panelShell
        anchors.fill: parent
        spacing: 0

        Flickable {
          id: bodyFlick
          width: parent.width
          height: Math.max(0, panelShell.height - footerArea.height)
          contentWidth: width
          contentHeight: bodyContent.height
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height

          Item {
            id: bodyContent
            width: bodyFlick.width
            height: menu.implicitHeight + Style.space(8) + Style.space(10)

      Column {
        id: menu
        x: Style.space(10)
        y: Style.space(8)
        width: parent.width - Style.space(20)
        spacing: Style.space(10)

        // -- header ------------------------------------------------------
        Item {
          width: parent.width
          height: Math.max(headerBall.height, headerText.implicitHeight)

          DeviceIcon {
            id: headerBall
            size: Style.space(44)
            color: root.ballColor
            kind: root.deviceKind
            opened: root.opened
            shadow: true
          }

          MouseArea {
            anchors.fill: headerBall
            cursorShape: Qt.PointingHandCursor
            onClicked: headerBall.kick()
          }

          Column {
            id: headerText
            anchors.left: headerBall.right
            anchors.leftMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width - headerBall.width - Style.space(12))
            spacing: Style.space(2)

            Row {
              id: titleRow
              width: parent.width
              spacing: Style.space(8)

              Text {
                id: titleText
                width: Math.min(implicitWidth, Math.max(0,
                  titleRow.width
                    - (modeBadge.visible ? modeBadge.width + titleRow.spacing : 0)
                    - (batteryBadge.visible ? batteryBadge.width + titleRow.spacing : 0)))
                text: root.deviceTitle
                textFormat: Text.PlainText
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.title
                elide: Text.ElideRight
              }

              Rectangle {
                id: modeBadge

                anchors.verticalCenter: titleText.verticalCenter
                implicitWidth: badgeRow.implicitWidth + Style.space(10)
                implicitHeight: badgeRow.implicitHeight + Style.space(3)
                radius: Style.space(4)
                color: Qt.rgba(root.ballColor.r, root.ballColor.g, root.ballColor.b, 0.15)
                border.width: 1
                border.color: Qt.rgba(root.ballColor.r, root.ballColor.g, root.ballColor.b, 0.6)

                Row {
                  id: badgeRow
                  anchors.centerIn: parent
                  spacing: Style.space(3)

                  Text {
                    text: !root.hasDevice
                      ? "\uf127"
                      : (root.sniper ? "\uf05b" : (root.scrolling ? "\uf07d" : "\uf245"))
                    textFormat: Text.PlainText
                    color: root.ballColor
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    text: root.modeLabel
                    textFormat: Text.PlainText
                    color: root.ballColor
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              Rectangle {
                id: batteryBadge

                visible: root.batteryAvailable
                width: visible ? implicitWidth : 0
                anchors.verticalCenter: titleText.verticalCenter
                implicitWidth: batteryBadgeRow.implicitWidth + Style.space(10)
                implicitHeight: batteryBadgeRow.implicitHeight + Style.space(3)
                radius: Style.space(4)
                color: Qt.rgba(root.batteryColor.r, root.batteryColor.g,
                  root.batteryColor.b, 0.15)
                border.width: 1
                border.color: Qt.rgba(root.batteryColor.r, root.batteryColor.g,
                  root.batteryColor.b, 0.6)
                opacity: root.batteryStale ? 0.7 : 1

                Row {
                  id: batteryBadgeRow
                  anchors.centerIn: parent
                  spacing: Style.space(3)

                  Text {
                    text: root.batteryIcon
                    textFormat: Text.PlainText
                    color: root.batteryColor
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    text: root.batteryPercentText
                    textFormat: Text.PlainText
                    color: root.batteryColor
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }

            Text {
              width: parent.width
              text: root.activeName !== "" ? root.activeName : strings.t("menu.notConnected")
              textFormat: Text.PlainText
              color: Color.popups.text
              opacity: 0.5
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }

        // -- background service missing ---------------------------------
        Column {
          visible: root.serviceState !== "active"
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width
            text: root.serviceState === "missing" ? strings.t("setup.title") : strings.t("setup.stoppedTitle")
            textFormat: Text.PlainText
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            text: root.serviceState === "missing" ? strings.t("setup.body") : strings.t("setup.stoppedBody")
            textFormat: Text.PlainText
            color: Color.popups.text
            opacity: 0.6
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Ui.Button {
            width: parent.width
            text: root.serviceState === "missing" ? strings.t("setup.install") : strings.t("setup.start")
            bordered: true
            foreground: Color.popups.text
            onClicked: root.installService()
          }
        }

        // -- device picker ----------------------------------------------
        Column {
          visible: root.serviceState === "active" && !root.noDevices
          width: parent.width
          spacing: Style.space(4)

          Item {
            width: parent.width
            height: Math.max(deviceLabelText.implicitHeight, hiddenLabel.implicitHeight)

            Text {
              id: deviceLabelText
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: strings.t("menu.device")
              textFormat: Text.PlainText
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            Text {
              id: hiddenLabel
              visible: root.hiddenCount > 0
              anchors.left: deviceLabelText.right
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: "\u00b7 " + strings.t("menu.hidden").arg(root.hiddenCount)
              textFormat: Text.PlainText
              color: Color.popups.text
              opacity: 0.5
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          Ui.Dropdown {
            id: devicePicker
            width: parent.width
            height: Style.spacing.controlHeight
            options: root.deviceOptions
            value: root.pendingId
            showLabel: false
            onChanged: function(value) { root.pendingId = value }
            onHovered: function(isHovered) { if (isHovered) root.setCursor("device") }
          }

          Row {
            width: parent.width
            spacing: Style.space(6)

            ActionButton {
              id: useButton
              width: parent.width - refreshButton.width - parent.spacing
              height: Style.spacing.controlHeight
              idleText: strings.t("menu.useDevice")
              onHovered: function(isHovered) { if (isHovered) root.setCursor("useDevice") }
              onActivated: {
                if (root.pendingId !== root.activeId) root.useDevice(root.pendingId)
              }
            }

            ActionButton {
              id: refreshButton
              width: height
              height: Style.spacing.controlHeight
              iconOnly: true
              idleIcon: "\uf021"
              tooltipText: strings.t("menu.refresh")
              onHovered: function(isHovered) { if (isHovered) root.setCursor("rescan") }
              onActivated: root.rescan()
            }
          }
        }

        Ui.PanelSeparator {
          width: parent.width
          visible: root.serviceState === "active" && !root.noDevices
        }

        // -- no devices at all ------------------------------------------
        Column {
          visible: root.serviceState === "active" && root.noDevices
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width
            text: strings.t("noDevice.title")
            textFormat: Text.PlainText
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            text: strings.t("noDevice.body")
            textFormat: Text.PlainText
            color: Color.popups.text
            opacity: 0.6
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          ActionButton {
            width: parent.width
            idleText: strings.t("menu.retry")
            onActivated: root.rescan()
          }
        }

        // -- picked device not applied yet -------------------------------
        Column {
          visible: root.serviceState === "active" && root.pendingMismatch
          width: parent.width
          spacing: Style.space(6)

          Text {
            width: parent.width
            text: strings.t("pending.title")
            textFormat: Text.PlainText
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            text: strings.t("pending.body")
            textFormat: Text.PlainText
            color: Color.popups.text
            opacity: 0.6
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        // -- settings ----------------------------------------------------
        Column {
          id: settings
          visible: root.settingsVisible
          width: parent.width
          spacing: Style.space(10)

          Row {
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: root.tabOptions

              delegate: Ui.Button {
                required property var modelData

                width: (parent.width - (root.tabOptions.length - 1) * parent.spacing)
                  / Math.max(1, root.tabOptions.length)
                height: Style.spacing.controlHeight
                text: modelData.label
                bordered: true
                selected: root.tab === modelData.index
                foreground: Color.popups.text
                onClicked: root.tab = modelData.index
              }
            }
          }

          Flickable {
            id: statsFlick
            visible: root.tab === 3 && root.deviceKind !== "mouse"
            width: parent.width
            height: Math.min(statsColumn.implicitHeight, Style.space(700))
            contentWidth: width
            contentHeight: statsColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            interactive: contentHeight > height

            Column {
              id: statsColumn
              width: parent.width
              spacing: Style.space(14)

              Text {
                visible: root.statCounts <= 0
                width: parent.width
                text: strings.t("stats.empty")
                textFormat: Text.PlainText
                color: Color.popups.text
                opacity: 0.65
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }

              Row {
                visible: root.statCounts > 0
                width: parent.width
                spacing: Style.space(8)

                Column {
                  width: (parent.width - 2 * parent.spacing) / 3
                  spacing: 0

                  Text {
                    width: parent.width
                    text: root.fmtNumber(root.statPeak, 0) + " /s"
                    textFormat: Text.PlainText
                    color: Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Math.round(Style.font.title * 1.35)
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width
                    text: strings.t("stats.topSpeed")
                    textFormat: Text.PlainText
                    color: Color.popups.text
                    opacity: 0.55
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width
                    text: strings.t("stats.rpm").arg(root.fmtNumber(root.statRpm, 0))
                    textFormat: Text.PlainText
                    color: Color.popups.text
                    opacity: 0.5
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                Column {
                  width: (parent.width - 2 * parent.spacing) / 3
                  spacing: 0

                  Text {
                    width: parent.width
                    text: root.fmtDistance(root.statKm)
                    textFormat: Text.PlainText
                    color: Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Math.round(Style.font.title * 1.35)
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width
                    text: strings.t("stats.distance")
                    textFormat: Text.PlainText
                    color: Color.popups.text
                    opacity: 0.55
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                Column {
                  width: (parent.width - 2 * parent.spacing) / 3
                  spacing: 0

                  Text {
                    width: parent.width
                    text: root.fmtNumber(root.statTurns, 1)
                    textFormat: Text.PlainText
                    color: Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Math.round(Style.font.title * 1.35)
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width
                    text: strings.t("stats.turns")
                    textFormat: Text.PlainText
                    color: Color.popups.text
                    opacity: 0.55
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }
              }

              Column {
                visible: root.statCounts > 0
                width: parent.width
                spacing: Style.space(6)

                StatHeader { text: strings.t("stats.sectionTotals") }
                StatPair {
                  label: strings.t("stats.notches")
                  value: root.fmtNumber(root.statNotches, 0)
                  label2: strings.t("stats.pages")
                  value2: root.fmtNumber(root.statNotches / 20, 0)
                }
                StatPair {
                  label: strings.t("stats.ballTime")
                  value: root.fmtDuration(root.statScrollMs)
                  label2: strings.t("stats.longestFlick")
                  value2: root.fmtNumber(root.statLongestFlick, 0) + " "
                    + strings.t("stats.msUnit")
                }
              }

              Column {
                visible: root.statCounts > 0
                width: parent.width
                spacing: Style.space(6)

                StatHeader { text: strings.t("stats.sectionFlicks") }
                StatPair {
                  label: strings.t("stats.flicks")
                  value: root.fmtNumber(root.statFlicks, 0)
                  label2: strings.t("stats.coasted")
                  value2: root.fmtNumber(root.statCoastPct, 0) + " %"
                }
                StatPair {
                  label: strings.t("stats.longestCoast")
                  value: root.fmtNumber(root.statLongestCoast, 1) + " "
                    + strings.t("stats.notchesUnit")
                  label2: strings.t("stats.mostly")
                  value2: root.statDirection
                }
              }

              Column {
                visible: root.statCounts > 0
                width: parent.width
                spacing: Style.space(6)

                StatHeader { text: strings.t("stats.sectionFun") }
                StatRow {
                  label: strings.t("stats.footballFields")
                  value: root.fmtMultiple(root.statKm * 1000 / 105)
                }
                StatRow {
                  label: strings.t("stats.marathons")
                  value: root.fmtMultiple(root.statKm / 42.195)
                }
                CosmicRow {
                  label: strings.t("stats.earth")
                  done: root.fmtDistance(root.statKm) + " of "
                    + root.fmtNumber(40075, 0) + " km"
                  progress: root.cosmicProgress(root.statTurns, 40075)
                }
                CosmicRow {
                  label: strings.t("stats.moon")
                  done: root.fmtDistance(root.statKm) + " of "
                    + root.fmtNumber(384400, 0) + " km"
                  progress: root.cosmicProgress(root.statTurns, 384400)
                }
                CosmicRow {
                  label: strings.t("stats.sun")
                  done: root.fmtDistance(root.statKm) + " of "
                    + root.fmtNumber(940000000, 0) + " km"
                  progress: root.cosmicProgress(root.statTurns, 940000000)
                }
              }

              Column {
                visible: root.statCounts > 0
                width: parent.width
                spacing: Style.space(6)

                StatHeader { text: strings.t("stats.sectionDays") }
                StatPair {
                  label: strings.t("stats.today")
                  value: root.fmtDistance(root.statTodayKm)
                  label2: strings.t("stats.activeDays")
                  value2: root.fmtNumber(root.statActiveDays, 0)
                }
                StatRow {
                  label: strings.t("stats.bestDay")
                  value: root.statBestLabel + " · " + root.fmtDistance(root.statBestKm)
                }
              }

              Text {
                visible: root.statCounts > 0
                width: parent.width
                text: strings.t("stats.note")
                textFormat: Text.PlainText
                color: Color.popups.text
                opacity: 0.4
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }
          }

          Flickable {
            id: mouseStatsFlick
            visible: root.tab === 3 && root.deviceKind === "mouse"
            width: parent.width
            height: Math.min(mouseStatsColumn.implicitHeight, Style.space(700))
            contentWidth: width
            contentHeight: mouseStatsColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            interactive: contentHeight > height

            Column {
              id: mouseStatsColumn
              width: parent.width
              spacing: Style.space(14)

              Text {
                visible: root.mouseEmpty
                width: parent.width
                text: strings.t("stats.mouseEmpty")
                textFormat: Text.PlainText
                color: Color.popups.text
                opacity: 0.65
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }

              Row {
                visible: !root.mouseEmpty
                width: parent.width
                spacing: Style.space(8)

                Column {
                  width: (parent.width - 2 * parent.spacing) / 3
                  spacing: 0

                  Text {
                    width: parent.width
                    text: root.fmtNumber(root.mousePeak, 0) + " /s"
                    textFormat: Text.PlainText
                    color: Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Math.round(Style.font.title * 1.35)
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width
                    text: strings.t("stats.topPointerSpeed")
                    textFormat: Text.PlainText
                    color: Color.popups.text
                    opacity: 0.55
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                Column {
                  width: (parent.width - 2 * parent.spacing) / 3
                  spacing: 0

                  Text {
                    width: parent.width
                    text: root.fmtNumber(root.mouseWheel, 0)
                    textFormat: Text.PlainText
                    color: Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Math.round(Style.font.title * 1.35)
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width
                    text: strings.t("stats.wheelNotches")
                    textFormat: Text.PlainText
                    color: Color.popups.text
                    opacity: 0.55
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                Column {
                  width: (parent.width - 2 * parent.spacing) / 3
                  spacing: 0

                  Text {
                    width: parent.width
                    text: root.fmtNumber(root.mouseClicks, 0)
                    textFormat: Text.PlainText
                    color: Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Math.round(Style.font.title * 1.35)
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width
                    text: strings.t("stats.clicks")
                    textFormat: Text.PlainText
                    color: Color.popups.text
                    opacity: 0.55
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }
              }

              Column {
                visible: !root.mouseEmpty
                width: parent.width
                spacing: Style.space(6)

                StatHeader { text: strings.t("stats.sectionTotals") }
                StatPair {
                  label: strings.t("stats.wheelNotches")
                  value: root.fmtNumber(root.mouseWheel, 0)
                  label2: strings.t("stats.pages")
                  value2: root.fmtNumber(root.mouseWheel / 20, 0)
                }
                StatPair {
                  label: strings.t("stats.activeTime")
                  value: root.fmtDuration(root.mouseActiveMs)
                  label2: strings.t("stats.movement")
                  value2: root.mouseMovementText
                }
                StatPair {
                  label: strings.t("stats.clicks")
                  value: root.fmtNumber(root.mouseClicks, 0)
                  label2: strings.t("stats.mostly")
                  value2: root.mouseDirection
                }
              }

              Column {
                visible: !root.mouseEmpty
                width: parent.width
                spacing: Style.space(6)

                StatHeader { text: strings.t("stats.sectionFun") }
                Text {
                  visible: !root.mouseHasDistance
                  width: parent.width
                  text: strings.t("stats.mouseNoDpi")
                  textFormat: Text.PlainText
                  color: Color.popups.text
                  opacity: 0.55
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
                Column {
                  visible: root.mouseHasDistance
                  width: parent.width
                  spacing: Style.space(6)

                  StatRow {
                    label: strings.t("stats.buses")
                    value: root.fmtMultiple(root.mouseKm * 1000 / 12)
                  }
                  StatRow {
                    label: strings.t("stats.footballFields")
                    value: root.fmtMultiple(root.mouseKm * 1000 / 105)
                  }
                  StatRow {
                    label: strings.t("stats.trackLaps")
                    value: root.fmtMultiple(root.mouseKm * 1000 / 400)
                  }
                  StatRow {
                    label: strings.t("stats.marathons")
                    value: root.fmtMultiple(root.mouseKm / 42.195)
                  }
                  CosmicRow {
                    label: strings.t("stats.earth")
                    done: root.fmtDistance(root.mouseKm) + " of "
                      + root.fmtNumber(40075, 0) + " km"
                    progress: root.cosmicProgressKm(root.mouseKm, 40075)
                  }
                  CosmicRow {
                    label: strings.t("stats.moon")
                    done: root.fmtDistance(root.mouseKm) + " of "
                      + root.fmtNumber(384400, 0) + " km"
                    progress: root.cosmicProgressKm(root.mouseKm, 384400)
                  }
                  CosmicRow {
                    label: strings.t("stats.sun")
                    done: root.fmtDistance(root.mouseKm) + " of "
                      + root.fmtNumber(940000000, 0) + " km"
                    progress: root.cosmicProgressKm(root.mouseKm, 940000000)
                  }
                }
              }

              Column {
                visible: !root.mouseEmpty
                width: parent.width
                spacing: Style.space(6)

                StatHeader { text: strings.t("stats.sectionDays") }
                StatPair {
                  label: strings.t("stats.today")
                  value: root.mouseDayText(root.mouseToday)
                  label2: strings.t("stats.activeDays")
                  value2: root.fmtNumber(root.mouseActiveDays, 0)
                }
                StatRow {
                  label: strings.t("stats.bestDay")
                  value: root.mouseBestLabel + " · " + root.mouseDayText(root.mouseDays[root.mouseBestKey] || ({}))
                }
              }

              Text {
                visible: !root.mouseEmpty
                width: parent.width
                text: strings.t("stats.mouseNote")
                textFormat: Text.PlainText
                color: Color.popups.text
                opacity: 0.4
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }
          }

          SliderRow {
            id: speedSlider
            helpId: "speedHelp"
            rowId: "speed"
            visible: root.scrollTabVisible
            label: strings.t("menu.speed")
            help: strings.t("help.speed")
            valueText: Math.round(sliderValue) + " %"
            from: 25
            to: 300
            step: 5
            tickCount: 14
            integer: true
            source: Number(root.value("scroll.counts_per_notch", 85))
            toSlider: function(cpn) {
              var percent = 100 * 85 / Math.max(1, cpn)
              return Math.max(25, Math.min(300, Math.round(percent / 5) * 5))
            }
            fromSlider: function(percent) {
              return Math.max(20, Math.min(400, Math.round(85 * 100 / percent)))
            }
            onCommit: function(v) { root.setValue("scroll.counts_per_notch", v) }
          }

          SliderRow {
            id: sniperSlider
            helpId: "sniperHelp"
            rowId: "sniper"
            visible: root.scrollTabVisible
            label: strings.t("menu.sniper")
            help: strings.t("help.sniperSpeed")
            valueText: Math.round(sliderValue) + " %"
            from: 5
            to: 100
            step: 5
            tickCount: 19
            integer: true
            source: Number(root.value("scroll.sniper_multiplier", 0.2))
            toSlider: function(value) { return Math.round(Number(value) * 100) }
            fromSlider: function(percent) { return percent / 100 }
            onCommit: function(v) { root.setValue("scroll.sniper_multiplier", Number(v).toFixed(2)) }
          }

          Ui.PanelSeparator {
            visible: root.scrollTabVisible
            width: parent.width
          }

          ToggleRow {
            id: invertVToggle
            rowId: "invertV"
            visible: root.scrollTabVisible
            label: strings.t("menu.invertVertical")
            checked: root.bool("scroll.invert_vertical")
            onClicked: root.setValue("scroll.invert_vertical", !root.bool("scroll.invert_vertical"))
          }

          ToggleRow {
            id: invertHToggle
            rowId: "invertH"
            visible: root.scrollTabVisible
            label: strings.t("menu.invertHorizontal")
            checked: root.bool("scroll.invert_horizontal")
            onClicked: root.setValue("scroll.invert_horizontal", !root.bool("scroll.invert_horizontal"))
          }

          ToggleRow {
            id: axisLockToggle
            helpId: "axisLockHelp"
            rowId: "axisLock"
            visible: root.scrollTabVisible
            label: strings.t("menu.axisLock")
            help: strings.t("help.axisLock")
            checked: root.bool("scroll.axis_lock")
            onClicked: root.setValue("scroll.axis_lock", !root.bool("scroll.axis_lock"))
          }

          ToggleRow {
            id: hiResToggle
            helpId: "hiResHelp"
            rowId: "hiRes"
            visible: root.scrollTabVisible
            label: strings.t("menu.hiRes")
            help: strings.t("help.smooth")
            checked: root.bool("scroll.hi_res")
            onClicked: root.setValue("scroll.hi_res", !root.bool("scroll.hi_res"))
          }

          ToggleRow {
            id: exitOnClickToggle
            helpId: "exitOnClickHelp"
            rowId: "exitOnClick"
            visible: root.scrollTabVisible
            label: strings.t("menu.exitOnClick")
            help: strings.t("help.exitOnClick")
            checked: root.bool("exit_on_click")
            onClicked: root.setValue("exit_on_click", !root.bool("exit_on_click"))
          }

          ToggleRow {
            id: inertiaToggle
            helpId: "inertiaHelp"
            rowId: "inertia"
            visible: root.feelTabVisible
            label: strings.t("menu.inertia")
            help: strings.t("help.inertia")
            checked: root.bool("scroll.inertia")
            onClicked: root.setValue("scroll.inertia", !root.bool("scroll.inertia"))
          }

          SliderRow {
            id: inertiaTriggerSlider
            helpId: "inertiaTriggerHelp"
            rowId: "inertiaTrigger"
            visible: root.feelTabVisible && root.bool("scroll.inertia")
            label: strings.t("menu.inertiaTrigger")
            help: strings.t("help.inertiaTrigger")
            valueText: strings.t("menu.perSecond").arg(Math.round(sliderValue))
            from: 4
            to: 30
            step: 1
            tickCount: 14
            integer: true
            source: Number(root.value("scroll.inertia_trigger", 12))
            onCommit: function(v) { root.setValue("scroll.inertia_trigger", v) }
          }

          SliderRow {
            id: inertiaCoastSlider
            helpId: "inertiaCoastHelp"
            rowId: "inertiaCoast"
            visible: root.feelTabVisible && root.bool("scroll.inertia")
            label: strings.t("menu.inertiaCoast")
            help: strings.t("help.inertiaCoast")
            valueText: Math.round(sliderValue) + " %"
            from: 50
            to: 200
            step: 10
            tickCount: 16
            integer: true
            source: Number(root.value("scroll.inertia_strength", 100))
            onCommit: function(v) { root.setValue("scroll.inertia_strength", v) }
          }

          Column {
            visible: root.tab === 2 && root.batteryAvailable
            width: parent.width
            spacing: Style.space(6)

            StatHeader { text: strings.t("menu.battery") }

            Item {
              width: parent.width
              height: Math.max(batteryLabel.implicitHeight, batteryValue.implicitHeight)

              Text {
                id: batteryLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: strings.t("menu.batteryLevel")
                textFormat: Text.PlainText
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }

              Text {
                id: batteryValue
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, parent.width - batteryLabel.width - Style.space(8))
                text: root.batteryAvailable
                  ? root.batteryPercentText
                    + (root.batteryStateLabel !== "" ? " · " + root.batteryStateLabel : "")
                    + (root.batteryStale ? " · " + strings.t("battery.stale") : "")
                  : strings.t("battery.notReported")
                textFormat: Text.PlainText
                color: root.batteryAvailable ? root.batteryColor : Color.popups.text
                opacity: root.batteryAvailable ? 1 : 0.55
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
              }
            }

            Rectangle {
              visible: root.batteryAvailable && root.batteryPercent >= 0
              width: parent.width
              height: Style.space(4)
              radius: height / 2
              color: Qt.rgba(Color.popups.text.r, Color.popups.text.g,
                Color.popups.text.b, 0.10)

              Rectangle {
                width: parent.width * Math.max(0, Math.min(100, root.batteryPercent)) / 100
                height: parent.height
                radius: height / 2
                color: root.batteryColor
                opacity: root.batteryStale ? 0.65 : 1
              }
            }

            ToggleRow {
              id: batteryShowToggle
            helpId: "batteryShowBarHelp"
              rowId: "batteryShowBar"
              visible: root.batteryAvailable
              label: strings.t("menu.batteryShowBar")
              help: strings.t("help.batteryShowBar")
              checked: root.batteryShowBar
              onClicked: root.setValue("battery.show_bar", !root.batteryShowBar)
            }

            SliderRow {
              id: batteryLowSlider
            helpId: "batteryLowHelp"
              rowId: "batteryLow"
              visible: root.batteryAvailable
              label: strings.t("menu.batteryLow")
              help: strings.t("help.batteryLow")
              valueText: Math.round(sliderValue) + " %"
              from: 5
              to: 50
              step: 5
              tickCount: 10
              integer: true
              source: root.batteryLowPercent
              onCommit: function(v) { root.setValue("battery.low_percent", v) }
            }

            Item {
              visible: root.batteryAvailable
              width: parent.width
              height: Math.max(pollLabel.implicitHeight, pollHint.height)

              Text {
                id: pollLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: strings.t("menu.batteryPoll")
                textFormat: Text.PlainText
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }

              HintIcon {
                id: pollHint
                anchors.left: pollLabel.right
                anchors.leftMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                text: strings.t("help.batteryPoll")
                rowId: "batteryPollHelp"
                hasCursor: root.rowHasCursor("batteryPollHelp")
              }
            }

            Row {
              id: batteryPollRow
              visible: root.batteryAvailable
              width: parent.width
              spacing: Style.space(4)

              HoverHandler {
                onHoveredChanged: if (hovered && !pollHint.containsMouse)
                  root.setCursor("batteryPoll")
              }

              Repeater {
                model: [
                  { value: "60", label: "1" },
                  { value: "300", label: "5" },
                  { value: "900", label: "15" },
                  { value: "1800", label: "30" }
                ]

                delegate: Ui.Button {
                  required property var modelData

                  width: (parent.width - 3 * parent.spacing) / 4
                  height: Style.spacing.controlHeight
                  text: strings.t("battery.minutes").arg(modelData.label)
                  bordered: true
                  selected: String(Number(root.value("battery.poll_seconds", 300)))
                    === modelData.value
                  foreground: Color.popups.text
                  onHovered: function(isHovered) { if (isHovered) root.setCursor("batteryPoll") }
                  onClicked: root.setValue("battery.poll_seconds", Number(modelData.value))
                }
              }
            }
          }

          Text {
            visible: root.tab === 2 && !root.supportsButtons
            width: parent.width
            text: strings.t("device.limited")
            textFormat: Text.PlainText
            color: Color.popups.text
            opacity: 0.55
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          StatHeader {
            visible: root.tab === 2 && root.supportsButtons
            text: strings.t("menu.buttons")
          }

          Column {
            visible: root.supportsButtons && root.sniperAvailable && root.tab === 2
            width: parent.width
            spacing: Style.space(6)

            ToggleRow {
              id: sniperClearToggle
            helpId: "sniperClearHelp"
              rowId: "sniperClear"
              visible: root.sniperCode > 0
              label: strings.t("menu.sniperButton")
              help: strings.t("help.sniperButton").arg(root.sniperButtonName)
              checked: root.sniperCode > 0
              onClicked: root.setValue("sniper_button", 0)
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              Ui.Button {
                id: sniperChooseButton
                width: parent.width - (sniperChooseHint.visible
                  ? sniperChooseHint.width + parent.spacing : 0)
                text: root.sniperDone
                  ? strings.t("menu.done")
                  : (root.sniperCode > 0
                    ? strings.t("menu.sniperChange").arg(root.sniperButtonName)
                    : strings.t("menu.sniperChoose"))
                iconText: root.sniperDone ? "\uf00c" : ""
                bordered: true
                foreground: root.sniperDone ? root.doneColor : Color.popups.text
                onHovered: function(isHovered) { if (isHovered) root.setCursor("sniperChoose") }
                onClicked: Quickshell.execDetached([root.cli, "learn"])
              }

              HintIcon {
                id: sniperChooseHint
                visible: root.sniperCode === 0
                anchors.verticalCenter: parent.verticalCenter
                text: strings.t("help.sniperChoose")
                rowId: "sniperChooseHelp"
                hasCursor: root.rowHasCursor("sniperChooseHelp")
              }
            }

            Text {
              visible: root.learning
              width: parent.width
              text: strings.t("menu.sniperLearning")
              textFormat: Text.PlainText
              color: Color.popups.text
              opacity: 0.7
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Text {
              visible: !root.learning && root.learnErrorText !== ""
              width: parent.width
              text: root.learnErrorText
              textFormat: Text.PlainText
              color: root.armedColor
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Ui.PanelSeparator {
            visible: root.feelTabVisible
            width: parent.width
          }

          SliderRow {
            id: holdSlider
            helpId: "holdThresholdHelp"
            rowId: "holdThreshold"
            visible: root.feelTabVisible
            label: strings.t("menu.holdThreshold")
            help: strings.t("help.hold")
            valueText: strings.t("menu.ms").arg(Math.round(sliderValue))
            from: 100
            to: 800
            step: 50
            tickCount: 14
            integer: true
            source: Number(root.value("hold_threshold_ms", 300))
            onCommit: function(v) { root.setValue("hold_threshold_ms", v) }
          }

          Column {
            id: autoExitRow
            visible: root.feelTabVisible
            width: parent.width
            spacing: Style.space(4)

            HoverHandler {
              onHoveredChanged: if (hovered && !autoExitHint.containsMouse)
                root.setCursor("autoExit")
            }

            Item {
              width: parent.width
              height: Math.max(autoExitLabel.implicitHeight, autoExitHint.height)

              Text {
                id: autoExitLabel
                anchors.verticalCenter: parent.verticalCenter
                text: strings.t("menu.autoExit")
                textFormat: Text.PlainText
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }

              HintIcon {
                id: autoExitHint
                anchors.left: autoExitLabel.right
                anchors.leftMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                text: strings.t("help.autoExit")
                rowId: "autoExitHelp"
                hasCursor: root.rowHasCursor("autoExitHelp")
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: [
                  { value: "0", label: strings.t("menu.off") },
                  { value: "15", label: "15" },
                  { value: "30", label: "30" },
                  { value: "60", label: "60" }
                ]

                delegate: Ui.Button {
                  id: autoExitChip
                  required property var modelData
                  property bool flash: false

                  width: (parent.width - 3 * parent.spacing) / 4
                  height: Style.spacing.controlHeight
                  text: autoExitChip.flash ? strings.t("menu.done") : autoExitChip.modelData.label
                  iconText: autoExitChip.flash ? "\uf00c" : ""
                  selected: String(Number(root.value("auto_exit_seconds", 0))) === autoExitChip.modelData.value
                  bordered: true
                  foreground: autoExitChip.flash ? root.doneColor : Color.popups.text
                  onHovered: function(isHovered) { if (isHovered) root.setCursor("autoExit") }

                  Timer {
                    interval: 1200
                    running: autoExitChip.flash
                    onTriggered: autoExitChip.flash = false
                  }

                  onClicked: {
                    root.setValue("auto_exit_seconds", Number(autoExitChip.modelData.value))
                    autoExitChip.flash = true
                  }
                }
              }
            }
          }

          Ui.PanelSeparator {
            visible: root.tab === 2 && root.supportsButtons
            width: parent.width
          }

          Column {
            visible: root.tab === 2 && root.supportsButtons
            width: parent.width
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: strings.t("menu.hotkeys")
              textFormat: Text.PlainText
              color: Color.popups.text
              opacity: 0.55
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: strings.t("menu.hotkeyScroll").arg(String(root.value("hotkey", "ALT + Z")))
              textFormat: Text.PlainText
              color: Color.popups.text
              opacity: 0.8
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: strings.t("menu.hotkeySniper").arg(String(root.value("sniper_hotkey", "ALT + S")))
              textFormat: Text.PlainText
              color: Color.popups.text
              opacity: 0.8
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          ActionButton {
            id: openConfigButton
            visible: root.tab === 2 && root.supportsButtons
            width: parent.width
            idleText: strings.t("menu.openConfig")
            onHovered: function(isHovered) { if (isHovered) root.setCursor("openConfig") }
            onActivated: Quickshell.execDetached(["omarchy-launch-editor", root.cfgPath])
          }

          Ui.Button {
            id: resetButton
            visible: root.tab === 2 && root.supportsButtons
            width: parent.width
            property bool done: false
            property bool armed: false
            text: done ? strings.t("menu.done") : (armed ? strings.t("menu.resetConfirm") : strings.t("menu.reset"))
            iconText: done ? "\uf00c" : ""
            bordered: true
            foreground: done ? root.doneColor : (armed ? root.armedColor : Color.popups.text)
            onHovered: function(isHovered) { if (isHovered) root.setCursor("reset") }
            onClicked: root.triggerReset()

            Timer {
              id: resetDoneTimer
              interval: 1200
              onTriggered: resetButton.done = false
            }

            Timer {
              id: resetArmedTimer
              interval: 3000
              onTriggered: resetButton.armed = false
            }
          }
        }
      }

      Ui.CursorSurface {
        id: cursorRing
        visible: root.cursorActive && target !== null && target.visible
        property Item target: root.cursorTarget(root.cursorId)
        x: target ? target.mapToItem(bodyContent, 0, 0).x + Style.space(2) : 0
        y: target ? target.mapToItem(bodyContent, 0, 0).y + Style.space(2) : 0
        width: target ? Math.max(0, target.width - Style.space(4)) : 0
        height: target ? Math.max(0, target.height - Style.space(4)) : 0
        z: 20
        hasCursor: true
        fill: "transparent"
        foreground: Color.popups.text
        accent: Color.accent
        radius: Style.cornerRadius
      }
          }
        }

        Item {
          id: footerArea
          width: parent.width
          height: footerColumn.implicitHeight + Style.space(8)

          Rectangle {
            anchors.fill: parent
            color: Color.popups.background
            opacity: 0.98
          }

          Column {
            id: footerColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(2)
            anchors.rightMargin: Style.space(2)
            anchors.top: parent.top
            anchors.topMargin: Style.space(8)
            spacing: Style.space(6)

            Ui.PanelSeparator {
              width: parent.width
            }

            Grid {
              id: footerGrid
              width: parent.width
              columns: 3
              columnSpacing: Style.space(4)
              rowSpacing: Style.space(2)

              Repeater {
                model: root.footerHints

                Text {
                  required property var modelData
                  width: (footerGrid.width - (footerGrid.columns - 1) * footerGrid.columnSpacing)
                    / footerGrid.columns
                  text: String(modelData).trim()
                  textFormat: Text.PlainText
                  color: Color.popups.text
                  opacity: 0.48
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                }
              }
            }
          }
        }
      }
    }
  }

  // Small circled question mark with a tooltip. The MouseArea only exists for
  // hover and to keep a click on the hint from toggling the row underneath.
  component HintIcon: Item {
    id: hint

    property string text: ""
    property string rowId: ""
    property bool hasCursor: false
    readonly property bool containsMouse: hintMouse.containsMouse

    width: Style.space(22)
    height: width
    implicitWidth: width
    implicitHeight: height
    visible: text !== ""
    z: 2

    Rectangle {
      width: Style.space(14)
      height: width
      anchors.centerIn: parent
      radius: width / 2
      color: "transparent"
      border.width: 1
      border.color: Color.popups.text
      opacity: (hintMouse.containsMouse || hint.hasCursor) ? 0.9 : 0.4
    }

    Text {
      anchors.centerIn: parent
      text: "?"
      textFormat: Text.PlainText
      color: Color.popups.text
      opacity: (hintMouse.containsMouse || hint.hasCursor) ? 0.98 : 0.45
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      id: hintMouse
      width: Style.space(14)
      height: width
      anchors.centerIn: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton
      cursorShape: Qt.WhatsThisCursor
      onClicked: {}
      onContainsMouseChanged: {
        if (containsMouse && hint.rowId !== "") root.setCursor(hint.rowId)
      }
    }

    Ui.PanelToolTip {
      visible: hintMouse.containsMouse || hint.hasCursor
      text: hint.text
      width: Style.space(240)
      delay: 250
    }
  }

  component StatHeader: Item {
    id: headerItem

    property string text: ""

    width: parent ? parent.width : 0
    implicitHeight: headerLabel.implicitHeight

    Text {
      id: headerLabel
      text: headerItem.text
      textFormat: Text.PlainText
      color: Color.popups.text
      opacity: 0.72
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      font.capitalization: Font.AllUppercase
      font.letterSpacing: 0.8
    }

    Rectangle {
      anchors.left: headerLabel.right
      anchors.leftMargin: Style.space(8)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      height: 1
      color: Color.popups.text
      opacity: 0.12
    }
  }

  component CosmicRow: Item {
    id: cosmic

    property string label: ""
    property string done: ""
    property string progress: ""

    width: parent ? parent.width : 0
    implicitHeight: titleRow.height + doneText.height + Style.space(2)

    Item {
      id: titleRow
      width: parent.width
      height: Math.max(cosmicLabel.implicitHeight, cosmicProgress.implicitHeight)

      Text {
        id: cosmicLabel
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width * 0.52
        text: cosmic.label
        textFormat: Text.PlainText
        color: Color.popups.text
        opacity: 0.75
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        id: cosmicProgress
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width * 0.46
        text: cosmic.progress
        textFormat: Text.PlainText
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
      }
    }

    Text {
      id: doneText
      anchors.top: titleRow.bottom
      width: parent.width
      text: cosmic.done
      textFormat: Text.PlainText
      color: Color.popups.text
      opacity: 0.5
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  component MiniStat: Column {
    id: miniStat

    property string label: ""
    property string value: ""

    spacing: 0

    Text {
      width: parent.width
      text: miniStat.value
      textFormat: Text.PlainText
      color: Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      text: miniStat.label
      textFormat: Text.PlainText
      color: Color.popups.text
      opacity: 0.55
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  component StatPair: Row {
    id: statPair

    property string label: ""
    property string value: ""
    property string label2: ""
    property string value2: ""

    width: parent ? parent.width : 0
    spacing: Style.space(8)

    MiniStat {
      id: first
      width: (statPair.width - statPair.spacing) / 2
      label: statPair.label
      value: statPair.value
    }

    MiniStat {
      id: second
      width: (statPair.width - statPair.spacing) / 2
      label: statPair.label2
      value: statPair.value2
    }
  }

  component StatRow: Item {
    id: statRow

    property string label: ""
    property string value: ""

    width: parent ? parent.width : 0
    implicitHeight: Math.max(statLabel.implicitHeight, statValue.implicitHeight)
      + Style.space(3)

    Text {
      id: statLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width * 0.44
      text: statRow.label
      textFormat: Text.PlainText
      color: Color.popups.text
      opacity: 0.7
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    Text {
      id: statValue
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width * 0.54
      text: statRow.value
      textFormat: Text.PlainText
      color: Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideRight
    }
  }

  // Green confirmation flashed after a control changes: an optional dot, a
  // check, and an optional "Done".
  component DoneMark: Row {
    id: doneMark

    property bool shown: false
    property bool withDot: true
    property bool withText: true

    visible: shown
    spacing: Style.space(4)

    Text {
      visible: doneMark.withDot
      text: "\u00b7"
      textFormat: Text.PlainText
      color: Color.popups.text
      opacity: 0.5
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Text {
      text: "\uf00c"
      textFormat: Text.PlainText
      color: root.doneColor
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Text {
      visible: doneMark.withText
      text: strings.t("menu.done")
      textFormat: Text.PlainText
      color: root.doneColor
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  // A button that flashes "Done" (green, with a check) after it runs. With
  // iconOnly it just swaps its glyph for the check, keeping its square size.
  component ActionButton: Ui.Button {
    id: actionButton

    property string idleText: ""
    property string idleIcon: ""
    property bool iconOnly: false
    property bool done: false

    signal activated()

    text: (actionButton.done && !actionButton.iconOnly) ? strings.t("menu.done") : actionButton.idleText
    iconText: actionButton.done ? "\uf00c" : actionButton.idleIcon
    bordered: true
    foreground: actionButton.done ? root.doneColor : Color.popups.text

    Timer {
      interval: 1200
      running: actionButton.done
      onTriggered: actionButton.done = false
    }

    onClicked: {
      if (actionButton.done) return
      actionButton.done = true
      actionButton.activated()
    }
  }

  // Compact labelled switch: the panel is a menu, so rows stay short.
  component ToggleRow: Item {
    id: toggleRow

    property string label: ""
    property string help: ""
    property bool checked: false
    property bool flash: false
    property string rowId: ""
    property string helpId: ""
    property Item helpIcon: hintIcon
    readonly property real inset: Style.space(6)

    signal clicked()

    HoverHandler {
      onHoveredChanged: if (hovered && !hintIcon.containsMouse && toggleRow.rowId !== "")
        root.setCursor(toggleRow.rowId)
    }

    width: parent ? parent.width : 0
    implicitHeight: Math.max(toggleLabel.implicitHeight, toggleSwitch.implicitHeight) + Style.space(12)

    Timer {
      interval: 1200
      running: toggleRow.flash
      onTriggered: toggleRow.flash = false
    }

    Text {
      id: toggleLabel
      anchors.left: parent.left
      anchors.leftMargin: toggleRow.inset
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, Math.max(0, toggleRow.width - toggleSwitch.width - toggleRow.inset * 2 - Style.space(8)
        - (toggleRow.flash ? toggleDone.width + Style.space(8) : 0)
        - (hintIcon.visible ? hintIcon.width + Style.space(6) : 0)))
      text: toggleRow.label
      textFormat: Text.PlainText
      color: Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    HintIcon {
      id: hintIcon
      anchors.left: toggleLabel.right
      anchors.leftMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      text: toggleRow.help
      rowId: toggleRow.helpId
      hasCursor: root.rowHasCursor(toggleRow.helpId)
    }

    DoneMark {
      id: toggleDone
      anchors.left: hintIcon.visible ? hintIcon.right : toggleLabel.right
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      shown: toggleRow.flash
    }

    Ui.ToggleSwitch {
      id: toggleSwitch
      anchors.right: parent.right
      anchors.rightMargin: toggleRow.inset
      anchors.verticalCenter: parent.verticalCenter
      checked: toggleRow.checked
      interactive: false
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        toggleRow.flash = true
        toggleRow.clicked()
      }
    }
  }

  // Label on the left, live value on the right, slider underneath.
  component SliderRow: Column {
    id: row

    property string label: ""
    property string hint: ""
    property string help: ""
    property string valueText: ""
    property real from: 0
    property real to: 1
    property real step: 1
    property int tickCount: 0
    property bool integer: true
    property real decimals: 0
    property real source: 0
    property var toSlider: null
    property var fromSlider: null
    property bool flash: false
    property string rowId: ""
    property string helpId: ""
    property Item helpIcon: hintIcon
    readonly property real inset: Style.space(6)

    signal commit(real configValue)

    HoverHandler {
      onHoveredChanged: if (hovered && !hintIcon.containsMouse && row.rowId !== "")
        root.setCursor(row.rowId)
    }

    Timer {
      interval: 1200
      running: row.flash
      onTriggered: row.flash = false
    }

    readonly property real sliderValue: toSlider ? Number(toSlider(source)) : source

    width: parent ? parent.width : 0
    spacing: Style.space(3)

    Item { width: 1; height: Style.space(6) }

    function snap(value) {
      var stepped = Math.round(value / step) * step
      var factor = Math.pow(10, decimals)
      stepped = Math.round(stepped * factor) / factor
      return Math.max(from, Math.min(to, stepped))
    }

    Item {
      x: row.inset
      width: row.width - row.inset * 2
      height: Math.max(labelText.implicitHeight, valueLabel.implicitHeight)

      Text {
        id: labelText
        width: Math.min(labelText.implicitWidth, Math.max(0,
          parent.width - valueLabel.implicitWidth - Style.space(8)
            - (hintIcon.visible ? hintIcon.width + Style.space(6) : 0)
            - (doneMark.visible ? doneMark.width + Style.space(8) : 0)))
        text: row.label
        textFormat: Text.PlainText
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      HintIcon {
        id: hintIcon
        anchors.left: labelText.right
        anchors.leftMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        text: row.help
        rowId: row.helpId
        hasCursor: root.rowHasCursor(row.helpId)
      }

      DoneMark {
        id: doneMark
        anchors.left: hintIcon.visible ? hintIcon.right : labelText.right
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        shown: row.flash
      }

      Text {
        id: valueLabel
        anchors.right: parent.right
        text: row.valueText
        textFormat: Text.PlainText
        color: Color.popups.text
        opacity: 0.8
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }

    Ui.PanelSlider {
      x: row.inset
      width: row.width - row.inset * 2
      bar: root.bar
      minimum: row.from
      maximum: row.to
      step: row.step
      tickCount: row.tickCount
      integer: row.integer
      value: row.sliderValue
      onReleased: function(v) {
        var stepped = row.snap(v)
        row.commit(row.fromSlider ? row.fromSlider(stepped) : stepped)
        row.flash = true
      }
    }

    Text {
      visible: row.hint !== ""
      x: row.inset
      width: row.width - row.inset * 2
      text: row.hint
      textFormat: Text.PlainText
      color: Color.popups.text
      opacity: 0.55
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Item { width: 1; height: Style.space(6) }
  }
}
