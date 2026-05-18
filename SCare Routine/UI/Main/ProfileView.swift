import SwiftUI

/// Profil tab'ı — hesap bilgileri, profil tamamlama satırları, tercihler, hesap aksiyonları.
///
/// Her satır gerçek `appState.currentProfile` / `appState.currentUser` değerlerini okur,
/// tap edildiğinde ilgili `ProfileEdit*View` sheet'ini açar. Sheet'ler kapanırken
/// `AppState.refreshMe()` çağrılır, böylece bu ekran otomatik tazelenir.
struct ProfileView: View {
    let user: AuthUser
    @Environment(AppState.self) private var appState

    @State private var showDeleteConfirm = false
    @State private var isProcessing = false
    @State private var editSheet: EditSheet?

    /// Açılacak edit sheet'i (Identifiable ile native .sheet(item:) için)
    enum EditSheet: String, Identifiable {
        case displayName
        case skinType
        case birthDate
        case gender
        case fitzpatrick
        case lifestyle
        case photoMode
        case country
        var id: String { rawValue }
    }

    // MARK: - Derived state

    private var displayName: String {
        let live = appState.currentUser?.displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let live, !live.isEmpty { return live }
        if let fallback = user.displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !fallback.isEmpty { return fallback }
        return "Adını ekle"
    }

    private var email: String? {
        appState.currentUser?.email ?? user.email
    }

