import SwiftUI

/// Kullanıcının tüm rutinleri — sabah / akşam / diğer şeklinde gruplandırılır.
///
/// Boş state: "İlk rutinini oluştur" CTA + örnek ipucu.
/// Dolu state: NavigationLink ile RoutineDetailView'a push.
struct RoutineListView: View {
    @Environment(AppState.self) private var appState

    @State private var routines: [RoutineResponse] = []
    @State private var isLoading: Bool = false
    @State private var loadError: String?
    @State private var showCreate: Bool = false
    @State private var routineToEdit: RoutineResponse?

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            if isLoading && routines.isEmpty {
                ProgressView().tint(Theme.inkSoft)
            } else if routines.isEmpty {
                emptyState
            } else {
                routineList
            }
        }
        .navigationTitle(L("Rutinlerim"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.light()
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                }
                .tint(Theme.ink)
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateRoutineSheet(onCreated: { newRoutine in
                routines.insert(newRoutine, at: 0)
                routines.sort { $0.orderIndex < $1.orderIndex }
            })
        }
        .task { await loadRoutines() }
        .refreshable { await loadRoutines() }
        .alert(L("Hata"), isPresented: errorBinding) {
            Button(L("Tamam"), role: .cancel) { loadError = nil }
        } message: {
            Text(loadError ?? "")
        }
    }

    // MARK: - Sections

    private var morning: [RoutineResponse] { routines.filter { isMorning($0) } }
    private var evening: [RoutineResponse] { routines.filter { isEvening($0) } }
    private var other: [RoutineResponse] {
        routines.filter { !isMorning($0) && !isEvening($0) }
    }

    @ViewBuilder
    private var routineList: some View {
        ScrollView {
            VStack(spacing: 20) {
                if !morning.isEmpty {
                    section(title: "Sabah", systemImage: "sun.max", items: morning)
                }
                if !evening.isEmpty {
                    section(title: "Akşam", systemImage: "moon.stars", items: evening)
                }
                if !other.isEmpty {
                    section(title: "Diğer", systemImage: "sparkles", items: other)
                }
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func section(title: String, systemImage: String, items: [RoutineResponse]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(Theme.inkSoft)
                Text(LocalizedStringKey(title))
                    .font(Theme.Typo.headline)
                    .foregroundStyle(Theme.ink)
                Spacer()
            }
            VStack(spacing: 10) {
                ForEach(items) { r in
                    NavigationLink(value: r.id) {
                        RoutineRow(routine: r)
                    }
                    .buttonStyle(PressedScaleButtonStyle())
                }
            }
        }
        .navigationDestination(for: String.self) { routineId in
            if let r = routines.first(where: { $0.id == routineId }) {
                RoutineDetailView(routineId: routineId, initialRoutine: r, onDeleted: { id in
                    routines.removeAll { $0.id == id }
                })
            }
        }
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Theme.inkMute)
            Text(L("Henüz rutinin yok"))
                .font(Theme.Typo.headline)
                .foregroundStyle(Theme.ink)
            Text(L("Sabah ve akşam için ayrı rutinler oluştur, arşivindeki ürünleri ekle. Sonra AI sana ne eksik olduğunu söyler."))
                .font(Theme.Typo.body)
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            PrimaryActionButton(title: L("İlk rutinini oluştur"), systemImage: "plus") {
                showCreate = true
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Helpers

    private func isMorning(_ r: RoutineResponse) -> Bool {
        guard let t = r.schedule?.time else { return r.name.lowercased().contains("sabah") || r.name.lowercased().contains("morning") }
        guard let h = Int(t.split(separator: ":").first.map(String.init) ?? "") else { return false }
        return h < 14
    }

    private func isEvening(_ r: RoutineResponse) -> Bool {
        guard let t = r.schedule?.time else { return r.name.lowercased().contains("akşam") || r.name.lowercased().contains("evening") || r.name.lowercased().contains("gece") }
        guard let h = Int(t.split(separator: ":").first.map(String.init) ?? "") else { return false }
        return h >= 14
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { loadError != nil }, set: { if !$0 { loadError = nil } })
    }

    @MainActor
    private func loadRoutines() async {
        if routines.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            routines = try await RoutineService.shared.listRoutines()
                .sorted { $0.orderIndex < $1.orderIndex }
        } catch {
            loadError = L("Rutinler yüklenemedi")
        }
    }
}

// MARK: - Row

private struct RoutineRow: View {
    let routine: RoutineResponse

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.18))
                    .frame(width: 44, height: 44)
                Text(routine.emoji ?? defaultEmoji)
                    .font(.system(size: 22))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(routine.name)
                    .font(Theme.Typo.body.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if let s = subtitle {
                    Text(s)
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.inkMute)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surface.opacity(0.6))
        )
    }

    private var accentColor: Color {
        if let hex = routine.colorHex { return Color(hex: hex) ?? Theme.ink }
        return Theme.ink
    }

    private var defaultEmoji: String {
        switch routine.categoryId {
        case "skincare": return "🧴"
        case "haircare": return "💆"
        case "bodycare": return "🧖"
        case "makeup": return "💄"
        default: return "✨"
        }
    }

    private var subtitle: String? {
        var parts: [String] = []
        if let s = routine.schedule {
            if let t = s.time { parts.append(t) }
            if let f = s.frequency, f != "daily" { parts.append(f.capitalized) }
        }
        if routine.reminder { parts.append(L("Hatırlatma")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Hex Color helper

private extension Color {
    init?(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(
            red: Double((v >> 16) & 0xff) / 255,
            green: Double((v >> 8) & 0xff) / 255,
            blue: Double(v & 0xff) / 255
        )
    }
}
