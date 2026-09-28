import SwiftUI

extension SubstanceColor {
    var color: Color {
        tint.color
    }
}

extension [SubstanceColor] {
    /// Map of lowercased substance name -> Color
    var colorMap: [String: Color] {
        Dictionary(map { ($0.substance.lowercased(), $0.color) }, uniquingKeysWith: { _, last in last })
    }
}

nonisolated extension SubstancePalette {
    static func color(for name: String, colorMap: [String: Color]) -> Color {
        colorMap[name.lowercased()] ?? fallback(for: name).color
    }
}
