import Foundation

/// The app a capture is sent to, chosen in Settings: a new Claude Code session or a new Codex thread.
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

    var newChatURL: URL {
        switch self {
        case .claude: URL(string: "claude://code/new")!
        case .codex: URL(string: "codex://threads/new")!
        }
    }

    static var current: SendTarget {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(SendTarget.init) ?? .claude
    }
}
