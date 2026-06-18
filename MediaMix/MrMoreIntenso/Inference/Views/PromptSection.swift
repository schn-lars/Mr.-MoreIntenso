import SwiftUI

struct PromptSection: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var configManager: ConfigurationManager
    @ObservedObject var vm: SettingsViewModel
    @State private var newPrompt: String = ""
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        if appSettings.model == .SAM3 {
            Section("SAM3 Prompts") {
                VStack(spacing: 12) {
                    // Existing prompts
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(Array(appSettings.prompts.enumerated()), id: \.offset) { index, prompt in
                                HStack {
                                    Text(prompt)
                                        .lineLimit(2)
                                        .font(.body)
                                    
                                    Spacer()
                                    
                                    Button(role: .destructive) {
                                        appSettings.prompts.remove(at: index)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(isProcessing)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .frame(minHeight: 0, maxHeight: 250)
                    // minHeight: 0 because if it is empty too much space is occupied
                    
                    // Add new prompt
                    HStack {
                        TextField("Enter new prompt...", text: $newPrompt)
                            .textFieldStyle(.roundedBorder)
                        
                        Button {
                            addPrompt()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.borderless)
                        .disabled(
                            newPrompt.trimmingCharacters(in: .whitespaces).isEmpty ||
                            isProcessing
                        )
                    }
                    
                    // Reset button
                    Button(role: .destructive) {
                        print("PromptSection: Reset to Default")
                        appSettings.prompts.removeAll()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset to Default")
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(isProcessing)
                }
                
                /**
                    I am ignoring positive cases as well as negative cases (server timed out or something, not based on the rules here)
                    The list should be consistent and since it is Published, it will propage the changes (eventho there are not any).
                    Exceptions are being handled in backend without frontend knowing what is happening.
                 */
                if let message = errorMessage {
                    Text(message)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red)
                        .cornerRadius(10)
                        .padding(.horizontal)
                }
            }
            .onAppear {
                newPrompt = "" // reset prompt
                errorMessage = nil
            }
        } else {
            EmptyView()
        }
    }
    
    private func setErrorMessage(with message: String) {
        self.errorMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.errorMessage = nil
        }
    }
    
    private func addPrompt() {
        let cleaned = newPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !cleaned.isEmpty else {
            setErrorMessage(with: "Please provide a non-empty string.")
            return
        }
        
        guard cleaned.count <= 100 else {
            setErrorMessage(with: "Prompt cannot exceed 100 characters.")
            return
        }
        
        guard !appSettings.prompts.contains(cleaned) else {
            setErrorMessage(with: "You have already specified that prompt.")
            return
        }
        
        guard appSettings.prompts.count <= 10 else {
            setErrorMessage(with: "You cannot have more than 10 prompts.")
            return
        }
        
        appSettings.prompts.append(cleaned)
        newPrompt = ""
    }
}
