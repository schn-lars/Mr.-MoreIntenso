//
//  AppConfig.swift
//  MediaMix
//
//  Created by Rahel Arnold
//
import Foundation

/// Represents the application's configuration settings.
/// This struct holds various URLs and the DRES configuration.
struct AppConfig: Codable {
    let ferelightUrl: String
    let vitrivrUrl: String

    let ferelightDataURL: String
    let vitrivrDataURL: String

    let vitrivrResultsPath: String
    
    let mrIntensoApiUrl: String
    let mrIntensoVlmUrl: String
    let mrIntensoAPIGuestUsername: String
    let mrIntensoAPIGuestPassword: String

    let retrievalEngine: RetrievalEngine
    let dres: DresConfig
}

extension AppConfig {
    func withDres(
        apiBaseURL: String? = nil,
        username: String? = nil,
        password: String? = nil
    ) -> AppConfig {
        AppConfig(
            ferelightUrl: ferelightUrl,
            vitrivrUrl: vitrivrUrl,
            ferelightDataURL: ferelightDataURL,
            vitrivrDataURL: vitrivrDataURL,
            vitrivrResultsPath: vitrivrResultsPath,
            mrIntensoApiUrl: mrIntensoApiUrl,
            mrIntensoVlmUrl: mrIntensoVlmUrl,
            mrIntensoAPIGuestUsername: mrIntensoAPIGuestUsername,
            mrIntensoAPIGuestPassword: mrIntensoAPIGuestPassword,
            retrievalEngine: retrievalEngine,
            dres: DresConfig(
                apiBaseURL: apiBaseURL ?? dres.apiBaseURL,
                username: username ?? dres.username,
                password: password ?? dres.password
            )
        )
    }
}
