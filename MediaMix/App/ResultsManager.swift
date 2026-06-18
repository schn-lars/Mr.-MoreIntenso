//
//  ResultsManager.swift
//  MediaMix
//
//  Created by Rahel Arnold
//
import RealityKit
import RealityKitContent
import SwiftUI

@MainActor
final class ResultsManager: ObservableObject {
    // MARK: - Query / Retrieval

    @Published var results: [RetrievalItem] = []
    @Published var sphereResults: [RetrievalItem] = []
    
    /// Mr.MoreIntenso
    @Published var selectedDetection: SelectedDetection?
    @Published var selectedShare: SharedObject?

    @Published var database: String = ""
    var queryText: String = ""
    var multiQueryText: [String] = []
    var query: [(String, QueryType)] = []
    var textMerge: Bool = false

    @Published var lheSelectedCategoryKeysSnapshot: Set<String> = []

    // MARK: - UI State

    @Published var showResultsWindow: [Bool] = [false]
    @Published var selectedSegment: DetailedSegment? = nil
    @Published var performMergedQuery: Bool = false

    // MARK: - Sphere Scene State

    @Published var areSpheresVisible: Bool = false
    @Published var spheres: [SphereController] = []
    @Published var allDetailedSegments: [DetailedSegment] = []

    /// Incremented externally when a new sphere is added
    var amountOfResults: Int = -1

    /// Anchor for all spheres
    let sphereAnchor = AnchorEntity(world: [0, 0.0, -1.5])

    /// Collision subscriptions
    private(set) var subscriptions: [EventSubscription] = []

    // MARK: - Constants

    private let layoutResetPosition = SIMD3<Float>(0, 1.0, -3)

    // MARK: - Init

    init() {
        SpherePosition.shared.resetSpherePosition(position: layoutResetPosition)
        print("ResultsManager has been initialized.")
    }

    // MARK: - Public API

    func activateSphere() {
        areSpheresVisible = true
    }

    func addSubscription(_ sub: EventSubscription) {
        subscriptions.append(sub)
    }

    func removeSpheres() {
        areSpheresVisible = false
        resetSphereLayoutState()

        // remove scene content
        for ctrl in spheres {
            ctrl.disableAndRemoveFromScene()
        }
        spheres.removeAll()

        // clear anchor children (safety)
        sphereAnchor.children.forEach { $0.removeFromParent() }
    }

    // MARK: - Private

    private func resetSphereLayoutState() {
        SpherePosition.shared.resetSpherePosition(position: layoutResetPosition)
        amountOfResults = -1
        
        print("ResultsManager: resetSphereLayoutState TRACE - removing \(allDetailedSegments.count) spheresegments")
        allDetailedSegments.removeAll()

        subscriptions.forEach { $0.cancel() }
        subscriptions.removeAll()
    }
}
