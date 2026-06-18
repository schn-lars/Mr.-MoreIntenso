/**
    This class is supposed to take care of fetching images from the RealityView and cropping it to the models needs.
    Key components are most likely 3D to 2D conversion and vice versa, althought latter functionality might be offered in the component responsible for rendering.
 */
import CoreVideo
import CoreImage
import Vision

class ImageCaptureManager {
    private let ciContext = CIContext()
    
    /// Crops and resizes a CVPixelBuffer to the model's expected input size
    func preprocess(
        trackedFrame: TrackedFrame,
        targetSize: CGSize = CGSize(width: 640, height: 640)
    ) -> TrackedFrame? {
        let ciImage = CIImage(cvPixelBuffer: trackedFrame.buffer)
        
        // sclaing to model input size
        let scaleX = targetSize.width / ciImage.extent.width
        let scaleY = targetSize.height / ciImage.extent.height
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        var outputBuffer: CVPixelBuffer?
        
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(targetSize.width),
            Int(targetSize.height),
            kCVPixelFormatType_32BGRA,
            nil,
            &outputBuffer
        )
        
        if let outputBuffer {
            ciContext.render(scaled, to: outputBuffer)
            
            return TrackedFrame(
                buffer: outputBuffer,
                extrinsics: trackedFrame.extrinsics
            )
        }
        print("ImageCaptureManager: returned nil")
        return nil
    }
    
    func preprocessLetterboxed(
        trackedFrame: TrackedFrame,
        targetSize: CGSize = CGSize(width: 640, height: 640)
    ) -> TrackedFrame? {
        let ciImage = CIImage(cvPixelBuffer: trackedFrame.buffer)
        let srcW = ciImage.extent.width
        let srcH = ciImage.extent.height
        
        // min(640/1920, 640/1080) = min(0.333, 0.593) = 0.333
        let scale = min(targetSize.width / srcW, targetSize.height / srcH)
        let scaledW = srcW * scale // = 1920 * 0.333 = 640
        let scaledH = srcH * scale // = 1080 * 0.333 = 360
        
        let padX = (targetSize.width - scaledW) / 2 // 640 - 640 / 2 = 0
        let padY = (targetSize.height - scaledH) / 2 // 640 - 360 / 2 = 140
        
        let scaled = ciImage
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: padX, y: padY)) // centring
        
        let background = CIImage(color: CIColor.black)
            .cropped(to: CGRect(x: 0, y: 0, width: targetSize.width, height: targetSize.height))
        
        let composited = scaled.composited(over: background)
        
        var outputBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(targetSize.width),
            Int(targetSize.height),
            kCVPixelFormatType_32BGRA,
            nil,
            &outputBuffer
        )
        
        guard let outputBuffer else {
            print("ImageCaptureManager: letterbox returned nil")
            return nil
        }
        
        ciContext.render(composited, to: outputBuffer)
        return TrackedFrame(buffer: outputBuffer, extrinsics: trackedFrame.extrinsics)
    }
    
    /// Projects 2D bounding box back to a 3D world position
    /// using depth information from ARKit anchors
    func project2DTo3D(
        normalizedRect: CGRect, // [0,1]
        cameraTransform: simd_float4x4,
        estimatedDepth: Float = 2.0
    ) -> SIMD3<Float> {
        // Convert normalized rect center to camera space
        let centerX = Float(normalizedRect.midX) * 2 - 1  // [-1, 1]
        let centerY = Float(normalizedRect.midY) * 2 - 1
        
        // Simple projection, potentially refine with actual depth
        let localPos = SIMD3<Float>(centerX * estimatedDepth,
                                    -centerY * estimatedDepth,
                                    -estimatedDepth)
        let worldPos = cameraTransform * SIMD4<Float>(localPos, 1)
        return SIMD3<Float>(worldPos.x, worldPos.y, worldPos.z)
    }
}
