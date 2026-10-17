#if !APPSTORE
import SwiftUI

// MARK: - Garmin tab (the big view, GitHub build only)

/// Yehonathan's whole Redline picture in the notch: readiness, status and load, today's tip,
/// sleep / HRV / stress / VO₂ max, the week's readiness, and on the right the next race,
/// recent training and personal records.
struct GarminFullView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store = GarminStore.shared

    enum Section: String, CaseIterable { case race, training, records }
    @State private var section: Section = .race

    var body: some View {
        ZStack(alignment: .topLeading) {
            CardBackground(wash: nil)
            Group {
                if let s = store.snapshot, let d = store.details {
                    HStack(alignment: .top, spacing: 14) {
                        today(s, d).frame(width: 250)
                        Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1)
                        right(s, d).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                } else {
                    VStack(spacing: 8) {
                        Spacer(minLength: 0)
                        Image(systemName: "figure.run").font(.system(size: 24)).foregroundColor(Color(hex: GarminStore.color))
                        Text("No Garmin data yet")
                            .font(.system(size: 12)).foregroundColor(Color(hex: "#8E939C"))
                        Button(String(localized: "Get it now")) { store.fetchIfStale(force: true) }
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(Color(hex: GarminStore.color))
                            .buttonStyle(.plain)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.leading, 84)
            .padding(.trailing, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .padding(.bottom, 10)
        .onAppear {
            store.refresh()
            store.fetchIfStale()
        }
    }

    // MARK: Left: today

    private func today(_ s: GarminStore.Snapshot, _ d: GarminStore.Details) -> some View {
        let color = GarminStore.readinessColor(s.readinessLevel)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: GarminStore.color)).frame(width: 7, height: 7)
                Text("Garmin")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                Spacer(minLength: 4)
                GarminUpdatedLine()
            }

            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.08), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: CGFloat(s.readiness ?? 0) / 100)
                        .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: color.opacity(0.5), radius: 5)
                    VStack(spacing: 0) {
                        Text(s.readiness.map(String.init) ?? "–")
                            .font(.system(size: 19, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(Color(hex: "#F5F6F8"))
                        Text(s.readinessLevel.capitalized)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(color)
                    }
                }
                .frame(width: 60, height: 60)

                VStack(alignment: .leading, spacing: 5) {
                    chip(icon: "chart.line.uptrend.xyaxis", text: d.statusLabel.isEmpty ? "–" : d.statusLabel,
                         band: d.statusBand, help: String(localized: "Training status"))
                    chip(icon: "scalemass", text: d.loadRatio.map { String(format: "Load %.1f · %@", $0, d.loadStatus.lowercased()) } ?? "–",
                         band: d.loadBand, help: String(localized: "Acute : chronic training load"))
                    if !d.bannerTitle.isEmpty {
                        Text(d.bannerTitle)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(Self.toneColor(d.bannerTone))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .help(d.bannerText)
                    }
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    tile("moon.zzz.fill", "#818CF8", s.sleep.map(String.init) ?? "–", String(localized: "Sleep"),
                         s.sleepSub.components(separatedBy: " · ").first ?? "")
                    tile("heart.fill", d.hrvStatus == "low" ? "#FB923C" : "#F472B6", s.hrv.map(String.init) ?? "–", "HRV",
                         s.hrvLow.flatMap { lo in s.hrvHigh.map { String(localized: "base \(lo)–\($0)") } } ?? "")
                }
                GridRow {
                    tile("brain.head.profile", "#F5A524", d.stress.map(String.init) ?? "–", String(localized: "Stress"),
                         s.steps.map { String(localized: "\(GarminCardView.compact($0)) steps") } ?? "")
                    tile("lungs.fill", "#22D3EE", s.vo2.map { String(format: "%.1f", $0) } ?? "–", "VO₂ max",
                         d.vo2Sub.components(separatedBy: " from ").first ?? "")
                }
            }

            weekBars(d.week)
        }
    }

    private func chip(icon: String, text: String, band: String, help: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 8.5, weight: .semibold))
            Text(text).font(.system(size: 10, weight: .semibold)).lineLimit(1)
        }
        .foregroundColor(Self.bandColor(band))
        .padding(.horizontal, 7)
        .frame(height: 18)
        .background(Capsule().fill(Self.bandColor(band).opacity(0.14)))
        .help(help)
    }

    private func tile(_ icon: String, _ tint: String, _ value: String, _ label: String, _ sub: String) -> some View {
        HStack(alignment: .center, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: tint))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(Color(hex: "#F1F2F4"))
                    Text(label)
                        .font(.system(size: 9.5))
                        .foregroundColor(Color(hex: "#8E939C"))
                }
                if !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 9))
                        .foregroundColor(Color(hex: "#6B7079"))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7).padding(.vertical, 5)
        .frame(width: 122, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
    }

    /// The last 7 days of readiness as bars, today brightest.
    private func weekBars(_ days: [GarminStore.Details.Day]) -> some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(days) { day in
                let isToday = Calendar.current.isDateInToday(day.date)
                VStack(spacing: 2) {
                    Text("\(day.score)")
                        .font(.system(size: 8, weight: .semibold).monospacedDigit())
                        .foregroundColor(Color(hex: isToday ? "#F5F6F8" : "#6B7079"))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(GarminStore.readinessColor(day.level).opacity(isToday ? 1 : 0.55))
                        .frame(width: 22, height: max(3, CGFloat(day.score) / 100 * 26))
                    Text(day.date.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 8, weight: isToday ? .bold : .regular))
                        .foregroundColor(Color(hex: isToday ? "#F5F6F8" : "#6B7079"))
                }
                .help("\(day.date.formatted(date: .abbreviated, time: .omitted)) · \(day.level.capitalized) \(day.score)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Right: race, training, records

    private func right(_ s: GarminStore.Snapshot, _ d: GarminStore.Details) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                sectionButton(.race, "flag.checkered", String(localized: "Race"))
                sectionButton(.training, "figure.run", String(localized: "Training"))
                sectionButton(.records, "medal.fill", String(localized: "Records"))
                Spacer(minLength: 0)
                Button { store.openDashboard() } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.white.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .help(String(localized: "Open the Redline dashboard"))
            }
            ScrollView(.vertical, showsIndicators: false) {
                switch section {
                case .race:     raceSection(s, d)
                case .training: trainingSection(d)
                case .records:  recordsSection(d)
                }
            }
        }
    }

    private func sectionButton(_ s: Section, _ icon: String, _ title: String) -> some View {
        let on = section == s
        return Button { withAnimation(.snappy(duration: 0.2)) { section = s } } label: {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 8.5, weight: .semibold))
                Text(title).font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundColor(on ? Color(hex: GarminStore.color) : Color(hex: "#6B7079"))
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule().fill(on ? Color(hex: GarminStore.color).opacity(0.16) : Color.white.opacity(0.04)))
        }
        .buttonStyle(NowPlayingPressStyle())
    }

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
                        .foregroundColor(Color(hex: GarminStore.color))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color(hex: GarminStore.color).opacity(0.12)))
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
#endif
