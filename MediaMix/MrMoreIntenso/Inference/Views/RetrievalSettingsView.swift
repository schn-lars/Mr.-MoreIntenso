//
//  RetrievalSettingsView.swift
//  MediaMix
//
//  Created by Lars Schneider on 26.05.2026.
//

import SwiftUI

struct RetrievalSettingsView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var configManager: ConfigurationManager
    @EnvironmentObject private var resultsManager: ResultsManager

    var body: some View {
        if resultsManager.areSpheresVisible && !resultsManager.spheres.isEmpty {
            Section("Retrieval") {
                Button("Close all Spheres") {
                    resultsManager.removeSpheres()
                }
                .buttonStyle(DefaultButtonStyle())
                .padding(.horizontal)
            }
        }
    }
}
