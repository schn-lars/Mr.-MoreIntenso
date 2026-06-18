//
//  RealityViewContainer.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import AudioToolbox
import Combine
import RealityKit
import RealityKitContent
import SwiftUI

struct RealityViewContainer: View {
    let detailedSegments: [DetailedSegment]
    @Binding var currentRotation: simd_float3

    @State private var lastDragPosition: CGSize = .zero

    @EnvironmentObject var resultsManager: ResultsManager
    @Environment(\.openWindow) private var openWindow

    /// Keep one collision subscription
    @State private var collisionSubscribed = false

    var body: some View {
        ZStack {
            RealityView { content, _ in
                // Ensure anchor is in scene once
                if !content.entities.contains(where: { $0 === resultsManager.sphereAnchor }) {
                    content.add(resultsManager.sphereAnchor)
                }

                // Visibility toggle
                if !resultsManager.areSpheresVisible {
                    clearAllSpheresEntitiesOnly()
                    return
                }

                // If there are new results, create a new sphere controller + entity
                if !resultsManager.sphereResults.isEmpty {
                    spawnSphereIfNeeded(content: content)
                }

            } update: { content, attachments in
                if !resultsManager.areSpheresVisible {
                    removeSphereFromSceneOnly(content)
                    return
                }

                // Update rotations
                updateSphereRotation()

                // Attachments: add settings view entities to each sphere entity
                for controller in resultsManager.spheres {
                    let id = controller.descriptor.id
                    if let textEntity = attachments.entity(for: attachmentID(for: id)) {
                        // Avoid double-add
                        guard controller.entity.children.first(where: { $0 === textEntity }) == nil else { continue }
                        controller.entity.addChild(textEntity, preservingWorldTransform: false)

                        textEntity.scenePosition.y += SpherePosition.shared.sphere_radius + 0.25
                    }
                }

            } attachments: {
                ForEach(resultsManager.spheres.indices, id: \.self) { idx in
                    let controller = resultsManager.spheres[idx]
                    let id = controller.descriptor.id

                    Attachment(id: attachmentID(for: id)) {
                        SphereSettings(controller: controller) {
                            Task { @MainActor in
                                controller.disableAndRemoveFromScene()
                                resultsManager.spheres.removeAll { $0 === controller }
                            }
                        }
                    }
                }
            }

            .installGestures()
            .gesture(tapGesture)
        }
    }

    // MARK: - Helpers

    private func attachmentID(for sphereID: Int) -> String {
        "Attachment \(sphereID)"
    }

    /// Creates a new sphere (controller + entity) only if it doesn't exist yet.
    private func spawnSphereIfNeeded(content: RealityViewContent) {
        guard !detailedSegments.isEmpty else { return }

        let newID = resultsManager.amountOfResults

        // already exists?
        guard !resultsManager.spheres.contains(where: { $0.descriptor.id == newID }) else { return }

        Task { @MainActor in
            // 1) compute resolution from result count (your old semantics)
            let resolution = computeResolution(resultCount: resultsManager.sphereResults.count)

            // 2) create entity
            let sphereEntity = SphereEntity(
                idNumber: newID,
                radius: SpherePosition.shared.sphere_radius
            )

            // 3) build descriptor + resultset
            let descriptor = SphereDescriptor(
                id: newID,
                database: resultsManager.database,
                query: resultsManager.query.map { text, type in
                    SphereQueryItem(text: text, type: type)
                }
            )

            let resultSet = SphereResultSet(segments: detailedSegments)

            // 4) controller
            let controller = SphereController(
                descriptor: descriptor,
                resultSet: resultSet,
                sphereEntity: sphereEntity
            )
            controller.resolution = Double(resolution)

            // 5) set rotation + position
            sphereEntity.transform.rotation = simd_quatf(
                angle: currentRotation.y,
                axis: [0, 1, 0]
            )

            let existingPositions = resultsManager.spheres.map {
                $0.entity.position(relativeTo: resultsManager.sphereAnchor)
            }

            let position = SpherePosition.shared.getSpherePosition(
                spherePositions: existingPositions
            )
            sphereEntity.position = position

            // 6) store + attach to anchor
            resultsManager.spheres.append(controller)
            resultsManager.sphereAnchor.addChild(sphereEntity)

            // 7) build tiles + textures
            await controller.rebuild()

            // 8) subscribe collision once
            subscribeCollisionsIfNeeded(content: content)

            print("Sphere \(newID) added. Total: \(resultsManager.spheres.count)")
        }
    }

