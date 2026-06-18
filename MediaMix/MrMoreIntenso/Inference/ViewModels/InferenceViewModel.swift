import SwiftUI
import ARKit
import Combine
import simd

@MainActor
class InferenceViewModel: ObservableObject {
    // Logic needed to react to changes for prompts (backend needs to know these changes)
    private var appSettings: AppSettings?
    private var cancellables = Set<AnyCancellable>()
    private var lastValidPrompts: [String] = []
    private var doingRollback: Bool = false
    private var didBind = false
    
    private let tracker = ObjectTracker()
    
    let frameBuffer = AtomicBuffer<TrackedFrame>()
    let latestFrameBuffer = AtomicBuffer<TrackedFrame>()
    //@Published var lastFrameBuffer: CVPixelBuffer?
    private var trackedObjectsContinuation: AsyncStream<ProcessedObservations>.Continuation?
    
    func makeTrackedObjectsStream() -> AsyncStream<ProcessedObservations> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { [weak self] continuation in
            self?.trackedObjectsContinuation = continuation
        }
    }
    
    private var meshAnchorContinuation: AsyncStream<AnchorUpdate<MeshAnchor>>.Continuation?
    
    func makeMeshAnchorStream() -> AsyncStream<AnchorUpdate<MeshAnchor>> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            self.meshAnchorContinuation = continuation
        }
    }
    
    /*
    var meshAnchorStream: AsyncStream<AnchorUpdate<MeshAnchor>> {
        AsyncStream { continuation in
            Task {
                for await update in sceneProvider.anchorUpdates {
                    continuation.yield(update)
                }
            }
        }
    }
    */
    
    //@Published var activeObservations: [AnyObservation] = [] // TODO: replacing everytime seems excessive. But only way to evade that, would be to track objects across frames possibly.
    private var inferenceRunning = false
    
    /// Providers
    let arkitSessionManager = ARKitSessionManager()
    
    private let imageCaptureManager = ImageCaptureManager()
    private let inferenceManager = InferenceManager()
    
    private var cameraTask: Task<Void, Never>?
    private var localInferenceTask: Task<Void, Never>?
    private var meshTask: Task<Void, Never>?
    private var remoteSendingTask: Task<Void, Never>?
    private var remoteResultTask: Task<Void, Never>?
    
    private let frameSkip = 5 // No need to do inference every frame. Also not feasible actually
    
    init() {
        print("InferenceViewModel: init TRACE")
    }
    
    func setARKitBridge(bridge: simd_float4x4) {
        self.arkitSessionManager.setARKitBridge(bridge: bridge)
    }
    
    func bind(appSettings: AppSettings) {
        guard !didBind else {
            print("InferenceViewModel: bind GUARD bind already performed")
            return
        }
        didBind = true
        
        self.appSettings = appSettings
        print("InferenceViewModel: bind TRACE appSettings=", ObjectIdentifier(appSettings))
        observePromptChanges()
        observeModelChanges()
        observeInferenceModeChanges()
        observeInferenceLocationChanges()
        observeSettingsOpenChanges()
    }
    
    /**
            Methods responsible for observing changes
     */
    private func observeSettingsOpenChanges() {
        appSettings?.$isSettingsOpen
            .dropFirst()
            .sink { [weak self] open in
                self?.handleSettingsOpenChanged(open)
            }
            .store(in: &cancellables)
    }
    
    private func observePromptChanges() {
        appSettings?.$prompts
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] prompts in
                self?.handlePromptsChanged(prompts)
            }
            .store(in: &cancellables)
    }
    
    private func observeModelChanges() {
        appSettings?.$model
            .dropFirst()
            .scan((previous: nil, current: nil)) { state, newValue in
                (previous: state.current, current: newValue)
            }
            .sink { [weak self] state in
                guard let previous = state.previous,
                      let current = state.current else { return }
                self?.handleModelChange(
                    from: previous,
                    to: current
                )
            }
            .store(in: &cancellables)
    }
    
    private func observeInferenceLocationChanges() {
        appSettings?.$remoteInference
            .dropFirst()
            .sink { [weak self] location in
                self?.handleLocationChanges(location)
            }
            .store(in: &cancellables)
    }
    
    private func observeInferenceModeChanges() {
        appSettings?.$inferenceTask
            .dropFirst()
            .sink { [weak self] mode in
                self?.handleModeChange(mode: mode)
            }
            .store(in: &cancellables)
    }
    
    private func handleSettingsOpenChanged(_ open: Bool) {
        if open {
            print("InferenceViewModel: settings opened")
            stop()
        } else {
            print("InferenceViewModel: settings closed")
            start()
        }
    }
    
    /// Helpers
    private func handleLocationChanges(_ remote: Bool) {
        guard !doingRollback else {
            print("InferenceViewModel: handleLocationChanges - Aborting due to Rollback")
            self.doingRollback = false
            return
        }
        
        guard let model = appSettings?.model,
              let task = appSettings?.inferenceTask
        else {
            print("run")
            return
        }
        
        print("InferenceViewModel: handleLocationChange TRACE - switching to \(remote ? "remote" : "local")")
        
        inferenceManager.handleLocationChanges(
            remote: remote,
            model: model,
            task: task
        ) { result in
            switch result {
            case .success(_):
                print("InferenceViewModel: handleLocationChanges SUCCESS")
                return
            case .failure(let error):
                print("InferenceViewModel: handleLocationChanges ERROR \(error.localizedDescription)")
                // self.appSettings?.remoteInference remains unchanged
                self.doingRollback = true
                DispatchQueue.main.async {
                    self.appSettings?.remoteInference = !remote
                }
                return
            }
        }
    }
    
    private func handleModeChange(mode: IntensoInferenceTask) {
        guard !doingRollback else {
            print("InferenceViewModel: handleModeChange - Aborting due to Rollback")
            self.doingRollback.toggle()
            return
        }
        print("InferenceViewModel: handleModeChange TRACE - switching to \(mode.displayName)")
        
        guard let model = appSettings?.model else {
            return
        }
        
        inferenceManager.handleModeChange(
            mode: mode,
            model: model
        ) { result in
            switch result {
            case .success(_):
                // do nothing
                print("InferenceViewModel: handleModeChange SUCCESS")
                return
            case .failure(let error):
                // reset
                print("InferenceViewModel: handleModeChange FAILURE - failure setting mode. Resetting ... [\(error.localizedDescription)]")
                self.doingRollback = true
                DispatchQueue.main.async {
                    self.appSettings?.inferenceTask = mode == .SEG ? .DET : .SEG
                }
                return
            }
        }
    }
    
    private func handleModelChange(
        from: IntensoInferenceModelType,
        to: IntensoInferenceModelType
    ) {
        guard !doingRollback else {
            print("InferenceViewModel: handleModelChange - Aborting due to Rollback")
            self.doingRollback.toggle()
            return
        }
        
        print("InferenceViewModel: handleModelChange to - \(to.rawValue)")
        
        guard let task = appSettings?.inferenceTask else {
            print("InferenceViewModel: handleModelChange ERROR - undefined task")
            return
        }
        
        guard !inferenceRunning else {
            print("InferenceViewModel: handleModelChange ERROR - inference task is running")
            return
        }
        
        inferenceManager.handleModelChange(
            mode: task,
            model: to
        ) { result in
            switch result {
            case .success(_):
                // appSettings.model is already set the way it should be. That triggered the entire thing
                print("InferenceViewModel: handleModelChange SUCCESS")
                return
            case .failure(let error):
                print("InferenceViewModel: handleModelChange ERROR - \(error.localizedDescription)")
                self.doingRollback = true
                DispatchQueue.main.async {
                    self.appSettings?.model = from // that is defined here. No way that this is nil
                }
                return
            }
        }
    }
    
    private func handlePromptsChanged(_ prompts: [String]) {
        guard !doingRollback else {
            print("InferenceViewModel: handlePromptsChanged - Aborting due to Rollback")
            self.doingRollback.toggle()
            return
        }
        
        guard appSettings?.model == .SAM3 else {
            print("InferenceViewModel: handlePromptsChanged - SAM3 is not active")  
            return
        }
        
        guard lastValidPrompts.count < 10 else {
            print("InferenceViewModel: handlePromptsChanged - Too many prompts already")
            return
        }
        
        let cleaned_prompts = Array(Set(prompts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
        
        guard cleaned_prompts.count < 10 else {
            print("InferenceViewModel: handlePromptsChanged - Too many prompts now")
            return
        }
        
        if cleaned_prompts.count == 0 {
            // Factory reset
            print("InferenceViewModel: initiate sendSetDefaultPrompt")
            inferenceManager.sendSetDefaultPrompt() { result in
                switch result {
                case .success(_):
                    self.lastValidPrompts = []
                case .failure(_):
                    self.doingRollback = true
                    DispatchQueue.main.async {
                        self.appSettings?.prompts = self.lastValidPrompts
                    }
                }
            }
        } else {
            print("InferenceViewModel: initiate sendNewPrompts")
            inferenceManager.sendNewPrompts(cleaned_prompts) { result in
                switch result {
                case .success(_):
                    // https://stackoverflow.com/questions/24589181/set-operations-union-intersection-on-swift-array
                    // appSettings.prompts acts as ground truth
                    self.lastValidPrompts = self.appSettings?.prompts ?? []
                case .failure(_):
                    self.doingRollback = true // such that we do not retrigger the entire process
                    DispatchQueue.main.async {
                        self.appSettings?.prompts = self.lastValidPrompts
                    }
                }
            }
        }
    }
    
    func setup(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let model = appSettings?.model,
              let task = appSettings?.inferenceTask else {
            print("InferenceViewModel: setup ERROR model and task are nil")
            completion(.failure(NSError(domain: "guard", code: -1)))
            return
        }

        inferenceManager.setup(
            model: model,
            task: task,
            completion: completion
        )
    }
    
    func start() {
        guard !inferenceRunning else {
            print("InferenceViewModel: start GUARD already running")
            return
        }
        
        guard cameraTask == nil else {
            print("InferenceViewModel: start GUARD cameraTask still alive")
            return
        }
        
        inferenceRunning = true
        
        cameraTask = Task { [weak self] in
            guard let self else { return }
            
            do {
                try await self.arkitSessionManager.start()
                print("InferenceViewModel: start TRACE - Camera started")
            } catch {
                print("InferenceViewModel: start ERROR - Camera failed to start: \(error)")
                await MainActor.run { self.inferenceRunning = false }
                return
            }
            
            self.meshTask = Task { [weak self] in
                guard let self = self else {
                    print("InferenceViewModel: meshTask GUARD")
                    return
                }
                
                for await update in self.arkitSessionManager.sceneProvider.anchorUpdates {
                    if Task.isCancelled { break }
                    //print("InferenceViewModel: start TRACE anchor updates")
                    self.meshAnchorContinuation?.yield(update)
                }
            }
            
            for await buffer in self.arkitSessionManager.pixelBufferStream() {
                if Task.isCancelled { break }
                //print("InferenceViewModel: start TRACE stored buffer")
                await self.frameBuffer.store(buffer)
            }
        }
        
        if let remote = appSettings?.remoteInference {
            if remote {
                startRemoteSender()
                startRemoteReceiver()
            } else {
                startLocalInference()
            }
        }
    }
    
    private func startRemoteSender() {
        remoteSendingTask = Task(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            while !Task.isCancelled {
                guard let trackedFrame = await self.frameBuffer.take() else {
                    await Task.yield()
                    continue
                }
                
                guard let processed = self.imageCaptureManager.preprocess(
                    trackedFrame: trackedFrame
                ) else {
                    continue
                }
                
                await self.latestFrameBuffer.store(processed)
                
                self.inferenceManager.sendFrame(processed)
            }
        }
    }
    
    private func startRemoteReceiver() {
        print("InferenceViewModel: startRemoteSender TRACE starting...")
        remoteResultTask = Task { [weak self] in
            guard let self else { return }
            for await observations in self.inferenceManager.remoteObservationsStream {
                if Task.isCancelled { break }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.tracker.updateTrackedObjects(with: observations)
                    self.trackedObjectsContinuation?.yield(self.tracker.trackedObjects)
                }
            }
        }
    }
    
    private func startLocalInference() {
        print("InferenceViewModel: startLocalInference TRACE starting ...")
        localInferenceTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            while !Task.isCancelled {
                // if none ready, yield and retry
                guard let trackedFrame = await self.frameBuffer.take() else {
                    await Task.yield()
                    continue
                }
                
                //print("InferenceViewModel: start TRACE got trackedFrame")
                // Preprocess off main
                guard
                    let processed = await self.imageCaptureManager.preprocessLetterboxed(
                        trackedFrame: trackedFrame,
                        targetSize: CGSize(width: 640, height: 640)
                    )
                else { continue }
                
                await self.latestFrameBuffer.store(trackedFrame)
                
                let observations = await self.inferenceManager.processFrame(
                    processed,
                    segmenting: appSettings?.inferenceTask == .SEG
                )
                
                // Tracking + yield — hop to main for @MainActor-isolated state
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.tracker.updateTrackedObjects(with: observations)
                    self.trackedObjectsContinuation?.yield(self.tracker.trackedObjects)
                }
            }
        }
    }
    
    func stop() {
        print("InferenceViewModel: stop")
        // local inference
        localInferenceTask?.cancel()
        localInferenceTask = nil
        
        // remote inference
        remoteResultTask?.cancel()
        remoteResultTask = nil
        
        remoteSendingTask?.cancel()
        remoteSendingTask = nil
        
        meshTask?.cancel()
        meshTask = nil
        
        cameraTask?.cancel()
        cameraTask = nil
        
        arkitSessionManager.stop()
        // TODO: cameraTask most likely killing it here too
        inferenceRunning = false
        inferenceManager.stop()
    }
}
