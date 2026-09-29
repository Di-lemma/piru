// Color math SkipFuseUI leaves out. A Skip Color cannot be resolved, but one built from
// components keeps them in its spec, which Mirror can read: that makes `mix` a real linear
// blend for component colors (substance tints, white, black). A named or semantic color has
// no components here, and mixing it returns it unchanged.

import SwiftUI

nonisolated extension Color {
    /// Red, green, blue, alpha in 0…1, where the color was built from components.
    var androidComponents: (red: Double, green: Double, blue: Double, alpha: Double)? {
        guard let spec = Mirror(reflecting: self).children.first(where: { $0.label == "spec" })?.value else { return nil }
        let specMirror = Mirror(reflecting: spec)
        let opacity = specMirror.children.first { $0.label == "opacity" }?.value as? Double ?? 1
        guard let type = specMirror.children.first(where: { $0.label == "type" })?.value else { return nil }
        let typeMirror = Mirror(reflecting: type)
        guard let case_ = typeMirror.children.first else {
            switch String(describing: type) {
            case "white": return (1, 1, 1, opacity)
            case "black": return (0, 0, 0, opacity)
            case "clear": return (0, 0, 0, 0)
            default: return nil
            }
        }
        let values = Mirror(reflecting: case_.value).children.compactMap { $0.value as? Double }
        switch case_.label {
        case "rgb" where values.count == 4: return (values[0], values[1], values[2], values[3] * opacity)
        case "w" where values.count == 2: return (values[0], values[0], values[0], values[1] * opacity)
        default: return nil
        }
    }

    func androidMix(with other: Color, by fraction: Double, in _: Any? = nil) -> Color {
        guard let a = androidComponents, let b = other.androidComponents else { return self }
        let t = min(max(fraction, 0), 1)
        return Color(
            red: a.red + (b.red - a.red) * t, green: a.green + (b.green - a.green) * t,
            blue: a.blue + (b.blue - a.blue) * t, opacity: a.alpha + (b.alpha - a.alpha) * t,
        )
    }
}

/// iOS materials as the fills stage.py generates for them (`MATERIALS`): Compose draws no blur,
/// and Skip's own stand-in is near-white, which leaves a material card invisible on the page.
extension ShapeStyle where Self == Color {
    static var androidUltraThinMaterial: Color { Color("android__material__ultraThin", bundle: AndroidResources.bundle) }
    static var androidThinMaterial: Color { Color("android__material__thin", bundle: AndroidResources.bundle) }
    static var androidRegularMaterial: Color { Color("android__material__regular", bundle: AndroidResources.bundle) }
    static var androidThickMaterial: Color { Color("android__material__thick", bundle: AndroidResources.bundle) }
    static var androidUltraThickMaterial: Color { Color("android__material__ultraThick", bundle: AndroidResources.bundle) }
}
