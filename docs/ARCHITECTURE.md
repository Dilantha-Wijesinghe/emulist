# Architecture

Emulist is one Swift package with three products and a strict dependency
direction:

```
┌──────────────────────── Sources/Emulist (the SwiftUI app) ────────────────────────┐
│  EmulistApp ── ContentView: library · viewer · scopes · clip strip · palettes     │
│  State/     Workspace (single source of truth: clips, grade, undo, modes)        │
│             PlaybackController · Thumbnails · LibraryItems · WindowLayout        │
│  Views/     ViewerView (MTKView) · ScopesPanel · LookLibraryView · sheets        │
│  Palettes/  grading panel, built from ParameterSpecs (data)                       │
│  Controls/  knobs, wheels, jog wheel, switches · Support/ Theme, Tactile         │
└──────────────────┬─────────────────────────────────────┬────────────────────────┘
                   │ depends on (never the reverse)      │
┌──────────────────┴──── Sources/EmulistCore (no UI) ────┴────────────────────────┐
│  Color/     transfer functions, primaries, camera profiles, working space        │
│  Film/      FilmModel, stocks, LUT baking, .cube I/O, looks library, recipes      │
│  Grading/   GradeSettings, PrimaryGrade, HueVectors, ColorPipeline, presets       │
│  Render/    MetalContext, Shaders, FrameRenderer, Scopes, image readback          │
│  Video/     FrameReader, VideoExporter, MediaInfo · Project/ .emulist format      │
└──────────────────────────────────────┬──────────────────────────────────────────┘
                                       │
                   Sources/emulist-cli (headless renderer for development)
```

## Principles

1. **Color math in Swift, tested; the GPU interpolates.** `FilmModel`,
   `TransferFunction`, `ColorMath`, `PrimaryGrade` and `HueVectors` are plain
   Swift with unit tests. The renderer bakes them into tables (a 4096-entry 1D
   camera decode, a 65³ look LUT over a 20-stop log shaper) and the shaders
   sample those. The one exception is the primary grade: it also runs in a
   shader, so moving a wheel never rebakes anything, and `GPUGradeTests` holds
   the shader to `PrimaryGrade` within 0.002 stops.
2. **The grade is a value.** `GradeSettings` is `Codable` and `Equatable`.
   `ColorPipeline(settings)` is `Hashable` and doubles as the key of the baked
   LUT cache, so switching looks back and forth, or drawing thumbnails, never
   rebakes. Undo is a history of values (`EditHistory`).
3. **Data over code.** Film stocks, recipes and the grading panel's controls
   are tables (`BuiltInStocks`, `FujiXWeeklyRecipes`, `ParameterSpecs`).
   Adding one is a data change.
4. **One pipeline everywhere.** The viewer, thumbnails, the CLI, export and
   `.cube` export all render through `FrameRenderer` / `ColorPipeline`, so
   they agree. Effect sizes are fractions of the frame height against a
   1080-line reference, so a half-resolution preview matches the export.
5. **Design tokens.** `Theme` holds the palette, sizes and type styles: neutral
   greys that never bias color judgment, and one amber accent.

## How the image is made

```
decode (10-bit Y'CbCr, no OS color conversion)
  → camera decode: Apple Log / S-Log3 / V-Log / F-Log / F-Log2 → scene-linear
  → working space: linear Rec.2020, D65, mid grey 0.18; exposure and white balance (Bradford)
  → softness ("film resolution")
  → bloom + halation, added as light in scene-linear (half resolution, MPS Gaussian)
  → grain, as noise in log exposure (density), deterministic per frame
  → primary grade, on the GPU (log: wheels, contrast, color, push, printer lights)
  → look LUT (65³, baked in Swift; 33³ while a look control is dragged):
      hue vectors (log chroma, by hue) →
      film (negative → print → gamut map)  or  external LUT (via its camera encoding)
      → fade → encode
  → scopes, when shown: one GPU pass bins the displayed frame, each scope is drawn from the bins
```

