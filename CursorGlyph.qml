import QtQuick
import qs.Commons

// A cursor-arrow badge for mouse devices. This is a full pointer silhouette
// (tip, wing, notch and tail), not a triangle: the rounded outline is
// extruded into a solid 3D slab that turns around its vertical axis. Idle
// rotation is calm, a click kicks it fast with air streaks, and opening glides
// the glyph into place.
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

      function roundedPolygon(points, radius) {
        var out = []
        var count = points.length
        for (var i = 0; i < count; i++) {
          var p = points[i]
          var prev = points[(i + count - 1) % count]
          var next = points[(i + 1) % count]
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

      // The ordinary system pointer silhouette, with smoothed corners:
      // tip, right wing, deep notch and the familiar offset tail.
      var local = [
        [2.8, 1.6],
        [18.6, 11.9],
        [12.2, 12.6],
        [15.8, 18.8],
        [11.6, 20.2],
        [8.8, 13.7],
        [2.8, 17.6]
      ]
      var points = roundedPolygon(local, 1.50)

      var minX = points[0][0]
      var maxX = points[0][0]
      var minY = points[0][1]
      var maxY = points[0][1]
      for (var q = 1; q < points.length; q++) {
        minX = Math.min(minX, points[q][0])
        maxX = Math.max(maxX, points[q][0])
        minY = Math.min(minY, points[q][1])
        maxY = Math.max(maxY, points[q][1])
      }
      var spanX = Math.max(0.001, maxX - minX)
      var spanY = Math.max(0.001, maxY - minY)
      var fit = w * 0.90
      var scale = Math.min(fit / spanX, fit / spanY)
      var originX = (minX + maxX) / 2
      var originY = (minY + maxY) / 2

      // True extrusion: the same outline at z = +t/2 and z = -t/2, rotated
      // around Y, then projected once. No per-face shrinking or fake offsets,
      // so the silhouette stays even at every angle.
      var rad = (cursor.angle + 18) * Math.PI / 180
      var ca = Math.cos(rad)
      var sa = Math.sin(rad)
      var halfDepth = w * 0.08
      var focal = w * 3.6

      function rotateY(x, y, z) {
        return [x * ca + z * sa, y, -x * sa + z * ca]
      }

      function project(v) {
        var s = focal / Math.max(1, focal - v[2])
        return [cx + v[0] * s, cy + v[1] * s]
      }

      var front3 = []
      var back3 = []
      var front = []
      var back = []
      for (var i = 0; i < points.length; i++) {
        var x = (points[i][0] - originX) * scale
        var y = (points[i][1] - originY) * scale
        var f3 = rotateY(x, y, halfDepth)
        var b3 = rotateY(x, y, -halfDepth)
        front3.push(f3)
        back3.push(b3)
        front.push(project(f3))
        back.push(project(b3))
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

      function averageZ(vertices) {
        var total = 0
        for (var v = 0; v < vertices.length; v++)
          total += vertices[v][2]
        return total / Math.max(1, vertices.length)
      }

      function polyPath(vertices) {
        ctx.beginPath()
        ctx.moveTo(vertices[0][0], vertices[0][1])
        for (var v = 1; v < vertices.length; v++)
          ctx.lineTo(vertices[v][0], vertices[v][1])
        ctx.closePath()
      }

      var faces = []
      faces.push({ kind: "front", pts: front, z: averageZ(front3) })
      faces.push({ kind: "back", pts: back, z: averageZ(back3) })
      for (var e = 0; e < front.length; e++) {
        var n = (e + 1) % front.length
        faces.push({
          kind: "side",
          pts: [front[e], front[n], back[n], back[e]],
          z: (front3[e][2] + front3[n][2] + back3[n][2] + back3[e][2]) / 4
        })
      }

      // Flat, slightly different face colours: a lit front, the base colour
      // on the side walls and a slightly darker rear. No gradients, so no
      // plane can look pressed in and no edge changes tone while turning.
      var frontColor = Qt.lighter(cursor.color, 1.12)
      var sideColor = Qt.lighter(cursor.color, 1.05)
      var backColor = cursor.color

      // Seal the seams before sorting, using the side colour.
      ctx.fillStyle = sideColor
      ctx.strokeStyle = sideColor
      ctx.lineWidth = Math.max(0.7, w * 0.008)
      for (var u = 0; u < faces.length; u++) {
        polyPath(faces[u].pts)
        ctx.fill()
        ctx.stroke()
      }

      faces.sort(function(a, b) { return a.z - b.z })
      for (var f = 0; f < faces.length; f++) {
        var face = faces[f]
        var fill = face.kind === "front" ? frontColor
          : (face.kind === "back" ? backColor : sideColor)
        polyPath(face.pts)
        ctx.fillStyle = fill
        ctx.strokeStyle = fill
        ctx.lineWidth = Math.max(0.8, w * 0.010)
        ctx.fill()
        ctx.stroke()
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

  // Horizontal air streams in front of the cursor while it spins fast.
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
