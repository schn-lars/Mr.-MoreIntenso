import SwiftUI

struct Token: Decodable {
    let access_token: String
    let token_type: String
}

struct WSPromptMessage: Codable {
    let type: String
    let prompt: [String]?
}

struct WSSwitchModelMessage: Codable {
    let type: String
    let model: String
    let task: String
}

/// technically the same thing as WSSwitchModelMessage
struct WSInitModelMessage: Codable {
    let type: String
    let model: String
    let task: String
}

struct IntensoVLMResponse {
    let owner: String
    let object: String
    let confidence: Float
    let image: CGImage? // was not using this. Maybe this was a mistake making optional
    let content: [String : [String : IntensoContent]]
}

enum IntensoContent: Decodable {
    case text(String)
    case list([String])
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .text(string)
                return
            }
            
            if let list = try? container.decode([String].self) {
                self = .list(list)
                return
            }
            
            throw DecodingError.typeMismatch(
                IntensoContent.self,
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported IntensoContent type"
                )
            )
    }
}

enum SelectedTopic: Equatable {
    case scope(String)
    case topic(scope: String, topic: String)
}

struct ProximityResponse: Decodable {
    let rows: [SharedObject]
}

struct SharedObject: Decodable, Identifiable {
    let id: String
    let owner: String
    let obj: String
    let confidence: Float
    let coord_y: Double
    let coord_x: Double
    let json: [String : [String : IntensoContent]]
    let image_url: String
}

/**
    Since [String : Any] cannot be implementing Decodable interface, we need to add a helper to bypass this issue
 */
struct AnyDecodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyDecodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyDecodable].self) {
            value = dict.mapValues(\.value)
        } else {
            value = NSNull()
        }
    }
}
