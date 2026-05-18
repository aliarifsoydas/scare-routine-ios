import Foundation
import SwiftUI

// MARK: - Onboarding adımları (6 adım, Cal AI / Yazio / Headspace 2026 best practice'lerine göre sentez)
//
//   1. welcome      → interaktif selamlama + "5 sorum var" ton
//   2. essentials   → locale + zorunlu account / opsiyonel AI consent + disclaimer
//   3. skinType     → ANCHOR: cilt tipi seçimi + mini reveal (ingredient ipucu)
//   4. healthSync   → opsiyonel HealthKit (skippable)
//   5. preferences  → kategoriler + foto modu
//   6. finalPlan    → kişisel plan reveal + "Hadi başlayalım" (SUBMIT burada)
//
// Endişeler / fitzpatrick / lifestyle gibi opsiyonel alanlar artık onboarding'de
// SORULMAZ. Bunlardan bir kısmı HealthKit'ten gelir; geri kalanı kullanıcı
// "Profilini tamamla" CTA'sıyla sonradan ekler.

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case essentials
    case skinType
    case healthSync
    case preferences
    case finalPlan

    var id: Int { rawValue }

    /// 0..1 arası ilerleme. Welcome ve finalPlan'da özel davranış.
    /// welcome: 0, finalPlan: 1, ortadakiler eşit dağılır.
    var progress: Double {
        let total = Double(OnboardingStep.allCases.count - 1)
        guard total > 0 else { return 1 }
        return Double(rawValue) / total
    }

    /// Welcome'da back yok. FinalPlan'dan geri dönüp Preferences'i düzenleyebilir.
    var canGoBack: Bool { self != .welcome }

    /// Üst bar'da "Atla" butonu artık YOK — kullanıcı şikayetine göre.
    /// HealthSync'in alttaki secondary butonu skip için yeterli.
    var isSkippable: Bool { false }

    /// Progress bar gösterilsin mi? Welcome'da gizli.
    /// Top bar HER ZAMAN 56pt yer kaplar (görsel sıçramayı önlemek için);
    /// içeride sadece içerik değişir.
    var showsProgress: Bool { self != .welcome }

    /// Top bar görünür mü? Welcome'da hiç görünmez; finalPlan'da sadece progress (dolu).
    var showsTopBar: Bool { self != .welcome }

    /// "2/6" gibi okunabilir konum
    var positionLabel: String {
        let total = OnboardingStep.allCases.count
        return "\(rawValue + 1)/\(total)"
    }
}

// MARK: - Yardımcı tipler

enum OnboardingGender: String, CaseIterable, Identifiable {
    case female, male, nonBinary = "non_binary", preferNotToSay = "prefer_not_to_say"
    var id: String { rawValue }

    var displayTR: String {
        switch self {
        case .female: return "Kadın"
        case .male: return "Erkek"
        case .nonBinary: return "Non-binary"
        case .preferNotToSay: return "Belirtmek istemiyorum"
        }
    }
}

/// Adım geçiş yönü. OnboardingHostView, transition edge'ini bu değere göre seçer.
/// İleri giderken yeni sayfa sağdan, geri dönerken soldan girer.
enum TransitionDirection {
    case forward
    case backward
}

// MARK: - Ana state

/// Tüm onboarding boyunca tek "source of truth". `@Observable` ile reactive.
@MainActor
@Observable
final class OnboardingFlow {

    // Navigation
    var step: OnboardingStep = .welcome
    var direction: TransitionDirection = .forward
    var isSubmitting: Bool = false
    var submitError: String?

    // Step 2: Essentials
    var locale: String = "tr"
    var consentAccount: Bool = false
    var consentAIProcessing: Bool = true

    // Step 3: Skin type (anchor)
    /// nil ⇒ "Emin değilim" veya hiç seçim yapılmadı; payload'a girmez.
    var selectedSkinType: SkinType? = nil
    /// Kullanıcı açıkça "Emin değilim" dediyse Devam butonunu unlock etmek için
    var skinTypeAcknowledgedUnknown: Bool = false

    // Step 4: HealthKit sonuçları
    var healthKit: HealthKitSnapshot? = nil
    var isLoadingHealthKit: Bool = false

