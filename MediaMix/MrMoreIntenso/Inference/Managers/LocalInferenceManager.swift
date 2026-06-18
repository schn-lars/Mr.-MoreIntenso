/**
    This class is in charge of inference that happens locally.
 */

import SwiftUI
import CoreML
import Vision

class LocalInferenceManager {
    var onDetections: (([AnyObservation]) -> Void)?
    private let ciContext = CIContext(options: [
        .useSoftwareRenderer: true,
        .workingColorSpace: CGColorSpaceCreateDeviceRGB()
    ])
    
    private var resizedBuffer: CVPixelBuffer? = {
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            1024,
            1024,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
            &pixelBuffer
        )
        return pixelBuffer
    }()
    
    
    //private let yoloWorld: yolov8sWorldv2
    private let yoloVisionModel: VNCoreMLModel
    //private let yolov26: yolo26s
    
    /*
    private let promptEncoder: SAM2TinyPromptEncoderFLOAT16
    private let maskDecoder: SAM2TinyMaskDecoderFLOAT16
    private let imageEncoder: SAM2TinyImageEncoderFLOAT16
    */
    
    private let mobileSamDecoder: mobile_sam_decoder
    private let mobileSamEncoder: mobile_sam_encoder
    private var mobileSamPromptEncoder: SAMPromptEncoder!
    
    init() {
        print("LocalInferenceManager: init")
        let aneConfig = MLModelConfiguration()
        aneConfig.computeUnits = .all

        // Mask decoder must avoid ANE due to dynamic ConvTranspose shapes
        let cpuGpuConfig = MLModelConfiguration()
        cpuGpuConfig.computeUnits = .cpuAndGPU
        
        do {
            
            let yoloWorld = try yolov8sWorldv2(configuration: aneConfig)
            self.yoloVisionModel = try VNCoreMLModel(for: yoloWorld.model)
            
            //self.yolov26 = try yolo26s(configuration: aneConfig)
            /*
            print("LocalInferenceManager: yoloWorld")
            self.promptEncoder = try SAM2TinyPromptEncoderFLOAT16(configuration: cpuGpuConfig)
            print("LocalInferenceManager: promptEncoder")
            self.maskDecoder = try SAM2TinyMaskDecoderFLOAT16(configuration: cpuGpuConfig)
            print("LocalInferenceManager: maskDecoder")
            self.imageEncoder = try SAM2TinyImageEncoderFLOAT16(configuration: aneConfig)
            print("LocalInferenceManager: imageEncoder")
            */
            self.mobileSamDecoder = try mobile_sam_decoder(configuration: aneConfig)
            self.mobileSamEncoder = try mobile_sam_encoder(configuration: aneConfig)
            let jsonURL = Bundle.main.url(
                forResource: "mobile_sam_prompt_encoder_weights",
                withExtension: "json"
            )!
            mobileSamPromptEncoder = try! SAMPromptEncoder(jsonURL: jsonURL)
            
            /// The following output of has been documented on Week 9 - Journal.
            //print("LocalInferenceManager: PromptEncoder InputDescirption:")
            //print(promptEncoder.model.modelDescription.inputDescriptionsByName)
            //print("LocalInferenceManager: MaskDecoder InputDescirption:")
            //print(maskDecoder.model.modelDescription.inputDescriptionsByName)
        } catch {
            fatalError("LocalInferenceManager: init ERROR - \(error.localizedDescription)")
        }
    }
    
    private func debugMask(_ mask: MLMultiArray) {
        print("Mask shape: \(mask.shape)")
        print("Mask dataType: \(mask.dataType.rawValue)")
        // 65552 = Float16, 65568 = Float32
        
        // Sample a few values
        let count = min(10, mask.count)
        for i in 0..<count {
            print("mask[\(i)] = \(mask[i].floatValue)")
        }
    }
    
    func processFrame(_ trackedFrame: TrackedFrame, segmenting: Bool = true) async -> ResultObservations {
        // First get predictions using yolo world
        //let start = Date().timeIntervalSince1970
        
        let request = VNCoreMLRequest(model: yoloVisionModel)
        request.imageCropAndScaleOption = .scaleFill
        
        let handler = VNImageRequestHandler(
            cvPixelBuffer: trackedFrame.buffer,
            orientation: .up,
            options: [:]
        )

        do {
            try handler.perform([request])
        } catch {
            print("LocalInferenceManager: Vision request failed \(error)")
            return ResultObservations(
                observations: [],
                extrinsics: trackedFrame.extrinsics
            )
        }

        guard let yoloResults = request.results as? [VNRecognizedObjectObservation],
              !yoloResults.isEmpty else {
            //print("LocalInferenceManager: processFrame GUARD - no Vision results")
            return ResultObservations(
                observations: [],
                extrinsics: trackedFrame.extrinsics
            )
        }

        var results: [AnyObservation] = []
        if !segmenting {
            for obs in yoloResults {
                let bbox = obs.boundingBox
                let x1 = Float(bbox.minX)
                let y1 = Float(1.0 - bbox.maxY)
                let w  = Float(bbox.width)
                let h  = Float(bbox.height)
  
                guard let topLabel = obs.labels.first else { continue }
                let className = topLabel.identifier
                let conf = Float(topLabel.confidence)
                
                /// if a bounding box would be covering a large amount of the FOV we are skipping it
                /// this is mostly due to the fact that our vocabulary is filled with scene words (classroom)
                guard w * h < 0.8 else { continue }
                guard w < 0.7 else { continue } // similar to the above case
                guard conf > 0.6 else { continue }

                results.append(
                    AnyObservation(
                        base: Detection(
                            label: className,
                            confidence: conf,
                            bbox: BoundingBox(
                                x: Float(x1),
                                y: Float(y1),
                                width: w,
                                height: h
                            )
                        ),
                        extrinsics: trackedFrame.extrinsics,
                        image: cropPixelBufferToCGImage(
                            trackedFrame.buffer,
                            bbox: CGRect(
                                origin:
                                    CGPoint(
                                        x: Double(x1),
                                        y: Double(y1)
                                    ),
                                size: CGSize(
                                    width: Double(w),
                                    height: Double(h)
                                )
                            )
                        )
                    )
                )
            }
        } else {
            // MobileSAM
            //let start = Date().timeIntervalSince1970
            guard let resized = resizePixelBuffer(trackedFrame.buffer, to: 1024) else {
                //print("LocalInferenceManager: processFrame GUARD - resized is nil")
                return ResultObservations(
                    observations: [],
                    extrinsics: trackedFrame.extrinsics
                )
            }
            
            guard let pixel_array = pixelBufferToMLMultiArray(resized),
                  let imageEmbedding = try? mobileSamEncoder.prediction(image: pixel_array)
            else {
                print("LocalInferenceManager: processFrame GUARD - imageEmbedding is nil")
                return ResultObservations(
                    observations: [],
                    extrinsics: trackedFrame.extrinsics
                )
            }

            await withTaskGroup(of: AnyObservation?.self) { group in
                for obs in yoloResults {
                    let bbox = obs.boundingBox
                    let x1 = Float(bbox.minX)
                    let y1 = Float(1.0 - bbox.maxY)
                    let w  = Float(bbox.width)
                    let h  = Float(bbox.height)
      
                    guard let topLabel = obs.labels.first else { continue }
                    let className = topLabel.identifier
                    let conf = Float(topLabel.confidence)
                    
                    /// if a bounding box would be covering a large amount of the FOV we are skipping it
                    /// this is mostly due to the fact that our vocabulary is filled with scene words (classroom)
                    guard w * h < 0.8 else { continue }
                    guard w < 0.7 else { continue } // similar to the above case
                    guard conf > 0.6 else { continue }

                    // Capture values for task closure
                    let embedding = imageEmbedding
                    let buffer = trackedFrame.buffer
                    let extrinsics = trackedFrame.extrinsics

                    group.addTask {
                        guard let promptOutput = try? self.mobileSamPromptEncoder.encodeBox(
                            x1: x1,
                            y1: y1,
                            x2: x1 + w,
                            y2: y1 + h
                        ) else { return nil }

                        guard let maskOutput = try? await self.mobileSamDecoder.prediction(
                            input: mobile_sam_decoderInput(
                                image_embeddings: embedding.image_embeddings,
                                sparse_embeddings: promptOutput.sparse,
                                dense_embeddings: promptOutput.dense
                            )
                        ) else { return nil }

                        guard let bestMask = self.extractMaskBitmap(maskOutput.masks) else { return nil }

                        let croppedMask = self.cropMaskToBBox(
                            mask: bestMask,
                            normalized: BoundingBox(x: x1, y: y1, width: w, height: h),
                            outputSize: 256
                        )
                        
                        return AnyObservation(
                            base: Segmentation(
                                label: className,
                                confidence: conf,
                                bbox: BoundingBox(x: x1, y: y1, width: w, height: h),
                                mask: croppedMask
                            ),
                            extrinsics: extrinsics,
                            image: self.cropPixelBufferToCGImage(
                                buffer,
                                bbox: CGRect(x: Double(x1), y: Double(y1), width: Double(w), height: Double(h))
                            )
                        )
                    }
                }

                for await result in group {
                    if let obs = result { results.append(obs) }
                }
            }
        }
        /**
            mask: <1,3,256,256>
            also bbox: I encountered withs of 1.00007 f.e.
         */
        //onDetections(results)
        //let now = Date().timeIntervalSince1970
        //let duration = now - start
        //print("\(now)|\(duration)")
        return ResultObservations(
            observations: results,
            extrinsics: trackedFrame.extrinsics
        )
    }
    
    private func cropMaskToBBox(
        mask: [Bool],
        maskWidth: Int = 256,
        maskHeight: Int = 256,
        normalized bbox: BoundingBox,
        outputSize: Int = 256
    ) -> [Bool] {
        let x0 = Int(bbox.x * Float(maskWidth))
        let y0 = Int(bbox.y * Float(maskHeight))
        let bw = max(1, Int(bbox.width * Float(maskWidth)))
        let bh = max(1, Int(bbox.height * Float(maskHeight)))

        var cropped = [Bool](repeating: false, count: outputSize * outputSize)
        
        mask.withUnsafeBufferPointer { srcPtr in
            cropped.withUnsafeMutableBufferPointer { dstPtr in
                for row in 0..<outputSize {
                    let srcY = y0 + row * bh / outputSize
                    guard srcY < maskHeight else { continue }
                    let srcRowOffset = srcY * maskWidth
                    
                    for col in 0..<outputSize {
                        let srcX = x0 + col * bw / outputSize
                        guard srcX < maskWidth else { continue }
                        dstPtr[row * outputSize + col] = srcPtr[srcRowOffset + srcX]
                    }
                }
            }
        }
        return cropped
    }
    
    private func createCGImage(from buffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvImageBuffer: buffer)
        return ciContext.createCGImage(ciImage, from: ciImage.extent)
    }
    
    func cropPixelBufferToCGImage(
        _ pixelBuffer: CVPixelBuffer,
        bbox: CGRect
    ) -> CGImage? {

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        let width = ciImage.extent.width
        let height = ciImage.extent.height

        let cropRect = CGRect(
            x: bbox.minX * width,
            y: (1.0 - bbox.maxY) * height,
            width: bbox.width * width,
            height: bbox.height * height
        )

        guard let cgImage = ciContext.createCGImage(
            ciImage,
            from: cropRect
        ) else {
            return nil
        }
        return cgImage
    }
    
    private func saveCropDebug(_ buffer: CVPixelBuffer, index: Int, label: String) {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage)
        
        guard let data = uiImage.pngData() else { return }
        
        let filename = "crop_\(index)_\(label.replacingOccurrences(of: " ", with: "_")).png"
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
        
        try? data.write(to: url)
        print("LocalInferenceManager: saved crop to \(url.path)")
    }
    
    /// Currently only returning the first one.
    /// Testing showed that the index 0 showed best resutls
    private func extractBestMask(_ masks: MLMultiArray) -> MLMultiArray? {
        let H = masks.shape[2].intValue
        let W = masks.shape[3].intValue
        
        guard let best = try? MLMultiArray(
            shape: [1, 1, H, W] as [NSNumber],
            dataType: masks.dataType
        ) else {
            return nil
        }
        
        masks.withUnsafeBufferPointer(ofType: Float16.self) { msk_ptr in
            // I think the second parameter are strides
            best.withUnsafeMutableBufferPointer(ofType: Float16.self) { best_ptr, _ in
                // we are simply taking the first mask here
                // otherwise make something like let offset = idx * H * W and then [offset + i]
                for i in 0..<(H * W) {
                    best_ptr[i] = msk_ptr[i]
                }
            }
        }
        return best
    }
    
    private func extractMaskBitmap(_ masks: MLMultiArray) -> [Bool]? {
        let H = masks.shape[2].intValue
        let W = masks.shape[3].intValue
        var bitmap = [Bool](repeating: false, count: W * H)
        
        
        masks.withUnsafeBufferPointer(ofType: Float32.self) { ptr in
            /*
            var minVal: Float32 = .infinity
            var maxVal: Float32 = -.infinity
            var sum: Float32 = 0
            for i in 0..<(H * W) {
                let v = ptr[i]
                if v < minVal { minVal = v }
                if v > maxVal { maxVal = v }
                sum += v
            }
            //print("Mask raw range: min=\(minVal) max=\(maxVal) mean=\(sum / Float(H*W))")
            */
            for i in 0..<(H*W) { bitmap[i] = ptr[i] > 0 }
        }
        //let trueCount = bitmap.filter { $0 }.count
        //print("extractMaskBitmap: \(trueCount)/\(W*H) true pixels")
        return bitmap
    }
    
    private func resizePixelBuffer(_ buffer: CVPixelBuffer, to size: Int) -> CVPixelBuffer? {
        guard let resizedBuffer else { return nil }
        
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let scaleX = CGFloat(size) / CGFloat(CVPixelBufferGetWidth(buffer))
        let scaleY = CGFloat(size) / CGFloat(CVPixelBufferGetHeight(buffer))
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        ciContext.render(scaled, to: resizedBuffer)
        return resizedBuffer
    }
    
    /**
        Make sure the buffer is of size 1024x1024!
     */
    private func pixelBufferToMLMultiArray(_ buffer: CVPixelBuffer) -> MLMultiArray? {
        let dim = 1024
        
        guard let array = try? MLMultiArray(
            shape: [1, 3, dim, dim] as [NSNumber],
            dataType: .float32
        ) else { return nil }
        
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let src = baseAddress.assumingMemoryBound(to: UInt8.self)
        
        // ImageNet normalization constants (what MobileSAM was trained with)
        let mean: (Float, Float, Float) = (0.485, 0.456, 0.406)
        let std:  (Float, Float, Float) = (0.229, 0.224, 0.225)
        
        array.withUnsafeMutableBufferPointer(ofType: Float32.self) { ptr, _ in
            let rOffset = 0 * dim * dim
            let gOffset = 1 * dim * dim
            let bOffset = 2 * dim * dim
            
            for y in 0..<dim {
                for x in 0..<dim {
                    // BGRA layout: byte order is B, G, R, A
                    let pixel = y * bytesPerRow + x * 4
                    let b = Float(src[pixel + 0]) / 255.0
                    let g = Float(src[pixel + 1]) / 255.0
                    let r = Float(src[pixel + 2]) / 255.0
                    
                    let i = y * dim + x
                    ptr[rOffset + i] = (r - mean.0) / std.0
                    ptr[gOffset + i] = (g - mean.1) / std.1
                    ptr[bOffset + i] = (b - mean.2) / std.2
                }
            }
        }
        return array
    }
    
    private func getYOLOWorldClassLabel(_ array: MLMultiArray, row: Int, numClasses: Int) -> (String, Float) {
        let (idx, conf) = argmax(array, row: row, numClasses: numClasses)
        return (Constants.shared.getClassAt(idx), conf)
    }
    
    private func argmax(_ array: MLMultiArray, row: Int, numClasses: Int) -> (Int, Float) {
        var bestIdx: Int = 0
        var bestConf: Float = 0.0
        array.withUnsafeBufferPointer(ofType: Float.self) { ptr in
            for c in 0..<numClasses {
                let curr = ptr[row * numClasses + c]
                if bestConf < curr { bestConf = curr; bestIdx = c }
            }
        }
        return (bestIdx, bestConf)
    }
}
