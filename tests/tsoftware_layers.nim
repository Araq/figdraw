import std/[hashes, unittest, importutils]
import pkg/[pixie, chroma, vmath]
import figdraw/[figbackend, fignodes]
import figdraw/software/[context, layers]

type ComposedFrame = ref object
  image: Image
  layers: seq[Image]
  bounds: seq[Rect]

privateAccess ImageLayerContext

proc newContext(
    frame: ComposedFrame, native = false, maxCacheBytes: Positive = 64 * 1024 * 1024
): ImageLayerContext =
  var composer = ImageComposer(
    coordinateScale: 1,
    beginFrame: proc(size: Vec2, clear: bool, color: Color) =
      if frame.image.isNil or frame.image.width != size.x.int or
          frame.image.height != size.y.int:
        frame.image = newImage(size.x.int, size.y.int)
      if clear:
        frame.image.fill(color)
      frame.layers.setLen(0)
      frame.bounds.setLen(0),
    drawImage: proc(layer: LayerImage, bounds: Rect) =
      frame.layers.add(layer.image)
      frame.bounds.add(bounds)
      frame.image.draw(layer.image, translate(bounds.xy)),
    snapshot: proc(): Image =
      frame.image.copy(),
  )
  if native:
    composer.snapshot = nil
  newImageLayerContext(composer, workers = 1, maxCacheBytes = maxCacheBytes)

proc begin(ctx: BackendContext, clear = true) =
  ctx.beginFrame(vec2(64), clear, color(0, 0, 0, 0))

