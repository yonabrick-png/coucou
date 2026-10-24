#if !APPSTORE
import SwiftUI

// MARK: - Redline's Overview numbers (recovery, strain, sleep, key metrics)

extension GarminStore {
    /// What Redline's Overview tab shows, read from the same data.json: the three rings
    /// (recovery = Garmin readiness, strain 0–21, sleep % of need) with their last 7 days,
    /// and the key metric series for the sparklines.
    struct Vitals: Equatable {
        struct Day: Equatable, Identifiable {
            let id: String
            let date: Date
            let recovery: Int?
            let strain: Double
            let sleep: Int?
            let isToday: Bool
        }

        var recovery: Int?
        var recoveryIsToday: Bool
        var recoveryAvg30: Double?
        var strainToday: Double
        var strainYesterday: Double?
        var strainAvg7: Double
        var sleepPerf: Int?
        var sleepHours: Double?
        var sleepNeed: Double?
        var sleepIsLastNight: Bool
        var week: [Day]
        var hrv: [Double]
        var hrvLow: Int?
        var hrvHigh: Int?
        var rhr: [Double]
        var vo2: [Double]
        var vo2Sub: String
        var load: [Double]
        var statusLabel: String
        var statusBand: String
        var statusSince: Date?
    }

    static func parseVitals(_ j: [String: Any]) -> Vitals {
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
        /// A {date: value} dictionary as values in date order.
        func series(_ dict: [String: Any], _ value: (Any) -> Double?) -> [Double] {
            dict.keys.sorted().compactMap { dict[$0].flatMap(value) }
        }

        let a = j["analytics"] as? [String: Any] ?? [:]
        let daily = a["daily"] as? [String: [String: Any]] ?? [:]
        let sleep = a["sleep"] as? [String: [String: Any]] ?? [:]
        let readiness = j["readiness"] as? [String: [String: Any]] ?? [:]
        let today = j["today"] as? [String: Any] ?? [:]
        let dates = j["dates"] as? [String] ?? readiness.keys.sorted()
        let asof = j["asof"] as? String ?? dates.last ?? ""

        let rec = today["readiness"] as? [String: Any]
        let recScores = dates.dropLast().suffix(30).compactMap { num(readiness[$0]?["score"]) }
        let strain = { (d: String) in num(daily[d]?["strain"]) ?? 0 }
        let lastSleep = sleep.keys.max()
        let sl = lastSleep.flatMap { sleep[$0] }

        let week = dates.suffix(7).compactMap { d -> Vitals.Day? in
            guard let date = day.date(from: d) else { return nil }
            return Vitals.Day(id: d, date: date,
                              recovery: num(readiness[d]?["score"]).map { Int($0) },
                              strain: strain(d),
                              sleep: num(sleep[d]?["perf"]).map { Int($0) },
                              isToday: d == asof)
        }

        let status = today["status"] as? [String: Any] ?? [:]
        let baseline = j["hrvBaseline"] as? [String: Any] ?? [:]
        let acwr = a["acwrLong"] as? [[String: Any]] ?? []
        let last7 = dates.suffix(7).map(strain)

        return Vitals(
            recovery: num(rec?["score"]).map { Int($0) },
            recoveryIsToday: (rec?["date"] as? String) == asof,
            recoveryAvg30: recScores.isEmpty ? nil : recScores.reduce(0, +) / Double(recScores.count),
            strainToday: strain(asof),
            strainYesterday: dates.count > 1 ? num(daily[dates[dates.count - 2]]?["strain"]) : nil,
            strainAvg7: last7.isEmpty ? 0 : last7.reduce(0, +) / Double(last7.count),
            sleepPerf: num(sl?["perf"]).map { Int($0) },
            sleepHours: num(sl?["hours"]),
            sleepNeed: num(sl?["needH"]),
            sleepIsLastNight: lastSleep == asof,
            week: week,
            hrv: series(j["hrv"] as? [String: Any] ?? [:], num),
            hrvLow: num(baseline["low"]).map { Int($0) },
            hrvHigh: num(baseline["high"]).map { Int($0) },
            rhr: series(sleep, { num(($0 as? [String: Any])?["rhr"]) }),
            vo2: series(j["vo2max"] as? [String: Any] ?? [:], num),
            vo2Sub: (today["vo2"] as? [String: Any])?["sub"] as? String ?? "",
            load: acwr.compactMap { num($0["v"]) },
            statusLabel: status["label"] as? String ?? "",
            statusBand: status["band"] as? String ?? "",
            statusSince: (status["since"] as? String).flatMap { day.date(from: $0) })
    }
}
#endif
