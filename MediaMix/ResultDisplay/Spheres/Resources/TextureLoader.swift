//
//  TextureLoader.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import Foundation
import RealityKit
import UIKit

actor TextureLoader {
    struct Key: Hashable {
        let database: String
        let objectId: String
        let segmentId: String
    }

    enum TextureLoaderError: Error {
        case badURL
        case badImageData
        case noCGImage
    }

    private let limiter: AsyncLimiter
    private var cache: [Key: TextureResource] = [:]

    init(maxConcurrent: Int = 12) {
        limiter = AsyncLimiter(maxConcurrent)
    }

    /// Load (and cache) a RealityKit texture for the given segment.
    func texture(for segment: DetailedSegment) async throws -> TextureResource {
        let key = Key(database: segment.collection, objectId: segment.objectId, segmentId: segment.segmentId)

        if let cached = cache[key] {
            return cached
        }

        guard
            let url = URLGenerator.generateImageURL(
                database: segment.collection,
                objectId: segment.objectId,
                segmentId: segment.segmentId
            )
        else {
            throw TextureLoaderError.badURL
        }

        await limiter.acquire()
        defer {
            Task { await limiter.release() }
        }

        // Re-check cache after waiting (avoid duplicate work)
        if let cached = cache[key] {
            return cached
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = UIImage(data: data) else {
            throw TextureLoaderError.badImageData
        }
        guard let cgImage = image.cgImage else {
            throw TextureLoaderError.noCGImage
        }

        let texture = try await TextureResource(
            image: cgImage,
            options: .init(semantic: .color)
        )

        cache[key] = texture
        return texture
    }

    /// Optional: clear all cached textures (e.g., on memory warning / dataset switch)
    func clearCache() {
        cache.removeAll()
    }
}
