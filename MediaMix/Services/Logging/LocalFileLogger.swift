//
//  LocalFileLogger.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import Foundation

final class LocalFileLogger {
    static let shared = LocalFileLogger()

    private let queue = DispatchQueue(label: "LocalFileLogger.queue", qos: .utility)
    private let fileURL: URL

    private init(filename: String = "interactions.log") {
        let dir = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!

        fileURL = dir.appendingPathComponent(filename)

        print("Logfile (sandbox):", fileURL)

        ensureFileExists()
    }

    private func ensureFileExists() {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
        }
    }

    /// Public: append one line (newline added automatically)
    func logLine(_ line: String) {
        queue.async { [fileURL] in
            let stamped = line.hasSuffix("\n") ? line : (line + "\n")
            guard let data = stamped.data(using: .utf8) else { return }

            do {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    let handle = try FileHandle(forWritingTo: fileURL)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } else {
                    try data.write(to: fileURL, options: .atomic)
                }
            } catch {
                print("LocalFileLogger error:", error)
            }
        }
    }

    /// Helper: where the file is (useful for debugging/export)
    func getLogFileURL() -> URL {
        fileURL
    }
}

func logUI(
    engine: String,
    db: String,
    type: String,
    value: String
) {
    let ts = Int64(Date().timeIntervalSince1970 * 1000)

    let safeValue = value
        .replacingOccurrences(of: "\t", with: " ")
        .replacingOccurrences(of: "\n", with: "\\n")

    let line = [
        String(ts),
        "UI",
        engine,
        db,
        "INTERACTION",
        type,
        safeValue,
    ].joined(separator: "\t")

    LocalFileLogger.shared.logLine(line)
}
