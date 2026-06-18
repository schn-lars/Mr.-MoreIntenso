//
//  VitrivrDTO.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import AnyCodable
import Foundation

struct VitrivrQueryResult: Decodable {
    let retrievables: [VitrivrRetrievable]?
}

struct VitrivrRetrievable: Decodable {
    let id: String
    let score: Double
    let relationship: [String: VitrivrRetrievable]?
    let descriptors: [String: AnyCodable]?
}
