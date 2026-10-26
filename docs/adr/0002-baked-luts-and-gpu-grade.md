# 2. Color math in Swift, baked into LUTs; the primary grade on the GPU

- Status: accepted
- Date: 2026-10-24

## Context

The film model is a chain of per-channel curves, crosstalk matrices and gamut
mapping. Writing it twice, in Swift and in Metal, would let the two drift, and
shader math is hard to test. But rebaking a 65³ LUT (about 15 ms) on every
knob tick made grading drag.

## Decision

- All color math is Swift, unit-tested, and baked into tables the GPU samples:
  a 1D camera decode and a 3D look LUT over a 20-stop log shaper.
- The baked LUT is keyed by `ColorPipeline`, a `Hashable` value of everything
  it depends on, and cached.
- The primary grade (wheels, contrast, saturation, printer lights…) is the one
  exception: it runs in the shader before the LUT, and `GPUGradeTests` holds it
  to the Swift `PrimaryGrade` within 0.002 stops.
- Controls that do change the LUT (intensity, fade, hue vectors) bake a 33³
  draft (about 2 ms) while dragged and the full grid when released.

## Consequences

- Wheels and knobs redraw at the display rate, and the film model stays in one
  testable place.
- A change to the primary grade must be made in Swift and in the shader
  together; the parity test fails otherwise.