    private var profile: ProfileData? { appState.currentProfile }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                List {
                    Section {
                        userCard
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    }

                    Section("Profil bilgileri") {
                        completeRow(
                            icon: "person.text.rectangle",
                            title: "Ad",
                            value: appState.currentUser?.displayName?.isEmpty == false
                                ? appState.currentUser?.displayName
                                : nil,
                            placeholder: "Eklemek için dokun"
                        ) { editSheet = .displayName }

                        completeRow(
                            icon: "calendar",
                            title: "Doğum tarihi",
                            value: birthDateDisplay,
                            placeholder: "Eklemek için dokun"
                        ) { editSheet = .birthDate }

                        completeRow(
                            icon: "figure.stand",
                            title: "Cinsiyet",
                            value: genderDisplay,
                            placeholder: "Eklemek için dokun"
                        ) { editSheet = .gender }
                    }

                    Section("Cilt profili") {
                        completeRow(
                            icon: "drop.fill",
                            title: "Cilt tipi",
                            value: skinTypeDisplay,
                            placeholder: "Eklemek için dokun"
                        ) { editSheet = .skinType }

                        completeRow(
                            icon: "sun.max.fill",
                            title: "Cilt tonu",
                            value: fitzpatrickDisplay,
                            placeholder: "Eklemek için dokun"
                        ) { editSheet = .fitzpatrick }
                    }

                    Section("Yaşam tarzı") {
                        completeRow(
                            icon: "heart.text.square",
                            title: "Yaşam tarzı",
                            value: lifestyleSummary,
                            placeholder: "Sigara, alkol, uyku, su"
                        ) { editSheet = .lifestyle }
                    }

                    Section("Tercihler") {
                        completeRow(
                            icon: "camera.viewfinder",
                            title: "Fotoğraf modu",
                            value: photoModeDisplay,
                            placeholder: "Sadece veri saklanıyor"
                        ) { editSheet = .photoMode }

                        // Dil — basit toggle (TR/EN)
                        Button {
                            Haptics.selection()
                            let newLocale = appState.locale == "tr" ? "en" : "tr"
                            appState.setLocale(newLocale)
                            Task {
                                var payload = ProfileUpdateRequest()
                                payload.locale = newLocale
                                try? await UserService.shared.updateProfile(payload)
                                await appState.refreshMe()
                            }
                        } label: {
                            HStack {
                                Label("Dil", systemImage: "globe")
                                Spacer()
                                Text(appState.locale.uppercased())
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.inkSoft)
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.inkMute)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        completeRow(
                            icon: "location",
                            title: "Ülke",
                            value: profile?.country?.uppercased(),
                            placeholder: "Eklemek için dokun"
                        ) { editSheet = .country }

                        // Bildirimler — "Yakında" rozeti, henüz feature yok
                        HStack {
                            Label("Bildirimler", systemImage: "bell.fill")
                            Spacer()
                            Text("Yakında")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Theme.surfaceLow))
                                .foregroundStyle(Theme.inkSoft)
                        }
                    }

                    Section("Hesap") {
                        Button {
                            Task {
                                isProcessing = true
                                await appState.signOut()
                                isProcessing = false
                            }
                        } label: {
                            Label("Çıkış yap", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        .disabled(isProcessing)

                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Hesabı sil", systemImage: "trash")
                        }
                    }

                    Section {
                        VStack(alignment: .center, spacing: 4) {
                            Text("SCare Routine")
                                .font(Theme.Typo.caption.weight(.semibold))
                                .foregroundStyle(Theme.inkMute)
                            Text("v0.1.0")
                                .font(Theme.Typo.caption)
                                .foregroundStyle(Theme.inkMute)
                        }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.large)
            .task {
                // Tab açıldığında en güncel state'i çek — kullanıcı başka cihazda
                // güncelleme yapmış olabilir
                await appState.refreshMe()
            }
            .alert("Hesabını silmek istiyor musun?", isPresented: $showDeleteConfirm) {
                Button("İptal", role: .cancel) {}
                Button("Hesabımı sil", role: .destructive) {
                    Task {
                        isProcessing = true
                        try? await AuthService.shared.deleteAccount()
                        await appState.signOut()
                        isProcessing = false
                    }
                }
            } message: {
                Text("Bu işlem geri alınamaz. Tüm verilerin (profil, ürünler, rutinler, fotoğraflar) silinecek.")
            }
            .sheet(item: $editSheet) { sheet in
                switch sheet {
                case .displayName: ProfileEditDisplayNameView()
                case .skinType:    ProfileEditSkinTypeView()
                case .birthDate:   ProfileEditBirthDateView()
                case .gender:      ProfileEditGenderView()
                case .fitzpatrick: ProfileEditFitzpatrickView()
                case .lifestyle:   ProfileEditLifestyleView()
                case .photoMode:   ProfileEditPhotoModeView()
                case .country:     ProfileEditCountryView()
                }
            }
        }
    }

    // MARK: - Bileşenler

    private var userCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.inkSoft)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(Theme.Typo.headline)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if let email {
                    Text(email)
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                editSheet = .displayName
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.canvas))
                    .overlay(Circle().strokeBorder(Theme.divider, lineWidth: 1))
            }
            .buttonStyle(PressedScaleButtonStyle())
            .accessibilityLabel("Adı düzenle")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surface)
        )
        .padding(.horizontal, 16)
    }

    private func completeRow(
        icon: String,
        title: String,
        value: String?,
        placeholder: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            Haptics.light()
            action()
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 26)
                Text(title)
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 12)
                if let v = value, !v.isEmpty {
                    Text(v)
                        .font(Theme.Typo.caption.weight(.medium))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                        .multilineTextAlignment(.trailing)
                } else {
                    Text(placeholder)
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.inkMute)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkMute)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Display helpers

    private var skinTypeDisplay: String? {
        guard let raw = profile?.skinType, let t = SkinType(rawValue: raw) else { return nil }
        return t.displayTR
    }

    private var birthDateDisplay: String? {
        guard let bd = profile?.birthDate else { return nil }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        guard let parsed = f.date(from: bd) else { return bd }

        let years = Calendar.current.dateComponents([.year], from: parsed, to: .now).year ?? 0
        let display = DateFormatter()
        display.locale = Locale(identifier: "tr_TR")
        display.dateStyle = .medium
        return "\(display.string(from: parsed)) (\(years))"
    }

    private var genderDisplay: String? {
        guard let raw = profile?.gender, let g = OnboardingGender(rawValue: raw) else { return nil }
        return g.displayTR
    }

    private var fitzpatrickDisplay: String? {
        guard let t = profile?.fitzpatrickType else { return nil }
        let desc: String = {
            switch t {
            case 1: return "Çok açık"
            case 2: return "Açık"
            case 3: return "Açık-orta"
            case 4: return "Orta"
            case 5: return "Koyu"
            case 6: return "Çok koyu"
            default: return ""
            }
        }()
        return desc.isEmpty ? "Tip \(t)" : "Tip \(t) — \(desc)"
    }

    private var photoModeDisplay: String? {
        guard let raw = profile?.defaultPhotoMode else { return nil }
        switch raw {
        case PhotoMode.photoKept.rawValue: return "Fotoğraflar saklanıyor"
        case PhotoMode.metricsOnly.rawValue: return "Sadece veri saklanıyor"
        default: return raw
        }
    }

    private var lifestyleSummary: String? {
        guard let life = profile?.lifestyle else { return nil }
        var parts: [String] = []
        if let smoke = life.smoking {
            parts.append("Sigara: \(smokingTR(smoke))")
        }
        if let alcohol = life.alcoholFrequency {
            parts.append("Alkol: \(alcoholTR(alcohol))")
        }
        if let s = life.sleepHoursAvg {
            parts.append("Uyku: \(String(format: "%.1f", s)) sa")
        }
        if let w = life.waterGlassesPerDay {
            parts.append("Su: \(w) bardak")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func smokingTR(_ raw: String) -> String {
        switch raw {
        case "never": return "Hiç"
        case "occasionally", "occasional": return "Ara sıra"
        case "daily": return "Günlük"
        default: return raw.capitalized
        }
    }

    private func alcoholTR(_ raw: String) -> String {
        switch raw {
        case "never": return "Hiç"
        case "rare", "rarely": return "Nadiren"
        case "weekly": return "Haftalık"
        case "daily": return "Günlük"
        default: return raw.capitalized
        }
    }
}
