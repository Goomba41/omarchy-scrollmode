import QtQuick
import qs.Commons

// A drawn trackball: a shaded sphere with a highlight, fine surface marks and
// a texture that turns around the vertical axis, so marks slide across the ball
// and disappear behind it instead of spinning in the picture plane.
Item {
  id: ball

  property real size: 16
  property color ballColor: "#d95f5f"
  property bool spinning: false
  property bool shadow: false

  // Spin: a hard flick that eases to a very slow idle rotation (1 rev / 10 s).
  property real angle: 0
  property real elapsed: 0
  property real speed: 0
  readonly property real fastSpeed: 900   // deg/s, about 2.5 turns per second
  readonly property real slowSpeed: 36    // deg/s, one turn per ten seconds
  readonly property real rampSeconds: 1.2
  readonly property real kickSpeed: 1400  // deg/s, a deliberate finger flick
  readonly property real kickSeconds: 1.8
  readonly property real airThreshold: 260
  readonly property real airMargin: Math.max(3, size * 0.09)
  readonly property real airAmount: Math.max(0, Math.min(1,
    (speed - airThreshold) / (kickSpeed - airThreshold)))
  property bool kickActive: false
  property real kickElapsed: 0
  property bool airWasVisible: false

  // Deterministic surface texture. Each mark has a latitude (sine of it), a
  // longitude phase and a size; the delegate projects it onto the sphere for
  // the current angle and hides it on the far side.
  readonly property var specks: {
    var out = []
    var seed = 7
    function rnd() {
      seed = (seed * 16807) % 2147483647
      return seed / 2147483647
    }
    for (var i = 0; i < 22; i++) {
      var light = rnd() > 0.68
      out.push({
        lat: (rnd() * 2 - 1) * 0.76,
        phase: rnd() * 360,
        w: (light ? 0.06 : 0.03) + rnd() * (light ? 0.10 : 0.055),
        h: 0.008 + rnd() * 0.03,
        alpha: light ? 0.18 + rnd() * 0.14 : 0.16 + rnd() * 0.2,
        tilt: (rnd() * 2 - 1) * 60,
        light: light
      })
    }
    // One deeper dimple, the only mark that stayed from the first icon.
    out.push({ lat: 0.24, phase: 30, w: 0.105, h: 0.08, alpha: 0.3, tilt: 0, light: false })
    return out
  }

  implicitWidth: size
  implicitHeight: size
  width: size
  height: size

  onSpinningChanged: {
    if (spinning && !kickActive) {
      elapsed = 0
      speed = fastSpeed
    }
  }

  function kick() {
    if (Style.reduceMotion) return
    kickActive = true
    kickElapsed = 0
    if (!spinning) speed = slowSpeed
  }

  FrameAnimation {
    running: (ball.spinning || ball.kickActive) && !Style.reduceMotion
    onTriggered: {
      if (ball.kickActive) {
        ball.kickElapsed += frameTime
        if (ball.kickElapsed < 0.12) {
          var up = ball.kickElapsed / 0.12
          ball.speed = ball.slowSpeed + (ball.kickSpeed - ball.slowSpeed) * up
        } else {
          var down = Math.min(1, (ball.kickElapsed - 0.12) / ball.kickSeconds)
          ball.speed = ball.slowSpeed
            + (ball.kickSpeed - ball.slowSpeed) * Math.pow(1 - down, 2)
        }
        if (ball.kickElapsed >= 0.12 + ball.kickSeconds) {
          ball.kickActive = false
          ball.speed = ball.slowSpeed
        }
      } else {
        ball.elapsed += frameTime
        var ramp = Math.min(1, ball.elapsed / ball.rampSeconds)
        ball.speed = ball.slowSpeed
          + (ball.fastSpeed - ball.slowSpeed) * Math.pow(1 - ramp, 2)
      }
      ball.angle = (ball.angle + ball.speed * frameTime) % 360
      if (ball.airAmount > 0 || ball.airWasVisible) {
        ball.airWasVisible = ball.airAmount > 0
        airflow.requestPaint()
      }
    }
  }

  // Air streaks live outside the sphere, so this canvas is larger than the
  // ball. It is only painted while the ball is moving above the threshold.
  Canvas {
    id: airflow
    x: -ball.airMargin
    y: -ball.airMargin
    width: ball.size + ball.airMargin * 2
    height: width
    visible: !Style.reduceMotion && ball.airAmount > 0
    antialiasing: true
    z: 0

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var w = width
      var h = height
      var cx = w / 2
      var cy = h / 2
      var r = ball.size / 2 + ball.airMargin * 0.25
      var amount = ball.airAmount
      if (amount <= 0) return
      ctx.lineCap = "round"
      for (var i = 0; i < 5; i++) {
        var angle = (i * 72 + ball.angle * 0.32) * Math.PI / 180
        var span = (0.10 + amount * 0.22) * Math.PI
        ctx.beginPath()
        ctx.arc(cx, cy, r + (i % 2) * ball.airMargin * 0.25,
          angle, angle + span)
        ctx.strokeStyle = "rgba(255,255,255," + (0.08 + amount * 0.38) + ")"
        ctx.lineWidth = Math.max(1, ball.size * (0.025 + amount * 0.025))
        ctx.stroke()
      }
    }

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
  }

  Canvas {
    id: sphere
    anchors.fill: parent
    z: 1
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var w = width
      var h = height
      var r = Math.min(w, h) / 2
      var base = ball.ballColor

      // Soft cast shadow, offset down-right so a crescent stays visible.
      if (ball.shadow) {
        var shadowGradient = ctx.createRadialGradient(
          r * 1.05, r * 1.07, r * 0.1, r * 1.05, r * 1.07, r * 1.04)
        shadowGradient.addColorStop(0, "rgba(0,0,0,0.38)")
        shadowGradient.addColorStop(0.55, "rgba(0,0,0,0.2)")
        shadowGradient.addColorStop(1, "rgba(0,0,0,0)")
        ctx.beginPath()
        ctx.arc(r * 1.05, r * 1.07, r * 1.04, 0, Math.PI * 2)
        ctx.fillStyle = shadowGradient
        ctx.fill()
      }

      ctx.save()
      ctx.beginPath()
      ctx.arc(r, r, r, 0, Math.PI * 2)
      ctx.clip()

      // Body: light from the top left, a darker terminator at the bottom right.
      var body = ctx.createRadialGradient(
        r * 0.61, r * 0.52, r * 0.05, r * 0.9, r * 0.92, r * 1.2)
      body.addColorStop(0, Qt.lighter(base, 1.65))
      body.addColorStop(0.36, Qt.lighter(base, 1.2))
      body.addColorStop(0.68, base)
      body.addColorStop(0.88, Qt.darker(base, 1.55))
      body.addColorStop(1, Qt.darker(base, 2.25))
      ctx.fillStyle = body
      ctx.fillRect(0, 0, w, h)

      // Bounce light from the surface below, opposite the key light.
      var bounce = ctx.createRadialGradient(
        r * 1.34, r * 1.4, r * 0.02, r * 1.34, r * 1.4, r * 0.72)
      bounce.addColorStop(0, "rgba(255,255,255,0.16)")
      bounce.addColorStop(0.5, "rgba(255,255,255,0.05)")
      bounce.addColorStop(1, "rgba(255,255,255,0)")
      ctx.fillStyle = bounce
      ctx.fillRect(0, 0, w, h)

      // Highlight: a wide base glow, a softer white core, a small sharp spot.
      var glow = ctx.createRadialGradient(
        r * 0.62, r * 0.54, 0, r * 0.62, r * 0.54, r * 0.42)
      glow.addColorStop(0, "rgba(255,255,255,0.30)")
      glow.addColorStop(0.45, "rgba(255,255,255,0.10)")
      glow.addColorStop(1, "rgba(255,255,255,0)")
      ctx.fillStyle = glow
      ctx.fillRect(0, 0, w, h)

      var core = ctx.createRadialGradient(
        r * 0.66, r * 0.58, 0, r * 0.66, r * 0.58, r * 0.16)
      core.addColorStop(0, "rgba(255,255,255,0.42)")
      core.addColorStop(0.6, "rgba(255,255,255,0.14)")
      core.addColorStop(1, "rgba(255,255,255,0)")
      ctx.fillStyle = core
      ctx.fillRect(0, 0, w, h)

      var spot = ctx.createRadialGradient(
        r * 0.7, r * 0.62, 0, r * 0.7, r * 0.62, r * 0.055)
      spot.addColorStop(0, "rgba(255,255,255,0.95)")
      spot.addColorStop(0.55, "rgba(255,255,255,0.4)")
      spot.addColorStop(1, "rgba(255,255,255,0)")
      ctx.fillStyle = spot
      ctx.fillRect(0, 0, w, h)

      ctx.restore()

      // Thin rim, softer than a cartoon outline.
      ctx.beginPath()
      ctx.arc(r, r, r - 0.5, 0, Math.PI * 2)
      ctx.lineWidth = Math.max(1, w * 0.025)
      ctx.strokeStyle = Qt.darker(base, 2.3)
      ctx.globalAlpha = 0.4
      ctx.stroke()
    }
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    Connections {
      target: ball
      function onBallColorChanged() { sphere.requestPaint() }
      function onShadowChanged() { sphere.requestPaint() }
    }
  }

  // Surface marks. They move on a sphere: x follows sin(longitude), the width
  // squashes by cos(longitude), and the far half is hidden behind the ball.
  Item {
    anchors.fill: parent
    z: 2

    Repeater {
      model: ball.specks

      delegate: Rectangle {
        id: mark
        required property var modelData

        readonly property real radians: (modelData.phase + ball.angle) * Math.PI / 180
        readonly property real cosLongitude: Math.cos(radians)
        readonly property real latitude: Math.asin(modelData.lat)

        visible: cosLongitude > 0.035
        width: Math.max(0.8, ball.size * modelData.w * Math.max(0.12, cosLongitude))
        height: Math.max(0.8, ball.size * modelData.h)
        radius: Math.min(width, height) / 2
        x: ball.size / 2
          + ball.size / 2 * Math.cos(latitude) * Math.sin(radians) - width / 2
        y: ball.size / 2 - ball.size / 2 * modelData.lat - height / 2
        color: modelData.light ? Qt.lighter(ball.ballColor, 1.55)
                               : Qt.darker(ball.ballColor, 2.35)
        opacity: modelData.alpha * Math.min(1, cosLongitude * 1.7)
        rotation: modelData.tilt
      }
    }
  }
}
