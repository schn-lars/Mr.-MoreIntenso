import SwiftUI

struct InferenceModeSection: View {
    @EnvironmentObject private var appSettings: AppSettings

    var body: some View {
        Picker("Inference Mode", selection: $appSettings.inferenceTask) {
            ForEach(IntensoInferenceTask.allCases) { task in
                Text(task.displayName).tag(task)
            }
        }
        .pickerStyle(.segmented)
        
        if appSettings.inferenceTask == .SEG {
            HStack(alignment: .center) {
                Spacer()
                
                Label(
                    "Experimental feature",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 18))
                .foregroundStyle(.orange)
                
                Spacer()
            }
        }
    }
}
