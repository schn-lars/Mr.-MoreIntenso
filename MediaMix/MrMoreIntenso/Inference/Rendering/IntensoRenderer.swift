//
//  IntensoRenderer.swift
//  MediaMix
//
//  Created by Lars Schneider on 12.03.2026.
//

import SwiftUI
import RealityKit
import CoreML
import ARKit
import CoreLocation

// might be needed for segmentation rendering or even calculations
// https://developer.apple.com/documentation/metal/performing-calculations-on-a-gpu

final class IntensoRenderer {
    weak var appSettings: AppSettings?
    
    var detectionMap: [UUID : DetectionRenderData] = [:]
    var entityMap: [UUID : AnchorEntity] = [:]
    var meshEntityMap: [UUID : Entity] = [:]
    var placementExtrinsics: [UUID : simd_float4x4] = [:]
    var timingMap: [UUID : Date] = [:] // if not part of the detection, we do not want flickering
    
    var sharedMarkerMap: [UUID: AnchorEntity] = [:]
    
    private var content: RealityKit.RealityViewContent?
    private var scene: RealityKit.Scene?
    
    private let degreeSimilarity: Float = 30.0
    private let timeToForgetObject: TimeInterval = 4.0
    private let bboxBorderSize: Float = 0.005
    
    /*
     (736.633911, 0.000000, 0.000000)   -> [fx,    -,     -]
     (0.000000, 736.633911, 0.000000)   -> [- ,   fy,     -]
     (960.000000, 540.000000, 1.000000) -> [cx,   cy,     1]
     */
    
    /// Camera Specs from intrinsics
    private let fx: Float = 736.634
    private let fy: Float = 736.634
    private let cx: Float = 960.0
    private let cy: Float = 540.0
    private let imageW: Float = 1920
    private let imageH: Float = 1080
    private let depth: Float = 1.5 // meters in front of head
    
    private let hFOVDeg: Float = 82.0 // horizontal FOV
    private let vFOVDeg: Float = 60.0 // vertical FOV
    private let cameraOffset: SIMD3<Float> = SIMD3(0.02476, -0.02140, -0.05717)

    private var planeW: Float { depth * imageW / fx }
    private var planeH: Float { depth * imageH / fy }
    init() {}
    
