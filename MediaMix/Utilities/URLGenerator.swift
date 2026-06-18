//
//  URLGenerator.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import Foundation

class URLGenerator {
    static func generateImageURL(
        database: String,
        objectId: String,
        segmentId: String
    ) -> URL? {
        switch ConfigurationManager.shared.retrievalEngine {
        case .ferelight:
            return ferelightImageURL(
                database: database,
                objectId: objectId,
                segmentId: segmentId
            )
        case .vitrivr:
            return vitrivrImageURL(database: database, segmentId: segmentId)
        }
    }

    static func generateVideoURL(database: String, objectId: String) -> URL? {
        switch ConfigurationManager.shared.retrievalEngine {
        case .ferelight:
            return ferelightVideoURL(database: database, objectId: objectId)
        case .vitrivr:
            return vitrivrVideoURL(database: database, objectId: objectId)
        }
    }

    // MARK: - FereLight (existing behaviour)

    private static func ferelightImageURL(
        database: String,
        objectId: String,
        segmentId: String
    ) -> URL? {
        let base = ConfigurationManager.shared.vitrivrDataURL
        let prefix = ConfigurationManager.shared.vitrivrResultsPath
        let root = prefix.isEmpty ? "" : "\(prefix)/"

        let path: String

        switch database {
        case "mvk":
            path = "\(root)ferelight/\(database)/\(objectId)/\(segmentId).jpg"
        case "lhe":
            path = "\(root)ferelight/\(database)/\(segmentId).jpg"
        case "v3c":
            path =
                "\(root)ferelight/\(database)/thumbnails/\(objectId)/\(segmentId).jpg"
        default:
            path = "\(root)\(database)/\(objectId)jpg"
        }
        return URL(string: base + path)
    }

    private static func ferelightVideoURL(database: String, objectId: String)
        -> URL?
    {
        let base = ConfigurationManager.shared.vitrivrDataURL
        let prefix = ConfigurationManager.shared.vitrivrResultsPath
        let root = prefix.isEmpty ? "" : "\(prefix)/"

        let db = database.uppercased()
        let path: String
        switch db {
        case "MVK":
            let trimmedObjectId = String(objectId.dropFirst(2))
            path = "\(root)\(db)/videos/\(trimmedObjectId).mp4"
        case "LHE":
            path = "\(root)\(db)/videos/\(objectId).mp4"
        case "V3C":
            let trimmedObjectId = String(objectId.dropFirst(2))
            path = "\(root)\(db)/videos/\(trimmedObjectId).mp4"
        default:
            path = "\(root)\(db)/videos/\(objectId).mp4"
        }
        return URL(string: base + path)
    }

    // MARK: - vitrivr-engine (new behaviour)

    private static func vitrivrImageURL(database: String, segmentId: String)
        -> URL?
    {
        let base = ConfigurationManager.shared.vitrivrDataURL
        let prefix = ConfigurationManager.shared.vitrivrResultsPath
        let root = prefix.isEmpty ? "" : "\(prefix)/"

        let db = database.uppercased()
        let shard = String(segmentId.prefix(2))

        let path = "\(root)\(db)/thumbnails/shards/\(shard)/\(segmentId).jpg"
        return URL(string: base + path)
    }

    private static func vitrivrVideoURL(database: String, objectId: String)
        -> URL?
    {
        let base = ConfigurationManager.shared.vitrivrDataURL
        let prefix = ConfigurationManager.shared.vitrivrResultsPath
        let root = prefix.isEmpty ? "" : "\(prefix)/"

        let db = database.uppercased()
        let path = "\(root)\(db)/videos/\(objectId).mp4"
        return URL(string: base + path)
    }
}
