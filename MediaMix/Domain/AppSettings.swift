//
//  AppSettings.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import Combine
import Foundation

final class AppSettings: ObservableObject {
    @Published var selectedDatabase: String = "v3c"
    @Published var isLoggedInToDres: Bool = false
    @Published var resultViewMode: ResultViewMode = .grid
    @Published var retrievalEngine: RetrievalEngine = .vitrivr // was .ferelight
    @Published var lheSelectedCategoryKeys: Set<String> = []
    
    // Mr. MoreIntenso settings:
    @Published var remoteInference: Bool = false
    @Published var model: IntensoInferenceModelType = .YOLOv11
    @Published var inferenceTask: IntensoInferenceTask = .DET
    @Published var prompts: [String] = []
    
    // We need this to stop inference once settings are open
    @Published var isSettingsOpen: Bool = false
}

enum IntensoInferenceModelType: String, CaseIterable, Identifiable, Codable {
    case YOLOv26
    case YOLOv11
    case SAM3
    case WORLD
    
    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .YOLOv26: return "YOLOv26"
        case .YOLOv11: return "YOLOv11"
        case .SAM3:    return "SAM3"
        case .WORLD:   return "WORLD"
        }
    }
    
    static func fromDisplayName(_ name: String) throws -> Self {
        guard let value = Self.allCases.first(where: { $0.displayName == name }) else {
            throw NSError(domain: "InvalidDisplayName", code: -1)
        }
        return value
    }
}

enum IntensoInferenceTask: String, CaseIterable, Identifiable, Codable {
    case SEG
    case DET
    
    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .SEG: return "Segmentation"
        case .DET: return "Detection"
        }
    }
    
    static func fromDisplayName(_ name: String) throws -> Self {
        guard let value = Self.allCases.first(where: { $0.displayName == name }) else {
            throw NSError(domain: "InvalidDisplayName", code: -1)
        }
        return value
    }
}
