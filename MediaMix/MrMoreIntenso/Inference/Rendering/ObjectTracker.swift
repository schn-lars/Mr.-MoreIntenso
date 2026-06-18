import Foundation

class ObjectTracker {
    private let dementiaValue = 3.0
    
    var trackedObjects: ProcessedObservations = ProcessedObservations(trackedObservations: [], extrinsics: nil)
    
    func updateTrackedObjects(with observations: ResultObservations) {
        var newTracked: [TrackedObject] = []
        var usedObjectIDs: Set<UUID> = []
        for observation in observations.observations {
            if let det = observation.base as? Detection {
                let (bestMatch, bestIOU) = findBestMatch(
                    detection: det,
                    excluding: usedObjectIDs
                )
                
                /// we already have an existing object
                if let match = bestMatch, bestIOU > 0.5 {
                    let updated = TrackedObject(
                        id: match.id,
                        label: det.label,
                        bbox: det.bbox,
                        lastSeen: .now,
                        confidence: match.confidence,
                        image: match.image,
                        mask: nil
                    )
                    newTracked.append(updated)
                    usedObjectIDs.insert(match.id)
                } else {
                    let newID = UUID()
                    let newObj = TrackedObject(
                        id: newID,
                        label: det.label,
                        bbox: det.bbox,
                        lastSeen: .now,
                        confidence: det.confidence,
                        image: observation.image,
                        mask: nil
                    )
                    newTracked.append(newObj)
                }
            } else if let seg = observation.base as? Segmentation {
                let (bestMatch, bestIOU) = findBestMatch(
                    segmentation: seg,
                    excluding: usedObjectIDs
                )
                
                /// we already have an existing object
                if let match = bestMatch, bestIOU > 0.3 {
                    let updated = TrackedObject(
                        id: match.id,
                        label: seg.label,
                        bbox: seg.bbox,
                        lastSeen: .now,
                        confidence: match.confidence,
                        image: match.image,
                        mask: seg.mask
                    )
                    newTracked.append(updated)
                    usedObjectIDs.insert(match.id)
                } else {
                    let newID = UUID()
                    let newObj = TrackedObject(
                        id: newID,
                        label: seg.label,
                        bbox: seg.bbox,
                        lastSeen: .now,
                        confidence: seg.confidence,
                        image: observation.image,
                        mask: seg.mask
                    )
                    newTracked.append(newObj)
                }
            }
        }
        
        /// also, we want to keep old (not older than .5 seconds) objects that have not been detected inside new detections
        /// this should avoid flickering essentially
        let now = Date()
        for obj in trackedObjects.trackedObservations {
            if !newTracked.contains(where: { $0.id == obj.id}) && now.timeIntervalSince(obj.lastSeen) < dementiaValue {
                newTracked.append(obj)
            }
        }
        trackedObjects = ProcessedObservations(
            trackedObservations: newTracked,
            extrinsics: observations.extrinsics
        )
        //print("ObjectTracker: now tracking \(trackedObjects.count) objects")
    }
    
    private func findBestMatch(
        detection: Detection,
        excluding used: Set<UUID>
    ) -> (TrackedObject?, Float) {

        var best: TrackedObject? = nil
        var bestIOU: Float = 0

        for obj in trackedObjects.trackedObservations {
            if used.contains(obj.id) { continue }
            if obj.label != detection.label { continue; }

            let iouScore = iou(bbox1: detection.bbox, bbox2: obj.bbox)

            if iouScore > bestIOU {
                best = obj
                bestIOU = iouScore
            }
        }
        return (best, bestIOU)
    }
    
    private func findBestMatch(
        segmentation: Segmentation,
        excluding used: Set<UUID>
    ) -> (TrackedObject?, Float) {

        var best: TrackedObject? = nil
        var bestIOU: Float = 0

        for obj in trackedObjects.trackedObservations {
            if used.contains(obj.id) { continue }
            if obj.label != segmentation.label { continue; }
            
            let iouScore = iou(bbox1: segmentation.bbox, bbox2: obj.bbox)

            if iouScore > bestIOU {
                best = obj
                bestIOU = iouScore
            }
        }
        return (best, bestIOU)
    }
    
    private func iou(bbox1: BoundingBox, bbox2: BoundingBox) -> Float {
        // https://www.v7labs.com/blog/intersection-over-union-guide
        let a_inter = max(bbox1.x, bbox2.x)
        let b_inter = max(bbox1.y, bbox2.y)
        let c_inter = min(bbox1.width + bbox1.x, bbox2.width + bbox2.x)
        let d_inter = min(bbox1.height + bbox1.y, bbox2.height + bbox2.y)
        
        if c_inter < a_inter || d_inter < b_inter { return 0.0 }
        
        let intersection_area = (c_inter - a_inter) * (d_inter - b_inter)
        let area_one = bbox1.width * bbox1.height
        let area_two = bbox2.width * bbox2.height
        let union_area = area_one + area_two - intersection_area
        
        return intersection_area / union_area
    }
}
