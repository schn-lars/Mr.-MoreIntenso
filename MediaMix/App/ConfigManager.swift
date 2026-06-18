//
//  ConfigManager.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import Foundation
import SwiftUI

final class ConfigurationManager: ObservableObject {
    static let shared = ConfigurationManager()

    @Published private(set) var config: AppConfig
    @Published var retrievalEngine: RetrievalEngine = .vitrivr // was .ferelight

    private func ensureTrailingSlash(_ s: String) -> String {
        s.hasSuffix("/") ? s : (s + "/")
    }

    private init() {
        config = ConfigurationManager.load()
        print("ConfigurationManager has been initialized")
    }

    private static func load() -> AppConfig {
        guard
            let url = Bundle.main.url(
                forResource: "config",
                withExtension: "json"
            ),
            let data = try? Data(contentsOf: url)
        else {
            fatalError("Config file not found")
        }
        return try! JSONDecoder().decode(AppConfig.self, from: data)
    }

    var ferelightUrl: String {
        config.ferelightUrl
    }

    var vitrivrUrl: String {
        config.vitrivrUrl
    }

    var ferelightDataURL: String {
        ensureTrailingSlash(config.ferelightDataURL)
    }

    var vitrivrDataURL: String {
        ensureTrailingSlash(config.vitrivrDataURL)
    }

    var vitrivrResultsPath: String {
        config.vitrivrResultsPath.trimmingCharacters(
            in: CharacterSet(charactersIn: "/")
        )
    }
    
    var mrIntensoApiUrl: String {
        ensureTrailingSlash(config.mrIntensoApiUrl)
    }
    
    var mrIntensoVlmUrl: String {
        ensureTrailingSlash(config.mrIntensoVlmUrl)
    }
    
    var mrIntensoAPIGuestUsername: String {
        get { config.mrIntensoAPIGuestUsername }
    }
    
    var mrIntensoAPIGuestPassword: String {
        get { config.mrIntensoAPIGuestPassword }
    }

    // MARK: - Direct DRES bindings

    var dresHost: String {
        get { config.dres.apiBaseURL }
        set { config = config.withDres(apiBaseURL: newValue) }
    }

    var dresUser: String {
        get { config.dres.username }
        set { config = config.withDres(username: newValue) }
    }

    var dresPassword: String {
        get { config.dres.password }
        set { config = config.withDres(password: newValue) }
    }
}
