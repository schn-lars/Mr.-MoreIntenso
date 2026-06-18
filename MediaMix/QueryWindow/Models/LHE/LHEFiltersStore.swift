//
//  LHEFiltersStore.swift
//  MediaMix
//
//  Created by Rahel Arnold
//
import Foundation

final class LHEFiltersStore: ObservableObject {
    @Published var bundle: LHEFiltersBundle?
    @Published var categoryByVideoId: [String: String] = [:]

    func loadFromBundle(named fileName: String = "LHE_filters") {
        guard
            let url = Bundle.main.url(
                forResource: fileName,
                withExtension: "json"
            )
        else {
            print("Missing \(fileName).json in app bundle")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(
                LHEFiltersBundle.self,
                from: data
            )

            DispatchQueue.main.async {
                self.bundle = decoded
                self.categoryByVideoId = Dictionary(
                    uniqueKeysWithValues: decoded.videos.map {
                        ($0.video_id, $0.category)
                    }
                )
            }
        } catch {
            print("Failed to load LHE filters JSON: \(error)")
        }
    }
}