    private func computeResolution(resultCount: Int) -> Int {
        var resolution = Int(ceil(sqrt(Float(resultCount) / 6.0))) + 1
        resolution = min(resolution, 14) // upper limit
        resolution = max(resolution, 2) // lower limit
        return resolution
    }

    private func subscribeCollisionsIfNeeded(content: RealityViewContent) {
        guard !collisionSubscribed else { return }
        collisionSubscribed = true

        let event = content.subscribe(to: CollisionEvents.Began.self) { ce in
            guard
                let sphereA = ce.entityA.parent as? SphereEntity,
                let sphereB = ce.entityB.parent as? SphereEntity
            else { return }

            // Keep behavior: only merge if A is "newer" than B
            guard sphereA.idNumber > sphereB.idNumber else { return }

            print("Collision \(ce.entityA.name) | \(ce.entityB.name)")
            mergeSphere(sphereA: sphereA, sphereB: sphereB)
        }

        resultsManager.addSubscription(event)
    }

    private func controller(for entity: SphereEntity) -> SphereController? {
        resultsManager.spheres.first { $0.entity === entity }
    }

    // MARK: - Merge

    private func mergeSphere(sphereA: SphereEntity, sphereB: SphereEntity) {
        guard
            let ctrlA = controller(for: sphereA),
            let ctrlB = controller(for: sphereB)
        else { return }

        // prevent collision on duplicates
        guard ctrlA.descriptor.query.first?.text != ctrlB.descriptor.query.first?.text else { return }

        // same database only
        guard ctrlA.descriptor.database == ctrlB.descriptor.database else {
            print("Queries must be from the same database to be merged \(ctrlA.descriptor.database), \(ctrlB.descriptor.database)")
            return
        }

        // Save parameters for the new query (keep your ResultsManager format)
        resultsManager.database = ctrlA.descriptor.database
        resultsManager.query = (ctrlA.descriptor.query + ctrlB.descriptor.query).map { ($0.text, $0.type) }

        SpherePosition.shared.setMergePosition(
            positionA: sphereA.position(relativeTo: resultsManager.sphereAnchor),
            positionB: sphereB.position(relativeTo: resultsManager.sphereAnchor)
        )

        disableAndRemoveSphere(entity: sphereA)
        disableAndRemoveSphere(entity: sphereB)
        resultsManager.performMergedQuery = true
    }

    private func disableAndRemoveSphere(entity: SphereEntity) {
        // remove collision trigger if present
        entity.trigger.removeFromParent()

        entity.isEnabled = false
        entity.removeFromParent()

        // remove controller
        resultsManager.spheres.removeAll { $0.entity === entity }
    }

    // MARK: - Scene cleanup

    private func clearAllSpheresEntitiesOnly() {
        resultsManager.sphereAnchor.children.forEach { $0.removeFromParent() }
    }

    private func removeSphereFromSceneOnly(_ content: RealityViewContent) {
        clearAllSpheresEntitiesOnly()
        content.remove(resultsManager.sphereAnchor)
        print("SphereEntity and anchor removed from RealityView")
    }

    // MARK: - Rotation

    private func updateSphereRotation() {
        for controller in resultsManager.spheres {
            controller.entity.transform.rotation = simd_quatf(
                angle: currentRotation.y,
                axis: [0, 1, 0]
            )
        }
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let deltaX = value.translation.width - lastDragPosition.width
                let rotationDelta = Float(deltaX / 100)
                currentRotation.y += rotationDelta
                lastDragPosition = value.translation
            }
            .onEnded { _ in
                lastDragPosition = .zero
            }
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                let tappedName = value.entity.name

                // open segment viewer
                if let segment = resultsManager.allDetailedSegments.first(where: { $0.segmentId == tappedName }) {
                    DispatchQueue.main.async {
                        resultsManager.selectedSegment = segment
                        openWindow(id: "segmentViewer")
                    }
                }

                // tap attachment text to delete sphere
                if tappedName == "Text" {
                    if let sphere = value.entity.parent as? SphereEntity {
                        disableAndRemoveSphere(entity: sphere)
                    }
                }
            }
    }
}
