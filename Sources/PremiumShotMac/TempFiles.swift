import Foundation

/// Temp PNGs for drag-out. They live in the app's cache directory and are deleted at the next launch.
public enum DragTempFiles {
    public static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.fabien.premiumshot", isDirectory: true).appendingPathComponent("drag", isDirectory: true)
    }

    /// Removes everything left from earlier launches.
    public static func purge(directory: URL = DragTempFiles.directory) {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Writes `data` as `name` in the temp directory and returns its URL. Throws if the file cannot be written,
    /// in which case the drag must not start.
    public static func write(_ data: Data, name: String, directory: URL = DragTempFiles.directory) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }
}
