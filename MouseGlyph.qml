import QtQuick
import qs.Commons

// A drawn top-down mouse: neutral shell, split buttons, a mode-coloured wheel
// and side button. Opening produces a small settle and wheel turn; idle keeps
// a slow sensor glow. kick() presses the body and spins the wheel.
Item {
  id: mouse

  property real size: 16
  property color color: "#d95f5f"
  property bool opened: false
  property bool shadow: false

  property real openScale: 1
  property real openOffset: 0
  property real wheelAngle: 0
  property real glow: 0.18
  property real press: 0

  implicitWidth: size
  implicitHeight: size
  width: size
  height: size
  scale: openScale
  y: openOffset + press * 0.8
  transformOrigin: Item.Center

  onOpenedChanged: {
    if (opened && !Style.reduceMotion) {
      openAnim.restart()
      openWheel.restart()
      idleGlow.restart()
    } else {
      openAnim.stop()
      openWheel.stop()
      idleGlow.stop()
      openScale = 1
      openOffset = 0
      wheelAngle = 0
      glow = 0.18
    }
  }

  function kick() {
    if (Style.reduceMotion) return
    pressAnim.restart()
    wheelKick.from = mouse.wheelAngle
    wheelKick.to = mouse.wheelAngle + 360
    wheelKick.restart()
  }

  SequentialAnimation {
    id: openAnim
    running: false

    NumberAnimation {
      target: mouse
      property: "openScale"
      from: 1.06
      to: 1
      duration: 320
      easing.type: Easing.OutBack
    }
    NumberAnimation {
      target: mouse
      property: "openOffset"
      from: 1
      to: 0
      duration: 260
      easing.type: Easing.OutCubic
    }
  }

  NumberAnimation {
    id: openWheel
    target: mouse
    property: "wheelAngle"
    from: 0
    to: 90
    duration: 360
    easing.type: Easing.OutCubic
  }

  SequentialAnimation {
    id: pressAnim
    running: false

    NumberAnimation {
      target: mouse
      property: "press"
      from: 0
      to: 1
      duration: 70
    }
    NumberAnimation {
      target: mouse
      property: "press"
      from: 1
      to: 0
      duration: 180
      easing.type: Easing.OutCubic
    }
  }

  NumberAnimation {
    id: wheelKick
    target: mouse
    property: "wheelAngle"
    duration: 640
    easing.type: Easing.OutCubic
  }

  SequentialAnimation {
    id: idleGlow
    loops: Animation.Infinite
    running: false

    NumberAnimation {
      target: mouse
      property: "glow"
      from: 0.18
      to: 0.42
      duration: 1800
      easing.type: Easing.InOutSine
    }
    NumberAnimation {
      target: mouse
      property: "glow"
      from: 0.42
      to: 0.18
      duration: 1800
      easing.type: Easing.InOutSine
    }
  }

  Canvas {
    id: bodyCanvas
    anchors.fill: parent
    antialiasing: true

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      function oval(cx, cy, rx, ry) {
        ctx.save()
        ctx.translate(cx, cy)
        ctx.scale(Math.max(0.01, rx), Math.max(0.01, ry))
        ctx.beginPath()
        ctx.arc(0, 0, 1, 0, Math.PI * 2)
        ctx.restore()
      }
      var w = width
      var h = height
      if (w <= 0 || h <= 0) return
      var cx = w / 2
      var bodyWidth = w * 0.64
      var top = h * 0.035
      var bottom = h * 0.97
      var half = bodyWidth / 2
      var base = Qt.rgba(Color.popups.text.r, Color.popups.text.g,
        Color.popups.text.b, 0.90)

      if (mouse.shadow) {
        var shadow = ctx.createRadialGradient(
          cx + w * 0.035, bottom - h * 0.01, 0,
          cx + w * 0.035, bottom - h * 0.01, w * 0.40)
        shadow.addColorStop(0, "rgba(0,0,0,0.38)")
        shadow.addColorStop(0.55, "rgba(0,0,0,0.18)")
        shadow.addColorStop(1, "rgba(0,0,0,0)")
        ctx.fillStyle = shadow
        oval(cx + w * 0.035, bottom - h * 0.005, w * 0.42, h * 0.08)
        ctx.fill()
      }

      // Tapered shell: wide shoulders, narrower tail.
      var shell = ctx.createLinearGradient(cx - half, top, cx + half, bottom)
      shell.addColorStop(0, Qt.lighter(base, 1.55))
      shell.addColorStop(0.42, base)
      shell.addColorStop(1, Qt.darker(base, 1.65))
      ctx.beginPath()
      ctx.moveTo(cx, top)
      ctx.bezierCurveTo(cx + half * 0.92, top,
        cx + half, h * 0.30,
        cx + half * 0.86, h * 0.62)
      ctx.bezierCurveTo(cx + half * 0.74, h * 0.90,
        cx + half * 0.34, bottom,
        cx, bottom)
      ctx.bezierCurveTo(cx - half * 0.34, bottom,
        cx - half * 0.74, h * 0.90,
        cx - half * 0.86, h * 0.62)
      ctx.bezierCurveTo(cx - half, h * 0.30,
        cx - half * 0.92, top,
        cx, top)
      ctx.closePath()
      ctx.fillStyle = shell
      ctx.fill()
      ctx.lineWidth = Math.max(1, w * 0.018)
      ctx.strokeStyle = Qt.darker(base, 2.2)
      ctx.globalAlpha = 0.45
      ctx.stroke()
      ctx.globalAlpha = 1

      // Button seam and the horizontal button edge.
      ctx.beginPath()
      ctx.moveTo(cx, top + h * 0.015)
      ctx.lineTo(cx, h * 0.43)
      ctx.strokeStyle = Qt.darker(base, 1.8)
      ctx.lineWidth = Math.max(1, w * 0.015)
      ctx.globalAlpha = 0.5
      ctx.stroke()
      ctx.beginPath()
      ctx.moveTo(cx - half * 0.82, h * 0.205)
      ctx.lineTo(cx + half * 0.82, h * 0.205)
      ctx.stroke()
      ctx.globalAlpha = 1

      // Side button, tinted with the mode colour.
      oval(cx - half * 0.87, h * 0.51, w * 0.045, h * 0.075)
      ctx.fillStyle = Qt.rgba(mouse.color.r, mouse.color.g, mouse.color.b, 0.34)
      ctx.fill()
      ctx.strokeStyle = Qt.darker(base, 1.9)
      ctx.lineWidth = Math.max(1, w * 0.012)
      ctx.globalAlpha = 0.6
      ctx.stroke()
      ctx.globalAlpha = 1

      // Scroll wheel: a small mode-coloured disc with one moving notch.
      var wheelY = h * 0.275
      var wheelR = Math.max(1.2, w * 0.072)
      ctx.beginPath()
      ctx.arc(cx, wheelY, wheelR, 0, Math.PI * 2)
      ctx.fillStyle = Qt.rgba(mouse.color.r, mouse.color.g, mouse.color.b, 0.88)
      ctx.fill()
      ctx.strokeStyle = Qt.darker(base, 2.0)
      ctx.lineWidth = Math.max(1, w * 0.014)
      ctx.stroke()

      ctx.save()
      ctx.translate(cx, wheelY)
      ctx.rotate(mouse.wheelAngle * Math.PI / 180)
      ctx.beginPath()
      ctx.moveTo(0, -wheelR * 0.72)
      ctx.lineTo(0, wheelR * 0.28)
      ctx.strokeStyle = Qt.darker(mouse.color, 2.0)
      ctx.lineWidth = Math.max(1, w * 0.018)
      ctx.stroke()
      ctx.restore()

      // Soft sensor light at the tail; the only idle motion.
      var light = ctx.createRadialGradient(
        cx, h * 0.84, 0, cx, h * 0.84, w * 0.20)
      light.addColorStop(0, Qt.rgba(mouse.color.r, mouse.color.g,
        mouse.color.b, mouse.glow))
      light.addColorStop(1, Qt.rgba(mouse.color.r, mouse.color.g,
        mouse.color.b, 0))
      ctx.fillStyle = light
      oval(cx, h * 0.84, w * 0.18, h * 0.055)
      ctx.fill()

      // A quiet top-left highlight so the shell reads as a solid object.
      var highlight = ctx.createRadialGradient(
        cx - w * 0.12, h * 0.16, 0,
        cx - w * 0.12, h * 0.16, w * 0.24)
      highlight.addColorStop(0, "rgba(255,255,255,0.22)")
      highlight.addColorStop(1, "rgba(255,255,255,0)")
      ctx.fillStyle = highlight
      ctx.fillRect(0, 0, w, h)
    }

    Connections {
      target: mouse
      function onWheelAngleChanged() { bodyCanvas.requestPaint() }
      function onGlowChanged() { bodyCanvas.requestPaint() }
      function onColorChanged() { bodyCanvas.requestPaint() }
      function onShadowChanged() { bodyCanvas.requestPaint() }
    }
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
  }
}
