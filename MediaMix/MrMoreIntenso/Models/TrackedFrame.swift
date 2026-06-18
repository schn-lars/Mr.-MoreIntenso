import simd
import CoreVideo

struct TrackedFrame {
    let buffer: CVPixelBuffer
    let extrinsics: simd_float4x4
}
