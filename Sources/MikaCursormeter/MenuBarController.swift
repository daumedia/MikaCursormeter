import AppKit
import ServiceManagement

final class MenuBarController: NSObject {
    private let tracker: DistanceTracker
    private let calibration: CalibrationController
    private let stats: StatsWindowController
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var updateTimer: Timer?

    private let headerItem = NSMenuItem(title: "Mika+ Cursormeter", action: nil, keyEquivalent: "")
    private let speedItem = NSMenuItem(title: "Tempo: 0,0 km/h", action: nil, keyEquivalent: "")
    private let tripItem = NSMenuItem(title: "Fahrt heute: 0,00 km", action: nil, keyEquivalent: "")
    private let totalItem = NSMenuItem(title: "Gesamt: 0,00 km", action: nil, keyEquivalent: "")
    private let vMaxItem = NSMenuItem(title: "vMax: 1000 counts/s", action: nil, keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Beim Anmelden starten", action: nil, keyEquivalent: "")

    private let kmFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    private let speedFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        return f
    }()

    init(tracker: DistanceTracker, calibration: CalibrationController, stats: StatsWindowController) {
        self.tracker = tracker
        self.calibration = calibration
        self.stats = stats
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureStatusButton()
        buildMenu()
        statusItem.menu = menu
        startUpdates()
        refresh()
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        let symbol = NSImage(systemSymbolName: "speedometer", accessibilityDescription: "Mika+ Cursormeter")?
            .withSymbolConfiguration(config)
        symbol?.isTemplate = true
        button.image = symbol
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.font = .menuBarFont(ofSize: 0)
    }

    private func buildMenu() {
        headerItem.isEnabled = false
        speedItem.isEnabled = false
        tripItem.isEnabled = false
        totalItem.isEnabled = false
        vMaxItem.isEnabled = false

        menu.addItem(headerItem)
        menu.addItem(.separator())
        menu.addItem(speedItem)
        menu.addItem(tripItem)
        menu.addItem(totalItem)
        menu.addItem(.separator())
        menu.addItem(vMaxItem)
        menu.addItem(.separator())

        let statsItem = NSMenuItem(
            title: "Statistik öffnen…",
            action: #selector(openStats),
            keyEquivalent: ""
        )
        statsItem.target = self
        menu.addItem(statsItem)

        menu.addItem(.separator())

        let fullThrottle = NSMenuItem(
            title: "Vollgas-Kalibrierung…",
            action: #selector(startFullThrottle),
            keyEquivalent: ""
        )
        fullThrottle.target = self
        menu.addItem(fullThrottle)

        let distance = NSMenuItem(
            title: "Strecken-Kalibrierung…",
            action: #selector(startDistance),
            keyEquivalent: ""
        )
        distance.target = self
        menu.addItem(distance)

        menu.addItem(.separator())

        let resetTrip = NSMenuItem(
            title: "Heutige Fahrt zurücksetzen",
            action: #selector(resetTrip),
            keyEquivalent: ""
        )
        resetTrip.target = self
        menu.addItem(resetTrip)

        let resetTotal = NSMenuItem(
            title: "Gesamt-km zurücksetzen…",
            action: #selector(resetTotal),
            keyEquivalent: ""
        )
        resetTotal.target = self
        menu.addItem(resetTotal)

        menu.addItem(.separator())

        loginItem.target = self
        loginItem.action = #selector(toggleLoginItem)
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Beenden",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)
    }

    private func startUpdates() {
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
    }

    private func refresh() {
        tracker.checkDayRollover()
        let snap = tracker.snapshot()
        let vMax = tracker.currentVMax

        let totalStr = kmFormatter.string(from: NSNumber(value: snap.totalKm)) ?? "0,00"
        let tripStr = kmFormatter.string(from: NSNumber(value: snap.tripKm)) ?? "0,00"
        let speedStr = speedFormatter.string(from: NSNumber(value: snap.speedKmh)) ?? "0,0"

        statusItem.button?.title = " \(totalStr) km"
        speedItem.title = "Tempo: \(speedStr) km/h"
        tripItem.title = "Fahrt heute: \(tripStr) km"
        totalItem.title = "Gesamt: \(totalStr) km"
        vMaxItem.title = String(format: "vMax: %.0f counts/s  (≙ 10 km/h)", vMax)
        loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Login-Item konnte nicht geändert werden"
            alert.informativeText = """
            \(error.localizedDescription)

            Hinweis: Diese Funktion ist nur verfügbar, wenn Mika+ Cursormeter aus dem Programme-Ordner gestartet wurde (nicht aus `swift run`).
            """
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
        refresh()
    }

    @objc private func openStats() {
        stats.show()
    }

    @objc private func startFullThrottle() {
        calibration.startFullThrottle()
        refresh()
    }

    @objc private func startDistance() {
        calibration.startDistance()
        refresh()
    }

    @objc private func resetTrip() {
        tracker.resetTrip()
        refresh()
    }

    @objc private func resetTotal() {
        let alert = NSAlert()
        alert.messageText = "Gesamt-km zurücksetzen?"
        alert.informativeText = "Dieser Schritt kann nicht rückgängig gemacht werden."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Zurücksetzen")
        alert.addButton(withTitle: "Abbrechen")
        if alert.runModal() == .alertFirstButtonReturn {
            tracker.resetTotal()
            refresh()
        }
    }
}
