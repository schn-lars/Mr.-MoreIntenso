//
//  DresConfig.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

/// Represents the configuration for the DRES (Distributed Retrieval Evaluation Server) system.
/// This struct holds the necessary credentials and API base URL for accessing DRES.
struct DresConfig: Codable {
    /// The base URL for the DRES API.
    let apiBaseURL: String
    /// The username required for authentication.
    let username: String
    /// The password required for authentication.
    let password: String
}
