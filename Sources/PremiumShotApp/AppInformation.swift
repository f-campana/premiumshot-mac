import AppKit

enum AppInformation {
    static var supportURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "PSSupportURL") as? String,
              let url = URL(string: value), url.scheme == "https" else { return nil }
        return url
    }

    static var aboutOptions: [NSApplication.AboutPanelOptionKey: Any] {
        let credits = NSMutableAttributedString(string: "Screenshots, worth sharing.\n\n")
        for (label, key) in [("Website", "PSWebsiteURL"), ("Source on GitHub", "PSSourceURL"),
                             ("Send feedback", "PSFeedbackURL")] {
            if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
               let url = URL(string: value), url.scheme == "https" || (key == "PSFeedbackURL" && url.scheme == "mailto") {
                credits.append(NSAttributedString(string: label + "\n", attributes: [.link: url]))
            }
        }
        return [
            .applicationName: "PremiumShot",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development",
            .version: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            .credits: credits,
        ]
    }
}
