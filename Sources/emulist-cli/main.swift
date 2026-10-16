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
//
// Options: --time <seconds> --stock <id> --intensity <0-100> --scale <0-1> --split <0-1>
//          --settings <grade.json> --codec <prores|hevc|h264> --clean 1 (no grain/halation/bloom)

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
        if let id = options["stock"], let stock = FilmStock.with(id: id) { settings.select(stock) }
        if let intensity = double("intensity") { settings.intensity = intensity }
        if options["clean"] != nil {
            settings.grain.enabled = false
            settings.halation.enabled = false
            settings.bloom.enabled = false
        }
        return settings
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
            options: .init(scale: scale, beforeSplit: split), into: commandBuffer)
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
        for stock in FilmStock.builtIn {
            var settings = base
            settings.select(stock)
            looks.append(settings)
        }
        let images = try await renderFrame(
            paths[0], at: args.double("time") ?? 0, settings: looks, scale: args.double("scale") ?? 0.5, split: 0)
        try writePNG(contactSheet(images, columns: 3), to: paths[1])
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
    default:
        throw CLIError.usage("Unknown command \(command)")
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
