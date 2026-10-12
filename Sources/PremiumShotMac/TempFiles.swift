import Foundation

/// Temp PNGs for drag-out. They live in the app's cache directory and are deleted at the next launch.
public enum DragTempFiles {
    public static var directory: URL {
        directory(bundleIdentifier: Bundle.main.bundleIdentifier)
    }

    static func directory(bundleIdentifier: String?) -> URL {
        let namespace = bundleIdentifier == "app.premiumshot.mac.dev"
            ? "app.premiumshot.mac.dev" : "app.premiumshot.mac"
        return
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(namespace, isDirectory: true).appendingPathComponent(
                "drag", isDirectory: true)
    }

    /// Removes everything left from earlier launches.
    public static func purge(directory: URL = DragTempFiles.directory) {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Never delete an input file supplied by a user or another drag source.
    public static func remove(_ url: URL, directory: URL = DragTempFiles.directory) {
        guard url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }

    /// Writes `data` as `name` in the temp directory and returns its URL. Throws if the file cannot be written,
    /// in which case the drag must not start.
    public static func write(_ data: Data, name: String, directory: URL = DragTempFiles.directory) throws
        -> URL
    {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }
}
