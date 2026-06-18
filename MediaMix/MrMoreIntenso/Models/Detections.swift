import Foundation
import CoreML
import simd

struct BoundingBox {
    let x: Float
    let y: Float
    let width: Float
    let height: Float
}

protocol MLObservation {
    var label: String { get }
    var confidence: Float { get }
    var bbox: BoundingBox { get }
}

struct Detection: MLObservation {
    let label: String
    let confidence: Float
    let bbox: BoundingBox
}

struct Segmentation: MLObservation {
    let label: String
    let confidence: Float
    let bbox: BoundingBox
    let mask: [Bool]
}

enum ObservationType: String, Codable {
    case detection
    case segmentation
}

struct AnyObservation {
    let base: any MLObservation

    var label: String { base.label }
    var confidence: Float { base.confidence }
    var bbox: BoundingBox { base.bbox }
    let extrinsics: simd_float4x4?
    var image: CGImage?
    
    // we ned
    init(
        base: any MLObservation,
        extrinsics: simd_float4x4,
        image: CGImage?
    ) {
        self.base = base
        self.extrinsics = extrinsics
        self.image = image
    }
    
    init(
        base: any MLObservation,
        extrinsics: simd_float4x4?,
        image: CGImage?
    ) {
        self.base = base
        self.extrinsics = extrinsics
        self.image = image
    }
}

struct TrackedObject {
    let id: UUID
    let label: String
    var bbox: BoundingBox
    var lastSeen: Date
    let confidence: Float
    let image: CGImage?
    let mask: [Bool]?
}

struct ResultObservations {
    let observations: [AnyObservation]
    let extrinsics: simd_float4x4?
}

struct ProcessedObservations {
    let trackedObservations: [TrackedObject]
    let extrinsics: simd_float4x4?
}

struct SelectedDetection {
    let id: UUID
    let confidence: Float
    let label: String
    let fullImage: CGImage?
    let croppedImage: CGImage?
    
    /*
     Potentially add attributes for the actual retrieved content.
     
     Note: Actually this might not be necessary. If the id matches one which has already been shared,
     we get data anyways. We are not storing data on our device but somehow make it look like we do.
     */
}

/**
    Used to hold data that is being saved in the renderer to eventually be used to trigger the information retrieval itself.
 */
struct DetectionRenderData {
    let label: String
    let confidence: Float
    let bbox: BoundingBox

    let croppedImage: CGImage?
}
