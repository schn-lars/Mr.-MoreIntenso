//
//  DetailedSegment.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import SwiftUI

/// Represents a segment of a multimedia object retrieved from the system.
/// Each segment belongs to an object and has timing information.
struct DetailedSegment: Identifiable {
    var segmentId: String

    /// The relevance score of the segment (higher = more relevant).
    let score: Double

    /// The object (video/image) that this segment belongs to.
    let objectId: String

    /// The segment's position within the object (e.g., frame or clip number).
    let segmentNumber: Int

    /// The start time of the segment, in milliseconds (relative to the object).
    let segmentStart: Int

    /// The end time of the segment, in milliseconds (relative to the object).
    let segmentEnd: Int

    /// The absolute start time of the segment, in seconds (e.g., in a full dataset timeline).
    let segmentStartAbs: Double

    /// The absolute end time of the segment, in seconds.
    let segmentEndAbs: Double

    var clipVector: [Double]?

    /// The collection or dataset this segment belongs to.
    let collection: String

    /// Conforms to `Identifiable`, using `segmentId` as the unique identifier.
    var id: String {
        segmentId
    }
}
