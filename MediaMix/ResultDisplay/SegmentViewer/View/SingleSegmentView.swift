//
//  SingleSegmentView.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import AVKit
import SwiftUI

struct SingleSegmentView: View {
    @StateObject private var dres = DresService.shared
    @StateObject private var popup = SubmissionPopupModel.shared

    @EnvironmentObject private var resultsManager: ResultsManager
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.openWindow) private var openWindow

    let segment: DetailedSegment

    @StateObject private var vm: SingleSegmentViewModel

    init(segment: DetailedSegment) {
        self.segment = segment
        _vm = StateObject(wrappedValue: SingleSegmentViewModel(segment: segment))
    }

    var body: some View {
        VStack(spacing: 0) {
            SegmentDragHandle(
                onChanged: { vm.updateDrag(current: $0) },
                onEnded: { vm.commitDrag(translation: $0) }
            )

            SegmentPlayerSection(
                title: segment.objectId,
                videoURL: URLGenerator.generateVideoURL(
                    database: segment.collection,
                    objectId: segment.objectId
                ),
                player: vm.player,
                onAppearWithURL: { url in
                    vm.setupPlayer(with: url, engine: appSettings.retrievalEngine)
                }
            )

            SegmentControlsBar(
                engine: appSettings.retrievalEngine,
                isSubmitting: vm.isSubmitting,
                onSimilarityAtCurrentTime: {
                    vm.logInteraction(
                        dres: dres,
                        engine: appSettings.retrievalEngine,
                        database: segment.collection,
                        action: "UI",
                        type: "tapSimilarityAtTime",
                        value: "segmentId=\(segment.segmentId)"
                    )
                    Task {
                        do {
                            let factory = RetrievalClientFactory()

                            let results = try await vm.similarityAtCurrentTime(
                                dres: dres,
                                engine: appSettings.retrievalEngine,
                                factory: factory,
                                appSettings: appSettings
                            )

                            await presentResults(results, database: segment.collection)
                        } catch {
                            print("Similarity@time failed:", error.localizedDescription)
                        }
                    }
                },
                onSimilarity: {
                    vm.logInteraction(
                        dres: dres,
                        engine: appSettings.retrievalEngine,
                        database: segment.collection,
                        action: "UI",
                        type: "tapSimilaritySearch",
                        value: "segmentId=\(segment.segmentId)"
                    )
                    Task {
                        do {
                            let factory = RetrievalClientFactory()

                            let results = try await vm.similarity(
                                dres: dres,
                                engine: appSettings.retrievalEngine,
                                factory: factory,
                                appSettings: appSettings
                            )
                            await presentResults(results, database: segment.collection)
                        } catch {
                            print("Similarity failed:", error.localizedDescription)
                        }
                    }
                },
                onSubmitFrame: {
                    Task {
                        let outcome = await vm.submitFrame(
                            dres: dres,
                            engine: appSettings.retrievalEngine
                        )

                        popup.show(
                            success: outcome.ok,
                            message: outcome.message.isEmpty
                                ? (outcome.ok ? "Submission sent." : "Submission failed.")
                                : outcome.message
                        )
                        openWindow(id: "submissionStatus")
                    }
                }
            )
            .padding()

            AnswerSubmitBar(
                answerText: $vm.answerText,
                isSubmitting: vm.isSubmitting,
                onSubmit: {
                    Task {
                        let outcome = await vm.submitAnswer(
                            dres: dres,
                            engine: appSettings.retrievalEngine
                        )

                        popup.show(
                            success: outcome.ok,
                            message: outcome.message.isEmpty
                                ? (outcome.ok ? "Answer submitted." : "Answer submission failed.")
                                : outcome.message
                        )
                        openWindow(id: "submissionStatus")
                    }
                }
            )
            .padding()
        }
        .frame(width: 1000, height: 800)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(radius: 10)
        .padding()
        .offset(x: vm.totalOffset.width + vm.currentDragOffset.width,
                y: vm.totalOffset.height + vm.currentDragOffset.height)
    }

    // MARK: - Presentation

    @MainActor
    private func presentResults(_ mapped: [RetrievalItem], database: String) {
        resultsManager.database = database

        switch appSettings.resultViewMode {
        case .spheres:
            resultsManager.sphereResults = mapped
            if !mapped.isEmpty { resultsManager.amountOfResults += 1 }
            resultsManager.activateSphere()

        case .grid:
            resultsManager.results = mapped
            openWindow(id: "gridResults")
        }
    }
}
