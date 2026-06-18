//
//  QueryLogging.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import Foundation

enum QueryLogging {
    typealias LogEvent = DresService.LogEventTuple

    @inline(__always)
    static func nowMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    static func logQueryToDresAndLocal(
        timestamp: Int64,
        engine: RetrievalEngine,
        database: String,
        events: [LogEvent]
    ) {
        let metaPrefix = "engine=\(engine.displayName);db=\(database);"

        // 1) DRES enriched
        let enriched: [LogEvent] = events.map { e in
            (timestamp: e.timestamp, category: e.category, _type: e._type, value: metaPrefix + e.value)
        }
        logQueryNonBlocking(timestamp: timestamp, events: enriched)

        // 2) local file (raw)
        for e in events {
            let line = [
                String(e.timestamp),
                "QUERY",
                engine.rawValue,
                database,
                e.category,
                e._type,
                e.value,
            ].joined(separator: "\t")

            LocalFileLogger.shared.logLine(line)
        }
    }

    static func logQueryNonBlocking(timestamp: Int64, events: [LogEvent]) {
        Task {
            do { _ = try await DresService.shared.logQuery(timestamp: timestamp, events: events) }
            catch { /* ignored */ }
        }
    }

    static func logResultsLocal(
        timestamp: Int64,
        engine: RetrievalEngine,
        database: String,
        results: [RetrievalItem]
    ) {
        for (rank, r) in results.enumerated() {
            let line = [
                String(timestamp),
                "RESULT",
                engine.rawValue,
                database,
                String(rank),
                r.id,
                String(format: "%.6f", r.score),
                r.objectId ?? "",
            ].joined(separator: "\t")

            LocalFileLogger.shared.logLine(line)
        }
    }

    static func logTextQueryNonBlocking(timestamp: Int64, type: String, value: String) {
        logQueryNonBlocking(
            timestamp: timestamp,
            events: [(timestamp: timestamp, category: "TEXT", _type: type, value: value)]
        )
    }
}
