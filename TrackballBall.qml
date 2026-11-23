import QtQuick
import qs.Commons

// A drawn trackball: sphere gradient, static specular highlight and a small
// pattern that rotates to show the ball spinning. No raster assets, so it stays
// crisp in the bar and in the settings header.
Item {
  id: ball

  property real size: 16
  property color ballColor: "#d95f5f"
  property bool spinning: false
  property bool dot: false
  property bool shadow: false

  // Spin: a hard flick that eases to a very slow idle rotation (1 rev / 10 s).
  property real angle: 0
  property real elapsed: 0
  property real speed: 0
  readonly property real fastSpeed: 900   // deg/s, about 2.5 turns per second
  readonly property real slowSpeed: 36    // deg/s, one turn per ten seconds
  readonly property real rampSeconds: 1.2

  implicitWidth: size
  implicitHeight: size
  width: size
  height: size

  onSpinningChanged: {
    if (spinning) {
      elapsed = 0
      speed = fastSpeed
    }
  }

  FrameAnimation {
    running: ball.spinning && !Style.reduceMotion
    onTriggered: {
      ball.elapsed += frameTime
      var ramp = Math.min(1, ball.elapsed / ball.rampSeconds)
      ball.speed = ball.slowSpeed + (ball.fastSpeed - ball.slowSpeed) * Math.pow(1 - ramp, 2)
      ball.angle = (ball.angle + ball.speed * frameTime) % 360
    }
  }

  // Soft ground shadow, only where there is room for it (the panel header).
  Rectangle {
    visible: ball.shadow
    width: ball.size * 0.92
    height: width
    radius: width / 2
    x: ball.size * 0.04
    y: ball.size * 0.08
    color: "#000000"
    opacity: 0.18
  }

  Canvas {
    id: sphere
    anchors.fill: parent
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var w = width
      var h = height
      var r = Math.min(w, h) / 2
      var gradient = ctx.createRadialGradient(r * 0.68, r * 0.58, r * 0.06, r, r, r * 1.02)
      gradient.addColorStop(0, Qt.lighter(ball.ballColor, 1.55))
      gradient.addColorStop(0.55, ball.ballColor)
      gradient.addColorStop(1, Qt.darker(ball.ballColor, 1.75))
      ctx.beginPath()
      ctx.arc(r, r, r - 0.5, 0, Math.PI * 2)
      ctx.fillStyle = gradient
      ctx.fill()
      ctx.lineWidth = Math.max(1, w * 0.02)
      ctx.strokeStyle = Qt.darker(ball.ballColor, 2.3)
      ctx.globalAlpha = 0.5
      ctx.stroke()
    }
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    Connections {
      target: ball
      function onBallColorChanged() { sphere.requestPaint() }
    }
  }

  // Three dimples grouped and rotated: the cue that the ball is spinning.
  Item {
    anchors.fill: parent
    rotation: ball.angle

    Rectangle {
      width: ball.size * 0.10; height: width; radius: width / 2
      x: ball.size * 0.60 - width / 2
      y: ball.size * 0.40 - height / 2
      color: Qt.darker(ball.ballColor, 2.4)
      opacity: 0.38
    }

    Rectangle {
      width: ball.size * 0.085; height: width; radius: width / 2
      x: ball.size * 0.40 - width / 2
      y: ball.size * 0.62 - height / 2
      color: Qt.darker(ball.ballColor, 2.4)
      opacity: 0.32
    }

    Rectangle {
      width: ball.size * 0.06; height: width; radius: width / 2
      x: ball.size * 0.30 - width / 2
      y: ball.size * 0.36 - height / 2
      color: Qt.darker(ball.ballColor, 2.4)
      opacity: 0.28
    }
  }

  // Static highlight: light comes from the top-left, so it must not rotate.
  Rectangle {
    width: ball.size * 0.34
    height: width * 0.58
    radius: width / 2
    x: ball.size * 0.16
    y: ball.size * 0.12
    color: "#ffffff"
    opacity: 0.26
  }

  Rectangle {
    width: ball.size * 0.09
    height: width
    radius: width / 2
    x: ball.size * 0.25
    y: ball.size * 0.18
    color: "#ffffff"
    opacity: 0.72
  }

  // Micro dot for the bar: a tiny status light at the bottom-right.
  Rectangle {
    visible: ball.dot
    width: Math.max(2, ball.size * 0.29)
    height: width
    radius: width / 2
    x: ball.size - width - ball.size * 0.01
    y: ball.size - height - ball.size * 0.01
    color: "#ffffff"
    opacity: 0.9
    border.width: Math.max(1, ball.size * 0.055)
    border.color: Qt.darker(ball.ballColor, 2.5)
  }
}
