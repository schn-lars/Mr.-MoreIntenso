import CoreML

/**
    This class has been created using the JSON file fetched from here:
    - https://github.com/john-rocky/CoreML-Models?tab=readme-ov-file#mobilesam (MobileSam.zip)
 */
final class SAMPromptEncoder {
    private let gaussianMatrix: [[Float]] // [2, 128]
    private let pointEmbeddings: [[Float]]// [4, 256]
    private let notAPointEmbed: [Float]   // [256]
    private let noMaskEmbed: [Float]      // [256]
    
    private let imageSize: Float = 1024
    private let embedDim: Int = 256
    
    struct EncoderOutput {
        let sparse: MLMultiArray   // [1, 2, 256]
        let dense: MLMultiArray    // [1, 256, 64, 64]
    }
    
    init(jsonURL: URL) throws {
        let data = try Data(contentsOf: jsonURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        /// I had to do it like this, since JSONSerializaiton is apparently a obj-C API
        /// obj-C does not have native Float, Double or whatever but instead NSNumber.
        /// We need double, since it also has 64bits but Float does not, which caused the error when parsing directly I assume
        gaussianMatrix = (json["gaussian_matrix"] as! [[Double]])
            .map { $0.map { Float($0) } }
        
        pointEmbeddings = (json["point_embeddings"] as! [[Double]])
            .map { $0.map { Float($0) } }
        
        notAPointEmbed = (json["not_a_point_embed"] as! [Double])
            .map { Float($0) }
        
        noMaskEmbed = (json["no_mask_embed"] as! [Double])
            .map { Float($0) }
    }
    
    func encodeBox(x1: Float, y1: Float, x2: Float, y2: Float) throws -> EncoderOutput {
        guard let sparse = try? MLMultiArray(shape: [1, 2, 256], dataType: .float32),
              let dense  = try? MLMultiArray(shape: [1, 256, 64, 64], dataType: .float32)
        else { throw NSError(domain: "allocation-error", code: -1) }
        
        dense.withUnsafeMutableBufferPointer(ofType: Float32.self) { ptr, _ in
            for c in 0..<256 {
                let val = noMaskEmbed[c]
                let base = c * 64 * 64
                for i in 0..<(64 * 64) {
                    ptr[base + i] = val
                }
            }
        }
        

        let corners: [(x: Float, y: Float, labelIdx: Int)] = [
            (x1, y1, 2),
            (x2, y2, 3)
        ]
        
        for (ptIdx, corner) in corners.enumerated() {
            let px = (corner.x * imageSize) + 0.5
            let py = (corner.y * imageSize) + 0.5
            
            let posEmbed = positionalEncoding(x: px, y: py)
            let labelEmbed = pointEmbeddings[corner.labelIdx]
            
            for d in 0..<embedDim {
                let value = posEmbed[d] + labelEmbed[d]
                sparse[[0, ptIdx, d] as [NSNumber]] = NSNumber(value: value)
            }
        }
        
        return EncoderOutput(sparse: sparse, dense: dense)
    }
    
    private func positionalEncoding(x: Float, y: Float) -> [Float] {
        let nx = (x / imageSize) * 2.0 - 1.0 // was just x / imageSize
        let ny = (y / imageSize) * 2.0 - 1.0 // was just y / imageSize
        
        var freqs = [Float](repeating: 0, count: 128)
        for i in 0..<128 {
            freqs[i] = nx * gaussianMatrix[0][i] + ny * gaussianMatrix[1][i]
        }
        var embed = [Float](repeating: 0, count: 256)
        for i in 0..<128 {
            embed[i]       = sin(2 * Float.pi * freqs[i])
            embed[i + 128] = cos(2 * Float.pi * freqs[i])
        }
        return embed
    }
}
