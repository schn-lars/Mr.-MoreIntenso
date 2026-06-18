/// used for filtering

import RealityKit
import Foundation
import CoreLocation

struct SceneMeshTag: Component {}

struct ObjectIDComponent: Component {
    let id: UUID
}

struct SharedObjectTag: Component {
    let id: UUID
}


/**
    This struct is used to display shared objects in space.
 */
struct SharedMarkerData {
    let id: UUID
    let label: String
    let owner: String
    let confidence: Float
    let worldPosition: SIMD3<Float>
}

struct ProximityResult {
    let id: UUID
    let label: String
    let owner: String
    let confidence: Float
    let coordinates: CLLocationCoordinate2D
}
