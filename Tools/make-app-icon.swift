// Draws the app icon and writes every macOS size into the asset catalog.
//
//   swiftc -o /tmp/make-app-icon Tools/make-app-icon.swift && /tmp/make-app-icon MawaqitPrayerTime/Assets.xcassets/AppIcon.appiconset
//
// Everything is drawn on a 1024 × 1024 canvas using Apple's icon grid: an 824-point
// rounded square, centred, with room around it for the shadow.
import AppKit
import SwiftUI

private extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// A crescent: a disc with an offset disc cut out of it.
private struct Crescent: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(ellipseIn: rect)
        let cut = rect.offsetBy(dx: rect.width * 0.30, dy: -rect.height * 0.22).insetBy(dx: rect.width * 0.06, dy: rect.height * 0.06)
        path = path.subtracting(Path(ellipseIn: cut))
        return path
    }
}

private struct Star: Shape {
    var points = 5
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2, inner = outer * 0.42
        var path = Path()
        for i in 0..<(points * 2) {
            let radius = i.isMultiple(of: 2) ? outer : inner
            let angle = Double(i) * .pi / Double(points) - .pi / 2
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            i == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

/// Dome, two minarets and the prayer hall, in 1024-canvas coordinates.
private struct MosqueSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        // Onion dome with a short spire.
        p.move(to: CGPoint(x: 392, y: 708))
        p.addCurve(to: CGPoint(x: 512, y: 540), control1: CGPoint(x: 360, y: 620), control2: CGPoint(x: 478, y: 610))
        p.addCurve(to: CGPoint(x: 632, y: 708), control1: CGPoint(x: 546, y: 610), control2: CGPoint(x: 664, y: 620))
        p.closeSubpath()
        p.addRect(CGRect(x: 506, y: 500, width: 12, height: 48))
        p.addEllipse(in: CGRect(x: 500, y: 486, width: 24, height: 24))
        // Drum under the dome and the prayer hall.
        p.addRect(CGRect(x: 404, y: 700, width: 216, height: 56))
        p.addRect(CGRect(x: 300, y: 748, width: 424, height: 240))
        // Minarets: shaft, balcony and pointed cap.
        for x in [CGFloat(246), 742] {
            p.addRect(CGRect(x: x, y: 590, width: 36, height: 400))
            p.addRect(CGRect(x: x - 8, y: 640, width: 52, height: 14))
            p.move(to: CGPoint(x: x - 2, y: 592))
            p.addLine(to: CGPoint(x: x + 18, y: 520))
            p.addLine(to: CGPoint(x: x + 38, y: 592))
            p.closeSubpath()
        }
        return p
    }
}

/// An arched doorway, cut from the prayer hall.
private struct Doorway: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 476, y: 924))
        p.addLine(to: CGPoint(x: 476, y: 846))
        p.addQuadCurve(to: CGPoint(x: 548, y: 846), control: CGPoint(x: 512, y: 786))
        p.addLine(to: CGPoint(x: 548, y: 924))
        p.closeSubpath()
        return p
    }
}

struct AppIcon: View {
    private let body824 = CGRect(x: 100, y: 100, width: 824, height: 824)
    private let squircle = RoundedRectangle(cornerRadius: 185, style: .continuous)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ZStack(alignment: .topLeading) {
                // Night sky fading to a hint of dawn at the horizon.
                LinearGradient(colors: [Color(hex: 0x0B3B30), Color(hex: 0x16664F), Color(hex: 0x2C8C6A)],
                               startPoint: .top, endPoint: .bottom)
                // Soft glow behind the moon.
                RadialGradient(colors: [Color(hex: 0xF6D57A, opacity: 0.35), .clear],
                               center: UnitPoint(x: 0.61, y: 0.24), startRadius: 10, endRadius: 330)
                // A few small stars.
                ForEach(Array(starField.enumerated()), id: \.offset) { _, star in
                    Circle()
                        .fill(Color.white.opacity(star.2))
                        .frame(width: star.3, height: star.3)
                        .position(x: star.0 - 100, y: star.1 - 100)
                }
                // Golden crescent and star.
                Crescent()
                    .fill(LinearGradient(colors: [Color(hex: 0xFBE29A), Color(hex: 0xE9B44C)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 280, height: 280)
                    .position(x: 604 - 100, y: 296 - 100)
                    .shadow(color: Color(hex: 0xF6D57A, opacity: 0.5), radius: 18)
                Star()
                    .fill(Color(hex: 0xFBE29A))
                    .frame(width: 92, height: 92)
                    .position(x: 712 - 100, y: 268 - 100)
                // Mosque silhouette with a lit doorway.
                MosqueSilhouette()
                    .fill(LinearGradient(colors: [Color(hex: 0xFFFFFF), Color(hex: 0xE6EFEA)],
                                         startPoint: .top, endPoint: .bottom))
                    .offset(x: -100, y: -100)
                Doorway()
                    .fill(Color(hex: 0x16664F))
                    .offset(x: -100, y: -100)
            }
            .frame(width: body824.width, height: body824.height)
            .clipShape(squircle)
            .overlay(squircle.strokeBorder(Color.white.opacity(0.12), lineWidth: 3))
            .shadow(color: .black.opacity(0.28), radius: 14, y: 10)
            .offset(x: body824.minX, y: body824.minY)
        }
        .frame(width: 1024, height: 1024)
    }

    /// x, y, opacity, diameter (1024-canvas coordinates).
    private let starField: [(CGFloat, CGFloat, Double, CGFloat)] = [
        (230, 240, 0.85, 12), (330, 180, 0.6, 8), (420, 300, 0.7, 9), (280, 400, 0.45, 7),
        (820, 470, 0.6, 9), (860, 220, 0.5, 7), (190, 520, 0.4, 6), (470, 190, 0.5, 6),
    ]
}

@MainActor
func writeIcons(to directory: URL) throws {
    // (file name, pixel size) for every slot in a macOS app icon set.
    let slots: [(String, Int)] = [
        ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
    ]
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for (name, pixels) in slots {
        let renderer = ImageRenderer(content: AppIcon())
        renderer.scale = CGFloat(pixels) / 1024
        guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        let rep = NSBitmapImageRep(cgImage: image)
        try rep.representation(using: .png, properties: [:])!.write(to: directory.appending(path: name))
    }
    let images = slots.map { name, pixels -> String in
        let point = [16: 16, 32: 16, 64: 32, 128: 128, 256: 128, 512: 256, 1024: 512][pixels]!
        let size = name.contains("@2x") ? point : pixels
        let scale = name.contains("@2x") ? "2x" : "1x"
        return #"    { "filename" : "\#(name)", "idiom" : "mac", "scale" : "\#(scale)", "size" : "\#(size)x\#(size)" }"#
    }
    let contents = "{\n  \"images\" : [\n" + images.joined(separator: ",\n") + "\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
    try contents.write(to: directory.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
}

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.appiconset")
try MainActor.assumeIsolated { try writeIcons(to: output) }
print("Wrote app icon to \(output.path)")
