/**
    This class is used to control the user input of the LaunchView.
    The logic mostly contains logic regarding authorization.
 */
import Foundation

class LaunchViewModel {
    private let apiClient = IntensoAPIClient.shared
    
    func executeGuestLogin(completion: @escaping (Result<Void, APIError>) -> Void) {
        executeLogin(
            username: ConfigurationManager.shared.mrIntensoAPIGuestUsername,
            password: ConfigurationManager.shared.mrIntensoAPIGuestPassword
        ) { result in
            completion(result)
        }
    }
    
    func executeLogin(
        username: String,
        password: String,
        completion: @escaping (Result<Void, APIError>) -> Void
    ) {
        apiClient.login(username: username, password: password) { result in
            switch result {
            case .success(_):
                completion(.success(()))

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func executeRegister(
        username: String,
        password: String,
        completion: @escaping (Result<String, APIError>) -> Void
    ) {
        apiClient.register(username: username, password: password) { result in
            switch result {
            case .success(_):
                completion(.success("Succesfully registered!"))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}
