// Environment values SkipFuseUI marks unavailable, under names android/substitutions.txt
// points the shared code at.

import SwiftUI

extension EnvironmentValues {
    @Entry var androidDisplayScale: CGFloat = 3

    @Entry var androidIsPresented: Bool = false

    @Entry var androidDynamicTypeSize: DynamicTypeSize = .large

    @Entry var androidDifferentiateWithoutColor: Bool = false
}