- **Film model.** Per channel, in log exposure:
  1. Negative exposure and push.
  2. Inter-layer crosstalk and color separation (like dye-coupler interimage
     effects).
  3. An asymptotic negative shoulder, so highlights desaturate gracefully.
  4. Printing light balance.
  5. A print curve with toe, mid-grey contrast, a soft roll-off into paper
     white, and a black floor.
  6. Print saturation, Rec.2020 → 709, and soft gamut compression.

  Intensity blends the response *parameters* toward neutral, never pixels.
  That keeps hues stable.
- **Halation** comes from the red record only: in film, light that passes
  through the emulsion reflects off the base and re-exposes the red layer. It
  is added before the film curve, so it shows most on dark surroundings.
- **Grain** perturbs log exposure, so the print curve shapes it. It fades into
  pure black and paper white, and is strongest in the midtones. The grain
  canvas never drops below 1080 lines; smaller previews sample a filtered mip
  level.
- **External LUTs** (Fujifilm's, or imported `.cube` files) are reached
  through a colorimetric bridge: working space → the LUT's camera encoding
  (e.g. F-Log2 / F-Gamut). Colors at the edge of that gamut are first rolled
  softly back inside, so the LUT never clips them flat.

## Key flows

**Editing.** Every change goes through `Workspace`. A discrete change
(`edit`) is one undo step. A drag (`beginContinuousEdit` → `continuousEdit` →
`endContinuousEdit`) is one undo step per gesture, and its pointer events,
which arrive at up to 120 Hz, wait for the viewer's next display frame, so
SwiftUI updates at most once per frame. Knobs and wheels are `Equatable`, so
only the control that changed redraws.

**The viewer.** `ViewerCoordinator` is the `MTKView` delegate. It redraws
when its `RenderState` (frame, grade, size, quality, compare mode) changes.
The **Auto** preview renders at half resolution while a control is dragged
and at full the moment it is let go. While a look control or hue vector is
dragged, the look LUT is baked on the 33³ draft grid.

**Scopes.** After each render, one compute pass (`scope_analyze`) bins the
displayed frame into a 1024-wide grid, and each scope view draws from those
bins into its own fresh drawable. Hidden scopes cost nothing.

**Thumbnails.** `ThumbnailRenderer` (an actor) renders the library's and the
clip strip's thumbnails from the current frame, off the main thread, on a
coarser LUT grid and without grain or glow. Only thumbnails whose grade
changed are re-rendered.

**Export.** `VideoExporter` reads the clip in timestamp order with
`FrameReader`, renders each frame with its own `FrameRenderer` at full
quality and writes with AVFoundation (ProRes 422 HQ, HEVC 10-bit or H.264,
with audio). `ExportNaming` picks a free file name, so an
export never replaces a file.

**Projects.** An `.emulist` project is JSON (`EmulistProject`): each clip's
footage reference (with a bookmark, for relinking), grade and snapshots.
Grades decode tolerantly, so projects from earlier versions keep opening.

## Sources and measurements

- **Apple Log** constants come from Apple's white paper, via colour-science.
  18% grey encodes to 0.4883, which a test checks. Clips declare Apple Log
  through `kCMFormatDescriptionExtension_LogTransferFunction`.
- **Apple Log 2** (iPhone 17 Pro) uses an unpublished gamut. Emulist detects it
  and says so, rather than inventing constants.
- **Fujifilm's LUTs** take F-Log2 / F-Gamut input (F-Gamut uses the BT.2020
  primaries) and output BT.709, per Fujifilm's "Overview of 3D LUTs for
  F-Log2". The F-Log2 constants come from Fujifilm's data sheet via
  colour-science; 18% grey encodes to 0.3910, which a test checks.
- **Measured on macOS 26:** ColorSync's `itur_709` color space decodes with
  gamma 2.4, while AVFoundation decodes Rec.709 video with gamma ≈ 1.961. That
  gap is the source of the "QuickTime gamma shift", and it is why there are two
  output encodings.
- **Performance** (M3 Pro, UHD): the full pipeline with every effect takes
  about 13 ms a frame, 3 ms at half resolution. A 65³ look bake takes about
  15 ms, a 33³ draft about 2 ms. While a knob or wheel is dragged on a UHD
  clip, the viewer redraws about 57–60 times a second at Auto preview (47–52
  at Full). Export runs at about 55 fps to ProRes.

## Decisions

The reasoning behind the larger choices is recorded in [docs/adr](adr).
