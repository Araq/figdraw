import std/unittest

when defined(features.figdraw.uirelays):
  import pkg/[chroma, pixie]
  from pkg/uirelays/screen as relayScreen import nil
  from pkg/uirelays/coords as relayCoords import nil
  import figdraw/[fignodes, figrender, uirelays]

  var
    received: seq[uint32]
    destination: relayCoords.Rect
    accepts = true

  proc recordBlit(
      pixels: ptr UncheckedArray[uint32], w, h: int, dst: relayCoords.Rect
  ): bool =
    received.setLen(w * h)
    for i in 0 ..< received.len:
      received[i] = pixels[i]
    destination = dst
    accepts

  suite "uirelays software presentation":
    setup:
      let saved = relayScreen.drawRelays
      received.setLen(0)
      accepts = true
      relayScreen.drawRelays.blitRGBA = recordBlit
    teardown:
      relayScreen.drawRelays = saved

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

    test "presents regular FigDraw scenes at endFrame":
      let renderer = newUirelaysRenderer()
      var nodes = newRenders()
      discard nodes.addRoot(
        0.ZLevel,
        Fig(kind: nkRectangle, screenBox: rect(0, 0, 8, 8), fill: rgba(10, 20, 30, 255)),
      )
      renderer.renderFrame(nodes, vec2(8, 8))
      check received.len == 64
      check received[0] == 0x000a141e'u32
      check renderer.takeOneFrameScreenshot().width == 8

    test "missing or rejected image relay is reported":
      let image = newImage(1, 1)
      accepts = false
      check not presentUirelaysImage(image)
      let ctx = newUirelaysContext()
      ctx.beginFrame(vec2(1, 1), true, color(1, 1, 1, 1))
      expect ValueError:
        ctx.endFrame()
      relayScreen.drawRelays.blitRGBA = nil
      check not presentUirelaysImage(image)

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
