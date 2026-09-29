// Apple types the shared code names whose frameworks Android lacks, as plain values.

typealias CLLocationDegrees = Double

struct CLLocationCoordinate2D: Hashable, Sendable {
    var latitude: CLLocationDegrees
    var longitude: CLLocationDegrees
}
