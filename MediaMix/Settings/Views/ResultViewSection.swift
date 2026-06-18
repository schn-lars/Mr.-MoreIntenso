//
//  ResultViewSection.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import SwiftUI

struct ResultViewSection: View {
    @EnvironmentObject private var appSettings: AppSettings
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        Section("Result View") {
            Picker("Display Mode", selection: $appSettings.resultViewMode) {
                ForEach(ResultViewMode.allCases) { mode in
                    Text(mode.rawValue.capitalized).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: appSettings.resultViewMode) { _, newMode in
                vm.didChangeResultViewMode(to: newMode, appSettings: appSettings)
            }
        }
    }
}
