import QtQuick
import qs.Commons

// A drawn top-down mouse inspired by the Logitech Signature M650: a softly
// tapered shell, split buttons, a dark rubber wheel with a metal rim, and two
// side buttons. It glides gently while idle, settles on open, and clicks with
// small sound-wave arcs from the left button.
Item {
  id: mouse

  property real size: 16
  property color color: "#d95f5f"
  property bool opened: false
  property bool shadow: false

  property real openScale: 1
  property real openOffsetX: 0
  property real openOffsetY: 0
  property real openOpacity: 1
  property real wheelAngle: 0
  property real press: 0
  property real clickPulse: 1
  property real idlePhase: 0

  implicitWidth: size
  implicitHeight: size
  width: size
  height: size
  scale: openScale * (1 - press * 0.026)
  x: openOffsetX + Math.sin(idlePhase) * size * 0.060
  y: openOffsetY + press * 2.2 + Math.sin(idlePhase * 0.8) * size * 0.030
  rotation: opened && !Style.reduceMotion ? Math.sin(idlePhase * 0.65) * 1.6 : 0
  opacity: openOpacity
  transformOrigin: Item.Center

  onOpenedChanged: {
    if (opened && !Style.reduceMotion) {
      openAnim.restart()
      openWheel.restart()
      idleAnim.restart()
    } else {
      openAnim.stop()
      openWheel.stop()
      idleAnim.stop()
      pressAnim.stop()
      wheelKick.stop()
      clickWave.stop()
      openScale = 1
      openOffsetX = 0
      openOffsetY = 0
      openOpacity = 1
      wheelAngle = 0
      press = 0
      clickPulse = 1
      idlePhase = 0
    }
  }

  function kick() {
    if (Style.reduceMotion) return
    pressAnim.restart()
    wheelKick.from = mouse.wheelAngle
    wheelKick.to = mouse.wheelAngle + 540
    wheelKick.restart()
    clickWave.restart()
  }

  ParallelAnimation {
    id: openAnim
    running: false

    NumberAnimation {
      target: mouse
      property: "openScale"
      from: 0.88
      to: 1
      duration: 420
      easing.type: Easing.OutBack
      easing.overshoot: 1.5
    }
    NumberAnimation {
      target: mouse
      property: "openOffsetX"
      from: 3.5
      to: 0
      duration: 420
      easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: mouse
      property: "openOffsetY"
      from: 3.5
      to: 0
      duration: 400
      easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: mouse
      property: "openOpacity"
      from: 0.22
      to: 1
      duration: 260
      easing.type: Easing.OutCubic
    }
  }

  NumberAnimation {
    id: openWheel
    target: mouse
    property: "wheelAngle"
    from: 0
    to: 135
    duration: 430
    easing.type: Easing.OutCubic
  }

  NumberAnimation {
    id: idleAnim
    target: mouse
    property: "idlePhase"
    from: 0
    to: Math.PI * 2
    duration: 6000
    loops: Animation.Infinite
    running: false
  }

  SequentialAnimation {
    id: pressAnim
    running: false

    NumberAnimation {
      target: mouse
      property: "press"
      from: 0
      to: 1
      duration: 65
    }
    NumberAnimation {
      target: mouse
      property: "press"
      from: 1
      to: 0
      duration: 210
      easing.type: Easing.OutCubic
    }
  }

  NumberAnimation {
    id: wheelKick
    target: mouse
    property: "wheelAngle"
    duration: 680
    easing.type: Easing.OutCubic
  }

  NumberAnimation {
    id: clickWave
    target: mouse
    property: "clickPulse"
    from: 0
    to: 1
    duration: 650
    easing.type: Easing.OutCubic
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
      var half = w * 0.335
      var top = h * 0.035
      var bottom = h * 0.965
      var base = Qt.rgba(Color.popups.text.r, Color.popups.text.g,
        Color.popups.text.b, 0.92)

      if (mouse.shadow) {
        var shadow = ctx.createRadialGradient(
          cx + w * 0.035, bottom - h * 0.005, 0,
          cx + w * 0.035, bottom - h * 0.005, w * 0.44)
        shadow.addColorStop(0, "rgba(0,0,0,0.38)")
        shadow.addColorStop(0.55, "rgba(0,0,0,0.18)")
        shadow.addColorStop(1, "rgba(0,0,0,0)")
        ctx.fillStyle = shadow
        oval(cx + w * 0.035, bottom - h * 0.005, w * 0.46, h * 0.085)
        ctx.fill()
      }

      // Signature-style shell: broad shoulders, a gentle waist and a rounded
      // tail, rather than a plain ellipse.
      var shell = ctx.createLinearGradient(cx - half, top, cx + half, bottom)
      shell.addColorStop(0, Qt.lighter(base, 1.42))
      shell.addColorStop(0.32, Qt.lighter(base, 1.12))
      shell.addColorStop(0.64, base)
      shell.addColorStop(1, Qt.darker(base, 1.58))
      ctx.beginPath()
      ctx.moveTo(cx, top)
      ctx.bezierCurveTo(cx + half * 0.76, top,
        cx + half * 1.02, h * 0.17,
        cx + half * 0.98, h * 0.40)
      ctx.bezierCurveTo(cx + half * 0.95, h * 0.66,
        cx + half * 0.72, h * 0.88,
        cx + half * 0.38, bottom)
      ctx.bezierCurveTo(cx + half * 0.16, bottom + h * 0.012,
        cx - half * 0.16, bottom + h * 0.012,
        cx - half * 0.38, bottom)
      ctx.bezierCurveTo(cx - half * 0.72, h * 0.88,
        cx - half * 0.95, h * 0.66,
        cx - half * 0.98, h * 0.40)
      ctx.bezierCurveTo(cx - half * 1.02, h * 0.17,
        cx - half * 0.76, top,
        cx, top)
      ctx.closePath()
      ctx.fillStyle = shell
      ctx.fill()
      ctx.lineWidth = Math.max(1, w * 0.016)
      ctx.strokeStyle = Qt.darker(base, 2.1)
      ctx.globalAlpha = 0.48
      ctx.stroke()
      ctx.globalAlpha = 1

      // Two click panels: a centre seam and a shallow curved split.
      ctx.beginPath()
      ctx.moveTo(cx, top + h * 0.012)
      ctx.lineTo(cx, h * 0.385)
      ctx.strokeStyle = Qt.darker(base, 1.65)
      ctx.lineWidth = Math.max(1, w * 0.012)
      ctx.globalAlpha = 0.52
      ctx.stroke()
      ctx.beginPath()
      ctx.moveTo(cx - half * 0.86, h * 0.185)
      ctx.quadraticCurveTo(cx, h * 0.31, cx + half * 0.86, h * 0.185)
      ctx.stroke()
      ctx.globalAlpha = 1

      // Side buttons on the left edge.
      for (var i = 0; i < 2; i++) {
        var sy = h * (0.47 + i * 0.105)
        oval(cx - half * 0.92, sy, w * 0.050, h * 0.043)
        ctx.fillStyle = Qt.rgba(mouse.color.r, mouse.color.g, mouse.color.b, 0.28)
        ctx.fill()
        ctx.strokeStyle = Qt.darker(base, 1.9)
        ctx.lineWidth = Math.max(1, w * 0.011)
        ctx.globalAlpha = 0.65
        ctx.stroke()
        ctx.globalAlpha = 1
      }

      // Scroll wheel: a dark rubber capsule with a metal rim and moving ridges.
      var wheelW = w * 0.105
      var wheelH = h * 0.205
      var wheelX = cx - wheelW / 2
      var wheelY = h * 0.115
      var wheelR = wheelW / 2
      ctx.beginPath()
      ctx.moveTo(wheelX + wheelR, wheelY)
      ctx.lineTo(wheelX + wheelW - wheelR, wheelY)
      ctx.quadraticCurveTo(wheelX + wheelW, wheelY,
        wheelX + wheelW, wheelY + wheelR)
      ctx.lineTo(wheelX + wheelW, wheelY + wheelH - wheelR)
      ctx.quadraticCurveTo(wheelX + wheelW, wheelY + wheelH,
        wheelX + wheelW - wheelR, wheelY + wheelH)
      ctx.lineTo(wheelX + wheelR, wheelY + wheelH)
      ctx.quadraticCurveTo(wheelX, wheelY + wheelH,
        wheelX, wheelY + wheelH - wheelR)
      ctx.lineTo(wheelX, wheelY + wheelR)
      ctx.quadraticCurveTo(wheelX, wheelY,
        wheelX + wheelR, wheelY)
      ctx.closePath()
      ctx.fillStyle = "rgba(24,25,27,0.96)"
      ctx.fill()
      ctx.lineWidth = Math.max(1, w * 0.014)
      ctx.strokeStyle = Qt.lighter(base, 1.25)
      ctx.globalAlpha = 0.62
      ctx.stroke()
      ctx.globalAlpha = 1

      ctx.save()
      ctx.beginPath()
      ctx.rect(wheelX + 1, wheelY + 2, wheelW - 2, wheelH - 4)
      ctx.clip()
      var gap = wheelH / 5
      var ridge = (mouse.wheelAngle / 360) * gap
      for (var r = -1; r < 7; r++) {
        var ry = wheelY + r * gap + ridge
        if (ry < wheelY + 1 || ry > wheelY + wheelH - 1) continue
        ctx.beginPath()
        ctx.moveTo(wheelX + 1, ry)
        ctx.lineTo(wheelX + wheelW - 1, ry)
        ctx.strokeStyle = "rgba(220,220,220,0.30)"
        ctx.lineWidth = Math.max(0.6, h * 0.012)
        ctx.stroke()
      }
      ctx.restore()

      // A small mode-coloured ring at the base of the wheel.
      ctx.beginPath()
      ctx.arc(cx, wheelY + wheelH + h * 0.018, w * 0.018, 0, Math.PI * 2)
      ctx.fillStyle = Qt.rgba(mouse.color.r, mouse.color.g, mouse.color.b, 0.7)
      ctx.fill()

      // Quiet sensor dot at the tail.
      oval(cx, h * 0.82, w * 0.045, h * 0.018)
      ctx.fillStyle = Qt.rgba(mouse.color.r, mouse.color.g, mouse.color.b, 0.28)
      ctx.fill()

      // Top-left shell highlight.
      var highlight = ctx.createRadialGradient(
        cx - w * 0.14, h * 0.16, 0,
        cx - w * 0.14, h * 0.16, w * 0.26)
      highlight.addColorStop(0, "rgba(255,255,255,0.24)")
      highlight.addColorStop(1, "rgba(255,255,255,0)")
      ctx.fillStyle = highlight
      ctx.fillRect(0, 0, w, h)
    }

    Connections {
      target: mouse
      function onWheelAngleChanged() { bodyCanvas.requestPaint() }
      function onClickPulseChanged() { bodyCanvas.requestPaint() }
      function onColorChanged() { bodyCanvas.requestPaint() }
      function onShadowChanged() { bodyCanvas.requestPaint() }
    }
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
  }

  // Sound waves get their own larger canvas so they can leave the mouse body
  // and remain visible beside the cursor.
  Canvas {
    id: clickCanvas
    property real margin: mouse.size * 0.22
    x: -margin
    y: -margin
    width: mouse.size + margin * 2
    height: width
    visible: !Style.reduceMotion && mouse.clickPulse < 1
    antialiasing: true
    z: 3

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var w = width
      var h = height
      var margin = width - mouse.size
      margin /= 2
      var cx = margin + mouse.size / 2
      var bx = cx - mouse.size * 0.335 * 0.40
      var by = margin + mouse.size * 0.265
      for (var k = 0; k < 3; k++) {
        var p = Math.min(1, mouse.clickPulse + k * 0.12)
        var radius = mouse.size * (0.10 + p * 0.42)
        ctx.beginPath()
        ctx.arc(bx, by, radius, -Math.PI * 0.75, Math.PI * 0.75)
        ctx.strokeStyle = Qt.rgba(mouse.color.r, mouse.color.g,
          mouse.color.b, (1 - p) * 0.55)
        ctx.lineWidth = Math.max(1, mouse.size * 0.032)
        ctx.stroke()
      }
    }

    Connections {
      target: mouse
      function onClickPulseChanged() { clickCanvas.requestPaint() }
      function onColorChanged() { clickCanvas.requestPaint() }
    }
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
  }
}
