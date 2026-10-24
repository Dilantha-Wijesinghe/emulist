# Emulist

*Digital footage. Analog soul.*

A native macOS film emulation and color grading app for LOG footage (Swift 6, SwiftUI, Metal, AVFoundation).
Drop in a clip, pick a film, refine, and export.

## Build & run

Only the Swift toolchain is needed (Command Line Tools; no Xcode). Shaders compile at runtime.

```sh
scripts/build-app.sh --open      # builds build/Emulist.app (release) and launches it
scripts/test.sh                  # unit tests (Swift Testing)
```

Requires macOS 14.2+ on Apple Silicon.

## Using it

The window is laid out like Resolve's color page: looks on the left, the viewer in the middle, grading palettes
along the bottom.

1. **Drop footage** onto the window (or ⌘O). Apple Log is detected from the clip's metadata. If the file doesn't
   declare its LOG curve, Emulist asks which profile it was shot in.
2. **Pick a look** in the library. Every thumbnail is your current frame, rendered live. Emulist's own film stocks
   are there from the start; *Download from Fujifilm* adds Fujifilm's official film simulations (see below).
3. **Grade with the primaries** (bottom left), which work *under* the look like grading under a LUT in Resolve,
   so the film's curve keeps every correction graceful:
   - **Lift, Gamma, Gain, Offset wheels.** Drag anywhere on a wheel to move its puck toward a hue (relative and
     slow for precision; ⌥ finer, ⇧ faster). The ribbed thumbwheel underneath is the master level. Type exact
     R G B values in the readouts.
   - **Contrast & Pivot, Saturation, Color Boost** (lifts muted colors, spares already-vivid ones), **Density**
     (subtractive saturation: colors get deeper and richer, like denser dye; neutrals untouched), **Shadows**,
     **Highlights**, plus **Exposure, Temp, Tint** (applied as light, before everything).
4. **Shape the film** in the rack (bottom right): intensity, push/pull and fade; printer lights; grain, halation
   and bloom, each with its own power switch.
5. **Compare** with the two toolbar buttons: **Before / After** latches the ungraded image on and off (`B`), and **Split** shows a wipe you can drag (`⇧B`).
6. **Export** (⌘E): ProRes 422 HQ, HEVC 10-bit or H.264, with audio.
7. **Save** the grade as an `.emulist` project (⌘S). Saved projects autosave, and the footage is never modified.

**Every control works the same way.** Drag it (or scroll over it on a trackpad); hold ⌥ for fine control. It
clicks into its default with a haptic detent on Force Touch trackpads. Double-click to reset, or click the value
to type one. Each drag or scroll burst is one undo step.

| Shortcut | Action |
|---|---|
| Space | Play / pause |
| ← / → | Previous / next frame |
| B, ⇧B | Before / after, split compare |
| ⌘O, ⌘S, ⇧⌘S, ⌘E | Open, save, save as, export |
| ⌘Z, ⇧⌘Z | Undo, redo (each slider drag is one step) |

### Output encoding

Both options show the same image in the viewer. They differ in which players reproduce it exactly:

- **Rec.709 · Apple Devices** (default). Apple's video stack (QuickTime, Photos, Safari, iPhone) decodes
  Rec.709 video with an effective gamma of about 1.961. Emulist encodes for that, so your export looks like the viewer
  on Apple screens.
- **Rec.709 · Gamma 2.4**. This is the broadcast and DaVinci Resolve convention. It looks lighter in QuickTime.

## The film looks

| Stock | Character |
|---|---|
| Solstice 400 | Warm, soft color negative. Honest skin, golden highlights, open shadows. |
| Nocturne 800 | Cinema negative on print. Teal shadows, dense warm mids, restrained color. |
| Aurora 50 | Clean daylight cinema stock. Fine grain, natural and rich. |
| Golden 200 | Nostalgic consumer film. Buttery yellows and warm blacks. |
| Verdant 200 | Cool everyday film. Emerald greens and clean skin. |
| Chrome 100 | Slide film. Deep blacks, vivid separation. |
| Silver 400 | Panchromatic black and white on a faintly warm paper. |

These are original creative interpretations, not measurements of commercial stocks. A stock is plain data
(`FilmStock` is `Codable`), so adding one is a new entry in `BuiltInStocks.swift`. No UI code changes.

### Fujifilm film simulations

*Download from Fujifilm* in the library (or `emulist-cli install-fujifilm`) fetches Fujifilm's free official
LUT package (GFX ETERNA 55, 46 MB) from fujifilm-x.com. It installs the ten F-Log2 film simulations: Provia,
Velvia, Astia, Classic Chrome, Reala Ace, Pro Neg. Std, Classic Neg., Eterna, Eterna Bleach Bypass and Acros.
They land in `~/Library/Application Support/Emulist/Looks/Fujifilm` and are never bundled with Emulist.

Your footage reaches them through a colorimetric bridge: camera LOG → scene-linear Rec.2020 (= F-Gamut) → F-Log2.
Each simulation then renders as Fujifilm designed it, with the primaries, grain, halation and bloom still
applied around it. Only colors at the very edge of F-Gamut, or pushed beyond it by the grade, are first rolled
softly back inside, so the LUT never clips them flat. Intensity blends the simulation with Emulist's neutral print. Extreme saturation on
an already-vivid look (e.g. Velvia at 200%) can still clip inside Fujifilm's LUT.

