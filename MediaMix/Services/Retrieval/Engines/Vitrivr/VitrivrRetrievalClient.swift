//
//  VitrivrRetrievalClient.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import AnyCodable
import Foundation
import OpenAPIClient

/// Adapter to use the generated OpenAPI client in the app-wide RetrievalClient abstraction.
final class VitrivrRetrievalClient: RetrievalClient, ClipVectorQueryClient {
    // MARK: - Text Mode (kept local)

    private enum TextMode {
        case clip(prompt: String)
        case ocr(prompt: String)
        case asr(prompt: String)

        var opName: String {
            switch self {
            case .clip: return "clip"
            case .ocr: return "ocr"
            case .asr: return "asr"
            }
        }

        var fieldName: String {
            switch self {
            case .clip: return "clip"
            case .ocr: return "ocr"
            case .asr: return "asr"
            }
        }

        var dresTextCategory: String {
            switch self {
            case .clip: return "caption"
            case .ocr: return "OCR"
            case .asr: return "ASR"
            }
        }

        var prompt: String {
            switch self {
            case let .clip(p), let .ocr(p), let .asr(p): return p
            }
        }

        static func pick(similarityText: String?, ocrText: String?, asrText: String?) -> TextMode? {
            if let s = similarityText, !s.isEmpty { return .clip(prompt: s) }
            if let o = ocrText, !o.isEmpty { return .ocr(prompt: o) }
            if let a = asrText, !a.isEmpty { return .asr(prompt: a) }
            return nil
        }
    }

    // MARK: - Init

    /// Initialize with vitrivr-engine base URL
    init(baseURL: String) {
        // OpenAPI Generator swift5 client uses this global base path
        OpenAPIClientAPI.basePath = baseURL
    }

    // MARK: - RetrievalClient

    func query(
        database: String,
        similarityText: String?,
        ocrText: String?,
        asrText: String?,
        mergeType _: String?,
        limit: Int
    ) async throws -> [RetrievalItem] {
        guard let mode = TextMode.pick(
            similarityText: similarityText,
            ocrText: ocrText,
            asrText: asrText
        ) else {
            return []
        }

        let ts = QueryLogging.nowMillis()

        // 1) QUERY LOG
        QueryLogging.logQueryToDresAndLocal(
            timestamp: ts,
            engine: .vitrivr,
            database: database,
            events: [(timestamp: ts, category: "TEXT", _type: mode.dresTextCategory, value: mode.prompt)]
        )

        // 2) BUILD REQUEST (keeps operator order stable for vitrivr)
        let req = VitrivrRequestBuilder.makeTextQueryRequest(
            schema: database,
            prompt: mode.prompt,
            limit: limit,
            firstOpName: mode.opName,
            firstOpField: mode.fieldName
        )

        // 3) HTTP
        let qr = try await VitrivrHTTP.perform(req)

        // 4) MAP
        let results: [RetrievalItem] = (qr.retrievables ?? []).map { r in
            let vec = VitrivrParsing.toDoubleVector(r.descriptors?["clip.vector"]?.value)

            return RetrievalItem(
                segmentId: r.id,
                score: r.score,
                objectId: VitrivrParsing.extractVideoId(from: r),
                startNs: VitrivrParsing.extractInt64(r.descriptors?["time.start"]),
                endNs: VitrivrParsing.extractInt64(r.descriptors?["time.end"]),
                clipVector: vec
            )
        }

        // 5) RESULT LOG (local)
        QueryLogging.logResultsLocal(
            timestamp: ts,
            engine: .vitrivr,
            database: database,
            results: results
        )

        return results
    }

    // MARK: - Vector query (engine-specific convenience)

    func queryByClipVector(
        database: String,
        vector: [Float],
        limit: Int,
        sourceSegment: (segmentId: String?, objectId: String?, startMs: Int64?, endMs: Int64?)? = nil
    ) async throws -> [RetrievalItem] {
        let ts = QueryLogging.nowMillis()

        let value: String = {
            guard let s = sourceSegment else {
                return "clip.vector dim=\(vector.count)"
            }
            let seg = s.segmentId ?? "nil"
            let obj = s.objectId ?? "nil"
            let start = s.startMs.map(String.init) ?? "nil"
            let end = s.endMs.map(String.init) ?? "nil"
            return "segmentId=\(seg);objectId=\(obj);startMs=\(start);endMs=\(end)"
        }()

        QueryLogging.logQueryToDresAndLocal(
            timestamp: ts,
            engine: .vitrivr,
            database: database,
            events: [(timestamp: ts, category: "IMAGE", _type: "globalFeatures", value: value)]
        )

        // 1) BUILD REQUEST
        let req = VitrivrRequestBuilder.makeVectorQueryRequest(
            schema: database,
            vector: vector,
            limit: limit
        )

        // 2) HTTP
        let qr = try await VitrivrHTTP.perform(req)

        // 3) MAP
        let results: [RetrievalItem] = (qr.retrievables ?? []).map { r in
            let vec = VitrivrParsing.toDoubleVector(r.descriptors?["clip.vector"]?.value)

            return RetrievalItem(
                segmentId: r.id,
                score: r.score,
                objectId: VitrivrParsing.extractVideoId(from: r),
                startNs: VitrivrParsing.extractInt64(r.descriptors?["time.start"]),
                endNs: VitrivrParsing.extractInt64(r.descriptors?["time.end"]),
                clipVector: vec
            )
        }

        QueryLogging.logResultsLocal(
            timestamp: ts,
            engine: .vitrivr,
            database: database,
            results: results
        )

        return results
    }
}
