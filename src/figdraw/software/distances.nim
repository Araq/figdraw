## Prepared rounded-box fields shared by scalar and SIMD software rendering.

import pkg/vmath
import pkg/sdfy/shapes
import pkg/sdfy/simd/shapesSimd

const softwareSimdEnabled* =
  allowSimd and not defined(figdrawNoSimd) and
  (defined(amd64) or defined(arm64) or defined(aarch64) or defined(arm))

when softwareSimdEnabled:
  when defined(amd64):
    import pkg/nimsimd/sse2
  else:
    import pkg/nimsimd/neon

type RoundedBoxField* = object
  halfSize: Vec2
  rx, ry: Vec4
  circular: bool

proc roundedBoxField*(halfSize: Vec2, rx, ry: Vec4): RoundedBoxField =
  ## Normalize radii once per draw, preserving sdfy's clamping and sharp corners.
  result.halfSize = max(halfSize, vec2(0))
  result.circular = true
  for i in 0 ..< 4:
    var x, y: float32
    if rx[i] == ry[i]:
      x = clamp(rx[i], 0'f32, min(result.halfSize.x, result.halfSize.y))
      y = x
    else:
      x = clamp(rx[i], 0'f32, result.halfSize.x)
      y = clamp(ry[i], 0'f32, result.halfSize.y)
      if x <= 0 or y <= 0:
        x = 0
        y = 0
    result.rx[i] = x
    result.ry[i] = y
    result.circular = result.circular and x == y

proc distance*(field: RoundedBoxField, p: Vec2): float32 {.inline.} =
  if field.circular:
    sdRoundedBox(p, field.halfSize, field.rx)
  else:
    sdEllipticalRoundedBox(p, field.halfSize, field.rx, field.ry)

proc distances*(field: RoundedBoxField, points: array[4, Vec2]): array[4, float32] =
  ## Evaluate one packet. Callers retain control of shading and compositing.
  when softwareSimdEnabled:
    var xs, ys: array[4, float32]
    for i in 0 ..< 4:
      xs[i] = points[i].x
      ys[i] = points[i].y
    when defined(amd64):
      let px = mm_loadu_ps(xs[0].addr)
      let py = mm_loadu_ps(ys[0].addr)
      let values =
        if field.circular:
          sdRoundedBoxSimd(px, py, field.halfSize.x, field.halfSize.y, field.rx)
        else:
          sdEllipticalRoundedBoxSimd(
            px, py, field.halfSize.x, field.halfSize.y, field.rx, field.ry
          )
      mm_storeu_ps(result[0].addr, values)
    else:
      let px = vld1q_f32(xs[0].addr)
      let py = vld1q_f32(ys[0].addr)
      let values =
        if field.circular:
          sdRoundedBoxSimd(px, py, field.halfSize.x, field.halfSize.y, field.rx)
        else:
          sdEllipticalRoundedBoxSimd(
            px, py, field.halfSize.x, field.halfSize.y, field.rx, field.ry
          )
      vst1q_f32(result[0].addr, values)
  else:
    for i in 0 ..< 4:
      result[i] = field.distance(points[i])
