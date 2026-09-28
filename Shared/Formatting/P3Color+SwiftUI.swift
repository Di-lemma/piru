import SwiftUI

nonisolated extension P3Color {
    var color: Color {
        Color(.displayP3, red: red, green: green, blue: blue)
    }
}
