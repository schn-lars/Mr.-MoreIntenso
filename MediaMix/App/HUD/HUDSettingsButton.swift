import SwiftUI

struct HUDSettingsButton: View {
    @EnvironmentObject private var appSettings: AppSettings
    
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    
    var body: some View {
        Button {
            dismissWindow(id: "settings")
            openWindow(id: "settings")
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 24))
                .padding(16)
        }
        .buttonStyle(.plain)
        .glassBackgroundEffect()
        .disabled(appSettings.isSettingsOpen)
    }
}
