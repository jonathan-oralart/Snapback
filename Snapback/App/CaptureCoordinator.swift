import AppKit

/// Runs one capture: grab the front window, annotate it in place, then save or send it.
final class CaptureCoordinator {
    static let shared = CaptureCoordinator()

    private var panel: OverlayPanel?

    func start() {
        guard panel == nil else { return }
        guard Permission.allGranted else {
            PermissionsWindow.showIfNeeded()
            return
        }
        Task {
            do {
                present(AnnotationSession(capture: try await WindowCapture.captureFrontWindow()))
            } catch {
                NSSound.beep()
            }
        }
    }

    /// Opens a saved capture in the overlay to change and send again.
    func reopen(_ saved: SavedCapture) {
        guard panel == nil, let session = CaptureStore.shared.restore(saved) else { return }
        present(session)
    }

    /// Shows a session in the overlay, reusing the open overlay when stepping through history.
    private func present(_ session: AnnotationSession) {
        let view = OverlayView(
            session: session,
            animatesIn: panel == nil,
            onSend: { [weak self] in self?.close(session, sending: true) },
            onSave: { [weak self] in self?.close(session, sending: false) },
            onDiscard: { [weak self] in self?.dismiss() },
            onNavigate: { [weak self] step in self?.navigate(from: session, by: step) }
        )
        CaptureStore.shared.prefetchNeighbours(of: session.savedID)
        if let panel {
            panel.show(view)
        } else {
            let panel = OverlayPanel(screen: session.capture.screen, content: view)
            self.panel = panel
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// Steps through Recent while annotating: +1 is older, −1 newer. The capture being left is saved first,
    /// as closing would.
    private func navigate(from session: AnnotationSession, by step: Int) {
        let store = CaptureStore.shared
        // An unsaved capture sits just before the newest saved one.
        let current = session.savedID.flatMap { id in store.captures.firstIndex { $0.id == id } } ?? -1
        let target = current + step
        guard store.captures.indices.contains(target), let next = store.restore(store.captures[target]) else { return }
        present(next)
        // Show the next capture first; save the one left behind (only if it changed) once that's on screen.
        if session.hasChanges && !session.markers.isEmpty {
            Task {
                await Task.yield()
                store.save(session, png: FeedbackImage.png(for: session))
            }
        }
    }

    /// Saves the capture to Recent, and sends it to Claude Code if asked.
    private func close(_ session: AnnotationSession, sending: Bool) {
        guard !session.markers.isEmpty else { return }
        guard sending || session.hasChanges else {
            dismiss()
            return
        }
        // Close first so the overlay is gone the moment you press the button; render once it's off screen.
        dismiss()
        Task {
            await Task.yield()
            let png = FeedbackImage.png(for: session)
            CaptureStore.shared.save(session, png: png)
            if sending {
                await ClaudeCodeSender.send(png)
            }
        }
    }

    private func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}
