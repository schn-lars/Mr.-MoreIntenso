import CoreLocation

extension CLLocationCoordinate2D {
    
    /**
        Used by the renderer to map these coordinates into 3D vector space in front of the user.
     */
    func metersOffset(from origin: CLLocationCoordinate2D) -> SIMD3<Float> {
        let latMetersPerDeg: Double = 111_100 // at the equator, but decreasing as you move to the poles
        let lonMetersPerDeg: Double = 111_100 * cos(origin.latitude * .pi / 180)

        let dx = Float((self.longitude - origin.longitude) * lonMetersPerDeg)
        let dz = Float((self.latitude  - origin.latitude)  * latMetersPerDeg)
        // dx = east/west, dz = north/south, y = 0 (ground level)
        return SIMD3(dx, 0, -dz)
    }
}
