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

    struct Stats {
        let speedKmh: Double
        let tripKm: Double
        let totalKm: Double
        let peakSpeedKmh: Double
        let bestDayKm: Double
        let activeDayCount: Int
        let vMax: Double
        let lastDays: [(label: String, isoDate: String, km: Double, isToday: Bool)]
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

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekdayLabels = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
        var days: [(label: String, isoDate: String, km: Double, isToday: Bool)] = []
        for offset in (0..<14).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = Self.isoDayFormatter.string(from: date)
            let km: Double
            if offset == 0 {
                km = tripKm + (history[key] ?? 0)
            } else {
                km = history[key] ?? 0
            }
            let weekday = calendar.component(.weekday, from: date)
            days.append((label: weekdayLabels[weekday - 1], isoDate: key, km: km, isToday: offset == 0))
        }

        return Stats(
            speedKmh: speedKmh,
            tripKm: tripKm,
            totalKm: totalKm,
            peakSpeedKmh: peakSpeedKmh,
            bestDayKm: bestDayKm,
            activeDayCount: activeDayCount,
            vMax: vMax,
            lastDays: days
        )
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
