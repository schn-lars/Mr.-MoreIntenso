//
//  SphereDescriptor.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

struct SphereDescriptor: Identifiable, Equatable {
    let id: Int // sphere number
    let database: String
    let query: [SphereQueryItem]
    var label: String {
        var s = "Dataset: \(database)"
        for item in query {
            s += "\n\(item.text), \(item.type)"
        }
        return s
    }
}
