import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Writes the synthetic fixtures used by tests and reviews into fixtures/ (or the directory given as argument).
// Everything here is invented: no real screenshots, names or data. Run: swift run fixturegen [dir]

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!

/// A drawing surface measured in points with a top-left origin, rendered at 2x.
struct Canvas {
    let ctx: CGContext
    let width: Double, height: Double
    let space: CGColorSpace

    init(width: Int, height: Int, scale: Int = 2, space: CGColorSpace = sRGB) {
        self.width = Double(width); self.height = Double(height); self.space = space
        ctx = CGContext(data: nil, width: width * scale, height: height * scale, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(height * scale)); ctx.scaleBy(x: CGFloat(scale), y: CGFloat(-scale))
        ctx.setAllowsFontSmoothing(false)
    }

    func color(_ hex: UInt32, _ alpha: Double = 1) -> CGColor {
        let c = CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
        return c.converted(to: space, intent: .defaultIntent, options: nil) ?? c
    }
    func fill(_ hex: UInt32, _ x: Double, _ y: Double, _ w: Double, _ h: Double, r: Double = 0, alpha: Double = 1) {
        ctx.setFillColor(color(hex, alpha))
        ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: min(r, w / 2, h / 2), cornerHeight: min(r, w / 2, h / 2), transform: nil))
        ctx.fillPath()
    }
    func stroke(_ hex: UInt32, _ x: Double, _ y: Double, _ w: Double, _ h: Double, r: Double = 0, width: Double = 1, alpha: Double = 1) {
        ctx.setStrokeColor(color(hex, alpha)); ctx.setLineWidth(width)
        ctx.addPath(CGPath(roundedRect: CGRect(x: x + 0.5, y: y + 0.5, width: w - 1, height: h - 1), cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.strokePath()
    }
    func circle(_ hex: UInt32, _ cx: Double, _ cy: Double, _ r: Double, alpha: Double = 1) {
        ctx.setFillColor(color(hex, alpha)); ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
    }
    enum Align { case left, center, right }
    /// Draws one line of text with its baseline at `y`. Returns the width.
    @discardableResult
    func text(_ s: String, _ x: Double, _ y: Double, size: Double, bold: Bool = false, mono: Bool = false, _ hex: UInt32, align: Align = .left) -> Double {
        let font: CTFont = mono ? CTFontCreateWithName("Menlo" as CFString, size, nil)
            : CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)!
        let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(hex)]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attributes))
        let w = CTLineGetTypographicBounds(line, nil, nil, nil)
        let startX = align == .left ? x : align == .center ? x - w / 2 : x - w
        ctx.saveGState(); ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: startX, y: y); CTLineDraw(line, ctx); ctx.restoreGState()
        return w
    }
    /// Greedy word wrap. Returns the baseline for the line after the last one.
    func paragraph(_ s: String, _ x: Double, _ y: Double, width: Double, size: Double, lineHeight: Double, _ hex: UInt32, bold: Bool = false) -> Double {
        var y = y, line = ""
        for word in s.split(separator: " ") {
            let trial = line.isEmpty ? String(word) : line + " " + word
            let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)!
            let w = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(NSAttributedString(string: trial, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])), nil, nil, nil)
            if w > width, !line.isEmpty { text(line, x, y, size: size, bold: bold, hex); y += lineHeight; line = String(word) } else { line = trial }
        }
        if !line.isEmpty { text(line, x, y, size: size, bold: bold, hex); y += lineHeight }
        return y
    }
    func gradient(_ from: UInt32, _ to: UInt32, from p0: CGPoint, to p1: CGPoint) {
        let g = CGGradient(colorsSpace: space, colors: [color(from), color(to)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: p0, end: p1, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    func image() -> CGImage { ctx.makeImage()! }
}

func write(_ image: CGImage, to url: URL, type: UTType = .png, properties: [CFString: Any] = [:]) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(url.lastPathComponent)") }
    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    print("wrote \(url.lastPathComponent) \(image.width)x\(image.height) \(size / 1024) KB")
}

// MARK: Fixtures

/// A dark analytics dashboard, 1280 x 520 pt. Typical wide window.
func wideDashboard(space: CGColorSpace = sRGB) -> CGImage {
    let c = Canvas(width: 1280, height: 520, space: space)
    c.fill(0x0d1016, 0, 0, 1280, 520); c.fill(0x11151c, 0, 0, 204, 520); c.fill(0xffffff, 204, 0, 1, 520, alpha: 0.06)
    c.fill(0x5eead4, 22, 22, 24, 24, r: 7); c.text("Meridian", 56, 40, size: 15, bold: true, 0xe8ebf2)
    for (i, name) in ["Overview", "Reports", "Customers", "Funnels", "Billing", "Settings"].enumerated() {
        let y = 84 + Double(i) * 40
        if i == 0 { c.fill(0xffffff, 12, y - 16, 180, 32, r: 8, alpha: 0.07) }
        c.stroke(i == 0 ? 0xe8ebf2 : 0x6f7888, 26, y - 7, 14, 14, r: 4, width: 1.5)
        c.text(name, 52, y + 4, size: 13, i == 0 ? 0xe8ebf2 : 0x8a93a3)
    }
    c.text("Overview", 240, 46, size: 22, bold: true, 0xf3f5f9)
    c.text("Last 30 days · Sep 5 – Oct 4, 2026", 240, 70, size: 13, 0x7b8494)
    c.fill(0x1a2029, 1030, 26, 110, 34, r: 9); c.fill(0x1a2029, 1148, 26, 96, 34, r: 9)
    c.text("Last 30 days", 1085, 47, size: 12.5, 0xc9cfda, align: .center); c.text("Export", 1196, 47, size: 12.5, 0x5eead4, align: .center)
    for (i, k) in [("Active accounts", "12,480", "+8.2%"), ("Monthly revenue", "$184.2k", "+3.9%"), ("Churn", "1.8%", "−0.4%"), ("Median build time", "4m 12s", "−62%")].enumerated() {
        let x = 240 + Double(i) * 256
        c.fill(0x151a23, x, 92, 240, 104, r: 12); c.stroke(0xffffff, x, 92, 240, 104, r: 12, alpha: 0.06)
        c.text(k.0, x + 18, 120, size: 12.5, 0x8a93a3); c.text(k.1, x + 18, 154, size: 28, bold: true, 0xf3f5f9)
        c.text(k.2 + " vs prior period", x + 18, 182, size: 12.5, 0x5eead4)
    }
    c.fill(0x151a23, 240, 214, 664, 278, r: 12); c.text("Weekly active accounts", 260, 244, size: 14, bold: true, 0xe8ebf2)
    let gx = 292.0, gy = 272.0, gw = 588.0, gh = 180.0
    for i in 0...3 { c.fill(0xffffff, gx, gy + gh * Double(i) / 3, gw, 1, alpha: 0.07); c.text("\(12 - i * 4)k", gx - 10, gy + gh * Double(i) / 3 + 4, size: 11, 0x6f7888, align: .right) }
    var points: [CGPoint] = []
    for i in 0..<30 {
        let v = 6200 + Double(i) * 190 + sin(Double(i) * 0.9) * 380 + (i % 7 == 5 ? -520 : 0)
        points.append(CGPoint(x: gx + gw * Double(i) / 29, y: gy + gh - (v - 4000) / 9000 * gh))
    }
    let area = CGMutablePath(); area.move(to: CGPoint(x: gx, y: gy + gh)); area.addLine(to: points[0])
    let line = CGMutablePath(); line.move(to: points[0])
    for i in 1..<points.count {
        let mid = CGPoint(x: (points[i - 1].x + points[i].x) / 2, y: (points[i - 1].y + points[i].y) / 2)
        area.addQuadCurve(to: mid, control: points[i - 1]); line.addQuadCurve(to: mid, control: points[i - 1])
    }
    area.addLine(to: points[29]); area.addLine(to: CGPoint(x: gx + gw, y: gy + gh)); area.closeSubpath()
    c.ctx.saveGState(); c.ctx.addPath(area); c.ctx.clip()
    c.gradient(0x23504f, 0x151a23, from: CGPoint(x: 0, y: gy), to: CGPoint(x: 0, y: gy + gh)); c.ctx.restoreGState()
    c.ctx.setStrokeColor(c.color(0x5eead4)); c.ctx.setLineWidth(2.2); c.ctx.setLineJoin(.round); c.ctx.addPath(line); c.ctx.strokePath()
    c.circle(0x0d1016, points[29].x, points[29].y, 5); c.ctx.setStrokeColor(c.color(0x5eead4)); c.ctx.setLineWidth(2)
    c.ctx.strokeEllipse(in: CGRect(x: points[29].x - 4.5, y: points[29].y - 4.5, width: 9, height: 9))
    c.fill(0x151a23, 920, 214, 324, 278, r: 12); c.text("Top regions", 940, 244, size: 14, bold: true, 0xe8ebf2)
    for (i, r) in [("United States", 31.0), ("Germany", 14), ("United Kingdom", 11), ("France", 9), ("Japan", 8), ("Canada", 6)].enumerated() {
        let y = 280 + Double(i) * 34
        c.text(r.0, 940, y, size: 12.5, 0xc9cfda); c.text("\(Int(r.1))%", 1224, y, size: 12.5, 0x8a93a3, align: .right)
        c.fill(0xffffff, 940, y + 10, 284, 5, r: 2.5, alpha: 0.07); c.fill(0x5eead4, 940, y + 10, 284 * r.1 / 31, 5, r: 2.5)
    }
    return c.image()
}

/// A long light article page, 760 pt wide. Typical tall capture.
func tallArticle() -> CGImage {
    let width = 760
    func paint(_ c: Canvas) -> Double {
        c.fill(0xffffff, 0, 0, 760, 6000)
        c.text("Fieldnotes", 40, 44, size: 18, bold: true, 0x16181d)
        for (x, s) in [(520.0, "Posts"), (576, "Topics"), (640, "About")] { c.text(s, x, 44, size: 14, 0x5b6070) }
        c.fill(0x000000, 0, 64, 760, 1, alpha: 0.07)
        var y = 116.0
        c.text("ENGINEERING · 9 MIN READ", 60, y, size: 12, bold: true, 0x2b59ff); y += 44
        y = c.paragraph("How we cut CI build times by 62% without buying bigger machines", 60, y, width: 640, size: 38, lineHeight: 46, 0x16181d, bold: true)
        y += 14; c.circle(0xe8d9ff, 76, y + 10, 16); c.text("Priya Raman", 104, y + 8, size: 14, bold: true, 0x16181d); c.text("October 2, 2026", 104, y + 26, size: 13, 0x7b8190); y += 62
        c.ctx.saveGState(); c.ctx.addPath(CGPath(roundedRect: CGRect(x: 60, y: y, width: 640, height: 280), cornerWidth: 16, cornerHeight: 16, transform: nil)); c.ctx.clip()
        c.gradient(0xdfe9ff, 0xf3dcf5, from: CGPoint(x: 60, y: y), to: CGPoint(x: 700, y: y + 280))
        for (cx, cy, r, hex) in [(170.0, 190.0, 120.0, UInt32(0x9db8ff)), (330, 120, 84, 0xc7a8f5), (520, 200, 140, 0xffc2d6), (610, 70, 60, 0xa8e6d8)] { c.circle(hex, cx, y + cy, r, alpha: 0.75) }
        c.ctx.restoreGState(); y += 324
        func heading(_ s: String) { y += 14; c.text(s, 60, y, size: 24, bold: true, 0x16181d); y += 38 }
        func body(_ s: String) { y = c.paragraph(s, 60, y, width: 640, size: 17, lineHeight: 29, 0x2a2d36) + 12 }
        y = c.paragraph("For two years our pipeline got slower every quarter, and we answered the way most teams do: bigger runners. This autumn we tried something less glamorous and measured where the minutes actually went.", 60, y, width: 640, size: 19, lineHeight: 31, 0x16181d) + 14
        heading("Start with a profile of the pipeline")
        body("Every job reported a single number, so the first step was to break each one into phases. Dependency installs, compilation and test setup together accounted for 71% of wall-clock time, and most of that was work we had already done on the previous commit.")
        c.fill(0x12151b, 60, y, 640, 168, r: 12)
        for (i, l) in ["$ ci profile --last 200 --group phase", "install      4m 38s   31%", "compile      3m 05s   21%", "test-setup   2m 49s   19%", "tests        3m 51s   26%", "upload       0m 22s    3%"].enumerated() {
            c.text(l, 84, y + 38 + Double(i) * 22, size: 13.5, mono: true, i == 0 ? 0x9aa3b5 : 0xe6e9ef)
        }
        y += 204
        heading("Cache the boring parts")
        body("A content-addressed cache keyed on lockfiles removed most installs. Compile artifacts followed once we stopped embedding timestamps in the output, which had quietly invalidated every cache entry since 2024.")
        c.fill(0xf5f6f9, 60, y, 640, 236, r: 14); c.text("Median build time (minutes)", 84, y + 38, size: 14, bold: true, 0x16181d)
        for (i, b) in [("Before", 14.5, UInt32(0xc3c9d6)), ("After", 5.5, 0x2b59ff)].enumerated() {
            let by = y + 66 + Double(i) * 70, bw = 460 * b.1 / 14.5
            c.text(b.0, 84, by + 25, size: 13, 0x5b6070); c.fill(b.2, 150, by, bw, 40, r: 8)
            c.text(String(format: "%.1f", b.1), 150 + bw - 14, by + 26, size: 14, bold: true, i == 1 ? 0xffffff : 0x16181d, align: .right)
        }
        c.text("Median over 200 builds on the main branch.", 84, y + 220, size: 12, 0x7b8190); y += 276
        heading("What we left alone")
        body("We did not parallelise the test suite further. Two shards were already near the point where startup cost outweighs the gain, and a third would have made failures harder to read.")
        c.fill(0x2b59ff, 60, y + 6, 3, 74)
        y = c.paragraph("Most of our slowest minutes were work we had already done.", 84, y + 30, width: 600, size: 21, lineHeight: 32, 0x16181d) + 28
        body("Median build time fell from 14m 30s to 5m 31s. Runner spend dropped 38%, and the queue that used to back up at ten in the morning is gone.")
        y += 10; c.fill(0xf5f6f9, 60, y, 640, 150, r: 16)
        c.text("Get the next post", 90, y + 50, size: 20, bold: true, 0x16181d); c.text("One email when something ships. No tracking.", 90, y + 74, size: 14, 0x5b6070)
        c.fill(0xffffff, 90, y + 90, 360, 40, r: 10); c.stroke(0xd9dce3, 90, y + 90, 360, 40, r: 10); c.text("you@company.com", 106, y + 115, size: 14, 0x9aa0ae)
        c.fill(0x2b59ff, 462, y + 90, 138, 40, r: 10); c.text("Subscribe", 531, y + 115, size: 14, bold: true, 0xffffff, align: .center)
        y += 200; c.text("© 2026 Fieldnotes", 60, y, size: 12.5, 0x9aa0ae)
        return y + 40
    }
    let probe = Canvas(width: width, height: 6000)
    let height = Int(paint(probe).rounded(.up))
    let c = Canvas(width: width, height: height); _ = paint(c)
    return c.image()
}

/// A small settings sheet, 440 x 312 pt. Typical dialog capture.
func smallDialog() -> CGImage {
    let c = Canvas(width: 440, height: 312)
    c.fill(0xf6f6f9, 0, 0, 440, 312)
    c.ctx.saveGState(); c.ctx.addPath(CGPath(roundedRect: CGRect(x: 28, y: 28, width: 44, height: 44), cornerWidth: 11, cornerHeight: 11, transform: nil)); c.ctx.clip()
    c.gradient(0x6a7bff, 0xa56bff, from: CGPoint(x: 28, y: 28), to: CGPoint(x: 72, y: 72)); c.ctx.restoreGState()
    c.stroke(0xffffff, 40, 38, 20, 25, r: 3, width: 2)
    c.text("Export report", 88, 52, size: 16, bold: true, 0x16181d)
    _ = c.paragraph("Choose how Meridian packages the last 30 days of activity.", 88, 72, width: 320, size: 13, lineHeight: 18, 0x5b6070)
    for (label, value, y) in [("Format", "PDF, with charts", 112.0), ("Date range", "Last 30 days", 170)] {
        c.text(label, 28, y + 4, size: 12.5, bold: true, 0x16181d); c.fill(0xffffff, 28, y + 8, 384, 32, r: 8); c.stroke(0xd9dce3, 28, y + 8, 384, 32, r: 8)
        c.text(value, 42, y + 29, size: 13.5, 0x16181d)
    }
    c.text("Include raw data", 28, 251, size: 13.5, bold: true, 0x16181d); c.fill(0x34c759, 364, 231, 48, 28, r: 14); c.circle(0xffffff, 398, 245, 11)
    c.fill(0x000000, 0, 268, 440, 1, alpha: 0.08)
    c.fill(0xffffff, 232, 278, 88, 28, r: 8); c.stroke(0xd9dce3, 232, 278, 88, 28, r: 8); c.text("Cancel", 276, 297, size: 13, bold: true, 0x16181d, align: .center)
    c.fill(0x2f6bff, 328, 278, 84, 28, r: 8); c.text("Export", 370, 297, size: 13, bold: true, 0xffffff, align: .center)
    return c.image()
}

/// A dark editor on an ultrawide display, 1720 x 720 pt.
func ultrawideEditor() -> CGImage {
    let c = Canvas(width: 1720, height: 720)
    c.fill(0x14161c, 0, 0, 1720, 720); c.fill(0x191c24, 0, 0, 260, 720); c.fill(0x1d212b, 260, 0, 1460, 36)
    for (i, name) in ["layout.swift", "renderer.swift", "recipe.swift"].enumerated() {
        c.fill(i == 1 ? 0x14161c : 0x1d212b, 260 + Double(i) * 150, 0, 148, 36); c.text(name, 280 + Double(i) * 150, 23, size: 12.5, i == 1 ? 0xe6e9ef : 0x8a93a3)
    }
    for (i, name) in ["Sources", "  Core", "    Layout.swift", "    Renderer.swift", "    Recipe.swift", "  App", "Tests", "Package.swift"].enumerated() {
        c.text(name, 20, 40 + Double(i) * 26, size: 12.5, i == 3 ? 0xe6e9ef : 0x8a93a3)
    }
    let code = ["func resolve(sourceWidth: Int, sourceHeight: Int, recipe: Recipe) -> Layout {", "    let k = lerp(0.03, 0.19, Double(recipe.space) / 100)", "    var canvasW: Double, canvasH: Double, s: Double", "    if let fixed = recipe.shape.canvas {", "        let m = k * min(fixed.width, fixed.height)", "        s = min((fixed.width - 2 * m) / ww, (fixed.height - 2 * m) / wh, 1)", "    } else {", "        s = 1", "    }", "    let f = min(1, 4096 / max(canvasW, canvasH))", "    return Layout(width: outW, height: outH, capped: f < 1)", "}"]
    for (i, l) in code.enumerated() {
        let y = 70 + Double(i) * 22; c.text(String(i + 1), 330, y, size: 12.5, mono: true, 0x4a5262, align: .right)
        c.text(l, 350, y, size: 13.5, mono: true, l.contains("func") || l.contains("let") || l.contains("var") ? 0xc792ea : 0xd6dae3)
    }
    return c.image()
}

/// A thin toolbar strip, 1200 x 80 pt. Typical thin crop.
func thinStrip() -> CGImage {
    let c = Canvas(width: 1200, height: 80)
    c.fill(0xf4f5f8, 0, 0, 1200, 80); c.fill(0x000000, 0, 79, 1200, 1, alpha: 0.1)
    for (i, name) in ["New", "Open", "Save", "Share", "Export"].enumerated() {
        let x = 24 + Double(i) * 118
        c.fill(i == 3 ? 0x2f6bff : 0xffffff, x, 20, 104, 40, r: 10); c.stroke(0xd9dce3, x, 20, 104, 40, r: 10)
        c.text(name, x + 52, 46, size: 14, bold: true, i == 3 ? 0xffffff : 0x16181d, align: .center)
    }
    return c.image()
}

/// Saturated Display P3 colours that sRGB cannot hold, with an sRGB-safe row for comparison. For spike S9.
func p3Patches() -> CGImage {
    let c = Canvas(width: 600, height: 300, space: displayP3)
    func p3(_ r: Double, _ g: Double, _ b: Double) -> CGColor { CGColor(colorSpace: displayP3, components: [r, g, b, 1])! }
    let colours: [(Double, Double, Double)] = [(1, 0, 0), (0, 1, 0), (0, 0, 1), (1, 0.5, 0), (0, 1, 1), (1, 0, 1)]
    for (i, col) in colours.enumerated() {
        c.ctx.setFillColor(p3(col.0, col.1, col.2)); c.ctx.fill(CGRect(x: Double(i) * 100, y: 0, width: 100, height: 150))
    }
    let g = CGGradient(colorsSpace: displayP3, colors: [p3(1, 0, 0.35), p3(0.1, 0.2, 1)] as CFArray, locations: [0, 1])!
    c.ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 225), end: CGPoint(x: 600, y: 225), options: [])
    return c.image()
}

