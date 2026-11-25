import QtQuick
import qs.Commons

// A cursor-arrow badge for mouse devices. The arrow is a rounded, extruded
// triangle that turns around its vertical axis: slowly while idle, fast with
// air streaks on a click. Opening glides in and starts the idle turn.
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
      function convexHull(points) {
        if (points.length < 3) return points
        var pts = points.slice().sort(function(a, b) {
          return a[0] === b[0] ? a[1] - b[1] : a[0] - b[0]
        })
        function cross(o, a, b) {
          return (a[0] - o[0]) * (b[1] - o[1])
            - (a[1] - o[1]) * (b[0] - o[0])
        }
        var lower = []
        for (var i = 0; i < pts.length; i++) {
          while (lower.length >= 2 && cross(lower[lower.length - 2],
            lower[lower.length - 1], pts[i]) <= 0) lower.pop()
          lower.push(pts[i])
        }
        var upper = []
        for (var j = pts.length - 1; j >= 0; j--) {
          while (upper.length >= 2 && cross(upper[upper.length - 2],
            upper[upper.length - 1], pts[j]) <= 0) upper.pop()
          upper.push(pts[j])
        }
        lower.pop()
        upper.pop()
        return lower.concat(upper)
      }
      function roundedPolygon(points, radius) {
        var out = []
        var n = points.length
        for (var i = 0; i < n; i++) {
          var p = points[i]
          var prev = points[(i + n - 1) % n]
          var next = points[(i + 1) % n]
          var ax = p[0] - prev[0]
          var ay = p[1] - prev[1]
          var al = Math.max(0.001, Math.hypot(ax, ay))
          var bx = next[0] - p[0]
          var by = next[1] - p[1]
          var bl = Math.max(0.001, Math.hypot(bx, by))
          var p1 = [p[0] - ax / al * radius, p[1] - ay / al * radius]
          var p2 = [p[0] + bx / bl * radius, p[1] + by / bl * radius]
          for (var t = 0; t <= 6; t++) {
            var u = t / 6
            var v = 1 - u
            out.push([
              v * v * p1[0] + 2 * v * u * p[0] + u * u * p2[0],
              v * v * p1[1] + 2 * v * u * p[1] + u * u * p2[1]
            ])
          }
        }
        return out
      }

      var w = width
      var h = height
      if (w <= 0 || h <= 0) return
      var cx = w / 2
      var cy = h / 2

      // A massive rounded pointer triangle, with no thin stem.
      var local = [[4.5, 3.0], [20.0, 14.4], [10.6, 21.0]]
      var points = roundedPolygon(local, 2.0)
      var scale = w * 0.82 / 18.5
      var ox = cx - 12.25 * scale
      var oy = cy - 12.0 * scale
      var rad = cursor.angle * Math.PI / 180
      var ca = Math.cos(rad)
      var sa = Math.sin(rad)
      // A smooth perspective scale: no sign-clamp step at 90°. The extruded
      // side faces keep the pointer visible while the front face is edge-on.
      var sign = ca < 0 ? -1 : 1
      var sx = sign * Math.pow(Math.abs(ca), 0.72)
      var depth = Math.max(2.0, w * 0.11) * sa
      // A true prism: the back face is a little smaller than the front, so
      // the connecting side faces read as a solid, beveled end cap instead of
      // a flat ribbon. Edge-on the cap stays visible between the two rims.
      var backScale = 0.88 + 0.12 * Math.abs(ca)

      function project(p) {
        return [cx + (ox + p[0] * scale - cx) * sx, oy + p[1] * scale]
      }

      var front = []
      for (var i = 0; i < points.length; i++)
        front.push(project(points[i]))

      var bcx = 0
      var bcy = 0
      for (var c = 0; c < front.length; c++) {
        bcx += front[c][0]
        bcy += front[c][1]
      }
      bcx /= Math.max(1, front.length)
      bcy /= Math.max(1, front.length)

      var back = []
      for (var b = 0; b < front.length; b++) {
        back.push([
          bcx + (front[b][0] - bcx) * backScale + depth,
          bcy + (front[b][1] - bcy) * backScale
        ])
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

      // Fill the whole projected silhouette first. Any hairline between the
      // front, back and side quads then shows the side colour, not the panel
      // behind it, so the prism is always monolithic.
      var hull = convexHull(front.concat(back))
      if (hull.length >= 3) {
        ctx.beginPath()
        ctx.moveTo(hull[0][0], hull[0][1])
        for (var h = 1; h < hull.length; h++)
          ctx.lineTo(hull[h][0], hull[h][1])
        ctx.closePath()
        ctx.globalAlpha = 1
        ctx.fillStyle = Qt.darker(cursor.color, 1.55)
        ctx.fill()
      }

      // Back face and side extrusion.
      ctx.beginPath()
      ctx.moveTo(back[0][0], back[0][1])
      for (var b = 1; b < back.length; b++)
        ctx.lineTo(back[b][0], back[b][1])
      ctx.closePath()
      ctx.fillStyle = Qt.darker(cursor.color, 2.05)
      ctx.globalAlpha = 1
      ctx.fill()

      // Every face is opaque: the prism must read as one solid object, not a
      // translucent ribbon with a see-through end.
      ctx.fillStyle = Qt.darker(cursor.color, 1.72)
      for (var e = 0; e < front.length; e++) {
        var n = (e + 1) % front.length
        ctx.beginPath()
        ctx.moveTo(front[e][0], front[e][1])
        ctx.lineTo(front[n][0], front[n][1])
        ctx.lineTo(back[n][0], back[n][1])
        ctx.lineTo(back[e][0], back[e][1])
        ctx.closePath()
        ctx.fill()
      }
      ctx.globalAlpha = 1

      // A bright bevel on the far rim is the visible end face of the prism.
      // It stays readable when the front face is exactly edge-on.
      ctx.beginPath()
      ctx.moveTo(back[0][0], back[0][1])
      for (var bo = 1; bo < back.length; bo++)
        ctx.lineTo(back[bo][0], back[bo][1])
      ctx.closePath()
      ctx.lineWidth = Math.max(1, w * 0.016)
      ctx.strokeStyle = "rgba(255,255,255,0.24)"
      ctx.stroke()

      // Front face. The gradient is projected with the face, so it turns with
      // the arrow instead of sitting in screen space.
      var la = project([6.0, 5.0])
      var lb = project([16.0, 18.0])
      var face = ctx.createLinearGradient(la[0], la[1], lb[0], lb[1])
      face.addColorStop(0, Qt.lighter(cursor.color, 1.36))
      face.addColorStop(0.48, cursor.color)
      face.addColorStop(1, Qt.darker(cursor.color, 1.40))
      ctx.beginPath()
      ctx.moveTo(front[0][0], front[0][1])
      for (var j = 1; j < front.length; j++)
        ctx.lineTo(front[j][0], front[j][1])
      ctx.closePath()
      ctx.fillStyle = face
      ctx.fill()

      // Soft specular spot, clipped to the face so it shrinks naturally as
      // the arrow turns edge-on.
      ctx.save()
      ctx.beginPath()
      ctx.moveTo(front[0][0], front[0][1])
      for (var k = 1; k < front.length; k++)
        ctx.lineTo(front[k][0], front[k][1])
      ctx.closePath()
      ctx.clip()
      var hp = project([7.5, 6.2])
      var spotAmount = Math.pow(Math.max(0, ca), 0.7)
      var spot = ctx.createRadialGradient(hp[0], hp[1], 0,
        hp[0], hp[1], w * 0.20)
      spot.addColorStop(0, "rgba(255,255,255," + (0.30 * spotAmount) + ")")
      spot.addColorStop(0.45, "rgba(255,255,255," + (0.08 * spotAmount) + ")")
      spot.addColorStop(1, "rgba(255,255,255,0)")
      ctx.fillStyle = spot
      ctx.fillRect(0, 0, w, h)
      ctx.restore()

      // A light leading edge is always present, so a profile view still reads.
      ctx.beginPath()
      ctx.moveTo(front[0][0], front[0][1])
      for (var m = 1; m < front.length; m++)
        ctx.lineTo(front[m][0], front[m][1])
      ctx.closePath()
      ctx.lineWidth = Math.max(1, w * 0.016)
      ctx.strokeStyle = "rgba(255,255,255,0.30)"
      ctx.stroke()
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
