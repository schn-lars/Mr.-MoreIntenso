import SwiftUI

enum IntensoResultViewState {
    case loading
    case loaded(IntensoVLMResponse)
    case error(String)
}

struct IntensoResultView: View {
    @State var isReady: Bool = false
    @State var isMine: Bool = false
    @State var isShared: Bool = false
    @State var isSharing: Bool = false
    @EnvironmentObject private var configManager: ConfigurationManager
    @EnvironmentObject var resultsManager: ResultsManager
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss
    
    @State private var state: IntensoResultViewState = .loading
    @State private var selectedTopic: SelectedTopic?
    @State private var response: IntensoVLMResponse?
    @State private var userMessage: String? = nil
    @State private var userMessageIsError: Bool = false
    
    @StateObject private var vm = QueryViewModel()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                    .padding()
                    .frame(height: 200)
                    .background(.ultraThinMaterial)

                Divider()

                content
                    .frame(maxHeight: .infinity)
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay(alignment: .top) {
                if let message = userMessage {
                    Text(message)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            userMessageIsError ? Color.red : Color.green
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(radius: 8)
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(), value: userMessage)
        }
        .task {
            if let shared = resultsManager.selectedShare {
                self.state = .loaded(
                    IntensoVLMResponse(
                        owner: shared.owner,
                        object: shared.obj,
                        confidence: shared.confidence,
                        image: nil,
                        content: shared.json
                    )
                )
            } else {
                await loadData()
            }
        }
        .onAppear {
            //print("IntensoResultView: onAppear")
            appSettings.isSettingsOpen = true
            if let _ = resultsManager.selectedShare {
                isShared = true
                isReady = true
            }
        }
        .onDisappear {
            //print("IntensoResultView: onDisappear")
            appSettings.isSettingsOpen = false
            
            // resetting resultsManager for next opening
            // was not an issue before, as the value simply got overwritten.
            // But now that we re-use this class with shared Objects it gets messy.
            resultsManager.selectedDetection = nil
            resultsManager.selectedShare = nil
        }
    }
    
    private var header: some View {
        HStack(alignment: .center, spacing: 0) {
            Group {
                if let detection = resultsManager.selectedDetection {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(detection.label.uppercased())
                            .font(.headline)

                        Text("\(Int(detection.confidence * 100))% confidence")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                } else if let shared = resultsManager.selectedShare {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(shared.obj.uppercased())
                                .font(.headline)
                                .lineLimit(1)

                            Text("\(Int(shared.confidence * 100))% confidence")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        HStack(spacing: 6) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.subheadline)

                            Text("Shared by \(shared.owner)")
                                .font(.subheadline)
                                .lineLimit(1)
                        }
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.blue.opacity(0.12))
                        .clipShape(Capsule())
                    }
                } else {
                    Text("Unknown")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // centered image
            Group {
                if let image = resultsManager.selectedDetection?.croppedImage {
                    Image(uiImage: UIImage(cgImage: image))
                        .resizable()
                        .scaledToFill()

                } else if let shared = resultsManager.selectedShare,
                          let url = URL(string: shared.image_url) {
                    AsyncImage(url: url) { phase in
                        phase.image?
                            .resizable()
                            .scaledToFill()
                    }
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.gray.opacity(0.2))
                }
            }
            .frame(width: 180, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: .infinity, alignment: .center)

            // right side (buttons and controls)
            Group {
                headerAction
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 8)
        }
    }
    
    @ViewBuilder
    private var headerAction: some View {
        HStack(spacing: 12) {
            Button {
                guard !isSharing || !isShared || !isReady else {
                    print("IntensoResultView: headerAction GUARD isSharing=\(isSharing) and isShared\(isShared)")
                    return
                }
                
                isSharing = true
                share() { result in
                    switch result {
                    case .success(()):
                        displayMessage(message: "Succssfully shared object!", isError: false)
                        isShared = true
                        isSharing = false
                    case .failure(let error):
                        // TODO: display error message
                        displayMessage(
                            message: "Sharing object has failed! - \(error.localizedDescription)",
                            isError: true
                        )
                        isSharing = false
                        print("IntensoResultView: share ERROR \(error.localizedDescription)")
                    }
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 26))
            }
            .buttonStyle(.borderless)
            .disabled(isSharing || isShared || !isReady)

            Button {
                // search/lens action — wire up your logic here
                mediaMixSearch() { result in
                    switch result {
                    case .success(()):
                        print("IntensoResultView: headerAction CALLBACK - mediaMixSearch was successful")
                    case .failure(let error):
                        print("IntensoResultView: headerAction CALLBACK - mediaMixSearch failed: \(error.localizedDescription)")
                    }
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 26))
            }
            .buttonStyle(.borderless)
            .disabled(isSharing || !isReady)
        }
        .frame(width: 140, alignment: .trailing)
    }
    
    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .error(let message):
            Text(message)
                .foregroundStyle(.red)

        case .loaded(let result):
            HStack(spacing: 0) {
                leftPanel(result: result)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()

                Divider()
                rightPanel(result: result)
                    .frame(width: 250)
                    .padding(.vertical)
            }
            .background(.thinMaterial)
        }
    }
    
    @ViewBuilder
    private func leftPanel(result: IntensoVLMResponse) -> some View {
        switch selectedTopic {
            case .scope(let scope):
                if let topics = result.content[scope] {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            ForEach(topics.keys.sorted(), id: \.self) { topic in
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(getCleanedTopicName(topic: topic))
                                        .font(.title3)
                                        .bold()
                                    if let content = topics[topic] {
                                        renderContent(content)
                                    }
                                }
                                .padding()
                                .background(Color.white.opacity(0.03))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                        .padding()
                    }
                }
            case .topic(let scope, let topic):
                if let content = result.content[scope]?[topic] {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(getCleanedTopicName(topic: topic))
                                .font(.title2)
                                .bold()
                            renderContent(content)
                        }
                        .padding()
                    }
                }
            case nil:
                Text("Select a topic")
                    .foregroundStyle(.secondary)
            }
    }
    
    @ViewBuilder
    private func renderContent(_ content: IntensoContent) -> some View {
        switch content {
        case .text(let text):
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .list(let items):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                        Text(item)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
    
    private func rightPanel(result: IntensoVLMResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {

            Text("Topics")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(result.content.keys.sorted(), id: \.self) { scope in

                // Scope Button
                Button {
                    selectedTopic = .scope(scope)
                } label: {
                    Text(getCleanedTopicName(topic: scope))
                        .font(.headline)
                        .bold()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(
                            selectedTopic == .scope(scope)
                            ? Color.blue.opacity(0.15)
                            : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                // Nested Topics
                if let topics = result.content[scope] {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(topics.keys.sorted(), id: \.self) { topic in
                            Button {
                                selectedTopic = .topic(
                                    scope: scope,
                                    topic: topic
                                )
                            } label: {
                                Text(getCleanedTopicName(topic: topic))
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .padding(.leading, 12)
                                    .background(
                                        selectedTopic ==
                                        .topic(scope: scope, topic: topic)
                                        ? Color.blue.opacity(0.12)
                                        : Color.clear
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding()
    }
    
    private func loadData() async {
        do {
            guard let detection = resultsManager.selectedDetection,
                  let cropped = detection.croppedImage,
                  let full = detection.fullImage
            else {
                print("IntensoResultView: loadData GUARD detection is nil")
                state = .error("Could not load Detection properly.")
                return
            }
            
            let cropped_uiimage = UIImage(cgImage: cropped)
            let full_uiimage = UIImage(cgImage: full)
            guard let croppedImageData = cropped_uiimage.jpegData(compressionQuality: 0.4),
                  let fullImageData = full_uiimage.jpegData(compressionQuality: 0.4)
            else {
                print("IntensoResultView: loadData GUARD images are nil")
                state = .error("Images are empty.")
                return
            }
            
            let urlString = configManager.mrIntensoVlmUrl + "retrieve"
            guard let url = URL(string: urlString) else {
                print("IntensoResultView: loadData GUARD - url is nil")
                state = .error("URL is incorrect.")
                return
            }
            print("IntensoResultView: processing url \(urlString)")
            
            let boundary = UUID().uuidString
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            
            var body = Data()
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"obj\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(detection.label)\r\n".data(using: .utf8)!)
            
            // cropped image
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"cropped\"; filename=\"cropped.jpg\"\r\n".data(using: .utf8)!)

            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(croppedImageData)
            body.append("\r\n".data(using: .utf8)!)

            // full image
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"full\"; filename=\"full.jpg\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(fullImageData)
            body.append("\r\n".data(using: .utf8)!)
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)

            request.httpBody = body

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("IntensoResultView: invalid response")
                return
            }
            //print("IntensoResultView: loadData - TRACE Status:", httpResponse.statusCode)
            //print("IntensoResultView: loadData - TRACE response:", responseString ?? "nil")
            guard let jsonResponse = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String: Any] else {
                print("IntensoResultView: loadData ERROR - Internal Error parsing JSON.")
                return
            }
            
            guard let generalJson = jsonResponse["general"] as? [String : Any],
                  let specificJson = jsonResponse["specific"] as? [String : Any]
            else {
                print("IntensoResultView: loadData ERROR - invalid result format")
                state = .error("Invalid result format!")
                return
            }
            
            let general: [String : IntensoContent] = generalJson.compactMapValues({ value in
                switch value {
                case let string as String:
                    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return nil }
                    return .text(trimmed)
                case let array as [String]:
                    let filtered = array
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    guard !filtered.isEmpty else { return nil }
                    return .list(filtered)
                default:
                    print("Unsupported content type:", type(of: value))
                    return nil
                }
            })
            
            let specific: [String : IntensoContent] = specificJson.compactMapValues({ value in
                switch value {
                case let string as String:
                    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return nil }
                    return .text(trimmed)
                case let array as [String]:
                    let filtered = array
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    guard !filtered.isEmpty else { return nil }
                    return .list(filtered)
                default:
                    print("Unsupported content type:", type(of: value))
                    return nil
                }
            })
            
            // ["general" : ["url" : Any]]
            let content: [String : [String : IntensoContent]] = [
                "general" : general,
                "specific": specific
            ]
            
            let result = IntensoVLMResponse(
                owner: KeychainService.load(key: "moreintenso_username")?.stringValue ?? "UNKNOWN",
                object: detection.label,
                confidence: detection.confidence,
                image: cropped,
                content: content
            )
            self.response = result
            state = .loaded(result)
            isReady = true
        } catch {
            state = .error("Failed to load")
        }
    }
    
    private func isMe(username: String) -> Bool {
        return KeychainService.load(key: "moreintenso_username")?.stringValue == username
    }
    
    func share(
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        print("IntensoResultView: share TRACE starting")
        if isShared { return } // do not share if already shared!
        
        let urlString = ConfigurationManager.shared.mrIntensoApiUrl + "share/share-info"
        print("IntensoResultView: share TRACE not shared yet \(urlString)")
        guard let url = URL(string: urlString) else {
            print("IntensoResultView: share GUARD url is nil")
            completion(.failure(NSError(domain: "Guard", code: -1)))
            return
        }
        
        
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        guard let token = KeychainService.load(key: "auth_token") else {
            print("IntensoResultView: share GUARD - No auth token found")
            return
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        
        /// Helper, would otherwise be too messy in my opinion
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        
        guard let detection = resultsManager.selectedDetection,
              let croppedImage = detection.croppedImage,
              let extractedContent = self.response
        else {
            print("IntensoResultView: share GUARD - Cannot share this object as it does not exist.")
            completion(.failure(NSError(domain: "guard", code: -1)))
            return
        }
        
        guard let coordinates = locationManager.coordinate else {
            print("IntensoResultView: share GUARD - Unable to resolve location")
            completion(.failure(NSError(domain: "guard", code: -1)))
            return
        }
        
        guard let jsonString = makeContentJSON(info: extractedContent.content) else {
            print("IntensoResultView: share GUARD - jsonString is nil")
            completion(.failure(NSError(domain: "guard", code: -1)))
            return
        }
        
        field("id", detection.id.uuidString)
        field("label", detection.label)
        field("confidence", String(detection.confidence))
        field("coord_x", String(coordinates.longitude))
        field("coord_y", String(coordinates.latitude))
        field("content_json", jsonString)

        // Image part
        let uiImage = UIImage(cgImage: croppedImage)
        if let imageData = uiImage.jpegData(compressionQuality: 0.85) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"image\"; filename=\"detection.jpg\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(imageData)
            body.append("\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("IntensoResultView: share ERROR - \(error)")
                completion(.failure(error))
                return
            }
            
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                print("IntensoResultView: share GUARD - Bad server response")
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            
            guard let data = data else {
                print("IntensoResultView: share GUARD - no data")
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            
            
            guard let jsonResponse = try? JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String: Any] else {
                print("IntensoResultView: share ERROR - Internal Error parsing JSON.")
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            
            guard let status = jsonResponse["status"] as? Bool,
                  status == true // making it explicit such that it is clear
            else {
                print("IntensoResultView: share ERROR - invalid result format")
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            
            self.isShared = true
            completion(.success(()))
        }.resume()
    }
    
    private func mediaMixSearch(completion: @escaping (Result<Void, Error>) -> Void) {
        switch state {
        case .loaded(let message):
            guard let queryText = getSpecificSummary(from: message) else {
                print("IntensoResultView: mediaMixSearch GUARD - no query text")
                completion(.failure(NSError(domain: "No query text.", code: -1)))
                return
            }
            resultsManager.query = [(queryText, .sim)]
            print("IntensoResultView: mediaMixSearch TRACE - about to perform query")
            Task {
                let hasResults = await vm.performQuery(
                    resultsManager: resultsManager,
                    appSettings: appSettings,
                    similarityText: queryText,
                    ocrText: nil,
                    asrText: nil,
                    mergeType: nil
                )
                await presentResultsAfterQuery(hasResults: hasResults)
                completion(.success(()))
            }
        case _:
            print("IntensoResultView: mediaMixSearch TRACE - not yet loaded")
            completion(.failure(NSError(domain: "Not yet loaded", code: -1)))
            return
        }
        /**
         
         
         }
         */
    }
    
    /**
        Copied from QuerySystemView
     */
    @MainActor
    private func presentResultsAfterQuery(hasResults: Bool) async {
        guard hasResults else {
            print("IntensoResultView: presentResultsAfterQuery GUARD - no results")
            return
        }
        print("IntensoResultView: presentResultsAfterQuery TRACE - starting ...")

        switch appSettings.resultViewMode {
        case .spheres:
            print("IntensoResultView: presentResultsAfterQuery TRACE - in spheres")
            AppCoordinator.shared.dismissWindowAction?("gridResults")
            
            /// I probably do not need these, as ImmersiveSpace is already open
            //await openImmersiveSpace(id: "ImmersiveSpace")
            vm.isImmersiveSpaceOpen = true
            resultsManager.activateSphere()

        case .grid:
            print("IntensoResultView: presentResultsAfterQuery TRACE - in grid")
            /// unsure about this one, I dont like it.
            /// Ideally I should not close immersivespace anymore
            //if vm.isImmersiveSpaceOpen {
            //    await dismissImmersiveSpace()
            //    vm.isImmersiveSpaceOpen = false
            //}
            AppCoordinator.shared.openWindowAction?("gridResults")
        }
    }
    
    private func getSpecificSummary(from: IntensoVLMResponse) -> String? {
        if let specific = from.content["specific"] as? [String : IntensoContent],
           let summary = specific["summary"] as? IntensoContent {
            switch summary {
            case .text(let string):
                return string
            case _:
                return nil
            }
        }
        return nil
    }
    
    private func getCleanedTopicName(topic: String) -> String {
        return topic.replacingOccurrences(of: "_", with: " ").capitalized
    }
    
    private func makeContentJSON(info: [String : [String : IntensoContent]]) -> String? {
        var outer: [String : Any] = [:]
        for (section, items) in info {
            var inner: [String : Any] = [:]
            for (key, content) in items {
                switch content {
                case .text(let string):
                    inner[key] = string
                case .list(let list):
                    inner[key] = list
                }
            }
            outer[section] = inner
        }
        
        guard let data = try? JSONSerialization.data(withJSONObject: outer, options: .prettyPrinted),
              let jsonString = String(data: data, encoding: .utf8)
        else {
            print("IntensoResultView: makeContentJSON GUARD - could not serialize JSON")
            return nil
        }
        
        return jsonString
    }
    
    private func displayMessage(
        message: String,
        isError: Bool,
        duration: Int = 5
    ) {
        userMessage = message
        userMessageIsError = isError
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(duration)) {
            self.userMessageIsError = false
            self.userMessage = nil
        }
    }
}
