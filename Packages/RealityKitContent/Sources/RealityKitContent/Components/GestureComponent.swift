/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A component that handles standard drag, rotate, and scale gestures for an entity.
*/

import RealityKit
import SwiftUI

// MARK: -

/// A component that handles gesture logic for an entity.
public struct GestureComponent: Component, Codable {
    
    /// A Boolean value that indicates whether a gesture can drag the entity.
    public var canDrag: Bool = true
    
    /// A Boolean value that indicates if the drag should be excelerated in direction Z
    public var excelerateDragTowardsCamera: Bool = false
    
    /// A Boolean value that indicates whether a dragging can move the object in an arc, similar to dragging windows or moving the keyboard.
    public var pivotOnDrag: Bool = true
    
    /// A Boolean value that indicates whether a pivot drag keeps the orientation toward the
    /// viewer throughout the drag gesture.
    ///
    /// The property only applies when `pivotOnDrag` is `true`.
    public var preserveOrientationOnPivotDrag: Bool = true
    
    /// A Boolean value that indicates whether a gesture can scale the entity.
    public var canScale: Bool = true
    
    /// A Boolean value that indicates whether a gesture can rotate the entity.
    public var canRotate: Bool = true
    
    public var canTap: Bool = true
    
    public init() {}
    
    // MARK: - Drag Logic
    
    /// Handle `.onChanged` actions for drag gestures.
    @MainActor mutating func onChanged(value: EntityTargetValue<DragGesture.Value>) {
        guard canDrag else { return }
        
        let state = EntityGestureState.shared
        
        // Only allow a single Entity to be targeted at any given time.
        if state.targetedEntity == nil {
            state.targetedEntity = value.entity.parent
            state.initialOrientation = value.entity.parent!.orientation(relativeTo: nil)
        }
        
        if pivotOnDrag {
            handlePivotDrag(value: value)
        } else {
            handleFixedDrag(value: value)
        }
    }
    
    @MainActor mutating private func handlePivotDrag(value: EntityTargetValue<DragGesture.Value>) {
        
        let state = EntityGestureState.shared
        guard let entity = state.targetedEntity else { fatalError("Gesture contained no entity") }
        
        // The transform that the pivot will be moved to.
        var targetPivotTransform = Transform()
        
        // Set the target pivot transform depending on the input source.
        if let inputDevicePose = value.inputDevicePose3D {
            
            // If there is an input device pose, use it for positioning and rotating the pivot.
            targetPivotTransform.scale = .one
            targetPivotTransform.translation = value.convert(inputDevicePose.position, from: .local, to: .scene)
            targetPivotTransform.rotation = value.convert(AffineTransform3D(rotation: inputDevicePose.rotation), from: .local, to: .scene).rotation
        } else {
            // If there is not an input device pose, use the location of the drag for positioning the pivot.
            targetPivotTransform.translation = value.convert(value.location3D, from: .local, to: .scene)
        }
        
        if excelerateDragTowardsCamera {
            // a potential improvement in this would be to increase the translation not in direction z but in direction of the camera in general
            targetPivotTransform.translation.z *= 2
        }
        
        if !state.isDragging {
            // If this drag just started, create the pivot entity.
            let pivotEntity = Entity()
            
            guard let parent = entity.parent else { fatalError("Non-root entity is missing a parent.") }
            
            // Add the pivot entity into the scene.
            parent.addChild(pivotEntity)
            
            // Move the pivot entity to the target transform.
            pivotEntity.move(to: targetPivotTransform, relativeTo: nil)
            
            // Add the targeted entity as a child of the pivot without changing the targeted entity's world transform.
            pivotEntity.addChild(entity, preservingWorldTransform: true)
            
            // Store the pivot entity.
            state.pivotEntity = pivotEntity
            
            // Indicate that a drag has started.
            state.isDragging = true

        } else {
            // If this drag is ongoing, move the pivot entity to the target transform.
            // The animation duration smooths the noise in the target transform across frames.
            state.pivotEntity?.move(to: targetPivotTransform, relativeTo: nil, duration: 0.2)
        }
        
        if preserveOrientationOnPivotDrag, let initialOrientation = state.initialOrientation {
            state.targetedEntity?.setOrientation(initialOrientation, relativeTo: nil)
        }
    }
    
