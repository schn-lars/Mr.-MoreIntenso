//
//  ResultTileEntity.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import CoreText
import Foundation
import RealityKit
import RealityKitContent
import UIKit

@MainActor
final class ResultTileEntity: Entity {
    var modelEntity: ModelEntity?
    private var meshResource: MeshResource?

    private var rankLabelEntity: ModelEntity?
    private var currentRankText: String?

    // NEW: attachment anchors (RealityView will supply SwiftUI views for these)
    private var submitAnchor: Entity?
    private var similarityAnchor: Entity?

    /// Stable IDs so the RealityView can map attachments reliably.
    /// (You can include segmentId/objectId in these if you prefer.)
    func submitAttachmentID(tileID: String) -> String {
        "submit-\(tileID)"
    }

    func similarityAttachmentID(tileID: String) -> String {
        "similar-\(tileID)"
    }

    init(tileSize: Float) async throws {
        super.init()
        try await initialize(tileSize: tileSize)
    }

    required init() {
        fatalError("init() has not been implemented")
    }

    private func initialize(tileSize: Float) async throws {
        let mesh = MeshResource.generatePlane(width: tileSize, depth: tileSize)
        meshResource = mesh

        let placeholder = SimpleMaterial(color: .gray, isMetallic: false)
        let model = ModelEntity(mesh: mesh, materials: [placeholder])
        modelEntity = model
        addChild(model)
    }

    func updateTexture(material: SimpleMaterial) {
        modelEntity?.model?.materials = [material]
    }

    func addHover() async {
        components.set(InputTargetComponent(allowedInputTypes: .indirect))
        components.set(HoverEffectComponent())

        do {
            if let meshResource = meshResource {
                let collisionShape = try await ShapeResource.generateStaticMesh(from: meshResource)
                let collision = CollisionComponent(shapes: [collisionShape])
                components.set(collision)
            }
        } catch {
            print("Error generating collision shape: \(error)")
        }
    }

    func addGestures() {
        var component = GestureComponent()
        component.canDrag = true
        component.canScale = false
        component.canRotate = true
        component.canTap = true
        component.pivotOnDrag = false
        component.excelerateDragTowardsCamera = true
        components.set(component)
    }

    @MainActor
    func setRankLabel(_ rank: Int, tileSize: Float) async {
        let text = "\(rank + 1)"
        if currentRankText == text { return }
        currentRankText = text

        rankLabelEntity?.removeFromParent()
        rankLabelEntity = nil

        let fontSize: CGFloat = 0.06
        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0,
            font: .boldSystemFont(ofSize: fontSize),
            alignment: .center
        )

        let label = ModelEntity(mesh: mesh, materials: [UnlitMaterial()])
        label.position = SIMD3<Float>(
            -tileSize * 0.32,
            0.002,
            -tileSize * 0.32
        )
        label.scale = SIMD3<Float>(repeating: 0.25)

        rankLabelEntity = label
        addChild(label)
    }

    // MARK: - NEW: Attachments for Similarity + Submit

    /// Call this once after the tile exists and you know a stable tileID.
    /// The RealityView will render SwiftUI content into these anchors.
    func installActionButtonAnchors(tileID: String, tileSize: Float) {
        // Remove old anchors if re-installing
        submitAnchor?.removeFromParent()
        similarityAnchor?.removeFromParent()

        // Create anchors that will host attachments by ID
        let submit = Entity()
        submit.name = submitAttachmentID(tileID: tileID)

        let similar = Entity()
        similar.name = similarityAttachmentID(tileID: tileID)

        // Position anchors on the plane:
        // Plane is X-Z, normal is +Y, so lift on Y a bit to avoid z-fighting.
        let yLift: Float = 0.003

        // Bottom-right = +X, +Z (because top-left label uses -Z for "up")
        submit.position = SIMD3<Float>(
            +tileSize * 0.32,
            yLift,
            +tileSize * 0.32
        )

        // Bottom-left = -X, +Z
        similar.position = SIMD3<Float>(
            -tileSize * 0.32,
            yLift,
            +tileSize * 0.32
        )

        // Scale these anchors so the SwiftUI buttons aren’t huge in world space.
        // Tweak as needed.
        let s: Float = 0.35
        submit.scale = SIMD3<Float>(repeating: s)
        similar.scale = SIMD3<Float>(repeating: s)

        submitAnchor = submit
        similarityAnchor = similar

        addChild(submit)
        addChild(similar)
    }
}
