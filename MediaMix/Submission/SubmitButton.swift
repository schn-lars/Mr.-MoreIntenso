//
//  SubmitButton.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import SwiftUI

struct SubmitButton: View {
    let segment: DetailedSegment

    @StateObject private var dres = DresService.shared
    @State private var isSubmitting = false
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.openWindow) private var openWindow

    /// Use the same shared popup model as SingleSegmentView
    @StateObject private var popup = SubmissionPopupModel.shared

    var body: some View {
        Button {
            logUI(
                engine: appSettings.retrievalEngine.rawValue,
                db: segment.collection,
                type: "tapSubmitFrame",
                value: "segmentId=\(segment.segmentId);objectId=\(segment.objectId)"
            )

            Task { await submit() }
        } label: {
            if isSubmitting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "paperplane.fill")
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(!dres.isConnected || isSubmitting)
        .help(
            dres.isConnected
                ? "Submit to DRES"
                : "Connect to DRES first in Settings"
        )
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let startMs = Int64(segment.segmentStartAbs * 1000)
            let endMs = Int64(segment.segmentEndAbs * 1000)

            let objectIdToSubmit: String

            switch appSettings.retrievalEngine {
            case .ferelight:
                switch segment.collection {
                case "v3c", "mvk":
                    objectIdToSubmit = String(segment.objectId.dropFirst(2))
                case "lhe":
                    objectIdToSubmit = segment.objectId
                default:
                    return
                }
            case .vitrivr:
                objectIdToSubmit = segment.objectId
            }
            print("objectIdToSubmit ", objectIdToSubmit)
            print("start ", startMs)
            let (ok, msg) = try await dres.submitItem(
                database: segment.collection,
                objectId: objectIdToSubmit,
                start: startMs,
                end: endMs
            )

            await MainActor.run {
                popup.show(
                    success: ok,
                    message: msg.isEmpty
                        ? (ok ? "Submission sent." : "Submission failed.") : msg
                )
                openWindow(id: "submissionStatus")
            }

        } catch {
            await MainActor.run {
                popup.show(
                    success: false,
                    message: "Submission failed: \(error.localizedDescription)"
                )
                openWindow(id: "submissionStatus")
            }
        }
    }
}
