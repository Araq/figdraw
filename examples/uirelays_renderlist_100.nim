## atlas install --keepFeatures --features:uirelays,harfbuzz
## nim r examples/uirelays_renderlist_100.nim
## Animated stress scene with 10 copies by default, using sdfy software rendering.
## -d:figdraw.nodes=N adjusts copies; -d:figdraw.runOnce runs one frame.
## Only positions animate by default. -d:figdraw.animateShapes=on animates sizes
## and shadows; -d:figdraw.animateCorners=on animates corners independently.
## -d:figdraw.imageCacheMiB=N sets the raster cache budget (default 128 MiB).
import std/[os, monotimes, times, strformat]

import figdraw
import figdraw/uirelays
from pkg/uirelays/backend as relayBackend import nil
from pkg/uirelays/screen as relayScreen import nil
from pkg/uirelays/input as relayInput import nil
import ./renderlist_100_common

const
  Copies {.intdefine: "figdraw.nodes".} = 10
  AnimateCorners {.booldefine: "figdraw.animateCorners".} = false
  AnimateShapes {.booldefine: "figdraw.animateShapes".} = false
  CacheMiB {.intdefine: "figdraw.imageCacheMiB".} = 128
  RunOnce {.booldefine: "figdraw.runOnce".} = false
  NoSleep {.booldefine: "figdraw.noSleep".} = true

proc runUirelaysRenderlist100*(windowTitle = "FigDraw uirelays") =
  setFigDataDir(getCurrentDir() / "data")
  relayBackend.initBackend()
  defer:
    relayInput.shutdown()
  discard relayScreen.createWindow(800, 600)
  relayScreen.setWindowTitle(&"{windowTitle} / RenderList {Copies}")
  let renderer = newUirelaysRenderer(maxCacheBytes = CacheMiB * 1024 * 1024)
  let imageContext = ImageLayerContext(renderer.ctx)
  let font = FigFont(typefaceId: loadTypeface("Ubuntu.ttf"), size: 18)
  let runOnce = RunOnce or getEnv("FIGDRAW_RUN_ONCE") == "1"
  var
    running = true
    frame = 0
    fpsFrames = 0
    fpsStart = getMonoTime()
    fpsText = "0.0 FPS"
    cachedText = ""
    cachedScale = 0'f32
    fpsLayout: GlyphArrangement
    treeMs = 0.0
    renderMs = 0.0
    cacheHits, cacheMisses = 0

  while running:
    var event: relayInput.Event
    while relayInput.pollEvent(event):
      case event.kind
      of relayInput.QuitEvent, relayInput.WindowCloseEvent:
        running = false
      of relayInput.KeyDownEvent:
        if event.key == relayInput.KeyEsc:
          running = false
      else:
        discard
    if running:
      let size = configureUirelaysScale(relayScreen.getWindowLayout())
      if size.x > 0 and size.y > 0:
        inc frame
        inc fpsFrames
        let treeStart = getMonoTime()
        var nodes = makeRenderTree(
          size.x,
          size.y,
          frame,
          Copies,
          AnimateCorners,
          AnimateShapes,
          includeBackground = false,
        )
        let elementCount = nodes[0.ZLevel].nodes.len
        let hud = rect(size.x - 192, 12, 180, 34)
        discard nodes.addRoot(
          0.ZLevel,
          Fig(
            kind: nkRectangle,
            screenBox: hud,
            fill: rgba(0, 0, 0, 155),
            corners: [8'u16, 8, 8, 8],
          ),
        )
        if cachedText != fpsText or cachedScale != figUiScale():
          fpsLayout = typeset(
            rect(0, 0, 160, 22),
            [(fs(font, rgba(255, 255, 255, 245).color), fpsText)],
            hAlign = Right,
            vAlign = Middle,
            minContent = false,
            wrap = false,
          )
          cachedText = fpsText
          cachedScale = figUiScale()
        discard nodes.addRoot(
          0.ZLevel,
          Fig(
            kind: nkText,
            screenBox: rect(hud.x + 10, hud.y + 6, 160, 22),
            fill: clearColor,
            textLayout: fpsLayout,
          ),
        )
        treeMs += (getMonoTime() - treeStart).inNanoseconds.float64 / 1e6

        let renderStart = getMonoTime()
        renderer.renderFrame(nodes, size)
        let cache = imageContext.imageCacheStats()
        cacheHits += cache.hits
        cacheMisses += cache.misses
        relayScreen.refresh()
        renderMs += (getMonoTime() - renderStart).inNanoseconds.float64 / 1e6

        let now = getMonoTime()
        let elapsed = (now - fpsStart).inNanoseconds.float64 / 1e9
        if elapsed >= 1:
          let fps = fpsFrames.float64 / elapsed
          fpsText = &"{fps:.1f} FPS"
          echo &"fps: {fps:.1f} | elems: {elementCount} | makeRenderTree avg(ms): {treeMs / fpsFrames.float64:.3f} | renderFrame + present avg(ms): {renderMs / fpsFrames.float64:.3f}"
          echo &"image cache: {cacheHits} hits / {cacheMisses} misses | {cache.entries} images / {cache.bytes.float64 / (1024 * 1024):.1f} MiB | native rects: {cache.nativeRects}"
          fpsFrames = 0
          fpsStart = now
          treeMs = 0
          renderMs = 0
          cacheHits = 0
          cacheMisses = 0
        if runOnce:
          running = false
      when not NoSleep:
        if running:
          relayInput.sleep(16)

when isMainModule:
  runUirelaysRenderlist100()
