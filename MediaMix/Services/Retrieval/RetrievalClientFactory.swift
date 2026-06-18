//
//  RetrievalClientFactory.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import FereLightSwiftClient
import Foundation

struct RetrievalClientFactory {
    func make(appSettings: AppSettings) -> RetrievalClient {
        switch appSettings.retrievalEngine {
        case .ferelight:
            return FereLightRetrievalClient(
                baseURL: URL(string: ConfigurationManager.shared.ferelightUrl)!
            )
        case .vitrivr:
            return VitrivrRetrievalClient(
                baseURL: ConfigurationManager.shared.vitrivrUrl
            )
        }
    }
}
