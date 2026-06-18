//
//  RankedFrontLayout.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import Accelerate
import Foundation
import RealityKit
import RealityKitContent
import SwiftUI
import UIKit

/// Ranked layout on a seamless sphere:
/// - generate Fibonacci candidate points
/// - sort by "frontness" (faces viewer at +Z)
/// - assign rank 0 -> most front-facing
struct RankedFrontLayout: SphereLayoutEngine {
    func layout(
        segments: [DetailedSegment],
        radius: Float,
        resolution: Double
    ) throws -> [TilePlacement] {
        let res = max(2.0, ceil(resolution))
        let requestedTileCount = Int(pow(res - 1.0, 2.0) * 6.0)
        let tileCount = max(0, min(requestedTileCount, segments.count))
        guard tileCount > 0 else { return [] }

        // tileSize based on sphere area per tile (your logic)
        let sphereArea = 4.0 * Float.pi * radius * radius
        let areaPerTile = sphereArea / Float(tileCount)
        let approxSide = sqrt(areaPerTile)
        let tileSize = min(0.18, max(0.05, approxSide * 0.65))

        let goldenAngle = Float.pi * (3.0 - sqrt(5.0))
        let front = SIMD3<Float>(0, 0, 1)

        // 1) Candidate points (unit vectors)
        var candidates: [(unit: SIMD3<Float>, frontness: Float)] = []
        candidates.reserveCapacity(tileCount)

        for i in 0 ..< tileCount {
            let t = (Float(i) + 0.5) / Float(tileCount) // (0,1)
            let y = 1.0 - 2.0 * t
            let rAtY = sqrt(max(0.0, 1.0 - y * y))
            let theta = goldenAngle * Float(i)

            // theta=0 -> z+ (front)
            let x = sin(theta) * rAtY
            let z = cos(theta) * rAtY

            let unit = SIMD3<Float>(x, y, z)
            candidates.append((unit: unit, frontness: simd_dot(unit, front)))
        }

        // 2) Sort by frontness
        candidates.sort { $0.frontness > $1.frontness }

        // 3) Rank i gets candidate i
        var out: [TilePlacement] = []
        out.reserveCapacity(tileCount)

        for rank in 0 ..< tileCount {
            let unit = candidates[rank].unit
            let pos = unit * radius
            out.append(
                TilePlacement(
                    index: rank,
                    position: pos,
                    outward: simd_normalize(pos),
                    tileSize: tileSize
                )
            )
        }

        return out
    }
}
