import CoreLocation
import UIKit

@MainActor
class LocationManager: NSObject, CLLocationManagerDelegate, ObservableObject {
    private let manager = CLLocationManager()
    @Published var coordinate: CLLocationCoordinate2D?
    private var lastTriggeredCoordinate: CLLocationCoordinate2D? // used for RootImmeriveView to call for shared objects

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            self.coordinate = latest.coordinate
        }
    }
    
    /**
        This method is periodically called by the RootImmersiveView to render nearby shared objects.
     */
    func checkAndUpdateProximity() -> Bool {
        guard let current = coordinate else { return false }
        
        let currentLocation = CLLocation(latitude: current.latitude, longitude: current.longitude)
        
        guard let last = lastTriggeredCoordinate else {
            lastTriggeredCoordinate = current
            return true
        }
        
        let lastLocation = CLLocation(latitude: last.latitude, longitude: last.longitude)
        let distance = currentLocation.distance(from: lastLocation)
        
        if distance >= 10.0 {
            lastTriggeredCoordinate = current
            return true
        }
        return false
    }
    
}
