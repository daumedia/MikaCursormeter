import Foundation

final class DistanceTracker {
    private let store: PersistenceStore
    private let lock = NSLock()

    private var totalKm: Double
    private var tripKm: Double
    private var tripDate: Date
    private var vMax: Double
    private var peakSpeedKmh: Double

    private static let isoDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.setLocalizedDateFormatFromTemplate("MMM")
        return f
    }()

    private struct SpeedSample {
        let timestamp: TimeInterval
        let counts: Double
    }
    private var speedBuffer: [SpeedSample] = []
    private let speedWindow: TimeInterval = 1.0

    private var calibrationCapture: Double?

    private var lastFlush: TimeInterval = 0
    private let flushInterval: TimeInterval = 1.0

    struct Snapshot {
        let speedKmh: Double
        let tripKm: Double
        let totalKm: Double
    }

    enum HistoryRange: Int, CaseIterable {
        case days, weeks, months, years
    }

    struct HistoryBucket {
        let label: String   // z.B. "21", "KW25", "Jun", "2026"
        let km: Double
        let isCurrent: Bool // aktueller Tag/Woche/Monat/Jahr → Hervorhebung
    }

    struct Stats {
        let speedKmh: Double
        let tripKm: Double
        let totalKm: Double
        let peakSpeedKmh: Double
        let bestDayKm: Double
        let activeDayCount: Int
        let vMax: Double
        let thisWeekKm: Double
        let thisMonthKm: Double
        let thisYearKm: Double
    }

    init(store: PersistenceStore) {
        self.store = store
        self.totalKm = store.totalKm
        self.tripKm = store.tripKm
        self.tripDate = store.tripDate
        self.vMax = store.vMax
        self.peakSpeedKmh = store.peakSpeedKmh
    }

    var currentVMax: Double {
        lock.lock(); defer { lock.unlock() }
        return vMax
    }

    func setVMax(_ value: Double) {
        guard value > 0 else { return }
        lock.lock()
        vMax = value
        store.vMax = value
        lock.unlock()
    }

    func addCounts(_ magnitude: Double) {
        guard magnitude > 0 else { return }
        lock.lock()
        defer { lock.unlock() }

        let now = Date().timeIntervalSinceReferenceDate

        speedBuffer.append(SpeedSample(timestamp: now, counts: magnitude))
        let cutoff = now - speedWindow
        while let first = speedBuffer.first, first.timestamp < cutoff {
            speedBuffer.removeFirst()
        }

        if calibrationCapture != nil {
            calibrationCapture! += magnitude
            return
        }

        let kmIncrement = magnitude * 10.0 / (3600.0 * vMax)
        totalKm += kmIncrement
        tripKm += kmIncrement

        let countsLastSecond = speedBuffer.reduce(0.0) { $0 + $1.counts } / speedWindow
        let liveSpeedKmh = countsLastSecond / vMax * 10.0
        if liveSpeedKmh > peakSpeedKmh {
            peakSpeedKmh = liveSpeedKmh
        }

        if now - lastFlush > flushInterval {
            lastFlush = now
            store.totalKm = totalKm
            store.tripKm = tripKm
            store.tripDate = tripDate
            store.peakSpeedKmh = peakSpeedKmh
        }
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }

        let now = Date().timeIntervalSinceReferenceDate
        let cutoff = now - speedWindow
        while let first = speedBuffer.first, first.timestamp < cutoff {
            speedBuffer.removeFirst()
        }
        let countsLastWindow = speedBuffer.reduce(0.0) { $0 + $1.counts }
        let countsPerSecond = countsLastWindow / speedWindow
        let speedKmh = countsPerSecond / vMax * 10.0

        return Snapshot(speedKmh: speedKmh, tripKm: tripKm, totalKm: totalKm)
    }

    func checkDayRollover() {
        lock.lock()
        defer { lock.unlock() }

        if !Calendar.current.isDateInToday(tripDate) {
            if tripKm > 0 {
                let key = Self.isoDayFormatter.string(from: tripDate)
                var history = store.dailyHistory
                history[key] = (history[key] ?? 0) + tripKm
                store.dailyHistory = history
            }
            tripKm = 0.0
            tripDate = Date()
            store.tripKm = 0
            store.tripDate = tripDate
        }
    }

    func stats() -> Stats {
        lock.lock()
        defer { lock.unlock() }

        let now = Date().timeIntervalSinceReferenceDate
        let cutoff = now - speedWindow
        while let first = speedBuffer.first, first.timestamp < cutoff {
            speedBuffer.removeFirst()
        }
        let countsLastWindow = speedBuffer.reduce(0.0) { $0 + $1.counts } / speedWindow
        let speedKmh = countsLastWindow / vMax * 10.0

        let history = store.dailyHistory
        let bestArchived = history.values.max() ?? 0
        let bestDayKm = max(bestArchived, tripKm)

        let todayKey = Self.isoDayFormatter.string(from: Date())
        var activeDayCount = history.filter { $0.value > 0 }.count
        if tripKm > 0 && history[todayKey] == nil { activeDayCount += 1 }

        // Summen für aktuelle Woche / Monat / Jahr. tripKm (heutige Fahrt) ist noch
        // nicht in dailyHistory und wird zu jeder aktuellen Periode addiert.
        let calendar = Calendar.current
        let nowDate = Date()
        let entries = Self.datedEntries(from: history)
        let weekComps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: nowDate)
        let monthComps = calendar.dateComponents([.year, .month], from: nowDate)
        let currentYear = calendar.component(.year, from: nowDate)

        var thisWeekKm = tripKm
        var thisMonthKm = tripKm
        var thisYearKm = tripKm
        for entry in entries {
            if calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: entry.date) == weekComps {
                thisWeekKm += entry.km
            }
            if calendar.dateComponents([.year, .month], from: entry.date) == monthComps {
                thisMonthKm += entry.km
            }
            if calendar.component(.year, from: entry.date) == currentYear {
                thisYearKm += entry.km
            }
        }

        return Stats(
            speedKmh: speedKmh,
            tripKm: tripKm,
            totalKm: totalKm,
            peakSpeedKmh: peakSpeedKmh,
            bestDayKm: bestDayKm,
            activeDayCount: activeDayCount,
            vMax: vMax,
            thisWeekKm: thisWeekKm,
            thisMonthKm: thisMonthKm,
            thisYearKm: thisYearKm
        )
    }

    // MARK: - Verlauf (Tage / Wochen / Monate / Jahre)

    /// Aggregierte Verlaufsdaten für den gewählten Zeitraum.
    func history(for range: HistoryRange) -> [HistoryBucket] {
        lock.lock()
        defer { lock.unlock() }

        let entries = Self.datedEntries(from: store.dailyHistory)
        let calendar = Calendar.current
        let now = Date()

        switch range {
        case .days:   return dayBuckets(entries: entries, calendar: calendar, now: now, count: 30)
        case .weeks:  return weekBuckets(entries: entries, calendar: calendar, now: now, count: 12)
        case .months: return monthBuckets(entries: entries, calendar: calendar, now: now, count: 12)
        case .years:  return yearBuckets(entries: entries, calendar: calendar, now: now)
        }
    }

    /// Wandelt die ISO-Tageskeys der Historie in (Date, km)-Paare zurück.
    private static func datedEntries(from history: [String: Double]) -> [(date: Date, km: Double)] {
        history.compactMap { key, km in
            guard let date = isoDayFormatter.date(from: key) else { return nil }
            return (date: date, km: km)
        }
    }

    // Helfer laufen unter `lock` (lesen tripKm direkt) und nehmen den Lock NICHT erneut.

    private func dayBuckets(entries: [(date: Date, km: Double)], calendar: Calendar, now: Date, count: Int) -> [HistoryBucket] {
        let today = calendar.startOfDay(for: now)
        var sums: [Date: Double] = [:]
        for entry in entries {
            sums[calendar.startOfDay(for: entry.date), default: 0] += entry.km
        }
        var buckets: [HistoryBucket] = []
        for offset in (0..<count).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            var km = sums[date] ?? 0
            if offset == 0 { km += tripKm }
            buckets.append(HistoryBucket(label: "\(calendar.component(.day, from: date))", km: km, isCurrent: offset == 0))
        }
        return buckets
    }

    private func weekBuckets(entries: [(date: Date, km: Double)], calendar: Calendar, now: Date, count: Int) -> [HistoryBucket] {
        var sums: [DateComponents: Double] = [:]
        for entry in entries {
            sums[calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: entry.date), default: 0] += entry.km
        }
        var buckets: [HistoryBucket] = []
        for offset in (0..<count).reversed() {
            guard let date = calendar.date(byAdding: .weekOfYear, value: -offset, to: now) else { continue }
            let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            var km = sums[comps] ?? 0
            if offset == 0 { km += tripKm }
            buckets.append(HistoryBucket(label: "KW\(comps.weekOfYear ?? 0)", km: km, isCurrent: offset == 0))
        }
        return buckets
    }

    private func monthBuckets(entries: [(date: Date, km: Double)], calendar: Calendar, now: Date, count: Int) -> [HistoryBucket] {
        var sums: [DateComponents: Double] = [:]
        for entry in entries {
            sums[calendar.dateComponents([.year, .month], from: entry.date), default: 0] += entry.km
        }
        var buckets: [HistoryBucket] = []
        for offset in (0..<count).reversed() {
            guard let date = calendar.date(byAdding: .month, value: -offset, to: now) else { continue }
            let comps = calendar.dateComponents([.year, .month], from: date)
            var km = sums[comps] ?? 0
            if offset == 0 { km += tripKm }
            buckets.append(HistoryBucket(label: Self.monthFormatter.string(from: date), km: km, isCurrent: offset == 0))
        }
        return buckets
    }

    private func yearBuckets(entries: [(date: Date, km: Double)], calendar: Calendar, now: Date) -> [HistoryBucket] {
        var sums: [Int: Double] = [:]
        for entry in entries {
            sums[calendar.component(.year, from: entry.date), default: 0] += entry.km
        }
        let currentYear = calendar.component(.year, from: now)
        let earliestYear = min(sums.keys.min() ?? currentYear, currentYear)
        var buckets: [HistoryBucket] = []
        for year in earliestYear...currentYear {
            var km = sums[year] ?? 0
            if year == currentYear { km += tripKm }
            buckets.append(HistoryBucket(label: "\(year)", km: km, isCurrent: year == currentYear))
        }
        return buckets
    }

    func resetPeakSpeed() {
        lock.lock()
        peakSpeedKmh = 0
        store.peakSpeedKmh = 0
        lock.unlock()
    }

    func resetTrip() {
        lock.lock()
        tripKm = 0
        tripDate = Date()
        store.tripKm = 0
        store.tripDate = tripDate
        lock.unlock()
    }

    func resetTotal() {
        lock.lock()
        totalKm = 0
        store.totalKm = 0
        lock.unlock()
    }

    func beginCalibrationCapture() {
        lock.lock()
        calibrationCapture = 0
        lock.unlock()
    }

    func peekCalibrationCapture() -> Double {
        lock.lock(); defer { lock.unlock() }
        return calibrationCapture ?? 0
    }

    func endCalibrationCapture() -> Double {
        lock.lock(); defer { lock.unlock() }
        let result = calibrationCapture ?? 0
        calibrationCapture = nil
        return result
    }

    func flush() {
        lock.lock()
        store.totalKm = totalKm
        store.tripKm = tripKm
        store.tripDate = tripDate
        lock.unlock()
    }
}
