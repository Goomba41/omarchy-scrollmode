.pragma library

// Deterministic DPI colour. Only the DPI value decides the hue, so the same
// DPI always looks the same on every mouse:
//
//   hue = (log2(max(100, dpi) / 100) * 80) % 360
//
// 400 -> 160, 800 -> 240, 1600 -> 320, 3200 -> 40, 6400 -> 120,
// 12800 -> 200. The fractional part of the third octave step moves lightness
// a little, so nearby stages stay distinguishable.
function hueFor(dpi) {
  var value = Math.max(100, Number(dpi) || 0)
  var t = Math.log(value / 100) / Math.LN2
  return (t * 80) % 360
}

function colorFor(dpi, alpha, darkTheme) {
  var value = Math.max(100, Number(dpi) || 0)
  var t = Math.log(value / 100) / Math.LN2
  var frac = t * 3 - Math.floor(t * 3)
  var light = darkTheme === false ? 0.35 + 0.13 * frac : 0.50 + 0.14 * frac
  var a = alpha === undefined ? 1.0 : alpha
  return Qt.hsla(hueFor(value) / 360.0, 0.62, light, a)
}
