import Foundation

public enum Timing {
    public static func milliseconds(_ duration: Duration) -> Double {
        let c = duration.components
        return ((Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15) * 10).rounded() / 10
    }
}
