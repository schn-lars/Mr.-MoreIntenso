import SwiftUI
import Foundation

struct LaunchView: View {
    
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var appSettings: AppSettings

    @State private var inputUsername: String = ""
    @State private var inputPassword: String = ""
    @State private var isLoading: Bool = false
    @State private var isLoggedIn: Bool = false
    
    @State private var userMessage: String? = nil
    @State private var userMessageIsError: Bool = false
    
    private let launchVM: LaunchViewModel = LaunchViewModel()
    
    var body: some View {
        VStack(spacing: 30) {
            Text("Welcome to Mr.-MoreIntenso!")
                .font(.extraLargeTitle)
            
            HStack(alignment: .center) {
                Spacer()
                
                Image("MediaMix")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 300)
                
                Spacer(minLength: 20)
                
                // https://www.tutorialkart.com/swiftui/swiftui-divider/
                Divider()
                    .frame(width: 2, height: 300)
                    .background(Color.gray)
                    .padding(.vertical, 30)
                
                Spacer(minLength: 20)
                
                Image("MrMoreIntenso-Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 300)
                
                Spacer()
            }
            .frame(height: 300)
            
            HStack {
                Spacer()
                VStack(spacing: 10) {
                    TextField("Username", text: $inputUsername)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                    TextField("Password", text: $inputPassword)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                }
                Spacer()
            }
            
            HStack {
                Button("Login", action: {
                    // TODO: submit form for logging in with the provided credentials
                    launchVM.executeLogin(
                        username: $inputUsername.wrappedValue,
                        password: $inputPassword.wrappedValue
                    ) { result in
                        switch result {
                        case .success(_):
                            // close launchView and go to RootImmersiveView instead
                            self.isLoading.toggle()
                            self.clearInputs()
                            appModel.username = $inputUsername.wrappedValue
                            Task {
                                let result = await openImmersiveSpace(id: appModel.immersiveSpaceID)
                                if result == .opened {
                                    dismissWindow()
                                }
                            }
                            break
                        case .failure(let error):
                            // TODO: display error message
                            self.clearInputs()
                            userMessage = error.localizedDescription
                            userMessageIsError = true
                            break
                        }
                    }
                })
                .disabled(inputPassword == "" || inputUsername == "" || isLoading)
                
                Button("Register", action: {
                    // TODO: submit form for logging in with the provided credentials
                    launchVM.executeRegister(
                        username: $inputUsername.wrappedValue,
                        password: $inputPassword.wrappedValue
                    ) { result in
                        switch result {
                        case .success(_):
                            // Basically do nothing here. The user now has the option to press the login-button
                            // no need to clear the inputs as the user would otherwise need to write again
                            userMessage = "Registration was successful!"
                            userMessageIsError = false
                            break
                        case .failure(let error):
                            // TODO: display error message
                            print(error)
                            self.clearInputs()
                            userMessage = error.errorDescription
                            userMessageIsError = true
                            break
                        }
                    }
                })
                .disabled(inputPassword == "" || inputUsername == "" || isLoading)
                
                Button("Continue as Guest") {
                    launchVM.executeGuestLogin() { result in
                        switch result {
                        case .success(_):
                            // close launchView and go to RootImmersiveView instead
                            appModel.username = ConfigurationManager.shared.mrIntensoAPIGuestUsername
                            Task {
                                let result = await openImmersiveSpace(id: appModel.immersiveSpaceID)
                                if result == .opened {
                                    dismissWindow()
                                }
                            }
                            break
                        case .failure(let error):
                            // TODO: display error message
                            // The reasons why this would be happening is because of these:
                            // - config is not set correctly,
                            // - database does not have the user initialized
                            // - VPN?
                            userMessage = "This error should not happen. Check your configuration. \(error.localizedDescription)"
                            userMessageIsError = true
                            break
                        }
                    }
                }
                .disabled(isLoading)
            }
            
            // UserMessageSection
            if let message = userMessage {
                Text(message)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(userMessageIsError ? Color.red : Color.green)
                    .cornerRadius(10)
                    .padding(.horizontal)
            }
        }
        .padding()
        .onAppear {
            print("LaunchView has been opened appSettings=\(ObjectIdentifier(appSettings))")
        }
    }
    
    private func clearInputs() {
        self.inputPassword = ""
        self.inputUsername = ""
    }
}
