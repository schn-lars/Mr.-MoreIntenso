import SwiftUI
import RealityKit
import RealityKitContent
import CoreLocation
import FereLightSwiftClient

struct RootImmersiveView: View {
    @State private(set) var isReady = false
    private var detailedSegments: [DetailedSegment] {
        resultsManager.allDetailedSegments
    }
    @State private var spheresToggle: Bool = false
    @State private var hudAnchor: AnchorEntity?
    
    // from ResultsImmersiveView
    @State private var isLoadingSegments = false
    @StateObject private var lheFilters = LHEFiltersStore()
    private var client: FereLightClient {
        FereLightClient(url: URL(string: ConfigurationManager.shared.ferelightUrl)!)
    }
    
    //@StateObject var headTracker = HeadPositionTracker()
    
    /// MediaMix
    @State private var currentRotation: simd_float3 = .zero
    @State private var collisionSubscribed = false
    @State private var lastDragPosition: CGSize = .zero

    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @EnvironmentObject var resultsManager: ResultsManager
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var locationManager: LocationManager
    
    @EnvironmentObject private var inferenceVM: InferenceViewModel
    @State private var renderer: IntensoRenderer
    
    @State private var sharedObjects: [SharedObject] = []
    @State private var bridgeAnchor: AnchorEntity? = nil
    @State private var bridgeCaptured: Bool = false
    @State private var bridgeTrigger: Bool = false
    
    let cicontext = CIContext()
    
    @State private var segmentsReady = false
    @State private var spawningSpheres = false

    init() {
        renderer = IntensoRenderer()
    }

    var body: some View {
        RealityView { content, attachments in
            setupHUD(content: content, attachments: attachments)
            renderer.setup(content)
            
            let anchor = AnchorEntity(world: matrix_identity_float4x4)
            content.add(anchor)
            bridgeAnchor = anchor
            
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                bridgeTrigger.toggle()
            }
            
            // for mediamix
            if !content.entities.contains(where: { $0 === resultsManager.sphereAnchor }) {
                content.add(resultsManager.sphereAnchor)
            }
        } update: { content, attachments in
            let _ = spheresToggle
            //print("RootImmersiveView: update TRACE - spheresToggle=\(spheresToggle) segmentsReady=\(segmentsReady) spawningSpheres=\(spawningSpheres) areSpheresVisible=\(resultsManager.areSpheresVisible) sphereResultsCount=\(resultsManager.sphereResults.count)")
            
            // Bridge capture — intenso only
            if appModel.appMode == .intenso && !bridgeCaptured, let anchor = bridgeAnchor {
                let bridge = anchor.transformMatrix(relativeTo: nil)
                if bridge == matrix_identity_float4x4 {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        bridgeTrigger.toggle()
                    }
                    //return
                } else {
                    inferenceVM.setARKitBridge(bridge: bridge)
                    bridgeCaptured = true
                }
            }

            // Sphere logic — runs regardless of mode
            if !resultsManager.areSpheresVisible {
                clearAllSpheresEntitiesOnly()
                return
            }

            if !resultsManager.sphereResults.isEmpty && segmentsReady {
                // https://www.hackingwithswift.com/new-syntax-swift-2-defer
                defer {
                    spawnSphereIfNeeded(content: content)
                }
                
                Task { @MainActor in
                    guard segmentsReady else { return }
                    segmentsReady = false
                }
            } else {
                //print("RootImmersiveView: body TRACE else block of spawnSphereIfNeeded")
            }

            updateSphereRotation()

