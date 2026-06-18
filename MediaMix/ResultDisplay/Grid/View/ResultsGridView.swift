//
//  ResultsGridView.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import FereLightSwiftClient
import SwiftUI

struct ResultsGridView: View {
    @EnvironmentObject private var resultsManager: ResultsManager
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.openWindow) private var openWindow

    @StateObject private var vm = ResultsGridViewModel()

    private let columns = [GridItem(.adaptive(minimum: 200), spacing: 16)]

    var body: some View {
        VStack {
            if resultsManager.results.isEmpty && vm.detailedSegments.isEmpty {
                Text("No results yet")
                    .foregroundColor(.secondary)
                    .padding()
            } else if vm.isLoading && vm.detailedSegments.isEmpty {
                ProgressView("Loading result details…")
                    .padding()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(vm.detailedSegments, id: \.segmentId) { segment in
                            let isHovered = vm.hoveredSegmentId == segment.segmentId

                            ResultCard(
                                segment: segment,
                                onOpen: { openSegment(segment) },
                                onSimilarity: { runSimilarity(from: segment) },
                                isSimilarityEnabled: vm.isSimilarityEnabled(for: segment, engine: appSettings.retrievalEngine)
                            )
                            .padding(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(isHovered ? Color.white.opacity(0.95) : .clear, lineWidth: 5)
                                    .allowsHitTesting(false)
                            )
                            .shadow(color: isHovered ? .white.opacity(0.6) : .clear, radius: 8)
                            .contentShape(Rectangle())
                            .buttonStyle(.plain)
                            .hoverEffect(.highlight)
                            .onHover { hovering in
                                vm.hoveredSegmentId = hovering ? segment.segmentId : nil
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .task {
            vm.onAppear()

            let snapshotResults = resultsManager.results
            let snapshotDatabase = resultsManager.database
            let lheSnapshot = resultsManager.lheSelectedCategoryKeysSnapshot

            await vm.buildDetailedSegments(
                rawResults: snapshotResults,
                database: snapshotDatabase,
                engine: appSettings.retrievalEngine,
                lheSelectedSnapshot: lheSnapshot
            )
        }
    }

    // MARK: - Navigation

    private func openSegment(_ segment: DetailedSegment) {
        logUI(
            engine: appSettings.retrievalEngine.rawValue,
            db: resultsManager.database,
            type: "openSegmentViewer",
            value: "segmentId=\(segment.segmentId);rank=\(resultsManager.results.firstIndex { $0.segmentId == segment.segmentId } ?? -1)"
        )
        resultsManager.selectedSegment = segment
        openWindow(id: "segmentViewer")
    }

    // MARK: - Similarity (delegates to retrieval layer)

    private func runSimilarity(from segment: DetailedSegment) {
        logUI(
            engine: appSettings.retrievalEngine.rawValue,
            db: segment.collection,
            type: "tapResultSimilarity",
            value: "segmentId=\(segment.segmentId);objectId=\(segment.objectId)"
        )

        Task {
            do {
                let results = try await SimilaritySearchRunner.run(
                    segment: segment,
                    database: segment.collection,
                    factory: RetrievalClientFactory(),
                    appSettings: appSettings
                )

                await MainActor.run {
                    resultsManager.database = segment.collection
                    resultsManager.results = results
                    openWindow(id: "gridResults")
                }
            } catch {
                print("Similarity query failed:", error.localizedDescription)
            }
        }
    }
}
