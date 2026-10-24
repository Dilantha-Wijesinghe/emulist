import Foundation

/// Bakes color transforms into GPU-friendly tables. All color math lives in Swift (and is unit-tested);
/// the GPU only interpolates.
public enum LUTBaker {
    public static let filmLUTSize = 65
    /// A coarser grid that bakes about 8× faster, for previews while a look control is being dragged.
    public static let draftLUTSize = 33
    public static let transferLUTSize = 4096

    /// 3D LUT over the log shaper (see `WorkingSpace`), RGBA half floats, red varying fastest.
    public static func filmLUT(_ pipeline: ColorPipeline.Renderer, size: Int = filmLUTSize) -> [Float16] {
        var data = [Float16](repeating: 1, count: size * size * size * 4)
        let scale = 1 / Double(size - 1)
        let linear = (0..<size).map { i in
            WorkingSpace.midGrey * pow(2, WorkingSpace.stops(shaperCoordinate: Double(i) * scale))
        }
        data.withUnsafeMutableBufferPointer { buffer in
            nonisolated(unsafe) let out = buffer
            forEachPoint(size: size) { point, r, g, b in
                let value = pipeline.render(RGB(linear[r], linear[g], linear[b]))
                out[point * 4] = Float16(value.x)
                out[point * 4 + 1] = Float16(value.y)
                out[point * 4 + 2] = Float16(value.z)
            }
        }
        return data
    }

    /// Calls `body(point, r, g, b)` for every point of a size³ grid, in parallel; `point` counts with red
    /// varying fastest, the order of GPU 3D textures and `.cube` files.
    static func forEachPoint(size: Int, _ body: @Sendable (_ point: Int, _ r: Int, _ g: Int, _ b: Int) -> Void) {
        DispatchQueue.concurrentPerform(iterations: size) { b in
            for g in 0..<size {
                for r in 0..<size { body((b * size + g) * size + r, r, g, b) }
            }
        }
    }

    /// 1D decode table: normalized code value -> scene-linear light.
    public static func decodeLUT(_ transfer: TransferFunction, size: Int = transferLUTSize) -> [Float] {
        (0..<size).map { Float(transfer.decode(Double($0) / Double(size - 1))) }
    }
}
