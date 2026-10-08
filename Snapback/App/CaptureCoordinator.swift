import AppKit

/// Runs one capture: grab the front window, annotate it in place, then save or send it.
final class CaptureCoordinator {
    static let shared = CaptureCoordinator()

    private var panel: OverlayPanel?
    private var pill: RecordingPill?
    #if DEBUG
    /// The real overlay session and send progress, for demo takes.
    private(set) var demoSession: AnnotationSession?
    private(set) var demoIsSending = false

    #endif
    /// A capture from history is being opened; recordings take a moment, and steps shouldn't overtake each other.
    private var isNavigating = false

    func start() {
        guard panel == nil, !ScreenRecorder.shared.isRecording else { return }
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

    /// Starts recording the screen, or stops and opens the recording to pick frames from.
    func toggleRecording() {
        let recorder = ScreenRecorder.shared
        if recorder.isRecording {
            stopRecording()
            return
        }
        guard panel == nil else { return }
        guard Permission.allGranted else {
            PermissionsWindow.showIfNeeded()
            return
        }
        Task {
            var pill: RecordingPill?
            do {
                // The pill is up before recording starts, so Snapback has a window on screen to leave out of it.
                try await recorder.start { [weak self] screen in
                    let shown = RecordingPill(screen: screen, started: .now) { self?.stopRecording() }
                    shown.orderFrontRegardless()
                    self?.pill = shown
                    pill = shown
                    return CGWindowID(shown.windowNumber)
                }
            } catch {
                pill?.orderOut(nil)
                self.pill = nil
                NSSound.beep()
                return
            }
            try? await Task.sleep(for: ScreenRecorder.limit)
            // Still the same recording: stop it at the limit.
            if let pill, self.pill === pill { stopRecording() }
        }
    }

    /// Opens the recording at its first frame, cropped to the window that was in front.
    private func stopRecording() {
        // Stopping before capture has begun would leave it running with no pill.
        guard ScreenRecorder.shared.hasStarted else { return }
        pill?.orderOut(nil)
        pill = nil
        Task {
            do {
                let finished = try await ScreenRecorder.shared.stop()
                let recording = try await Recording.open(finished.url, deletesFile: true)
                let time = recording.times[0]
                let image = try await recording.image(at: time, exact: true).image
                let display = CapturedWindow(image: image, frame: finished.frame, screen: finished.screen,
                                             appName: finished.appName, windowTitle: finished.windowTitle)
                let crop = finished.windowRect ?? CGRect(origin: .zero, size: finished.frame.size)
                present(AnnotationSession(recording: recording, display: display, crop: crop.integral, frames: [], time: time))
            } catch {
                NSSound.beep()
            }
        }
    }

    /// Opens a saved capture in the overlay to change and send again.
    func reopen(_ saved: SavedCapture) {
        guard panel == nil, !ScreenRecorder.shared.isRecording else { return }
        Task {
            guard panel == nil, let session = await CaptureStore.shared.restore(saved) else { return }
            present(session)
        }
    }

    /// Shows a session in the overlay, reusing the open overlay when stepping through history.
    private func present(_ session: AnnotationSession) {
        #if DEBUG
        demoSession = session
        #endif
        let view = OverlayView(
            session: session,
            animatesIn: panel == nil,
            onSend: { [weak self] in self?.close(session, to: .claude) },
            onCopy: { [weak self] in self?.close(session, to: .clipboard) },
            onSave: { [weak self] in self?.close(session, to: .recent) },
            onDiscard: { [weak self] in self?.dismiss() },
            onNavigate: { [weak self] step in self?.navigate(from: session, by: step) }
        )
        CaptureStore.shared.prefetchNeighbours(of: session.savedID)
        SendSound.current.preload()
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
        guard store.captures.indices.contains(target), !isNavigating else { return }
        isNavigating = true
        Task {
            defer { isNavigating = false }
            // Decoding a recording's frames takes a moment; the overlay may have closed meanwhile.
            guard let next = await store.restore(store.captures[target]), panel != nil else { return }
            present(next)
            // Show the next capture first; save the one left behind (only if it changed) once that's on screen.
            if session.hasChanges && session.isWorthSaving {
                await Task.yield()
                store.save(session, png: FeedbackImage.png(for: session))
            }
        }
    }

    /// Where a capture goes when the overlay closes. It's always kept in Recent as well.
    private enum Destination {
        case recent, claude, clipboard
    }

    private func close(_ session: AnnotationSession, to destination: Destination) {
        // Only Copy works without markers: it copies the plain window, or the recording's frames.
        guard destination == .clipboard || session.hasMarkers else { return }
        guard destination != .recent || (session.hasChanges && session.isWorthSaving) else {
            dismiss()
            return
        }
        #if DEBUG
        demoIsSending = destination == .claude
        #endif
        // Close first so the overlay is gone the moment you press the button; render once it's off screen.
        dismiss()
        // Copy sounds the moment you press it; the image follows once rendered.
        if destination == .clipboard { SendSound.current.play() }
        Task {
            await Task.yield()
            let png = FeedbackImage.png(for: session)
            // Deliver before saving to history, so the image and sound don't wait on writing files.
            switch destination {
            case .recent: break
            case .claude: await ClaudeCodeSender.send(png)
            case .clipboard: Clipboard.copy(png: png)
            }
            CaptureStore.shared.save(session, png: png)
            #if DEBUG
            demoIsSending = false
            #endif
        }
    }

    private func dismiss() {
        #if DEBUG
        demoSession = nil
        #endif
        panel?.orderOut(nil)
        panel = nil
    }
}
