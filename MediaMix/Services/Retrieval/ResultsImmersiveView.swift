//
//  ResultsImmersiveView.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import AVKit
import FereLightSwiftClient
import RealityKit
import SceneKit
import SwiftUI

/// `ResultsImmersiveView` manages the immersive 3D visualization of query results.
/// It listens for updates to query results and dynamically fetches detailed segment data.
struct ResultsImmersiveView: View {
    /// Accesses the `ResultsManager` to track query results and manage visualization.
    @EnvironmentObject var resultsManager: ResultsManager

    @EnvironmentObject var appSettings: AppSettings

    @StateObject private var lheFilters = LHEFiltersStore()

    /// Whether detailed segments are currently being fetched.
    @State private var isLoading = false

    /// The fully fetched segment data, including metadata and feature vectors.
    @State private var detailedSegments: [DetailedSegment] = []

    /// The segment selected by the user (for video playback in a sheet).
    @State private var selectedSegment: DetailedSegment?

    /// Stores the current rotation position of the sphere.
    @State private var currentPosition: simd_float3 = [0, 0, 0]

    /// Client used to communicate with the FereLight server for fetching segment data.
    private var client: FereLightClient {
        FereLightClient(
            url: URL(string: ConfigurationManager.shared.ferelightUrl)!
        )
    }

    var body: some View {
        ZStack {
            if isLoading {
                // Show a loading spinner while fetching data
                ProgressView("Loading data...")
                    .padding()
            } else /* if !resultsManager.sphereResults.isEmpty */
            {
                // Display 3D query results
                RealityViewContainer(
                    detailedSegments: detailedSegments,
                    currentRotation: $currentPosition
                )
                .edgesIgnoringSafeArea(.all)
            }
        }
        .navigationTitle("Query Results")
        .sheet(item: $selectedSegment) { segment in
            VStack {
                VideoPlayerView(
                    videoUrl: URLGenerator.generateVideoURL(
                        database: segment.collection,
                        objectId: segment.objectId
                    )!
                )
                Button("Dismiss") {
                    selectedSegment = nil
                }
                .padding()
            }
        }

        .onReceive(resultsManager.$sphereResults) { newResults in
            Task {
                await fetchDetailedSegments(
                    with: newResults,
                    database: resultsManager.database
                )
            }
        }
        .onAppear {
            lheFilters.loadFromBundle(named: "LHE_filters")
        }
    }

    init() {
        MediaMixApp.spaceHasBeenOpened = true
        //        print("ResultsImmersiveView initialized")
    }

    /// Fetches detailed segment information from the database and updates the view.
    ///
    /// - Parameters:
    ///   - rawResults: The query results containing segment IDs and scores.
    ///   - database: The selected database for the query.
    private func fetchDetailedSegments(
        with rawResults: [RetrievalItem],
        database: String
    ) async {
        guard !rawResults.isEmpty else {
            // Clear segments if no results exist
            await MainActor.run {
                self.detailedSegments = []
                self.isLoading = false
            }
            return
        }

        isLoading = true
        switch appSettings.retrievalEngine {
        case .ferelight:
            do {
                let segmentIds = rawResults.map { $0.segmentId }

                // Fetch metadata for the retrieved segments
                let fetchedInfos = try await client.getSegmentInfos(
                    database: resultsManager.database,
                    segmentIds: segmentIds
                )

                // Combine query results with fetched metadata
                let combined = rawResults.compactMap {
                    result -> DetailedSegment? in
                    guard
                        let info = fetchedInfos.first(where: {
                            $0.segmentId == result.segmentId
                        })
                    else {
                        return nil
                    }

                    guard
                        passesLHEFilter(
                            objectId: info.objectId,
                            database: database
                        )
                    else { return nil }

                    return DetailedSegment(
                        segmentId: result.segmentId,
                        score: result.score,
                        objectId: info.objectId,
                        segmentNumber: info.segmentNumber,
                        segmentStart: info.segmentStart,
                        segmentEnd: info.segmentEnd,
                        segmentStartAbs: info.segmentStartAbs,
                        segmentEndAbs: info.segmentEndAbs,
                        clipVector: result.clipVector,
                        collection: resultsManager.database
                    )
                }
                let sorted = combined.sorted { $0.score > $1.score } // best first

                await MainActor.run {
                    self.detailedSegments = sorted
                    self.isLoading = false
                    resultsManager.allDetailedSegments += sorted
                }

            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
                print("getSegmentInfos failed:", error)
            }

        case .vitrivr:
            let combined: [DetailedSegment] = rawResults.compactMap { r in
                let objectId = r.objectId ?? ""
                guard passesLHEFilter(objectId: objectId, database: database)
                else { return nil }

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
                    collection: resultsManager.database
                )
            }

            /* await MainActor.run {
                 self.detailedSegments = combined
                 self.isLoading = false
                 resultsManager.allDetailedSegments += combined
             } */
            let sorted = combined.sorted { $0.score > $1.score } // best first

            await MainActor.run {
                self.detailedSegments = sorted
                self.isLoading = false
                resultsManager.allDetailedSegments += sorted
            }

            return
        }
    }

    private func passesLHEFilter(objectId: String, database: String) -> Bool {
        guard database.lowercased() == "lhe" else { return true }

        let selected = resultsManager.lheSelectedCategoryKeysSnapshot
        if selected.isEmpty { return true }

        let vidKey = normalizeLHEVideoId(objectId)

        // If mapping not loaded yet, DON'T pretend it matches.
        // Return true here means “no filtering”, which looks like "not working".
        guard !lheFilters.categoryByVideoId.isEmpty else {
            print("LHE mapping not loaded yet -> skipping filter")
            return true
        }

        let catKey = lheFilters.categoryByVideoId[vidKey]

        guard let cat = catKey else { return false }
        return selected.contains(cat)
    }

    private func normalizeLHEVideoId(_ objectId: String) -> String {
        let trimmed = objectId.trimmingCharacters(in: .whitespacesAndNewlines)

        // Already in correct format
        if trimmed.uppercased().hasPrefix("LHE") {
            return trimmed.uppercased()
        }

        // Backend gave only number → prefix it
        return "LHE" + trimmed
    }
}
