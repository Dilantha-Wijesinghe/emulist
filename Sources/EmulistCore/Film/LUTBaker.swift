import Foundation

/// Bakes color transforms into GPU-friendly tables. All color math lives in Swift (and is unit-tested);
/// the GPU only interpolates.
public enum LUTBaker {
    public static let filmLUTSize = 65
    public static let transferLUTSize = 4096

    /// 3D LUT over the log shaper (see `WorkingSpace`), RGBA half floats, red varying fastest.
    public static func filmLUT(_ model: FilmModel, size: Int = filmLUTSize) -> [Float16] {
        var data = [Float16](repeating: 1, count: size * size * size * 4)
        let scale = 1 / Double(size - 1)
        let linear = (0..<size).map { i in
            WorkingSpace.midGrey * pow(2, WorkingSpace.stops(shaperCoordinate: Double(i) * scale))
        }
        data.withUnsafeMutableBufferPointer { buffer in
            nonisolated(unsafe) let out = buffer
            DispatchQueue.concurrentPerform(iterations: size) { b in
                for g in 0..<size {
                    for r in 0..<size {
                        let value = model.render(RGB(linear[r], linear[g], linear[b]))
                        let index = ((b * size + g) * size + r) * 4
                        out[index] = Float16(value.x)
                        out[index + 1] = Float16(value.y)
                        out[index + 2] = Float16(value.z)
                    }
                }
            }
        }
        return data
    }

    /// 1D decode table: normalized code value -> scene-linear light.
    public static func decodeLUT(_ transfer: TransferFunction, size: Int = transferLUTSize) -> [Float] {
        (0..<size).map { Float(transfer.decode(Double($0) / Double(size - 1))) }
    }
}
