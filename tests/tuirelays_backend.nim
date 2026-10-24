import std/unittest

when defined(features.figdraw.uirelays):
  import pkg/[chroma, pixie]
  from pkg/uirelays/screen as relayScreen import nil
  from pkg/uirelays/coords as relayCoords import nil
  import figdraw/[commons, fignodes, figrender, uirelays]

  var
    received: seq[uint32]
    destination: relayCoords.Rect
    accepts = true
    sourceWidth, sourceHeight: int
    windowLayout: relayScreen.ScreenLayout
    nativeFills: seq[tuple[bounds: relayCoords.Rect, fill: relayScreen.Color]]

  proc recordFill(bounds: relayCoords.Rect, fill: relayScreen.Color) =
    nativeFills.add((bounds, fill))

  proc getLayout(): relayScreen.ScreenLayout =
    windowLayout

  proc recordBlit(
      pixels: ptr UncheckedArray[uint32],
      w, h: int,
      dst: relayCoords.Rect,
      format: relayScreen.RGBAFormat,
  ): bool =
    sourceWidth = w
    sourceHeight = h
    received.setLen(w * h)
    for i in 0 ..< received.len:
      received[i] = pixels[i]
    destination = dst
    accepts

  suite "uirelays software presentation":
    setup:
      let saved = relayScreen.drawRelays
      let savedWindow = relayScreen.windowRelays
      let savedScale = figUiScale()
      received.setLen(0)
      nativeFills.setLen(0)
      accepts = true
      windowLayout = relayScreen.ScreenLayout(scaleX: 1, scaleY: 1, uiScale: 100)
      relayScreen.windowRelays.getWindowLayout = getLayout
      relayScreen.drawRelays.blitRGBA = recordBlit
      relayScreen.drawRelays.drawRGBA = nil
      relayScreen.drawRelays.fillRect = recordFill
    teardown:
      relayScreen.drawRelays = saved
      relayScreen.windowRelays = savedWindow
      setFigUiScale(savedScale)

    test "packs host integers and composites transparent pixels once":
      let image = newImage(3, 1)
      image[0, 0] = rgba(20, 40, 60, 255)
      image[1, 0] = rgba(255, 0, 0, 128)
      check presentUirelaysImage(image, rgba(0, 0, 255, 255), x = 7, y = 9)
      check received == @[0x0014283c'u32, 0x0080007f'u32, 0x000000ff'u32]
      check destination.x == 7
      check destination.y == 9
      check destination.w == 3
      check destination.h == 1

    test "submits individual images with premultiplied alpha":
      let renderer = newUirelaysRenderer()
      var nodes = newRenders()
      discard nodes.addRoot(
        0.ZLevel,
        Fig(
          kind: nkRectangle,
          screenBox: rect(0, 0, 8, 8),
          fill: linear(rgba(10, 20, 30, 255), rgba(10, 20, 30, 255), axis = fgaX),
        ),
      )
      renderer.renderFrame(nodes, vec2(8, 8))
      check received.len == 64
      check received[0] == 0xff0a141e'u32
      check renderer.takeOneFrameScreenshot().width == 8

    test "solid square fills use native rectangles and retain captures":
      windowLayout = relayScreen.ScreenLayout(
        width: 8, height: 4, scaleX: 2, scaleY: 2, uiScale: 100
      )
      let renderer = newUirelaysRenderer()
      var nodes = newRenders()
      discard nodes.addRoot(
        0.ZLevel,
        Fig(kind: nkRectangle, screenBox: rect(1, 1, 4, 2), fill: rgba(255, 0, 0, 128)),
      )
      renderer.renderFrame(nodes, vec2(8, 4))
      check received.len == 0
      check nativeFills.len == 2 # Window clear followed by the shape.
      check nativeFills[1].bounds == relayCoords.rect(1, 1, 4, 2)
      check nativeFills[1].fill == relayScreen.color(255, 0, 0, 128)
      let stats = ImageLayerContext(renderer.ctx).imageCacheStats()
      check stats.nativeRects == 1
      check stats.entries == 0
      let captured = renderer.takeOneFrameScreenshot()
      check captured[2, 2] == rgba(255, 127, 127, 255).rgbx()
      check captured[0, 0] == rgba(255, 255, 255, 255).rgbx()

    test "native and raster image captures preserve draw order":
      let ctx = newUirelaysContext()
      ctx.beginFrame(vec2(8), true, color(1, 1, 1, 1))
      ctx.drawRect(rect(0, 0, 8, 8), color(1, 0, 0, 1))
      ctx.drawRoundedRectSdf(
        rect(0, 0, 4, 4),
        BackendFill(
          kind: bfLinear2,
          lin2Axis: fgaX,
          lin2Start: rgba(0, 0, 255, 255),
          lin2Stop: rgba(0, 0, 255, 255),
        ),
        default(CornerRadii2D[float32]),
        sdfModeClipAA,
        4,
        0,
        vec2(0),
      )
      ctx.drawRect(rect(1, 1, 2, 2), color(0, 1, 0, 128'f32 / 255))
      let captured = ctx.readPixels(rect(0, 0, 0, 0), false)
      check captured[0, 0] == rgba(0, 0, 255, 255).rgbx()
      check captured[1, 1] == rgba(0, 128, 127, 255).rgbx()
      check captured[5, 5] == rgba(255, 0, 0, 255).rgbx()
      check ctx.imageCacheStats().nativeRects == 2
      check ctx.imageCacheStats().entries == 1

    test "fractional placement and masks retain the image path":
      let ctx = newUirelaysContext()
      ctx.beginFrame(vec2(8), true, color(1, 1, 1, 1))
      nativeFills.setLen(0)
      ctx.drawRect(rect(0.25, 0.25, 4, 4), color(1, 0, 0, 0.5))
      check received.len > 0
      check nativeFills.len == 0
      received.setLen(0)
      ctx.beginMask(rect(0, 0, 8, 8), default(CornerRadii2D[float32]))
      ctx.endMask()
      ctx.drawRect(rect(0, 0, 4, 4), color(1, 0, 0, 0.5))
      ctx.popMask()
      check received.len > 0
      check nativeFills.len == 0

    test "missing or rejected image relay is reported":
      let image = newImage(1, 1)
      accepts = false
      check not presentUirelaysImage(image)
      let ctx = newUirelaysContext()
      ctx.beginFrame(vec2(1, 1), true, color(1, 1, 1, 1))
      var corners: CornerRadii2D[float32]
      corners.x = [1'f32, 1, 1, 1]
      corners.y = corners.x
      expect ValueError:
        ctx.drawRoundedRectSdf(
          rect(0, 0, 1, 1),
          BackendFill(kind: bfColor, color: rgba(255, 255, 255, 255)),
          corners,
          sdfModeClipAA,
          4,
          0,
          vec2(0),
        )
      relayScreen.drawRelays.blitRGBA = nil
      check not presentUirelaysImage(image)

    test "Retina frames rasterize device pixels and retain logical dimensions":
      windowLayout = relayScreen.ScreenLayout(
        width: 8, height: 4, scaleX: 2, scaleY: 2, uiScale: 100
      )
      relayScreen.drawRelays.drawRGBA = recordBlit
      let renderer = newUirelaysRenderer()
      check figUiScale() == 2
      let size = configureUirelaysScale(windowLayout)
      check size == vec2(8, 4)
      var nodes = newRenders()
      discard nodes.addRoot(
        0.ZLevel,
        Fig(
          kind: nkRectangle,
          screenBox: rect(0, 0, 1, 4),
          fill: linear(rgba(255, 0, 0, 255), rgba(255, 0, 0, 255), axis = fgaX),
        ),
      )
      renderer.renderFrame(nodes, size, clearColor = color(0, 0, 1, 1))
      check sourceWidth == 2
      check sourceHeight == 8
      check destination.w == 1
      check destination.h == 4
      check received[0] == 0xffff0000'u32
      check received[1] == 0xffff0000'u32

    test "UI enlargement and monitor density are applied once":
      let size = configureUirelaysScale(
        relayScreen.ScreenLayout(
          width: 800, height: 600, scaleX: 1, scaleY: 1, uiScale: 200
        )
      )
      check size == vec2(400, 300)
      check size.scaled() == vec2(800, 600)

    test "fractional Windows and Linux UI scales keep exact device dimensions":
      relayScreen.drawRelays.drawRGBA = recordBlit
      for percentage in [125, 150, 175, 200]:
        for width in [57, 59, 67, 101, 803, 819]:
          windowLayout = relayScreen.ScreenLayout(
            width: width, height: 9, scaleX: 1, scaleY: 1, uiScale: percentage
          )
          let renderer = newUirelaysRenderer()
          let size = configureUirelaysScale(windowLayout)
          var nodes = newRenders()
          discard nodes.addRoot(
            0.ZLevel,
            Fig(
              kind: nkRectangle,
              screenBox: rect(0, 0, size.x, size.y),
              fill: linear(rgba(10, 20, 30, 255), rgba(10, 20, 30, 255), axis = fgaX),
            ),
          )
          renderer.renderFrame(nodes, size)
          check sourceWidth == width
          check sourceHeight == 9

    test "high-density images require a capable relay":
      let image = newImage(4, 2)
      check not presentUirelaysImage(image, width = 2, height = 1)
      relayScreen.drawRelays.drawRGBA = recordBlit
      check presentUirelaysImage(image, width = 2, height = 1)
      check sourceWidth == 4
      check destination.w == 2

    test "presentation leaves native font and window relays installed":
      let fonts = relayScreen.fontRelays
      let window = relayScreen.windowRelays
      discard presentUirelaysImage(newImage(1, 1))
      check relayScreen.fontRelays.openFont == fonts.openFont
      check relayScreen.fontRelays.drawText == fonts.drawText
      check relayScreen.windowRelays.createWindow == window.createWindow
      check relayScreen.windowRelays.refresh == window.refresh

    test "transparent presentation backgrounds are rejected":
      expect ValueError:
        discard newUirelaysContext(rgba(0, 0, 0, 0))
else:
  suite "software backend (optional uirelays feature)":
    test "requires Atlas uirelays feature":
      skip()
