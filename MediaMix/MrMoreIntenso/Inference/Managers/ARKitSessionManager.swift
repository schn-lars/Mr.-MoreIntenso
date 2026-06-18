import ARKit
import CoreVideo
import QuartzCore

class ARKitSessionManager: ObservableObject {
    private var arKitSession = ARKitSession()
    // https://developer.apple.com/documentation/arkit/cameraframeprovider
    private(set) var cameraFrameProvider = CameraFrameProvider()
    private(set) var worldTrackingProvider = WorldTrackingProvider()
    private(set) var sceneProvider = SceneReconstructionProvider(modes: [.classification])
    
    var arKitToRealityKit: simd_float4x4 = matrix_identity_float4x4
    
    var anchorUpdates: some AsyncSequence<AnchorUpdate<MeshAnchor>, Never> {
        sceneProvider.anchorUpdates
    }
    
    // Called once when immersive space opens
    func start() async throws {
        arKitSession = ARKitSession()
        cameraFrameProvider = CameraFrameProvider()
        worldTrackingProvider = WorldTrackingProvider()
        sceneProvider = SceneReconstructionProvider(modes: [.classification])
        
        // Requires entitlement
        print("CameraFeedProvider: start")
        let authStatus = await arKitSession.requestAuthorization(
            for: [
                .worldSensing,
                .handTracking,
                .cameraAccess
            ]
        )
        guard authStatus[.worldSensing] == .allowed else {
            fatalError("CameraFeedProvider: We do not have access to the main camera.")
        }
        
        guard SceneReconstructionProvider.isSupported else {
            print("CameraFeedProvider: Scene Reconstruction is not supported on this device.")
            return
        }
        
        print("CameraFeedProvider: Starting ARKit session...")
        try await arKitSession.run([
            cameraFrameProvider,
            sceneProvider,
            worldTrackingProvider
        ])
    }
    
    func stop() {
        arKitSession.stop()
    }
    
    /// https://www.peachpit.com/articles/article.aspx?p=3197435&seqNum=4
    
    func pixelBufferStream() -> AsyncStream<TrackedFrame> {
        AsyncStream { continuation in
            let task = Task {
                let formats = CameraVideoFormat.supportedVideoFormats(
                    for: .main,
                    cameraPositions: [.left]
                )
                guard let format = formats.first else {
                    continuation.finish()
                    return
                }
                
                
                guard let updates = cameraFrameProvider.cameraFrameUpdates(
                    for: format
                ) else {
                    continuation.finish()
                    return
                }
                
                for await cameraFrame in updates {
                    if Task.isCancelled { break }
                    guard let sample = cameraFrame.sample(for: .left) else { continue }
                    /// Parameters(
                    ///     intrinsics:
                    ///     <matrix=
                    ///         (736.633911, 0.000000, 0.000000)
                    ///         (0.000000, 736.633911, 0.000000)
                    ///         (960.000000, 540.000000, 1.000000)
                    ///     >,
                    ///     extrinsics:
                    ///     <translation=(
                    ///         0.024762 -0.021401 -0.057167
                    ///     ) ... other information as well...
                    let hardwareExtrinsics = sample.parameters.extrinsics
                    guard let deviceAnchor = worldTrackingProvider.queryDeviceAnchor(atTimestamp: sample.parameters.captureTimestamp) else {
                        continue
                    }
                    let deviceFromWorldARKit = deviceAnchor.originFromAnchorTransform
                    let deviceFromWorldRK = arKitToRealityKit * deviceFromWorldARKit
                    let deviceFromCamera = simd_inverse(hardwareExtrinsics)
                    let cameraFromWorldRK = deviceFromWorldRK * deviceFromCamera
                    
                    /*
                    let rayOrigin = deviceFromWorld.columns.3.toFloat3()
                    print("ARKitSessionManager: rayOrigin - \(rayOrigin)")
                    
                    // Camera position in world space = device_in_world * camera_from_device
                    let deviceFromCamera = simd_inverse(hardwareExtrinsics)
                    
                    let cameraFromWorld = deviceFromWorld * deviceFromCamera
                    */
                    let trackedFrame = TrackedFrame(
                        buffer: sample.pixelBuffer,
                        extrinsics: cameraFromWorldRK
                    )
                    continuation.yield(trackedFrame)
                }
                
                continuation.finish()
            }
            
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
    
    func setARKitBridge(bridge: simd_float4x4) {
        self.arKitToRealityKit = bridge
        print("ARKitSessionManager: bridge set to \(bridge == matrix_identity_float4x4 ? "IDENTITY (bad)" : "non-identity (good)")")
    }
    
    func currentDeviceTransform() -> simd_float4x4? {
        guard let anchor = worldTrackingProvider.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else {
            return nil
        }
        return anchor.originFromAnchorTransform
    }
}
