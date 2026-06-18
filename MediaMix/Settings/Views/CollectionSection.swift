//
//  CollectionSection.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import SwiftUI

struct CollectionSection: View {
    @EnvironmentObject private var appSettings: AppSettings
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        Section("Collection") {
            Picker("Database", selection: $appSettings.selectedDatabase) {
                Text("V3C").tag("v3c")
                Text("MVK").tag("mvk")
                Text("LHE").tag("lhe")
            }
            .pickerStyle(.segmented)
            .onChange(of: appSettings.selectedDatabase) { _, newDB in
                vm.didChangeDatabase(to: newDB, appSettings: appSettings)
            }
        }
    }
}