/// Every pixel has a unique, known value, so exact-copy checks (R5) can compare byte for byte.
func exactPattern() -> CGImage {
    let w = 512, h = 300
    var pixels = [UInt8](repeating: 255, count: w * h * 4)
    for y in 0..<h { for x in 0..<w {
        let i = (y * w + x) * 4
        pixels[i] = UInt8((x * 7 + y * 3) & 255); pixels[i + 1] = UInt8((x * 5 + y * 11) & 255); pixels[i + 2] = UInt8((x ^ y) & 255)
    } }
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: sRGB,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}

// MARK: Run

let directory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "fixtures", isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
func out(_ name: String) -> URL { directory.appendingPathComponent(name) }

write(wideDashboard(), to: out("wide-dashboard.png"))
write(tallArticle(), to: out("tall-article.png"))
write(smallDialog(), to: out("small-dialog.png"))
write(ultrawideEditor(), to: out("ultrawide-editor.png"))
write(thinStrip(), to: out("thin-strip.png"))
write(p3Patches(), to: out("p3-patches.png"))
write(exactPattern(), to: out("exact-pattern.png"))
// The same wide dashboard stored rotated by an EXIF orientation tag (6 = rotate 90° clockwise): it must load upright.
let rotated = wideDashboard();
write(smallDialog(), to: out("rotated-dialog.jpg"), type: .jpeg, properties: [kCGImagePropertyOrientation: 6, kCGImageDestinationLossyCompressionQuality: 0.92])
write(smallDialog(), to: out("small-dialog.heic"), type: .heic, properties: [kCGImageDestinationLossyCompressionQuality: 0.85])
