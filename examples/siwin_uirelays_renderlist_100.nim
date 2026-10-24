## Siwin window/events with native uirelays composition and Harfbuzzy text.
## nim r examples/siwin_uirelays_renderlist_100.nim
## -d:figdraw.nodes=N; -d:figdraw.animateCorners=on; -d:figdraw.noSleep=off;
## -d:figdraw.animateShapes=on animates sizes/shadows; -d:figdraw.imageCacheMiB=N.
## -d:figdraw.runOnce or FIGDRAW_RUN_ONCE=1 runs one frame.
import ./uirelays_renderlist_100

when isMainModule:
  runUirelaysRenderlist100("FigDraw siwin + uirelays")
