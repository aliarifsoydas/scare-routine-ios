import Foundation
import SwiftUI
import ObjectiveC.runtime

/// Locale-aware string lookup — Apple'ın `String(localized:)` cache problemini bypass eder.
///
/// **Neden gerek**: Xcode 26'da `String(localized: "X")` ve `Text("X")` `LocalizedStringResource`
/// kullanır; bu cache mid-session `AppleLanguages` değişimine cevap vermez (sadece restart).
/// `Locale.autoupdatingCurrent` da app içi `UserDefaults["AppleLanguages"]` değişimini sessizce
/// yoksayar.
///
/// **Çözüm**: `Bundle(path:)` ile her çağrıda doğrudan `tr.lproj`/`en.lproj` binary plist'ten
/// okuruz. Cache yok, restart yok. Mass-replaced for all `String(localized:)` callsites.
public func L(_ key: String) -> String {
    let bundle = ScareLocalizedBundle.activeBundle
    if let bundle {
        let result = bundle.localizedString(forKey: key, value: "__SCARE_MISS__", table: nil)
        if result == "__SCARE_MISS__" {
            // Sub-bundle'da yok → key kendisi source value (TR source language)
            return key
        }
        return result
    }
    // System fallback (current == .system)
    return Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

/// In-app dil seçici — **Bundle swizzling** ile anlık dil değişimi.
///
/// **Neden swizzling**: SwiftUI `Text("...")` catalog lookup'ı için `Bundle.main`'i
/// kullanır. `.environment(\.locale, ...)` SADECE formatter'ları (date/number) etkiler;
/// catalog lookup için işe yaramaz. Anlık değişim için Bundle.main'in
/// `localizedString` metodunu override etmek gerek.
///
/// **Production pattern**: Duolingo, Toledo, Localize-Swift, BartyCrouch hepsi bu
/// pattern'i kullanır. App Store review-safe, documented.
///
/// **SwiftUI refresh**: Xcode 26 Text catalog lookup'ı Bundle.main override'ı
/// bypass ediyor; tam refresh için app restart gerekiyor (Apple-blessed pattern).
/// Picker, restart prompt gösterir; user `exit(0)` ile app'i kapatır, manuel açar.
@MainActor
@Observable
final class LanguageManager {
    static let shared = LanguageManager()

    enum AppLanguage: String, CaseIterable, Identifiable {
        case system, tr, en
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .system: return "Sistem"
            case .tr: return "Türkçe"
            case .en: return "English"
            }
        }

        /// `Bundle(path:)` için locale identifier; nil → sistem fallback.
        var localeId: String? {
            switch self {
            case .system: return nil
            case .tr: return "tr"
            case .en: return "en"
            }
        }
    }

    private let storageKey = "scare.app.language"

    var current: AppLanguage {
        didSet {
            UserDefaults.standard.set(current.rawValue, forKey: storageKey)
            applyLanguage()
            // `L(key)` ve ViewModifier'ler için aktif bundle'ı güncelle
            ScareLocalizedBundle.activeBundle = currentBundle
            if ScareLocalizedBundle.loggingEnabled {
                print("[i18n] 🔄 Language changed: \(oldValue.rawValue) → \(current.rawValue)")
                print("[i18n]    currentBundle: \(currentBundle?.bundlePath ?? "nil (system)")")
                print("[i18n]    effectiveLocale: \(effectiveLocale.identifier)")
                print("[i18n]    activeBundle: \(ScareLocalizedBundle.activeBundle?.bundlePath ?? "nil")")
            }
        }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? "system"
        self.current = AppLanguage(rawValue: raw) ?? .system
        // Bundle.main'i ilk init'te swizzle et (idempotent).
        ScareLocalizedBundle.activate()
        applyLanguage()
        // İlk activeBundle init
        ScareLocalizedBundle.activeBundle = currentBundle

        if ScareLocalizedBundle.loggingEnabled {
            let appleLangs = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String] ?? []
            let preferred = Bundle.main.preferredLocalizations
            let dev = Bundle.main.developmentLocalization ?? "?"
            let avail = Bundle.main.localizations
            print("""
            [i18n] ====================== Boot ======================
            [i18n]  stored:               \(current.rawValue)
            [i18n]  AppleLanguages:       \(appleLangs)
            [i18n]  preferredLocalizations: \(preferred)
            [i18n]  developmentLocalization: \(dev)
            [i18n]  availableLocalizations:  \(avail)
            [i18n]  currentBundle path:   \(currentBundle?.bundlePath ?? "nil (system)")
            [i18n]  effectiveLocale:      \(effectiveLocale.identifier)
            [i18n]  swizzle active:       \(ScareLocalizedBundle.isCurrentlyActive)
            [i18n]  logging enabled:      \(ScareLocalizedBundle.loggingEnabled)
            [i18n]  logging verbose:      \(ScareLocalizedBundle.loggingVerbose)
            [i18n] ==================================================
            """)
            // Catalog özet (en.lproj/tr.lproj key sayıları)
            ScareLocalizedBundle.dumpCatalogSummary()
        }
    }

    private func applyLanguage() {
        // UIKit/system alerts + iOS Settings için AppleLanguages'a yaz
        if let id = current.localeId {
            UserDefaults.standard.set([id], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
    }

    /// Aktif lokalizasyon bundle'ı — `tr.lproj` veya `en.lproj` içinde.
    /// `nil` → sistem (super.localizedString fallback).
    var currentBundle: Bundle? {
        guard let id = current.localeId else { return nil }
        guard let path = Bundle.main.path(forResource: id, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    /// `.environment(\.locale, ...)` için — formatter'lar (date/number/percent) doğru
    /// locale ile çalışsın diye. Catalog lookup için `currentBundle` ayrı.
    var effectiveLocale: Locale {
        guard let id = current.localeId else { return .autoupdatingCurrent }
        return Locale(identifier: id)
    }

    /// "Sistem (Türkçe)" gibi display için
    func systemDisplayName() -> String {
        let sys = Locale.preferredLanguages.first ?? "tr"
        let primary = String(sys.prefix(2)).lowercased()
        let langName: String
        switch primary {
        case "tr": langName = "Türkçe"
        case "en": langName = "English"
        default: langName = sys.uppercased()
        }
        return "Sistem (\(langName))"
    }
}

// MARK: - Bundle swizzle

/// `Bundle.main`'in `localizedString` metodunu intercept eden subclass.
/// `object_setClass` ile Bundle.main'in class'ı runtime'da bu sınıfa swap edilir.
/// Sonra her `NSLocalizedString` / SwiftUI `Text("...")` çağrısı buradan geçer,
/// `LanguageManager.shared.currentBundle` ile doğru dilden okunur.
///
/// **Debug logging**: `[i18n]` prefixli loglar — miss durumlarında ❌, hit'lerde
/// (verbose mode'da) ✓. DEBUG build'lerde varsayılan açık. Override:
/// - UserDefaults `"i18n.debug"` (Bool) → master switch
/// - UserDefaults `"i18n.verbose"` (Bool) → her lookup'ı logla, sadece miss değil
/// - Launch arg `-i18nDebug 1/0`, `-i18nVerbose` (Xcode scheme'inden ayarla)
final class ScareLocalizedBundle: Bundle, @unchecked Sendable {
    nonisolated(unsafe) private static var isActivated = false

    /// `L(key)` helper için cache'lenmiş aktif bundle. LanguageManager.didSet'te güncellenir.
    /// nil → system locale (Apple default fallback).
    nonisolated(unsafe) static var activeBundle: Bundle? = nil

    /// Master switch — DEBUG build'de açık, RELEASE'de kapalı (override edilebilir).
    nonisolated(unsafe) static var loggingEnabled: Bool = {
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-i18nDebug"), idx + 1 < args.count {
            let v = args[idx + 1].lowercased()
            return v == "1" || v == "true" || v == "yes"
        }
        if let v = UserDefaults.standard.object(forKey: "i18n.debug") as? Bool {
            return v
        }
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    /// Her lookup'ı logla (default: sadece miss'leri logla, log spam'i önlemek için)
    nonisolated(unsafe) static var loggingVerbose: Bool = {
        if ProcessInfo.processInfo.arguments.contains("-i18nVerbose") { return true }
        return UserDefaults.standard.bool(forKey: "i18n.verbose")
    }()

    /// Kaç miss/hit gördük — bir defa booted dump için.
    nonisolated(unsafe) private static var missCount: Int = 0
    nonisolated(unsafe) private static var hitCount: Int = 0
    nonisolated(unsafe) private static var sysCount: Int = 0

    /// Görülen miss'lerin set'i — duplicate spam önler.
    nonisolated(unsafe) private static var seenMisses: Set<String> = []

    /// Public stats — debug menülerden çağrılabilir.
    static func i18nStats() -> (hits: Int, misses: Int, sys: Int, uniqueMisses: Int) {
        (hitCount, missCount, sysCount, seenMisses.count)
    }

    /// Görülen unique miss key'lerini dump et.
    static func dumpMisses() {
        print("[i18n] ===== Unique misses (\(seenMisses.count)) =====")
        for key in seenMisses.sorted() {
            print("[i18n]   ❌ \(key)")
        }
        print("[i18n] ===== End misses =====")
    }

    // MARK: - Catalog audit (runtime, derlenmiş .lproj/Localizable.strings okur)

    /// Derlenmiş `<locale>.lproj/Localizable.strings` binary plist'i oku.
    /// Apple compiler her locale için ayrı plist üretir; source-language için (TR)
    /// genellikle dosya yoktur ya da boştur (identity mapping çıkartılır).
    nonisolated static func readCompiledStrings(locale: String) -> [String: String]? {
        guard let lprojPath = Bundle.main.path(forResource: locale, ofType: "lproj"),
              let lprojBundle = Bundle(path: lprojPath),
              let stringsPath = lprojBundle.path(forResource: "Localizable", ofType: "strings"),
              let dict = NSDictionary(contentsOfFile: stringsPath) as? [String: String]
        else {
            return nil
        }
        return dict
    }

    /// Cached en.lproj contents (boot'ta bir kere okunur).
    nonisolated(unsafe) private static var _enDictCache: [String: String]?
    nonisolated(unsafe) private static var _enDictLoaded = false

    nonisolated static func englishDict() -> [String: String] {
        if _enDictLoaded { return _enDictCache ?? [:] }
        _enDictLoaded = true
        _enDictCache = readCompiledStrings(locale: "en")
        return _enDictCache ?? [:]
    }

    /// Catalog özet — boot'ta veya manuel olarak çağrılır.
    static func dumpCatalogSummary() {
        let en = readCompiledStrings(locale: "en") ?? [:]
        let tr = readCompiledStrings(locale: "tr") ?? [:]
        print("[i18n] ===== Catalog summary =====")
        print("[i18n]   en.lproj/Localizable.strings: \(en.count) keys")
        if tr.isEmpty {
            print("[i18n]   tr.lproj/Localizable.strings: yok (source language, identity mapping)")
        } else {
            print("[i18n]   tr.lproj/Localizable.strings: \(tr.count) keys")
        }
        // Source kaynak dilde (TR) key'in kendisi value'dur. EN'de olmayan = TR-only.
        // SwiftUI Text("...") çoğunlukla swizzle'ı bypass ettiği için, runtime tracking
        // pratikte çalışmıyor. Onun yerine: en.lproj'da varsa EN'i var, yoksa TR-only.
        print("[i18n] ===== End summary =====")
    }

    /// Tüm EN translation'larını yazdır (key=value). Uzun çıktı.
    static func dumpAllEN() {
        let en = readCompiledStrings(locale: "en") ?? [:]
        print("[i18n] ===== en.lproj contents (\(en.count) keys) =====")
        for key in en.keys.sorted() {
            let v = en[key] ?? ""
            let kt = key.count > 60 ? String(key.prefix(60)) + "…" : key
            let vt = v.count > 60 ? String(v.prefix(60)) + "…" : v
            print("[i18n]   ✓ \"\(kt)\" → \"\(vt)\"")
        }
        print("[i18n] ===== End EN dump =====")
    }

    /// Bir key'in EN'i var mı? Programmatic kullanım için (örn. badge gösterme).
    nonisolated static func hasEN(_ key: String) -> Bool {
        englishDict()[key] != nil
    }

    /// Bir key'in EN değerini dön — yoksa nil.
    nonisolated static func en(_ key: String) -> String? {
        englishDict()[key]
    }

    /// Bir TR key listesi al, hangileri EN'de yok onu göster.
    /// Per-screen debug: view'ın .onAppear'ında bu çağrılır → console'a status raporu basar.
    static func auditKeys(_ keys: [String], screen: String = "?") {
        let en = englishDict()
        var missing: [String] = []
        var present: [String] = []
        for key in keys {
            if en[key] != nil {
                present.append(key)
            } else {
                missing.append(key)
            }
        }
        print("[i18n] ===== Audit screen=\"\(screen)\" =====")
        print("[i18n]   total: \(keys.count) · with EN: \(present.count) · TR-only: \(missing.count)")
        if !missing.isEmpty {
            print("[i18n]   ❌ TR-only keys:")
            for k in missing {
                print("[i18n]     • \"\(k)\"")
            }
        }
        print("[i18n] ===== End audit =====")
    }

    static func activate() {
        guard !isActivated else { return }
        object_setClass(Bundle.main, ScareLocalizedBundle.self)
        isActivated = true
    }

    static var isCurrentlyActive: Bool { isActivated }

    /// Catalog sourceLanguage — Localizable.xcstrings'in `sourceLanguage` field'ı.
    /// Source language için Apple compiler `.lproj/Localizable.strings` ÜRETMEZ
    /// (key == value identity mapping). Yani tr.lproj'da TR key'leri yoktur;
    /// bunun manası: TR modda probe sentinel döner — ama bu MISS değil, identity.
    static let sourceLanguageCode = "tr"

    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        let currentLangId = MainActor.assumeIsolated({ LanguageManager.shared.current.localeId })
        let bundle = MainActor.assumeIsolated({ LanguageManager.shared.currentBundle })
        let lang = MainActor.assumeIsolated({ LanguageManager.shared.current.rawValue })
        let isSourceLang = (currentLangId == Self.sourceLanguageCode)

        let result: String
        let status: String

        if let bundle = bundle {
            // Sentinel ile probe — hedef bundle'da key var mı?
            let sentinel = "__SCARE_I18N_MISS__"
            let probe = bundle.localizedString(forKey: key, value: sentinel, table: tableName)
            if probe == sentinel {
                // Probe miss
                if isSourceLang {
                    // TR source: tr.lproj'da identity mapping yok — key zaten TR source string.
                    // super.localizedString'e fallback yapma! Çünkü Bundle.main cache hâlâ
                    // önceki AppleLanguages'ı (ör. "en") kullanabilir → yanlış dilde döner.
                    result = value ?? key
                    status = "OK_SRC"
                    Self.hitCount &+= 1
                } else {
                    // Genuine miss: non-source language'de translation yok.
                    // Source language değerini (key'i) dön — partial fallback.
                    result = value ?? key
                    status = "MISS"
                    Self.missCount &+= 1
                    Self.seenMisses.insert(key)
                }
            } else {
                result = probe
                status = "OK"
                Self.hitCount &+= 1
            }
        } else {
            // System fallback (currentLang == .system) — Apple'ın native flow'u
            result = super.localizedString(forKey: key, value: value, table: tableName)
            status = "SYS"
            Self.sysCount &+= 1
        }

        if Self.loggingEnabled {
            if status == "MISS" {
                // Sadece her unique key için bir kez logla — spam önle
                if Self.seenMisses.count <= 200 {
                    print("[i18n] ❌ MISS [\(lang)] \"\(truncate(key))\" → fallback \"\(truncate(result))\"")
                }
            } else if Self.loggingVerbose {
                print("[i18n] ✓  \(status)   [\(lang)] \"\(truncate(key))\" → \"\(truncate(result))\"")
            }
        }

        return result
    }

    /// Uzun key/value'ları kısalt — log spam önle.
    private func truncate(_ s: String, max: Int = 80) -> String {
        if s.count <= max { return s }
        return String(s.prefix(max)) + "…"
    }
}

// MARK: - Picker UI

struct LanguagePickerView: View {
    @Environment(LanguageManager.self) private var lang
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var lang = lang
        NavigationStack {
            List {
                Section {
                    ForEach(LanguageManager.AppLanguage.allCases) { option in
                        Button {
                            Haptics.selection()
                            if option == lang.current {
                                dismiss()
                                return
                            }
                            // Live switch — L() + .id(lang.current) ile anlık geçer
                            lang.current = option
                            // Picker'ı kapat, sheet dismiss olunca dil değişimi görünür
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option == .system ? lang.systemDisplayName() : option.displayName)
                                        .font(.body)
                                        .foregroundStyle(Theme.ink)
                                    if option == .system {
                                        Text("Cihazın diline uy")
                                            .font(.caption)
                                            .foregroundStyle(Theme.inkSoft)
                                    }
                                }
                                Spacer()
                                if lang.current == option {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.accent)
                                        .fontWeight(.semibold)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text(L("Dil seçimi cihazdaki tüm metinler için anında uygulanır."))
                        .font(.caption)
                }

                #if DEBUG
                // DEBUG: i18n catalog + runtime miss paneli
                Section {
                    Button {
                        ScareLocalizedBundle.dumpCatalogSummary()
                    } label: {
                        debugRow(icon: "doc.text.magnifyingglass",
                                 title: "Catalog özeti",
                                 sub: "en.lproj + tr.lproj key sayıları")
                    }
                    Button {
                        ScareLocalizedBundle.dumpAllEN()
                    } label: {
                        debugRow(icon: "list.bullet.rectangle",
                                 title: "Tüm EN key'leri dump et",
                                 sub: "en.lproj/Localizable.strings → console (uzun)")
                    }
                    Button {
                        let stats = ScareLocalizedBundle.i18nStats()
                        print("[i18n] 📊 Stats: hits=\(stats.hits) misses=\(stats.misses) sys=\(stats.sys) uniqueMisses=\(stats.uniqueMisses)")
                        ScareLocalizedBundle.dumpMisses()
                    } label: {
                        let stats = ScareLocalizedBundle.i18nStats()
                        debugRow(icon: "exclamationmark.bubble",
                                 title: "Runtime miss dump",
                                 sub: "\(stats.uniqueMisses) eksik · \(stats.hits) hit · \(stats.misses) miss (sadece String(localized:) çağrıları)")
                    }
                    Toggle(isOn: .init(
                        get: { ScareLocalizedBundle.loggingVerbose },
                        set: { newValue in
                            ScareLocalizedBundle.loggingVerbose = newValue
                            UserDefaults.standard.set(newValue, forKey: "i18n.verbose")
                            print("[i18n] verbose logging: \(newValue)")
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Verbose i18n log")
                                .font(.body)
                            Text("Her String(localized:) lookup'ı console'a yaz")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("DEBUG · i18n")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("Not: SwiftUI `Text(\"...\")` Xcode 26'da LocalizedStringResource cache'i kullanıyor, Bundle.main swizzle'ı bypass ediyor. Per-page debug için view'lara `.i18nAudit(screen:keys:)` modifier ekle.")
                        .font(.caption2)
                }
                #endif
            }
            .navigationTitle(L("Dil"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Tamam")) { dismiss() }
                }
            }
            // Restart alert KALDIRILDI — L() + .id(lang.current) ile dil anlık geçer,
            // popup'a gerek yok.
        }
    }

    #if DEBUG
    @ViewBuilder
    private func debugRow(icon: String, title: String, sub: String) -> some View {
        HStack {
            Image(systemName: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
        }
    }
    #endif
}

// MARK: - Per-screen audit ViewModifier

extension View {
    /// View .onAppear'da verilen TR key listesini denetler — hangileri EN'de var,
    /// hangileri TR-only? Console'a `[i18n] Audit screen="..."` raporu basar.
    ///
    /// Kullanım:
    /// ```swift
    /// ProfileView()
    ///     .i18nAudit(screen: "Profile", keys: [
    ///         "Cilt tipi", "Yağlı", "Hassas", "Profil"
    ///     ])
    /// ```
    ///
    /// SwiftUI Text Xcode 26'da Bundle.main swizzle'ı bypass ettiği için runtime
    /// otomatik takip çalışmaz — manuel key listesi vermek gerek.
    func i18nAudit(screen: String, keys: [String]) -> some View {
        #if DEBUG
        return self.onAppear {
            ScareLocalizedBundle.auditKeys(keys, screen: screen)
        }
        #else
        return self
        #endif
    }
}
