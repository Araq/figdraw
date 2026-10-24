## Rasterize cached FigDraw constructs and compose them through uirelays.
##
## Initialize the uirelays driver and window first. This module imports only the
## platform-independent relays, so the application owns window/event lifetime.
## Native drivers and the Siwin adapter use platform drawing APIs. FigDraw GPU
## presentation is available only through explicitly selected legacy adapters.
## Call uirelays `refresh()` after rendering and after any native text overlays.

import std/math
import pkg/[chroma, pixie]
from pkg/uirelays/screen as relayScreen import nil
from pkg/uirelays/coords as relayCoords import nil
import ./[commons, figrender]
import ./software/context
import ./software/layers

export context, layers

proc presentUirelaysImage*(
    image: Image,
    background = rgba(255, 255, 255, 255),
    x = 0,
    y = 0,
    width = 0,
    height = 0,
): bool =
  ## Draws the source into a destination in driver coordinates. Use logical
  ## width/height when the source contains multiple device pixels per point.
  ## The default destination matches the image's dimensions. This convenience
  ## helper flattens transparency against `background` using the opaque format.
  ## Returns false if the installed driver cannot accept an in-memory image.
  ## Presentation must run on the thread that owns the uirelays window.
  if image.isNil or background.a != 255:
    raise newException(ValueError, "Presentation needs an image and opaque background")
  var pixels = newSeq[uint32](image.data.len)
  for i, pixel in image.data:
    let
      inverse = 255'u32 - pixel.a.uint32
      r = pixel.r.uint32 + (background.r.uint32 * inverse + 127) div 255
      g = pixel.g.uint32 + (background.g.uint32 * inverse + 127) div 255
      b = pixel.b.uint32 + (background.b.uint32 * inverse + 127) div 255
    pixels[i] = (r shl 16) or (g shl 8) or b
  relayScreen.drawRGBA(
    cast[ptr UncheckedArray[uint32]](addr pixels[0]),
    image.width,
    image.height,
    relayCoords.rect(
      x,
      y,
      if width > 0: width else: image.width,
      if height > 0: height else: image.height,
    ),
  )

proc configureUirelaysScale*(layout: relayScreen.ScreenLayout): Vec2 =
  ## Sets FigDraw's raster/UI scale and returns the logical scene size.
  ## Call before building layouts and after a window size or density change.
  ## The raster covers the backing pixels; native uirelays drawing keeps its
  ## usual driver coordinates and applies its own density scaling.
  let
    density = max(1, max(layout.scaleX, layout.scaleY)).float32
    uiScale =
      if layout.uiScale > 0:
        layout.uiScale.float32 / 100'f32
      else:
        1'f32
  setFigUiScale(density * uiScale)
  result = vec2(layout.width.float32, layout.height.float32) / uiScale
  for axis in 0 ..< 2:
    let pixels = (if axis == 0: layout.width else: layout.height).float32 * density
    if ceil(result[axis] * figUiScale()) > pixels:
      result[axis] = cast[float32](cast[uint32](result[axis]) - 1'u32)

proc newUirelaysContext*(
    background = rgba(255, 255, 255, 255),
    workers: Natural = 0,
    parallelThreshold: Positive = 262_144,
): ImageLayerContext =
  ## Rasterizes bounded, cached shape/glyph images with sdfy. The installed
  ## driver composes those images with premultiplied alpha in draw order.
  if background.a != 255:
    raise newException(ValueError, "Presentation background must be opaque")
  let composer = ImageComposer(
    coordinateScale: 1,
    packedPixels: true,
    background: background,
    frameScale: proc(): float32 =
      let layout = relayScreen.getWindowLayout()
      max(1, max(layout.scaleX, layout.scaleY)).float32,
    beginFrame: proc(size: Vec2, clear: bool, color: Color) =
      if clear:
        let layout = relayScreen.getWindowLayout()
        let source = color.rgba().rgbx()
        let inverse = 255'u32 - source.a.uint32
        let combined = relayScreen.color(
          (source.r.uint32 + (background.r.uint32 * inverse + 127) div 255).uint8,
          (source.g.uint32 + (background.g.uint32 * inverse + 127) div 255).uint8,
          (source.b.uint32 + (background.b.uint32 * inverse + 127) div 255).uint8,
        )
        relayScreen.fillRect(
          relayCoords.rect(0, 0, layout.width, layout.height), combined
        )
    ,
    drawImage: proc(layer: LayerImage, bounds: Rect) =
      if not relayScreen.drawRGBA(
        cast[ptr UncheckedArray[uint32]](unsafeAddr layer.pixels[0]),
        layer.image.width,
        layer.image.height,
        relayCoords.rect(bounds.x.int, bounds.y.int, bounds.w.int, bounds.h.int),
        relayScreen.RGBAFormat.argbPremultiplied,
      ):
        raise
          newException(ValueError, "The uirelays driver cannot compose alpha images")
    ,
  )
  newImageLayerContext(
    composer, workers = workers, parallelThreshold = parallelThreshold
  )

proc newUirelaysRenderer*(
    background = rgba(255, 255, 255, 255),
    workers: Natural = 0,
    parallelThreshold: Positive = 262_144,
): FigRenderer[NoRendererBackendState] =
  ## Uses the normal FigDraw scene/glyph APIs and presents via uirelays.
  let layout = relayScreen.getWindowLayout()
  if layout.width > 0 and layout.height > 0:
    discard configureUirelaysScale(layout)
  newFigRenderer(newUirelaysContext(background, workers, parallelThreshold))
