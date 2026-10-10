import Foundation

/// The app Copy & Open switches to, chosen in Settings.
enum SendTarget: String, CaseIterable, Identifiable {
    case claude
    case codex

    static let defaultsKey = "sendTarget"

    var id: Self { self }

    var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    var bundleID: String {
        switch self {
        case .claude: "com.anthropic.claudefordesktop"
        case .codex: "com.openai.codex"
        }
    }

    static var current: SendTarget {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(SendTarget.init) ?? .claude
    }
}
