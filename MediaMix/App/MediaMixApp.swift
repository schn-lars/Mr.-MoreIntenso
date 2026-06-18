//
//  MediaMixApp.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import SwiftUI

@main
struct MediaMixApp: App {
    @State private var appModel = AppModel()
    @StateObject private var resultsManager = ResultsManager()
    @StateObject private var appSettings = AppSettings()
    @StateObject private var inferenceVM = InferenceViewModel()
    @StateObject private var locationManager = LocationManager()

    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    static var spaceHasBeenOpened: Bool = false

    @AppStorage("isQueryWindowOpen") private var isQueryWindowOpen: Bool = true
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup(id: "launchWindow") {
            LaunchView()
                .environment(appModel)
                .environmentObject(appSettings)
        }
        .defaultSize(CGSize(width: 1000, height: 800))
        
        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            RootImmersiveView()
                .environment(appModel)
                .environmentObject(resultsManager)
                .environmentObject(appSettings)
                .environmentObject(inferenceVM)
                .environmentObject(locationManager)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)

        WindowGroup(id: "queryWindow") {
            QuerySystemView()
                .environmentObject(resultsManager)
                .environmentObject(appSettings)
                .environmentObject(ConfigurationManager.shared)
                .environment(appModel)
        }
        .defaultSize(CGSize(width: 1000, height: 800))
        
        WindowGroup(id: "resultWindow") {
            IntensoResultView()
                .environmentObject(appSettings)
                .environmentObject(resultsManager)
                .environmentObject(ConfigurationManager.shared)
                .environment(appModel)
                .environmentObject(locationManager)
        }

        WindowGroup("Segment Viewer", id: "segmentViewer") {
            if let segment = resultsManager.selectedSegment {
                SingleSegmentView(segment: segment)
                    .environmentObject(resultsManager)
                    .environmentObject(appSettings)
            } else {
                Text("No segment selected")
            }
        }
        .defaultSize(CGSize(width: 1200, height: 1000))

        WindowGroup("Grid Results", id: "gridResults") {
            ResultsGridView()
                .environmentObject(resultsManager)
                .environmentObject(appSettings)
        }
        .defaultSize(CGSize(width: 1200, height: 800))

        WindowGroup("Submission Status", id: "submissionStatus") {
            SubmissionStatusView()
                .environmentObject(SubmissionPopupModel.shared)
                .environmentObject(appSettings)
        }
        .defaultSize(CGSize(width: 420, height: 200))
        .windowResizability(.contentSize)
        
        WindowGroup("Settings", id: "settings") {
            SettingsView()
                .environment(appModel)
                .environmentObject(appSettings)
                .environmentObject(resultsManager)
                .environmentObject(ConfigurationManager.shared)
                .frame(width: 600, height: 700)
                .presentationDetents([.large])
        }
    }

    init() {
//        print("MediaMixApp initialized")
//        resultsImmersiveView.environmentObject(resultsManager)
    }

    /// Opens the immersive space if it's not already open
    private func openImmersiveSpaceIfNeeded() async {
        guard appModel.immersiveSpaceState != .open else { return }
        print("Opening immersive space")
        let result = await openImmersiveSpace(id: appModel.immersiveSpaceID)
        appModel.immersiveSpaceState = (result == .opened) ? .open : .closed
    }
}
