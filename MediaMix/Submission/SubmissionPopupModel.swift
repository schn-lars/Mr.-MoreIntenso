//
//  SubmissionPopupModel.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import SwiftUI

@MainActor
final class SubmissionPopupModel: ObservableObject {
    static let shared = SubmissionPopupModel()

    @Published var message: String = ""
    @Published var isSuccess: Bool = true
    @Published var nonce = UUID()

    func show(success: Bool, message: String) {
        isSuccess = success
        self.message = message
        nonce = UUID()
    }
}
