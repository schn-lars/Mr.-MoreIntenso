//
//  LayoutAssignment.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import Foundation
import simd

enum LayoutAssignment {
    /// Normalize coords to [-1,1] per axis (in-place).
    static func normalizeInPlaceToMinus1Plus1(_ coords: inout [SIMD2<Float>]) {
        guard !coords.isEmpty else { return }

        var minX = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude
        var maxY = -Float.greatestFiniteMagnitude

        for p in coords {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }

        let eps: Float = 1e-6
        let rangeX = max(eps, maxX - minX)
        let rangeY = max(eps, maxY - minY)

        for i in coords.indices {
            let nx = ((coords[i].x - minX) / rangeX) * 2.0 - 1.0
            let ny = ((coords[i].y - minY) / rangeY) * 2.0 - 1.0
            coords[i] = SIMD2<Float>(nx, ny)
        }
    }

    /// Items in dense areas first = better neighborhood preservation.
    static func densityOrder(_ items: [SIMD2<Float>]) -> [Int] {
        let n = items.count
        var scores: [(i: Int, nn: Float)] = []
        scores.reserveCapacity(n)

        for i in 0 ..< n {
            var best = Float.greatestFiniteMagnitude
            for j in 0 ..< n where j != i {
                let dx = items[i].x - items[j].x
                let dy = items[i].y - items[j].y
                let d = dx * dx + dy * dy
                if d < best { best = d }
            }
            scores.append((i, best))
        }

        // Smaller nn distance => denser => earlier
        scores.sort { $0.nn < $1.nn }
        return scores.map(\.i)
    }

    /// Greedy nearest-neighbor assignment:
    /// for each item i, pick closest unused candidate.
    /// O(n^2) but fine for ~1k.
    static func greedyAssign(items: [SIMD2<Float>], candidates: [SIMD2<Float>]) -> [Int] {
        let n = items.count
        precondition(candidates.count == n)

        var used = [Bool](repeating: false, count: n)
        var out = [Int](repeating: 0, count: n)

        let order = densityOrder(items)

        for idx in order {
            var bestJ = -1
            var bestD = Float.greatestFiniteMagnitude

            for j in 0 ..< n where !used[j] {
                let dx = items[idx].x - candidates[j].x
                let dy = items[idx].y - candidates[j].y
                let d = dx * dx + dy * dy
                if d < bestD {
                    bestD = d
                    bestJ = j
                }
            }

            used[bestJ] = true
            out[idx] = bestJ
        }

        return out
    }

    /// Wrap value to [-1,1] with period 2.
    static func wrapMinus1Plus1(_ x: Float) -> Float {
        var v = x
        while v > 1 {
            v -= 2
        }
        while v < -1 {
            v += 2
        }
        return v
    }
}
