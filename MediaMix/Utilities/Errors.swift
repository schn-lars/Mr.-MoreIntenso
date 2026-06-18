import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case decodingError
    case serverError(String)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return error.localizedDescription
        case .decodingError:
            return "Failed to decode server response"
        case .serverError(let message):
            return message
        case .unauthorized:
            return "Invalid username or password"
        }
    }
}
