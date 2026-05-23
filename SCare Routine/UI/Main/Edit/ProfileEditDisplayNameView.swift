import SwiftUI

/// İsim düzenleme sheet'i.
///
/// **NOT (Backend gap)**: Şu an `PUT /v1/me/profile` sadece `profiles` tablosu
/// alanlarını günceller; `display_name` `users` tablosunda. Backend bunu
/// destekleyene kadar Kaydet butonu uyarı gösterir ama akış kırılmaz —
/// kullanıcı yine de tasarımı deneyebilir.
///
/// Backend ya `PATCH /v1/me { display_name }` ya da `PUT /v1/me/profile`'a
/// `display_name` desteği eklendiğinde, aşağıdaki `save()` metodunu canlandırmak
/// için sadece payload yolunu değiştir + `unsupported` flag'i kaldır.
struct ProfileEditDisplayNameView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool

    @State private var name: String = ""
    @State private var initialized = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// TODO(backend): display_name endpoint hazırlanınca false yap
    private let unsupported = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L("SCare'in seni nasıl anmasını istersin?"))
                            .font(Theme.Typo.body)
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.top, 4)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("Ad"))
                                .font(Theme.Typo.caption.weight(.medium))
                                .foregroundStyle(Theme.inkMute)
                                .textCase(.uppercase)

                            TextField(L("Adın"), text: $name)
                                .font(Theme.Typo.body)
                                .foregroundStyle(Theme.ink)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled(false)
                                .submitLabel(.done)
                                .focused($nameFocused)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                                        .fill(Theme.surface)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                                        .strokeBorder(Theme.divider, lineWidth: 1)
                                )
                                .onSubmit { nameFocused = false }
                        }

                        if unsupported {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "hourglass")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.alert)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L("Yakında"))
                                        .font(Theme.Typo.caption.weight(.semibold))
                                        .foregroundStyle(Theme.ink)
                                    Text(L("İsim düzenleme şu an backend tarafında hazırlanıyor. Çok yakında bu ekrandan değiştirebileceksin."))
                                        .font(Theme.Typo.caption)
                                        .foregroundStyle(Theme.inkSoft)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                                    .fill(Theme.surfaceLow)
                            )
                        }

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
            .navigationTitle(L("Adın"))
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
                            .disabled(!canSave)
                            .fontWeight(.semibold)
                    }
                }
            }
            .onAppear {
                if initialized { return }
                initialized = true
                name = appState.currentUser?.displayName ?? ""
                // İlk açılışta klavyeyi otomatik aç — kullanıcı zaten yazmak için geldi
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    nameFocused = true
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if unsupported { return false }
        guard !trimmed.isEmpty, trimmed.count <= 60 else { return false }
        return trimmed != (appState.currentUser?.displayName ?? "")
    }

    /// Backend display_name endpoint'i hazırlanınca:
    /// 1. `unsupported = false` yap
    /// 2. Aşağıdaki `// FIXME` blok'unu canlandır (ProfileUpdateRequest'e
    ///    displayName field eklemek VEYA ayrı endpoint ile gönderme).
    private func save() {
        guard canSave, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Haptics.light()

        var payload = ProfileUpdateRequest()
        payload.displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
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
    ProfileEditDisplayNameView()
        .environment(AppState())
}