    @MainActor mutating private func handleFixedDrag(value: EntityTargetValue<DragGesture.Value>) {
        let state = EntityGestureState.shared
        guard let entity = state.targetedEntity else { fatalError("Gesture contained no entity") }
        
        if !state.isDragging {
            state.isDragging = true
            state.dragStartPosition = entity.scenePosition
        }
   
        let translation3D = value.convert(value.gestureValue.translation3D, from: .local, to: .scene)
        
        var offset = SIMD3<Float>(x: Float(translation3D.x),
                                  y: Float(translation3D.y),
                                  z: Float(translation3D.z))
        
        if excelerateDragTowardsCamera {
            offset.z *= 2
        }
        
        entity.scenePosition = state.dragStartPosition + offset
        if let initialOrientation = state.initialOrientation {
            state.targetedEntity?.setOrientation(initialOrientation, relativeTo: nil)
        }
    }
    
    /// Handle `.onEnded` actions for drag gestures.
    @MainActor mutating func onEnded(value: EntityTargetValue<DragGesture.Value>) {
        let state = EntityGestureState.shared
        state.isDragging = false
        
        if let pivotEntity = state.pivotEntity,
           pivotOnDrag {
            pivotEntity.parent!.addChild(state.targetedEntity!, preservingWorldTransform: true)
            pivotEntity.removeFromParent()
        }
        
        state.pivotEntity = nil
        state.targetedEntity = nil
    }

    // MARK: - Magnify (Scale) Logic
    
    /// Handle `.onChanged` actions for magnify (scale)  gestures.
    @MainActor mutating func onChanged(value: EntityTargetValue<MagnifyGesture.Value>) {
        let state = EntityGestureState.shared
        guard canScale, !state.isDragging else { return }
        
//        let entity = value.entity
        var entity = value.entity.parent
        if (entity == nil) {
            print("no parent")
            entity = value.entity
        }
        
        if !state.isScaling {
            state.isScaling = true
            state.startScale = entity!.scale
        }
        
        let magnification = Float(value.magnification)
        entity!.scale = state.startScale * magnification
    }
    
    /// Handle `.onEnded` actions for magnify (scale)  gestures
    @MainActor mutating func onEnded(value: EntityTargetValue<MagnifyGesture.Value>) {
        EntityGestureState.shared.isScaling = false
    }
    
    // MARK: - Rotate Logic
    
    /// Handle `.onChanged` actions for rotate  gestures.
    @MainActor mutating func onChanged(value: EntityTargetValue<RotateGesture3D.Value>) {
        let state = EntityGestureState.shared
        guard canRotate, !state.isDragging, !state.isSelectingImage else { return }
       
        var entity = value.entity.parent
        if (entity == nil) {
            entity = value.entity
        }
        
        if !state.isRotating {
            state.isRotating = true
            state.startOrientation = .init(entity!.orientation(relativeTo: nil))
        }
        
        let rotation = value.rotation
        let flippedRotation = Rotation3D(angle: rotation.angle,
                                         axis: RotationAxis3D(x: -rotation.axis.x,
                                                              y: rotation.axis.y,
                                                              z: -rotation.axis.z))
        let newOrientation = state.startOrientation.rotated(by: flippedRotation)
        entity!.setOrientation(.init(newOrientation), relativeTo: nil)
    }
    
    /// Handle `.onChanged` actions for rotate  gestures.
    @MainActor mutating func onEnded(value: EntityTargetValue<RotateGesture3D.Value>) {
        EntityGestureState.shared.isRotating = false
    }
    
    
//    // MARK: - Spatial Tap Logic
//    
//    /// Handle `.onChanged` actions for tap  gestures.
//    @MainActor mutating func onChanged(value: EntityTargetValue<SpatialTapGesture.Value>) {
//        let state = EntityGestureState.shared
//        guard canTap, !state.isDragging else { return }
//    }
//    
//    /// Handle `.onEnded` actions for tap gestures
//    @MainActor mutating func onEnded(value: EntityTargetValue<SpatialTapGesture.Value>) {
//        let name = value.entity.name
//        print("tap ended on \(name)")
//        
//        //TODO: open new view with the image named value.entity.name
//    }
}
