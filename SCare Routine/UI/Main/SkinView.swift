import SwiftUI
import Charts

/// Cilt günlüğü ekranı.
///
/// Bölümler:
/// 1. Header (Bugün — tarih)
/// 2. "Bugün değerlendir" CTA — SkinLogEntrySheet açar
/// 3. 7-günlük şerit (dolu/boş gün gösterimi)
/// 4. Trendler (son 30 gün, 5 metrik mini-sparkline)
/// 5. Son loglar (horizontal scroll, gün gün özet)
///
/// Veri akışı:
/// - `onAppear` ve sheet kapanışında `reloadAll()` çağrılır
/// - Son 30 günlük log listesi + her metrik için 30 günlük trend serisi paralel çekilir
/// - 7-gün şerit: log listesinden tarihe göre lookup
struct SkinView: View {
    @Environment(AppState.self) private var appState

    @State private var logs: [SkinLogResponse] = []
    @State private var trends: [String: SkinTrendsResponse] = [:]
    @State private var isLoading: Bool = false
    @State private var loadError: String?

    @State private var showEntrySheet: Bool = false

    /// Trend metric → görünür Türkçe etiket
    private let metricLabels: [(key: String, label: String)] = [
        ("hydration", "Nem"),
        ("redness", "Kızarıklık"),
        ("oiliness", "Yağ"),
        ("breakouts", "Sivilce"),
        ("overall", "Genel")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                            .padding(.horizontal, 20)

                        todayCTA
                            .padding(.horizontal, 20)

                        weekStrip
                            .padding(.horizontal, 20)

                        trendsSection

                        recentLogsSection

                        Color.clear.frame(height: 40)
                    }
                    .padding(.top, 12)
                }
                .refreshable {
                    await reloadAll()
                }
            }
            .navigationTitle("Cilt")
            .navigationBarTitleDisplayMode(.large)
            .task(id: appState.currentUser?.id) {
                await reloadAll()
            }
            .sheet(isPresented: $showEntrySheet) {
                SkinLogEntrySheet { _ in
                    Task { await reloadAll() }
                }
                .environment(appState)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greetingPrefix)
                .font(Theme.Typo.caption.weight(.medium))
                .foregroundStyle(Theme.inkSoft)
                .textCase(.uppercase)
            Text(todayLongDate)
                .font(Theme.Typo.headline)
                .foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greetingPrefix: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<11: return "Günaydın"
        case 11..<17: return "İyi günler"
        case 17..<22: return "İyi akşamlar"
        default: return "İyi geceler"
        }
    }

    private var todayLongDate: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "tr_TR")
        fmt.dateFormat = "d MMMM EEEE"
        return "Bugün — " + fmt.string(from: .now)
    }

    // MARK: - Today CTA

    private var todayCTA: some View {
        Button {
            Haptics.heavy()
            showEntrySheet = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.onAccent.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.onAccent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(hasTodayLog ? "Bugünü güncelle" : "Bugünü değerlendir")
                        .font(Theme.Typo.headline)
                        .foregroundStyle(Theme.onAccent)
                    Text("Birkaç saniye sürer")
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.onAccent.opacity(0.8))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.onAccent.opacity(0.7))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.ink)
            )
            .shadow(color: Theme.ink.opacity(0.12), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(PressedScaleButtonStyle())
    }

    private var hasTodayLog: Bool {
        let today = Self.ymd(.now)
        return logs.contains(where: { $0.logDate == today })
    }

    // MARK: - 7-day strip

    private var weekStrip: some View {
        HStack(spacing: 6) {
            ForEach(last7Days, id: \.self) { date in
                weekDayCell(date)
            }
        }
    }

    @ViewBuilder
    private func weekDayCell(_ date: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        let log = logFor(date)
        let hasLog = (log != nil)

        VStack(spacing: 6) {
            Text(weekdayShort(date))
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.inkSoft)

            ZStack {
                Circle()
                    .fill(isToday ? Theme.ink : (hasLog ? Theme.surface : Color.clear))
                    .frame(width: 36, height: 36)
                Circle()
                    .strokeBorder(
                        hasLog || isToday ? Color.clear : Theme.divider,
                        lineWidth: 1
                    )
                    .frame(width: 36, height: 36)

                Text(dayNumber(date))
                    .font(Theme.Typo.body.weight(.medium))
                    .foregroundStyle(isToday ? Theme.onAccent : Theme.ink)
            }

            // 5 skor pip — log varsa overall puanına göre dolar; yoksa boş
            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { i in
                    Circle()
                        .fill(pipColor(for: i, score: log?.selfOverall))
                        .frame(width: 4, height: 4)
                }
            }
            .frame(height: 8)
        }
        .frame(maxWidth: .infinity)
    }

    private func pipColor(for index: Int, score: Int?) -> Color {
        guard let s = score else { return Theme.surfaceLow }
        return index <= s ? Theme.ink : Theme.surfaceLow
    }

    private func weekdayShort(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "tr_TR")
        fmt.dateFormat = "EE"
        return fmt.string(from: date)
    }

    private func dayNumber(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "d"
        return fmt.string(from: date)
    }

    private var last7Days: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
    }

    private func logFor(_ date: Date) -> SkinLogResponse? {
        let ymd = Self.ymd(date)
        return logs.first(where: { $0.logDate == ymd })
    }

    // MARK: - Trends

    @ViewBuilder
    private var trendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Trendlerin")
                    .font(Theme.Typo.headline)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("Son 30 gün")
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(.horizontal, 20)

            if hasAnyTrendData {
                VStack(spacing: 12) {
                    ForEach(metricLabels, id: \.key) { entry in
                        trendRow(metricKey: entry.key, label: entry.label)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                        .fill(Theme.surface)
                )
                .padding(.horizontal, 20)
            } else {
                emptyTrendsCard
                    .padding(.horizontal, 20)
            }
        }
    }

    private var hasAnyTrendData: Bool {
        trends.values.contains { resp in
            resp.points.contains(where: { $0.value != nil })
        }
    }

    @ViewBuilder
    private func trendRow(metricKey: String, label: String) -> some View {
        let points = (trends[metricKey]?.points ?? [])
            .compactMap { p -> (date: String, value: Double)? in
                guard let v = p.value else { return nil }
                return (p.date, v)
            }
        let latest = points.last?.value
        let avg = points.isEmpty ? nil : points.map { $0.value }.reduce(0, +) / Double(points.count)

        HStack(spacing: 12) {
            Text(label)
                .font(Theme.Typo.body.weight(.medium))
                .foregroundStyle(Theme.ink)
                .frame(width: 72, alignment: .leading)

            if points.count >= 2 {
                Chart {
                    ForEach(Array(points.enumerated()), id: \.offset) { idx, item in
                        LineMark(
                            x: .value("i", idx),
                            y: .value("v", item.value)
                        )
                        .foregroundStyle(Theme.ink)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))

                        AreaMark(
                            x: .value("i", idx),
                            y: .value("v", item.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Theme.ink.opacity(0.18), Theme.ink.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: 1...5)
                .frame(height: 32)
            } else {
                // Yetersiz veri — incik bir baseline
                Rectangle()
                    .fill(Theme.surfaceLow)
                    .frame(height: 2)
                    .frame(maxWidth: .infinity)
            }

            VStack(alignment: .trailing, spacing: 2) {
                if let v = latest {
                    Text(String(format: "%.0f", v))
                        .font(Theme.Typo.body.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                } else {
                    Text("—")
                        .font(Theme.Typo.body.weight(.semibold))
                        .foregroundStyle(Theme.inkMute)
                }
                if let a = avg {
                    Text(String(format: "ort %.1f", a))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .frame(width: 48, alignment: .trailing)
        }
    }

    private var emptyTrendsCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.inkMute)
            Text("Trendler için en az birkaç gün veri girmen gerek")
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surface)
        )
    }

    // MARK: - Recent logs

    @ViewBuilder
    private var recentLogsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Son loglar")
                .font(Theme.Typo.headline)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 20)

            if logs.isEmpty {
                Text("Henüz log yok. Bugünü değerlendirerek başla.")
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(sortedRecentLogs) { log in
                            RecentSkinLogCard(log: log)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    private var sortedRecentLogs: [SkinLogResponse] {
        logs.sorted { $0.logDate > $1.logDate }
    }

    // MARK: - Data loading

    private func reloadAll() async {
        isLoading = true
        defer { isLoading = false }
        loadError = nil

        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard let start = cal.date(byAdding: .day, value: -29, to: today) else { return }
        let fromStr = Self.ymd(start)
        let toStr = Self.ymd(today)

        async let logsTask: [SkinLogResponse] = (try? SkinLogService.shared.list(from: fromStr, to: toStr)) ?? []

        // 5 metrik için trend serisi paralel
        async let h: SkinTrendsResponse? = try? SkinLogService.shared.trends(metric: "hydration", days: 30)
        async let r: SkinTrendsResponse? = try? SkinLogService.shared.trends(metric: "redness", days: 30)
        async let o: SkinTrendsResponse? = try? SkinLogService.shared.trends(metric: "oiliness", days: 30)
        async let b: SkinTrendsResponse? = try? SkinLogService.shared.trends(metric: "breakouts", days: 30)
        async let ov: SkinTrendsResponse? = try? SkinLogService.shared.trends(metric: "overall", days: 30)

        let loaded = await logsTask
        self.logs = loaded

        var map: [String: SkinTrendsResponse] = [:]
        if let v = await h { map["hydration"] = v }
        if let v = await r { map["redness"] = v }
        if let v = await o { map["oiliness"] = v }
        if let v = await b { map["breakouts"] = v }
        if let v = await ov { map["overall"] = v }
        self.trends = map
    }

    // MARK: - Helpers

    private static func ymd(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = .current
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }
}

// MARK: - Recent log kartı

/// Horizontal scroll listesindeki tek log özet kartı. Tarih + 5 metrik mini
/// görsel. Tıklama action'ı ileride detay sheet'ine bağlanabilir; şimdilik
/// sadece görüntü.
struct RecentSkinLogCard: View {
    let log: SkinLogResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(dayPart)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                VStack(alignment: .leading, spacing: 0) {
                    Text(monthPart)
                        .font(Theme.Typo.caption.weight(.medium))
                        .foregroundStyle(Theme.inkSoft)
                    Text(weekdayPart)
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.inkMute)
                }
            }

            Divider().background(Theme.divider)

            VStack(alignment: .leading, spacing: 4) {
                miniRow("Nem", value: log.selfHydration)
                miniRow("Kız", value: log.selfRedness)
                miniRow("Yağ", value: log.selfOiliness)
                miniRow("Sivilce", value: log.selfBreakouts)
                miniRow("Genel", value: log.selfOverall)
            }
        }
        .padding(12)
        .frame(width: 152)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.divider, lineWidth: 1)
        )
    }

    private func miniRow(_ label: String, value: Int?) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 48, alignment: .leading)
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { i in
                    Circle()
                        .fill(i <= (value ?? 0) ? Theme.ink : Theme.surfaceLow)
                        .frame(width: 5, height: 5)
                }
            }
        }
    }

    private var parsedDate: Date? {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = .current
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.date(from: log.logDate)
    }

    private var dayPart: String {
        guard let d = parsedDate else { return "—" }
        let fmt = DateFormatter()
        fmt.dateFormat = "d"
        return fmt.string(from: d)
    }

    private var monthPart: String {
        guard let d = parsedDate else { return "" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "tr_TR")
        fmt.dateFormat = "MMM"
        return fmt.string(from: d)
    }

    private var weekdayPart: String {
        guard let d = parsedDate else { return "" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "tr_TR")
        fmt.dateFormat = "EEE"
        return fmt.string(from: d)
    }
}
