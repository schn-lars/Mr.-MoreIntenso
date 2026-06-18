//
//  ClipVectorQueryClient.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

protocol ClipVectorQueryClient {
    func queryByClipVector(
        database: String,
        vector: [Float],
        limit: Int,
        sourceSegment: (segmentId: String?, objectId: String?, startMs: Int64?, endMs: Int64?)?
    ) async throws -> [RetrievalItem]
}