### Your own LUTs

Import any 3D `.cube` LUT with **+** in the library, or drop it on the window. Emulist reads the LUT's expected
input from its name: `F-Log2`, `F-Log`, `S-Log3` or `V-Log`, and otherwise Apple Log. It treats the LUT's output
as Rec.709 for a gamma 2.4 display, which is the convention for camera and creative LUTs. Imported LUTs live in
`…/Emulist/Looks/Imported`.

## How the image is made

```
decode (10-bit Y'CbCr, no OS color conversion)
  → camera decode: Apple Log / S-Log3 / V-Log → scene-linear
  → working space: linear Rec.2020, D65, mid grey 0.18; exposure and white balance (Bradford)
  → softness ("film resolution")
  → bloom + halation, added as light in scene-linear (half resolution, MPS Gaussian)
  → grain, as noise in log exposure (density), deterministic per frame
  → look LUT (65³, baked in Swift):
      primary grade (log: wheels, contrast, color, printer lights)
      → film (negative → print → gamut map)  or  external LUT (via its camera encoding)
      → fade → encode
```

- **All color math lives in Swift** (`FilmModel`, `TransferFunction`, `ColorMath`) and is unit-tested. The GPU
  only interpolates the baked tables. Camera decode is a 4096-entry 1D table, and the film is a 3D LUT over a log
  shaper covering 20 stops.
- **Film model.** Per channel, in log exposure:
  1. Negative exposure and push.
  2. Inter-layer crosstalk and color separation (like dye-coupler interimage effects).
  3. An asymptotic negative shoulder, so highlights desaturate gracefully.
  4. Printing light balance.
  5. A print curve with toe, mid-grey contrast, a soft roll-off into paper white, and a black floor.
  6. Print saturation, Rec.2020 → 709, and soft gamut compression.

  Intensity blends the response *parameters* toward neutral, never pixels. That keeps hues stable.
- **Halation** comes from the red record only. In film, light that passes through the emulsion reflects off the
  base and re-exposes the red layer. It is added before the film curve, so it shows most on dark surroundings.
- **Grain** perturbs log exposure, so the print curve shapes it. It fades naturally into pure black and paper
  white, and it is strongest in the midtones.
- **Resolution independence.** Effect sizes are fractions of frame height, against a 1080-line reference. The
  grain canvas never drops below 1080 lines; smaller previews sample a filtered mip level. Preview and
  full-resolution export therefore match.
- **Performance** (M3 Pro). The full UHD pipeline with every effect takes about 13 ms per frame. Half
  resolution takes about 3 ms. A LUT re-bake takes about 13 ms.

## Research notes

These came from the DaVinci Resolve manual, Apple's SDK and the camera makers' published documentation.

- **Apple Log** constants come from Apple's white paper, via colour-science. 18% grey encodes to 0.4883, which a
  test checks. Clips declare Apple Log through `kCMFormatDescriptionExtension_LogTransferFunction`.
- **Apple Log 2** (iPhone 17 Pro) uses an unpublished gamut. Emulist detects it and says so, rather than inventing
  constants.
- **Fujifilm's LUTs** take F-Log2 / F-Gamut input (F-Gamut uses the BT.2020 primaries) and output BT.709, per
  Fujifilm's "Overview of 3D LUTs for F-Log2". The F-Log2 constants come from Fujifilm's data sheet via
  colour-science; 18% grey encodes to 0.3910, which a test checks.
- **Measured on macOS 26:**
  - ColorSync's `itur_709` color space decodes with gamma 2.4.
  - AVFoundation decodes Rec.709 video with gamma ≈ 1.961.

  That gap is the source of the "QuickTime gamma shift", and it is why there are two output encodings.

## Developer tools

`emulist-cli` renders headlessly with the same engine:

```sh
swift build -c release --product emulist-cli
CLI=.build/release/emulist-cli
scripts/make-test-clip.sh photo.jpg test.mov                 # synthetic Apple Log ProRes from any photo
$CLI tag-apple-log test.mov tagged.mov                       # declare Apple Log like an iPhone does
$CLI sheet tagged.mov sheet.png --scale 0.25                 # neutral + every stock on one frame
$CLI render tagged.mov frame.png --stock nocturne-800 --time 1
$CLI export tagged.mov out.mp4 --codec hevc --stock aurora-50
$CLI bench tagged.mov                                        # LUT bake and per-frame GPU time
$CLI install-fujifilm                                        # download Fujifilm's film simulations
$CLI looks                                                   # list every look and its id
$CLI render tagged.mov f.png --stock "lut:Fujifilm/FLog2_to_ETERNA_65grid_V.1.00.cube" --density 40
```

Any grade setting can be overridden numerically from the command line, e.g. `--colorBoost 40` or `--gain.y 0.3`.

## Layout

```
Sources/EmulistCore   color science, film model, Metal pipeline, video I/O, project model (no UI)
Sources/Emulist       SwiftUI app: workspace state, viewer, look library, palettes, analog controls, export
Sources/emulist-cli   headless rendering, test footage, benchmarks
Tests/                Swift Testing suites
scripts/              build-app.sh, test.sh, make-test-clip.sh, make-icon.swift
```

## Roadmap

- Waveform / vectorscope
- Custom user stocks (JSON)
- Curves and qualifiers
- Gate weave, film breath and dust
- Canon Log 3
- Apple Log 2, once Apple publishes it
