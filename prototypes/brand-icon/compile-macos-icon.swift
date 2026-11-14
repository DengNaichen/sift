#!/usr/bin/env swift
import AppKit
import SwiftUI

// Usage:
//   swift prototypes/brand-icon/compile-macos-icon.swift <source-square-image> <output-squircle-1024.png> [--icns <output.icns>]
//
// Uses Apple's native SwiftUI `RoundedRectangle(cornerRadius:style:.continuous)`
// so straight edges and G2 continuous corners match macOS Sequoia / Tahoe HIG 1:1:
// - 1024x1024 total canvas
// - 824x824 continuous rounded-rect body (100pt padding per side)
// - 185.4pt continuous corner radius (22.5% of 824pt)
// - Top-lit 1.5pt Liquid Glass inner specular rim + authentic macOS drop shadow
// - Optional automatic 10-slice .iconset -> .icns compilation via /usr/bin/iconutil

struct IconSpec {
    let points: Int
    let scale: Int
    var pixels: Int { points * scale }
    var filename: String {
        scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    }
}

let allIconSpecs: [IconSpec] = [
    .init(points: 16, scale: 1),
    .init(points: 16, scale: 2),
    .init(points: 32, scale: 1),
    .init(points: 32, scale: 2),
    .init(points: 128, scale: 1),
    .init(points: 128, scale: 2),
    .init(points: 256, scale: 1),
    .init(points: 256, scale: 2),
    .init(points: 512, scale: 1),
    .init(points: 512, scale: 2)
]

struct MacOSAppIconCanvas: View {
    let source: CGImage
    let canvasSize: CGFloat

    var body: some View {
        let bodySize = canvasSize * (824.0 / 1024.0)
        let cornerRadius = bodySize * 0.225
        let rimWidth = max(0.75, canvasSize * (1.8 / 1024.0))
        let shadowRadius = canvasSize * (14.0 / 1024.0)
        let shadowY = canvasSize * (10.0 / 1024.0)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            Image(decorative: source, scale: 1.0)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: bodySize, height: bodySize)
                .clipShape(shape)
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.52), location: 0.0),
                                .init(color: .white.opacity(0.14), location: 0.45),
                                .init(color: .black.opacity(0.14), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: rimWidth
                    )
                )
                .shadow(color: .black.opacity(0.26), radius: shadowRadius, x: 0, y: shadowY)
        }
        .frame(width: canvasSize, height: canvasSize)
    }
}

@MainActor
func renderIcon(source: CGImage, pixels: Int) -> CGImage? {
    let view = MacOSAppIconCanvas(source: source, canvasSize: CGFloat(pixels))
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1.0
    renderer.isOpaque = false
    return renderer.cgImage
}

func savePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconCompiler", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
    }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

@MainActor
func main() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count >= 2 else {
        fputs("Usage: compile-macos-icon.swift <source-image> <output-1024.png> [--icns <AppIcon.icns>]\n", stderr)
        exit(1)
    }

    let srcURL = URL(fileURLWithPath: args[0])
    let outPNGURL = URL(fileURLWithPath: args[1])

    guard let nsImage = NSImage(contentsOf: srcURL),
          let srcCG = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fputs("Error: Unable to read source image at \(srcURL.path)\n", stderr)
        exit(1)
    }

    let side = min(srcCG.width, srcCG.height)
    let cropRect = CGRect(
        x: (srcCG.width - side) / 2,
        y: (srcCG.height - side) / 2,
        width: side,
        height: side
    )
    let squareCG = srcCG.cropping(to: cropRect) ?? srcCG

    guard let icon1024 = renderIcon(source: squareCG, pixels: 1024) else {
        fputs("Error: Failed to render 1024x1024 icon\n", stderr)
        exit(1)
    }
    try savePNG(icon1024, to: outPNGURL)
    print("Saved 1024x1024 squircle PNG -> \(outPNGURL.path)")

    if let icnsIdx = args.firstIndex(of: "--icns"), icnsIdx + 1 < args.count {
        let icnsURL = URL(fileURLWithPath: args[icnsIdx + 1])
        let tempIconset = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
        try FileManager.default.createDirectory(at: tempIconset, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempIconset) }

        for spec in allIconSpecs {
            guard let img = renderIcon(source: squareCG, pixels: spec.pixels) else { continue }
            try savePNG(img, to: tempIconset.appendingPathComponent(spec.filename))
        }

        try FileManager.default.createDirectory(at: icnsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        proc.arguments = ["-c", "icns", tempIconset.path, "-o", icnsURL.path]
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            fputs("Error: iconutil failed with status \(proc.terminationStatus)\n", stderr)
            exit(proc.terminationStatus)
        }
        print("Compiled macOS .icns -> \(icnsURL.path)")
    }
}

try MainActor.assumeIsolated {
    try main()
}
