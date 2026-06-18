//
//  RetrievalItem.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import Foundation

struct RetrievalItem: Identifiable, Equatable {
    let segmentId: String
    let score: Double

    var objectId: String?
    var startNs: Int64?
    var endNs: Int64?
    var clipVector: [Double]?

    var id: String {
        segmentId
    }
}
