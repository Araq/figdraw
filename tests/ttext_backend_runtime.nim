import std/[hashes, os, sequtils, unicode, unittest]

import figdraw/common/[fonttypes, fontutils, fontglyphs, shared, typefaces]

when runtimeTextBackends:
  const expectHarfbuzzMissing {.booldefine: "figdraw.expectHarfbuzzMissing".} = false

  proc fixtureFont(): FigFont =
    let path = figDataDir() / "Ubuntu.ttf"
    FigFont(typefaceId: loadTypeface("Ubuntu.ttf", readFile(path), TTF), size: 32)

  proc layout(font: FigFont): GlyphArrangement =
    typesetForMeasurement(
      rect(0, 0, 300, 80), [(fs(font), "office")], minContent = false, wrap = false
    )

  suite "automatic text backend":
    test "uses HarfBuzz when both native libraries are available":
      let expected =
        if expectHarfbuzzMissing: TextBackendKind.Pixie else: TextBackendKind.Harfbuzzy
      check selectedTextBackend() == expected
      let arrangement = fixtureFont().layout()
      check arrangement.glyphCount() > 0
      for glyph in arrangement.glyphs():
        check glyph.generateGlyph(force = true, upload = false) != nil
        break

  suite "runtime text backends":
    setup:
      setTextBackend(TextBackendKind.Pixie)

    test "reports the selected backend and actual availability":
      check selectedTextBackend() == TextBackendKind.Pixie
      check textBackend() == "pixie"
      check textBackendFeatures() == @["pixie-typesetting", "pixie-rasterization"]
      check textBackendAvailable(TextBackendKind.Pixie)
      check textBackendAvailable(TextBackendKind.Harfbuzzy) == not expectHarfbuzzMissing
      check textBackendAvailable(TextBackendKind.Hybrid) == not expectHarfbuzzMissing

    test "unavailable HarfBuzz leaves Pixie usable":
      if expectHarfbuzzMissing:
        check not trySetTextBackend(TextBackendKind.Harfbuzzy)
        expect ValueError:
          setTextBackend(TextBackendKind.Harfbuzzy)
        check textBackend() == "pixie"
        let arrangement = fixtureFont().layout()
        check arrangement.glyphCount() > 0
        for glyph in arrangement.glyphs():
          check glyph.rasterBackend == GlyphRasterBackend.Pixie
          check glyph.generateGlyph(force = true, upload = false) != nil

    test "switching preserves old layouts and separates their raster caches":
      if not expectHarfbuzzMissing:
        let font = fixtureFont()
        let pixieLayout = font.layout()
        let pixieGlyph = toSeq(pixieLayout.glyphs())[0]
        let pixieHash = pixieGlyph.hash()

        check trySetTextBackend(TextBackendKind.Harfbuzzy)
        check textBackend() == "harfbuzzy"
        check "glyph-id-rasterization" in textBackendFeatures()
        let shapedLayout = font.layout()
        let shapedGlyph = toSeq(shapedLayout.glyphs())[0]
        let shapedHash = shapedGlyph.hash()
        check pixieLayout.contentHash != shapedLayout.contentHash
        check shapedLayout.arrangedGlyphs.anyIt(
          it.source.runeEnd - it.source.runeStart > 1
        )
        check pixieGlyph.rasterBackend == GlyphRasterBackend.Pixie
        check shapedGlyph.rasterBackend == GlyphRasterBackend.Harfbuzz
        check pixieHash != shapedHash
        check pixieGlyph.hash() == pixieHash
        check pixieGlyph.generateGlyph(force = true, upload = false) != nil

        setTextBackend(TextBackendKind.Pixie)
        check shapedGlyph.hash() == shapedHash
        check shapedGlyph.generateGlyph(force = true, upload = false) != nil
        check font.layout().contentHash == pixieLayout.contentHash

    test "source spans and explicit placement follow the selected backend":
      if not expectHarfbuzzMissing:
        let font = fixtureFont()
        let source = initUtf8Runes("office")
        let runs = [StyledTextRun(byteEnd: 6, runeEnd: 6, styleId: TextStyleId(0))]
        let styles = [fs(font)]
        let box = rect(0, 0, 300, 80)
        let pixieSource = typesetSourceSpansForMeasurement(
          box, source, runs, styles, minContent = false, wrap = false
        )
        let pixiePlaced = placeGlyphs(styles[0], [(Rune(65), vec2(0, 0))])
        setTextBackend(TextBackendKind.Harfbuzzy)
        let shapedSource = typesetSourceSpansForMeasurement(
          box, source, runs, styles, minContent = false, wrap = false
        )
        let shapedPlaced = placeGlyphs(styles[0], [(Rune(65), vec2(0, 0))])
        check shapedSource.contentHash != pixieSource.contentHash
        check shapedPlaced.contentHash != pixiePlaced.contentHash
        check shapedPlaced.arrangedGlyphs[0].rasterBackend == GlyphRasterBackend.Harfbuzz
        check pixiePlaced.arrangedGlyphs[0].rasterBackend == GlyphRasterBackend.Pixie

    test "hybrid retains Pixie rasterization while using shaped layout":
      if not expectHarfbuzzMissing:
        let font = fixtureFont()
        setTextBackend(TextBackendKind.Hybrid)
        let arrangement = font.layout()
        check textBackend() == "hybrid"
        check "pixie-rasterization" in textBackendFeatures()
        check arrangement.arrangedGlyphs.anyIt(
          it.source.runeEnd - it.source.runeStart > 1
        )
        for glyph in arrangement.glyphs():
          check glyph.rasterBackend == GlyphRasterBackend.Pixie
else:
  suite "fixed text backend":
    test "only the compiled backend can be selected":
      check trySetTextBackend(selectedTextBackend())
      let other =
        if selectedTextBackend() == TextBackendKind.Pixie:
          TextBackendKind.Harfbuzzy
        else:
          TextBackendKind.Pixie
      check not trySetTextBackend(other)
      expect ValueError:
        setTextBackend(other)
