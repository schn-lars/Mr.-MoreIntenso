//
//  RetrievalClient.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import Foundation

protocol RetrievalClient {
    func query(
        database: String,
        similarityText: String?,
        ocrText: String?,
        asrText: String?,
        mergeType: String?,
        limit: Int
    ) async throws -> [RetrievalItem]
}
