//
//  Database.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

enum Database: String, CaseIterable, Identifiable {
    case v3c
    case lhe
    case mvk

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .v3c: return "V3C"
        case .lhe: return "LHE"
        case .mvk: return "MVK"
        }
    }
}
