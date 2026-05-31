import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: PersistenceStore!
    private var tracker: DistanceTracker!
    private var eventTap: EventTap!
    private var calibration: CalibrationController!
    private var statsWindow: StatsWindowController!
    private var menuBar: MenuBarController!
    private var permissionPollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = PersistenceStore()
        tracker = DistanceTracker(store: store)
        calibration = CalibrationController(tracker: tracker)
        statsWindow = StatsWindowController(tracker: tracker)
        menuBar = MenuBarController(tracker: tracker, calibration: calibration, stats: statsWindow)
        eventTap = EventTap(tracker: tracker)

        if isProcessTrusted(prompting: true) {
            if !eventTap.start() {
                showPermissionAlert()
            }
        } else {
            showPermissionAlert()
            startPermissionPoll()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        tracker?.flush()
        eventTap?.stop()
    }

    @objc private func systemDidWake() {
        eventTap?.stop()
        _ = eventTap?.start()
    }

    private func isProcessTrusted(prompting: Bool) -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: prompting] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func startPermissionPoll() {
        permissionPollTimer?.invalidate()
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if AXIsProcessTrusted() {
                timer.invalidate()
                self.permissionPollTimer = nil
                _ = self.eventTap.start()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionPollTimer = timer
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Bedienungshilfen erforderlich"
        alert.informativeText = """
        Mika+ Cursormeter benötigt Zugriff auf die Bedienungshilfen, um Mausbewegungen zu zählen.
        Bitte aktiviere die App unter
        Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen.
        """
        alert.addButton(withTitle: "Systemeinstellungen öffnen")
        alert.addButton(withTitle: "Später")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
