import Foundation

final class PersistenceStore {
    private let defaults: UserDefaults

    private enum Key {
        static let vMax = "cursormeter.vMax"
        static let totalKm = "cursormeter.totalKm"
        static let tripKm = "cursormeter.tripKm"
        static let tripDate = "cursormeter.tripDate"
        static let peakSpeed = "cursormeter.peakSpeedKmh"
        static let dailyHistory = "cursormeter.dailyHistory"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var vMax: Double {
        get {
            let stored = defaults.double(forKey: Key.vMax)
            return stored > 0 ? stored : 1000.0
        }
        set { defaults.set(newValue, forKey: Key.vMax) }
    }

    var totalKm: Double {
        get { defaults.double(forKey: Key.totalKm) }
        set { defaults.set(newValue, forKey: Key.totalKm) }
    }

    var tripKm: Double {
        get { defaults.double(forKey: Key.tripKm) }
        set { defaults.set(newValue, forKey: Key.tripKm) }
    }

    var tripDate: Date {
        get { defaults.object(forKey: Key.tripDate) as? Date ?? Date() }
        set { defaults.set(newValue, forKey: Key.tripDate) }
    }

    var peakSpeedKmh: Double {
        get { defaults.double(forKey: Key.peakSpeed) }
        set { defaults.set(newValue, forKey: Key.peakSpeed) }
    }

    var dailyHistory: [String: Double] {
        get {
            guard let data = defaults.data(forKey: Key.dailyHistory),
                  let dict = try? JSONDecoder().decode([String: Double].self, from: data)
            else { return [:] }
            return dict
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.dailyHistory)
            }
        }
    }
}
