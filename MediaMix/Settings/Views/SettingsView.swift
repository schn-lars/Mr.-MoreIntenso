//
//  SettingsView.swift
//  MediaMix
//
//  Created by Rahel Arnold
//
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var configManager: ConfigurationManager
    @EnvironmentObject private var resultsManager: ResultsManager

    @StateObject private var dres = DresService.shared
    @StateObject private var vm = SettingsViewModel()

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel

    var body: some View {
        NavigationStack {
            Form {
                if appModel.appMode == .mediamix {
                    RetrievalEngineSection(vm: vm)
                    CollectionSection(vm: vm)
                    ResultViewSection(vm: vm)
                    DresSection(vm: vm, dres: dres)
                    LogsSection()
                } else {
                    InferenceLocationSection()
                    InferenceModelSection(vm: vm)
                    InferenceModeSection()
                    PromptSection(vm: vm)
                    RetrievalSettingsView()
                        .environmentObject(resultsManager)
                    ResultViewSection(vm: vm)
                }
                Section("Application Mode") {
                    let targetMode: AppModel.AppMode =
                            appModel.appMode == .intenso
                            ? .mediamix
                            : .intenso
                    Button("Switch to \(targetMode.displayName)") {
                        dismiss()
                        // logic for swapping the actual mode resides inside AppCoordinator's onChange(of: $appModel.appMode) function
                        appModel.appMode = targetMode
                    }
                    .multilineTextAlignment(.center)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                appSettings.isSettingsOpen = true
                vm.onAppear(appSettings: appSettings, configManager: configManager)
            }
            .onDisappear {
                appSettings.isSettingsOpen = false
            }
        }
        .frame(minWidth: 400, minHeight: 40)
    }
}
