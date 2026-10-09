import CoreServices
import Foundation

public enum LatestScreenshot {
    public static var folder: URL {
        let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.screencapture")
        if let path = domain?["location"] as? String {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }
    /// Metadata flags avoid assuming the screenshot's filename language. Only this directory is inspected.
    public static func find(in folder: URL) throws -> URL? {
        let candidates = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles])
        let extensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff"]
        return candidates.compactMap { url -> (URL, Date)? in
            guard extensions.contains(url.pathExtension.lowercased()),
                let info = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                info.isRegularFile == true,
                let item = MDItemCreateWithURL(nil, url as CFURL),
                let captured = MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString) as? NSNumber,
                captured.boolValue
            else { return nil }
            return (url, info.contentModificationDate ?? .distantPast)
        }.max { $0.1 < $1.1 }?.0
    }
}
