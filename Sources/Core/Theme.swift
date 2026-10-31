import SwiftUI

/// Open Search brand: a warm orange on liquid glass, with Instrument Serif (bundled, OFL) for display type.
enum Brand {
    static let orange = Color(red: 1.0, green: 0.42, blue: 0.08)
    static let ember = Color(red: 0.93, green: 0.25, blue: 0.02)
    static let amber = Color(red: 1.0, green: 0.70, blue: 0.28)

    static func display(_ size: CGFloat) -> Font { .custom("InstrumentSerif-Regular", size: size) }
    static func displayItalic(_ size: CGFloat) -> Font { .custom("InstrumentSerif-Italic", size: size) }

    static var gradient: LinearGradient {
        LinearGradient(colors: [amber, orange, ember], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Registers the bundled fonts for this process. Call once at launch.
    static func registerFonts() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

/// Soft orange light behind the glass, so the glass has something to refract.
struct BrandBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Rectangle().fill(.background)
            RadialGradient(colors: [Brand.orange.opacity(scheme == .dark ? 0.30 : 0.22), .clear],
                           center: .topTrailing, startRadius: 20, endRadius: 560)
            RadialGradient(colors: [Brand.amber.opacity(scheme == .dark ? 0.16 : 0.18), .clear],
                           center: .bottomLeading, startRadius: 20, endRadius: 520)
            RadialGradient(colors: [Brand.ember.opacity(scheme == .dark ? 0.12 : 0.08), .clear],
                           center: .bottomTrailing, startRadius: 10, endRadius: 360)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Logo

/// The Open Search mark: an open lens with a person inside it and a handle. "Open" is the gap in the ring.
struct LogoMark: View {
    var size: CGFloat = 64
    var ring: AnyShapeStyle = AnyShapeStyle(Brand.gradient)

    var body: some View {
        Canvas { ctx, canvas in
            let s = min(canvas.width, canvas.height) / 100
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

            // Lens ring, open at the upper right.
            var lens = Path()
            lens.addArc(center: p(43, 43), radius: 30 * s,
                        startAngle: .degrees(-30), endAngle: .degrees(-72), clockwise: false)
            ctx.stroke(lens, with: .style(ring), style: StrokeStyle(lineWidth: 9 * s, lineCap: .round))

            // Handle.
            var handle = Path()
            handle.move(to: p(67, 67))
            handle.addLine(to: p(88, 88))
            ctx.stroke(handle, with: .style(ring), style: StrokeStyle(lineWidth: 11 * s, lineCap: .round))

            // Person: head and shoulders.
            ctx.fill(Path(ellipseIn: CGRect(x: 35.5 * s, y: 26 * s, width: 15 * s, height: 15 * s)), with: .style(ring))
            var shoulders = Path()
            shoulders.move(to: p(27, 61))
            shoulders.addQuadCurve(to: p(59, 61), control: p(43, 34))
            shoulders.closeSubpath()
            ctx.fill(shoulders, with: .style(ring))

            // The spark that escapes the open ring.
            ctx.fill(Path(ellipseIn: CGRect(x: 74 * s, y: 12 * s, width: 10 * s, height: 10 * s)), with: .style(ring))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Wordmark: serif "Open" + italic "Search".
struct Wordmark: View {
    var size: CGFloat = 24

    var body: some View {
        HStack(spacing: size * 0.18) {
            Text("Open").font(Brand.display(size))
            Text("Search").font(Brand.displayItalic(size)).foregroundStyle(Brand.gradient)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Open Search")
    }
}

// MARK: - CSS colours (for the style guide)

extension Color {
    /// Parses hex, rgb()/rgba() and hsl()/hsla() strings as returned by the style guide endpoint.
    init?(css raw: String) {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if s == "transparent" { self = .clear; return }
        if s.hasPrefix("#") {
            var h = String(s.dropFirst())
            if h.count == 3 || h.count == 4 { h = h.map { "\($0)\($0)" }.joined() }
            guard h.count == 6 || h.count == 8, let v = UInt64(h, radix: 16) else { return nil }
            let hasAlpha = h.count == 8
            let r = Double((v >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
            let g = Double((v >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
            let b = Double((v >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
            let a = hasAlpha ? Double(v & 0xFF) / 255 : 1
            self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
            return
        }
        guard let open = s.firstIndex(of: "("), let close = s.lastIndex(of: ")") else {
            switch s {
            case "white": self = .white
            case "black": self = .black
            default: return nil
            }
            return
        }
        let name = String(s[..<open])
        let nums = s[s.index(after: open)..<close]
            .replacingOccurrences(of: "/", with: " ")
            .components(separatedBy: CharacterSet(charactersIn: ", "))
            .filter { !$0.isEmpty }
            .map { part -> Double? in
                if part.hasSuffix("%") { return Double(part.dropLast()).map { $0 / 100 } }
                return Double(part.replacingOccurrences(of: "deg", with: ""))
            }
        guard nums.count >= 3, let a0 = nums[0], let a1 = nums[1], let a2 = nums[2] else { return nil }
        let alpha = nums.count > 3 ? (nums[3] ?? 1) : 1
        if name.hasPrefix("rgb") {
            // Percentages were already divided by 100; plain numbers are 0-255.
            func chan(_ v: Double) -> Double { v <= 1 && s.contains("%") ? v : v / 255 }
            self = Color(.sRGB, red: chan(a0), green: chan(a1), blue: chan(a2), opacity: alpha)
        } else if name.hasPrefix("hsl") {
            // SwiftUI takes HSB, so convert from HSL first.
            let v = a2 + a1 * min(a2, 1 - a2)
            let sat = v == 0 ? 0 : 2 * (1 - a2 / v)
            self = Color(hue: (a0.truncatingRemainder(dividingBy: 360)) / 360, saturation: sat, brightness: v, opacity: alpha)
        } else {
            return nil
        }
    }
}
