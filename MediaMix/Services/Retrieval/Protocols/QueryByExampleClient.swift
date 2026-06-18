//
//  QueryByExampleClient.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

protocol QueryByExampleClient {
    func queryByExample(
        database: String,
        segmentId: String,
        limit: Int,
        sourceSegment: (segmentId: String?, objectId: String?, startMs: Int64?, endMs: Int64?)?
    ) async throws -> [RetrievalItem]
}
