import AppKit

final class StatsWindowController: NSObject, NSWindowDelegate {
    private let tracker: DistanceTracker
    private let window: NSWindow
    private var refreshTimer: Timer?

    private let speedValue = StatsWindowController.makeValueLabel()
    private let tripValue = StatsWindowController.makeValueLabel()
    private let weekValue = StatsWindowController.makeValueLabel()
    private let monthValue = StatsWindowController.makeValueLabel()
    private let yearValue = StatsWindowController.makeValueLabel()
    private let totalValue = StatsWindowController.makeValueLabel()
    private let peakSpeedValue = StatsWindowController.makeValueLabel()
    private let bestDayValue = StatsWindowController.makeValueLabel()
    private let activeDaysValue = StatsWindowController.makeValueLabel()
    private let vMaxValue = StatsWindowController.makeValueLabel()
    private let chartView = HistoryChartView()
    private var selectedRange: DistanceTracker.HistoryRange = .days
    private let rangeControl = NSSegmentedControl(
        labels: ["Tage", "Wochen", "Monate", "Jahre"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )

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

    init(tracker: DistanceTracker) {
        self.tracker = tracker
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 664),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mika+ Cursormeter — Statistik"
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        super.init()
        window.delegate = self
        buildContent()
    }

    func show() {
        refresh()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startRefresh()
    }

    // MARK: - Layout

