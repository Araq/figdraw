## Shared scene for the CPU capture and uirelays window examples.
import figdraw

proc softwareScene*(width = 560'f32, height = 360'f32): Renders =
  result = newRenders()
  let root = result.addRoot(
    0.ZLevel,
    Fig(
      kind: nkRectangle,
      screenBox: rect(0, 0, width, height),
      fill: rgba(240, 243, 250, 255),
    ),
  )
  discard result.addChild(
    0.ZLevel,
    root,
    Fig(
      kind: nkRectangle,
      screenBox: rect(28, 64, 228, 132),
      corners: [32'u16, 48, 12, 36],
      cornerRadiiY: [12'u16, 24, 32, 48],
      flags: {NfEllipticalCorners},
      fill: linear(rgba(219, 58, 91, 255), rgba(125, 74, 215, 255), fgaDiagTLBR),
      stroke: RenderStroke(weight: 3, fill: rgba(100, 35, 100, 255)),
      shadows: [
        RenderShadow(
          style: DropShadow, fill: rgba(25, 30, 70, 80), blur: 12, spread: 2, y: 6
        ),
        default(RenderShadow),
        default(RenderShadow),
        default(RenderShadow),
      ],
    ),
  )
  let clip = result.addChild(
    0.ZLevel,
    root,
    Fig(
      kind: nkRectangle,
      screenBox: rect(290, 64, 230, 132),
      corners: [24'u16, 24, 24, 24],
      flags: {NfClipContent},
      fill: rgba(218, 232, 249, 255),
    ),
  )
  discard result.addChild(
    0.ZLevel,
    clip,
    Fig(
      kind: nkDrawable,
      screenBox: rect(290, 64, 230, 132),
      fill: rgba(45, 128, 210, 255),
      drawStroke: RenderStroke(weight: 5, fill: rgba(24, 65, 125, 255), cap: scRound),
      drawOps: @[
        drawableEllipse(vec2(44, 66), vec2(72, 42)),
        drawableBezier(@[vec2(94, 106), vec2(140, -22), vec2(218, 90)]),
      ],
    ),
  )
  # System font families work through the existing FigDraw glyph API.
  # Keep the bundled font as a portable fallback when Arial is unavailable.
  let font = FigFont(typefaceId: loadTypeface("Arial", ["data/Ubuntu.ttf"]), size: 22)
  let layout = typeset(
    rect(0, 0, 492, 70),
    [
      span(
        font,
        rgba(30, 43, 70, 255),
        "FigDraw glyphs, rendered in software.\nElliptical corners, gradients, shadows and curves.",
      )
    ],
    minContent = false,
    wrap = true,
  )
  discard result.addChild(
    0.ZLevel,
    root,
    Fig(kind: nkText, screenBox: rect(32, 236, 492, 70), textLayout: layout),
  )
