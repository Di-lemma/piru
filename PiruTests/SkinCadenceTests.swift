import Foundation
import Testing
@testable import Piru

@Suite("Skin cadence")
struct SkinCadenceTests {
    @Test
    func `Scenes run at 30 fps, stickers at 20, and Low Power Mode halves both`() {
        #expect(SkinBackdrop.frameInterval(stickers: false, lowPower: false) == 1.0 / 30)
        #expect(SkinBackdrop.frameInterval(stickers: true, lowPower: false) == 1.0 / 20)
        #expect(SkinBackdrop.frameInterval(stickers: false, lowPower: true) == 1.0 / 15)
        #expect(SkinBackdrop.frameInterval(stickers: true, lowPower: true) == 1.0 / 10)
    }

    @Test
    func `Only a serious or critical thermal state stops the scene`() {
        #expect(!SkinPower.constrained(.nominal))
        #expect(!SkinPower.constrained(.fair))
        #expect(SkinPower.constrained(.serious))
        #expect(SkinPower.constrained(.critical))
    }
}
