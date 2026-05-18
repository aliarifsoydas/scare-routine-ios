import SwiftUI

/// Profil ülke seçim sheet'i. ISO 3166-1 alpha-2 kodu olarak PUT /v1/me/profile'a gider.
/// Native iOS Form + Picker pattern — Theme korunur.
struct ProfileEditCountryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var selectedCode: String = "TR"
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?
    @State private var searchQuery: String = ""

    /// 30 popüler ülke + global. Onboarding ile aynı liste, alfabetik.
    private let countries: [(code: String, nameTR: String, flag: String)] = [
        ("AE", "Birleşik Arap Emirlikleri", "🇦🇪"),
        ("AR", "Arjantin", "🇦🇷"),
        ("AT", "Avusturya", "🇦🇹"),
        ("AU", "Avustralya", "🇦🇺"),
        ("AZ", "Azerbaycan", "🇦🇿"),
        ("BE", "Belçika", "🇧🇪"),
        ("BG", "Bulgaristan", "🇧🇬"),
        ("BR", "Brezilya", "🇧🇷"),
        ("CA", "Kanada", "🇨🇦"),
        ("CH", "İsviçre", "🇨🇭"),
        ("CN", "Çin", "🇨🇳"),
        ("DE", "Almanya", "🇩🇪"),
        ("EG", "Mısır", "🇪🇬"),
        ("ES", "İspanya", "🇪🇸"),
        ("FR", "Fransa", "🇫🇷"),
        ("GB", "Birleşik Krallık", "🇬🇧"),
        ("GR", "Yunanistan", "🇬🇷"),
        ("IL", "İsrail", "🇮🇱"),
        ("IN", "Hindistan", "🇮🇳"),
        ("IT", "İtalya", "🇮🇹"),
        ("JP", "Japonya", "🇯🇵"),
        ("KR", "Güney Kore", "🇰🇷"),
        ("KZ", "Kazakistan", "🇰🇿"),
        ("MA", "Fas", "🇲🇦"),
        ("MX", "Meksika", "🇲🇽"),
        ("NL", "Hollanda", "🇳🇱"),
        ("NZ", "Yeni Zelanda", "🇳🇿"),
        ("RO", "Romanya", "🇷🇴"),
        ("RU", "Rusya", "🇷🇺"),
        ("SA", "Suudi Arabistan", "🇸🇦"),
        ("TR", "Türkiye", "🇹🇷"),
        ("UA", "Ukrayna", "🇺🇦"),
        ("US", "Amerika Birleşik Devletleri", "🇺🇸"),
        ("ZA", "Güney Afrika", "🇿🇦")
    ]

    private var filtered: [(code: String, nameTR: String, flag: String)] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return countries }
        return countries.filter { $0.nameTR.lowercased().contains(q) || $0.code.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(filtered, id: \.code) { c in
                        Button {
                            selectedCode = c.code
                            Haptics.selection()
                        } label: {
                            HStack(spacing: 12) {
                                Text(c.flag)
                                    .font(.system(size: 22))
                                Text(c.nameTR)
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                if selectedCode == c.code {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Theme.ink)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Yaşadığın bölge cilt önerilerini hava ve UV koşullarına göre kişiselleştirmemize yardım eder.")
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "Ülke ara")
            .navigationTitle("Ülke")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                        .disabled(isSaving || selectedCode == appState.currentProfile?.country)
                        .fontWeight(.semibold)
                }
            }
            .alert("Hata", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Tamam") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear {
                if let c = appState.currentProfile?.country, !c.isEmpty {
                    selectedCode = c.uppercased()
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Haptics.light()
        var payload = ProfileUpdateRequest()
        payload.country = selectedCode
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
