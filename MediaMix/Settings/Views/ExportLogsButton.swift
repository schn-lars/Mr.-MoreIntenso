//
//  ExportLogsButton.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import SwiftUI
import UniformTypeIdentifiers

struct ExportLogsButton: View {
    @State private var showExporter = false

    var body: some View {
        Button("Export log…") {
            showExporter = true
        }
        .fileExporter(
            isPresented: $showExporter,
            document: LogFileDocument(url: LocalFileLogger.shared.getLogFileURL()),
            contentType: .plainText,
            defaultFilename: "interactions"
        ) { result in
            if case let .failure(error) = result {
                print("Export failed:", error)
            }
        }
    }
}

struct LogFileDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.plainText]
    }

    let url: URL

    init(url: URL) {
        self.url = url
    }

    init(configuration _: ReadConfiguration) throws {
        url = URL(fileURLWithPath: "/")
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        let data = try Data(contentsOf: url)
        return .init(regularFileWithContents: data)
    }
}
