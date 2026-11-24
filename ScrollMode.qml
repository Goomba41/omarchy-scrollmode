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
    TrackballBall {
      size: Style.bar.iconSize
      ballColor: root.ballColor
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
  readonly property real statCounts: Number(statsInfo.counts || 0)
  readonly property real statNotches: Number(statsInfo.notches || 0)
  readonly property int statFlicks: Number(statsInfo.flicks || 0)
  readonly property int statCoasted: Number(statsInfo.coasted || 0)
  readonly property real statScrollMs: Number(statsInfo.scroll_ms || 0)
  readonly property real statPeak: Number(statsInfo.max_peak_notches || 0)
  readonly property real statPeakCounts: Number(statsInfo.max_peak_counts || 0)
  readonly property real statLongestCoast: Number(statsInfo.max_coast_notches || 0)
  readonly property real statLongestFlick: Number(statsInfo.max_flick_ms || 0)
  readonly property var statDays: (statsInfo && statsInfo.days) ? statsInfo.days : ({})
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
    var up = Number(statsInfo.up || 0)
    var down = Number(statsInfo.down || 0)
    var left = Number(statsInfo.left || 0)
    var right = Number(statsInfo.right || 0)
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

  function statProgressPercent(turns, target) {
    var value = Number(turns)
    var goal = Number(target)
    if (!(value > 0) || !(goal > 0)) return "0 %"
    var percent = value / goal * 100
    var digits = percent >= 1 ? 2 : percent >= 0.01 ? 4
      : percent >= 0.0001 ? 6 : percent >= 0.000001 ? 8 : 10
    var text = percent.toFixed(digits)
    if (text.indexOf(".") >= 0) {
      text = text.replace(/0+$/, "").replace(/\.$/, "")
    }
    return text + " %"
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
    for (var i = 0; i < list.length; i++)
      options.push({ value: list[i].id, label: list[i].name })
    return options
  }

  property string pendingId: ""
  readonly property bool pendingMismatch: root.devices.length > 0
    && root.pendingId !== "" && root.pendingId !== root.activeId
  readonly property bool noDevices: root.devices.length === 0

  readonly property color doneColor: "#a7c080"
  readonly property color armedColor: "#dbbc7f"

  property int tab: 0
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
    installProbe.running = true
  }
  onStatusChanged: syncPending()

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
    tooltipText: root.serviceState !== "active"
      ? (root.serviceState === "missing" ? strings.t("tip.uninstalled") : strings.t("tip.stopped"))
      : !root.present
      ? strings.t("tip.none")
      : root.sniper
        ? strings.t("tip.sniper")
        : root.scrolling
          ? strings.t("tip.scroll")
          : strings.t("tip.pointer")
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
      implicitHeight: menu.implicitHeight
      onCloseRequested: root.close()

      Column {
        id: menu
        width: parent.width
        spacing: Style.space(10)

        // -- header ------------------------------------------------------
        Item {
          width: parent.width
          height: Math.max(headerBall.height, headerText.implicitHeight)

          TrackballBall {
            id: headerBall
            size: Style.space(44)
            ballColor: root.ballColor
            spinning: root.opened
            shadow: true
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
                width: Math.min(implicitWidth,
                  Math.max(0, titleRow.width - modeBadge.width - titleRow.spacing))
                text: strings.t("menu.title")
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
            width: parent.width
            height: Style.spacing.controlHeight
            options: root.deviceOptions
            value: root.pendingId
            showLabel: false
            onChanged: function(value) { root.pendingId = value }
          }

          Row {
            width: parent.width
            spacing: Style.space(6)

            ActionButton {
              id: useButton
              width: parent.width - refreshButton.width - parent.spacing
              height: Style.spacing.controlHeight
              idleText: strings.t("menu.useDevice")
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
          visible: root.serviceState === "active" && !root.noDevices && !root.pendingMismatch
          width: parent.width
          spacing: Style.space(10)

          Row {
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: [
                strings.t("tab.scroll"),
                strings.t("tab.feel"),
                strings.t("tab.device"),
                strings.t("tab.stats")
              ]

              delegate: Ui.Button {
                required property var modelData
                required property int index
                width: (parent.width - 3 * parent.spacing) / 4
                height: Style.spacing.controlHeight
                text: modelData
                bordered: true
                selected: root.tab === index
                foreground: Color.popups.text
                onClicked: root.tab = index
              }
            }
          }

          Flickable {
            id: statsFlick
            visible: root.tab === 3
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
                visible: root.statFlicks === 0
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
                visible: root.statFlicks > 0
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

              Ui.PanelSeparator {
                visible: root.statFlicks > 0
                width: parent.width
              }

              Column {
                visible: root.statFlicks > 0
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
                visible: root.statFlicks > 0
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
                visible: root.statFlicks > 0
                width: parent.width
                spacing: Style.space(6)

                StatHeader { text: strings.t("stats.sectionFun") }
                StatRow {
                  label: strings.t("stats.cars")
                  value: root.fmtMultiple(root.statKm * 1000 / 4.5)
                }
                StatRow {
                  label: strings.t("stats.footballFields")
                  value: root.fmtMultiple(root.statKm * 1000 / 105)
                }
                StatRow {
                  label: strings.t("stats.tenKRuns")
                  value: root.fmtMultiple(root.statKm / 10)
                }
                StatRow {
                  label: strings.t("stats.marathons")
                  value: root.fmtMultiple(root.statKm / 42.195)
                }
                CosmicRow {
                  label: strings.t("stats.earth")
                  done: root.fmtDistance(root.statKm) + " of "
                    + root.fmtNumber(40075, 0) + " km"
                  progress: root.statProgressPercent(root.statTurns, root.statTurnsFor(40075))
                }
                CosmicRow {
                  label: strings.t("stats.moon")
                  done: root.fmtDistance(root.statKm) + " of "
                    + root.fmtNumber(384400, 0) + " km"
                  progress: root.statProgressPercent(root.statTurns, root.statTurnsFor(384400))
                }
                CosmicRow {
                  label: strings.t("stats.sun")
                  done: root.fmtDistance(root.statKm) + " of "
                    + root.fmtNumber(940000000, 0) + " km"
                  progress: root.statProgressPercent(root.statTurns, root.statTurnsFor(940000000))
                }
              }

              Column {
                visible: root.statFlicks > 0
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
                visible: root.statFlicks > 0
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

          SliderRow {
            visible: root.tab === 0
            label: strings.t("menu.speed")
            hint: strings.t("menu.speedHint")
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
            visible: root.tab === 0
            label: strings.t("menu.sniper")
            hint: strings.t("menu.sniperHint")
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
            visible: root.tab === 0
            width: parent.width
          }

          ToggleRow {
            visible: root.tab === 0
            label: strings.t("menu.invertVertical")
            checked: root.bool("scroll.invert_vertical")
            onClicked: root.setValue("scroll.invert_vertical", !root.bool("scroll.invert_vertical"))
          }

          ToggleRow {
            visible: root.tab === 0
            label: strings.t("menu.invertHorizontal")
            checked: root.bool("scroll.invert_horizontal")
            onClicked: root.setValue("scroll.invert_horizontal", !root.bool("scroll.invert_horizontal"))
          }

          ToggleRow {
            visible: root.tab === 0
            label: strings.t("menu.axisLock")
            help: strings.t("help.axisLock")
            checked: root.bool("scroll.axis_lock")
            onClicked: root.setValue("scroll.axis_lock", !root.bool("scroll.axis_lock"))
          }

          ToggleRow {
            visible: root.tab === 0
            label: strings.t("menu.hiRes")
            help: strings.t("help.smooth")
            checked: root.bool("scroll.hi_res")
            onClicked: root.setValue("scroll.hi_res", !root.bool("scroll.hi_res"))
          }

          ToggleRow {
            visible: root.tab === 0
            label: strings.t("menu.exitOnClick")
            help: strings.t("help.exitOnClick")
            checked: root.bool("exit_on_click")
            onClicked: root.setValue("exit_on_click", !root.bool("exit_on_click"))
          }

          ToggleRow {
            visible: root.tab === 1
            label: strings.t("menu.inertia")
            help: strings.t("help.inertia")
            checked: root.bool("scroll.inertia")
            onClicked: root.setValue("scroll.inertia", !root.bool("scroll.inertia"))
          }

          SliderRow {
            visible: root.tab === 1 && root.bool("scroll.inertia")
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
            visible: root.tab === 1 && root.bool("scroll.inertia")
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
            visible: root.sniperAvailable && root.tab === 2
            width: parent.width
            spacing: Style.space(6)

            ToggleRow {
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
                onClicked: Quickshell.execDetached([root.cli, "learn"])
              }

              HintIcon {
                id: sniperChooseHint
                visible: root.sniperCode === 0
                anchors.verticalCenter: parent.verticalCenter
                text: strings.t("help.sniperChoose")
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
            visible: root.tab === 1
            width: parent.width
          }

          SliderRow {
            visible: root.tab === 1
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
            visible: root.tab === 1
            width: parent.width
            spacing: Style.space(4)

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
            visible: root.tab === 2
            width: parent.width
          }

          Column {
            visible: root.tab === 2
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
            visible: root.tab === 2
            width: parent.width
            idleText: strings.t("menu.openConfig")
            onActivated: Quickshell.execDetached(["omarchy-launch-editor", root.cfgPath])
          }

          Ui.Button {
            id: resetButton
            visible: root.tab === 2
            width: parent.width
            property bool done: false
            property bool armed: false
            text: done ? strings.t("menu.done") : (armed ? strings.t("menu.resetConfirm") : strings.t("menu.reset"))
            iconText: done ? "\uf00c" : ""
            bordered: true
            foreground: done ? root.doneColor : (armed ? root.armedColor : Color.popups.text)
            onClicked: {
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
    }
  }

  // Small circled question mark with a tooltip. The MouseArea only exists for
  // hover and to keep a click on the hint from toggling the row underneath.
  component HintIcon: Item {
    id: hint

    property string text: ""

    width: Style.space(14)
    height: width
    implicitWidth: width
    implicitHeight: height
    visible: text !== ""
    z: 2

    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: "transparent"
      border.width: 1
      border.color: Color.popups.text
      opacity: hintMouse.containsMouse ? 0.85 : 0.4
    }

    Text {
      anchors.centerIn: parent
      text: "?"
      textFormat: Text.PlainText
      color: Color.popups.text
      opacity: hintMouse.containsMouse ? 0.95 : 0.45
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      id: hintMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton
      cursorShape: Qt.WhatsThisCursor
      onClicked: {}
    }

    Ui.PanelToolTip {
      visible: hintMouse.containsMouse
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

    signal clicked()

    width: parent ? parent.width : 0
    implicitHeight: Math.max(toggleLabel.implicitHeight, toggleSwitch.implicitHeight) + Style.space(8)

    Timer {
      interval: 1200
      running: toggleRow.flash
      onTriggered: toggleRow.flash = false
    }

    Text {
      id: toggleLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, Math.max(0, toggleRow.width - toggleSwitch.width - Style.space(8)
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

    signal commit(real configValue)

    Timer {
      interval: 1200
      running: row.flash
      onTriggered: row.flash = false
    }

    readonly property real sliderValue: toSlider ? Number(toSlider(source)) : source

    width: parent ? parent.width : 0
    spacing: Style.space(3)

    function snap(value) {
      var stepped = Math.round(value / step) * step
      var factor = Math.pow(10, decimals)
      stepped = Math.round(stepped * factor) / factor
      return Math.max(from, Math.min(to, stepped))
    }

    Item {
      width: row.width
      height: Math.max(labelText.implicitHeight, valueLabel.implicitHeight)

      Text {
        id: labelText
        text: row.label
        textFormat: Text.PlainText
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      HintIcon {
        id: hintIcon
        anchors.left: labelText.right
        anchors.leftMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        text: row.help
      }

      DoneMark {
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
      width: row.width
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
      width: row.width
      text: row.hint
      textFormat: Text.PlainText
      color: Color.popups.text
      opacity: 0.55
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }
}
