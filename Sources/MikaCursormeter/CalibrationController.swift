import AppKit

final class CalibrationController {
    private let tracker: DistanceTracker
    private var fullThrottleWindow: NSWindow?
    private var fullThrottleTimer: Timer?

    init(tracker: DistanceTracker) {
        self.tracker = tracker
    }

    // MARK: - Vollgas-Kalibrierung (10 s Peak)

    func startFullThrottle() {
        let intro = NSAlert()
        intro.messageText = "Vollgas-Kalibrierung"
        intro.informativeText = """
        Bewege den Cursor 10 Sekunden lang so schnell wie möglich (z. B. schnelle Kreise auf dem Trackpad).
        Der höchste gemessene counts/s-Wert wird als „Vollauslenkung = 10 km/h" gespeichert.
        """
        intro.addButton(withTitle: "Starten")
        intro.addButton(withTitle: "Abbrechen")
        guard intro.runModal() == .alertFirstButtonReturn else { return }

        runFullThrottleSession()
    }

    private func runFullThrottleSession() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 140),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Vollgas-Kalibrierung läuft…"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.center()

        let content = NSView(frame: window.contentLayoutRect)
        content.autoresizingMask = [.width, .height]

        let countdown = NSTextField(labelWithString: "10,0 s — bitte voll auslenken")
        countdown.frame = NSRect(x: 20, y: 80, width: 320, height: 30)
        countdown.alignment = .center
        countdown.font = .systemFont(ofSize: 18, weight: .semibold)
        content.addSubview(countdown)

        let peakLabel = NSTextField(labelWithString: "Peak: 0 counts/s")
        peakLabel.frame = NSRect(x: 20, y: 50, width: 320, height: 20)
        peakLabel.alignment = .center
        peakLabel.font = .systemFont(ofSize: 13)
        peakLabel.textColor = .secondaryLabelColor
        content.addSubview(peakLabel)

        let liveLabel = NSTextField(labelWithString: "Aktuell: 0 counts/s")
        liveLabel.frame = NSRect(x: 20, y: 28, width: 320, height: 20)
        liveLabel.alignment = .center
        liveLabel.font = .systemFont(ofSize: 11)
        liveLabel.textColor = .tertiaryLabelColor
        content.addSubview(liveLabel)

        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        fullThrottleWindow = window

        tracker.beginCalibrationCapture()

        let startTime = Date()
        let duration: TimeInterval = 10.0
        var lastCounts: Double = 0
        var lastSampleTime = startTime
        var peakRate: Double = 0

        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let now = Date()
            let elapsed = now.timeIntervalSince(startTime)
            let dt = now.timeIntervalSince(lastSampleTime)
            lastSampleTime = now

            let captureSum = self.tracker.peekCalibrationCapture()
            let delta = captureSum - lastCounts
            lastCounts = captureSum
            let rate = dt > 0 ? delta / dt : 0
            if rate > peakRate { peakRate = rate }

            let remaining = max(0, duration - elapsed)
            countdown.stringValue = String(format: "%.1f s — bitte voll auslenken", remaining)
            peakLabel.stringValue = String(format: "Peak: %.0f counts/s", peakRate)
            liveLabel.stringValue = String(format: "Aktuell: %.0f counts/s", rate)

            if elapsed >= duration {
                timer.invalidate()
                self.fullThrottleTimer = nil
                _ = self.tracker.endCalibrationCapture()
                window.orderOut(nil)
                self.fullThrottleWindow = nil
                self.finishFullThrottle(peak: peakRate)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        fullThrottleTimer = timer
    }

    private func finishFullThrottle(peak: Double) {
        if peak > 0 {
            tracker.setVMax(peak)
            let done = NSAlert()
            done.messageText = "Kalibrierung abgeschlossen"
            done.informativeText = String(
                format: "Peak: %.1f counts/s\nDieser Wert entspricht jetzt 10 km/h (volle Auslenkung).",
                peak
            )
            done.addButton(withTitle: "OK")
            done.runModal()
        } else {
            let fail = NSAlert()
            fail.messageText = "Keine Bewegung erkannt"
            fail.informativeText = "Bitte erneut versuchen und während der 10 Sekunden ohne Pause Maus oder Trackpad bewegen."
            fail.addButton(withTitle: "OK")
            fail.runModal()
        }
    }

    // MARK: - Strecken-Kalibrierung

    func startDistance() {
        let intro = NSAlert()
        intro.messageText = "Strecken-Kalibrierung"
        intro.informativeText = "Gib die Strecke in Metern ein, die du anschließend zurücklegst:"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.stringValue = "100"
        input.placeholderString = "Meter"
        intro.accessoryView = input
        intro.addButton(withTitle: "Aufnahme starten")
        intro.addButton(withTitle: "Abbrechen")

        guard intro.runModal() == .alertFirstButtonReturn else { return }

        let sanitized = input.stringValue.replacingOccurrences(of: ",", with: ".")
        guard let meters = Double(sanitized), meters > 0 else {
            let err = NSAlert()
            err.messageText = "Ungültige Eingabe"
            err.informativeText = "Bitte eine positive Zahl in Metern eingeben."
            err.addButton(withTitle: "OK")
            err.runModal()
            return
        }

        tracker.beginCalibrationCapture()

        let rec = NSAlert()
        rec.messageText = "Aufnahme läuft (\(formatMeters(meters)))"
        rec.informativeText = """
        Fahre nun die Strecke und klicke anschließend auf „Beenden".
        Während der Aufnahme zählt die Bewegung NICHT in Fahrt/Gesamt.
        """
        rec.addButton(withTitle: "Beenden")
        rec.addButton(withTitle: "Abbrechen")
        let response = rec.runModal()

        let counts = tracker.endCalibrationCapture()

        guard response == .alertFirstButtonReturn else { return }
        guard counts > 0 else {
            let fail = NSAlert()
            fail.messageText = "Keine Bewegung erfasst"
            fail.informativeText = "Während der Aufnahme wurden keine Mausbewegungen registriert."
            fail.addButton(withTitle: "OK")
            fail.runModal()
            return
        }

        let vMax = counts * 10_000.0 / (3600.0 * meters)
        tracker.setVMax(vMax)

        let done = NSAlert()
        done.messageText = "Kalibrierung abgeschlossen"
        done.informativeText = String(
            format: "Counts gesamt: %.0f bei %.1f m\nNeuer vMax: %.1f counts/s",
            counts, meters, vMax
        )
        done.addButton(withTitle: "OK")
        done.runModal()
    }

    private func formatMeters(_ value: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 1
        return (f.string(from: NSNumber(value: value)) ?? "\(value)") + " m"
    }
}
