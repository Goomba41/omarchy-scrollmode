import QtQuick
import qs.Commons

// Cursor-arrow badge for mouse devices.
//
// The silhouette is traced from the supplied reference as a 40-point contour,
// then softened with one smoothing pass. It is extruded into a solid 3D slab
// that turns around the line from the top corner to the notch; soft rounded
// ends and tinted rims keep the shape readable while it rotates.
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

  readonly property real slowSpeed: 28
  readonly property real kickSpeed: 900
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
    id: cursorCanvas
    anchors.fill: parent
    z: 1
    antialiasing: true

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.lineJoin = "round"
      ctx.lineCap = "round"
      ctx.miterLimit = 2

      function ellipse(cx, cy, rx, ry) {
        ctx.save()
        ctx.translate(cx, cy)
        ctx.scale(Math.max(0.01, rx), Math.max(0.01, ry))
        ctx.beginPath()
        ctx.arc(0, 0, 1, 0, Math.PI * 2)
        ctx.restore()
      }

      function smoothLoop(points, iterations, weight) {
        var out = points
        for (var iteration = 0; iteration < iterations; iteration++) {
          var next = []
          for (var i = 0; i < out.length; i++) {
            var a = out[(i + out.length - 1) % out.length]
            var b = out[i]
            var c = out[(i + 1) % out.length]
            next.push([
              weight * a[0] + (1 - 2 * weight) * b[0] + weight * c[0],
              weight * a[1] + (1 - 2 * weight) * b[1] + weight * c[1]
            ])
          }
          out = next
        }
        return out
      }

      function area(points) {
        var total = 0
        for (var i = 0; i < points.length; i++) {
          var p = points[i]
          var q = points[(i + 1) % points.length]
          total += p[0] * q[1] - q[0] * p[1]
        }
        return total / 2
      }

      var w = width
      var h = height
      if (w <= 0 || h <= 0) return

      // 40-point contour traced from the reference, with one gentle smoothing
      // pass. Coordinates keep the real 12 x 13.525 aspect ratio; the rounded
      // ends come from the reference itself, not from cutting the corners.
      var base = [
        [1.322, 0.0], [1.9322, 0.0], [2.1356, 0.1017], [2.4407, 0.4068],
        [2.8475, 0.6102], [3.5593, 1.2203], [3.9661, 1.4237],
        [4.2712, 1.7288], [4.678, 1.9322], [5.3898, 2.5424],
        [5.7966, 2.7458], [7.322, 3.9661], [8.0339, 4.3729],
        [8.4407, 4.7797], [8.8475, 4.9831], [9.5593, 5.5932],
        [9.9661, 5.7966], [10.2712, 6.1017], [10.3729, 6.1017],
        [11.3898, 6.9153], [11.4915, 6.9153], [11.8983, 7.322],
        [12.0, 7.5254], [12.0, 8.1356], [11.8983, 8.339],
        [11.6949, 8.5424], [11.2881, 8.6441], [11.1864, 8.7458],
        [10.7797, 8.7458], [10.678, 8.8475], [10.2712, 8.8475],
        [10.1695, 8.9492], [9.7627, 8.9492], [9.661, 9.0508],
        [8.6441, 9.1525], [8.5424, 9.2542], [7.5254, 9.3559],
        [7.4237, 9.4576], [7.0169, 9.4576], [6.9153, 9.5593],
        [6.5085, 9.5593], [6.4068, 9.661], [6.0, 9.661],
        [5.8983, 9.7627], [5.6949, 9.7627], [5.1864, 10.2712],
        [5.0847, 10.2712], [4.5763, 10.7797], [4.4746, 10.7797],
        [3.9661, 11.2881], [3.8644, 11.2881], [3.3559, 11.7966],
        [3.2542, 11.7966], [1.6271, 13.2203], [1.5254, 13.2203],
        [1.1186, 13.5254], [0.6102, 13.5254], [0.4068, 13.4237],
        [0.0, 13.0169], [0.0, 11.2881], [0.1017, 11.1864],
        [0.1017, 9.661], [0.2034, 9.5593], [0.2034, 8.0339],
        [0.3051, 7.9322], [0.3051, 6.4068], [0.4068, 6.3051],
        [0.4068, 4.7797], [0.5085, 4.678], [0.5085, 3.1525],
        [0.6102, 3.0508], [0.6102, 1.6271], [0.7119, 1.5254],
        [0.7119, 0.6102], [0.8136, 0.4068], [1.1186, 0.1017],
        [1.2203, 0.1017]
      ]
      var points = smoothLoop(base, 1, 0.25)
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
      var shapeW = Math.max(0.001, maxX - minX)
      var shapeH = Math.max(0.001, maxY - minY)
      var centerX = (minX + maxX) / 2
      var centerY = (minY + maxY) / 2
      var scale = Math.min((w * 0.92) / shapeW, (h * 0.92) / shapeH)
      var cx = w / 2
      var cy = h / 2
      var halfDepth = w * 0.055
      var focal = w * 4.2

      var top = [1.322, 0.0]
      var notch = [5.6949, 9.7627]
      var ax = notch[0] - top[0]
      var ay = notch[1] - top[1]
      var al = Math.max(0.001, Math.hypot(ax, ay))
      var ux = ax / al
      var uy = ay / al
      var pivotX = (top[0] - centerX) * scale
      var pivotY = (top[1] - centerY) * scale
      var theta = cursor.angle * Math.PI / 180
      var ct = Math.cos(theta)
      var st = Math.sin(theta)

      function rotate(v) {
        var px = v[0] - pivotX
        var py = v[1] - pivotY
        var pz = v[2]
        var dot = px * ux + py * uy
        var crossX = uy * pz
        var crossY = -ux * pz
        var crossZ = ux * py - uy * px
        return [
          pivotX + px * ct + crossX * st + ux * dot * (1 - ct),
          pivotY + py * ct + crossY * st + uy * dot * (1 - ct),
          pz * ct + crossZ * st
        ]
      }

      function project(v) {
        var s = focal / Math.max(1, focal - v[2])
        return [cx + v[0] * s, cy + v[1] * s]
      }

      function buildLayer(pts, z) {
        var v3 = []
        var v2 = []
        for (var i = 0; i < pts.length; i++) {
          var v = rotate([
            (pts[i][0] - centerX) * scale,
            (pts[i][1] - centerY) * scale,
            z
          ])
          v3.push(v)
          v2.push(project(v))
        }
        return { v3: v3, v2: v2 }
      }

      var front = buildLayer(points, halfDepth)
      var back = buildLayer(points, -halfDepth)

      if (cursor.shadow) {
        var grad = ctx.createRadialGradient(
          cx, h * 0.84, 0, cx, h * 0.84, w * 0.40)
        grad.addColorStop(0, "rgba(0,0,0,0.30)")
        grad.addColorStop(1, "rgba(0,0,0,0)")
        ctx.fillStyle = grad
        ellipse(cx, h * 0.84, w * 0.27, h * 0.075)
        ctx.fill()
      }

      function averageZ(vertices) {
        var total = 0
        for (var v = 0; v < vertices.length; v++) total += vertices[v][2]
        return total / Math.max(1, vertices.length)
      }

      function path(vertices) {
        ctx.beginPath()
        ctx.moveTo(vertices[0][0], vertices[0][1])
        for (var v = 1; v < vertices.length; v++)
          ctx.lineTo(vertices[v][0], vertices[v][1])
        ctx.closePath()
      }

      var faces = []
      faces.push({ kind: "front", pts: front.v2, v3: front.v3,
                   z: averageZ(front.v3) })
      faces.push({ kind: "back", pts: back.v2, v3: back.v3,
                   z: averageZ(back.v3) })
      for (var e = 0; e < points.length; e++) {
        var n = (e + 1) % points.length
        var sideV3 = [front.v3[e], front.v3[n], back.v3[n], back.v3[e]]
        faces.push({
          kind: "side",
          pts: [front.v2[e], front.v2[n], back.v2[n], back.v2[e]],
          v3: sideV3,
          z: (front.v3[e][2] + front.v3[n][2]
              + back.v3[n][2] + back.v3[e][2]) / 4
        })
      }

      // All faces keep the same fill: the plane colour must not change as the
      // glyph turns. The dark rims carry the 3D read instead.
      var frontColor = cursor.color
      var sideColor = cursor.color
      var backColor = cursor.color
      var edgeColor = Qt.darker(cursor.color, 2.5)
      var edgeWidth = Math.max(0.7, w * 0.018)
      // A face is visible when its outward normal points toward the camera.
      // Projected winding is not enough here: a half turn around an in-plane
      // axis also mirrors the silhouette.
      function faceNormal(vs) {
        var ax = vs[1][0] - vs[0][0]
        var ay = vs[1][1] - vs[0][1]
        var az = vs[1][2] - vs[0][2]
        var bx = vs[2][0] - vs[0][0]
        var by = vs[2][1] - vs[0][1]
        var bz = vs[2][2] - vs[0][2]
        var nx = ay * bz - az * by
        var ny = az * bx - ax * bz
        var nz = ax * by - ay * bx
        var length = Math.hypot(nx, Math.hypot(ny, nz))
        return [nx / Math.max(0.001, length), ny / Math.max(0.001, length),
                nz / Math.max(0.001, length)]
      }

      function faceCenter(vs) {
        var total = [0, 0, 0]
        for (var k = 0; k < vs.length; k++) {
          total[0] += vs[k][0]
          total[1] += vs[k][1]
          total[2] += vs[k][2]
        }
        return [total[0] / vs.length, total[1] / vs.length,
                total[2] / vs.length]
      }

      // Seal tiny seams behind the sorted faces.
      ctx.fillStyle = sideColor
      for (var s = 0; s < faces.length; s++) {
        path(faces[s].pts)
        ctx.fill()
      }

      var visible = []
      for (var v = 0; v < faces.length; v++) {
        var face = faces[v]
        if (Math.abs(area(face.pts)) < 0.15) continue
        var normal = faceNormal(face.v3)
        var center = faceCenter(face.v3)
        if (normal[0] * center[0] + normal[1] * center[1]
            + normal[2] * center[2] < 0) {
          normal = [-normal[0], -normal[1], -normal[2]]
        }
        if (normal[2] <= 0.001) continue
        visible.push(face)
      }
      visible.sort(function(a, b) { return a.z - b.z })
      for (var f = 0; f < visible.length; f++) {
        var item = visible[f]
        path(item.pts)
        ctx.fillStyle = item.kind === "front" ? frontColor
          : (item.kind === "back" ? backColor : sideColor)
        ctx.fill()
        // Side walls are one continuous surface. Stroke only their front and
        // back rims, not the narrow seams between neighbouring quads.
        ctx.strokeStyle = edgeColor
        ctx.lineWidth = edgeWidth
        if (item.kind === "side") {
          var a = item.pts[0]
          var b = item.pts[1]
          var c = item.pts[2]
          var d = item.pts[3]
          ctx.beginPath()
          ctx.moveTo(a[0], a[1])
          ctx.lineTo(b[0], b[1])
          ctx.stroke()
          ctx.beginPath()
          ctx.moveTo(d[0], d[1])
          ctx.lineTo(c[0], c[1])
          ctx.stroke()
        } else {
          ctx.stroke()
        }
      }
    }

    Connections {
      target: cursor
      function onAngleChanged() { cursorCanvas.requestPaint() }
      function onColorChanged() { cursorCanvas.requestPaint() }
      function onShadowChanged() { cursorCanvas.requestPaint() }
    }
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
  }

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
      // Streams follow the cursor's diagonal instead of running flat.
      ctx.save()
      ctx.translate(w / 2, h / 2)
      ctx.rotate(Math.PI / 4)
      ctx.translate(-w / 2, -h / 2)
      var overscan = Math.hypot(w, h) * 0.35
      for (var i = 0; i < 3; i++) {
        var y = h * (0.53 + i * 0.10)
        var alpha = (0.10 + amount * 0.36) * (1 - i * 0.14)
        var start = -cursor.airMargin * 0.35 + (i % 2 ? -phase : phase)
          - overscan
        var end = w + cursor.airMargin * 0.35 - (i % 2 ? phase : -phase)
          + overscan
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
      ctx.restore()
    }

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
  }
}
