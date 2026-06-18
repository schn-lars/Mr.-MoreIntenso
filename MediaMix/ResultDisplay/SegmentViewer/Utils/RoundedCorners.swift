//
//  RoundedCorners.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import SwiftUI

struct RoundedCorners: Shape {
    var radius: CGFloat = 15
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
