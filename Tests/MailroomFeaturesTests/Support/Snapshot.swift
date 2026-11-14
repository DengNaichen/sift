import AppKit
import Foundation
import SwiftUI
import Testing

/// 不依赖第三方库的最小快照比对：离屏 NSWindow + NSHostingView → bitmap → 与 PNG 基线逐像素比对。
@MainActor
enum Snapshot {
    static let size = CGSize(width: 1220, height: 780)

    static var directory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__", isDirectory: true)
    }

    static var isRecording: Bool {
        ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
    }

    static func render(_ view: AnyView, dark: Bool, settle: TimeInterval = 0.6) async -> NSBitmapImageRep {
        _ = NSApplication.shared
        let rect = NSRect(origin: .zero, size: size)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = rect
        let window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        try? await Task.sleep(nanoseconds: UInt64(settle * 1_000_000_000))
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        window.orderOut(nil)
        window.contentView = nil
        return rep
    }

    /// 像素差异：通道差 > channelTolerance 计为差异像素；差异像素比例 > maxDiffRatio 判失败。
    static func assertMatches(
        _ view: AnyView,
        dark: Bool,
        named name: String,
        channelTolerance: Int = 6,
        maxDiffRatio: Double = 0.0015,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        let rep = await render(view, dark: dark)
        let url = directory.appendingPathComponent("\(name).png")
        let fm = FileManager.default
        if isRecording || !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            return
        }
        guard let data = try? Data(contentsOf: url),
              let baseline = NSBitmapImageRep(data: data) else {
            Issue.record("Cannot read baseline \(name)", sourceLocation: sourceLocation)
            return
        }
        let actual = normalized(rep)
        let expected = normalized(baseline)
        guard actual.width == expected.width, actual.height == expected.height else {
            Issue.record("Snapshot \(name) size mismatch \(actual.width)x\(actual.height) vs \(expected.width)x\(expected.height)", sourceLocation: sourceLocation)
            return
        }
        var diffPixels = 0
        var diffBytes = [UInt8](repeating: 0, count: actual.bytes.count)
        for i in stride(from: 0, to: actual.bytes.count, by: 4) {
            var maxDelta = 0
            for c in 0..<4 {
                maxDelta = max(maxDelta, abs(Int(actual.bytes[i + c]) - Int(expected.bytes[i + c])))
            }
            if maxDelta > channelTolerance {
                diffPixels += 1
                diffBytes[i] = 255; diffBytes[i + 3] = 255
            } else {
                diffBytes[i] = actual.bytes[i] / 4; diffBytes[i + 1] = actual.bytes[i + 1] / 4
                diffBytes[i + 2] = actual.bytes[i + 2] / 4; diffBytes[i + 3] = 255
            }
        }
        let ratio = Double(diffPixels) / Double(actual.width * actual.height)
        if ratio > maxDiffRatio {
            let failDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mailroom-snapshot-failures", isDirectory: true)
            try? fm.createDirectory(at: failDir, withIntermediateDirectories: true)
            try? rep.representation(using: .png, properties: [:])?.write(to: failDir.appendingPathComponent("\(name)-actual.png"))
            if let diffRep = makeRep(diffBytes, width: actual.width, height: actual.height) {
                try? diffRep.representation(using: .png, properties: [:])?.write(to: failDir.appendingPathComponent("\(name)-diff.png"))
            }
            Issue.record("Snapshot \(name) differs: \(diffPixels) px (\(String(format: "%.4f", ratio * 100))%). See \(failDir.path)", sourceLocation: sourceLocation)
        }
    }

    private struct RGBA {
        let width: Int
        let height: Int
        let bytes: [UInt8]
    }

    private static func normalized(_ rep: NSBitmapImageRep) -> RGBA {
        let w = rep.pixelsWide, h = rep.pixelsHigh
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        bytes.withUnsafeMutableBytes { buf in
            if let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
               let cg = rep.cgImage {
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        }
        return RGBA(width: w, height: h, bytes: bytes)
    }

    private static func makeRep(_ bytes: [UInt8], width: Int, height: Int) -> NSBitmapImageRep? {
        var copy = bytes
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        return copy.withUnsafeMutableBytes { buf -> NSBitmapImageRep? in
            guard let ctx = CGContext(data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let cg = ctx.makeImage() else { return nil }
            return NSBitmapImageRep(cgImage: cg)
        }
    }
}
