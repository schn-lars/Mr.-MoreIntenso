//
//  DresSection.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import SwiftUI

struct DresSection: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var configManager: ConfigurationManager

    @ObservedObject var vm: SettingsViewModel
    @ObservedObject var dres: DresService

    var body: some View {
        Section("DRES") {
            TextField("Host", text: $configManager.dresHost)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            TextField("Username", text: $configManager.dresUser)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("Password", text: $configManager.dresPassword)

            if dres.isConnected {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                Picker("Evaluation", selection: Binding(
                    get: { vm.currentEvaluation },
                    set: { vm.currentEvaluation = $0 }
                )) {
                    ForEach(vm.evaluationViewData) { eval in
                        Text(eval.name).tag(Optional(eval.id))
                    }
                }

                Button("Logout") {
                    vm.logout(appSettings: appSettings)
                }
                .foregroundStyle(.red)

            } else {
                Button {
                    vm.login(appSettings: appSettings)
                } label: {
                    if vm.isLoggingIn {
                        HStack(spacing: 8) { ProgressView(); Text("Login") }
                    } else {
                        Text("Login")
                    }
                }
                .disabled(vm.isLoggingIn)
            }

            if let msg = vm.loginError {
                Text(msg).foregroundStyle(.red)
            }
        }
    }
}
