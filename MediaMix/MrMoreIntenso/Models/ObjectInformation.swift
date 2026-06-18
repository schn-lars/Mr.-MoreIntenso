/**
    This model should no longer be static and in need to be extended using fixed and new objects.
    Rather than that, the object's information should be saved using JSON representation of itself.
 */

import Foundation
import SwiftUI
import CoreLocation
import MapKit
import ShazamKit
import WeatherKit

class ObjectInformation: ObservableObject, Identifiable {
    
    static func < (lhs: ObjectInformation, rhs: ObjectInformation) -> Bool {
        // Favourite objects should come first
        if lhs.favourite != rhs.favourite {
            return !lhs.favourite
        }
        // Both are or are not favourized, then sort by lastSpotted
        return lhs.lastSpotted < rhs.lastSpotted
    }
    
    var id: UUID = UUID()
    @Published var owner: String
    @Published var confidence: Float = 0.0
    @Published var coordinates: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: CLLocationDegrees(), longitude: CLLocationDegrees())
    @Published var object: String = "Unknown"
    @Published var image: UIImage? = nil
    @Published var lastSpotted: Int64 = Int64(NSDate().timeIntervalSince1970)
    @Published var shared: Bool = false
    @Published var favourite: Bool = false
    @Published var json: String?
    
    var description: String {
        return "ObjectInformation(object: \(object), favourite: \(favourite), lastSpotted: \(lastSpotted))"
    }
    
    init(owner: String,
         confidence: Float,
         object name: String,
         croppedImage image: UIImage,
         location: CLLocation? = nil
    ) {
        print("Initializing ObjectInformation... with location? :\(location != nil)")
        self.object = name
        self.confidence = confidence
        self.image = image
        if let location = location {
            self.coordinates = location.coordinate
        }
        self.owner = owner
    }
    
    func addObjectDescription(new payload: Data, completion: @escaping () -> Void) {
        do {
            let stringPlaylod = try JSONSerialization.jsonObject(with: payload) as? String
            DispatchQueue.main.async {
                self.json = stringPlaylod
                print("addObjectDescription: added description")
                completion()
            }
        } catch {
            print("addObjectDescription: ERROR - invalid JSON \(error.localizedDescription)")
            completion()
            return
        }
    }
    
    func setFavorite() {
        self.favourite = !self.favourite
    }
}
