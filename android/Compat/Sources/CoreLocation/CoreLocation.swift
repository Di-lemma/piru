public typealias CLLocationDegrees = Double

public struct CLLocationCoordinate2D: Hashable, Sendable {
    public var latitude: CLLocationDegrees
    public var longitude: CLLocationDegrees

    public init(latitude: CLLocationDegrees, longitude: CLLocationDegrees) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public init() {
        self.init(latitude: 0, longitude: 0)
    }
}
