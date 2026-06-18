import SwiftUI

@Observable
class AppCoordinator {
    static let shared = AppCoordinator()
    
    /// These functions can be called by any element of the application to dynamically change what the user needs to see
    var openWindowAction: ((String) -> Void)?
    var dismissWindowAction: ((String) -> Void)?
    
    func switchTo(_ mode: AppModel.AppMode) {
        print("AppCoordinator switching to mode: \(mode.displayName)")
        switch mode {
        case .mediamix:
            openWindowAction?("queryWindow")
            //openWindowAction?("gridResults")
        case .intenso:
            dismissWindowAction?("queryWindow")
            dismissWindowAction?("gridResults")
            dismissWindowAction?("segmentViewer")
            dismissWindowAction?("submissionStatus")
            openWindowAction?("ImmersiveSpace")
        }
    }
    
    func openSettings() {
        openWindowAction?("settings")
    }
    
    func closeSettings() {
        dismissWindowAction?("settings")
    }
}
