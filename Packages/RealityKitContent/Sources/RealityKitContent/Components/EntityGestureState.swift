//
//  EntityGestureState.swift
//  RealityKitContent
//
//  Created by Rahel Kempf on 09.11.2024.
//

import RealityKit
import SwiftUI

public class EntityGestureState: ObservableObject {
    
    /// The entity currently being dragged if a gesture is in progress.
    var targetedEntity: Entity?
    
    // MARK: - Drag
    
    /// The starting position.
    var dragStartPosition: SIMD3<Float> = .zero
    
    /// Marks whether the app is currently handling a drag gesture.
    var isDragging = false
    
    /// When `rotateOnDrag` is`true`, this entity acts as the pivot point for the drag.
    var pivotEntity: Entity?
    
    var initialOrientation: simd_quatf?
    
    // MARK: - Magnify
    
    /// The starting scale value.
    var startScale: SIMD3<Float> = .one
    
    /// Marks whether the app is currently handling a scale gesture.
    var isScaling = false
    
    // MARK: - Rotation
    
    /// The starting rotation value.
    var startOrientation = Rotation3D.identity
    
    /// Marks whether the app is currently handling a rotation gesture.
    var isRotating = false
    
    public var isSelectingImage = false
    
    // MARK: - Singleton Accessor
    
    /// Retrieves the shared instance.
    @MainActor public static let shared = EntityGestureState()
}
