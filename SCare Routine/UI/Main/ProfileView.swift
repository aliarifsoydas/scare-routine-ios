import SwiftUI
import UserNotifications
import UIKit

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

    /// Notification permission durumu — onAppear + permission iste sonrası refresh.
    @State private var notifAuthStatus: UNAuthorizationStatus = .notDetermined
    /// HealthKit bağlantı durumu — Apple "denied" rapor etmez, sadece "dialog soruldu mu" tahmini.
    @State private var healthKitStatus: HealthKitService.ConnectionStatus = .unknown
    /// In-app dil picker sheet
    @State private var showLanguagePicker: Bool = false
    @Environment(LanguageManager.self) private var languageManager

    /// Picker satırında gösterilecek aktif dil
    private var currentLanguageDisplayName: String {
        switch languageManager.current {
        case .system: return "Sistem"
        case .tr: return "Türkçe"
        case .en: return "English"
        }
    }

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
        return L("Adını ekle")
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

                    Section(L("Profil bilgileri")) {
                        completeRow(
                            icon: "person.text.rectangle",
                            title: L("Ad"),
                            value: appState.currentUser?.displayName?.isEmpty == false
                                ? appState.currentUser?.displayName
                                : nil,
                            placeholder: L("Eklemek için dokun")
                        ) { editSheet = .displayName }

                        completeRow(
                            icon: "calendar",
                            title: L("Doğum tarihi"),
                            value: birthDateDisplay,
                            placeholder: L("Eklemek için dokun")
                        ) { editSheet = .birthDate }

                        completeRow(
                            icon: "figure.stand",
                            title: L("Cinsiyet"),
                            value: genderDisplay,
                            placeholder: L("Eklemek için dokun")
                        ) { editSheet = .gender }
                    }

                    Section(L("Cilt profili")) {
                        completeRow(
                            icon: "drop.fill",
                            title: L("Cilt tipi"),
                            value: skinTypeDisplay,
                            placeholder: L("Eklemek için dokun")
                        ) { editSheet = .skinType }

                        completeRow(
                            icon: "sun.max.fill",
                            title: L("Cilt tonu"),
                            value: fitzpatrickDisplay,
                            placeholder: L("Eklemek için dokun")
                        ) { editSheet = .fitzpatrick }
                    }

                    Section(L("Yaşam tarzı")) {
                        completeRow(
                            icon: "heart.text.square",
                            title: L("Yaşam tarzı"),
                            value: lifestyleSummary,
                            placeholder: L("Sigara, alkol, uyku, su")
                        ) { editSheet = .lifestyle }
                    }

                    Section(L("Tercihler")) {
                        completeRow(
                            icon: "camera.viewfinder",
                            title: L("Fotoğraf modu"),
                            value: photoModeDisplay,
                            placeholder: L("Sadece veri saklanıyor")
                        ) { editSheet = .photoMode }

                        // Dil — in-app picker.
                        // Modern apps (Duolingo, WhatsApp, Headspace) bu pattern'i kullanır:
                        // anlık `.environment(\.locale)` switch ile SwiftUI tree refresh olur.
                        // Settings'e gönderme antipattern, kullanıcı haklı.
                        Button {
                            Haptics.selection()
                            showLanguagePicker = true
                        } label: {
                            HStack {
                                Label(L("Dil"), systemImage: "globe")
                                Spacer()
                                Text(currentLanguageDisplayName)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.inkSoft)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.inkMute)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        completeRow(
                            icon: "location",
                            title: L("Ülke"),
                            value: profile?.country?.uppercased(),
                            placeholder: L("Eklemek için dokun")
                        ) { editSheet = .country }

                        // Bildirimler — permission durumuna göre interaktif
                        Button {
                            handleNotificationTap()
                        } label: {
                            HStack {
                                Label(L("Bildirimler"), systemImage: "bell.fill")
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                notifStatusBadge
                            }
                        }
                        .buttonStyle(.plain)

                        // Apple Health bağlantısı
                        Button {
                            handleHealthKitTap()
                        } label: {
                            HStack {
                                Label(L("Apple Health"), systemImage: "heart.fill")
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                healthKitStatusBadge
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(healthKitStatus == .unsupported)
                    }

                    Section(L("Hesap")) {
                        Button {
                            Task {
                                isProcessing = true
                                await appState.signOut()
                                isProcessing = false
                            }
                        } label: {
                            Label(L("Çıkış yap"), systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        .disabled(isProcessing)

                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label(L("Hesabı sil"), systemImage: "trash")
                        }
                    }

                    Section {
                        VStack(alignment: .center, spacing: 4) {
                            Text(L("SCare Routine"))
                                .font(Theme.Typo.caption.weight(.semibold))
                                .foregroundStyle(Theme.inkMute)
                            Text(L("v0.1.0"))
                                .font(Theme.Typo.caption)
                                .foregroundStyle(Theme.inkMute)
                        }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(L("Profil"))
            .navigationBarTitleDisplayMode(.large)
            .task {
                // Tab açıldığında en güncel state'i çek — kullanıcı başka cihazda
                // güncelleme yapmış olabilir
                await appState.refreshMe()
                // Permission durumlarını da refresh et
                notifAuthStatus = await NotificationService.shared.authorizationStatus()
                healthKitStatus = await HealthKitService.shared.connectionStatus()
            }
            .alert(L("Hesabını silmek istiyor musun?"), isPresented: $showDeleteConfirm) {
                Button(L("İptal"), role: .cancel) {}
                Button(L("Hesabımı sil"), role: .destructive) {
                    Task {
                        isProcessing = true
                        try? await AuthService.shared.deleteAccount()
                        await appState.signOut()
                        isProcessing = false
                    }
                }
            } message: {
                Text(L("Bu işlem geri alınamaz. Tüm verilerin (profil, ürünler, rutinler, fotoğraflar) silinecek."))
            }
            .sheet(isPresented: $showLanguagePicker) {
                LanguagePickerView()
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
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
            .accessibilityLabel(L("Adı düzenle"))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surface)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Notifications row

    @ViewBuilder
    private var notifStatusBadge: some View {
        switch notifAuthStatus {
        case .authorized, .provisional, .ephemeral:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                Text(L("Açık"))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.green.opacity(0.12)))
        case .denied:
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                Text(L("Kapalı"))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.alert)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.alert.opacity(0.12)))
        case .notDetermined:
            Text(L("İzin ver"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Theme.ink))
        @unknown default:
            Text(L("—")).foregroundStyle(Theme.inkMute)
        }
    }

    @ViewBuilder
    private var healthKitStatusBadge: some View {
        switch healthKitStatus {
        case .requested:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                Text(L("Bağlı"))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.green.opacity(0.12)))
        case .notRequested:
            Text(L("Bağla"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Theme.ink))
        case .unsupported:
            Text(L("Desteklenmiyor"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkMute)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Theme.surfaceLow))
        case .unknown:
            Text(L("—"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkMute)
        }
    }

    private func handleHealthKitTap() {
        Haptics.light()
        switch healthKitStatus {
        case .notRequested:
            // İzin diyaloğunu göster — Apple sleep/sex/birth/fitz hepsini soracak.
            Task {
                _ = try? await HealthKitService.shared.requestAuthorization()
                healthKitStatus = await HealthKitService.shared.connectionStatus()
                // Dialog'tan sonra hemen sync dene — kullanıcı allow ettiyse veri gelsin
                await appState.syncHealthKitHistory()
                await appState.syncHealthKitSleepToProfile()
            }
        case .requested, .unknown:
            // Diyalog daha önce gösterilmiş. Apple state'i tek taraflı veremiyor →
            // kullanıcı Settings'ten Health > SCare Routine'e gidip manuel açar/kapatır.
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        case .unsupported:
            break
        }
    }

    private func handleNotificationTap() {
        Haptics.light()
        switch notifAuthStatus {
        case .notDetermined:
            // İzin iste → granted ise Tier 0 sched + bekleyen admin queue'yu da poll et
            Task {
                await NotificationService.shared.loadTemplates(locale: appState.locale)
                let granted = await NotificationService.shared.requestAuthorization()
                if granted {
                    await NotificationService.shared.scheduleTier0Activation()
                    await NotificationService.shared.syncPendingQueue()
                }
                notifAuthStatus = await NotificationService.shared.authorizationStatus()
            }
        case .denied:
            // iOS API'siyle kapalıyı açamayız — Settings'e yönlendir
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        case .authorized, .provisional, .ephemeral:
            // Açıksa Settings'e gitsin (kapatmak için tek yol)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        @unknown default:
            break
        }
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
        display.locale = LanguageManager.shared.effectiveLocale
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
            case 1: return L("fitzpatrick_1")
            case 2: return L("fitzpatrick_2")
            case 3: return L("fitzpatrick_3")
            case 4: return L("fitzpatrick_4")
            case 5: return L("fitzpatrick_5")
            case 6: return L("fitzpatrick_6")
            default: return ""
            }
        }()
        // "Tip %lld" / "Type %lld" format string — catalog locale-aware
        let typeLabel = String(format: L("Tip %lld"), t)
        return desc.isEmpty ? typeLabel : "\(typeLabel) — \(desc)"
    }

    private var photoModeDisplay: String? {
        guard let raw = profile?.defaultPhotoMode else { return nil }
        switch raw {
        case PhotoMode.photoKept.rawValue: return L("Fotoğraflar saklanıyor")
        case PhotoMode.metricsOnly.rawValue: return L("Sadece veri saklanıyor")
        default: return raw
        }
    }

    private var lifestyleSummary: String? {
        guard let life = profile?.lifestyle else { return nil }
        var parts: [String] = []
        if let smoke = life.smoking {
            parts.append(String(format: L("profile_smoking_prefix"), smokingTR(smoke)))
        }
        if let alcohol = life.alcoholFrequency {
            parts.append(String(format: L("profile_alcohol_prefix"), alcoholTR(alcohol)))
        }
        if let s = life.sleepHoursAvg {
            let hoursStr = s.formatted(.number.precision(.fractionLength(1)))
            let hoursLabel = String(format: L("sleep_hours_short"), hoursStr)
            parts.append(String(format: L("profile_sleep_prefix"), hoursLabel))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func smokingTR(_ raw: String) -> String {
        switch raw {
        case "never": return L("smoking_never")
        case "occasionally", "occasional": return L("smoking_occasional")
        case "daily": return L("smoking_daily")
        default: return raw.capitalized
        }
    }

    private func alcoholTR(_ raw: String) -> String {
        switch raw {
        case "never": return L("alcohol_never")
        case "rare", "rarely": return L("alcohol_rarely")
        case "weekly": return L("alcohol_weekly")
        case "daily": return L("alcohol_daily")
        default: return raw.capitalized
        }
    }
}
