## Text measured and drawn by the platform, through uirelays' font relays.
##
## Fonts are opened from the typeface's file at their device pixel size; each
## glyph image is the platform's own rendering of its rune. The relays are not
## thread-safe, and glyphs are rasterized on the render thread while text is
## laid out on the app thread, so every call goes through `relayLock`.

import std/[hashes, locks, math, os, tables, unicode]

import pkg/pixie
from pkg/uirelays/screen as relays import nil
import pkg/uirelays/screen except Image, Font, Color

import ../fonttypes
import ../imgutils
import ../shared
import ../typefaces

when defined(windows):
  import pkg/uirelays/drivers/winapi_driver
else:
  {.error: "the uirelays text backend needs a driver with `renderText`; " &
    "only the winapi driver has one".}

type RelayFont* = object
  handle*: relays.Font
  metrics*: FontMetrics ## In device pixels.

var
  relayLock: Lock
  relayFonts: Table[(TypefaceId, int), RelayFont]
  relayFontPaths: Table[TypefaceId, string]

relayLock.initLock()
initWinapiFontRelays()

proc devicePixelSize*(font: FigFont, scale: float32): int =
  max(1, round(font.size * scale).int)

proc typefacePath(id: TypefaceId): string =
  ## A file the platform can open: the one the typeface was loaded from, or
  ## a copy of the bytes it was registered with.
  if id in relayFontPaths:
    return relayFontPaths[id]
  let source = getTypefaceSource(id)
  if source.name.isAbsolute and fileExists(source.name):
    result = source.name
  else:
    let dir = getTempDir() / "figdraw-uirelays-fonts"
    createDir(dir)
    let ext =
      case source.kind
      of OTF: ".otf"
      else: ".ttf"
    result = dir / ($cast[uint](hash(source.data)) & ext)
    if not fileExists(result) or getFileSize(result) != source.data.len:
      writeFile(result, source.data)
  relayFontPaths[id] = result

proc relayFontLocked(typefaceId: TypefaceId, pixelSize: int): RelayFont =
  let key = (typefaceId, pixelSize)
  if key notin relayFonts:
    var metrics = FontMetrics()
    let handle = openFont(typefacePath(typefaceId), pixelSize, metrics)
    if handle.int == 0:
      raise newException(ValueError, "uirelays could not open the typeface")
    relayFonts[key] = RelayFont(handle: handle, metrics: metrics)
  relayFonts[key]

proc relayFont*(font: FigFont, scale: float32): RelayFont =
  {.cast(gcsafe).}:
    withLock relayLock:
      result = relayFontLocked(font.typefaceId, font.devicePixelSize(scale))

proc relayTextWidth*(font: RelayFont, text: string): int =
  ## Device pixel width of `text`, as the platform shapes it.
  {.cast(gcsafe).}:
    withLock relayLock:
      result = measureText(font.handle, text).w

proc renderUirelaysGlyph*(
    imageId: ImageId, fontId: FontId, rune: Rune, upload = true
): Image {.discardable.} =
  ## Renders one rune as the platform draws it: white on transparency, its
  ## top at the font's ascent above the baseline, its width the advance.
  let font = getFigFont(fontId)
  var
    pixels: seq[uint32]
    extent: TextExtent
  {.cast(gcsafe).}:
    withLock relayLock:
      let relay = relayFontLocked(font.typefaceId, font.devicePixelSize(figUiScale()))
      extent = renderText(
        relay.handle, $rune, relays.Color(r: 255, g: 255, b: 255, a: 255), pixels
      )
  if extent.w <= 0 or extent.h <= 0:
    return nil

  result = newImage(extent.w, extent.h)
  for i, p in pixels:
    result.data[i] = rgbx(
      uint8((p shr 16) and 0xFF), uint8((p shr 8) and 0xFF), uint8(p and 0xFF),
      uint8(p shr 24),
    )
  if upload:
    loadGlyphImage(imageId, fontId, font.typefaceId, result)
