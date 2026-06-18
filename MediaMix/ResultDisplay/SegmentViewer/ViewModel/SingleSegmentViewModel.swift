//
//  SingleSegmentViewModel.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import AVFoundation
import AVKit
import Foundation

@MainActor
final class SingleSegmentViewModel: ObservableObject {
    // MARK: - UI state

    @Published var totalOffset: CGSize = .zero
    @Published var currentDragOffset: CGSize = .zero

    @Published var player: AVPlayer? = nil
    @Published var isSubmitting: Bool = false
    @Published var answerText: String = ""

    private let segment: DetailedSegment
    private var startTime: Double = 0.0

    init(segment: DetailedSegment) {
        self.segment = segment
    }

    // MARK: - Dragging

    func updateDrag(current: CGSize) {
        currentDragOffset = current
    }

    func commitDrag(translation: CGSize) {
        totalOffset.width += translation.width
        totalOffset.height += translation.height
        currentDragOffset = .zero
    }

    // MARK: - Player

    func setupPlayer(with url: URL, engine: RetrievalEngine) {
        player = AVPlayer(url: url)
        startTime = segment.segmentStartAbs
        seekToStartTime()
        player?.play()
        logPlayerInitialized(engine: engine)
    }

    private func seekToStartTime() {
        guard let player else { return }
        let time = CMTime(seconds: startTime, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: - Similarity (delegated)

    func similarity(
        dres _: DresService,
        engine _: RetrievalEngine,
        factory: RetrievalClientFactory,
        appSettings: AppSettings
    ) async throws -> [RetrievalItem] {
        // optional UI logging here (oder im View wie bisher)
        return try await SimilaritySearchRunner.run(
            segment: segment,
            database: segment.collection,
            factory: factory,
            appSettings: appSettings
        )
    }

    func similarityAtCurrentTime(
        dres _: DresService,
        engine: RetrievalEngine,
        factory: RetrievalClientFactory,
        appSettings: AppSettings
    ) async throws -> [RetrievalItem] {
        guard engine == .ferelight else { return [] }
        guard let player else { return [] }

        let t = player.currentTime().seconds

        return try await SimilaritySearchRunner.runAtTime(
            segment: segment,
            database: segment.collection,
            objectId: segment.objectId,
            timestampSeconds: t,
            factory: factory,
            appSettings: appSettings
        )
    }

    // MARK: - Submissions (unverändert)

    struct SubmitOutcome {
        let ok: Bool
        let message: String
    }

    func submitFrame(dres: DresService, engine: RetrievalEngine) async -> SubmitOutcome {
        isSubmitting = true
        defer { isSubmitting = false }

        guard let player else {
            return .init(ok: false, message: "Player is not initialized")
        }

        let tMs = Int64(player.currentTime().seconds * 1000)

        let submittedObjectId: String
        switch engine {
        case .ferelight:
            switch segment.collection {
            case "v3c", "mvk":
                submittedObjectId = String(segment.objectId.dropFirst(2))
            case "lhe":
                submittedObjectId = segment.objectId
            default:
                return .init(ok: false, message: "Unsupported collection")
            }
        case .vitrivr:
            submittedObjectId = segment.objectId
        }

        logSubmit(
            dres: dres,
            engine: engine,
            database: segment.collection,
            type: "submitAtTimeStart",
            value: "segmentId=\(segment.segmentId);objectId=\(submittedObjectId);timeMs=\(tMs)"
        )

        do {
            let (ok, msg) = try await dres.submitItem(
                database: segment.collection,
                objectId: submittedObjectId,
                start: tMs,
                end: tMs
            )

            let safeMsg = msg
                .replacingOccurrences(of: "\t", with: " ")
                .replacingOccurrences(of: "\n", with: "\\n")

            logSubmit(
                dres: dres,
                engine: engine,
                database: segment.collection,
                type: "submitAtTimeResult",
                value: "ok=\(ok);msg=\(safeMsg.isEmpty ? "nil" : safeMsg);segmentId=\(segment.segmentId);objectId=\(submittedObjectId);timeMs=\(tMs)"
            )

            return .init(ok: ok, message: msg)
        } catch {
            let err = error.localizedDescription
                .replacingOccurrences(of: "\t", with: " ")
                .replacingOccurrences(of: "\n", with: "\\n")

            logSubmit(
                dres: dres,
                engine: engine,
                database: segment.collection,
                type: "submitAtTimeError",
                value: "segmentId=\(segment.segmentId);objectId=\(submittedObjectId);timeMs=\(tMs);error=\(err)"
            )
            return .init(ok: false, message: "Submission failed: \(error.localizedDescription)")
        }
    }

    func submitAnswer(dres: DresService, engine: RetrievalEngine) async -> SubmitOutcome {
        isSubmitting = true
        defer { isSubmitting = false }

        logSubmit(
            dres: dres,
            engine: engine,
            database: segment.collection,
            type: "submitAnswerStart",
            value: "len=\(answerText.count)"
        )

        do {
            let (ok, msg) = try await dres.submitText(answerText)

            let safeMsg = msg
                .replacingOccurrences(of: "\t", with: " ")
                .replacingOccurrences(of: "\n", with: "\\n")

            logSubmit(
                dres: dres,
                engine: engine,
                database: segment.collection,
                type: "submitAnswerResult",
                value: "ok=\(ok);msg=\(safeMsg.isEmpty ? "nil" : safeMsg);len=\(answerText.count)"
            )

            if ok { answerText = "" }
            return .init(ok: ok, message: msg)
        } catch {
            let err = error.localizedDescription
                .replacingOccurrences(of: "\t", with: " ")
                .replacingOccurrences(of: "\n", with: "\\n")

            logSubmit(
                dres: dres,
                engine: engine,
                database: segment.collection,
                type: "submitAnswerError",
                value: "len=\(answerText.count);error=\(err)"
            )

            return .init(ok: false, message: "Answer submission failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Logging (wie bei dir)

    func logInteraction(
        dres: DresService,
        engine: RetrievalEngine,
        database: String,
        action: String,
        type: String,
        value: String
    ) {
        let ts = Int64(Date().timeIntervalSince1970 * 1000)

        let line = [
            String(ts),
            action,
            engine.rawValue,
            database,
            "INTERACTION",
            type,
            value,
        ].joined(separator: "\t")

        LocalFileLogger.shared.logLine(line)

        Task {
            do {
                _ = try await dres.logQuery(
                    timestamp: ts,
                    events: [(timestamp: ts, category: action, _type: type, value: value)]
                )
            } catch {}
        }
    }

    private func logPlayerInitialized(engine: RetrievalEngine) {
        let startMs = Int64(segment.segmentStartAbs * 1000)
        let endMs = Int64(segment.segmentEndAbs * 1000)

        let objectId: String = {
            switch engine {
            case .ferelight:
                return segment.objectId
            case .vitrivr:
                return stripSuffixAfterLastUnderscore(segment.objectId)
            }
        }()

        let value =
            "objectId=\(objectId);" +
            "segmentId=\(segment.segmentId);" +
            "startMs=\(startMs);" +
            "endMs=\(endMs)"

        logInteraction(
            dres: DresService.shared,
            engine: engine,
            database: segment.collection,
            action: "BROWSING",
            type: "videoPlayerInit",
            value: value
        )
    }

    private func logSubmit(
        dres: DresService,
        engine: RetrievalEngine,
        database: String,
        type: String,
        value: String
    ) {
        let ts = Int64(Date().timeIntervalSince1970 * 1000)

        let line = [
            String(ts),
            "SUBMIT",
            engine.rawValue,
            database,
            "INTERACTION",
            type,
            value,
        ].joined(separator: "\t")

        LocalFileLogger.shared.logLine(line)

        Task {
            do {
                _ = try await dres.logQuery(
                    timestamp: ts,
                    events: [(timestamp: ts, category: "SUBMIT", _type: type, value: value)]
                )
            } catch {}
        }
    }

    // MARK: - Utils

    private func stripSuffixAfterLastUnderscore(_ s: String) -> String {
        guard let idx = s.lastIndex(of: "_") else { return s }
        return String(s[..<idx])
    }
}
