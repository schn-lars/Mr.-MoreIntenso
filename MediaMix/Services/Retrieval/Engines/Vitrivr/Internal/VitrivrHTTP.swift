//
//  VitrivrHTTP.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import Foundation

enum VitrivrHTTP {
    static func perform(_ req: URLRequest) async throws -> VitrivrQueryResult {
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if !(200 ..< 300).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(
                domain: "Vitrivr",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: text]
            )
        }

        return try JSONDecoder().decode(VitrivrQueryResult.self, from: data)
    }
}
