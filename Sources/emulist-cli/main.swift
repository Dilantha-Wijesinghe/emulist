import AVFoundation
import CoreGraphics
import EmulistCore
import Foundation
import ImageIO
import Metal
import simd

// Headless tools for look development and verification.
//
//   emulist-cli log-encode <image> <out.tiff>        Photo -> synthetic Apple Log frame (16-bit TIFF)
//   emulist-cli chart <out.tiff>                      Procedural Apple Log test chart
//   emulist-cli render <clip> <out.png> [options]     Render one frame
//   emulist-cli sheet <clip> <out.png> [options]      Before + every stock, as a contact sheet
//   emulist-cli export <clip> <out.mov> [options]     Export the graded clip
//   emulist-cli tag-apple-log <clip> <out.mov>        Remux, declaring Apple Log the way an iPhone does
//   emulist-cli verify-decode <clip>                  Viewer (player) and export (reader) decodes must be identical
//   emulist-cli install-fujifilm [folder]             Install Fujifilm's film simulation LUTs (download, or from an unzipped folder)
//   emulist-cli looks                                 List every look in the library
//
// Options: --time <seconds> --stock <id> --recipe <name> --scale <0-1> --split <0-1> --settings <grade.json>
//          --codec <prores|hevc|h264> --clean 1 (no grain/halation/bloom) --collection <name> (sheet)
//          Any other --<setting> <number> overrides that grade setting, e.g. --colorBoost 40 --lift.x 0.3

struct Arguments {
    var positional: [String] = []
    var options: [String: String] = [:]

    init(_ raw: [String]) {
        var iterator = raw.makeIterator()
        while let arg = iterator.next() {
            if arg.hasPrefix("--") { options[String(arg.dropFirst(2))] = iterator.next() ?? "" } else { positional.append(arg) }
        }
    }

    func double(_ key: String) -> Double? { options[key].flatMap(Double.init) }

    func settings() throws -> GradeSettings {
        var settings = GradeSettings()
        if let path = options["settings"] {
            settings = try JSONDecoder().decode(GradeSettings.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        }
        if let id = options["stock"] {
            guard let stock = FilmStock.with(id: id) else { throw CLIError.usage("Unknown look \(id)") }
            settings.select(stock)
        }
        if let name = options["recipe"] {
            guard let recipe = FilmRecipe.fujiXWeekly.first(where: { $0.name == name }),
                  let preset = recipe.preset(in: LookLibrary.shared.all)
            else { throw CLIError.usage("Unknown recipe \(name), or its Fujifilm simulation isn’t installed") }
            settings = preset.applied(to: settings)
        }
        settings = try overriding(settings)
        if options["clean"] != nil {
            settings.grain.enabled = false
            settings.halation.enabled = false
            settings.bloom.enabled = false
        }
        return settings
    }

    static let reserved: Set = ["settings", "stock", "recipe", "time", "scale", "split", "codec", "clean", "collection", "columns"]

    /// Applies numeric `--key value` options to the settings' JSON (dotted keys reach nested values).
    func overriding(_ settings: GradeSettings) throws -> GradeSettings {
        let overrides = options.filter { !Self.reserved.contains($0.key) }
        guard !overrides.isEmpty else { return settings }
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String: Any]
        func set(_ path: ArraySlice<Substring>, _ value: Double, in dict: inout [String: Any]) throws {
            let key = String(path.first!)
            if path.count == 1 {
                guard dict[key] is NSNumber else { throw CLIError.usage("Unknown setting \(key)") }
                dict[key] = value
            } else {
                guard var nested = dict[key] as? [String: Any] else { throw CLIError.usage("Unknown setting \(key)") }
                try set(path.dropFirst(), value, in: &nested)
                dict[key] = nested
            }
        }
        for (key, raw) in overrides {
            guard let value = Double(raw) else { throw CLIError.usage("--\(key) needs a number") }
            try set(key.split(separator: ".")[...], value, in: &json)
        }
        return try JSONDecoder().decode(GradeSettings.self, from: JSONSerialization.data(withJSONObject: json))
    }
}

enum CLIError: Error, CustomStringConvertible {
    case usage(String)
    var description: String { if case .usage(let text) = self { return text } else { return "" } }
}

// MARK: Synthetic Apple Log footage

