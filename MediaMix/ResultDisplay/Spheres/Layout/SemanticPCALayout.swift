//
//  SemanticPCALayout.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

//
//  SemanticPCALayout.swift
//  multimediaSphere
//

import Foundation
import simd

/// Semantic layout on sphere:
/// - use PCA to reduce clip vectors to 2D
/// - normalize to [-1,1]
/// - create Fibonacci candidates on sphere + UV mapping
/// - greedy-assign items to candidates by UV distance
struct SemanticPCALayout: SphereLayoutEngine {
    let projector: Projector2D

    init(projector: Projector2D = PCA2DProjector()) {
        self.projector = projector
    }

    func layout(
        segments: [DetailedSegment],
        radius: Float,
        resolution: Double
    ) throws -> [TilePlacement] {
        let res = max(2.0, ceil(resolution))
        let requestedTileCount = Int(pow(res - 1.0, 2.0) * 6.0)
        let tileCount = max(0, min(requestedTileCount, segments.count))
        guard tileCount > 0 else { return [] }

        let shownSegments = Array(segments.prefix(tileCount))

        // 1) Extract vectors
        let vectors: [[Float]] = shownSegments.compactMap { toFloatVector($0.clipVector) }
        guard vectors.count == tileCount else {
            // Missing vectors: caller can fall back to ranked
            // Here we return empty so controller can detect and fallback.
            return []
        }

        // 2) Tile size same logic
        let sphereArea = 4.0 * Float.pi * radius * radius
        let areaPerTile = sphereArea / Float(tileCount)
        let approxSide = sqrt(areaPerTile)
        let tileSize = min(0.18, max(0.05, approxSide * 0.65))

        // 3) 2D coords via PCA + normalize
        var itemUV = projector.project(vectors)
        LayoutAssignment.normalizeInPlaceToMinus1Plus1(&itemUV)

        // 4) Build candidate points (Fibonacci) and UV
        let goldenAngle = Float.pi * (3.0 - sqrt(5.0))
        let front = SIMD3<Float>(0, 0, 1)

        struct Candidate {
            let unit: SIMD3<Float>
            let uv: SIMD2<Float> // in [-1,1]
            let frontness: Float
        }

        var candidates: [Candidate] = []
        candidates.reserveCapacity(tileCount)

        for i in 0 ..< tileCount {
            let t = (Float(i) + 0.5) / Float(tileCount)
            let y = 1.0 - 2.0 * t
            let rAtY = sqrt(max(0.0, 1.0 - y * y))
            let theta = goldenAngle * Float(i)

            let x = sin(theta) * rAtY
            let z = cos(theta) * rAtY
            let unit = SIMD3<Float>(x, y, z)

            // thetaNormalized: [-π, π] -> [-1,1]
            let thetaNorm = atan2(unit.x, unit.z) / Float.pi
            let uv = SIMD2<Float>(thetaNorm, unit.y)

            candidates.append(
                Candidate(unit: unit, uv: uv, frontness: simd_dot(unit, front))
            )
        }

        // Optional: rotate candidate u so “most front-facing” aligns with item 0 u
        if let bestFront = candidates.max(by: { $0.frontness < $1.frontness }) {
            let desiredTheta = itemUV[0].x
            let currentTheta = bestFront.uv.x
            let shift = desiredTheta - currentTheta

            candidates = candidates.map { c in
                let u = LayoutAssignment.wrapMinus1Plus1(c.uv.x + shift)
                return Candidate(unit: c.unit, uv: SIMD2<Float>(u, c.uv.y), frontness: c.frontness)
            }
        }

        // 5) Greedy assignment in UV space
        let assignment = LayoutAssignment.greedyAssign(
            items: itemUV,
            candidates: candidates.map(\.uv)
        )

        // 6) Create placements
        var out: [TilePlacement] = []
        out.reserveCapacity(tileCount)

        for i in 0 ..< tileCount {
            let cIndex = assignment[i]
            let unit = candidates[cIndex].unit
            let pos = unit * radius
            out.append(
                TilePlacement(
                    index: i,
                    position: pos,
                    outward: simd_normalize(pos),
                    tileSize: tileSize
                )
            )
        }

        return out
    }

    // MARK: - Vector conversion (matches your runner helper)

    private func toFloatVector(_ any: Any?) -> [Float]? {
        guard let any else { return nil }
        if let f = any as? [Float] { return f }
        if let d = any as? [Double] { return d.map(Float.init) }
        if let n = any as? [NSNumber] { return n.map { $0.floatValue } }
        if let a = any as? [Any] {
            let v = a.compactMap {
                if let f = $0 as? Float { return f }
                if let d = $0 as? Double { return Float(d) }
                if let n = $0 as? NSNumber { return n.floatValue }
                return nil
            }
            return v.isEmpty ? nil : v
        }
        return nil
    }
}