    private func buildContent() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 664))
        content.autoresizingMask = [.width, .height]
        content.wantsLayer = true

        let title = NSTextField(labelWithString: "Statistik")
        title.font = .systemFont(ofSize: 22, weight: .bold)
        title.frame = NSRect(x: 24, y: 616, width: 412, height: 30)
        content.addSubview(title)

        let subtitle = NSTextField(labelWithString: "Mausbewegung als Fahrt — kalibriert via vMax")
        subtitle.font = .systemFont(ofSize: 12, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 24, y: 596, width: 412, height: 18)
        content.addSubview(subtitle)

        let card = NSView(frame: NSRect(x: 24, y: 336, width: 412, height: 246))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(white: 1, alpha: 0.04).cgColor
        card.layer?.cornerRadius = 12
        card.layer?.borderColor = NSColor(white: 1, alpha: 0.08).cgColor
        card.layer?.borderWidth = 1
        content.addSubview(card)

        let rows: [(String, NSTextField)] = [
            ("Tempo", speedValue),
            ("Fahrt heute", tripValue),
            ("Diese Woche", weekValue),
            ("Dieser Monat", monthValue),
            ("Dieses Jahr", yearValue),
            ("Gesamt", totalValue),
            ("Höchsttempo", peakSpeedValue),
            ("Beste Tagesfahrt", bestDayValue),
            ("Aktive Tage", activeDaysValue),
            ("vMax", vMaxValue)
        ]

        let rowH: CGFloat = 22
        let topPad: CGFloat = 14
        for (i, row) in rows.enumerated() {
            let y = card.bounds.height - topPad - CGFloat(i) * rowH - 18
            let key = NSTextField(labelWithString: row.0)
            key.font = .systemFont(ofSize: 12, weight: .medium)
            key.textColor = .secondaryLabelColor
            key.frame = NSRect(x: 18, y: y, width: 180, height: 18)
            card.addSubview(key)
            row.1.frame = NSRect(x: 200, y: y, width: 200, height: 18)
            card.addSubview(row.1)
        }

        let chartTitle = NSTextField(labelWithString: "Verlauf")
        chartTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        chartTitle.frame = NSRect(x: 24, y: 306, width: 412, height: 18)
        content.addSubview(chartTitle)

        rangeControl.selectedSegment = selectedRange.rawValue
        rangeControl.target = self
        rangeControl.action = #selector(rangeChanged(_:))
        rangeControl.frame = NSRect(x: 24, y: 272, width: 412, height: 26)
        rangeControl.autoresizingMask = [.width]
        content.addSubview(rangeControl)

        chartView.frame = NSRect(x: 24, y: 70, width: 412, height: 192)
        chartView.autoresizingMask = [.width]
        content.addSubview(chartView)

        let resetPeak = NSButton(title: "Höchsttempo zurücksetzen", target: self, action: #selector(resetPeakSpeed))
        resetPeak.bezelStyle = .rounded
        resetPeak.frame = NSRect(x: 24, y: 24, width: 220, height: 28)
        content.addSubview(resetPeak)

        window.contentView = content
    }

    private static func makeValueLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "—")
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        label.alignment = .right
        return label
    }

    // MARK: - Refresh

    private func startRefresh() {
        guard refreshTimer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func stopRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func refresh() {
        tracker.checkDayRollover()
        let s = tracker.stats()

        speedValue.stringValue = "\(speedFmt(s.speedKmh)) km/h"
        tripValue.stringValue = "\(kmFmt(s.tripKm)) km"
        weekValue.stringValue = "\(kmFmt(s.thisWeekKm)) km"
        monthValue.stringValue = "\(kmFmt(s.thisMonthKm)) km"
        yearValue.stringValue = "\(kmFmt(s.thisYearKm)) km"
        totalValue.stringValue = "\(kmFmt(s.totalKm)) km"
        peakSpeedValue.stringValue = "\(speedFmt(s.peakSpeedKmh)) km/h"
        bestDayValue.stringValue = "\(kmFmt(s.bestDayKm)) km"
        activeDaysValue.stringValue = "\(s.activeDayCount)"
        vMaxValue.stringValue = String(format: "%.0f counts/s", s.vMax)

        chartView.buckets = tracker.history(for: selectedRange)
        chartView.needsDisplay = true
    }

    private func kmFmt(_ value: Double) -> String {
        kmFormatter.string(from: NSNumber(value: value)) ?? "0,00"
    }

    private func speedFmt(_ value: Double) -> String {
        speedFormatter.string(from: NSNumber(value: value)) ?? "0,0"
    }

    @objc private func rangeChanged(_ sender: NSSegmentedControl) {
        selectedRange = DistanceTracker.HistoryRange(rawValue: sender.selectedSegment) ?? .days
        refresh()
    }

    @objc private func resetPeakSpeed() {
        let alert = NSAlert()
        alert.messageText = "Höchsttempo zurücksetzen?"
        alert.informativeText = "Der gespeicherte Peak-Wert wird auf 0 gesetzt."
        alert.addButton(withTitle: "Zurücksetzen")
        alert.addButton(withTitle: "Abbrechen")
        if alert.runModal() == .alertFirstButtonReturn {
            tracker.resetPeakSpeed()
            refresh()
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        stopRefresh()
    }
}

// MARK: - Chart

final class HistoryChartView: NSView {
    var buckets: [DistanceTracker.HistoryBucket] = []

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let bounds = self.bounds

        // Hintergrund Card
        let card = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        NSColor(white: 1, alpha: 0.04).setFill()
        card.fill()
        NSColor(white: 1, alpha: 0.08).setStroke()
        card.lineWidth = 1
        card.stroke()

        guard !buckets.isEmpty else { return }
        let maxKm = max(buckets.map { $0.km }.max() ?? 0, 0.001)

        let innerX: CGFloat = 16
        let innerWidth = bounds.width - innerX * 2
        let labelHeight: CGFloat = 18
        let valueHeight: CGFloat = 14
        let topPadding: CGFloat = 12
        let chartHeight = bounds.height - labelHeight - valueHeight - topPadding

        let n = CGFloat(buckets.count)
        let slot = innerWidth / n
        let barWidth = slot * 0.62
        let mint = NSColor(red: 0.30, green: 0.82, blue: 0.65, alpha: 1.0)
        let mintDim = mint.withAlphaComponent(0.30)

        let baseY = labelHeight + valueHeight

        // Baseline
        ctx.setStrokeColor(NSColor(white: 1, alpha: 0.08).cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: NSPoint(x: innerX, y: baseY))
        ctx.addLine(to: NSPoint(x: innerX + innerWidth, y: baseY))
        ctx.strokePath()

        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let todayLabelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: mint
        ]

        // Bei vielen Balken nur jedes k-te Achsenlabel zeichnen (gegen Überlappung),
        // der aktuelle Balken wird immer beschriftet. Werte über den Balken nur,
        // wenn der Slot breit genug ist.
        let labelStep = max(1, Int(ceil(n / 12.0)))
        let showValues = slot > 24

        for (i, bucket) in buckets.enumerated() {
            let cx = innerX + slot * CGFloat(i) + slot / 2
            let h = chartHeight * CGFloat(bucket.km / maxKm)
            let rect = NSRect(
                x: cx - barWidth / 2,
                y: baseY,
                width: barWidth,
                height: max(2, h)
            )
            let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
            (bucket.km > 0 ? mint : mintDim).setFill()
            path.fill()

            // Wert nur anzeigen wenn signifikant und Slot breit genug
            if showValues && bucket.km > 0.005 {
                let valText = NSAttributedString(
                    string: String(format: "%.2f", bucket.km),
                    attributes: valueAttrs
                )
                let vs = valText.size()
                valText.draw(at: NSPoint(x: cx - vs.width / 2, y: baseY + max(2, h) + 2))
            }

            if i % labelStep == 0 || bucket.isCurrent {
                let attrs = bucket.isCurrent ? todayLabelAttrs : labelAttrs
                let lbl = NSAttributedString(string: bucket.label, attributes: attrs)
                let ls = lbl.size()
                lbl.draw(at: NSPoint(x: cx - ls.width / 2, y: 2))
            }
        }
    }
}
