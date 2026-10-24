## Native window: nim r examples/uirelays_renderlist.nim
## siwin window: nim r -d:features.uirelays.siwin examples/uirelays_renderlist.nim
## Windy window: nim r -d:features.uirelays.figDrawWindy examples/uirelays_renderlist.nim
## Run atlas install --keepFeatures --feature=figdraw.uirelays first.
import std/os
import figdraw
import figdraw/uirelays
from pkg/uirelays/backend as relayBackend import nil
from pkg/uirelays/screen as relayScreen import nil
from pkg/uirelays/input as relayInput import nil
import ./software_scene

proc runUirelaysExample*(initBackend: proc() {.nimcall.} = relayBackend.initBackend) =
  initBackend()
  defer:
    relayInput.shutdown()
  let initial = relayScreen.createWindow(560, 360)
  relayScreen.setWindowTitle("FigDraw software + uirelays")
  let renderer = newUirelaysRenderer()
  var metrics: relayScreen.FontMetrics
  var nativeFont = relayScreen.openFont("", relayScreen.scaled(initial, 18), metrics)
  defer:
    relayScreen.closeFont(nativeFont)
  var scene: SoftwareSceneCache
  var fontUiScale = initial.uiScale
  var running = true
  var needsRedraw = true
  let runOnce = getEnv("FIGDRAW_RUN_ONCE") == "1"
  while running:
    if needsRedraw:
      let layout = relayScreen.getWindowLayout()
      let size = configureUirelaysScale(layout)
      needsRedraw = false
      if size.x <= 0 or size.y <= 0:
        continue
      if fontUiScale != layout.uiScale:
        relayScreen.closeFont(nativeFont)
        nativeFont = relayScreen.openFont("", relayScreen.scaled(layout, 18), metrics)
        fontUiScale = layout.uiScale
      var nodes = scene.softwareScene(size.x, size.y)
      renderer.renderFrame(nodes, size)
      # The native text engine remains available for overlays. Shaped FigDraw
      # text in the scene retains glyph IDs, selection geometry and transforms.
      discard relayScreen.drawText(
        nativeFont,
        28,
        22,
        "Native system font",
        relayScreen.color(30, 43, 70),
        relayScreen.color(240, 243, 250),
      )
      relayScreen.refresh()
      if runOnce:
        break
    var event: relayInput.Event
    if relayInput.waitEvent(event):
      while true:
        case event.kind
        of relayInput.QuitEvent, relayInput.WindowCloseEvent:
          running = false
        of relayInput.KeyDownEvent:
          if event.key == relayInput.KeyEsc:
            running = false
        of relayInput.NoEvent, relayInput.WindowResizeEvent,
            relayInput.WindowMetricsEvent:
          needsRedraw = true
        else:
          discard
        if not running or not relayInput.pollEvent(event):
          break

when isMainModule:
  runUirelaysExample()
