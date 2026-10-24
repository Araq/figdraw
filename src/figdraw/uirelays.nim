## Present software-rendered FigDraw scenes through an installed uirelays driver.
##
## Initialize the uirelays driver and window first. This module imports only the
## platform-independent relays, so the application owns window/event lifetime.
## Use uirelays' native driver or its FigDraw + siwin / Windy driver. The latter
## retains its regular GPU renderer, avoiding recursive software presentation.
## Call uirelays `refresh()` after rendering and after any native text overlays.

import pkg/[chroma, pixie]
from pkg/uirelays/screen as relayScreen import nil
from pkg/uirelays/coords as relayCoords import nil
import ./figrender
import ./software/context

export context

proc presentUirelaysImage*(
    image: Image, background = rgba(255, 255, 255, 255), x = 0, y = 0
): bool =
  ## Blits at one source pixel per driver coordinate. Transparent pixels are
  ## composited against an opaque background because blitRGBA ignores alpha.
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
  relayScreen.blitRGBA(
    cast[ptr UncheckedArray[uint32]](addr pixels[0]),
    image.width,
    image.height,
    relayCoords.rect(x, y, image.width, image.height),
  )

proc newUirelaysContext*(background = rgba(255, 255, 255, 255)): SoftwareContext =
  ## Creates a software context which blits at endFrame. Initialize a uirelays
  ## window before the first frame. A rejected blit raises ValueError.
  if background.a != 255:
    raise newException(ValueError, "Presentation background must be opaque")
  newSoftwareContext(
    presenter = proc(image: Image) =
      if not presentUirelaysImage(image, background):
        raise newException(ValueError, "The uirelays driver cannot present RGBA pixels")
  )

proc newUirelaysRenderer*(
    background = rgba(255, 255, 255, 255)
): FigRenderer[NoRendererBackendState] =
  ## Uses the normal FigDraw scene/glyph APIs and presents via uirelays.
  newFigRenderer(newUirelaysContext(background))
