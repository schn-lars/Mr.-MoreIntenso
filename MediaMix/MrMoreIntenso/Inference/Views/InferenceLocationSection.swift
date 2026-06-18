import SwiftUI

struct InferenceLocationSection: View {
    @EnvironmentObject private var appSettings: AppSettings

    var body: some View {
        Section("Inference Location") {
            Toggle("Remote Inference", isOn: $appSettings.remoteInference)
        }
    }
}
