/**
    This class is responsible for Server-Side inference.
 */

import AVFoundation
import SwiftUI

// TODO: Common protocol which works as base interface between InferenceManager and either Remote or Local inference
class RemoteInferenceManager {
    /// Variables used for server-side inference
    private var inferenceWebsocket: URLSessionWebSocketTask?
    private var lastSentImage = Date()
    private var sentImageTimestamps: [TimeInterval] = []
    
    /// state variables
    private var currentModel: IntensoInferenceModelType = .YOLOv26
    private var currentTask: IntensoInferenceTask = .SEG
    
    // We only want one in-flight communication
    private var waitingForModelChange = false
    private var waitingForPromptChange = false
    private var waitingForStreaming = false
    var isConnected: Bool = false
    
    let context = CIContext()
    
    /// Callbacks for responses
    private var pendingPromptUpdate: ((Result<Void, Error>) -> Void)?
    private var pendingModelChange: ((Result<Void, Error>) -> Void)?
    
    /// Used for async stream in the `InferenceManager`
    private var observationsContinuation: AsyncStream<ResultObservations>.Continuation?

    var observationsStream: AsyncStream<ResultObservations> {
        AsyncStream { continuation in
            self.observationsContinuation = continuation
        }
    }
    
    private var pendingFrames: [TrackedFrame] = []
    private let maxPendingFrames: Int = 5
    
