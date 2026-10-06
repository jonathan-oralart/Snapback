import KeyboardShortcuts
import SwiftUI

/// A capture's place in Recent, newest first. `index` is nil for a capture that hasn't been saved yet.
struct HistoryPosition {
    let index: Int?
    let count: Int

    var hasOlder: Bool { (index ?? -1) + 1 < count }
    var hasNewer: Bool { (index ?? 0) > 0 }
}

/// History arrows, marker colour and size, and Send, under the screenshot. Closing is done by clicking the background.
struct OverlayToolbar: View {
    let hasMarkers: Bool
    @Binding var style: MarkerStyle
    let history: HistoryPosition
    let showsShortcuts: Bool
    let onNavigate: (Int) -> Void
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if history.count > 0 {
                HistoryControls(position: history, showsShortcuts: showsShortcuts, onNavigate: onNavigate)
                Divider().frame(height: 22)
            }
            StyleControls(style: $style, showsShortcuts: showsShortcuts)
            Divider().frame(height: 22)
            Button(action: onSend) {
                HStack(spacing: 6) {
                    Label("Claude", systemImage: "paperplane.fill")
                    if showsShortcuts { KeyCap(for: .send) }
                }
            }
            .globalKeyboardShortcut(.send)
            .buttonStyle(SendButtonStyle())
            .disabled(!hasMarkers)
            .help("Send to a new Claude Code chat")
        }
        .padding(8)
        .glassEffect(.regular, in: .capsule)
    }
}

/// A shortcut drawn as a small keycap, shown while ⌘ is held.
private struct KeyCap: View {
    let keys: String

    init(_ keys: String) {
        self.keys = keys
    }

    init(for name: KeyboardShortcuts.Name) {
        keys = KeyboardShortcuts.getShortcut(for: name)?.description ?? ""
    }

    var body: some View {
        Text(keys)
            .font(.system(size: 10, weight: .medium))
            .opacity(0.7)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.foreground.opacity(0.35), lineWidth: 1))
            .transition(.opacity)
    }
}

/// Older and newer arrows around this capture's place in Recent.
private struct HistoryControls: View {
    let position: HistoryPosition
    let showsShortcuts: Bool
    let onNavigate: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            arrow("chevron.left", step: 1, enabled: position.hasOlder, help: "Older capture")
            Text(position.index.map { "\($0 + 1) / \(position.count)" } ?? "New")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 44)
            arrow("chevron.right", step: -1, enabled: position.hasNewer, help: "Newer capture")
            if showsShortcuts { KeyCap("← →").padding(.leading, 4) }
        }
    }

    private func arrow(_ symbol: String, step: Int, enabled: Bool, help: String) -> some View {
        Button { onNavigate(step) } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 28)
                .contentShape(Rectangle())
                .hoverHighlight(in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .help(help)
    }
}

/// A dot showing the current marker colour and size; clicking it opens the swatches and size dots beside it.
private struct StyleControls: View {
    @Binding var style: MarkerStyle
    let showsShortcuts: Bool
    @State private var isExpanded = false

    var body: some View {
        HStack(spacing: 14) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Circle().fill(Color(nsColor: style.color))
                        .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                        .frame(width: 8 + 4 * CGFloat(style.size.rawValue), height: 8 + 4 * CGFloat(style.size.rawValue))
                        .frame(width: 18, height: 18)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    if showsShortcuts { KeyCap("− +") }
                }
                .padding(.horizontal, 8)
                .frame(height: 30)
                .contentShape(Capsule())
                .hoverHighlight(in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Marker colour and size")

            if isExpanded {
                options
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .padding(.leading, 2)
    }

    private var options: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                ForEach(MarkerStyle.Tint.allCases, id: \.self) { tint in
                    Button { style.tint = tint } label: {
                        Circle().fill(Color(nsColor: tint.color))
                            .frame(width: 18, height: 18)
                            .padding(3)
                            .overlay(Circle().strokeBorder(.foreground.opacity(style.tint == tint ? 0.7 : 0), lineWidth: 2))
                            .contentShape(Circle())
                            .hoverHighlight(in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(tint.name)
                }
            }
            HStack(spacing: 0) {
                ForEach(MarkerStyle.Size.allCases, id: \.self) { size in
                    Button { style.size = size } label: {
                        Circle()
                            .fill(style.size == size ? Color(nsColor: style.color) : Color.secondary.opacity(0.45))
                            .frame(width: 8 + 4 * CGFloat(size.rawValue), height: 8 + 4 * CGFloat(size.rawValue))
                            .frame(width: 22, height: 26)
                            .contentShape(Rectangle())
                            .hoverHighlight(in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .help("Marker size (− and +)")
        }
    }
}

/// An accent-coloured capsule that lightens on hover and darkens when pressed.
private struct SendButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration)
    }

    private struct StyledButton: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            let lift = configuration.isPressed ? -0.08 : (isHovering ? 0.1 : 0)
            configuration.label
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.accentColor.mix(with: lift >= 0 ? .white : .black, by: abs(lift))))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Capsule())
                .onHover { isHovering = $0 && isEnabled }
                .animation(.easeOut(duration: 0.12), value: isHovering)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }
    }
}

private extension View {
    /// A faint backdrop in `shape` while the pointer is over the view.
    func hoverHighlight(in shape: some Shape) -> some View {
        modifier(HoverHighlight(shape: AnyShape(shape)))
    }
}

private struct HoverHighlight: ViewModifier {
    let shape: AnyShape
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(shape.fill(Color.primary.opacity(isHovering ? 0.1 : 0)))
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
