# 1. Swift, SwiftUI and Metal, buildable without Xcode

- Status: accepted
- Date: 2026-10-17

## Context

Emulist decodes 10-bit LOG video, grades it on the GPU at display rate and
exports it. It should feel like a Mac app, with tactile controls, and anyone
should be able to build it.

## Decision

- A Swift package with no dependencies: SwiftUI for the interface, Metal for
  rendering, AVFoundation for decoding and export.
- Metal shaders are compiled from source at runtime (`Shaders.swift`), so no
  `.metallib` build step is needed, and the package builds with the Command
  Line Tools alone. `scripts/build-app.sh` assembles the `.app`.
- Swift 6 language mode with strict concurrency, built with zero warnings.

## Consequences

- No Xcode project to maintain, and CI is plain `swift build` / `swift test`.
- Shader compile errors surface at launch, not at build time. The tests
  render through the shaders, so CI catches them.
- Swift Testing under Command Line Tools needs extra flags, which
  `scripts/test.sh` supplies.
