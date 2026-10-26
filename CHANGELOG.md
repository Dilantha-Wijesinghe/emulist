# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-10-26

The first public release.

### Added

- Film emulation for LOG footage: seven original film looks, each with its own
  negative and print response, grain, halation and bloom.
- Apple Log input, detected from the clip's metadata (including Blackmagic Camera's iPhone clips), plus Sony
  S-Log3, Panasonic V-Log, Fujifilm F-Log and F-Log2, and Rec.709.
- Primaries that grade under the look: Lift, Gamma, Gain and Offset wheels; contrast and pivot, saturation,
  Color Boost, Density, shadows and highlights; exposure, temperature and tint.
- Hue vectors: six hue ranges you can turn, saturate or deepen, with Protect Skin.
- Fujifilm's official film simulations, downloaded from fujifilm-x.com on request, and 14 Fuji X Weekly recipes
  built on them.
- A looks library with live thumbnails of your frame, hover preview, search, favorites and recent looks.
- Your own `.cube` LUTs, and any grade exported as a `.cube` LUT for other apps.
- Waveform, RGB parade and vectorscope beside the viewer, and a full-screen cinema viewer.
- Before/after, a split wipe, and comparison with another clip's graded frame.
- Several clips per project, each with its own grade and undo history; copy and paste grades, in whole or by
  part; snapshots and saved looks.
- Export to ProRes 422 HQ, HEVC 10-bit or H.264 with audio, one clip or all of them, never replacing a file.
- `.emulist` projects that autosave and relink moved footage.
- `emulist-cli`, a headless renderer for look development, contact sheets, exports and benchmarks.

[Unreleased]: https://github.com/Dilantha-Wijesinghe/emulist/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Dilantha-Wijesinghe/emulist/releases/tag/v0.1.0
