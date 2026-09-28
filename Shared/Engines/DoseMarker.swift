import Foundation

/// A dose without duration data, shown as a timestamp marker on the graph.
nonisolated struct DoseMarker: Hashable, Codable, Sendable {
    let substanceName: String
    let timestamp: Date
    let tint: P3Color
    let amount: Double
    let unit: String
}
