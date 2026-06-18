import SwiftUI

struct InferenceModelSection: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var configManager: ConfigurationManager
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        // we cannot change model type when we are doing our inference locally
        if appSettings.remoteInference {
            Section("Inference Model") {
                Picker("Model", selection: $appSettings.model) {
                    ForEach(IntensoInferenceModelType.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: appSettings.model) { _, newModel in
                    vm.didChangeInferenceModel(
                        to: newModel,
                        appSettings: appSettings
                    )
                }
            }
        }
    }
}
