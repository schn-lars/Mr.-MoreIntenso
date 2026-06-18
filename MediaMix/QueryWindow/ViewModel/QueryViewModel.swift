//
//  QueryViewModel.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import SwiftUI

@MainActor
final class QueryViewModel: ObservableObject {
    // UI State
    @Published var selectedDatabase: Database = .v3c
    @Published var queryText: String = ""
    @Published var selectedMergeType: MergeType = .idIntersection

    @Published var noResults: Bool = false
    @Published var isImmersiveSpaceOpen: Bool = false
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false
    @Published var showSettings: Bool = false

    /// Dependencies
    private let clientFactory: RetrievalClientFactory

    init(clientFactory: RetrievalClientFactory = .init()) {
        self.clientFactory = clientFactory
    }

    func syncDatabase(from settings: AppSettings) {
        selectedDatabase = Database(rawValue: settings.selectedDatabase.lowercased()) ?? .v3c
    }

    func toggleLHECategory(key: String, settings: AppSettings) {
        if settings.lheSelectedCategoryKeys.contains(key) {
            settings.lheSelectedCategoryKeys.remove(key)
        } else {
            settings.lheSelectedCategoryKeys.insert(key)
        }
    }

    @MainActor
    func mergeQueries(resultsManager: ResultsManager, appSettings: AppSettings) async -> Bool {
        // resultsManager.database is String -> bridge to enum
        selectedDatabase = Database(rawValue: resultsManager.database.lowercased()) ?? .v3c

        var similarityText = ""
        var ocrText = ""
        var asrText = ""

        for (text, type) in resultsManager.query {
            switch type {
            case .sim:
                similarityText += text + "#"
            case .ocr:
                ocrText += text + " "
            case .asr:
                asrText += text + " "
            }
        }

        return await performQuery(
            resultsManager: resultsManager,
            appSettings: appSettings,
            similarityText: similarityText.isEmpty ? nil : similarityText,
            ocrText: ocrText.isEmpty ? nil : ocrText,
            asrText: asrText.isEmpty ? nil : asrText,
            mergeType: selectedMergeType.rawValue
        )
    }

    @MainActor
    func performQuery(
        resultsManager: ResultsManager,
        appSettings: AppSettings,
        similarityText: String?,
        ocrText: String?,
        asrText: String?,
        mergeType: String?
    ) async -> Bool {
        guard !isLoading else { return false }

        isLoading = true
        errorMessage = nil
        noResults = false

        do {
            let client = clientFactory.make(appSettings: appSettings)
            let queryResults = try await client.query(
                database: selectedDatabase.rawValue,
                similarityText: similarityText,
                ocrText: ocrText,
                asrText: asrText,
                mergeType: mergeType,
                limit: 1000
            )

            let mapped = queryResults.map {
                RetrievalItem(
                    segmentId: $0.id,
                    score: $0.score,
                    objectId: $0.objectId,
                    startNs: $0.startNs,
                    endNs: $0.endNs,
                    clipVector: $0.clipVector
                )
            }

            resultsManager.database = selectedDatabase.rawValue
            resultsManager.lheSelectedCategoryKeysSnapshot =
                selectedDatabase == .lhe ? appSettings.lheSelectedCategoryKeys : []

            switch appSettings.resultViewMode {
            case .spheres:
                resultsManager.sphereResults = mapped
                print("QueryViewModel: performQuery TRACE spheres-count: \(mapped.count)")
                if !mapped.isEmpty { resultsManager.amountOfResults += 1 }
            case .grid:
                print("QueryViewModel: performQuery TRACE grid-count: \(mapped.count)")
                resultsManager.results = mapped
            }

            noResults = mapped.isEmpty
            isLoading = false
            return !mapped.isEmpty
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
            isLoading = false
            return false
        }
    }
}
