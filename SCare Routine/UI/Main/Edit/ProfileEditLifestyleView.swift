import SwiftUI

/// Yaşam tarzı düzenleme sheet'i — sigara, alkol, uyku, su.
///
/// Form-style native iOS pattern. Tüm değerler opsiyonel; kullanıcı sadece bilinen
/// alanları doldurabilir.
struct ProfileEditLifestyleView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    // Sigara
    @State private var smoking: SmokingValue?
    // Alkol
    @State private var alcohol: AlcoholValue?
    // Uyku / su
    @State private var sleepHoursEnabled: Bool = false
    @State private var sleepHours: Double = 7.0
    @State private var waterEnabled: Bool = false
    @State private var waterGlasses: Double = 8.0

    @State private var isSaving = false
    @State private var errorMessage: String?

    enum SmokingValue: String, CaseIterable, Identifiable {
        case never = "never"
        case occasionally = "occasionally"
        case daily = "daily"
        var id: String { rawValue }
        var displayTR: String {
            switch self {
            case .never: return "Hiç"
            case .occasionally: return "Ara sıra"
            case .daily: return "Günlük"
            }
        }
    }

    enum AlcoholValue: String, CaseIterable, Identifiable {
        case never = "never"
        case rarely = "rarely"
        case weekly = "weekly"
        case daily = "daily"
        var id: String { rawValue }
        var displayTR: String {
            switch self {
            case .never: return "Hiç"
            case .rarely: return "Nadiren"
            case .weekly: return "Haftalık"
            case .daily: return "Günlük"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        sectionHeader("Sigara", systemImage: "smoke.fill")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(SmokingValue.allCases) { v in
                                    OnboardingChip(
                                        title: v.displayTR,
                                        symbol: nil,
                                        isSelected: smoking == v
                                    ) {
                                        smoking = (smoking == v) ? nil : v
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .scrollIndicators(.hidden)

                        sectionHeader("Alkol", systemImage: "wineglass.fill")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(AlcoholValue.allCases) { v in
                                    OnboardingChip(
                                        title: v.displayTR,
                                        symbol: nil,
                                        isSelected: alcohol == v
                                    ) {
                                        alcohol = (alcohol == v) ? nil : v
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .scrollIndicators(.hidden)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "bed.double.fill")
                                    .foregroundStyle(Theme.inkSoft)
                                Text("Uyku (saat)")
                                    .font(Theme.Typo.headline)
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Toggle("", isOn: $sleepHoursEnabled.animation())
                                    .labelsHidden()
                                    .tint(Theme.ink)
                            }

                            if sleepHoursEnabled {
                                HStack {
                                    Text("4 sa")
                                        .font(Theme.Typo.caption)
                                        .foregroundStyle(Theme.inkMute)
                                    Slider(value: $sleepHours, in: 4...12, step: 0.5)
                                        .tint(Theme.ink)
                                    Text("12 sa")
                                        .font(Theme.Typo.caption)
                                        .foregroundStyle(Theme.inkMute)
                                }
                                Text("Ortalama: \(String(format: "%.1f", sleepHours)) saat")
                                    .font(Theme.Typo.caption.weight(.medium))
                                    .foregroundStyle(Theme.inkSoft)
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                                .fill(Theme.surface)
                        )

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "drop.fill")
                                    .foregroundStyle(Theme.inkSoft)
                                Text("Su (bardak/gün)")
                                    .font(Theme.Typo.headline)
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Toggle("", isOn: $waterEnabled.animation())
                                    .labelsHidden()
                                    .tint(Theme.ink)
                            }

                            if waterEnabled {
                                HStack {
                                    Text("0")
                                        .font(Theme.Typo.caption)
                                        .foregroundStyle(Theme.inkMute)
                                    Slider(value: $waterGlasses, in: 0...15, step: 1)
                                        .tint(Theme.ink)
                                    Text("15")
                                        .font(Theme.Typo.caption)
                                        .foregroundStyle(Theme.inkMute)
                                }
                                Text("\(Int(waterGlasses)) bardak")
                                    .font(Theme.Typo.caption.weight(.medium))
                                    .foregroundStyle(Theme.inkSoft)
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                                .fill(Theme.surface)
                        )

                        if let msg = errorMessage {
                            Text(msg)
                                .font(Theme.Typo.caption)
                                .foregroundStyle(Theme.alert)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Yaşam tarzı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Kaydet", action: save)
                            .disabled(!canSave)
                            .fontWeight(.semibold)
                    }
                }
            }
            .onAppear(perform: loadInitial)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var canSave: Bool {
        smoking != nil || alcohol != nil || sleepHoursEnabled || waterEnabled
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.inkSoft)
            Text(title)
                .font(Theme.Typo.headline)
                .foregroundStyle(Theme.ink)
        }
    }

    private func loadInitial() {
        guard let life = appState.currentProfile?.lifestyle else { return }
        if let s = life.smoking, let v = SmokingValue(rawValue: s) {
            smoking = v
        }
        if let a = life.alcoholFrequency, let v = AlcoholValue(rawValue: a) {
            alcohol = v
        }
        if let sh = life.sleepHoursAvg {
            sleepHoursEnabled = true
            sleepHours = min(max(sh, 4.0), 12.0)
        }
        if let w = life.waterGlassesPerDay {
            waterEnabled = true
            waterGlasses = Double(min(max(w, 0), 15))
        }
    }

    private func save() {
        guard !isSaving, canSave else { return }
        isSaving = true
        errorMessage = nil
        Haptics.light()

        let lifestylePayload = LifestylePayload(
            smoking: smoking?.rawValue,
            alcoholFrequency: alcohol?.rawValue,
            sleepHoursAvg: sleepHoursEnabled ? sleepHours : nil,
            waterGlassesPerDay: waterEnabled ? Int(waterGlasses) : nil
        )

        var payload = ProfileUpdateRequest()
        payload.lifestyle = lifestylePayload

        Task {
            do {
                try await UserService.shared.updateProfile(payload)
                await appState.refreshMe()
                Haptics.success()
                dismiss()
            } catch {
                Haptics.error()
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
                isSaving = false
            }
        }
    }
}

#Preview {
    ProfileEditLifestyleView()
        .environment(AppState())
}
