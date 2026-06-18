//
//  QuerySystemView.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import SwiftUI

struct QuerySystemView: View {
    @AppStorage("isQueryWindowOpen") private var isQueryWindowOpen: Bool = true

    @EnvironmentObject var resultsManager: ResultsManager
    @EnvironmentObject var appSettings: AppSettings

    @StateObject private var vm = QueryViewModel()
    @StateObject private var lheFilters = LHEFiltersStore()

    @Environment(\.openWindow) var openWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            Text("Query").font(.headline)

            QueryInputBar(queryText: $vm.queryText) {
                logUI(engine: appSettings.retrievalEngine.rawValue,
                      db: vm.selectedDatabase.rawValue,
                      type: "clearQueryText",
                      value: "prevLen=\(vm.queryText.count)")
                vm.queryText = ""
            }

            if vm.selectedDatabase == .lhe, let bundle = lheFilters.bundle {
                LHEFiltersSection(
                    bundle: bundle,
                    selectedKeys: appSettings.lheSelectedCategoryKeys,
                    onToggle: { key in vm.toggleLHECategory(key: key, settings: appSettings) },
                    onClear: { appSettings.lheSelectedCategoryKeys.removeAll() }
                )
            }

            QueryButtonsBar(
                isLoading: vm.isLoading,
                queryText: vm.queryText,
                showASR: appSettings.retrievalEngine == .vitrivr,
                onSim: {
                    resultsManager.query = [(vm.queryText, .sim)]
                    Task {
                        let hasResults = await vm.performQuery(
                            resultsManager: resultsManager,
                            appSettings: appSettings,
                            similarityText: vm.queryText,
                            ocrText: nil,
                            asrText: nil,
                            mergeType: nil
                        )
                        await presentResultsAfterQuery(hasResults: hasResults)
                    }
                },
                onOCR: {
                    resultsManager.query = [(vm.queryText, .ocr)]
                    Task {
                        let hasResults = await vm.performQuery(
                            resultsManager: resultsManager,
                            appSettings: appSettings,
                            similarityText: nil,
                            ocrText: vm.queryText,
                            asrText: nil,
                            mergeType: nil
                        )
                        await presentResultsAfterQuery(hasResults: hasResults)
                    }
                },
                onASR: {
                    resultsManager.query = [(vm.queryText, .asr)]
                    Task {
                        let hasResults = await vm.performQuery(
                            resultsManager: resultsManager,
                            appSettings: appSettings,
                            similarityText: nil,
                            ocrText: nil,
                            asrText: vm.queryText,
                            mergeType: nil
                        )
                        await presentResultsAfterQuery(hasResults: hasResults)
                    }
                }
            )

            if appSettings.retrievalEngine == .ferelight && appSettings.resultViewMode == .spheres {
                MergeTypeSection(selectedMergeType: $vm.selectedMergeType) { newValue in
                    logUI(engine: appSettings.retrievalEngine.rawValue,
                          db: vm.selectedDatabase.rawValue,
                          type: "changeMergeType",
                          value: "mergeType=\(newValue.rawValue)")
                }
            }

            StatusSection(isLoading: vm.isLoading, noResults: vm.noResults, errorMessage: vm.errorMessage)

            if resultsManager.areSpheresVisible && !resultsManager.spheres.isEmpty {
                Button("Close all Spheres") {
                    resultsManager.removeSpheres()
                }
                .buttonStyle(DefaultButtonStyle())
                .padding(.horizontal)
            }
        }
        .padding()
        .onAppear {
            isQueryWindowOpen = true
            vm.syncDatabase(from: appSettings)
            lheFilters.loadFromBundle(named: "LHE_filters")
        }
        .onDisappear { isQueryWindowOpen = false }
        .onChange(of: appSettings.selectedDatabase) { _, _ in
            vm.syncDatabase(from: appSettings)
        }
        .onChange(of: vm.selectedDatabase) { _, newDB in
            if newDB != .lhe {
                appSettings.lheSelectedCategoryKeys.removeAll()
            }
        }
        .task(id: resultsManager.performMergedQuery) {
            guard resultsManager.performMergedQuery else { return }

            let hasResults = await vm.mergeQueries(
                resultsManager: resultsManager,
                appSettings: appSettings
            )
            await presentResultsAfterQuery(hasResults: hasResults)

            resultsManager.performMergedQuery = false
        }

        // Setting Button
        .ornament(
            visibility: .visible,
            attachmentAnchor: .scene(.topTrailing),
            contentAlignment: .topTrailing
        ) {
            Button {
                logUI(
                    engine: appSettings.retrievalEngine.rawValue,
                    db: appSettings.selectedDatabase,
                    type: "openSettings",
                    value: ""
                )
                openWindow(id: "settings")
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .padding(.trailing, 20)
            .padding(.top, 20)
        }
        /*.sheet(isPresented: $vm.showSettings) {
            SettingsView()
                .environmentObject(appSettings)
                .frame(width: 600, height: 700)
                .presentationDetents([.large])
        }*/
    }

    @MainActor
    private func presentResultsAfterQuery(hasResults: Bool) async {
        guard hasResults else { return }

        switch appSettings.resultViewMode {
        case .spheres:
            dismissWindow(id: "gridResults")
            //await openImmersiveSpace(id: "ImmersiveSpace")
            vm.isImmersiveSpaceOpen = true
            resultsManager.activateSphere()

        case .grid:
            //if vm.isImmersiveSpaceOpen {
            //    await dismissImmersiveSpace()
            //    vm.isImmersiveSpaceOpen = false
            //}
            openWindow(id: "gridResults")
        }
    }
}
