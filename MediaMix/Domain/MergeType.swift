//
//  MergeType.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

enum MergeType: String, CaseIterable, Identifiable {
    case idIntersection = "id_intersection"
    case vectorMean = "vector_mean"

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .idIntersection: return "ID Intersection"
        case .vectorMean: return "Vector Mean"
        }
    }
}
