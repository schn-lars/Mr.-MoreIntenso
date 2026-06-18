//
//  SphereTriggerFactory.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import Foundation
import RealityKit

enum SphereTriggerFactory {
    static func make(radius: Float, id: Int) -> TriggerVolume {
        let trigger = TriggerVolume(
            shape: ShapeResource.generateSphere(radius: radius)
        )

        trigger.components.set(
            CollisionComponent(shapes: [
                ShapeResource.generateSphere(radius: radius * 0.8),
            ])
        )

        trigger.name = "Trigger \(id)"
        return trigger
    }
}
