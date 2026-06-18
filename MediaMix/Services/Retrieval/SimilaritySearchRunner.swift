//
//  SimilaritySearchRunner.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import Foundation

/// Optional capability for engines that can resolve a segmentId for a given time.
protocol SegmentByTimeClient {
    func segmentByTime(database: String, objectId: String, timestamp: Double) async throws -> String
}

enum SimilaritySearchRunner {
    static func run(
        segment: DetailedSegment,
        database: String,
        factory: RetrievalClientFactory,
        appSettings: AppSettings
    ) async throws -> [RetrievalItem] {
        let client = factory.make(appSettings: appSettings)

        // 1) If engine supports segmentId-by-example
        if let qbe = client as? QueryByExampleClient {
            return try await qbe.queryByExample(
                database: database,
                segmentId: segment.segmentId,
                limit: 1000,
                sourceSegment: (
                    segmentId: segment.segmentId,
                    objectId: segment.objectId,
                    startMs: Int64(segment.segmentStartAbs * 1000),
                    endMs: Int64(segment.segmentEndAbs * 1000)
                )
            )
        }

        // 2) If engine supports clip-vector query
        if let vecClient = client as? ClipVectorQueryClient {
            let vec = toFloatVector(segment.clipVector)
            guard !vec.isEmpty else { return [] }

            return try await vecClient.queryByClipVector(
                database: database,
                vector: vec,
                limit: 1000,
                sourceSegment: (
                    segmentId: segment.segmentId,
                    objectId: segment.objectId,
                    startMs: Int64(segment.segmentStartAbs * 1000),
                    endMs: Int64(segment.segmentEndAbs * 1000)
                )
            )
        }

        // 3) Engine supports neither capability
        return []
    }

    /// Only meaningful for engines that support:
    /// - segmentByTime (resolve segmentId at timestamp)
    /// - queryByExample (run retrieval by that segmentId)
    static func runAtTime(
        segment _: DetailedSegment,
        database: String,
        objectId: String,
        timestampSeconds: Double,
        factory: RetrievalClientFactory,
        appSettings: AppSettings
    ) async throws -> [RetrievalItem] {
        let client = factory.make(appSettings: appSettings)

        guard
            let segByTime = client as? SegmentByTimeClient,
            let qbe = client as? QueryByExampleClient
        else { return [] }

        let segId = try await segByTime.segmentByTime(
            database: database,
            objectId: objectId,
            timestamp: timestampSeconds
        )

        return try await qbe.queryByExample(
            database: database,
            segmentId: segId,
            limit: 1000,
            sourceSegment: (
                segmentId: segId,
                objectId: stripSuffixAfterLastUnderscore(segId),
                startMs: Int64(timestampSeconds * 1000),
                endMs: nil
            )
        )
    }

    // MARK: - Helpers

    private static func stripSuffixAfterLastUnderscore(_ s: String) -> String {
        guard let idx = s.lastIndex(of: "_") else { return s }
        return String(s[..<idx])
    }

    private static func toFloatVector(_ any: Any?) -> [Float] {
        guard let any else { return [] }
        if let f = any as? [Float] { return f }
        if let d = any as? [Double] { return d.map(Float.init) }
        if let n = any as? [NSNumber] { return n.map { $0.floatValue } }
        if let a = any as? [Any] {
            return a.compactMap {
                if let f = $0 as? Float { return f }
                if let d = $0 as? Double { return Float(d) }
                if let n = $0 as? NSNumber { return n.floatValue }
                return nil
            }
        }
        return []
    }
}
