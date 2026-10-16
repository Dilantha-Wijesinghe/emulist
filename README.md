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

1. **Drop footage** onto the window (or ⌘O). Apple Log is detected from the clip's metadata. If the file doesn't
   declare its LOG curve, Emulist asks which profile it was shot in.
2. **Pick a film** from the strip under the viewer. Every thumbnail is your current frame, rendered live.
3. **Refine** in the inspector:
   - Input: exposure and white balance, applied as light, before the film.
   - Film: intensity, push/pull, contrast, saturation, highlight roll-off and fade.
   - Printer lights, grain & texture, halation and bloom.
   Drag a slider to adjust it (hold ⌥ for fine control). Double-click it to reset.
4. **Compare** with the toolbar control: graded, split wipe (drag the handle), or before. `B` toggles before.
5. **Export** (⌘E): ProRes 422 HQ, HEVC 10-bit or H.264, with audio.
6. **Save** the grade as an `.emulist` project (⌘S). Saved projects autosave, and the footage is never modified.

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

## How the image is made

```
decode (10-bit Y'CbCr, no OS color conversion)
  → camera decode: Apple Log / S-Log3 / V-Log → scene-linear
  → working space: linear Rec.2020, D65, mid grey 0.18; exposure and white balance (Bradford)
  → softness ("film resolution")
  → bloom + halation, added as light in scene-linear (half resolution, MPS Gaussian)
  → grain, as noise in log exposure (density), deterministic per frame
  → film LUT (65³, baked in Swift): negative → printer lights → print → gamut map → encode
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
```

## Layout

```
Sources/EmulistCore   color science, film model, Metal pipeline, video I/O, project model (no UI)
Sources/Emulist       SwiftUI app: workspace state, viewer, inspector, stock strip, export
Sources/emulist-cli   headless rendering, test footage, benchmarks
Tests/                Swift Testing suites
scripts/              build-app.sh, test.sh, make-test-clip.sh, make-icon.swift
```

## Roadmap

- Waveform / vectorscope
- Custom user stocks (JSON) and `.cube` import
- Gate weave, film breath and dust
- Canon Log 3 and F-Log2
- Apple Log 2, once Apple publishes it
