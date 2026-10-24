import std/[os, unittest]

when defined(features.figdraw.uirelays):
  import figdraw
  from pkg/uirelays/screen as relayScreen import nil
  from pkg/uirelays/input as relayInput import nil
  from pkg/uirelays/coords as relayCoords import nil
  import ../examples/uirelays_renderlist

  var
    layout: relayScreen.ScreenLayout
    batches: seq[seq[relayInput.Event]]
    batch, nextEvent, frames, sleeps, closedFonts, shutdowns: int
    waits: seq[int]

  proc deliver(event: var relayInput.Event, value: relayInput.Event) =
    event = value
    if event.kind in {relayInput.WindowMetricsEvent, relayInput.WindowResizeEvent}:
      layout.width = event.x
      layout.height = event.y
      if event.kind == relayInput.WindowMetricsEvent:
        layout.scaleX = event.scaleX
        layout.scaleY = event.scaleY
        layout.uiScale = event.uiScale

  proc poll(event: var relayInput.Event, flags: set[relayInput.InputFlag]): bool =
    if batch > 0 and nextEvent < batches[batch - 1].len:
      deliver(event, batches[batch - 1][nextEvent])
      inc nextEvent
      return true

  proc wait(
      event: var relayInput.Event, timeout: int, flags: set[relayInput.InputFlag]
  ): bool =
    waits.add(timeout)
    if batch >= batches.len:
      raise newException(ValueError, "The example waited past the scripted close event")
    deliver(event, batches[batch][0])
    inc batch
    nextEvent = 1
    true

  proc initialize() =
    relayScreen.windowRelays.createWindow = proc(
        value: var relayScreen.ScreenLayout, icon: pointer, iconLen: int
    ) =
      value = layout
    relayScreen.windowRelays.getWindowLayout = proc(): relayScreen.ScreenLayout =
      layout
    relayScreen.windowRelays.setWindowTitle = proc(title: string) =
      discard
    relayScreen.windowRelays.refresh = proc() =
      inc frames
    relayScreen.fontRelays.openFont = proc(
        path: string,
        size: int,
        style: relayScreen.FontStyles,
        metrics: var relayScreen.FontMetrics,
    ): relayScreen.Font =
      relayScreen.Font(1)
    relayScreen.fontRelays.closeFont = proc(font: relayScreen.Font) =
      inc closedFonts
    relayScreen.fontRelays.drawText = proc(
        font: relayScreen.Font, x, y: int, text: string, fg, bg: relayScreen.Color
    ): relayScreen.TextExtent =
      relayScreen.TextExtent()
    relayScreen.drawRelays.drawRGBA = proc(
        pixels: ptr UncheckedArray[uint32],
        w, h: int,
        dst: relayCoords.Rect,
        format: relayScreen.RGBAFormat,
    ): bool =
      true
    relayInput.inputRelays.pollEvent = poll
    relayInput.inputRelays.waitEvent = wait
    relayInput.inputRelays.sleep = proc(ms: int) =
      inc sleeps
    relayInput.inputRelays.shutdown = proc() =
      inc shutdowns

  suite "uirelays example event loop":
    setup:
      let savedWindow = relayScreen.windowRelays
      let savedFont = relayScreen.fontRelays
      let savedDraw = relayScreen.drawRelays
      let savedInput = relayInput.inputRelays
      let savedScale = figUiScale()
      let oldRunOnce = getEnv("FIGDRAW_RUN_ONCE")
      putEnv("FIGDRAW_RUN_ONCE", "")
      layout = relayScreen.ScreenLayout(
        width: 560, height: 360, scaleX: 1, scaleY: 1, uiScale: 100
      )
      batch = 0
      nextEvent = 0
      frames = 0
      sleeps = 0
      closedFonts = 0
      shutdowns = 0
      waits.setLen(0)
    teardown:
      relayScreen.windowRelays = savedWindow
      relayScreen.fontRelays = savedFont
      relayScreen.drawRelays = savedDraw
      relayInput.inputRelays = savedInput
      setFigUiScale(savedScale)
      if oldRunOnce.len == 0:
        delEnv("FIGDRAW_RUN_ONCE")
      else:
        putEnv("FIGDRAW_RUN_ONCE", oldRunOnce)

    test "idle input blocks, while batched invalidations cause one redraw":
      batches = @[
        @[
          relayInput.Event(kind: relayInput.MouseMoveEvent),
          relayInput.Event(kind: relayInput.WindowFocusGainedEvent),
          relayInput.Event(kind: relayInput.KeyDownEvent, key: relayInput.KeyA),
        ],
        @[
          relayInput.Event(kind: relayInput.NoEvent),
          relayInput.Event(kind: relayInput.WindowResizeEvent, x: 600, y: 400),
          relayInput.Event(
            kind: relayInput.WindowMetricsEvent,
            x: 600,
            y: 400,
            scaleX: 1,
            scaleY: 1,
            uiScale: 200,
          ),
        ],
        @[relayInput.Event(kind: relayInput.QuitEvent)],
      ]
      runUirelaysExample(initialize)
      check frames == 2
      check waits == @[-1, -1, -1]
      check sleeps == 0
      check closedFonts == 2
      check shutdowns == 1

    test "zero-sized windows wait until restored without drawing empty frames":
      batches = @[
        @[relayInput.Event(kind: relayInput.WindowResizeEvent, x: 0, y: 0)],
        @[relayInput.Event(kind: relayInput.WindowResizeEvent, x: 700, y: 450)],
        @[relayInput.Event(kind: relayInput.WindowCloseEvent)],
      ]
      runUirelaysExample(initialize)
      check frames == 2
      check waits.len == 3
      check sleeps == 0

    test "run-once draws and exits before waiting":
      batches = @[]
      putEnv("FIGDRAW_RUN_ONCE", "1")
      runUirelaysExample(initialize)
      check frames == 1
      check waits.len == 0
      check closedFonts == 1
      check shutdowns == 1
else:
  suite "uirelays example event loop":
    test "requires Atlas uirelays feature":
      skip()
