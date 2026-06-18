//
//  ResultViewMode.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import Combine
import Foundation

enum ResultViewMode: String, CaseIterable, Identifiable {
    case spheres
    case grid

    var id: String {
        rawValue
    }
}
