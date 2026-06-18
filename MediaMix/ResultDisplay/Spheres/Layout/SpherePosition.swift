//
//  SpherePosition.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import Foundation
import simd

/// Manages the positioning of result spheres.
/// Spheres are arranged on a semicircle around the user, filling the nearest free slot.
/// Merged spheres are placed at the midpoint between the two colliding spheres.
final class SpherePosition {
    static let shared = SpherePosition()

    /// Position for a sphere created by merging two other spheres.
    private var mergedPosition: SIMD3<Float>?

    /// Current candidate position for the next newly created sphere.
    private var newSpherePosition: SIMD3<Float> = .zero

    /// Offset for the entire layout (e.g. anchor/world origin).
    private var offset: SIMD3<Float> = .zero

    /// Radius of each sphere (used for collision-free spacing).
    let sphere_radius: Float = 0.5

    /// Radius (meters) of the semicircle arc on which spheres are placed.
    private var arcRadius: Float = 3.0

    /// Angular step between slots on the arc (radians).
    private var slotAngle: Float = 0.15

    /// Counter indicating how far we have filled the arc.
    private var counter: Int = 1

    private init() {
        // Set slotAngle so spheres are spaced by ~2.5 * sphere_radius along the arc
        slotAngle = (2.5 * sphere_radius) / arcRadius
    }

    // MARK: - Public API

    /// Determines the position of a new sphere, taking merge into account.
    func getSpherePosition(spherePositions: [SIMD3<Float>]) -> SIMD3<Float> {
        if let m = mergedPosition {
            mergedPosition = nil
            return m
        } else {
            updateNewSpherePosition(spherePositions: spherePositions)
            return newSpherePosition
        }
    }

    /// Store midpoint between two spheres before triggering merged query.
    func setMergePosition(positionA: SIMD3<Float>, positionB: SIMD3<Float>) {
        mergedPosition = (positionA + positionB) * 0.5
    }

    /// Reset layout origin/offset (used when clearing spheres / restarting).
    func resetSpherePosition(position: SIMD3<Float> = .zero) {
        offset = position
        newSpherePosition = position
        counter = 1
        mergedPosition = nil
    }

    /// Optional compatibility with the "NEW" API style (if you still call it anywhere).
    func consumeMergePosition() -> SIMD3<Float>? {
        defer { mergedPosition = nil }
        return mergedPosition
    }

    // MARK: - Internal placement

    /// Calculate the next free position on the semicircle (closest free slot first),
    /// and stack upwards once the arc exceeds π.
    private func updateNewSpherePosition(spherePositions: [SIMD3<Float>]) {
        // Search progressively further out on the arc, alternating left/right
        for i in 0 ... counter {
            for side in [1, -1] {
                var isPosFree = true
                var newPos = SIMD3<Float>.zero

                // Semicircle coordinates (same as your original)
                let theta = slotAngle * Float(i * side)
                newPos.x = sin(theta) * arcRadius
                newPos.z = arcRadius * (1 - cos(theta))
                newPos += offset

                // If the circle is "full", start a new circle above the current one
                if slotAngle * Float(i) >= .pi {
                    newPos.y += 1.5
                }

                // Collision-free check
                for position in spherePositions {
                    if distance(newPos, position) < sphere_radius * 2.2 {
                        isPosFree = false
                        break
                    }
                }

                if isPosFree {
                    newSpherePosition = newPos
                    if i == counter {
                        counter += 1
                    }
                    return
                }
            }
        }
    }
}
