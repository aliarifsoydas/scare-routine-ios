import SwiftUI

/// Cilt tonu (Fitzpatrick) düzenleme sheet'i — 6 ton seçeneği.
///
/// Fitzpatrick skalası UV hassasiyeti için kullanılır. Her satır kendi tonunda
/// daireli swatch + TR açıklama gösterir. Backend "fitzpatrick_type": 1..6 bekler.
struct ProfileEditFitzpatrickView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Int?
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// (tip, başlık, alt başlık, swatch rengi)
    private let options: [(Int, String, String, Color)] = [
        (1, "Tip 1 — Çok açık", "Hep yanar, asla bronzlaşmaz",
         Color(red: 1.00, green: 0.92, blue: 0.86)),
        (2, "Tip 2 — Açık", "Kolay yanar, az bronzlaşır",
         Color(red: 0.98, green: 0.85, blue: 0.74)),
        (3, "Tip 3 — Açık-orta", "Bazen yanar, kademeli bronzlaşır",
         Color(red: 0.88, green: 0.72, blue: 0.56)),
        (4, "Tip 4 — Orta", "Az yanar, kolay bronzlaşır",
         Color(red: 0.74, green: 0.55, blue: 0.40)),
        (5, "Tip 5 — Koyu", "Nadiren yanar, koyu bronzlaşır",
         Color(red: 0.55, green: 0.37, blue: 0.27)),
        (6, "Tip 6 — Çok koyu", "Asla yanmaz, hep koyu",
         Color(red: 0.30, green: 0.20, blue: 0.15))
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("UV hassasiyetini ve SPF önerilerini kişiselleştirmek için cilt tonunu seç.")
                            .font(Theme.Typo.body)
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.top, 4)

                        VStack(spacing: 10) {
                            ForEach(options, id: \.0) { opt in
                                fitzCard(type: opt.0,
                                         title: opt.1,
                                         subtitle: opt.2,
                                         swatch: opt.3)
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
            .navigationTitle("Cilt tonu")
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
                            .disabled(selected == nil)
                            .fontWeight(.semibold)
                    }
                }
            }
            .onAppear {
                selected = appState.currentProfile?.fitzpatrickType
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func fitzCard(type: Int, title: String, subtitle: String, swatch: Color) -> some View {
        Button {
            Haptics.selection()
            selected = type
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(swatch)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .strokeBorder(Theme.divider, lineWidth: 1)
                        )
                    if selected == type {
                        Circle()
                            .strokeBorder(Theme.onAccent, lineWidth: 2)
                            .frame(width: 44, height: 44)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Theme.Typo.headline)
                        .foregroundStyle(selected == type ? Theme.onAccent : Theme.ink)
                    Text(subtitle)
                        .font(Theme.Typo.caption)
                        .foregroundStyle(selected == type ? Theme.onAccent.opacity(0.75) : Theme.inkSoft)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                ZStack {
                    if selected == type {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(Theme.onAccent)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.4).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
                .frame(width: 22, height: 22)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(selected == type ? Theme.ink : Theme.canvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(selected == type ? Color.clear : Theme.divider, lineWidth: 1)
            )
            .shadow(color: selected == type ? Theme.ink.opacity(0.14) : .clear,
                    radius: 10, x: 0, y: 4)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: selected)
        }
        .buttonStyle(PressedScaleButtonStyle())
    }

    private func save() {
        guard let t = selected, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Haptics.light()

        var payload = ProfileUpdateRequest()
        payload.fitzpatrickType = t

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
    ProfileEditFitzpatrickView()
        .environment(AppState())
}
