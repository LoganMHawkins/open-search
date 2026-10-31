#if DEBUG
import SwiftUI
import AppKit

/// The app icon, drawn from the same vector mark as the in-app logo.
/// `Tools/make-icon.sh` launches the app with `--export-icon <dir>` to render the PNGs, then builds the asset catalog.
struct IconArt: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 188, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.62, blue: 0.20), Brand.orange, Color(red: 0.90, green: 0.22, blue: 0.02)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 188, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0)], startPoint: .top, endPoint: .center))
            LogoMark(size: 540, ring: AnyShapeStyle(.white))
                .shadow(color: .black.opacity(0.28), radius: 20, x: 0, y: 14)
        }
        .frame(width: 824, height: 824)
        .shadow(color: .black.opacity(0.32), radius: 22, x: 0, y: 14)
        .frame(width: 1024, height: 1024)
    }
}

@MainActor
enum IconExporter {
    static func run(into directory: String) {
        let dir = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        write(IconArt(), size: 1024, to: dir.appendingPathComponent("icon-1024.png"))
        // Foreground layer for the Icon Composer bundle: the white mark, centred, with room for the system's glass and shadow.
        write(LogoMark(size: 640, ring: AnyShapeStyle(.white)), size: 1024, to: dir.appendingPathComponent("mark-white-1024.png"))
        write(LogoMark(size: 512), size: 512, to: dir.appendingPathComponent("logo-512.png"))
        print("Exported icon art to \(dir.path)")
        exit(0)
    }

    private static func write<V: View>(_ view: V, size: CGFloat, to url: URL) {
        let renderer = ImageRenderer(content: view.frame(width: size, height: size))
        renderer.scale = 1
        renderer.isOpaque = false
        guard let cg = renderer.cgImage else { print("Could not render \(url.lastPathComponent)"); return }
        let rep = NSBitmapImageRep(cgImage: cg)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
    }
}
#endif
