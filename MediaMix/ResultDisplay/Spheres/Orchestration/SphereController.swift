//
//  SphereController.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import Foundation
import RealityKit

@MainActor
final class SphereController: ObservableObject {
    @Published var layoutMode: SphereLayoutMode = .rankedFront
    @Published var resolution: Double = 9.0

    let descriptor: SphereDescriptor
    private(set) var resultSet: SphereResultSet

    private let sphereEntity: SphereEntity

    var entity: SphereEntity {
        sphereEntity
    }

    private let rankedLayout = RankedFrontLayout()
    private let semanticLayout = SemanticPCALayout()
    private let textureLoader = TextureLoader(maxConcurrent: 12)

    init(descriptor: SphereDescriptor, resultSet: SphereResultSet, sphereEntity: SphereEntity) {
        self.descriptor = descriptor
        self.resultSet = resultSet
        self.sphereEntity = sphereEntity
    }

    func disableAndRemoveFromScene() {
        sphereEntity.trigger.removeFromParent()
        sphereEntity.isEnabled = false
        sphereEntity.removeFromParent()
    }

    func rebuild() async {
        let segments = resultSet.segments
        guard !segments.isEmpty else { return }

        do {
            let engine: SphereLayoutEngine = (layoutMode == .semanticTSNE) ? semanticLayout : rankedLayout
            var placements = try engine.layout(segments: segments, radius: sphereEntity.radius, resolution: resolution)

            // semantic may return [] if vectors missing -> fallback to ranked
            if placements.isEmpty, layoutMode == .semanticTSNE {
                placements = try rankedLayout.layout(segments: segments, radius: sphereEntity.radius, resolution: resolution)
            }

            guard let tileSize = placements.first?.tileSize else { return }

            try await sphereEntity.rebuildTiles(count: placements.count, tileSize: tileSize)
            sphereEntity.applyPlacements(placements)

            await sphereEntity.addHoverToChildEntities()
            await loadTexturesTopFirst(segments: Array(segments.prefix(placements.count)))

        } catch {
            print("Sphere rebuild failed:", error.localizedDescription)
        }
    }

    private func loadTexturesTopFirst(segments: [DetailedSegment]) async {
        let total = segments.count
        let firstBatch = min(40, total)

        // 1) top batch
        await withTaskGroup(of: Void.self) { group in
            for i in 0 ..< firstBatch {
                group.addTask { [textureLoader, sphereEntity] in
                    do {
                        let tex = try await textureLoader.texture(for: segments[i])
                        let scale = rankScale(for: i)
                        let seg = segments[i]
                        await MainActor.run {
                            sphereEntity.setTileIdentity(index: i, segmentId: seg.segmentId)
                            sphereEntity.applyTexture(tex, toIndex: i, scale: scale)
                        }
                    } catch {}
                }
            }
        }

        // 2) rest
        guard firstBatch < total else { return }
        await withTaskGroup(of: Void.self) { group in
            for i in firstBatch ..< total {
                group.addTask { [textureLoader, sphereEntity] in
                    do {
                        let tex = try await textureLoader.texture(for: segments[i])
                        let scale = rankScale(for: i)
                        let seg = segments[i]

                        await MainActor.run {
                            sphereEntity.setTileIdentity(index: i, segmentId: seg.segmentId)
                            sphereEntity.applyTexture(tex, toIndex: i, scale: scale)
                        }
                    } catch {}
                }
            }
        }
    }
}

func rankScale(for rank: Int) -> SIMD3<Float> {
    if rank < 12 { return SIMD3<Float>(repeating: 1.25) }
    if rank < 30 { return SIMD3<Float>(repeating: 1.12) }
    return SIMD3<Float>(repeating: 1.0)
}
