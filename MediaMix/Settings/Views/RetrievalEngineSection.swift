//
//  RetrievalEngineSection.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import SwiftUI

struct RetrievalEngineSection: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var configManager: ConfigurationManager
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        Section("Retrieval Engine") {
            Picker("Engine", selection: $appSettings.retrievalEngine) {
                ForEach(RetrievalEngine.allCases) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: appSettings.retrievalEngine) { _, newEngine in
                vm.didChangeRetrievalEngine(
                    to: newEngine,
                    appSettings: appSettings,
                    configManager: configManager
                )
            }
        }
    }
}
