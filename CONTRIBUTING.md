# Contributing to Emulist

Thanks for helping. Emulist is a colorist's tool, so the image comes first: a
change that makes the picture less faithful, or the controls less responsive,
needs a very good reason.

## Development setup

Only the Swift toolchain is needed: Xcode, or just the Command Line Tools
(Swift 6.2 or later). There are no package dependencies, and shaders compile
at runtime.

```sh
scripts/build-app.sh --open          # build build/Emulist.app (release) and launch it
scripts/test.sh                      # unit tests (Swift Testing; works with Command Line Tools too)
swift build -c release -Xswiftc -warnings-as-errors   # what CI builds (the app and emulist-cli)
```

Requires macOS 14.2 or later on Apple silicon.

### Test footage

`scripts/make-test-clip.sh` turns any photo, or a procedural chart, into a
synthetic Apple Log ProRes clip (it needs `ffmpeg`, and builds `emulist-cli`
first). Then `emulist-cli` renders it headlessly with the same engine as the
app:

```sh
CLI=.build/release/emulist-cli
scripts/make-test-clip.sh chart test.mov                     # or: photo.jpg test.mov
$CLI tag-apple-log test.mov tagged.mov                       # declare Apple Log like an iPhone does
$CLI sheet tagged.mov sheet.png --scale 0.25                 # neutral + every look on one frame
$CLI render tagged.mov frame.png --stock nocturne-800 --time 1
$CLI export tagged.mov out.mp4 --codec hevc --stock aurora-50
$CLI bench tagged.mov                                        # LUT bake and per-frame GPU time
$CLI looks                                                   # list every look and its id
$CLI cube look.cube --stock golden-200                       # bake a look as a .cube LUT
```

Any grade setting can be overridden numerically, e.g. `--colorBoost 40` or
`--gain.y 0.3`. Rendered media is ignored by git; please don't commit footage.

## Ground rules

- **Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) first.** Color science,
  the film model, rendering and the project format go in `EmulistCore`, which
  has no UI. The app (`Sources/Emulist`) only presents and orchestrates.
- **Color math lives in Swift and is tested.** The GPU interpolates tables
  baked in Swift. The one exception, the primary grade, runs in a shader too,
  and `GPUGradeTests` holds it to `PrimaryGrade` within 0.002 stops: change
  both together.
- **Keep it simple and DRY.** Reuse the controls in `Controls/` and the tokens
  in `Theme.swift`; don't hard-code colors or sizes in views. Looks, recipes
  and controls are data (`BuiltInStocks.swift`, `FujiXWeeklyRecipes.swift`,
  `ParameterSpecs.swift`), so adding one should not need new UI code.
- **Zero warnings** under Swift 6 strict concurrency. CI builds with
  `-warnings-as-errors`.
- **Measure performance; don't estimate it.** For a change on the render path
  or in the grading panel, say what you measured (redraws a second while
  dragging, `emulist-cli bench`) and on which Mac.
- **No third-party looks in the repository.** Emulist's stocks are original
  interpretations. Fujifilm's LUTs are downloaded by the user, never bundled.
  Never contribute material extracted or reverse-engineered from commercial
  software, such as film profiles or LUTs. `.cube` import is the supported way
  to use other looks.

## Adding a film stock

Append a `FilmStock` to `Sources/EmulistCore/Film/BuiltInStocks.swift` and
list it in `builtIn`:

```swift
static let harbor160 = FilmStock(
    id: "harbor-160", name: "Harbor 160", format: "Color Negative",
    summary: "One or two sentences on its character.",
    response: FilmResponse(/* see the comment at the top of the file */),
    grain: GrainSettings(amount: 20, size: 25, softness: 30, chroma: 35),
    halation: HalationSettings(amount: 20, radius: 30), bloom: BloomSettings(amount: 15, radius: 35))
```

`emulist-cli sheet` shows it next to the others on any frame.

## Commit messages

We use [Conventional Commits](https://www.conventionalcommits.org), so the
changelog can be drafted with [git-cliff](https://git-cliff.org):

```
feat(scopes): add a histogram
fix(export): keep the audio track's channel layout
docs: explain printer lights
```

## Releasing (maintainers)

Emulist follows [Semantic Versioning](https://semver.org).

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in
   `packaging/macos/Info.plist`.
2. Move the *Unreleased* notes in `CHANGELOG.md` under the new version
   (`git cliff --unreleased --tag vX.Y.Z` drafts them), then commit with
   `chore(release): vX.Y.Z`.
3. Tag and push: `git tag -a vX.Y.Z -m "Emulist vX.Y.Z" && git push --follow-tags`.
4. The **Release** workflow checks the tag against the Info.plist, runs the
   tests, builds the app with `scripts/package.sh` and publishes a GitHub
   release with that version's changelog section, the `.dmg`, the `.zip` and
   `SHA256SUMS.txt`.

Releases are ad-hoc signed and not notarized yet.