/// Scene-linear Rec.2020 image -> 16-bit Apple Log TIFF.
func writeAppleLogTIFF(width: Int, height: Int, to url: URL, scene: (Int, Int) -> RGB) throws {
    var pixels = [UInt16](repeating: 0, count: width * height * 3)
    for y in 0..<height {
        for x in 0..<width {
            let value = scene(x, y)
            for c in 0..<3 {
                let code = TransferFunction.appleLog.encode(value[c])
                pixels[(y * width + x) * 3 + c] = UInt16(max(0, min(65535, (code * 65535).rounded())))
            }
        }
    }
    let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
    guard let provider = CGDataProvider(data: data as CFData),
          let image = CGImage(
            width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 48, bytesPerRow: width * 6,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue | CGBitmapInfo.byteOrder16Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 1, nil)
    else { throw CLIError.usage("Could not write \(url.path)") }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

/// Loads a photo as display-linear Rec.2020 and inverts the neutral print curve, so rendering the result
/// with the neutral look reproduces the photo, and highlights regain scene-referred headroom.
func photoToScene(_ url: URL) throws -> (width: Int, height: Int, scene: (Int, Int) -> RGB) {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CLIError.usage("Can't read \(url.path)") }
    let width = image.width, height = image.height
    var floats = [Float](repeating: 0, count: width * height * 4)
    let space = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!
    floats.withUnsafeMutableBytes { bytes in
        let context = CGContext(
            data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 32, bytesPerRow: width * 16,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    let neutral = FilmModel(response: .neutral, output: .rec709Apple)
    // Tabulate the inverse of the neutral print curve once (monotonic, so bisection per entry).
    let table: [Double] = (0...4096).map { i in
        let target = min(Double(i) / 4096, 0.985)
        var lo = -14.0, hi = 12.0
        for _ in 0..<60 {
            let mid = (lo + hi) / 2
            if neutral.printDensity(stops: RGB(repeating: mid)).y < target { lo = mid } else { hi = mid }
        }
        return WorkingSpace.midGrey * pow(2, (lo + hi) / 2)
    }
    return (width, height, { x, y in
        let i = (y * width + x) * 4
        return RGB((0..<3).map { c in table[Int(max(0, min(1, Double(floats[i + c]))) * 4096)] })
    })
}

/// Grey ramp, stepped greys, color and skin patches, and point lights on black for halation/bloom.
func chartScene(width: Int, height: Int) -> (Int, Int) -> RGB {
    let srgbToWorking = ColorPrimaries.rec709.conversion(to: .rec2020)
    func srgb(_ r: Double, _ g: Double, _ b: Double) -> RGB {
        let lin = RGB(r, g, b).decoded(.gamma24) * 0.9
        return srgbToWorking * lin
    }
    let patches: [RGB] = [
        srgb(0.45, 0.32, 0.27), srgb(0.76, 0.59, 0.51), srgb(0.38, 0.48, 0.61), srgb(0.35, 0.42, 0.26),
        srgb(0.51, 0.50, 0.69), srgb(0.40, 0.74, 0.67), srgb(0.84, 0.48, 0.17), srgb(0.31, 0.36, 0.65),
        srgb(0.76, 0.33, 0.38), srgb(0.36, 0.24, 0.42), srgb(0.62, 0.73, 0.25), srgb(0.88, 0.64, 0.18),
        srgb(0.17, 0.24, 0.58), srgb(0.27, 0.58, 0.29), srgb(0.69, 0.20, 0.23), srgb(0.93, 0.78, 0.12),
        srgb(0.73, 0.33, 0.58), srgb(0.0, 0.52, 0.65),
    ]
    return { x, y in
        let u = Double(x) / Double(width), v = Double(y) / Double(height)
        if v < 0.14 { return RGB(repeating: 0.18 * pow(2, -8 + 14 * u)) }
        if v < 0.26 { return RGB(repeating: 0.18 * pow(2, Double(Int(u * 12)) - 6)) }
        if v < 0.78, u < 0.62 {
            let col = Int(u / 0.62 * 6), row = Int((v - 0.26) / 0.52 * 3)
            return patches[row * 6 + col]
        }
        // Light sources on a near-black background.
        let lights: [(Double, Double, Double, RGB)] = [
            (0.72, 0.45, 0.012, RGB(40, 32, 22)), (0.86, 0.45, 0.02, RGB(12, 12, 14)), (0.79, 0.68, 0.008, RGB(30, 6, 4)),
        ]
        var value = RGB(repeating: 0.006)
        let aspect = Double(width) / Double(height)
        for (cx, cy, r, color) in lights where hypot((u - cx) * aspect, v - cy) < r { value = color }
        if v > 0.82, u < 0.62 { value = srgb(0.86, 0.66, 0.55) * (0.5 + u) } // skin tone ramp
        return value
    }
}

// MARK: Metadata

/// Copies a clip's video samples untouched into a new file whose format description declares Apple Log.
func tagAppleLog(_ source: URL, to destination: URL) async throws {
    let asset = AVURLAsset(url: source)
    guard let track = try await asset.loadTracks(withMediaType: .video).first,
          let format = try await track.load(.formatDescriptions).first else { throw CLIError.usage("No video") }
    var extensions = (CMFormatDescriptionGetExtensions(format) as? [String: Any]) ?? [:]
    extensions[kCMFormatDescriptionExtension_LogTransferFunction as String] = kCMFormatDescriptionLogTransferFunction_AppleLog
    extensions[kCMFormatDescriptionExtension_ColorPrimaries as String] = kCMFormatDescriptionColorPrimaries_ITU_R_2020
    extensions[kCMFormatDescriptionExtension_YCbCrMatrix as String] = kCMFormatDescriptionYCbCrMatrix_ITU_R_2020
    // Otherwise the writer copies the original sample description byte for byte.
    extensions[kCMFormatDescriptionExtension_VerbatimSampleDescription as String] = nil
    let dimensions = CMVideoFormatDescriptionGetDimensions(format)
    var tagged: CMFormatDescription?
    CMVideoFormatDescriptionCreate(
        allocator: nil, codecType: CMFormatDescriptionGetMediaSubType(format), width: dimensions.width,
        height: dimensions.height, extensions: extensions as CFDictionary, formatDescriptionOut: &tagged)

    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    reader.add(output)
    try? FileManager.default.removeItem(at: destination)
    let writer = try AVAssetWriter(outputURL: destination, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: tagged)
    writer.add(input)
    reader.startReading()
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    while let sample = output.copyNextSampleBuffer() {
        guard let tagged, let data = CMSampleBufferGetDataBuffer(sample) else { continue }
        var timing = [CMSampleTimingInfo](repeating: .init(), count: CMSampleBufferGetNumSamples(sample))
        var sizes = [Int](repeating: 0, count: timing.count)
        CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: timing.count, arrayToFill: &timing, entriesNeededOut: nil)
        CMSampleBufferGetSampleSizeArray(sample, entryCount: sizes.count, arrayToFill: &sizes, entriesNeededOut: nil)
        var retagged: CMSampleBuffer?
        CMSampleBufferCreateReady(
            allocator: nil, dataBuffer: data, formatDescription: tagged, sampleCount: timing.count,
            sampleTimingEntryCount: timing.count, sampleTimingArray: &timing, sampleSizeEntryCount: sizes.count,
            sampleSizeArray: &sizes, sampleBufferOut: &retagged)
        while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
        if let retagged { input.append(retagged) }
    }
    input.markAsFinished()
    await writer.finishWriting()
    if let error = writer.error { throw error }
}

// MARK: Decode verification

/// First frame as the viewer receives it: AVPlayer + AVPlayerItemVideoOutput, paused at time zero.
@MainActor
func playerFirstFrame(_ url: URL) async throws -> CVPixelBuffer {
    let item = AVPlayerItem(url: url)
    let output = DecodeFormat.makePlayerOutput()
    item.add(output)
    let player = AVPlayer(playerItem: item)
    for _ in 0..<300 where item.status != .readyToPlay { try await Task.sleep(for: .milliseconds(10)) }
    await player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
    for _ in 0..<300 {
        if let buffer = output.copyPixelBuffer(forItemTime: .zero, itemTimeForDisplay: nil) { return buffer }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw CLIError.usage("The player produced no frame")
}

/// Largest difference between two Y'CbCr buffers, in code values, over both planes.
func maxDifference(_ a: CVPixelBuffer, _ b: CVPixelBuffer) -> Int {
    CVPixelBufferLockBaseAddress(a, .readOnly)
    CVPixelBufferLockBaseAddress(b, .readOnly)
    defer {
        CVPixelBufferUnlockBaseAddress(a, .readOnly)
        CVPixelBufferUnlockBaseAddress(b, .readOnly)
    }
    var worst = 0
    for plane in 0..<CVPixelBufferGetPlaneCount(a) {
        let rows = CVPixelBufferGetHeightOfPlane(a, plane)
        let samples = CVPixelBufferGetWidthOfPlane(a, plane) * (plane == 0 ? 1 : 2)
        for row in 0..<rows {
            let pa = CVPixelBufferGetBaseAddressOfPlane(a, plane)!.advanced(by: row * CVPixelBufferGetBytesPerRowOfPlane(a, plane))
            let pb = CVPixelBufferGetBaseAddressOfPlane(b, plane)!.advanced(by: row * CVPixelBufferGetBytesPerRowOfPlane(b, plane))
            let ra = pa.assumingMemoryBound(to: UInt16.self), rb = pb.assumingMemoryBound(to: UInt16.self)
            for i in 0..<samples { worst = max(worst, abs(Int(ra[i] >> 6) - Int(rb[i] >> 6))) }
        }
    }
    return worst
}

// MARK: Rendering

func renderFrame(_ url: URL, at time: Double, settings: [GradeSettings], scale: Double, split: Double) async throws -> [CGImage] {
    let info = try await MediaInfo.inspect(url)
    let reader = try await FrameReader(info: info, startingAt: time)
    guard let frame = try reader.next() else { throw CLIError.usage("No frame at \(time)s") }
    let context = try MetalContext.make()
    let renderer = FrameRenderer(context: context)
    return try settings.map { settings in
        guard let commandBuffer = context.queue.makeCommandBuffer() else { throw RenderError.textureCreation }
        let texture = try renderer.encode(
            frame.pixelBuffer, frameIndex: info.frameIndex(at: frame.time.seconds), settings: settings,
            options: .init(scale: scale, beforeSplit: split, orientation: info.transform), into: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return try renderer.makeImage(from: texture, output: settings.output)
    }
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw CLIError.usage("Can't write \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

func contactSheet(_ images: [CGImage], columns: Int) -> CGImage {
    let w = images[0].width, h = images[0].height, rows = (images.count + columns - 1) / columns
    let context = CGContext(
        data: nil, width: w * columns, height: h * rows, bitsPerComponent: 8, bytesPerRow: 0,
        space: images[0].colorSpace!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    for (i, image) in images.enumerated() {
        context.draw(image, in: CGRect(x: (i % columns) * w, y: (rows - 1 - i / columns) * h, width: w, height: h))
    }
    return context.makeImage()!
}

// MARK: Entry point

let args = Arguments(Array(CommandLine.arguments.dropFirst()))
do {
    guard let command = args.positional.first else { throw CLIError.usage("usage: emulist-cli <command> ...") }
    let paths = args.positional.dropFirst().map { URL(fileURLWithPath: $0) }
    switch command {
    case "log-encode":
        guard paths.count == 2 else { throw CLIError.usage("log-encode <image> <out.tiff>") }
        let photo = try photoToScene(paths[0])
        try writeAppleLogTIFF(width: photo.width, height: photo.height, to: paths[1], scene: photo.scene)
    case "chart":
        guard paths.count == 1 else { throw CLIError.usage("chart <out.tiff>") }
        try writeAppleLogTIFF(width: 1920, height: 1080, to: paths[0], scene: chartScene(width: 1920, height: 1080))
    case "render":
        guard paths.count == 2 else { throw CLIError.usage("render <clip> <out.png>") }
        let images = try await renderFrame(
            paths[0], at: args.double("time") ?? 0, settings: [try args.settings()],
            scale: args.double("scale") ?? 1, split: args.double("split") ?? 0)
        try writePNG(images[0], to: paths[1])
    case "sheet":
        guard paths.count == 2 else { throw CLIError.usage("sheet <clip> <out.png>") }
        let base = try args.settings()
        var looks = [base]
        looks[0].intensity = 0
        looks[0].grain.enabled = false
        looks[0].halation.enabled = false
        looks[0].bloom.enabled = false
        let library = LookLibrary.shared.all.filter { args.options["collection"].map($0.collection.hasPrefix) ?? true }
        for stock in library {
            var settings = base
            settings.select(stock)
            looks.append(settings)
        }
        if args.options["collection"].map(FilmRecipe.fujiXWeeklyCollection.hasPrefix) ?? true {
            looks += FilmRecipe.fujiXWeekly.compactMap { $0.preset(in: LookLibrary.shared.all)?.applied(to: base) }
        }
        let images = try await renderFrame(
            paths[0], at: args.double("time") ?? 0, settings: looks, scale: args.double("scale") ?? 0.5, split: 0)
        try writePNG(contactSheet(images, columns: Int(args.double("columns") ?? 4)), to: paths[1])
    case "export":
        guard paths.count == 2 else { throw CLIError.usage("export <clip> <out.mov>") }
        let info = try await MediaInfo.inspect(paths[0])
        let codec = ExportSettings.Codec(rawValue: args.options["codec"] ?? "prores") ?? .proRes422HQ
        let exporter = try VideoExporter(
            info: info, settings: try args.settings(), export: ExportSettings(codec: codec), destination: paths[1])
        let start = Date()
        try await exporter.run { progress in
            FileHandle.standardError.write(Data("\rexporting \(Int(progress * 100))%".utf8))
        }
        print(String(format: "\ndone in %.1fs", Date().timeIntervalSince(start)))
    case "bench":
        guard paths.count == 1 else { throw CLIError.usage("bench <clip>") }
        let settings = try args.settings()
        _ = try ColorPipeline(settings).makeRenderer() // load the look's LUT outside the timing
        var start = Date()
        for i in 0..<10 {
            var s = settings
            s.contrast = Double(i)
            _ = LUTBaker.filmLUT(try ColorPipeline(s).makeRenderer())
        }
        print(String(format: "look LUT bake: %.1f ms", Date().timeIntervalSince(start) * 100))
        let info = try await MediaInfo.inspect(paths[0])
        let reader = try await FrameReader(info: info)
        guard let frame = try reader.next() else { throw CLIError.usage("empty clip") }
        let context = try MetalContext.make()
        let renderer = FrameRenderer(context: context)
        for scale in [1.0, 0.5] {
            for pass in 0..<2 {
                start = Date()
                for i in 0..<30 {
                    let commandBuffer = context.queue.makeCommandBuffer()!
                    _ = try renderer.encode(frame.pixelBuffer, frameIndex: i, settings: settings,
                                            options: .init(scale: scale, orientation: info.transform), into: commandBuffer)
                    commandBuffer.commit()
                    if i == 29 { await commandBuffer.completed() }
                }
                if pass == 1 {
                    print(String(format: "%dx%d @ %.2f: %.2f ms/frame", info.width, info.height, scale,
                                 Date().timeIntervalSince(start) * 1000 / 30))
                }
            }
        }
    case "verify-decode":
        guard paths.count == 1 else { throw CLIError.usage("verify-decode <clip>") }
        let reader = try await FrameReader(info: try await MediaInfo.inspect(paths[0]))
        guard let exportFrame = try reader.next() else { throw CLIError.usage("empty clip") }
        let viewerFrame = try await playerFirstFrame(paths[0])
        let difference = maxDifference(viewerFrame, exportFrame.pixelBuffer)
        print("viewer vs export decode: max difference \(difference) code values (10-bit)")
        if difference > 0 { exit(2) }
    case "install-fujifilm":
        if let folder = paths.first {
            try FujifilmLooks.installLUTs(from: folder)
            LookLibrary.shared.reload()
        } else {
            print("downloading \(FujifilmLooks.packageURL.absoluteString) (\(FujifilmLooks.packageSize))…")
            try await FujifilmLooks.install()
        }
        print("installed into \(LookLibrary.directory.path)")
        fallthrough
    case "looks":
        for look in LookLibrary.shared.all { print("\(look.collection) · \(look.name)  [\(look.id)]") }
        for recipe in FilmRecipe.fujiXWeekly { print("\(FilmRecipe.fujiXWeeklyCollection) · \(recipe.name)  [--recipe \"\(recipe.name)\"]") }
    case "tag-apple-log":
        guard paths.count == 2 else { throw CLIError.usage("tag-apple-log <clip> <out.mov>") }
        try await tagAppleLog(paths[0], to: paths[1])
        let info = try await MediaInfo.inspect(paths[1])
        print("detected profile: \(info.detectedProfile?.name ?? "none")")
    default:
        throw CLIError.usage("Unknown command \(command)")
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
