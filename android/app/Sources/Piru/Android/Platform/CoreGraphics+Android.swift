// The CoreGraphics bitmap path the color picker draws its Oklch plane and hue rail through:
// a CGImage built from raw RGBA pixels, shown with `Image(decorative:scale:)`. On Android the
// pixels become an uncompressed PNG that SkipFuseUI's UIImage decodes, so the picker shows
// the same computed gradients. An ImageRenderer never produces one (SwiftUI+Android.swift).

import SwiftUI

typealias CFData = Data

nonisolated struct CGColorSpace {
    static let displayP3 = "kCGColorSpaceDisplayP3"
    static let sRGB = "kCGColorSpaceSRGB"

    init?(name _: String) {}
}

final nonisolated class CGDataProvider {
    let data: Data

    init?(data: CFData) {
        self.data = data
    }
}

nonisolated struct CGBitmapInfo: OptionSet {
    let rawValue: UInt32
}

nonisolated enum CGImageAlphaInfo: UInt32 {
    case none
    case premultipliedLast
    case premultipliedFirst
    case last
    case first
    case noneSkipLast
    case noneSkipFirst
    case alphaOnly
}

nonisolated enum CGColorRenderingIntent {
    case defaultIntent
    case absoluteColorimetric
    case relativeColorimetric
    case perceptual
    case saturation
}

final nonisolated class CGImage {
    let width: Int
    let height: Int
    /// Premultiplied RGBA, 8 bits per component, rows packed.
    let pixels: Data

    init?(
        width: Int, height: Int, bitsPerComponent: Int, bitsPerPixel: Int, bytesPerRow: Int,
        space _: CGColorSpace, bitmapInfo _: CGBitmapInfo, provider: CGDataProvider,
        decode _: UnsafePointer<CGFloat>?, shouldInterpolate _: Bool, intent _: CGColorRenderingIntent,
    ) {
        guard bitsPerComponent == 8, bitsPerPixel == 32, bytesPerRow == width * 4,
              provider.data.count >= bytesPerRow * height else { return nil }
        self.width = width
        self.height = height
        pixels = provider.data
    }

    /// The pixels as a PNG: stored (uncompressed) deflate blocks, which every decoder reads.
    var pngData: Data {
        var raw = Data(capacity: (width * 4 + 1) * height)
        for row in 0 ..< height {
            raw.append(0)
            raw.append(pixels[(row * width * 4) ..< ((row + 1) * width * 4)])
        }
        var header = Data()
        header.appendBigEndian(UInt32(width))
        header.appendBigEndian(UInt32(height))
        header.append(contentsOf: [8, 6, 0, 0, 0])

        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        png.appendChunk("IHDR", header)
        png.appendChunk("IDAT", Self.zlibStored(raw))
        png.appendChunk("IEND", Data())
        return png
    }

    private static func zlibStored(_ data: Data) -> Data {
        var out = Data([0x78, 0x01])
        var offset = 0
        repeat {
            let length = min(65535, data.count - offset)
            let final: UInt8 = offset + length == data.count ? 1 : 0
            out.append(final)
            out.append(UInt8(length & 0xFF))
            out.append(UInt8(length >> 8))
            out.append(UInt8(~length & 0xFF))
            out.append(UInt8((~length >> 8) & 0xFF))
            out.append(data[offset ..< offset + length])
            offset += length
        } while offset < data.count
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        out.appendBigEndian((b << 16) | a)
        return out
    }
}

private nonisolated let crcTable: [UInt32] = (0 ..< 256).map { n in
    var c = UInt32(n)
    for _ in 0 ..< 8 { c = c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
    return c
}

private nonisolated extension Data {
    mutating func appendBigEndian(_ value: UInt32) {
        append(contentsOf: [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }

    mutating func appendChunk(_ type: String, _ body: Data) {
        appendBigEndian(UInt32(body.count))
        let typed = Data(type.utf8) + body
        append(typed)
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in typed { crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        appendBigEndian(crc ^ 0xFFFF_FFFF)
    }
}

extension Image {
    init(decorative image: CGImage, scale: CGFloat, orientation _: Image.Orientation = .up) {
        if let ui = UIImage(data: image.pngData, scale: scale) {
            self.init(uiImage: ui)
        } else {
            self.init(systemName: "square")
        }
    }
}

extension ImageRenderer {
    var cgImage: CGImage? { nil }
}
