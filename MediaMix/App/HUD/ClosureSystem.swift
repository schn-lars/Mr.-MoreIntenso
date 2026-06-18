import SwiftUI
import RealityKit

/// Code from: https://developer.apple.com/documentation/visionos/displaying-a-3d-object-that-moves-to-stay-in-a-person's-view#Update-the-entities-over-time
struct ClosureSystem: System {
    /// The query to check if the entity has the `ClosureComponent`.
    static let query = EntityQuery(where: .has(ClosureComponent.self))
    
    init(scene: RealityKit.Scene) {}
    
    /// Update entities with `ClosureComponent` at each render frame.
    func update(context: SceneUpdateContext) {
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard let comp = entity.components[ClosureComponent.self] else { continue }
            comp.closure(context.deltaTime)
        }
    }
}
