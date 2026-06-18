//
//  LHEFiltersBundle.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import Foundation

struct LHEFiltersBundle: Codable {
    let schemaVersion: Int
    let categories: [LHECategory]
    let videos: [LHEVideo]
}
