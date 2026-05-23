import SwiftUI

/// Doğum tarihi düzenleme sheet'i — wheel-style DatePicker.
///
/// Range: 12-100 yıl önce (skincare için anlamlı). ISO "yyyy-MM-dd" formatında
/// kaydedilir. AppState.refreshMe() ile sonradan yenilenir.
struct ProfileEditBirthDateView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date = .defaultBirthDate
    @State private var initialized = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 16) {
                    Text(L("Yaşına göre cilt ihtiyaçların önemli ölçüde değişir."))
                        .font(Theme.Typo.body)
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)

                    DatePicker(
                        L("Doğum tarihi"),
                        selection: $date,
                        in: Date.minBirthDate ... Date.maxBirthDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                            .fill(Theme.surface)
                    )
                    .padding(.horizontal, 16)

                    if let years = computedAge() {
                        HStack(spacing: 6) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 13))
                            Text(String(format: L("Yaşın: %d"), years))
                        }
                        .font(Theme.Typo.caption.weight(.medium))
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, 16)
                    }

                    if let msg = errorMessage {
                        Text(msg)
                            .font(Theme.Typo.caption)
                            .foregroundStyle(Theme.alert)
                            .padding(.horizontal, 16)
                    }

                    Spacer()
                }
                .padding(.bottom, 16)
            }
            .navigationTitle(L("Doğum tarihi"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("İptal")) { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(L("Kaydet"), action: save)
                            .fontWeight(.semibold)
                    }
                }
            }
            .onAppear {
                if initialized { return }
                initialized = true
                if let bd = appState.currentProfile?.birthDate,
                   let parsed = DateFormatter.scareISO.date(from: bd) {
                    date = parsed
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func computedAge() -> Int? {
        let comps = Calendar.current.dateComponents([.year], from: date, to: .now)
        return comps.year
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Haptics.light()

        var payload = ProfileUpdateRequest()
        payload.birthDate = DateFormatter.scareISO.string(from: date)

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

// MARK: - Yardımcılar

private extension DateFormatter {
    /// Backend "yyyy-MM-dd" ISO date formatter (UTC neutral)
    static let scareISO: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

private extension Date {
    /// 100 yıl önce
    static var minBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: -100, to: .now) ?? .distantPast
    }
    /// 12 yıl önce (en gencin tarihi)
    static var maxBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: -12, to: .now) ?? .now
    }
    /// İlk açılışta default: 25 yıl önce
    static var defaultBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now
    }
}

#Preview {
    ProfileEditBirthDateView()
        .environment(AppState())
}
