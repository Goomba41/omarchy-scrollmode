import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui as Ui
import qs.Commons
import qs.Commons as Commons

// Scroll modes: pointer, scroll, sniper. Left click toggles pointer/scroll
// (double click: sniper). Right click opens the settings panel.
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

  function toggleScroll() {
    Quickshell.execDetached([root.cli, "toggle"])
  }

  function toggleSniper() {
    Quickshell.execDetached([root.cli, "sniper"])
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
    }
  }

  // A single left click acts after this delay, so a double click can win.
  Timer {
    id: clickDelay
    interval: 230
    onTriggered: root.toggleScroll()
  }

  Ui.BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.sniper ? "\uf05b" : (root.scrolling ? "\uf07d" : "\uf245")
    active: root.scrolling
    activeColor: root.sniper ? Color.urgent : Color.accent
    dimmed: !root.present
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
      if (button === Qt.RightButton) {
        root.toggle()
        return
      }
      if (button !== Qt.LeftButton) return
      if (root.opened) {
        root.close()
        return
      }
      if (clickDelay.running) {
        clickDelay.stop()
        root.toggleSniper()
      } else {
        clickDelay.start()
      }
    }
  }

  Ui.KeyboardPanel {
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.opened
    focusTarget: keys
    contentWidth: fittedContentWidth(Style.space(340))
    contentHeight: fittedContentHeight(Math.max(keys.implicitHeight, Style.space(120)), Style.space(900))

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
          height: Math.max(titleText.implicitHeight, deviceLabel.implicitHeight)

          Text {
            id: titleText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: strings.t("menu.title")
            textFormat: Text.PlainText
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.title
          }

          Text {
            id: deviceLabel
            anchors.left: titleText.right
            anchors.leftMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width - titleText.implicitWidth - Style.space(8))
            text: "· " + (root.activeName !== "" ? root.activeName : strings.t("menu.notConnected"))
            textFormat: Text.PlainText
            color: Color.popups.text
            opacity: 0.5
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
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
              opacity: 0.55
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
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

          SliderRow {
            label: strings.t("menu.speed")
            hint: strings.t("menu.speedHint")
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
            label: strings.t("menu.sniper")
            hint: strings.t("menu.sniperHint")
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

          Ui.PanelSeparator { width: parent.width }

          ToggleRow {
            label: strings.t("menu.invertVertical")
            checked: root.bool("scroll.invert_vertical")
            onClicked: root.setValue("scroll.invert_vertical", !root.bool("scroll.invert_vertical"))
          }

          ToggleRow {
            label: strings.t("menu.invertHorizontal")
            checked: root.bool("scroll.invert_horizontal")
            onClicked: root.setValue("scroll.invert_horizontal", !root.bool("scroll.invert_horizontal"))
          }

          ToggleRow {
            label: strings.t("menu.axisLock")
            checked: root.bool("scroll.axis_lock")
            onClicked: root.setValue("scroll.axis_lock", !root.bool("scroll.axis_lock"))
          }

          ToggleRow {
            label: strings.t("menu.hiRes")
            checked: root.bool("scroll.hi_res")
            onClicked: root.setValue("scroll.hi_res", !root.bool("scroll.hi_res"))
          }

          ToggleRow {
            label: strings.t("menu.exitOnClick")
            checked: root.bool("exit_on_click")
            onClicked: root.setValue("exit_on_click", !root.bool("exit_on_click"))
          }

          Ui.PanelSeparator { width: parent.width }

          SliderRow {
            label: strings.t("menu.holdThreshold")
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
            width: parent.width
            spacing: Style.space(4)

            Text {
              width: parent.width
              text: strings.t("menu.autoExit")
              textFormat: Text.PlainText
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
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

          Ui.PanelSeparator { width: parent.width }

          Column {
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
            width: parent.width
            idleText: strings.t("menu.openConfig")
            onActivated: Quickshell.execDetached(["omarchy-launch-editor", root.cfgPath])
          }

          Ui.Button {
            id: resetButton
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
        - (toggleRow.flash ? toggleDone.width + Style.space(8) : 0)))
      text: toggleRow.label
      textFormat: Text.PlainText
      color: Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    DoneMark {
      id: toggleDone
      anchors.left: toggleLabel.right
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

      DoneMark {
        anchors.left: labelText.right
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
