//
//  SphereEntity.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import Accelerate
import Foundation
import RealityKit
import RealityKitContent
import SwiftUI
import UIKit

@MainActor
final class SphereEntity: Entity {
    private(set) var tiles: [ResultTileEntity] = []
    let radius: Float
    let idNumber: Int
    let trigger: TriggerVolume

    init(idNumber: Int, radius: Float) {
        self.idNumber = idNumber
        self.radius = radius
        trigger = SphereTriggerFactory.make(radius: radius, id: idNumber)
        super.init()
        name = "Sphere \(idNumber)"
        addChild(trigger)
    }

    required init() {
        fatalError("init() has not been implemented")
    }

    func rebuildTiles(count: Int, tileSize: Float) async throws {
        tiles.forEach { $0.removeFromParent() }
        tiles.removeAll()

        for _ in 0 ..< count {
            let tile = try await ResultTileEntity(tileSize: tileSize)
            tiles.append(tile)
            addChild(tile)
        }
    }

    func applyPlacements(_ placements: [TilePlacement]) {
        for p in placements {
            let tile = tiles[p.index]
            tile.position = p.position
            tile.orientation = TileOrientation.outwardFacing(fromPosition: p.position)
            tile.position += p.outward * 0.01
        }
    }

    func applyTexture(_ texture: TextureResource, toIndex i: Int, scale: SIMD3<Float>) {
        var material = SimpleMaterial()
        material.baseColor = .texture(texture)
        tiles[i].updateTexture(material: material)
        tiles[i].scale = scale
    }

    func addHoverToChildEntities() async {
        await withTaskGroup(of: Void.self) { group in
            for tile in tiles {
                group.addTask {
                    await tile.addHover()
                    await tile.addGestures()
                }
            }
        }
    }

    func setTileIdentity(index: Int, segmentId: String) {
        guard tiles.indices.contains(index) else { return }
        tiles[index].name = segmentId
        tiles[index].modelEntity?.name = segmentId
    }
}
