//
//  AsyncLimiter.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import Foundation

actor AsyncLimiter {
    private let limit: Int
    private var active = 0

    init(_ limit: Int) {
        self.limit = max(1, limit)
    }

    func acquire() async {
        while active >= limit {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        active += 1
    }

    func release() async {
        active = max(0, active - 1)
    }
}
