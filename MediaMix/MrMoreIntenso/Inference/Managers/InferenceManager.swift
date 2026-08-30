import Foundation
import SwiftUI
import AVFoundation


/*
*   Access-point for any inference related inquiries.
*   The top-level multiplexer for both local and remote inference.
*/

class InferenceManager {
    private var serverSideInference: Bool = false
    private var isRunning: Bool = false
    
    private var remoteInferenceEngine = RemoteInferenceManager()
    private var localInferenceManager = LocalInferenceManager()
    var onLocalObservations: (([AnyObservation]) -> Void)?
    
    var remoteObservationsStream: AsyncStream<ResultObservations> {
        remoteInferenceEngine.observationsStream
    }
    
    
    func setup(
        model: IntensoInferenceModelType = .YOLOv26,
        task: IntensoInferenceTask = .DET,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        if serverSideInference {
            // TODO: potentially restart stream, but this probably not needed.
            remoteInferenceEngine.start_websocket_connection(
                model: model,
                task: task,
                completion: completion
            )
        } else {
            // TODO: add local inference engine startup code
            print("InferenceManager: setup locally")
            localInferenceManager.onDetections = { [weak self] observations in
                DispatchQueue.main.async {
                    self?.onLocalObservations?(observations)
                }
            }
            completion(.success(()))
        }
    }
    
    /**
        This method is being called, when the User switches from Remote to Local inference or vice versa.
        We only need to swap the model, as the model has been initialized in both of the engines.
        
        As an example: The Websocket is still running. After connection has been made, we send `init_model` request to it.
        Therefore, we can simply switch models.
     */
    func handleLocationChanges(
        remote: Bool,
        model: IntensoInferenceModelType,
        task: IntensoInferenceTask,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        
        if remote {
            // TODO: potentially restart stream, but this probably not needed.
            remoteInferenceEngine.sendSwitchModel(
                model: model,
                task: task
            ) { result in
                switch result {
                case .failure(let error):
                    print("InferenceManager: handleLocationChanges ERROR - \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                case .success(_):
                    print("InferenceManager: handleLocationChanges SUCCESS now running locally")
                    self.serverSideInference = remote
                    completion(.success(()))
                    return
                }
            }
        } else {
            // TODO: switch local inference model
            localInferenceManager.onDetections = { [weak self] observations in
                DispatchQueue.main.async {
                    self?.onLocalObservations?(observations)
                }
            }
        }
    }
    
    func handleModelChange(
        mode: IntensoInferenceTask,
        model: IntensoInferenceModelType,
        completion:  @escaping (Result<Void, Error>) -> Void
    ) {
        if serverSideInference {
            remoteInferenceEngine.sendSwitchModel(
                model: model,
                task: mode,
                completion: completion
            )
        } else {
            //completion(.failure(NSError(domain: "not supported", code: -1)))
            completion(.success(()))
        }
    }
    
    func handleModeChange(
        mode: IntensoInferenceTask,
        model: IntensoInferenceModelType,
        completion:  @escaping (Result<Void, Error>) -> Void
    ) {
        if serverSideInference {
            remoteInferenceEngine.sendSwitchModel(
                model: model,
                task: mode,
                completion: completion
            )
        } else {
            //completion(.failure(NSError(domain: "not supported", code: -1)))
            print("InferenceManager: handleModeChange SUCCESS local only (no-brainer)")
            completion(.success(()))
        }
    }
    
    func stop() {
        if serverSideInference {
            //remoteInferenceEngine.stop()
            // I am simply not sending anymore. This method could benefit from more robustness
        } else {
            // stop locally
        }
    }
    
    /**
        This method calls the local-inferenceManager to perform inference.
     */
    func processFrame(_ trackedFrame: TrackedFrame, segmenting: Bool) async -> ResultObservations {
        guard !serverSideInference else {
            return
                ResultObservations(
                    observations: [],
                    extrinsics: trackedFrame.extrinsics
                )
        }
        
        return await localInferenceManager.processFrame(trackedFrame, segmenting: segmenting)
    }
    
    /**
        This method calls server-side inference. Since the communication is using websockets, we cannot react to them in the same way as HTTP requests.
     */
    func sendFrame(_ trackedFrame: TrackedFrame) {
        guard serverSideInference else { return }
        remoteInferenceEngine.sendFrame(trackedFrame)
    }
    
    /**
        Propagate when changes have happened initiated from the SettingsView.
     */
    func sendNewPrompts(_ prompts: [String], completion: @escaping (Result<Void, Error>) -> Void) {
        remoteInferenceEngine.sendNewPrompts(prompts, completion: completion)
    }
    
    func sendSetDefaultPrompt(completion: @escaping (Result<Void, Error>) -> Void) {
        remoteInferenceEngine.sendSetDefaultPrompt(completion: completion)
    }
    
    func sendSwitchModel(
        model: IntensoInferenceModelType,
        task: IntensoInferenceTask,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        if serverSideInference {
            if !remoteInferenceEngine.isConnected {
                completion(.failure(NSError(domain: "connection", code: -1)))
            }
            
            remoteInferenceEngine.sendSwitchModel(model: model, task: task, completion: completion)
        } else {
            completion(.failure(NSError(domain: "NotImplemented", code: 1)))
        }
    }
}
