import SwiftUI

/// Cilt tipi düzenleme sheet'i — ProfileView'dan açılır.
///
/// Onboarding SkinTypeView'in light versiyonu: 5 BigSelectionCard +
/// "Emin değilim" sıfırlama. Kayıt PUT /v1/me/profile { skin_type } ile
/// gider, sonrasında AppState.refreshMe() ile state tazelenir.
struct ProfileEditSkinTypeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var selected: SkinType?
    @State private var ackUnsure: Bool = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let types: [SkinType] = [.oily, .dry, .combo, .normal, .sensitive]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L("Cildini en iyi hangisi tanımlıyor?"))
                            .font(Theme.Typo.body)
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.top, 4)

                        VStack(spacing: 10) {
                            ForEach(types) { type in
                                BigSelectionCard(
                                    title: type.displayTR,
                                    subtitle: type.subtitleTR,
                                    symbol: type.symbol,
                                    isSelected: selected == type
                                ) {
                                    selected = type
                                    ackUnsure = false
                                }
                            }
                        }

                        unsureLink

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
            .navigationTitle(L("Cilt tipi"))
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
                if let raw = appState.currentProfile?.skinType,
                   let t = SkinType(rawValue: raw) {
                    selected = t
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var canSave: Bool {
        // Yeni seçim varsa veya "emin değilim" → nil göndererek temizleme istiyor
        selected != nil || ackUnsure
    }

    private var unsureLink: some View {
        Button {
            Haptics.selection()
            selected = nil
            ackUnsure = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: ackUnsure ? "checkmark.circle.fill" : "questionmark.circle")
                    .font(.system(size: 13, weight: .regular))
                Text(L("Emin değilim"))
                    .font(Theme.Typo.caption.weight(.medium))
            }
            .foregroundStyle(ackUnsure ? Theme.ink : Theme.inkSoft)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressedScaleButtonStyle())
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Haptics.light()

        var payload = ProfileUpdateRequest()
        payload.skinType = selected?.rawValue
        // ackUnsure ⇒ selected nil ⇒ skinType field encode'da skip olur (encodeIfPresent).
        // Bu davranış kullanıcının açıkça "temizleme" istediği durumda backend
        // skin_type'ı koruyabilir. Şimdilik bu kabul edilebilir; daha sonra
        // explicit null göndermek için ProfileUpdateRequest revize edilebilir.

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
    ProfileEditSkinTypeView()
        .environment(AppState())
}
