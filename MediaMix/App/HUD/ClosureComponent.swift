import SwiftUI
import RealityKit

/// Code from: https://developer.apple.com/documentation/visionos/displaying-a-3d-object-that-moves-to-stay-in-a-person's-view#Update-the-entities-over-time
struct ClosureComponent: Component {
    /// The closure that takes the time interval since the last update.
    let closure: (TimeInterval) -> Void


    init (closure: @escaping (TimeInterval) -> Void) {
        self.closure = closure
        ClosureSystem.registerSystem()
    }
}
