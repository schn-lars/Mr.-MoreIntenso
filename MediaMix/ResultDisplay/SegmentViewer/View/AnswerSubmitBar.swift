//
//  AnswerSubmitBar.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import SwiftUI

struct AnswerSubmitBar: View {
    @Binding var answerText: String
    let isSubmitting: Bool
    let onSubmit: () -> Void

    var body: some View {
        HStack {
            TextField("Enter your answer here", text: $answerText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            Button("Submit Answer", action: onSubmit)
                .disabled(answerText.isEmpty || isSubmitting)
                .padding()
        }
    }
}