proc radii(): CornerRadii2D[float32] =
  result.x = [5'f32, 8, 3, 6]
  result.y = [3'f32, 4, 6, 8]

suite "cached software image layers":
  test "capture references do not retain rasters evicted by the cache budget":
    let frame = ComposedFrame()
    let ctx = frame.newContext(native = true, maxCacheBytes = 512)
    ctx.begin()
    for i in 0 ..< 3:
      ctx.drawRect(rect(i.float32 * 10, 0, 8, 8), color(i.float32 / 2, 0, 0, 1))
    check ctx.cacheBytes <= 512
    check ctx.captured.len == 0
    check not ctx.captureValid
    check frame.image[20, 0].r == 255
    expect ValueError:
      discard ctx.readPixels(rect(0, 0, 0, 0), false)

  test "internal raster does not subscribe to global image updates":
    let ctx = ComposedFrame().newContext()
    check ctx.imageMessages != nil
    check ctx.raster.imageMessages == nil

  test "native captures retain image revisions after source updates and removal":
    let frame = ComposedFrame()
    let ctx = frame.newContext(native = true)
    let image = newImage(2, 2)
    image.fill(rgba(255, 0, 0, 255))
    ctx.putImage(42.Hash, image)
    ctx.begin()
    ctx.drawImage(42.Hash, vec2(4), color(1, 1, 1, 1), false)
    image.fill(rgba(0, 255, 0, 255))
    ctx.updateImage(42.Hash, image)
    ctx.drawImage(42.Hash, vec2(12), color(1, 1, 1, 1), false)
    ctx.removeImage(ImageId(42))
    let captured = ctx.readPixels(rect(0, 0, 0, 0), false)
    check captured[4, 4] == rgba(255, 0, 0, 255).rgbx()
    check captured[12, 12] == rgba(0, 255, 0, 255).rgbx()

  test "uncleared native frames draw without reconstructing a software frame":
    let frame = ComposedFrame()
    let ctx = frame.newContext(native = true)
    ctx.begin()
    ctx.drawRect(rect(4, 4, 8, 8), color(1, 0, 0, 1))
    ctx.begin(clear = false)
    ctx.drawRect(rect(20, 20, 8, 8), color(0, 1, 0, 1))
    check frame.image[4, 4].r == 255
    check frame.image[20, 20].g == 255
    expect ValueError:
      discard ctx.readPixels(rect(0, 0, 0, 0), false)

  test "bounded images are reused and changes invalidate the affected image":
    let frame = ComposedFrame()
    let ctx = frame.newContext()
    ctx.begin()
    ctx.drawRect(rect(4, 5, 8, 9), color(1, 0, 0, 0.5))
    ctx.drawRect(rect(20, 6, 7, 8), color(0, 1, 0, 0.5))
    let first = frame.layers
    check first.len == 2
    check first[0].width == 8
    check first[0].height == 9
    ctx.begin()
    ctx.drawRect(rect(4, 5, 8, 9), color(1, 0, 0, 0.5))
    ctx.drawRect(rect(20, 6, 7, 8), color(0, 0, 1, 0.5))
    check frame.layers[0] == first[0]
    check frame.layers[1] != first[1]
    ctx.begin()
    ctx.drawRect(rect(8, 9, 8, 9), color(1, 0, 0, 0.5))
    check frame.layers[0] == first[0]
    check frame.bounds[0] == rect(8, 9, 8, 9)

  test "the compositor owns scene blending including clipped transformed layers":
    let frame = ComposedFrame()
    let layers = frame.newContext()
    let reference = newSoftwareContext(workers = 1)
    for ctx in [BackendContext(layers), BackendContext(reference)]:
      ctx.begin()
      ctx.drawRect(rect(0, 0, 64, 64), color(0, 0, 1, 1))
      ctx.saveTransform()
      ctx.translate(vec2(11, 7))
      ctx.beginMask(rect(0, 0, 35, 33), radii())
      ctx.endMask()
      ctx.rotate(0.15)
      ctx.drawRoundedRectSdf(
        rect(-4, -3, 39, 40),
        BackendFill(
          kind: bfLinear2,
          lin2Axis: fgaDiagTLBR,
          lin2Start: rgba(255, 0, 0, 128),
          lin2Stop: rgba(0, 255, 0, 180),
        ),
        radii(),
        sdfModeClipAA,
        0,
        0,
        vec2(0),
      )
      ctx.popMask()
      ctx.restoreTransform()
    let expected = reference.readPixels(rect(0, 0, 0, 0), false)
    var error = 0
    for i, actual in frame.image.data:
      let p = expected.data[i]
      error = max(error, abs(actual.r.int - p.r.int))
      error = max(error, abs(actual.g.int - p.g.int))
      error = max(error, abs(actual.b.int - p.b.int))
      error = max(error, abs(actual.a.int - p.a.int))
    check error <= 1

  test "backdrop blur does not add image layers or change scene pixels":
    let frame = ComposedFrame()
    let layers = frame.newContext()
    let reference = newSoftwareContext(workers = 1)
    for ctx in [BackendContext(layers), BackendContext(reference)]:
      ctx.begin()
      ctx.drawRect(rect(0, 0, 32, 64), color(1, 0, 0, 0.5))
      ctx.drawBackdropBlur(rect(10, 10, 40, 40), radii(), 4)
    let expected = reference.readPixels(rect(0, 0, 0, 0), false)
    check frame.image.data == expected.data
    check frame.image[10, 10].a == 128
    check frame.layers.len == 1

  test "source-image updates invalidate cached glyph and image layers":
    let frame = ComposedFrame()
    let ctx = frame.newContext()
    let image = newImage(4, 4)
    image.fill(rgba(255, 0, 0, 255))
    ctx.putImage(42.Hash, image)
    ctx.begin()
    ctx.drawImage(42.Hash, vec2(4), color(1, 1, 1, 1), false)
    let first = frame.layers[0]
    image.fill(rgba(0, 255, 0, 255))
    ctx.updateImage(42.Hash, image)
    ctx.begin()
    ctx.drawImage(42.Hash, vec2(4), color(1, 1, 1, 1), false)
    check frame.layers[0] != first
    check frame.image[4, 4].g == 255

  test "uncleared frames preserve previous compositor contents":
    let frame = ComposedFrame()
    let ctx = frame.newContext()
    ctx.begin()
    ctx.drawRect(rect(4, 4, 8, 8), color(1, 0, 0, 1))
    ctx.begin(clear = false)
    ctx.drawRect(rect(20, 20, 8, 8), color(0, 1, 0, 1))
    check frame.image[4, 4].r == 255
    check frame.image[20, 20].g == 255
