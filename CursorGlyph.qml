import QtQuick
import qs.Commons

// A cursor-arrow glyph for mouse devices. The arrow is a solid 3D badge that
// turns around its vertical axis: slow while idle, fast with air streaks on a
// click. Opening glides in and starts the idle turn.
Item {
  id: cursor

  property real size: 16
  property color color: "#d95f5f"
  property bool opened: false
  property bool shadow: false

  property real angle: 0
  property real speed: 0
  property real openScale: 1
  property real openOffsetX: 0
  property real openOffsetY: 0
  property real openOpacity: 1
  property bool kickActive: false
  property real kickElapsed: 0
  property bool airWasVisible: false

  readonly property real slowSpeed: 28      // deg/s, one calm turn every ~13 s
  readonly property real kickSpeed: 900     // deg/s, deliberate flick
  readonly property real kickSeconds: 1.8
  readonly property real airThreshold: 220
  readonly property real airMargin: Math.max(3, size * 0.10)
  readonly property real airAmount: Math.max(0, Math.min(1,
    (speed - airThreshold) / (kickSpeed - airThreshold)))

  implicitWidth: size
  implicitHeight: size
  width: size
  height: size
  scale: openScale
  x: openOffsetX
  y: openOffsetY
  opacity: openOpacity
  transformOrigin: Item.Center

  onOpenedChanged: {
    if (opened && !Style.reduceMotion) {
      angle = 0
      speed = slowSpeed
      kickActive = false
      kickElapsed = 0
      openAnim.restart()
    } else {
      openAnim.stop()
      kickActive = false
      speed = 0
      openScale = 1
      openOffsetX = 0
      openOffsetY = 0
      openOpacity = 1
      airWasVisible = false
      airflow.requestPaint()
    }
  }

  function kick() {
    if (!opened || Style.reduceMotion) return
    kickActive = true
    kickElapsed = 0
  }

  ParallelAnimation {
    id: openAnim
    running: false

    NumberAnimation {
      target: cursor
      property: "openScale"
      from: 0.90
      to: 1
      duration: 380
      easing.type: Easing.OutBack
      easing.overshoot: 1.4
    }
    NumberAnimation {
      target: cursor
      property: "openOffsetX"
      from: 3
      to: 0
      duration: 380
      easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: cursor
      property: "openOffsetY"
      from: 3
      to: 0
      duration: 360
      easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: cursor
      property: "openOpacity"
      from: 0.2
      to: 1
      duration: 260
      easing.type: Easing.OutCubic
    }
  }

  FrameAnimation {
    running: (cursor.opened || cursor.kickActive) && !Style.reduceMotion
    onTriggered: {
      if (cursor.kickActive) {
        cursor.kickElapsed += frameTime
        if (cursor.kickElapsed < 0.12) {
          var up = cursor.kickElapsed / 0.12
          cursor.speed = cursor.slowSpeed
            + (cursor.kickSpeed - cursor.slowSpeed) * up
        } else {
          var down = Math.min(1, (cursor.kickElapsed - 0.12) / cursor.kickSeconds)
          cursor.speed = cursor.slowSpeed
            + (cursor.kickSpeed - cursor.slowSpeed) * Math.pow(1 - down, 2)
        }
        if (cursor.kickElapsed >= 0.12 + cursor.kickSeconds) {
          cursor.kickActive = false
          cursor.speed = cursor.slowSpeed
        }
      } else if (cursor.opened) {
        cursor.speed = cursor.slowSpeed
      }
      cursor.angle = (cursor.angle + cursor.speed * frameTime) % 360
      if (cursor.airAmount > 0 || cursor.airWasVisible) {
        cursor.airWasVisible = cursor.airAmount > 0
        airflow.requestPaint()
      }
    }
  }

  Canvas {
    id: arrowCanvas
    anchors.fill: parent
    z: 1
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
      var cy = h / 2

      // Classic cursor arrow, mapped into the icon with a little padding.
      var pts = [
        [5.0, 3.0], [20.0, 13.0], [12.2, 13.0], [16.0, 21.0],
        [12.8, 22.2], [9.0, 14.0], [5.0, 18.2]
      ]
      var scale = w * 0.80 / 19.2
      var ox = cx - 12.5 * scale
      var oy = cy - 12.6 * scale
      var rad = cursor.angle * Math.PI / 180
      var ca = Math.cos(rad)
      var sa = Math.sin(rad)
      var depth = Math.max(1.2, w * 0.070) * sa
      var front = []
      var back = []
      for (var i = 0; i < pts.length; i++) {
        var px = ox + pts[i][0] * scale
        var py = oy + pts[i][1] * scale
        var fx = cx + (px - cx) * ca
        front.push([fx, py])
        back.push([fx + depth, py])
      }

      if (cursor.shadow) {
        var shadow = ctx.createRadialGradient(
          cx + w * 0.06, h * 0.82, 0, cx + w * 0.06, h * 0.82, w * 0.40)
        shadow.addColorStop(0, "rgba(0,0,0,0.34)")
        shadow.addColorStop(1, "rgba(0,0,0,0)")
        ctx.fillStyle = shadow
        oval(cx + w * 0.06, h * 0.82, w * 0.38, h * 0.10)
        ctx.fill()
      }

      // Extruded side first, then the front face.
      var side = Qt.darker(cursor.color, 2.3)
      for (var e = 0; e < front.length; e++) {
        var n = (e + 1) % front.length
        ctx.beginPath()
        ctx.moveTo(front[e][0], front[e][1])
        ctx.lineTo(front[n][0], front[n][1])
        ctx.lineTo(back[n][0], back[n][1])
        ctx.lineTo(back[e][0], back[e][1])
        ctx.closePath()
        ctx.fillStyle = side
        ctx.globalAlpha = 0.9
        ctx.fill()
      }
      ctx.globalAlpha = 1

      var face = ctx.createLinearGradient(cx - w * 0.24, h * 0.18,
        cx + w * 0.22, h * 0.82)
      face.addColorStop(0, Qt.lighter(cursor.color, 1.35))
      face.addColorStop(0.45, cursor.color)
      face.addColorStop(1, Qt.darker(cursor.color, 1.36))
      ctx.beginPath()
      ctx.moveTo(front[0][0], front[0][1])
      for (var j = 1; j < front.length; j++)
        ctx.lineTo(front[j][0], front[j][1])
      ctx.closePath()
      ctx.fillStyle = face
      ctx.fill()
      ctx.lineWidth = Math.max(1, w * 0.018)
      ctx.strokeStyle = Qt.darker(cursor.color, 2.0)
      ctx.globalAlpha = 0.65
      ctx.stroke()
      ctx.globalAlpha = 1

      // A thin light edge keeps the arrow readable while it is nearly edge-on.
      if (Math.abs(ca) < 0.16) {
        ctx.beginPath()
        ctx.moveTo(cx - Math.abs(depth) * 0.5, h * 0.16)
        ctx.lineTo(cx + Math.abs(depth) * 0.5, h * 0.84)
        ctx.strokeStyle = "rgba(255,255,255,0.45)"
        ctx.lineWidth = Math.max(1, w * 0.016)
        ctx.stroke()
      }

      // Highlight on the front tip.
      if (ca > 0.1) {
        var hl = ctx.createRadialGradient(
          cx - w * 0.15, h * 0.26, 0,
          cx - w * 0.15, h * 0.26, w * 0.24)
        hl.addColorStop(0, "rgba(255,255,255,0.30)")
        hl.addColorStop(1, "rgba(255,255,255,0)")
        ctx.fillStyle = hl
        ctx.fillRect(0, 0, w, h)
      }
    }

    Connections {
      target: cursor
      function onAngleChanged() { arrowCanvas.requestPaint() }
      function onColorChanged() { arrowCanvas.requestPaint() }
      function onShadowChanged() { arrowCanvas.requestPaint() }
    }
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
  }

  // Horizontal air streams in front of the arrow while it is spinning fast.
  Canvas {
    id: airflow
    x: -cursor.airMargin
    y: -cursor.airMargin
    width: cursor.size + cursor.airMargin * 2
    height: width
    visible: !Style.reduceMotion && cursor.airAmount > 0
    z: 3
    antialiasing: true

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var w = width
      var h = height
      var amount = cursor.airAmount
      if (amount <= 0) return
      var phase = (cursor.angle * 0.16) % Math.max(4, cursor.size * 0.22)
      ctx.lineCap = "round"
      for (var i = 0; i < 3; i++) {
        var y = h * (0.53 + i * 0.10)
        var alpha = (0.10 + amount * 0.36) * (1 - i * 0.14)
        var start = -cursor.airMargin * 0.35 + (i % 2 ? -phase : phase)
        var end = w + cursor.airMargin * 0.35 - (i % 2 ? phase : -phase)
        var grad = ctx.createLinearGradient(start, y, end, y)
        grad.addColorStop(0, "rgba(255,255,255,0)")
        grad.addColorStop(0.14, "rgba(255,255,255," + alpha + ")")
        grad.addColorStop(0.65, "rgba(255,255,255," + alpha + ")")
        grad.addColorStop(1, "rgba(255,255,255,0)")
        ctx.beginPath()
        ctx.moveTo(start, y)
        ctx.quadraticCurveTo((start + end) / 2, y + (i % 2 ? -1 : 1) * h * 0.018,
          end, y)
        ctx.strokeStyle = grad
        ctx.lineWidth = Math.max(1, cursor.size * (0.017 + amount * 0.022))
        ctx.stroke()
      }
    }

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
  }
}
