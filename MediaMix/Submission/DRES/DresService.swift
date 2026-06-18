//
//  DresService.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import DresSwiftClient
import Foundation

@MainActor
final class DresService: ObservableObject {
    static let shared = DresService()

    @Published private(set) var isConnected = false
    @Published private(set) var evaluations: [EvaluationData] = []
    @Published var currentEvaluation: String?

    private var client: DresClient?

    private init() {}

    // MARK: - Connect using your JSON config

    func connect() async throws {
        let cfg = ConfigurationManager.shared.config.dres

        let newClient = try await DresClient(
            url: URL(string: cfg.apiBaseURL)!,
            username: cfg.username,
            password: cfg.password
        )

        // Connection test
        let evaluations = try await newClient.listEvaluations()

        // If this line is reached, auth worked
        client = newClient
        self.evaluations = evaluations.map {
            EvaluationData(name: $0.name, id: $0.id)
        }
        currentEvaluation = self.evaluations.first?.id
        isConnected = true
    }

    // MARK: - Logout

    func logout() {
        client = nil
        isConnected = false
        evaluations = []
        currentEvaluation = nil
    }

    // MARK: - Evaluations

    func updateEvaluations() async throws {
        guard let client else { throw DresError.notConnected }

        let results = try await client.listEvaluations()
        evaluations = results.map { EvaluationData(name: $0.name, id: $0.id) }

        if currentEvaluation == nil {
            currentEvaluation = evaluations.first?.id
        }
    }

    private func requireEvaluation() throws -> String {
        guard let eval = currentEvaluation else {
            throw DresError.noEvaluation
        }
        return eval
    }

    // MARK: - Submit text

    func submitText(_ text: String) async throws -> (Bool, String) {
        guard let client else { throw DresError.notConnected }
        let eval = try requireEvaluation()

        let result = try await client.submitText(
            evaluationId: eval,
            text: text
        )

        return (result.status, result.description)
    }

    private func normalizeItemId(database: String, objectId: String) -> String {
        if database.lowercased() == "lhe" { return objectId }
        if objectId.count > 2 { return String(objectId.dropFirst(2)) }
        return objectId
    }

    // MARK: - Submit video frame

    func submitItem(
        database _: String,
        objectId: String,
        start: Int64,
        end: Int64
    ) async throws -> (Bool, String) {
        guard let client else { throw DresError.notConnected }
        let eval = try requireEvaluation()

        // let normalized = normalizeItemId(database: database, objectId: objectId)

        let result = try await client.submit(
            evaluationId: eval,
            item: objectId,
            start: start,
            end: end
        )

        return (result.status, result.description)
    }

    // MARK: - Logging helpers

    private func nowMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    /// Convenience typealias to keep call-sites readable
    typealias LogEventTuple = (
        timestamp: Int64, category: String, _type: String, value: String
    )

    /// Logs a query state (events only) to DRES.
    /// According to the API, QueryEventLog is essentially { timestamp, events }. :contentReference[oaicite:2]{index=2}
    func logQuery(
        timestamp: Int64? = nil,
        events: [LogEventTuple]
    ) async throws -> Bool {
        guard let client else { throw DresError.notConnected }
        let eval = try requireEvaluation()

        return try await client.logQuery(
            evaluationId: eval,
            timestamp: timestamp ?? nowMillis(),
            events: events
        )
    }

    /// Logs a result set to DRES. This is the recommended VBS-style log: query state + top results. :contentReference[oaicite:3]{index=3}
    func logResults(
        timestamp: Int64? = nil,
        sortType: String,
        resultSetAvailability: String,
        collectionName _: String?,
        results: [(mediaItem: String, start: Int64, end: Int64)],
        events: [LogEventTuple]
    ) async throws -> Bool {
        guard let client else { throw DresError.notConnected }
        let eval = try requireEvaluation()

        return try await client.logResults(
            evaluationId: eval,
            timestamp: timestamp ?? nowMillis(),
            sortType: sortType,
            resultSetAvailability: resultSetAvailability,
            results: results,
            events: events
        )
    }
}

struct EvaluationData: Hashable {
    let name: String
    let id: String
}

enum DresError: Error {
    case notConnected
    case noEvaluation
}
