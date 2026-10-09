import AppKit
import PremiumShotCore

/// A drop may promise several files. Keep its folder until every reader has finished, and let
/// only the first decodable image replace the source. Late readers always clean up their files.
@MainActor
final class PromisedImport {
    private weak var model: PanelModel?
    private let token: WorkToken
    let folder: URL
    private var remaining = 0
    private var finished = false
    private var failure = "The dropped files contain no supported image."
    private var timeout: Task<Void, Never>?

    init(model: PanelModel, token: WorkToken, folder: URL) {
        self.model = model
        self.token = token
        self.folder = folder
    }

    func expect(_ count: Int) { remaining += max(1, count) }

    func startTimeout() {
        timeout = Task {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            expired()
            timeout = nil
        }
    }

    func expired() {
        if !finished {
            finished = true
            model?.importFailed("The dropped image did not arrive. Try dropping it again.", token: token)
        }
        try? FileManager.default.removeItem(at: folder)
    }

    func receive(_ url: URL, error: Error? = nil) async {
        defer {
            remaining -= 1
            if remaining <= 0 {
                timeout?.cancel()
                if !finished { model?.importFailed(failure, token: token) }
                finished = true
                try? FileManager.default.removeItem(at: folder)
            } else if finished && error == nil && owns(url) {
                // A writer can complete after timeout removed the folder.
                try? FileManager.default.removeItem(at: url)
            }
        }
        guard !finished, let model, model.state.token == token else { return }
        if let error {
            failure = error.localizedDescription
            return
        }
        do {
            let source = try await Task.detached(priority: .userInitiated) {
                try ImageLoader.load(url: url)
            }.value
            guard !finished, model.state.token == token else { return }
            finished = true
            model.replace(with: source)
        } catch { failure = error.localizedDescription }
    }

    private func owns(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path + "/")
    }
}
