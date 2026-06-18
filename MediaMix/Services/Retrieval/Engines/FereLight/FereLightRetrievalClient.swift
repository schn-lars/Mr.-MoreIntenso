//
//  FereLightRetrievalClient.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import FereLightSwiftClient
import Foundation

final class FereLightRetrievalClient: RetrievalClient, QueryByExampleClient, SegmentByTimeClient {
    private let client: FereLightClient

    init(baseURL: URL) {
        client = FereLightClient(url: baseURL)
    }

    func query(
        database: String,
        similarityText: String?,
        ocrText: String?,
        asrText: String?,
        mergeType: String?,
        limit: Int
    ) async throws -> [RetrievalItem] {
        guard let (prompt, dresTextCategory) = pickPrompt(
            similarityText: similarityText,
            ocrText: ocrText,
            asrText: asrText
        ) else { return [] }

        let ts = QueryLogging.nowMillis()
        QueryLogging.logQueryToDresAndLocal(
            timestamp: ts,
            engine: .ferelight,
            database: database,
            events: [(timestamp: ts, category: "TEXT", _type: dresTextCategory, value: prompt)]
        )

        let results = try await client.query(
            database: database,
            similarityText: similarityText,
            ocrText: ocrText,
            asrtext: asrText,
            mergetype: mergeType,
            limit: limit,
            includevectors: true
        )

        let mapped = results.map { r -> RetrievalItem in
            let clipAsDouble: [Double]? =
                (r.clipVector) ?? (r.clipVector as? [Float])?.map(Double.init)

            return RetrievalItem(
                segmentId: r.segmentId,
                score: r.score,
                clipVector: clipAsDouble
            )
        }

        QueryLogging.logResultsLocal(
            timestamp: ts,
            engine: .ferelight,
            database: database,
            results: mapped
        )

        return mapped
    }

    func queryByExample(
        database: String,
        segmentId: String,
        limit: Int,
        sourceSegment: (segmentId: String?, objectId: String?, startMs: Int64?, endMs: Int64?)? = nil
    ) async throws -> [RetrievalItem] {
        let ts = QueryLogging.nowMillis()

        let value: String = {
            guard let s = sourceSegment else { return "segmentId=\(segmentId)" }
            let seg = s.segmentId ?? "nil"
            let obj = s.objectId ?? "nil"
            let start = s.startMs.map(String.init) ?? "nil"
            let end = s.endMs.map(String.init) ?? "nil"
            return "segmentId=\(seg);objectId=\(obj);startMs=\(start);endMs=\(end)"
        }()

        QueryLogging.logQueryToDresAndLocal(
            timestamp: ts,
            engine: .ferelight,
            database: database,
            events: [(timestamp: ts, category: "IMAGE", _type: "globalFeatures", value: value)]
        )

        let results = try await client.queryByExample(
            database: database,
            segmentId: segmentId,
            limit: limit
        )

        let mapped = results.map { r -> RetrievalItem in
            let clipAsDouble: [Double]? =
                (r.clipVector) ?? (r.clipVector as? [Float])?.map(Double.init)

            return RetrievalItem(segmentId: r.segmentId, score: r.score, clipVector: clipAsDouble)
        }

        QueryLogging.logResultsLocal(timestamp: ts, engine: .ferelight, database: database, results: mapped)
        return mapped
    }

    func segmentByTime(
        database: String,
        objectId: String,
        timestamp: Double
    ) async throws -> String {
        try await client.segmentByTime(
            database: database,
            objectId: objectId,
            timestamp: timestamp
        )
    }

    private func pickPrompt(
        similarityText: String?,
        ocrText: String?,
        asrText: String?
    ) -> (prompt: String, dresTextCategory: String)? {
        if let s = similarityText, !s.isEmpty { return (s, "caption") }
        if let o = ocrText, !o.isEmpty { return (o, "OCR") }
        if let a = asrText, !a.isEmpty { return (a, "ASR") }
        return nil
    }
}
