//
//  LHECategory.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import Foundation

struct LHECategory: Codable, Identifiable {
    var id: String {
        key
    }

    let key: String
    let displayName: String
    let count: Int
}