            for controller in resultsManager.spheres {
                let id = controller.descriptor.id
                if let textEntity = attachments.entity(for: "sphere_\(id)") {
                    guard controller.entity.children.first(where: { $0 === textEntity }) == nil else { continue }
                    controller.entity.addChild(textEntity, preservingWorldTransform: false)
                    textEntity.scenePosition.y += SpherePosition.shared.sphere_radius + 0.25
                }
            }
        }
        attachments: {
            Attachment(id: "modeToggle") {
                HUDSettingsButton()
                    .environmentObject(appSettings)
            }
            
            // mediamix (was wrapped in state == .intenso)
            ForEach(resultsManager.spheres.indices, id: \.self) { idx in
                let controller = resultsManager.spheres[idx]
                Attachment(id: "sphere_\(controller.descriptor.id)") {
                    SphereSettings(controller: controller) {
                        // this is called when you close a sphere
                        // this should
                        Task { @MainActor in
                            controller.disableAndRemoveFromScene()
                            resultsManager.spheres.removeAll { $0 === controller }
                        }
                    }
                }
            }
        }
        .installGestures()
        .task {
            await waitUntilReady()
            
            //print("RootImmersiveView: .task TRACE starting trackedObjectStream")
            for await objects in inferenceVM.makeTrackedObjectsStream() {
                //print("RootImmersiveView: received tracked objects:", objects.trackedObservations.count)
                //print(Date().timeIntervalSince1970) // used for performance metrics
                guard appModel.appMode == .intenso else { continue }
                
                // remove any objects once
                if !resultsManager.spheres.isEmpty {
                    //print("RootImmersiveView: body TRACE removing objects as we have spheres shown")
                    renderer.removeAllObjects(except: nil)
                    continue
                }
                
                renderer.apply(result: objects)
            }
        }
        .task {
            await waitUntilReady()
            
            print("RootImmersiveView: .task TRACE starting meshAnchorStream")
            for await update in inferenceVM.makeMeshAnchorStream() {
                guard appModel.appMode == .intenso else { continue }
                switch update.event {
                case .added, .updated:
                    do {
                        let shape = try await ShapeResource.generateStaticMesh(from: update.anchor)
                        /// For visualization
                        //let meshResource = try await MeshResource(from: update.anchor)
                        //print("RootImmersiveView: received updates for anchor Stream")
                        try await renderer.updateMeshEntity(
                            id: update.anchor.id,
                            shape: shape,
                            //meshResource: meshResource,
                            transform: update.anchor.originFromAnchorTransform
                        )
                    } catch {
                        print("RootImmersiveView: mesh shape error \(error)")
                    }
                    //print("RootImmersiveView: .task TRACE add / update")
                case .removed:
                    //print("RootImmersiveView: .task TRACE remove")
                    renderer.removeMeshEntity(id: update.anchor.id)
                }
            }
        }
        .task {
            await waitUntilReady()
            
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard appModel.appMode == .intenso else { continue }
                
                guard !Task.isCancelled else { break }
                
                if locationManager.checkAndUpdateProximity() {
                    /// Trigger retrieval of shared objects
                    print("RootImmersiveView: device moved 10m+ — triggering proximity check")
                    await fetchSharedObjectsByProximity()
                } else {
                    
                    // leave this for now, the if might need additional logic behind it
                    // also, idealy we would trigger this (or just re-rendering) after we close settings or results
                    await fetchSharedObjectsByProximity()
                }
                
                if let cameraTransform = inferenceVM.arkitSessionManager.currentDeviceTransform() {
                    renderer.removeFarthestSharedMarkerIfNeeded(
                        deviceWorldTransform: cameraTransform
                    )
                    
                    // clean up sharedObjects after removing them potentially
                    sharedObjects.removeAll(where: { obj in
                        guard let uuid = UUID(uuidString: obj.id) else { return true }
                        return !renderer.sharedMarkerMap.keys.contains(uuid)
                    })
                }
            }
        }
        .onAppear {
            // Wire up coordinator with window actions
            print("RootImmersiveView onAppaear")
            // Setting variables as the AppCoordinator is not a View making it not possible to have @Environment directly
            
            AppCoordinator.shared.dismissWindowAction = { id in
                dismissWindow(id: id)
            }
            
            AppCoordinator.shared.openWindowAction = { id in
                openWindow(id: id)
            }
            
            lheFilters.loadFromBundle(named: "LHE_filters")
            //AppCoordinator.shared.switchTo(appModel.appMode)
            //print("RootImmersiveView switched to \(appModel.appMode == .intenso ? "intenso" : "mediamix")")
            
            renderer.appSettings = appSettings
            inferenceVM.bind(appSettings: appSettings)
            inferenceVM.setup() { result in
                switch result {
                case .failure(let error):
                    fatalError(error.localizedDescription)
                case .success(_):
                    print("RootImmersiveView: inferenceVM is setup")
                    self.inferenceVM.start()
                    self.isReady = true
                }
            }
        }
        .onChange(of: appModel.appMode) { _, newMode in
            // Drive window state on every mode change
            print("RootImmersiveView change of appMode to \(newMode.displayName)")
            AppCoordinator.shared.switchTo(newMode)
            
            switch newMode {
            case .intenso:
                inferenceVM.start()
                clearAllSpheresEntitiesOnly()
                resultsManager.removeSpheres()
            case .mediamix:
                inferenceVM.stop()
                clearAllSpheresEntitiesOnly()
                resultsManager.removeSpheres()
                removeAllObjects(except: nil, shared: true)
            }
        }
        /// these are supposed to react to changes in the resultmanager
        //.onChange(of: resultsManager.spheres.count) { _, _ in
        //    spheresToggle.toggle()
        //}
        //.onChange(of: resultsManager.areSpheresVisible) { _, _ in
        //    spheresToggle.toggle()
        //}
        //.onChange(of: resultsManager.sphereResults.count) { _, _ in
        //    spheresToggle.toggle()
        //}
        .onReceive(resultsManager.$sphereResults) { newResults in
            Task {
                await fetchDetailedSegments(
                    with: newResults,
                    database: resultsManager.database
                )
            }
        }
        .onChange(of: resultsManager.areSpheresVisible) { _, new in
            if !new {
                segmentsReady = false
                spawningSpheres = false
                print("segmentsReady, spawningSpheres set FALSE, FALSE")
                print("segmentsReady=\(segmentsReady), spawningSpheres=\(spawningSpheres)")
                spheresToggle.toggle()
            } else {
                print("RootImmersiveView: body TRACE - onChange areSpheresVisible(\(new)); segmentsReady=\(segmentsReady), spawningSpheres=\(spawningSpheres)")
            }
        }
        .onDisappear {
            inferenceVM.stop()
        }
        .gesture(unifiedTapGesture)
        //.gesture(
        //    appModel.appMode == .mediamix ? dragGesture : nil
        //)
        .simultaneousGesture(dragGesture)
    }
    
    private var unifiedTapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                Task {
                    guard !appSettings.isSettingsOpen else { return }

                    await handleIntensoTap(value: value)
                    handleMediaMixTap(value: value)
                }
            }
    }
    
    func waitUntilReady() async {
        while !isReady {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let deltaX = value.translation.width - lastDragPosition.width
                let rotationDelta = Float(deltaX / 100)
                currentRotation.y += rotationDelta
                lastDragPosition = value.translation
            }
            .onEnded { _ in
                lastDragPosition = .zero
            }
    }
    
    private func handleIntensoTap(value: EntityTargetValue<SpatialTapGesture.Value>) async {
        guard let idComponent = findObjectID(from: value.entity) else { return }
        if let detection = getDetection(from: idComponent) {
            print("RootImmersiveView: body TRACE tapped entity", value.entity.name)
            // TODO: potentially remove other windows
            resultsManager.selectedDetection = SelectedDetection(
                id: idComponent,
                confidence: detection.confidence,
                label: detection.label,
                fullImage: bufferToCGImage(
                    buffer: await inferenceVM.latestFrameBuffer.peek()?.buffer
                ),
                croppedImage: detection.croppedImage
            )
            removeAllObjects(except: idComponent)
            AppCoordinator.shared.dismissWindowAction?("resultWindow")
            AppCoordinator.shared.openWindowAction?("resultWindow")
        } else if let shared = getSharedObject(from: idComponent) {
            print("RootImmersiveView: selected shared object \(shared.obj)")
            resultsManager.selectedShare = shared
            removeAllObjects(except: idComponent)
            AppCoordinator.shared.dismissWindowAction?("resultWindow")
            AppCoordinator.shared.openWindowAction?("resultWindow")
        } else {
            print("RootImmersiveView: selected unknown object \(idComponent.uuidString)")
            //print("RootImmersiveView: shared keys: \(sharedObjects.count)")
            //debugSharedObjects()
        }
    }
    
    private func handleMediaMixTap(value: EntityTargetValue<SpatialTapGesture.Value>) {
        let tappedName = value.entity.name
        print("RootImmersiveView: handleMediaMixTap TRACE starting with \(tappedName) ...")
        if let segment = resultsManager.allDetailedSegments.first(where: { $0.segmentId == tappedName }) {
            resultsManager.selectedSegment = segment
            openWindow(id: "segmentViewer")
            print("RootImmersiveView: handleMediaMixTap TRACE found segment")
        }
        if tappedName == "Text", let sphere = value.entity.parent as? SphereEntity {
            disableAndRemoveSphere(entity: sphere)
        }
    }
    
    private func debugSharedObjects() {
        for obj in sharedObjects {
            print("id=\(obj.id); label=\(obj.obj)")
        }
    }
    
    func findObjectID(from entity: Entity) -> UUID? {
        var current: Entity? = entity
        while let e = current {
            if let comp = e.components[ObjectIDComponent.self] {
                return comp.id
            } else if let comp = e.components[SharedObjectTag.self] {
                return comp.id
            }
            current = e.parent
        }
        return nil
    }
    
    /// MEDIAMIX (copied over from ResultsImmersieView)
    
    private func fetchDetailedSegments(
        with rawResults: [RetrievalItem],
        database: String
    ) async {
        print("RootImmersiveView: fetchDetailedSegments TRACE - starting ...")
        guard !rawResults.isEmpty else {
            // Clear segments if no results exist
            print("RootImmersiveView: fetchDetailedSegments GUARD - rawResults is empty")
            await MainActor.run {
                self.resultsManager.allDetailedSegments = []
                self.isLoadingSegments = false
            }
            return
        }
        
        segmentsReady = false
        isLoadingSegments = true
        print("segmentsReady set FALSE")
        print("segmentsReady=\(segmentsReady), spawningSpheres=\(spawningSpheres)")
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
                    self.isLoadingSegments = false
                    resultsManager.allDetailedSegments += sorted
                    segmentsReady = true
                    print("segmentsReady set TRUE")
                    print("segmentsReady=\(segmentsReady), spawningSpheres=\(spawningSpheres)")
                    spheresToggle.toggle()
                    print("RootImmersiveView: fetchDetailedSegments TRACE allDetailedSegments.count=\(resultsManager.allDetailedSegments.count)")
                }

            } catch {
                await MainActor.run {
                    self.isLoadingSegments = false
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
                self.isLoadingSegments = false
                resultsManager.allDetailedSegments += sorted
                segmentsReady = true
                print("segmentsReady set TRUE")
                print("segmentsReady=\(segmentsReady), spawningSpheres=\(spawningSpheres)")
                spheresToggle.toggle()
                print("RootImmersiveView: fetchDetailedSegments TRACE allDetailedSegments.count=\(resultsManager.allDetailedSegments.count)")
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
    
    /// MEDIAMIX (copied from RealityViewContainer)
    
    private func spawnSphereIfNeeded(content: RealityViewContent) {
        guard !detailedSegments.isEmpty else {
            print("RootImmersiveView: spawnSphereIfNeeded GUARD detailedSegments is empty")
            return
        }

        let newID = resultsManager.amountOfResults
        print("RootImmersiveView: spawnSphereIfNeeded TRACE - processing new ...")
        // already exists?
        guard !resultsManager.spheres.contains(where: { $0.descriptor.id == newID }) else {
            print("RootImmersiveView: spawnSphereIfNeeded GUARD already exists")
            return
        }
        
        print("segmentsReady, spawningSpheres set FALSE, TRUE")
        print("segmentsReady=\(segmentsReady), spawningSpheres=\(spawningSpheres)")
        
        Task { @MainActor in
            // 1) compute resolution from result count (your old semantics)
            let resolution = computeResolution(resultCount: resultsManager.sphereResults.count)

            // 2) create entity
            let sphereEntity = SphereEntity(
                idNumber: newID,
                radius: SpherePosition.shared.sphere_radius
            )

            // 3) build descriptor + resultset
            let descriptor = SphereDescriptor(
                id: newID,
                database: resultsManager.database,
                query: resultsManager.query.map { text, type in
                    SphereQueryItem(text: text, type: type)
                }
            )

            let resultSet = SphereResultSet(segments: detailedSegments)

            // 4) controller
            let controller = SphereController(
                descriptor: descriptor,
                resultSet: resultSet,
                sphereEntity: sphereEntity
            )
            controller.resolution = Double(resolution)

            // 5) set rotation + position
            sphereEntity.transform.rotation = simd_quatf(
                angle: currentRotation.y,
                axis: [0, 1, 0]
            )

            let existingPositions = resultsManager.spheres.map {
                $0.entity.position(relativeTo: resultsManager.sphereAnchor)
            }

            let position = SpherePosition.shared.getSpherePosition(
                spherePositions: existingPositions
            )
            sphereEntity.position = position

            // 6) store + attach to anchor
            resultsManager.spheres.append(controller)
            resultsManager.sphereAnchor.addChild(sphereEntity)

            // 7) build tiles + textures
            await controller.rebuild()

            // 8) subscribe collision once
            subscribeCollisionsIfNeeded(content: content)
            print("spawningSpheres set TRUE")
            print("segmentsReady=\(segmentsReady), spawningSpheres=\(spawningSpheres)")
            print("RootImmersiveView: spawnSphereIfNeeded TRACE - Sphere \(newID) added. Total: \(resultsManager.spheres.count)")
        }
    }
    
    private func clearAllSpheresEntitiesOnly() {
        resultsManager.sphereAnchor.children.forEach { $0.removeFromParent() }
    }
    
    private func subscribeCollisionsIfNeeded(content: RealityViewContent) {
        guard !collisionSubscribed else { return }
        collisionSubscribed = true

        let event = content.subscribe(to: CollisionEvents.Began.self) { ce in
            guard
                let sphereA = ce.entityA.parent as? SphereEntity,
                let sphereB = ce.entityB.parent as? SphereEntity
            else { return }

            // Keep behavior: only merge if A is "newer" than B
            guard sphereA.idNumber > sphereB.idNumber else { return }

            print("Collision \(ce.entityA.name) | \(ce.entityB.name)")
            mergeSphere(sphereA: sphereA, sphereB: sphereB)
        }

        resultsManager.addSubscription(event)
    }
    
    private func updateSphereRotation() {
        for controller in resultsManager.spheres {
            controller.entity.transform.rotation = simd_quatf(
                angle: currentRotation.y,
                axis: [0, 1, 0]
            )
        }
    }
    
    private func mergeSphere(sphereA: SphereEntity, sphereB: SphereEntity) {
        guard
            let ctrlA = controller(for: sphereA),
            let ctrlB = controller(for: sphereB)
        else { return }

        // prevent collision on duplicates
        guard ctrlA.descriptor.query.first?.text != ctrlB.descriptor.query.first?.text else { return }

        // same database only
        guard ctrlA.descriptor.database == ctrlB.descriptor.database else {
            print("Queries must be from the same database to be merged \(ctrlA.descriptor.database), \(ctrlB.descriptor.database)")
            return
        }

        // Save parameters for the new query (keep your ResultsManager format)
        resultsManager.database = ctrlA.descriptor.database
        resultsManager.query = (ctrlA.descriptor.query + ctrlB.descriptor.query).map { ($0.text, $0.type) }

        SpherePosition.shared.setMergePosition(
            positionA: sphereA.position(relativeTo: resultsManager.sphereAnchor),
            positionB: sphereB.position(relativeTo: resultsManager.sphereAnchor)
        )

        disableAndRemoveSphere(entity: sphereA)
        disableAndRemoveSphere(entity: sphereB)
        resultsManager.performMergedQuery = true
    }
    
    private func controller(for entity: SphereEntity) -> SphereController? {
        resultsManager.spheres.first { $0.entity === entity }
    }

    private func disableAndRemoveSphere(entity: SphereEntity) {
        // remove collision trigger if present
        entity.trigger.removeFromParent()

        entity.isEnabled = false
        entity.removeFromParent()

        // remove controller
        resultsManager.spheres.removeAll { $0.entity === entity }
    }
    
    private func computeResolution(resultCount: Int) -> Int {
        var resolution = Int(ceil(sqrt(Float(resultCount) / 6.0))) + 1
        resolution = min(resolution, 14) // upper limit
        resolution = max(resolution, 2) // lower limit
        return resolution
    }
    
    
    /// Intenso
    
    private func removeAllObjects(except: UUID?, shared: Bool = false) {
        renderer.removeAllObjects(except: except, shared: shared)
    }
    
    func bufferToCGImage(buffer: CVPixelBuffer?) -> CGImage? {
        guard let buffer = buffer else {
            return nil
        }
        let ciImage = CIImage(cvImageBuffer: buffer)
        return cicontext.createCGImage(ciImage, from: ciImage.extent)
    }
    
    private func getDetection(from: UUID) -> DetectionRenderData? {
        return renderer.detectionMap[from]
    }
    
    private func getSharedObject(from: UUID) -> SharedObject? {
        if renderer.sharedMarkerMap.keys.contains(from) {
            return sharedObjects.first(where: { UUID(uuidString: $0.id) == from })
        }
        return nil
    }
    
    private func setupHUD(content: RealityViewContent,
                          attachments: RealityViewAttachments) {
        let anchor = AnchorEntity(.head)

        guard let modeToggleEntity = attachments.entity(for: "modeToggle") else { return }
        modeToggleEntity.position = [0.25, -0.2, -1.3]

        anchor.addChild(modeToggleEntity)
        content.add(anchor)
    }
    
    private func fetchSharedObjectsByProximity() async {
        /// I need to know label, confidence?, coordinates, ID, username who shared it
        //print("RootImmersiveView: fetchSharedObjectsByProximity TRACE - starting ...")
        guard var components = URLComponents(
            string: ConfigurationManager.shared.mrIntensoApiUrl + "share/proximity-info"
        ) else {
            print("RootImmersiveView: fetchSharedObjectsByProximity GUARD - components are nil")
            return
        }
        
        guard let position = locationManager.coordinate else {
            print("RootImmersiveView: fetchSharedObjectsByProximity GUARD - position is nil")
            return
        }
        
        components.queryItems = [
            URLQueryItem(name: "coord_x", value: "\(position.longitude)"),
            URLQueryItem(name: "coord_y", value: "\(position.latitude)")
        ]
        
        guard let url = components.url else {
            print("RootImmersiveView: fetchSharedObjectsByProximity GUARD - url is nil")
            return
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        
        guard let token = KeychainService.load(key: "auth_token") else {
            print("RootImmersiveView: fetchSharedObjectsByProximity GUARD - No auth token found")
            return
        }
        urlRequest.setValue("Bearer \(token.stringValue)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("RootImmersiveView: fetchSharedObjectsByProximity GUARD - invalid response")
                return
            }
            
            let decoded = try JSONDecoder().decode(
                ProximityResponse.self,
                from: data
            )
            
            handleProximityResults(results: decoded.rows)
        } catch {
            print("RootImmersiveView: fetchSharedObjectsByProximity ERROR - \(error.localizedDescription)")
            return
        }
    }
    
    private func handleProximityResults(
        results: [SharedObject]
    ) {
        guard let deviceCoord = locationManager.coordinate else {
            print("RootImmersiveView: handleProximityResults GUARD - no deviceCoord")
            return
        }
        
        //print("RootImmersiveView: handleProximityResults TRACE - starting ...")

        for result in results {
            guard let uuid = UUID(uuidString: result.id) else {
                return
            }
            
            if !sharedObjects.contains(where: { $0.id == result.id }) {
                sharedObjects.append(result)
            } else {
                continue
            }
            
            let coordinates = CLLocationCoordinate2D(
                latitude: CLLocationDegrees(floatLiteral: result.coord_y),
                longitude: CLLocationDegrees(floatLiteral: result.coord_x)
            )
            let worldPos = coordinates.metersOffset(from: deviceCoord)
            let data = SharedMarkerData(
                id: uuid,
                label: result.obj,
                owner: result.owner,
                confidence: result.confidence,
                worldPosition: worldPos
            )
            renderer.renderSharedObjectEntity(data: data)
        }
    }
}
