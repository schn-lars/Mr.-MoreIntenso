//
//  InteractionLogger.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import Foundation

/// Small logger that writes TSV lines locally and (optionally) forwards to DRES.
/// Designed so failures never break UX.
struct InteractionLogger {
    typealias LogEvent = DresService.LogEventTuple

    let dres: DresService

    func log(
        action: String, // e.g. "BROWSING", "SUBMIT", "UI"
        engine: String, // retrieval engine raw value
        database: String,
        type: String, // e.g. "videoPlayerInit", "tapSubmitFrame"
        value: String
    ) {
        let ts = nowMillis()

        // Local TSV:
        // ts   action   engine   db   category   type   value
        let line = [
            String(ts),
            action,
            engine,
            database,
            "INTERACTION",
            type,
            value,
        ].joined(separator: "\t")

        LocalFileLogger.shared.logLine(line)

        // Optional: also send to DRES (non-blocking)
        Task {
            do {
                _ = try await dres.logQuery(
                    timestamp: ts,
                    events: [(timestamp: ts, category: action, _type: type, value: value)]
                )
            } catch {
                // never break UX
            }
        }
    }

    private func nowMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
