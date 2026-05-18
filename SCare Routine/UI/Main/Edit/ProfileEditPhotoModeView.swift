import SwiftUI

/// Fotoğraf modu düzenleme sheet'i — onboarding'in PreferencesView'inin
/// post-onboarding ikizi.
///
/// 2 büyük kart: "Fotoğrafları sakla" vs "Sadece veri sakla". Mevcut tercih
/// önceden işaretli; kullanıcı dilediği zaman değiştirebilir.
struct ProfileEditPhotoModeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var mode: PhotoMode = .photoKept
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Çektiğin fotoğrafları nasıl saklayalım?")
                            .font(Theme.Typo.body)
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.top, 4)

                        VStack(spacing: 10) {
                            BigSelectionCard(
                                title: "Fotoğrafları sakla",
                                subtitle: "Before/after karşılaştırması yapabilirsin. İstediğin zaman silebilirsin.",
                                symbol: "photo.on.rectangle.angled",
                                isSelected: mode == .photoKept
                            ) { mode = .photoKept }

                            BigSelectionCard(
                                title: "Sadece veri sakla",
                                subtitle: "Daha gizlilik dostu. Fotoğraf AI analizinden sonra silinir; yorumlar kalır.",
                                symbol: "lock.fill",
                                isSelected: mode == .metricsOnly
                            ) { mode = .metricsOnly }
                        }

                        Text("Geçmiş fotoğraflarına dokunmaz; yalnızca yeni çekimleri etkiler.")
                            .font(Theme.Typo.caption)
                            .foregroundStyle(Theme.inkMute)
                            .padding(.top, 4)

                        if let msg = errorMessage {
                            Text(msg)
                                .font(Theme.Typo.caption)
                                .foregroundStyle(Theme.alert)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Fotoğraf modu")
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
                            .fontWeight(.semibold)
                    }
                }
            }
            .onAppear {
                if let raw = appState.currentProfile?.defaultPhotoMode,
                   let m = PhotoMode(rawValue: raw) {
                    mode = m
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Haptics.light()

        var payload = ProfileUpdateRequest()
        payload.defaultPhotoMode = mode.rawValue

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
    ProfileEditPhotoModeView()
        .environment(AppState())
}
