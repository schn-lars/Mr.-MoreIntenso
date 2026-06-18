//
//  TileOrientation.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import Foundation
import RealityKit
import simd

enum TileOrientation {
    /// Returns an orientation so that the tile's +Y axis points outward (normal to the sphere).
    /// This matches your old code: simd_quatf(from: (0,1,0), to: outward)
    static func outwardFacing(fromPosition position: SIMD3<Float>) -> simd_quatf {
        let outward = simd_normalize(position)
        let from = SIMD3<Float>(0, 1, 0)
        return simd_quatf(from: from, to: outward)
    }
}
