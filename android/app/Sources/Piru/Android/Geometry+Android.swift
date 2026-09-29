// One CoreGraphics family for the whole module. Android's Foundation declares CGFloat,
// CGPoint, CGSize, CGRect and CGAffineTransform, and SkipFuseUI declares its own (CGFloat is
// Double there); a file that imports only Foundation would otherwise hold values its SwiftUI
// neighbors cannot take. Declarations at module scope shadow imported ones in every file, so
// all of them use SkipFuseUI's, the family every view API speaks.

import SkipSwiftUI
import SwiftUI

typealias CGFloat = SkipSwiftUI.CGFloat
typealias CGPoint = SkipSwiftUI.CGPoint
typealias CGSize = SkipSwiftUI.CGSize
typealias CGRect = SkipSwiftUI.CGRect
typealias CGVector = SkipSwiftUI.CGVector
typealias CGAffineTransform = SkipSwiftUI.CGAffineTransform
