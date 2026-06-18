import SwiftUI

/**
    This protocol defines the interface for on-device inference.
 */
protocol InferenceEngine {
    func predict(pixelBuffer: CVPixelBuffer) async throws -> [any MLObservation]
}
