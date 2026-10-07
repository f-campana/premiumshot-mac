import Foundation

/// Every failure the loop can hit. All of them are recoverable: the UI shows the message and stays usable.
public enum PremiumShotError: Error, Equatable, Sendable, LocalizedError {
    case invalidRecipe(String)
    case unreadableImage(String)
    case unsupportedFormat(String)
    case imageTooLarge(pixels: Int, limit: Int)
    case renderFailed(String)
    case encodeFailed(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRecipe(let m): return "Invalid recipe: \(m)"
        case .unreadableImage(let m): return "That image could not be read. \(m)"
        case .unsupportedFormat(let m): return "Unsupported image format. \(m)"
        case .imageTooLarge(let p, let l):
            return "That image is \(p / 1_000_000) megapixels. The limit is \(l / 1_000_000)."
        case .renderFailed(let m): return "Too large to render. \(m)"
        case .encodeFailed(let m): return "Could not encode the PNG. \(m)"
        case .writeFailed(let m): return "Could not write the file. \(m)"
        }
    }

    /// Process exit codes used by the `pshot` CLI.
    public var exitCode: Int32 {
        switch self {
        case .invalidRecipe: return 2
        case .unreadableImage, .unsupportedFormat: return 3
        case .imageTooLarge, .renderFailed: return 4
        case .encodeFailed, .writeFailed: return 5
        }
    }
}
