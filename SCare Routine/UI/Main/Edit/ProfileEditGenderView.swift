import SwiftUI

/// Cinsiyet düzenleme sheet'i — 4 chip seçenek.
///
/// "Belirtmek istemiyorum" varsayılan: kullanıcı asla seçmek zorunda değil
/// ama gönderdiyse sunucuda saklanır. Backend "female|male|non_binary|prefer_not_to_say"
/// rawValue'ları bekliyor.
struct ProfileEditGenderView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var selected: OnboardingGender?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L("Cinsiyet bilgisi hormonel öneriler için kullanılır. Tamamen opsiyonel."))
                            .font(Theme.Typo.body)
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.top, 4)

                        VStack(spacing: 10) {
                            ForEach(OnboardingGender.allCases) { g in
                                BigSelectionCard(
                                    title: g.displayTR,
                                    subtitle: subtitle(for: g),
                                    symbol: symbol(for: g),
                                    isSelected: selected == g
                                ) {
                                    selected = g
                                }
                            }
                        }

                        if let msg = errorMessage {
                            Text(msg)
                                .font(Theme.Typo.caption)
                                .foregroundStyle(Theme.alert)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(L("Cinsiyet"))
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
                            .disabled(selected == nil)
                            .fontWeight(.semibold)
                    }
                }
            }
            .onAppear {
                if let raw = appState.currentProfile?.gender,
                   let g = OnboardingGender(rawValue: raw) {
                    selected = g
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func subtitle(for g: OnboardingGender) -> String? {
        switch g {
        case .female: return L("gender_female_subtitle")
        case .male: return L("gender_male_subtitle")
        case .nonBinary: return L("gender_nonbinary_subtitle")
        case .preferNotToSay: return L("gender_prefer_not_subtitle")
        }
    }

    private func symbol(for g: OnboardingGender) -> String {
        switch g {
        case .female: return "person.fill"
        case .male: return "person.fill"
        case .nonBinary: return "person.2.fill"
        case .preferNotToSay: return "lock.fill"
        }
    }

    private func save() {
        guard let g = selected, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Haptics.light()

        var payload = ProfileUpdateRequest()
        payload.gender = g.rawValue

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
    ProfileEditGenderView()
        .environment(AppState())
}
