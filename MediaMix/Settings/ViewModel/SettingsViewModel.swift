//
//  SettingsViewModel.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import Foundation
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    // UI state
    @Published var loginError: String?
    @Published var isLoggingIn: Bool = false

    /// Dependencies
    private let dres: DresService

    init(dres: DresService = .shared) {
        self.dres = dres
    }

    // MARK: - Sync / lifecycle

    func onAppear(appSettings: AppSettings, configManager: ConfigurationManager) {
        // Keep config in sync when opening settings
        configManager.retrievalEngine = appSettings.retrievalEngine

        if dres.isConnected {
            Task { try? await refreshEvaluations() }
        }
    }

    // MARK: - Settings changes

    func didChangeRetrievalEngine(
        to newEngine: RetrievalEngine,
        appSettings: AppSettings,
        configManager: ConfigurationManager
    ) {
        configManager.retrievalEngine = newEngine
        logUI(
            engine: newEngine.rawValue,
            db: appSettings.selectedDatabase,
            type: "changeRetrievalEngine",
            value: "engine=\(newEngine.rawValue)"
        )
    }

    func didChangeDatabase(to newDB: String, appSettings: AppSettings) {
        logUI(
            engine: appSettings.retrievalEngine.rawValue,
            db: newDB,
            type: "changeDatabase",
            value: ""
        )
    }

    func didChangeResultViewMode(to newMode: ResultViewMode, appSettings: AppSettings) {
        logUI(
            engine: appSettings.retrievalEngine.rawValue,
            db: appSettings.selectedDatabase,
            type: "changeResultViewMode",
            value: "mode=\(newMode.rawValue)"
        )
    }
    
    func didChangeInferenceModel(to newModel: IntensoInferenceModelType, appSettings: AppSettings) {
        logUI(
            engine: appSettings.retrievalEngine.rawValue,
            db: appSettings.selectedDatabase,
            type: "changeInferenceModel",
            value: "mode=\(newModel.displayName)"
        )
    }

    // MARK: - DRES

    func login(appSettings: AppSettings) {
        guard !isLoggingIn else { return }

        loginError = nil
        isLoggingIn = true

        logUI(
            engine: appSettings.retrievalEngine.rawValue,
            db: appSettings.selectedDatabase,
            type: "dresLoginAttempt",
            value: ""
        )

        Task {
            do {
                try await dres.connect()
                try? await refreshEvaluations()
                loginError = nil
            } catch {
                // keep it simple; you can also show error.localizedDescription if you want
                loginError = "Login failed"
            }
            isLoggingIn = false
        }
    }

    func logout(appSettings: AppSettings) {
        logUI(
            engine: appSettings.retrievalEngine.rawValue,
            db: appSettings.selectedDatabase,
            type: "dresLogout",
            value: ""
        )
        dres.logout()
    }

    func refreshEvaluations() async throws {
        try await dres.updateEvaluations()
    }

    /// Expose dres state if needed by views
    var isConnected: Bool {
        dres.isConnected
    }

    var evaluationViewData: [DresEvaluationViewData] {
        dres.evaluations.map {
            DresEvaluationViewData(
                id: $0.id,
                name: $0.name
            )
        }
    }

    var currentEvaluation: String? {
        get { dres.currentEvaluation }
        set { dres.currentEvaluation = newValue }
    }
}

struct DresEvaluationViewData: Identifiable {
    let id: String
    let name: String
}
