import Foundation

/// Normalised drawing geometry for transient UI frames. These frames are never export specifications.
public struct PresentationGeometry: Equatable, Sendable {
    public var values: [Double]
    public init(_ layout: Layout) {
        let u = Double(layout.height)
        let w = layout.window
        values = [
            Double(layout.width) / u, Double(w.x) / u, Double(w.y) / u,
            Double(w.width) / u, Double(w.height) / u,
            layout.cornerRadius / u,
            layout.keyShadow.blur / u, layout.keyShadow.offsetY / u, layout.keyShadow.alpha,
            layout.ambientShadow.blur / u, layout.ambientShadow.offsetY / u, layout.ambientShadow.alpha,
        ]
    }
    public func interpolated(to other: Self, fraction: Double) -> Self {
        var result = self
        let t = min(1, max(0, fraction))
        result.values = zip(values, other.values).map { $0 + ($1 - $0) * t }
        return result
    }
    /// The raster aspect includes integer canvas rounding, so preview sizing
    /// uses exactly the transform that renderPresentation will compose.
    public func aspectRatio(reference: Layout) -> Double {
        let raster = layout(reference: reference)
        return Double(raster.width) / Double(raster.height)
    }

    func layout(reference: Layout) -> Layout {
        let u = Double(reference.height)
        let v = values
        return Layout(
            width: max(5, Int((v[0] * u).rounded())), height: reference.height,
            capped: reference.capped, screenshotScale: reference.screenshotScale,
            window: .init(
                x: Int((v[1] * u).rounded()), y: Int((v[2] * u).rounded()),
                width: max(1, Int((v[3] * u).rounded())), height: max(1, Int((v[4] * u).rounded()))),
            cornerRadius: v[5] * u,
            keyShadow: .init(blur: v[6] * u, offsetY: v[7] * u, alpha: v[8]),
            ambientShadow: .init(blur: v[9] * u, offsetY: v[10] * u, alpha: v[11]))
    }
}
