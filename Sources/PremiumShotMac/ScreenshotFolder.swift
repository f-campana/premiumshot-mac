import AppKit
import Foundation

/// Folder selection is independent of Save. No directory is enumerated until Open latest is requested.
enum ScreenshotFolder {
    static let bookmarkKey = "screenshotsFolderBookmark.v1"

    static func selected(in defaults: UserDefaults) throws -> URL {
        guard let data = defaults.data(forKey: bookmarkKey) else { return LatestScreenshot.folder }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            try remember(url, in: defaults)
        }
        return url
    }

    static func remember(_ url: URL, in defaults: UserDefaults) throws {
        let data = try url.bookmarkData(options: .withSecurityScope,
                                        includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: bookmarkKey)
    }

    static func isDenied(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError { return true }
        if error.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(error.code) { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error { return isDenied(underlying) }
        return false
    }

    @MainActor static func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") else { return }
        NSWorkspace.shared.open(url)
    }
}
