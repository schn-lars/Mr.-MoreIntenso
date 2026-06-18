//
//  SphereLayoutMode.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

enum SphereLayoutMode: String, CaseIterable, Identifiable {
    case rankedFront = "Ranked"
    case semanticTSNE = "t-SNE"
    var id: String {
        rawValue
    }
}