    // Step 4 (alternatif): Manuel veri girişi (HealthKit reddedilirse veya kullanıcı tercih ederse)
    var manualBirthDate: Date? = nil
    var manualBiologicalSex: String? = nil      // "female"|"male"|"non_binary"|"prefer_not_to_say"
    var manualSleepHours: Double? = nil
    var manualWaterGlasses: Int? = nil

    // Step 5: Preferences — sadece foto modu (kategoriler onboarding'den kaldırıldı,
    // hepsi true default ile backend'e gönderilir; kullanıcı ileride arşive ürün
    // ekledikçe gerçek kategori dağılımı oluşur).
    let categorySkincare: Bool = true
    let categoryHaircare: Bool = true
    let categoryBodycare: Bool = true
    let categoryMakeup: Bool = true

    // Foto modu — default kullanıcı tercihiyle: fotoğrafları koru
    var photoMode: PhotoMode = .photoKept

    // MARK: - Hesaplanmış

    var canProceedFromEssentials: Bool { consentAccount }

    /// SkinType adımı: bir tip seçilmişse veya "Emin değilim" işaretliyse devam edebilir.
    var canProceedFromSkinType: Bool {
        selectedSkinType != nil || skinTypeAcknowledgedUnknown
    }

    var canProceedFromPreferences: Bool {
        categorySkincare || categoryHaircare || categoryBodycare || categoryMakeup
    }

    var selectedCategories: [String] {
        var arr: [String] = []
        if categorySkincare { arr.append("skincare") }
        if categoryHaircare { arr.append("haircare") }
        if categoryBodycare { arr.append("bodycare") }
        if categoryMakeup   { arr.append("makeup") }
        return arr
    }

    /// FinalPlanView için TR display string'leri
    var selectedCategoriesDisplayTR: [String] {
        var arr: [String] = []
        if categorySkincare { arr.append("Cilt bakımı") }
        if categoryHaircare { arr.append("Saç bakımı") }
        if categoryBodycare { arr.append("Vücut bakımı") }
        if categoryMakeup   { arr.append("Makyaj") }
        return arr
    }

    var photoModeDisplayTR: String {
        switch photoMode {
        case .metricsOnly: return "Sadece veri saklanır"
        case .photoKept:   return "Fotoğraflar saklanır"
        }
    }

    /// FinalPlan: kullanıcı seçtiyse cilt tipi display + reveal hint, yoksa "Bilinmiyor"
    var skinTypeFinalSummary: String {
        if let t = selectedSkinType {
            return "\(t.displayTR) — \(t.revealHintTR)"
        }
        return "Bilinmiyor (sonradan belirleyeceğiz)"
    }

