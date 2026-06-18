//
//  RetrievalEngine.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import Foundation

enum RetrievalEngine: String, CaseIterable, Identifiable, Codable {
    case ferelight
    case vitrivr

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .ferelight: return "FereLight"
        case .vitrivr: return "vitrivr-engine"
        }
    }
}
