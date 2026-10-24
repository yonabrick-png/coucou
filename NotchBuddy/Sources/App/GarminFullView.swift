#if !APPSTORE
import SwiftUI

// MARK: - Garmin tab (the big view, GitHub build only)

/// Yehonathan's Redline in the notch, styled like its WHOOP-style Overview: recovery, strain and
/// sleep rings with the last 7 days, the insight banner and key metrics, plus tabs for the next
/// race, recent training and personal records.
struct GarminFullView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store = GarminStore.shared
    @Environment(\.islandViewActive) private var viewActive

    enum Section: String, CaseIterable { case overview, race, training, records }
    @State private var section: Section = .overview
    /// Rings sweep in each time the tab opens, like Redline's.
    @State private var ringsShown = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            CardBackground(wash: nil)
            Group {
                if let s = store.snapshot, let d = store.details, let v = store.vitals {
                    VStack(alignment: .leading, spacing: 8) {
                        topBar
                        switch section {
                        case .overview: overview(v, d)
                        case .race:     ScrollView(.vertical, showsIndicators: false) { raceSection(s, d) }
                        case .training: ScrollView(.vertical, showsIndicators: false) { trainingSection(d) }
                        case .records:  ScrollView(.vertical, showsIndicators: false) { recordsSection(d) }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    VStack(spacing: 8) {
                        Spacer(minLength: 0)
                        Image(systemName: "figure.run").font(.system(size: 24)).foregroundColor(Self.red)
                        Text("No Garmin data yet")
                            .font(.system(size: 12)).foregroundColor(Self.text2)
                        Button(String(localized: "Get it now")) { store.fetchIfStale(force: true) }
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(Self.red)
                            .buttonStyle(.plain)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            // Clear Mochi and the badge beside him
            .padding(.leading, 104)
            .padding(.trailing, 12)
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
        .padding(.bottom, 10)
        .onAppear {
            store.refresh()
            store.fetchIfStale()
            if viewActive { showRings() }
        }
        .onChange(of: viewActive) { _, active in
            if active { showRings() } else { ringsShown = false }
        }
    }

    private func showRings() {
        ringsShown = false
        withAnimation(.easeOut(duration: 0.9).delay(0.15)) { ringsShown = true }
    }

    // MARK: Redline palette (its dark theme)

    static let surface = Color(hex: "#121519")
    static let border  = Color(hex: "#232930")
    static let text1   = Color(hex: "#F1F4F6")
    static let text2   = Color(hex: "#A9B3BD")
    static let text3   = Color(hex: "#6C7681")
    static let good    = Color(hex: "#19D27A")
    static let mid     = Color(hex: "#F4C430")
    static let red     = Color(hex: "#FF4D5E")
    static let strain  = Color(hex: "#2F9BFF")
    static let sleep   = Color(hex: "#9097FF")

    /// WHOOP bands, as on Redline: 67+ green, 34+ yellow, below red.
    static func recoveryColor(_ v: Int?) -> Color {
        guard let v else { return text3 }
        return v >= 67 ? good : v >= 34 ? mid : red
    }

    // MARK: Top bar: wordmark, tabs, updated

    private var topBar: some View {
        HStack(spacing: 4) {
            (Text("REDLIN").foregroundColor(Self.text1) + Text("E").foregroundColor(Self.red))
                .font(.system(size: 13, weight: .heavy).width(.condensed))
                .tracking(0.4)
                .padding(.trailing, 6)
            tab(.overview, "circle", String(localized: "Overview"))
            tab(.race, "flag", String(localized: "Races"))
            tab(.training, "waveform.path.ecg", String(localized: "Activity"))
            tab(.records, "medal", String(localized: "Records"))
            Spacer(minLength: 4)
            GarminUpdatedLine()
            Button { store.openDashboard() } label: {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(Self.text2)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.white.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .help(String(localized: "Open the Redline dashboard"))
        }
    }

    private func tab(_ s: Section, _ icon: String, _ title: String) -> some View {
        let on = section == s
        return Button { withAnimation(.snappy(duration: 0.2)) { section = s } } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 8.5, weight: .semibold))
                Text(title).font(.system(size: 10.5, weight: on ? .semibold : .medium))
            }
            .foregroundColor(on ? Self.text1 : Self.text2)
            .padding(.horizontal, 8)
            .frame(height: 21)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(on ? Color(hex: "#20252B") : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(NowPlayingPressStyle())
    }

    // MARK: Overview: rings, banner, key metrics

    private func overview(_ v: GarminStore.Vitals, _ d: GarminStore.Details) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                recoveryCard(v)
                strainCard(v)
                sleepCard(v)
            }
            banner(v, d)
            HStack(spacing: 8) {
                metrics(v)
            }
        }
    }

    private func recoveryCard(_ v: GarminStore.Vitals) -> some View {
        let rec = v.recovery
        let state = rec.map { $0 >= 67 ? String(localized: "Ready to perform")
                                : $0 >= 34 ? String(localized: "Moderate") : String(localized: "Take it easy") }
            ?? String(localized: "No data")
        let sub = [v.recoveryIsToday ? String(localized: "Today") : nil,
                   v.recoveryAvg30.map { String(localized: "30-day avg \(Int($0.rounded()))%") }]
            .compactMap { $0 }.joined(separator: " · ")
        return ringCard(label: String(localized: "RECOVERY"), color: Self.recoveryColor(rec),
                        value: rec.map(String.init) ?? "–", unit: "%", fill: Double(rec ?? 0) / 100,
                        state: state, sub: sub,
                        bars: v.week.map { ($0, $0.recovery.map(Double.init), Self.recoveryColor($0.recovery)) }, max: 100)
    }

    private func strainCard(_ v: GarminStore.Vitals) -> some View {
        let s = v.strainToday
        let state = s >= 18 ? String(localized: "All out") : s >= 14 ? String(localized: "Strenuous")
            : s >= 10 ? String(localized: "Moderate") : s > 0 ? String(localized: "Light") : String(localized: "Rest so far")
        let sub = String(localized: "Yesterday \(v.strainYesterday.map { String(format: "%.1f", $0) } ?? "–") · avg \(String(format: "%.1f", v.strainAvg7))")
        return ringCard(label: String(localized: "STRAIN"), color: Self.strain,
                        value: String(format: "%.1f", s), unit: String(localized: "of 21"), fill: s / 21,
                        state: state, sub: sub,
                        bars: v.week.map { ($0, $0.strain, Self.strain) }, max: 21)
    }

    private func sleepCard(_ v: GarminStore.Vitals) -> some View {
        let p = v.sleepPerf
        let state = p.map { $0 >= 85 ? String(localized: "Optimal") : $0 >= 70 ? String(localized: "Sufficient") : String(localized: "Poor") }
            ?? String(localized: "No data")
        var sub = String(localized: "No sleep recorded")
        if let h = v.sleepHours {
            sub = String(localized: "\(String(format: "%.1f", h)) h of \(v.sleepNeed.map { String(format: "%.1f", $0) } ?? "?") h")
            if v.sleepIsLastNight { sub += " · " + String(localized: "last night") }
        }
        return ringCard(label: String(localized: "SLEEP"), color: Self.sleep,
                        value: p.map(String.init) ?? "–", unit: String(localized: "% need"), fill: Double(p ?? 0) / 100,
                        state: state, sub: sub,
                        bars: v.week.map { ($0, $0.sleep.map(Double.init), Self.sleep) }, max: 100)
    }

    /// One of Redline's three ring cards: ring + label/state/sub, then the last 7 days as bars.
    private func ringCard(label: String, color: Color, value: String, unit: String, fill: Double,
                          state: String, sub: String,
                          bars: [(GarminStore.Vitals.Day, Double?, Color)], max: Double) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.07), lineWidth: 4.5)
                    Circle()
                        .trim(from: 0, to: ringsShown ? min(1, Swift.max(0, fill)) : 0)
                        .stroke(color, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: color.opacity(0.45), radius: 4)
                    VStack(spacing: -1) {
                        Text(value)
                            .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(color)
                        Text(unit)
                            .font(.system(size: 6.5, weight: .medium))
                            .foregroundColor(Self.text3)
                    }
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(color)
                    Text(state)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(Self.text1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(sub)
                        .font(.system(size: 8.5))
                        .foregroundColor(Self.text3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }

            HStack(alignment: .bottom, spacing: 0) {
                ForEach(bars, id: \.0.id) { day, val, tint in
                    VStack(spacing: 2) {
                        ZStack(alignment: .bottom) {
                            Color.clear.frame(height: 15)
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(val == nil ? Color.white.opacity(0.1) : tint)
                                .frame(width: 11, height: val.map { Swift.max(2.5, $0 / max * 15) } ?? 2.5)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                        .stroke(Color.white.opacity(day.isToday ? 0.9 : 0), lineWidth: 1)
                                )
                        }
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 7, weight: day.isToday ? .bold : .regular))
                            .foregroundColor(day.isToday ? Self.text1 : Self.text3)
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(day.date.formatted(.dateTime.weekday(.abbreviated).day().month())): \(val.map { max == 21 ? String(format: "%.1f", $0) : "\(Int($0))%" } ?? String(localized: "no data"))")
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Self.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Self.border, lineWidth: 1))
    }

    /// Redline's insight banner: tone bar on the left, kicker + title, the first paragraph.
    private func banner(_ v: GarminStore.Vitals, _ d: GarminStore.Details) -> some View {
        let tone = d.bannerTone == "good" ? Self.good : d.bannerTone == "crit" ? Self.red
            : d.bannerTone == "warn" ? Self.mid : Self.text2
        return HStack(spacing: 8) {
            Image(systemName: d.bannerTone == "good" ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(tone)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(d.bannerKicker)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(tone)
                    Text(d.bannerTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Self.text1)
                        .lineLimit(1)
                }
                Text(d.bannerText)
                    .font(.system(size: 9))
                    .foregroundColor(Self.text2)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            if !v.statusLabel.isEmpty {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(v.statusLabel)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(Self.bandColor(v.statusBand))
                    if let since = v.statusSince {
                        Text(String(localized: "since \(since.formatted(.dateTime.month(.abbreviated).day()))"))
                            .font(.system(size: 8.5))
                            .foregroundColor(Self.text3)
                    }
                }
                .help(String(localized: "Training status"))
            }
        }
        .padding(.leading, 11).padding(.trailing, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Self.surface))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10, style: .continuous)
                .fill(tone).frame(width: 2.5)
        }
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Self.border, lineWidth: 1))
        .help(d.bannerText)
    }

    // MARK: Key metrics: value, sparkline, change vs 30-day average

    @ViewBuilder private func metrics(_ v: GarminStore.Vitals) -> some View {
        if let hrv = v.hrv.last {
            metric("HRV", "\(Int(hrv))", "ms", v.hrv.suffix(14),
                   Self.delta(hrv, Self.avg(v.hrv.dropLast()), higherIsBetter: true, unit: " ms"))
        }
        if let rhr = v.rhr.last {
            metric(String(localized: "Resting HR"), "\(Int(rhr))", "bpm", v.rhr.suffix(14),
                   Self.delta(rhr, Self.avg(v.rhr.dropLast()), higherIsBetter: false, unit: " bpm"))
        }
        if let vo2 = v.vo2.last {
            let up = v.vo2Sub.lowercased().hasPrefix("up")
            let down = v.vo2Sub.lowercased().hasPrefix("down")
            let short = v.vo2Sub.components(separatedBy: " on ").first ?? v.vo2Sub
            metric("VO₂ max", String(format: "%.1f", vo2), "ml/kg/min", v.vo2.suffix(31),
                   (short.prefix(1).uppercased() + short.dropFirst(), up ? Self.good : down ? Self.red : Self.text3))
        }
        if let load = v.load.last {
            metric(String(localized: "Load ratio"), String(format: "%.2f", load), String(localized: "a:c"), v.load.suffix(28),
                   load < 0.8 ? (String(localized: "Below 0.8 · lighter"), Self.red)
                   : load > 1.3 ? (String(localized: "Above 1.3 · ramping"), Self.red)
                   : (String(localized: "0.8–1.3 · sweet spot"), Self.good))
        }
    }

    private func metric(_ label: String, _ value: String, _ unit: String,
                        _ spark: ArraySlice<Double>, _ delta: (String, Color)) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8.5))
                .foregroundColor(Self.text3)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(Self.text1)
                    .fixedSize()
                    .layoutPriority(1)
                Text(unit)
                    .font(.system(size: 7.5))
                    .foregroundColor(Self.text3)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Sparkline(values: Array(spark))
                    .stroke(Self.text2.opacity(0.8), style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
                    .frame(width: 26, height: 13)
            }
            Text(delta.0)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundColor(delta.1)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Self.surface))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Self.border, lineWidth: 1))
    }

    static func avg<C: Collection>(_ xs: C) -> Double? where C.Element == Double {
        xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }

    /// "−2 ms vs 30-day avg", green when it moved the good way.
    static func delta(_ cur: Double, _ base: Double?, higherIsBetter: Bool, unit: String) -> (String, Color) {
        guard let base else { return ("", text3) }
        let d = cur - base
        if abs(d) < 0.5 { return (String(localized: "Same as 30-day avg"), text3) }
        let good = higherIsBetter ? d > 0 : d < 0
        return ("\(d > 0 ? "+" : "−")\(Int(abs(d).rounded()))\(unit) " + String(localized: "vs 30-day avg"), good ? Self.good : red)
    }

    // MARK: Races, activity, records

    @ViewBuilder private func raceSection(_ s: GarminStore.Snapshot, _ d: GarminStore.Details) -> some View {
        if let race = s.race {
            VStack(alignment: .leading, spacing: 6) {
                Text(race.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(GarminCardView.raceWhen(race.date))
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(Color(hex: "#F5A524"))
                    Text("\(race.distance) m\(race.xc ? " · XC" : "")")
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundColor(Color(hex: "#C5C8CD"))
                    Text(d.raceRegistered ? String(localized: "registered ✓") : String(localized: "not registered yet"))
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(Color(hex: d.raceRegistered ? "#22C55E" : "#FB923C"))
                }
                if !d.raceVenue.isEmpty {
                    Text(d.raceVenue)
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .lineLimit(1)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(localized: "Target"))
                        .font(.system(size: 9.5))
                        .foregroundColor(Color(hex: "#6B7079"))
                    Text(race.target)
                        .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(Color(hex: "#F5F6F8"))
                    Text(d.racePace)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundColor(Color(hex: "#8E939C"))
                }
                .help(d.raceBasis)

                if !d.rivals.isEmpty {
                    Text(String(localized: "Rivals"))
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(Color(hex: "#6B7079"))
                        .padding(.top, 2)
                    ForEach(d.rivals) { r in
                        HStack(spacing: 6) {
                            Text(r.best)
                                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                                .foregroundColor(Color(hex: "#F1F2F4"))
                                .frame(width: 46, alignment: .leading)
                            Text(r.name)
                                .font(.system(size: 10.5))
                                .foregroundColor(Color(hex: "#C5C8CD"))
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Text(r.club)
                                .font(.system(size: 9))
                                .foregroundColor(Color(hex: "#6B7079"))
                                .lineLimit(1)
                        }
                    }
                }

                if !d.predictions.isEmpty {
                    Text(String(localized: "Garmin race predictions"))
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(Color(hex: "#6B7079"))
                        .padding(.top, 2)
                    HStack(spacing: 10) {
                        ForEach(Array(d.predictions.enumerated()), id: \.offset) { _, p in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(Self.clock(p.1))
                                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                    .foregroundColor(Color(hex: "#F1F2F4"))
                                Text(p.0 == "Half Marathon" ? "Half" : p.0)
                                    .font(.system(size: 9))
                                    .foregroundColor(Color(hex: "#6B7079"))
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("No race coming up")
                .font(.system(size: 11.5))
                .foregroundColor(Color(hex: "#8E939C"))
        }
    }

    private func trainingSection(_ d: GarminStore.Details) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(d.activities) { a in
                HStack(spacing: 8) {
                    Image(systemName: Self.icon(for: a.type))
                        .font(.system(size: 11))
                        .foregroundColor(Self.strain)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Self.strain.opacity(0.14)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(a.name)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(Color(hex: "#F1F2F4"))
                            .lineLimit(1)
                        Text(Self.activityMeta(a))
                            .font(.system(size: 9.5).monospacedDigit())
                            .foregroundColor(Color(hex: "#8E939C"))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if !a.effect.isEmpty {
                        Text(a.effect)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color(hex: "#A78BFA"))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color(hex: "#A78BFA").opacity(0.14)))
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recordsSection(_ d: GarminStore.Details) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(d.records) { r in
                HStack(spacing: 8) {
                    Text(r.result)
                        .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(Color(hex: "#F5A524"))
                        .frame(width: 62, alignment: .leading)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(r.event)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "#F1F2F4"))
                            .lineLimit(1)
                        Text("\(r.date) · \(r.meet)")
                            .font(.system(size: 9))
                            .foregroundColor(Color(hex: "#6B7079"))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Helpers

    static func bandColor(_ band: String) -> Color {
        switch band {
        case "good": return Color(hex: "#22C55E")
        case "warn": return Color(hex: "#F5A524")
        case "bad", "crit": return Color(hex: "#F4505E")
        default: return Color(hex: "#8E939C")
        }
    }

    static func toneColor(_ tone: String) -> Color {
        switch tone {
        case "crit": return Color(hex: "#F4505E")
        case "warn": return Color(hex: "#F5A524")
        case "good": return Color(hex: "#22C55E")
        default: return Color(hex: "#C5C8CD")
        }
    }

    static func icon(for type: String) -> String {
        let t = type.lowercased()
        if t.contains("run") || t.contains("track") { return "figure.run" }
        if t.contains("cycl") || t.contains("bik") { return "bicycle" }
        if t.contains("swim") { return "figure.pool.swim" }
        if t.contains("strength") || t.contains("training") { return "dumbbell.fill" }
        if t.contains("walk") || t.contains("hik") { return "figure.walk" }
        return "heart.fill"
    }

    static func activityMeta(_ a: GarminStore.Details.Activity) -> String {
        var parts: [String] = []
        if let date = a.date {
            parts.append(Calendar.current.isDateInToday(date) ? String(localized: "today")
                         : Calendar.current.isDateInYesterday(date) ? String(localized: "yesterday")
                         : date.formatted(.dateTime.weekday(.abbreviated).day()))
        }
        if a.km > 0.05 { parts.append(String(format: "%.1f km", a.km)) }
        if a.minutes > 0 { parts.append("\(Int(a.minutes.rounded())) min") }
        if let hr = a.hr { parts.append("♥ \(hr)") }
        return parts.joined(separator: " · ")
    }

    static func clock(_ seconds: Int) -> String {
        seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// "Updated today 09:47" + ↻, shared by the card and the big view.
struct GarminUpdatedLine: View {
    @ObservedObject private var store = GarminStore.shared

    var body: some View {
        HStack(spacing: 4) {
            Text(GarminCardView.updatedText(store.updatedAt, fetching: store.fetching))
                .font(.system(size: 9))
                .foregroundColor(Color(hex: "#5F646D"))
            Button { store.fetchIfStale(force: true) } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color(hex: store.fetching ? GarminStore.color : "#6B7079"))
                    .rotationEffect(.degrees(store.fetching ? 360 : 0))
                    .animation(store.fetching ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                               value: store.fetching)
            }
            .buttonStyle(.plain)
            .disabled(store.fetching)
            .help(String(localized: "Get today's numbers from Garmin now"))
        }
    }
}
/// Redline's tiny trend line: the values scaled to the frame, no axes.
struct Sparkline: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard values.count > 1, let lo = values.min(), let hi = values.max() else { return p }
        let span = hi - lo == 0 ? 1 : hi - lo
        for (i, v) in values.enumerated() {
            let pt = CGPoint(x: rect.minX + rect.width * CGFloat(i) / CGFloat(values.count - 1),
                             y: rect.maxY - rect.height * CGFloat((v - lo) / span))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}
#endif
