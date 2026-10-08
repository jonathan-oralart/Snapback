import AppKit

/// The sound played when a capture lands in Claude: SND01 "sine" by Yasuhiro Tsuchiya (https://snd.dev), used unmodified.
enum SendSound: String, CaseIterable, Identifiable {
    case off
    case button
    case tap1 = "tap_01"
    case tap2 = "tap_02"
    case tap3 = "tap_03"
    case tap4 = "tap_04"
    case tap5 = "tap_05"

    static let defaultsKey = "sendSound"

    var id: Self { self }

    var title: String {
        switch self {
        case .off: "None"
        case .button: "Button"
        case .tap1: "Tap 1"
        case .tap2: "Tap 2"
        case .tap3: "Tap 3"
        case .tap4: "Tap 4"
        case .tap5: "Tap 5"
        }
    }

    static var current: SendSound {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(SendSound.init) ?? .button
    }

    /// Kept so the sound isn't released while it's playing.
    private static var playing: NSSound?

    func play() {
        guard self != .off, let url = Bundle.main.url(forResource: rawValue, withExtension: "wav") else { return }
        Self.playing?.stop()
        Self.playing = NSSound(contentsOf: url, byReference: true)
        Self.playing?.play()
    }
}