    func start_websocket_connection(
        model: IntensoInferenceModelType = .YOLOv26,
        task: IntensoInferenceTask = .DET,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        print("RemoteInferenceManager: start")
        setup() { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(()):
                self.sendInitModel(model: model, task: task, completion: completion)
            }
            
        }
    }
    
    private func setup(
        model: IntensoInferenceModelType = .YOLOv26,
        task: IntensoInferenceTask = .DET,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let base = ConfigurationManager.shared.mrIntensoApiUrl
        let wsBase = base
            .replacingOccurrences(of: "https://", with: "wss://") // just in case
            .replacingOccurrences(of: "http://", with: "ws://")
        
        guard let url = URL(
            string: wsBase + "inference/ws/inference"
        ) else {
            print("RemoteInferenceManager: Setup ERROR - Invalid URL")
            return
        }
        
        mk_websocket_connection(
            url: url
        )
        
        waitForConnection(completion: completion)
    }
    
    func stop() {
        print("RemoteInferenceManager: Stopping")
        close_websocket_connection()
    }
    
    func sendFrame(_ trackedFrame: TrackedFrame) {
        guard isConnected else {
            print("RemoteInferenceManager: sendFrame - Inference not running")
            return
        }
        
        let now = Date()
        
        guard now.timeIntervalSince(lastSentImage) > 0.2 else { return }
        lastSentImage = now
        
        guard let data = convert_to_jpeg_data(trackedFrame.buffer) else { return }
        
        if pendingFrames.count >= maxPendingFrames {
            pendingFrames.removeFirst()
        }
        pendingFrames.append(trackedFrame)
        sentImageTimestamps.append(now.timeIntervalSince1970)
        
        //print("RemoteInferenceManager: sendFrame")
        inferenceWebsocket?.send(.data(data)) { error in
            if let error = error {
                print("Send error:", error)
            }
        }
    }
    
    private func convert_to_jpeg_data(_ pixelBuffer: CVPixelBuffer) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        
        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: 0.6)
    }
    
    private func mk_websocket_connection(url: URL) {
        print("mk_websocket_connection: Setting up connection")
        /// The following logic is needed for the authentification
        /// If not needed (as backend no longer needs it) simply delete everytihng until
        /// where inferenceWebsocket gets created using
        /// inferenceWebsocket = URLSession.shared.webSocketTask(with: url)
        guard let token = KeychainService.load(key: "auth_token") else {
            print("RemoteInferenceManager: mk_websocket_connection GUARD No auth token found")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        inferenceWebsocket = URLSession.shared.webSocketTask(with: request)
        guard let ws = inferenceWebsocket else {
            print("RemoteInferenceManager: mk_websocket_connection ERROR nil")
            return
        }
        ws.resume()
        
        isConnected = true
        
        print("RemoteInferenceManager: About to start ping \(isConnected)")
        startPing()
        
        
        receive()
    }
    
    private func waitForConnection(
        timeout: TimeInterval = 5.0,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let start = Date()

        func check() {
            if self.isConnected {
                print("RemoteInferenceEngine: waitForConnection SUCCESS")
                completion(.success(()))
                return
            }

            if Date().timeIntervalSince(start) > timeout {
                print("RemoteInferenceEngine: waitForConnection ERROR timeout")
                completion(.failure(NSError(domain: "timeout", code: -1)))
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                check()
            }
        }
        check()
    }
    
    // https://www.appspector.com/blog/websockets-in-ios-using-urlsessionwebsockettask
    private func close_websocket_connection() {
        guard let ws = inferenceWebsocket else {
            print("close_websocket_connection: ERROR - Websocket is nil")
            return
        }
        print("close_websocket_connection: Closing websocket")
        ws.cancel(with: .goingAway, reason: nil)
    }
    
    /**
        This method is the main entrypoint for incoming websocket responses.
        It esentially implements the protocol on the receiving side.
        Make sure you are using the correct callbacks. These callbacks are essential, as the response will otherwise be ignored by the frontend.
     */
    private func receive() {
        inferenceWebsocket?.receive { [weak self] result in
            defer { self?.receive() } // we need to call this function every time. This makes it easier.
            
            switch result {
            case .success(.string(let text)):
                self?.isConnected = true
                guard let data = text.data(using: .utf8) else { return }

                do {
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

                    if let status = json?["status"] as? String {
                        print("RemoteInferenceManager: receive - STATUS \(status)")
                        if status == "prompt_updated" {
                            self?.pendingPromptUpdate?(.success(()))
                            self?.pendingPromptUpdate = nil
                            self?.waitingForPromptChange = false
                            return
                        }
                        
                        /// this will be invoked once the user setup the websocket connection
                        /// it is the default configuration that is being invoked here technically
                        /// TODO: we might even drop this case later actually
                        else if status == "model_loaded" {
                            guard let model = json?["model"] as? String,
                                  let task  = json?["task"] as? String,
                                  let currentModel = try? IntensoInferenceModelType.fromDisplayName(model),
                                  let currentTask = try? IntensoInferenceTask.fromDisplayName(task)
                            else {
                                print("RemoteInferenceManager: receive model_loaded ERROR - no model or task")
                                self?.pendingModelChange?(.failure(NSError(domain: "guard", code: -1)))
                                self?.pendingModelChange = nil
                                self?.waitingForModelChange = false
                                self?.sentImageTimestamps.removeAll()
                                return
                            }
                            
                            self?.pendingModelChange?(.success(()))
                            self?.pendingModelChange = nil
                            self?.waitingForModelChange = false
                            self?.currentModel = currentModel
                            self?.currentTask = currentTask
                            self?.sentImageTimestamps.removeAll()
                            return
                        }
                        
                        /// this is being returned when the user switched models
                        else if status == "model_switched" {
                            guard let model = json?["model"] as? String,
                                  let task  = json?["task"] as? String,
                                  let currentModel = try? IntensoInferenceModelType.fromDisplayName(model),
                                  let currentTask = try? IntensoInferenceTask.fromDisplayName(task)
                            else {
                                print("RemoteInferenceManager: receive model_switched ERROR - no model or task")
                                self?.pendingModelChange?(.failure(NSError(domain: "guard", code: -1)))
                                self?.pendingModelChange = nil
                                self?.waitingForModelChange = false
                                self?.sentImageTimestamps.removeAll()
                                return
                            }
                            
                            self?.pendingModelChange?(.success(()))
                            self?.pendingModelChange = nil
                            self?.waitingForModelChange = false
                            self?.currentModel = currentModel
                            self?.currentTask = currentTask
                            self?.sentImageTimestamps.removeAll()
                            return
                        }
                        
                        else {
                            print("RemoteInferenceManager: receive() - ERROR unknown status '\(status)'")
                            return
                        }
                    } else if let type = json?["type"] as? String,
                              let observations = json?["observations"] as? [[String: Any]],
                              let time = json?["time"] as? Float {
                        //print("RemoteInferenceManager: received inference result")
                        
                        guard   let self = self,
                                self.pendingFrames.count > 0
                        else {
                            /// This should not be possible. But like this it is the most harmless
                            self?.observationsContinuation?.yield(
                                ResultObservations(
                                    observations: [],
                                    extrinsics: nil
                                )
                            )
                            return
                        }
                        
                        let trackedFrame = self.pendingFrames.removeFirst()
                        //let start = Date().timeIntervalSince1970
                        if type == IntensoInferenceTask.SEG.displayName {
                            let parsed = observations.compactMap { obs -> AnyObservation? in
                                // parse your observation here
                                guard let box = obs["bbox"] as? [String : Any] else {
                                    print("RemoteInfereceManager: invalid format for bounding box")
                                    return nil
                                }
                                
                                guard
                                    let x = self.toFloat(box["x"]),
                                    let y = self.toFloat(box["y"]),
                                    let w = self.toFloat(box["width"]),
                                    let h = self.toFloat(box["height"]),
                                    let c = self.toFloat(obs["confidence"])
                                else {
                                    print("RemoteInfereceManager: Invalid bbox format")
                                    return nil
                                }
                                
                                let cropped = self.cropPixelBufferToCGImage(
                                    trackedFrame.buffer,
                                    bbox: CGRect(
                                        x: Double(x),
                                        y: Double(y),
                                        width: Double(w),
                                        height: Double(h)
                                    )
                                )
                                
                                guard let maskB64 = obs["mask"] as? String,
                                      let maskWidth = obs["mask_width"] as? Int,
                                      let maskHeight = obs["mask_height"] as? Int,
                                      let maskData = Data(base64Encoded: maskB64)
                                else {
                                    print("RemoteInferenceManager: receive GUARD mask parsing failed")
                                    return nil
                                }
                                let maskFlat: [Bool] = maskData.map { $0 != 0 }
                                
                                let croppedMask = self.cropMaskToBBox(
                                    mask: maskFlat,
                                    normalized: BoundingBox(
                                        x: x,
                                        y: y,
                                        width: w,
                                        height: h
                                    )
                                )
                                
                                return AnyObservation(
                                    base: Segmentation(
                                        label: obs["label"] as! String,
                                        confidence: c,
                                        bbox: BoundingBox(
                                            x: x,
                                            y: y,
                                            width: w,
                                            height: h
                                        ),
                                        mask: croppedMask
                                    ),
                                    extrinsics: trackedFrame.extrinsics,
                                    image: cropped
                                )
                            }
                            
                            let result = ResultObservations(
                                observations: parsed,
                                extrinsics: trackedFrame.extrinsics
                            )
                            //let now = Date().timeIntervalSince1970
                            //let duration = now - start
                            //let latency = now - sentImageTimestamps.removeFirst()
                            //print("\(now)|\(duration)|\(latency)|\(time)")
                            self.observationsContinuation?.yield(result)
                            return
                        } else if type == IntensoInferenceTask.DET.displayName {
                            let parsed = observations.compactMap { obs -> AnyObservation? in
                                // parse your observation here
                                guard let box = obs["bbox"] as? [String : Any] else {
                                    print("RemoteInfereceManager: invalid format for bounding box")
                                    return nil
                                }
                                
                                guard
                                    let x = self.toFloat(box["x"]),
                                    let y = self.toFloat(box["y"]),
                                    let w = self.toFloat(box["width"]),
                                    let h = self.toFloat(box["height"]),
                                    let c = self.toFloat(obs["confidence"])
                                else {
                                    print("RemoteInfereceManager: Invalid bbox format")
                                    return nil
                                }
                                
                                /*
                                // Width should not be all used except with small height
                                guard w < 0.8 && h < 0.4 else { return nil }
                                
                                // Height should not be all used except with small width
                                guard w < 0.4 && h < 0.8 else { return nil }
                                
                                guard w * h < 0.8 else { return nil }
                                
                                */
                                let cropped = self.cropPixelBufferToCGImage(
                                    trackedFrame.buffer,
                                    bbox: CGRect(
                                        x: Double(x),
                                        y: Double(y),
                                        width: Double(w),
                                        height: Double(h)
                                    )
                                )
                                
                                return AnyObservation(
                                    base: Detection(
                                        label: obs["label"] as! String,
                                        confidence: c,
                                        bbox: BoundingBox(
                                            x: x,
                                            y: y,
                                            width: w,
                                            height: h
                                        )
                                    ),
                                    extrinsics: trackedFrame.extrinsics,
                                    image: cropped
                                )
                            }
                            
                            let result = ResultObservations(
                                observations: parsed,
                                extrinsics: trackedFrame.extrinsics
                            )
                            //let now = Date().timeIntervalSince1970
                            //let duration = now - start
                            //let latency = now - sentImageTimestamps.removeFirst()
                            //print("\(now)|\(duration)|\(latency)|\(time)")
                            self.observationsContinuation?.yield(result)
                            return
                        } else {
                            print("RemoteInferenceManager: receive ERROR unknown type \(type)")
                        }
                    }
                } catch {
                    print("Decoding error:", error)
                }
            case .success(.data(let data)):
                print("RemoteInferenceManager - Data:", data)
                return
            case .failure(let error):
                print("RemoteInferenceManager: receive ERROR - \(error.localizedDescription)")
                self?.handleDisconnect()
                return
            case .success(_):
                self?.isConnected = true
                print("RemoteInferenceManager: receive: .success(.none)")
                return
            }
        }
    }
    
    private func toFloat(_ value: Any?) -> Float? {
        if let d = value as? Double { return Float(d) }
        if let f = value as? Float { return f }
        if let n = value as? NSNumber { return n.floatValue }
        return nil
    }
    
    /*
     *  This method is needed as websockets are mean sometimes and decide to die.
     */
    private func handleDisconnect() {
        print("RemoteInferenceManager: handleDisconnect — attempting reconnect")

        inferenceWebsocket = nil
        isConnected = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.start_websocket_connection() { result in
                switch result {
                case .failure(_):
                    print("RemoteInferenceManager: handleDisconnect ERROR reconnect has failed!")
                    self.handleDisconnect()
                    return
                case .success(()):
                    self.isConnected = true
                    return
                }
            }
        }
    }
    
    /**
        This method is needed to figure out the status of our connection.
        - Different Approach:
            Technically, we could simply set `isConnected` to false if `receive` or `send` fails.
     */
    private func startPing() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self = self else { return }

            self.inferenceWebsocket?.sendPing { error in
                if let error = error {
                    print("RemoteInferenceManager: Ping ERROR - \(error.localizedDescription)")
                    self.isConnected = false
                    self.handleDisconnect()
                } else {
                    self.isConnected = true
                    self.startPing()
                }
            }
        }
    }
    
    func sendNewPrompts(_ prompts: [String], completion: @escaping (Result<Void, Error>) -> Void) {
        guard let ws = inferenceWebsocket else {
            print("RemoteInferenceManager: sendNewPrompts ERROR - WebSocket is nil")
            handleDisconnect()
            return
        }
        
        let message = WSPromptMessage(
            type: "set_prompt",
            prompt: prompts
        )
        
        guard let data = try? JSONEncoder().encode(message),
              let text = String(data: data, encoding: .utf8)
        else {
            completion(.failure(NSError(domain: "encoding", code: -1)))
            return
        }
        
        pendingPromptUpdate = completion
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self else { return }

            if self.waitingForPromptChange {
                print("RemoteInferenceManager: sendNewPrompts TIMEOUT — resetting state")
                self.waitingForPromptChange = false
                self.pendingPromptUpdate?(.failure(NSError(domain: "timeout", code: -1)))
                self.pendingPromptUpdate = nil
            }
        }
        
        
        ws.send(.string(text)) { error in
            if let error = error {
                print("RemoteInferenceManager: sendNewPrompts ERROR - \(error.localizedDescription)")
                self.waitingForPromptChange = false
                self.pendingPromptUpdate?(.failure(error))
                self.pendingPromptUpdate = nil
                return
            }
        }
    }
    
    /**
            This function is intended to be called on startup of the application.
            It allows to change the default in this application and not being dependent on the implementation of the backend.
            The backend is therefore truly stateless.
     */
    func sendInitModel(
        model: IntensoInferenceModelType,
        task: IntensoInferenceTask,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let ws = inferenceWebsocket else {
            print("RemoteInferenceManager: sendInitModel ERROR - WebSocket is nil")
            handleDisconnect()
            return
        }
        
        guard !waitingForModelChange else {
            print("RemoteInferenceManager: sendInitModel ERROR - we are already waiting for model change")
            completion(.failure(NSError(domain: "Try again later.", code: -1)))
            return
        }
        
        let message = WSInitModelMessage(
            type: "init_model",
            model: model.displayName,
            task: task.displayName
        )
        
        guard let data = try? JSONEncoder().encode(message),
              let text = String(data: data, encoding: .utf8)
        else {
            completion(.failure(NSError(domain: "encoding", code: -1)))
            return
        }
        
        pendingModelChange = completion
        waitingForModelChange = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self else { return }

            if self.waitingForModelChange {
                print("RemoteInferenceManager: sendInitModel TIMEOUT — resetting state")
                self.waitingForModelChange = false
                self.pendingModelChange?(.failure(NSError(domain: "timeout", code: -1)))
                self.pendingModelChange = nil
            }
        }
        
        ws.send(.string(text)) { error in
            if let error = error {
                print("RemoteInferenceManager: sendInitModel ERROR - \(error.localizedDescription)")
                self.waitingForModelChange = false
                self.pendingModelChange?(.failure(error))
                self.pendingModelChange = nil
                return
            }
        }
    }
    
    func sendSetDefaultPrompt(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let ws = inferenceWebsocket else {
            print("RemoteInferenceManager: sendSetDefaultPrompt ERROR - WebSocket is nil")
            handleDisconnect()
            return
        }
        
        let message = WSPromptMessage(
            type: "set_prompt",
            prompt: nil
        )
        
        guard let data = try? JSONEncoder().encode(message),
              let text = String(data: data, encoding: .utf8)
        else {
            completion(.failure(NSError(domain: "encoding", code: -1)))
            return
        }
        
        pendingPromptUpdate = completion
        waitingForPromptChange = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self else { return }

            if self.waitingForPromptChange {
                print("RemoteInferenceManager: sendSetDefaultPrompt TIMEOUT — resetting state")
                self.waitingForPromptChange = false
                self.pendingPromptUpdate?(.failure(NSError(domain: "timeout", code: -1)))
                self.pendingPromptUpdate = nil
            }
        }
        
        ws.send(.string(text)) { error in
            if let error = error {
                print("Prompt send error:", error)
                self.waitingForPromptChange = false
                self.pendingPromptUpdate?(.failure(error))
                self.pendingPromptUpdate = nil
                return
            }
        }
    }
    
    func sendSwitchModel(
        model: IntensoInferenceModelType,
        task: IntensoInferenceTask,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let ws = inferenceWebsocket else {
            print("RemoteInferenceManager: sendSwitchModel ERROR - WebSocket is nil")
            handleDisconnect()
            completion(.failure(NSError(domain: "guard", code: -1)))
            return
        }
        
        guard !waitingForModelChange else {
            print("RemoteInferenceManager: sendSwitchModel ERROR - we are already waiting for model change")
            completion(.failure(NSError(domain: "Try again later.", code: -1)))
            return
        }
        
        let message = WSSwitchModelMessage(
            type: "switch_model",
            model: model.displayName,
            task: task.displayName
        )
        
        guard let data = try? JSONEncoder().encode(message),
              let text = String(data: data, encoding: .utf8)
        else {
            completion(.failure(NSError(domain: "encoding", code: -1)))
            return
        }
        
        pendingModelChange = completion
        waitingForModelChange = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self else { return }

            if self.waitingForModelChange {
                print("RemoteInferenceManager: sendSetDefaultPrompt TIMEOUT — resetting state")
                self.waitingForModelChange = false
                self.pendingModelChange?(.failure(NSError(domain: "timeout", code: -1)))
                self.pendingModelChange = nil
            }
        }
        
        print("RemoteInferenceManager: sendSwitchModel TRACE - about to send it")
        
        ws.send(.string(text)) { error in
            if let error = error {
                print("RemoteInferenceManager: sendSwitchModel ERROR - ", error)
                self.waitingForModelChange = false
                self.pendingModelChange?(.failure(error))
                self.pendingModelChange = nil
                return
            }
        }
    }
    
    func cropPixelBufferToCGImage(
        _ pixelBuffer: CVPixelBuffer,
        bbox: CGRect
    ) -> CGImage? {

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        let width = ciImage.extent.width
        let height = ciImage.extent.height

        let cropRect = CGRect(
            x: bbox.minX * width,
            y: (1.0 - bbox.maxY) * height,
            width: bbox.width * width,
            height: bbox.height * height
        )

        guard let cgImage = context.createCGImage(
            ciImage,
            from: cropRect
        ) else {
            return nil
        }
        return cgImage
    }
    
    private func cropMaskToBBox(
        mask: [Bool],
        maskWidth: Int = 256,
        maskHeight: Int = 256,
        normalized bbox: BoundingBox,
        outputSize: Int = 256
    ) -> [Bool] {
        let x0 = Int(bbox.x * Float(maskWidth))
        let y0 = Int(bbox.y * Float(maskHeight))
        let bw = max(1, Int(bbox.width * Float(maskWidth)))
        let bh = max(1, Int(bbox.height * Float(maskHeight)))

        var cropped = [Bool](repeating: false, count: outputSize * outputSize)
        
        mask.withUnsafeBufferPointer { srcPtr in
            cropped.withUnsafeMutableBufferPointer { dstPtr in
                for row in 0..<outputSize {
                    let srcY = y0 + row * bh / outputSize
                    guard srcY < maskHeight else { continue }
                    let srcRowOffset = srcY * maskWidth
                    
                    for col in 0..<outputSize {
                        let srcX = x0 + col * bw / outputSize
                        guard srcX < maskWidth else { continue }
                        dstPtr[row * outputSize + col] = srcPtr[srcRowOffset + srcX]
                    }
                }
            }
        }
        return cropped
    }
}