    // https://developer.apple.com/documentation/visionos/placing-entities-using-head-and-device-transform
    func setup(_ content: RealityViewContent) {
        self.content = content // should be the same for both. Exists a single scene per View
        
        Task { @MainActor in
            for _ in 0..<10 {
                if let s = content.entities.first?.scene {
                    self.scene = s
                    print("IntensoRenderer: scene cached, raycast now available")
                    break
                }
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
        }
    }
    
    @MainActor
    func apply(result: ProcessedObservations) {
        //print("IntensoRenderer: apply TRACE applying \(objects.count) objects")
        //print("IntensoRenderer: apply — \(objects.count) objects, \(entityMap.count) entities")
        guard let extrinsics = result.extrinsics else {
            print("IntensoRenderer: apply GUARD no extrinsics")
            return
        }
        for obj in result.trackedObservations {
            //print("Camera world position:", obj.extrinsics)
            //print("IntensoRenderer: apply TRACE processing \(obj.label)")
            let centerX = obj.bbox.x + obj.bbox.width / 2.0
            let centerY = obj.bbox.y + obj.bbox.height / 2.0
            guard let realDepth = sampleDepth (
                normX: centerX,
                normY: centerY,
                cameraTransform: extrinsics
            ) else {
                //print("IntensoRenderer: apply GUARD no depth")
                continue
            }

            //print("apply: Camera forward=", extrinsics.columns.2)
            
            refreshTimingIfVisible(
                label: obj.label,
                normX: centerX,
                normY: centerY,
                extrinsics: extrinsics
            )
            
            //print("IntensoRenderer: apply TRACE realDepth for \(obj.label)=\(realDepth)")
            
            /*
            /// (0.5, 0.0) -> Top
            /// (0.5, 1.0) -> Bottom
            /// (0.0, 0.5) -> left
            /// (1.0, 0.5) -> Right
            */
            let worldPosition = unprojectToWorld(
                normX: centerX,
                normY: centerY,
                depth: realDepth,
                cameraTransform: extrinsics
            )
            
            guard simd_length(worldPosition) > 0.1 else {
                print("IntensoRenderer: apply GUARD - worldPosition is origin skipping")
                continue
            }
            
            let w = obj.bbox.width * realDepth * imageW / fx
            let h = obj.bbox.height * realDepth * imageH / fy
            
            if let (existingID, anchor) = findNearbyEntity(
                worldPosition: worldPosition,
                label: obj.label,
                cameraPosition: extrinsics.columns.3.toFloat3()
            ) {
                //print("IntensoRenderer: apply TRACE - found nearby Entity [\(obj.label)]")
                //entity.setPosition(worldPosition, relativeTo: nil) // do not set position again since we are in the world now
                // if the object was seen, it is okay to assume it may stay longer.
                timingMap.updateValue(.now, forKey: existingID)
                guard let pastExtrinsics = placementExtrinsics[existingID] else {
                    print("IntensoRenderer: apply GUARD pastExtrinsics is nil")
                    continue
                }
                let angle = angularDistance(from: pastExtrinsics, to: extrinsics)
                guard angle > 5.0 else { continue }
                anchor.setPosition(worldPosition, relativeTo: nil)
                placementExtrinsics[existingID] = extrinsics
                
                detectionMap.updateValue(
                    DetectionRenderData(
                        label: obj.label,
                        confidence: obj.confidence,
                        bbox: obj.bbox,
                        croppedImage: obj.image
                    ),
                    forKey: obj.id
                )
            } else {
                //print("IntensoRenderer: apply TRACE - checking predicates for new [\(obj.label)]")
                /// if id already inside the entityMap, then we lose reference to the anchor!
                /// this could happen, if findNearbyEntity does not work.
                if entityMap.keys.contains(obj.id) { continue }
                if !isInCenter(centerX: centerX, centerY: centerY) { continue }
                //print("IntensoRenderer: apply TRACE - new entity found [\(obj.label)]")
                
                /// following line prints out worldPosition as well extracted depth
                //printPosition(label: obj.label, depth: realDepth, pos: worldPosition)
                
                /// unsure about this one but I think migth be good to do so
                /// Actually, `killingRaycast` is designed to kill objects that are not the same detection
                /// If an other instance is already there, we should simply continue
                
                /*
                /// This could work if we had a plane for our bounding boxes
                /// we simply have a rectangle of some arcs meaning we rarely get hits
                /// would most likely solve the issue of overlaps, then again, is it worth it?
                /// Since a ML model is not always correct it sometimes sees objects that are significantlly
                /// smaller, than the object in plain sight (i.e. keyboar of laptop is seen but not laptop)
                 
                let shouldAdd = killingRaycast(
                    normX: centerX,
                    normY: centerY,
                    cameraTransform: extrinsics,
                    newEntityDepth: realDepth,
                    newEntityArea: obj.bbox.width * obj.bbox.height
                )
                
                /// same goes for killingNeighbors that is taking the distance into account.
                /// Problem here is the depth which we hardly can account for without causing unwanted effects
                /// of removing objects which should be rendered. For instance, an object could be right in front
                /// of an other but 2m in front (i.e. laptop in front of you and a chair in the background).
                /// Since the bounding boxes are technically (in 2D) on top or even inside each other, we would
                /// need a threshold of 2m+ to get rid of the bounding box behind. But that 2m means,
                /// that no other bounding box can be placed in a radius of 2 meters from any bounding box which
                /// is not ideal either.
                 
                let shouldAdd = killingNeighbors(
                    newEntityPosition: worldPosition,
                    newEntityArea: obj.bbox.width * obj.bbox.height,
                    distanceThreshold: 0.25
                )
                */
                
                let shouldAdd = suppressOverlapping(
                    newBBox: obj.bbox,
                    newArea: obj.bbox.width * obj.bbox.height
                )
                
                guard shouldAdd else { continue }
                
                let entity = createEntity(obj: obj, width: w, height: h)
                
                let anchor = AnchorEntity(world: worldPosition)
                anchor.addChild(entity)
                
                //entity.setPosition(worldPosition, relativeTo: nil)
                let cameraPosition = extrinsics.columns.3.toFloat3()
                //anchor.look(
                //    at: cameraPosition,
                //    from: worldPosition,
                //    relativeTo: nil
                //)
                
                //entity.look(at: cameraPostion, from: worldPosition, relativeTo: nil)
                
                let forward = simd_normalize(cameraPosition - worldPosition)
                
                let worldUp = SIMD3<Float>(0, 1, 0)
                
                let right = simd_normalize(simd_cross(worldUp, forward))
                let up = simd_cross(forward, right)
                
                let rotMatrix = float3x3(columns: (right, up, forward))
                
                /// this was used to determine the rotation matrices as I had a bug where at a certain threshold
                /// the bounding boxes were rotated by 180 degrees. This helped to figure out why.
                //if obj.label == "dishwasher" || obj.label == "shampoo" {
                //    print("IntensoRenderer: apply TRACE rotmatrix for  \(obj.label)=\(rotMatrix)")
                //}
                anchor.orientation = simd_quatf(rotMatrix)
                
                entityMap[obj.id] = anchor
                timingMap.updateValue(.now, forKey: obj.id)
                placementExtrinsics.updateValue(extrinsics, forKey: obj.id)
                detectionMap.updateValue(
                    DetectionRenderData(
                        label: obj.label,
                        confidence: obj.confidence,
                        bbox: obj.bbox,
                        croppedImage: obj.image
                    ),
                    forKey: obj.id
                )
                content?.add(anchor)
                //print("IntensoRenderer: added entity '\(obj.label)' now at \(counter)<:>\(content?.entities.count)")
            }
        }
        
        cleanup()
        // cleaning up while iterating over the content's entities
        //print("IntensoRenderer: update TRACE number of entities \(content?.entities.count)")
    }
    
    private func printPosition(
        label: String,
        depth: Float,
        pos: SIMD3<Float>
    ) {
        print("IntensoRenderer: printPosition DEBUG label=\(label) depth=\(depth) pos=\(pos)")
    }
    
    /**
        This method is a somewhat simple implementation to determine wether the user is looking at that object.
     */
    private func isInCenter(centerX: Float, centerY: Float) -> Bool {
        return  (0.4 < centerX && centerX < 0.6) &&
                (0.4 < centerY && centerY < 0.7)
    }
    
    @MainActor
    private func cleanup() {
        /// Cleanup
        let toRemove = timingMap.filter({ $0.value + timeToForgetObject < .now })
        for (id, _) in toRemove {
            if let anchor = entityMap[id] {
                content?.remove(anchor)
            }
            entityMap.removeValue(forKey: id)
            placementExtrinsics.removeValue(forKey: id)
            timingMap.removeValue(forKey: id)
            detectionMap.removeValue(forKey: id)
        }
    }
    
    @MainActor
    func removeAllObjects(except: UUID?, shared: Bool = false) {
        let toRemove = entityMap.filter({ $0.key != except ? except != nil : true })
        
        for id in toRemove.keys {
            if let anchor = entityMap[id] {
                content?.remove(anchor)
            }
            entityMap.removeValue(forKey: id)
            placementExtrinsics.removeValue(forKey: id)
            timingMap.removeValue(forKey: id)
            detectionMap.removeValue(forKey: id)
        }
        
        /// SharedObjects
        if shared { removeSharedMarker(except: except) }
    }
    
    /*
     This method refresh timing for any entity whose label matches AND whose direction from camera is similar
    */
    private func refreshTimingIfVisible(
        label: String,
        normX: Float,
        normY: Float,
        extrinsics: simd_float4x4
    ) {
        let px = normX * imageW
        let py = normY * imageH
        let rayDirCamera = simd_normalize(SIMD3<Float>(
            (px - cx) / fx,
            (py - cy) / fy,
            1.0
        ))
        let camRot = simd_float3x3(
            extrinsics.columns.0.toFloat3(),
            extrinsics.columns.1.toFloat3(),
            extrinsics.columns.2.toFloat3()
        )
        let rayDir = camRot * rayDirCamera
        let camPos = extrinsics.columns.3.toFloat3()
        
        for (id, anchor) in entityMap {
            guard anchor.children.contains(where: { $0.name == label }) else { continue }
            
            // Direction from camera to this entity
            let toEntity = simd_normalize(anchor.position(relativeTo: nil) - camPos)
            let dot = simd_clamp(simd_dot(rayDir, toEntity), -1.0, 1.0)
            let angleDeg = acos(dot) * 180 / .pi
            
            // If detection ray points roughly at this entity, refresh it
            if angleDeg < 15.0 {
                timingMap[id] = .now
            }
        }
    }
    
    private func findNearbyEntity(
        worldPosition: SIMD3<Float>,
        label: String,
        cameraPosition: SIMD3<Float>,
        threshold: Float = 0.6 // in meters
    ) -> (id: UUID, anchor: AnchorEntity)? {
        var bestID: UUID? = nil
        var bestAngle: Float = .infinity
        for (id, anchor) in entityMap {
            /// needs to be the same object kind
            guard anchor.children.contains(where: {
                $0.name == label
            }) else { continue }

            let entityPos = anchor.position(relativeTo: nil)
            
            // 1. angle
            let toExisting = simd_normalize(entityPos - cameraPosition)
            let toNew = simd_normalize(worldPosition - cameraPosition)
            let dot = simd_clamp(simd_dot(toExisting, toNew), -1.0, 1.0)
            let angleDeg = acos(dot) * 180 / .pi
            
            if angleDeg < bestAngle {
                bestAngle = angleDeg
                bestID = id
            }
        }
        //print("IntensoRenderer: findNearbyEntity TRACE - none was found \(label)")
        let anglularThreshold: Float = 15.0
        if let id = bestID, bestAngle < anglularThreshold, let anchor = entityMap[id] {
            return (id, anchor)
        }
        return nil
    }
    
    // https://en.wikipedia.org/wiki/Dot_product
    private func angularDistance(
        from oldExtrinsics: simd_float4x4,
        to newExtrinsics: simd_float4x4
    ) -> Float {
        let oldForward = simd_normalize(oldExtrinsics.columns.2.toFloat3())
        let newForward = simd_normalize(newExtrinsics.columns.2.toFloat3())
        let dotProduct = simd_clamp(simd_dot(oldForward, newForward), -1.0, 1.0)
        return acos(dotProduct) * 180 / .pi
    }
    
    @MainActor
    func sampleDepth(
        normX: Float,
        normY: Float,
        cameraTransform: simd_float4x4?
    ) -> Float? {
        //print("IntensoRenderer: sampleDepth TRACE [\(normX), \(normY)]")
        guard let cameraTransform = cameraTransform else {
            print("IntensoRenderer: sampleDepth GUARD cameraTransform is nil")
            return nil
        }
        
        guard let scene else {
            print("IntensoRenderer: sampleDepth GUARD scene is nil")
            return nil
        }

        let px = normX * imageW
        let py = normY * imageH

        /*
        let rayDirCamera = simd_normalize(SIMD3<Float>(
            (px - cx) / fx,
            -((py - cy) / fy),
            -1.0
        ))
        */
        
        let rayDirCamera = simd_normalize(SIMD3<Float>(
            (px - cx) / fx,
            (py - cy) / fy,
            1.0
        ))
        
        
        //print("IntensoRenderer: sampleDepth TRACE rayDirCamera \(rayDirCamera)")

        // Rotate into world space using camera orientation
        let camRot = simd_float3x3(
            cameraTransform.columns.0.toFloat3(),
            cameraTransform.columns.1.toFloat3(),
            cameraTransform.columns.2.toFloat3()
        )
        let rayOrigin = cameraTransform.columns.3.toFloat3()
        let rayDir = camRot * rayDirCamera
        
        //debugRay(origin: rayOrigin, dir: rayDir)
        //print("IntensoRenderer: sampleDepth TRACE rayDir=\(rayDir), rayOrigin=\(rayOrigin)")

        let hits = scene.raycast(
            from: rayOrigin,
            to: rayOrigin + rayDir * 10.0
        )
        //print("sampleDepth: rayDir=\(rayDir) hits=\(hits.count)")
        for hit in hits {
            var current: Entity? = hit.entity
            while let entity = current {
                if entity.components.has(SceneMeshTag.self) {
                    //print("IntensoRenderer: sampleDepth TRACE - mesh hit depth =", hit.distance)
                    let distance = hit.distance
                    
                    if distance < 0.1 { continue }
                    if distance > 6.0 { continue }
                    return Float(hit.distance)
                }
                current = entity.parent
            }
        }
        //print("IntensoRenderer: sampleDepth TRACE no hit DEFAULT \(depth)m")
        return nil
    }
    
    private func debugRay(origin: SIMD3<Float>, dir: SIMD3<Float>) {
        let length: Float = 2.0
        
        let mesh = MeshResource.generateBox(size: [0.05, 0.05, length])
        let mat = SimpleMaterial(color: .red, isMetallic: false)
        
        let rayEntity = ModelEntity(mesh: mesh, materials: [mat])
        
        let worldPos = origin + dir * (length / 2)
        rayEntity.setPosition(worldPos, relativeTo: nil)
        rayEntity.look(at: origin + dir * length, from: worldPos, relativeTo: nil)

        content?.add(rayEntity)
    }
    
    private func createEntity(obj: TrackedObject, width: Float, height: Float) -> ModelEntity {
        let mesh = MeshResource.generatePlane(
            width: width,
            height: height
        )
        
        let material: RealityKit.Material

        if appSettings?.inferenceTask == .SEG,
           let mask = obj.mask,
           let texture = maskToTexture(mask, label: obj.label) {

            // Use UnlitMaterial so the mask isnt affected by scene lighting
            var unlitMaterial = UnlitMaterial()
            unlitMaterial.color = .init(
                tint: .white.withAlphaComponent(0.99),
                texture: .init(texture)
            )
            unlitMaterial.blending = .transparent(opacity: .init(floatLiteral: 1.0))
            material = unlitMaterial
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.name = obj.label
            //print("Creating entity '\(obj.label)' size=(\(w), \(h)) at will be placed at bbox \(obj.bbox)")
            return entity
        } else {
            return createBBoxBorderEntity(obj: obj, width: width, height: height)
        }
    }
    
    // When you receive a MeshAnchor update from SceneReconstructionProvider
    @MainActor // needs to be main character
    func updateMeshEntity(
        id: UUID,
        shape: ShapeResource,
        //meshResource: MeshResource,
        transform: simd_float4x4
    ) async throws {
        if let existing = meshEntityMap[id] {
            existing.components[CollisionComponent.self] = CollisionComponent(
                shapes: [shape],
                mode: .colliding
            )
            existing.transform = Transform(matrix: transform)
        } else {
            let anchor = AnchorEntity(world: transform)
            
            /// Visualizing the mesh:
            /*
            var material = UnlitMaterial()
            material.color = .init(tint: UIColor.cyan.withAlphaComponent(0.3))
            let visibleEntity = ModelEntity(mesh: meshResource, materials: [material])
            anchor.addChild(visibleEntity)
            */
             
            let collisionEntity = Entity()
            collisionEntity.components.set(
                CollisionComponent(
                    shapes: [shape],
                    mode: .colliding
                )
            )
            collisionEntity.components.set(SceneMeshTag())
            anchor.addChild(collisionEntity)
            
            content?.add(anchor)
            meshEntityMap[id] = anchor
        }
    }
    
    @MainActor
    func removeMeshEntity(id: UUID) {
        if let entity = meshEntityMap.removeValue(forKey: id) {
            content?.remove(entity)
        }
    }
    
    private func unprojectToWorld(
        normX: Float,
        normY: Float,
        depth: Float,
        cameraTransform: simd_float4x4
    ) -> SIMD3<Float> {
        let px = normX * imageW
        let py = normY * imageH

        let rayDirCamera = simd_normalize(SIMD3<Float>(
            (px - cx) / fx,
            (py - cy) / fy,
            1.0 // before: -1.0
        ))
        let camRot = simd_float3x3(
            cameraTransform.columns.0.toFloat3(),
            cameraTransform.columns.1.toFloat3(),
            cameraTransform.columns.2.toFloat3()
        )
        let rayOrigin = cameraTransform.columns.3.toFloat3()

        return rayOrigin + (camRot * rayDirCamera) * depth
    }
    
    private func maskToTexture(
        _ mask: [Bool],
        label: String,
        width: Int = 256,
        height: Int = 256
    ) -> TextureResource? {
        let color = getColor(label: label)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: nil)
        let rByte = UInt8(r * 255)
        let gByte = UInt8(g * 255)
        let bByte = UInt8(b * 255)

        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        for i in 0..<mask.count {
            let base = i * 4
            if mask[i] {
                pixels[base]     = rByte
                pixels[base + 1] = gByte
                pixels[base + 2] = bByte
                pixels[base + 3] = 180
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                  width: width, height: height,
                  bitsPerComponent: 8, bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil, shouldInterpolate: true,
                  intent: .defaultIntent
              )
        else { return nil }

        return try? TextureResource(image: cgImage, options: .init(semantic: .color))
    }
    
    /**
        This method is supposed to cast a ray which kills any BoundingBox entity in its way.
        The return value is used to decide wether a new bounding box should be placed or not.
     */
    @MainActor
    private func killingRaycast(
        normX: Float,
        normY: Float,
        cameraTransform: simd_float4x4?,
        newEntityDepth: Float,
        newEntityArea: Float
    ) -> Bool {
        guard let cameraTransform = cameraTransform else {
            print("IntensoRenderer: killingRaycast GUARD cameraTransform is nil")
            return true
        }
        
        guard let scene else {
            print("IntensoRenderer: killingRaycast GUARD scene is nil")
            return true
        }
        
        let px = normX * imageW
        let py = normY * imageH
        let rayDirCamera = simd_normalize(SIMD3<Float>(
            (px - cx) / fx,
            (py - cy) / fy,
            1.0
        ))
        let camRot = simd_float3x3(
            cameraTransform.columns.0.toFloat3(),
            cameraTransform.columns.1.toFloat3(),
            cameraTransform.columns.2.toFloat3()
        )
        let rayOrigin = cameraTransform.columns.3.toFloat3()
        let rayDir = camRot * rayDirCamera
    
        let hits = scene.raycast(
            from: rayOrigin,
            to: rayOrigin + rayDir * 10.0
        )
        for hit in hits {
            guard let hitAnchor = entityMap.first(where: {
                $0.value.children.contains(hit.entity) || $0.value == hit.entity
            }) else { continue }
            
            let existingID = hitAnchor.key
            
            guard let existingData = detectionMap[existingID] else { continue }
            let existingArea = existingData.bbox.width * existingData.bbox.height
            
            if newEntityArea >= existingArea {
                return false
            } else {
                // current one is at least smaller, causing this one to be evitected anyways
                timingMap[existingID] = .distantPast
            }
        }
        return true
    }
    
    @MainActor
    private func killingNeighbors(
        newEntityPosition: SIMD3<Float>,
        newEntityArea: Float,
        distanceThreshold: Float = 0.25
    ) -> Bool {
        var neighbors: [(id: UUID, area: Float)] = [] // maps uuid to area
        for (id, anchor) in entityMap {
            let distance = simd_distance(
                anchor.position(relativeTo: nil),
                newEntityPosition
            )
            
            // filter out non-neighbors
            if distanceThreshold < distance { continue }
            
            guard let detection = detectionMap[id] else {
                continue
            }
            
            let area = detection.bbox.width * detection.bbox.height
            neighbors.append((id: id, area: area))
        }
        neighbors.sort(by: { $0.area < $1.area })
        
        guard let nearestNeighbor = neighbors.first else {
            // no neighbors found, therefore can add without problems
            return true
        }
        
        if nearestNeighbor.area <= newEntityArea {
            for neighborToBeKilled in neighbors.dropFirst() {
                timingMap[neighborToBeKilled.id] = .distantPast
            }
            return false
        }
        
        return true
    }
    
    @MainActor
    private func suppressOverlapping(
        newBBox: BoundingBox,
        newArea: Float
    ) -> Bool {
        var overlappingIDs: [UUID] = []

        for (id, detection) in detectionMap {
            let overlap = iou(bbox1: newBBox, bbox2: detection.bbox)

            if overlap > 0.2 {
                overlappingIDs.append(id)
            }
        }
        
        for id in overlappingIDs {
            guard let existing = detectionMap[id] else {
                continue
            }
            let existingArea = existing.bbox.width * existing.bbox.height

            if existingArea <= newArea {
                return false
            }
            timingMap[id] = .distantPast
        }
        return true
    }
    
    /// copied from object tracker
    private func iou(bbox1: BoundingBox, bbox2: BoundingBox) -> Float {
        // https://www.v7labs.com/blog/intersection-over-union-guide
        let a_inter = max(bbox1.x, bbox2.x)
        let b_inter = max(bbox1.y, bbox2.y)
        let c_inter = min(bbox1.width + bbox1.x, bbox2.width + bbox2.x)
        let d_inter = min(bbox1.height + bbox1.y, bbox2.height + bbox2.y)
        
        if c_inter < a_inter || d_inter < b_inter { return 0.0 }
        
        let intersection_area = (c_inter - a_inter) * (d_inter - b_inter)
        let area_one = bbox1.width * bbox1.height
        let area_two = bbox2.width * bbox2.height
        let union_area = area_one + area_two - intersection_area
        
        return intersection_area / union_area
    }
    
    /**
        This method is responsible to create a boundary around the object that has been detected.
     */
    private func createBBoxBorderEntity(obj: TrackedObject, width: Float, height: Float) -> ModelEntity {
        let thickness = bboxBorderSize
        let color = getColor(label: obj.label).withAlphaComponent(0.9)
        let mat = SimpleMaterial(color: color, isMetallic: false)
        
        let root = ModelEntity()
        root.name = obj.label
        
        /// Collision logic:
        let shape = ShapeResource.generateBox(
            width: width,
            height: height,
            depth: 0.01
        )
        
        root.components.set(ObjectIDComponent(id: obj.id))
        root.components.set(
            CollisionComponent(
                shapes: [shape],
                mode: .trigger
            )
        )
        
        // for gestures
        root.components.set(InputTargetComponent())
        root.components.set(HoverEffectComponent())
        
        // top, bottom, left, right lines
        let segments: [(width: Float, height: Float, dx: Float, dy: Float)] = [
            (width      , thickness ,  0, (height - thickness) / 2),
            (width      , thickness ,  0, -(height - thickness) / 2),
            (thickness  , height    , -(width - thickness) / 2  , 0),
            (thickness  , height    ,  (width - thickness) / 2  , 0)
        ]
            
        for seg in segments {
            //let mesh = MeshResource.generatePlane(width: seg.width, height: seg.height)
            let mesh = MeshResource.generateBox(width: seg.width, height: seg.height, depth: 0.02)
            let strip = ModelEntity(mesh: mesh, materials: [mat])
            strip.position = SIMD3(seg.dx, seg.dy, 0)
            root.addChild(strip)
        }
        let textMesh = MeshResource.generateText(
            obj.label,
            extrusionDepth: 0.001,
            font: .systemFont(ofSize: 0.05), // TODO: possibly adapt to settings
            containerFrame: .zero,
            alignment: .left,
            lineBreakMode: .byTruncatingTail
        )
        let textEntity = ModelEntity(mesh: textMesh, materials: [mat])
        textEntity.position = SIMD3(-(width / 2), (height / 2) + thickness + 0.005, 0)
        root.addChild(textEntity)
        
        return root
    }
    
    private func getColor(label: String) -> UIColor {
        /// Since we technically have a dynamic (and presumebly infite amount of possible labels)
        /// We need to find a way to react to these dynamic labels
        /// by assigning as many different colors as possible
        ///
        /// https://stackoverflow.com/questions/2328339/how-to-generate-n-different-colors-for-any-natural-number-n
        /// The attribute `colors` has been fetched from that thread as well.
        let hue = CGFloat(label.getStableRepresentation() % 360) / 360
        return UIColor(
            hue: hue,
            saturation: 0.8,
            brightness: 0.9,
            alpha: 0.5
        )
    }
    
    func renderSharedObjectEntity(data: SharedMarkerData) {
        guard let content else { return }
        
        if sharedMarkerMap.keys.contains(data.id) { return }
        
        removeSharedMarker(id: data.id)
        
        let root = AnchorEntity(world: data.worldPosition)
        
        // pole
        let segmentHeight: Float = 0.08
        let gap: Float = 0.04
        let poleHeight: Float = 1.2
        let count = Int(poleHeight / (segmentHeight + gap))

        for i in 0..<count {
            let segmentMesh = MeshResource.generateCylinder(
                height: segmentHeight,
                radius: 0.004
            )

            var material = UnlitMaterial()
            material.color = .init(tint: UIColor(
                red: 0.50, green: 0.47, blue: 0.87, alpha: 0.55
            ))

            let segment = ModelEntity(mesh: segmentMesh, materials: [material])

            let y = Float(i) * (segmentHeight + gap) + (segmentHeight / 2)
            segment.position = SIMD3(0, y, 0)

            root.addChild(segment)
        }
        
        let discMesh = MeshResource.generateCylinder(height: 0.005, radius: 0.04)
        var discMaterial = UnlitMaterial()
        discMaterial.color = .init(tint: UIColor(red: 0.50, green: 0.47, blue: 0.87, alpha: 0.4))
        let disc = ModelEntity(mesh: discMesh, materials: [discMaterial])
        disc.position = SIMD3(0, 0.002, 0)
        root.addChild(disc)
        
        // label
        let labelEntity = makeSharedLabelEntity(data: data)
        labelEntity.position = SIMD3(0, poleHeight + 0.1, 0)
        labelEntity.components.set(BillboardComponent())
        labelEntity.components.set(SharedObjectTag(id: data.id))
        labelEntity.components.set(
            CollisionComponent(
                shapes: [.generateBox(size: SIMD3(0.35, 0.18, 0.02))],
                mode: .trigger
            )
        )
        labelEntity.components.set(InputTargetComponent())
        labelEntity.components.set(HoverEffectComponent())
        root.addChild(labelEntity)

        root.components.set(SharedObjectTag(id: data.id))
        content.add(root)
        sharedMarkerMap[data.id] = root
        print("IntensoRenderer: renderSharedObjectEntity TRACE - set up entity at \(data.worldPosition) - total: \(sharedMarkerMap.keys.count) entities")
    }
    
    /**
        This method is occasionally called by the RootImmersiveView to clean up the 3D space.
        The method lacks some form of deeper logic such as also including when the objects have been added.
        It simply removes objects that are closest from the current location of the device. This seems to be enough for now.
     */
    func removeFarthestSharedMarkerIfNeeded(
        deviceWorldTransform: simd_float4x4,
        keeping: Int = 5
    ) {
        if sharedMarkerMap.keys.count <= keeping { return }
        
        let devicePos = SIMD3<Float>(
            deviceWorldTransform.columns.3.x,
            deviceWorldTransform.columns.3.y,
            deviceWorldTransform.columns.3.z
        )
        
        let sorted = sharedMarkerMap
            .map { (id, anchor) -> (UUID, Float) in
                let markerPos = SIMD3<Float>(
                    anchor.position(relativeTo: nil).x,
                    anchor.position(relativeTo: nil).y,
                    anchor.position(relativeTo: nil).z
                )
                let dist = simd_distance(devicePos, markerPos)
                return (id, dist)
            }
            .sorted { $0.1 > $1.1 }
        
        let toRemove = sorted.dropLast(keeping)
        
        print("IntensoRenderer: removeFarthestSharedMarkerIfNeeded TRACE - removing \(toRemove.count) markers")
        for (id, _) in toRemove {
            removeSharedMarker(id: id)
        }
    }
    
    private func removeSharedMarker(id: UUID) {
        if let existing = sharedMarkerMap[id] {
            existing.removeFromParent()
            sharedMarkerMap.removeValue(forKey: id)
        }
    }
    
    private func removeSharedMarker(except id: UUID?) {
        guard let id = id else {
            removeAllSharedMarkers()
            return
        }
        
        let toRemove = sharedMarkerMap.filter({ $0.key != id })
        for (uuid, entity) in toRemove {
            if id == uuid { continue }
            entity.removeFromParent()
            sharedMarkerMap.removeValue(forKey: uuid)
        }
    }
    
    func removeAllSharedMarkers() {
        sharedMarkerMap.keys.forEach { removeSharedMarker(id: $0) }
    }
    
    /**
        Factory function for creating entity for shared label.
     */
    private func makeSharedLabelEntity(data: SharedMarkerData) -> Entity {
        // backgroudn to make it better visually understandable that it is clickable
        let cardMesh = MeshResource.generatePlane(width: 0.35, height: 0.2)
        var cardMat = UnlitMaterial()
        cardMat.color = .init(tint: UIColor(
            red: 0.10, green: 0.09, blue: 0.18, alpha: 0.75
        ))
        let card = ModelEntity(mesh: cardMesh, materials: [cardMat])
        
        let labelMesh = MeshResource.generateText(
            "\(data.label)",
            extrusionDepth: 0.001,
            font: .boldSystemFont(ofSize: 0.045),
            containerFrame: CGRect(x: -0.15, y: 0.01, width: 0.30, height: 0.08),
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )
        var labelMat = UnlitMaterial()
        labelMat.color = .init(tint: UIColor(red: 0.93, green: 0.92, blue: 1.0, alpha: 1.0))
        let labelText = ModelEntity(mesh: labelMesh, materials: [labelMat])
        labelText.position = SIMD3(0, 0, 0.002)
        card.addChild(labelText)
        
        let subMesh = MeshResource.generateText(
            "@\(data.owner) · \(Int(data.confidence * 100))%",
            extrusionDepth: 0.001,
            font: .systemFont(ofSize: 0.030),
            containerFrame: CGRect(x: -0.15, y: -0.07, width: 0.30, height: 0.05),
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )
        var subMat = UnlitMaterial()
        subMat.color = .init(tint: UIColor(red: 0.63, green: 0.60, blue: 0.87, alpha: 0.9))
        let subText = ModelEntity(mesh: subMesh, materials: [subMat])
        subText.position = SIMD3(0, 0, 0.002)
        card.addChild(subText)
        
        return card
    }
}
