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
                        Text(L("Çektiğin fotoğrafları nasıl saklayalım?"))
                            .font(Theme.Typo.body)
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.top, 4)

                        VStack(spacing: 10) {
                            BigSelectionCard(
                                title: L("Fotoğrafları sakla"),
                                subtitle: L("Before/after karşılaştırması yapabilirsin. İstediğin zaman silebilirsin."),
                                symbol: "photo.on.rectangle.angled",
                                isSelected: mode == .photoKept
                            ) { mode = .photoKept }

                            BigSelectionCard(
                                title: L("Sadece veri sakla"),
                                subtitle: L("Daha gizlilik dostu. Fotoğraf AI analizinden sonra silinir; yorumlar kalır."),
                                symbol: "lock.fill",
                                isSelected: mode == .metricsOnly
                            ) { mode = .metricsOnly }
                        }

                        Text(L("Geçmiş fotoğraflarına dokunmaz; yalnızca yeni çekimleri etkiler."))
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
            .navigationTitle(L("Fotoğraf modu"))
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