    /// Manuel girilen veya HealthKit'ten gelen doğum tarihi (manuel öncelikli)
    private var effectiveBirthDateISO: String? {
        let date = manualBirthDate ?? healthKit?.birthDate
        guard let bd = date else { return nil }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: bd)
    }

    /// Manuel veya HealthKit'ten gelen biyolojik cinsiyet (manuel öncelikli)
    private var effectiveBiologicalSex: String? {
        manualBiologicalSex ?? healthKit?.biologicalSex
    }

    /// Manuel veya HealthKit'ten gelen uyku (manuel öncelikli)
    private var effectiveSleepHours: Double? {
        manualSleepHours ?? healthKit?.avgSleepHoursLast30Days
    }

    /// Manuel veya HealthKit'ten gelen su (manuel öncelikli)
    private var effectiveWaterGlasses: Int? {
        manualWaterGlasses ?? healthKit?.avgWaterGlassesLast30Days
    }

    // MARK: - Navigation

    func goNext() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        direction = .forward
        Haptics.light()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
            step = next
        }
    }

    func goBack() {
        guard let prev = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        direction = .backward
        Haptics.light()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
            step = prev
        }
    }

    func skipCurrent() {
        guard step.isSkippable else { return }
        Haptics.warning()
        direction = .forward
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
            step = next
        }
    }

    /// SkinType'ta kullanılan "Emin değilim" link buton aksiyonu
    func acknowledgeSkinTypeUnknown() {
        Haptics.selection()
        selectedSkinType = nil
        skinTypeAcknowledgedUnknown = true
    }

    // MARK: - HealthKit

    /// HealthSync adımından çağrılır. Yetki ister + snapshot okur.
    /// Reddedilse / boş gelse bile akış bloklanmaz.
    func syncFromHealthKit() async {
        isLoadingHealthKit = true
        defer { isLoadingHealthKit = false }
        let snap = await HealthKitService.shared.fetchProfileData()
        self.healthKit = snap
        if snap.hasAnyData {
            Haptics.success()
        } else {
            Haptics.warning()
        }
    }

    // MARK: - Payload üretimi

    func buildProfileRequest() -> ProfileUpdateRequest {
        // Manuel girilen / HealthKit'ten gelen uyku/su lifestyle alanlarına yansır
        let lifestyle: LifestylePayload? = {
            let sleep = effectiveSleepHours
            let water = effectiveWaterGlasses
            if sleep == nil && water == nil { return nil }
            return LifestylePayload(
                smoking: nil,
                alcoholFrequency: nil,
                sleepHoursAvg: sleep,
                waterGlassesPerDay: water
            )
        }()

        return ProfileUpdateRequest(
            skinType: selectedSkinType?.rawValue,
            skinConcerns: nil,
            hairType: nil,
            hairConcerns: nil,
            bodyConcerns: nil,
            makeupPref: nil,
            birthDate: effectiveBirthDateISO,
            gender: effectiveBiologicalSex,
            fitzpatrickType: healthKit?.fitzpatrickType,
            lifestyle: lifestyle,
            country: nil,
            pregnancy: nil,
            defaultPhotoMode: photoMode.rawValue,
            locale: locale,
            categories: selectedCategories
        )
    }

    func buildConsentRequests(version: String) -> [ConsentRequest] {
        [
            ConsentRequest(consentType: ConsentType.account.rawValue,
                           granted: consentAccount,
                           version: version),
            ConsentRequest(consentType: ConsentType.aiProcessing.rawValue,
                           granted: consentAIProcessing,
                           version: version)
        ]
    }
}

// MARK: - SkinType: onboarding UI display

extension SkinType {

    /// Onboarding kartlarında gösterilen ana etiket (TR)
    var displayTR: String {
        switch self {
        case .oily:      return "Yağlı"
        case .dry:       return "Kuru"
        case .combo:     return "Karma"
        case .normal:    return "Normal"
        case .sensitive: return "Hassas"
        }
    }

    /// Kart altındaki kısa açıklama (TR)
    var subtitleTR: String {
        switch self {
        case .oily:      return "T-zone parlıyor, gözenekler belirgin"
        case .dry:       return "Çekiyor, pul pul, mat görünür"
        case .combo:     return "T-zone yağlı, yanaklar kuru"
        case .normal:    return "Dengeli, pek sorun yok"
        case .sensitive: return "Kolayca kızarıyor, tepki verir"
        }
    }

    /// SF Symbol kart ikonu
    var symbol: String {
        switch self {
        case .oily:      return "drop.fill"
        case .dry:       return "wind"
        case .combo:     return "circle.lefthalf.filled"
        case .normal:    return "sparkles"
        case .sensitive: return "leaf.arrow.circlepath"
        }
    }

    /// SkinType seçildiğinde mini reveal kartında gösterilen kişiselleştirilmiş metin.
    /// Cal AI tarzı "we got you" mikro-an: seçimin direkt değerini hissettir.
    var revealTextTR: String {
        switch self {
        case .oily:
            return "Niacinamide, salisilik asit (BHA) ve oil-free formüller önereceğim."
        case .dry:
            return "Hyaluronik asit, ceramide ve zengin moisturizer'lara odaklanacağım."
        case .combo:
            return "T-zone için BHA, yanaklar için ceramide karışık önerilerim olacak."
        case .normal:
            return "Hafif aktifler ve dengeli rutinler önereceğim."
        case .sensitive:
            return "Centella, allantoin ve kokusuz formüllere öncelik vereceğim."
        }
    }

    /// FinalPlan özet kartında kullanılan kısa ingredient hint
    var revealHintTR: String {
        switch self {
        case .oily:      return "Niacinamide, BHA"
        case .dry:       return "Hyaluronik asit, ceramide"
        case .combo:     return "BHA + ceramide"
        case .normal:    return "Dengeli aktifler"
        case .sensitive: return "Centella, allantoin"
        }
    }
}
