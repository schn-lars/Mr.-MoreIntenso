//
//  ResultsGridViewModel.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import FereLightSwiftClient
import Foundation
import SwiftUI

@MainActor
final class ResultsGridViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var detailedSegments: [DetailedSegment] = []
    @Published var hoveredSegmentId: String? = nil

    private let lheFilters = LHEFiltersStore()

    func onAppear() {
        lheFilters.loadFromBundle(named: "LHE_filters")
    }

    func buildDetailedSegments(
        rawResults: [RetrievalItem],
        database: String,
        engine: RetrievalEngine,
        lheSelectedSnapshot: Set<String>
    ) async {
        guard !rawResults.isEmpty else {
            detailedSegments = []
            return
        }

        isLoading = true
        detailedSegments = []

        switch engine {
        case .ferelight:
            await fetchDetailedSegmentsFromFerelight(
                rawResults: rawResults,
                database: database,
                lheSelectedSnapshot: lheSelectedSnapshot
            )

        case .vitrivr:
            let combined = rawResults.compactMap { r -> DetailedSegment? in
                let objectId = r.objectId ?? ""
                guard passesLHEFilter(objectId: objectId, database: database, selected: lheSelectedSnapshot) else {
                    return nil
                }

                let startNs = r.startNs ?? 0
                let endNs = r.endNs ?? 0
                let startSec = Double(startNs) / 1_000_000_000.0
                let endSec = Double(endNs) / 1_000_000_000.0

                return DetailedSegment(
                    segmentId: r.segmentId,
                    score: r.score,
                    objectId: objectId,
                    segmentNumber: 0,
                    segmentStart: Int(startSec),
                    segmentEnd: Int(endSec),
                    segmentStartAbs: startSec,
                    segmentEndAbs: endSec,
                    clipVector: r.clipVector,
                    collection: database
                )
            }

            detailedSegments = combined
            isLoading = false
        }
    }

    // MARK: - Similarity enablement

    func isSimilarityEnabled(for segment: DetailedSegment, engine: RetrievalEngine) -> Bool {
        switch engine {
        case .vitrivr:
            return segment.clipVector?.isEmpty == false
        case .ferelight:
            return true
        }
    }

    // MARK: - LHE filter

    private func passesLHEFilter(objectId: String, database: String, selected: Set<String>) -> Bool {
        guard database.lowercased() == "lhe" else { return true }
        if selected.isEmpty { return true }

        let vidKey = normalizeLHEVideoId(objectId)

        // If mapping not loaded yet, better to NOT filter out everything; keep behavior consistent
        guard !lheFilters.categoryByVideoId.isEmpty else {
            return true
        }

        guard let catKey = lheFilters.categoryByVideoId[vidKey] else { return false }
        return selected.contains(catKey)
    }

    private func normalizeLHEVideoId(_ objectId: String) -> String {
        let trimmed = objectId.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.uppercased().hasPrefix("LHE") { return trimmed.uppercased() }
        return "LHE" + trimmed
    }

    // MARK: - Ferelight detail fetch

    private var ferelightClient: FereLightClient {
        FereLightClient(url: URL(string: ConfigurationManager.shared.ferelightUrl)!)
    }

    private func fetchDetailedSegmentsFromFerelight(
        rawResults: [RetrievalItem],
        database: String,
        lheSelectedSnapshot: Set<String>
    ) async {
        do {
            let ids = rawResults.map { $0.segmentId }
            let infos = try await ferelightClient.getSegmentInfos(database: database, segmentIds: ids)

            let combined = rawResults.compactMap { r -> DetailedSegment? in
                guard let info = infos.first(where: { $0.segmentId == r.segmentId }) else { return nil }
                guard passesLHEFilter(objectId: info.objectId, database: database, selected: lheSelectedSnapshot) else { return nil }

                return DetailedSegment(
                    segmentId: r.segmentId,
                    score: r.score,
                    objectId: info.objectId,
                    segmentNumber: info.segmentNumber,
                    segmentStart: info.segmentStart,
                    segmentEnd: info.segmentEnd,
                    segmentStartAbs: info.segmentStartAbs,
                    segmentEndAbs: info.segmentEndAbs,
                    clipVector: r.clipVector, // keep vector if present
                    collection: database
                )
            }

            detailedSegments = combined
            isLoading = false
        } catch {
            isLoading = false
            print("Grid fetch failed: \(error.localizedDescription)")
        }
    }
}
