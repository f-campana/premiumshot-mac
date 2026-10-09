import Foundation

public enum FileOutput {
    /// Exclusive creation closes the race between choosing a collision suffix and writing the file.
    /// Called only after the main actor validates the work token. No suspension occurs until the effect is complete.
    public static func save(_ data: Data, directory: URL, date: Date = Date()) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let stem = "Screenshot \(formatter.string(from:date)) polished"
        for suffix in 1...10000 {
            let url = directory.appendingPathComponent(stem + (suffix == 1 ? "" : " \(suffix)") + ".png")
            do {
                try data.write(to: url, options: .withoutOverwriting)
                return url
            } catch {
                if FileManager.default.fileExists(atPath: url.path) { continue }
                throw error
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }
}
