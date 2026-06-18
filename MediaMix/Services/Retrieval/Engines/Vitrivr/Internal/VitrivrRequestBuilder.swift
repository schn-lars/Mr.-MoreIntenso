//
//  VitrivrRequestBuilder.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import Foundation
import OpenAPIClient

enum VitrivrRequestBuilder {
    static func makeTextQueryRequest(
        schema: String,
        prompt: String,
        limit: Int,
        firstOpName: String,
        firstOpField: String
    ) -> URLRequest {
        let url = URL(string: "\(OpenAPIClientAPI.basePath)/api/\(schema)/query")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "accept")

        let safePrompt = jsonEscape(prompt)

        let json = """
        {
          "inputs": { "txt": { "type": "TEXT", "data": "\(safePrompt)" } },
          "operations": {
            "\(firstOpName)": { "field": "\(firstOpField)", "inputs": { "txt": "txt" }, "parameters": { "limit": "\(limit)" } },
            "relations": { "factory": "RelationExpander", "inputs": { "in": "\(firstOpName)" }, "parameters": { "outgoing": "partOf" } },
            "aggregator": { "factory": "ScoreAggregator", "inputs": { "in": "relations" } },
            "timelookup": { "factory": "FieldLookup", "inputs": { "in": "aggregator" }, "parameters": { "field": "time", "keys": "start, end" } },
            "clipveclookup": { "factory": "FieldLookup", "inputs": { "in": "timelookup" }, "parameters": { "field": "clip", "keys": "vector" } },
            "filelookup": { "factory": "ObjectFieldLookup", "inputs": { "in": "clipveclookup" }, "parameters": { "field": "file", "predicates": "partOf", "keys": "path" } }
          },
          "output": "filelookup"
        }
        """
        req.httpBody = json.data(using: .utf8)
        return req
    }

    static func makeVectorQueryRequest(
        schema: String,
        vector: [Float],
        limit: Int
    ) -> URLRequest {
        let url = URL(string: "\(OpenAPIClientAPI.basePath)/api/\(schema)/query")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "accept")

        let vecJson = vector.map(String.init(describing:)).joined(separator: ", ")

        let json = """
        {
          "inputs": { "txt": { "type": "FLOATVECTOR", "data": [\(vecJson)] } },
          "operations": {
            "clip": { "field": "clip", "inputs": { "txt": "txt" }, "parameters": { "limit": "\(limit)" } },
            "relations":  { "factory": "RelationExpander", "inputs": { "in": "clip" }, "parameters": { "outgoing": "partOf" } },
            "aggregator": { "factory": "ScoreAggregator", "inputs": { "in": "relations" } },
            "timelookup": { "factory": "FieldLookup", "inputs": { "in": "aggregator" }, "parameters": { "field": "time", "keys": "start, end" } },
            "clipveclookup": { "factory": "FieldLookup", "inputs": { "in": "timelookup" }, "parameters": { "field": "clip", "keys": "vector" } },
            "filelookup": { "factory": "ObjectFieldLookup", "inputs": { "in": "clipveclookup" }, "parameters": { "field": "file", "predicates": "partOf", "keys": "path" } }
          },
          "output": "filelookup"
        }
        """
        req.httpBody = json.data(using: .utf8)
        return req
    }

    static func jsonEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
