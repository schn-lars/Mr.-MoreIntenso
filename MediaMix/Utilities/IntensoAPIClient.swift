import Foundation

/**
    This class is supposed to act as an inferface to the rest of the application to call the backend to
    make use of `Mr. Intenso`'s benefits and exposed endpoints.
 */
class IntensoAPIClient {
    static let shared = IntensoAPIClient()
    private var configManager: ConfigurationManager = ConfigurationManager.shared
    
    ///
    /// Authentification endpoints:
    ///     - LOGIN
    ///     - REGISTER
    ///
    
    func login(username: String, password: String, completion: @escaping (Result<Token, APIError>) -> Void) {
        guard let url = URL(string: configManager.mrIntensoApiUrl + "users/login") else {
            completion(.failure(.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let body = "username=\(username)&password=\(password)"
        request.httpBody = body.data(using: .utf8)

        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("IntensoAPIClient: Login error:", error)
                completion(.failure(.serverError(error.localizedDescription)))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.networkError(URLError(.badServerResponse))))
                return
            }

            guard let data = data else {
                completion(.failure(.networkError(URLError(.badServerResponse))))
                return
            }

            if httpResponse.statusCode == 401 {
                completion(.failure(.unauthorized))
                return
            }

            do {
                let decoded = try JSONDecoder().decode(Token.self, from: data)
                print("IntensoAPIClient: login was successful")
                KeychainService.save(key: "auth_token", value: decoded.access_token)
                KeychainService.save(key: "moreintenso_username", value: username)
                completion(.success(decoded))
            } catch {
                print("IntensoAPIClient: Decoding error:", error)
                completion(.failure(.decodingError))
            }

        }.resume()
    }
    
    func register(username: String, password: String, completion: @escaping (Result<Void, APIError>) -> Void) {
        guard let url = URL(string: configManager.mrIntensoApiUrl + "users/register") else {
            print("IntensoAPIClient: Error creating the register URL")
            completion(.failure(.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "username": username,
            "password": password
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("IntensoAPIClient: Register error:", error)
                completion(.failure(.serverError(error.localizedDescription)))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.networkError(URLError(.badServerResponse))))
                return
            }

            guard let data = data else {
                completion(.failure(.networkError(URLError(.badServerResponse))))
                return
            }

            if httpResponse.statusCode == 401 {
                completion(.failure(.unauthorized))
                return
            }
            
            do {
                guard let jsonResponse = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String: Any] else {
                    print("IntensoAPIClient: Decoding has failed")
                    completion(.failure(.decodingError))
                    return
                }
                if let detail = jsonResponse["detail"] as? String {
                    print("IntensoAPIClient: Registration has failed \(detail)")
                    completion(.failure(.serverError(detail)))
                    return
                }
                
                if (jsonResponse["status"] as? Bool)! {
                    print("IntensoAPIClient: register-success: \(String(data: data, encoding: .utf8) ?? "")")
                    completion(.success(()))
                    return
                }
                print("IntensoAPIClient: Register uncaught error")
                completion(.failure(.serverError("Unsure what happened here.")))
                return
            } catch {
                print("IntensoAPIClient: Register caught error:", error.localizedDescription)
                completion(.failure(.decodingError))
                return
            }
        }.resume()
    }
    
}
