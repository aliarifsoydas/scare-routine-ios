import Foundation
import HealthKit

// MARK: - Snapshot

/// HealthKit'ten okunan, onboarding'de profil ön-doldurma için kullanılan veri kümesi.
/// Hiçbir alan zorunlu değil — kullanıcının izin vermediği / verisi olmayan alanlar `nil` döner.
struct HealthKitSnapshot: Sendable, Equatable {
    let birthDate: Date?
    /// "female" | "male" | "non_binary" | nil
    let biologicalSex: String?
    /// 1-6 (Fitzpatrick I..VI). HKFitzpatrickSkinType.notSet -> nil
    let fitzpatrickType: Int?
    /// Son 30 günün günlük uyku ortalaması (saat cinsinden)
    let avgSleepHoursLast30Days: Double?
    /// Son 30 günün günlük su tüketimi ortalaması (250ml = 1 bardak varsayımı)
    let avgWaterGlassesLast30Days: Int?

    static let empty = HealthKitSnapshot(
        birthDate: nil,
        biologicalSex: nil,
        fitzpatrickType: nil,
        avgSleepHoursLast30Days: nil,
        avgWaterGlassesLast30Days: nil
    )

    /// En az bir veri var mı? UI'da "Şu bilgiler okundu" özeti göstermek için.
    var hasAnyData: Bool {
        birthDate != nil
        || biologicalSex != nil
        || fitzpatrickType != nil
        || avgSleepHoursLast30Days != nil
        || avgWaterGlassesLast30Days != nil
    }
}

// MARK: - Service

/// HealthKit izinleri + read-only veri sorguları için merkezi servis.
/// `@MainActor` olmasının nedeni: `OnboardingFlow` ve UI bu sınıfla doğrudan konuşur.
/// İçerdeki HealthKit query'leri async/await sarmalı ile background'da çalışır.
@MainActor
final class HealthKitService {

    static let shared = HealthKitService()

    private let store = HKHealthStore()

    /// Cihazda HealthKit destekleniyor mu? (Sim'de iPad/Mac üzerinde false olabilir)
    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Okumak istediğimiz tipler

    private var readTypes: Set<HKObjectType> {
        var set: Set<HKObjectType> = []
        if let dob = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) {
            set.insert(dob)
        }
        if let sex = HKObjectType.characteristicType(forIdentifier: .biologicalSex) {
            set.insert(sex)
        }
        if let fitz = HKObjectType.characteristicType(forIdentifier: .fitzpatrickSkinType) {
            set.insert(fitz)
        }
        if let water = HKObjectType.quantityType(forIdentifier: .dietaryWater) {
            set.insert(water)
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            set.insert(sleep)
        }
        return set
    }

    // MARK: - Yetki

    /// Kullanıcıdan read-only izin ister. Kullanıcının izin verip vermediğine bakmaksızın
    /// `true` döner çünkü Apple iznin verilip verilmediğini app'e söylemez (privacy).
    /// `false` yalnızca: HealthKit cihazda mevcut değil veya HK API hata fırlattı.
    func requestAuthorization() async throws -> Bool {
        guard isAvailable else { return false }
        try await store.requestAuthorization(toShare: [], read: readTypes)
        return true
    }

    // MARK: - Snapshot okuma

    /// Yetki + veri çekimi tek pas. Yetki yoksa kullanıcıdan ister, sonra okur.
    /// Hata olursa (örn. izin reddedildi) ilgili alan nil döner — onboarding bloklanmaz.
    func fetchProfileData() async -> HealthKitSnapshot {
        guard isAvailable else { return .empty }

        // Yetki iste (idempotent — Apple zaten cache'liyor)
        _ = try? await requestAuthorization()

        async let birth: Date? = readBirthDate()
        async let sex: String? = readBiologicalSex()
        async let fitz: Int? = readFitzpatrickType()
        async let sleep: Double? = readAverageSleepHours(days: 30)
        async let water: Int? = readAverageWaterGlasses(days: 30)

        return await HealthKitSnapshot(
            birthDate: birth,
            biologicalSex: sex,
            fitzpatrickType: fitz,
            avgSleepHoursLast30Days: sleep,
            avgWaterGlassesLast30Days: water
        )
    }

    // MARK: - Characteristic okumaları (senkron API'leri async sarmal)

    private func readBirthDate() async -> Date? {
        do {
            let components = try store.dateOfBirthComponents()
            return Calendar(identifier: .gregorian).date(from: components)
        } catch {
            return nil
        }
    }

    private func readBiologicalSex() async -> String? {
        do {
            let sex = try store.biologicalSex().biologicalSex
            switch sex {
            case .female: return "female"
            case .male: return "male"
            case .other: return "non_binary"
            case .notSet: return nil
            @unknown default: return nil
            }
        } catch {
            return nil
        }
    }

    private func readFitzpatrickType() async -> Int? {
        do {
            let type = try store.fitzpatrickSkinType().skinType
            switch type {
            case .I: return 1
            case .II: return 2
            case .III: return 3
            case .IV: return 4
            case .V: return 5
            case .VI: return 6
            case .notSet: return nil
            @unknown default: return nil
            }
        } catch {
            return nil
        }
    }

    // MARK: - Uyku

    /// Son `days` günün günlük uyku saati ortalaması.
    /// `asleepCore`, `asleepREM`, `asleepDeep`, `asleepUnspecified` segmentleri toplanır.
    /// `inBed` segmentleri DIŞARIDA tutulur — gerçek uyku süresi istenir.
    /// Veri yoksa veya izin yoksa nil.
    private func readAverageSleepHours(days: Int) async -> Double? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return nil
        }
        let end = Date()
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: end) else {
            return nil
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { (cont: CheckedContinuation<Double?, Never>) in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample], !samples.isEmpty else {
                    cont.resume(returning: nil); return
                }
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                ]
                var totalSeconds: TimeInterval = 0
                for s in samples where asleepValues.contains(s.value) {
                    totalSeconds += s.endDate.timeIntervalSince(s.startDate)
                }
                guard totalSeconds > 0 else { cont.resume(returning: nil); return }
                let hoursPerDay = (totalSeconds / 3600.0) / Double(days)
                cont.resume(returning: hoursPerDay)
            }
            store.execute(query)
        }
    }

    // MARK: - Su

    /// Son `days` günün günlük su tüketimi → 250ml = 1 bardak çevirimi.
    /// HKStatisticsQuery cumulative sum kullanır.
    private func readAverageWaterGlasses(days: Int) async -> Int? {
        guard let waterType = HKObjectType.quantityType(forIdentifier: .dietaryWater) else {
            return nil
        }
        let end = Date()
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: end) else {
            return nil
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { (cont: CheckedContinuation<Int?, Never>) in
            let query = HKStatisticsQuery(
                quantityType: waterType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, _ in
                guard let sum = stats?.sumQuantity() else {
                    cont.resume(returning: nil); return
                }
                let totalMl = sum.doubleValue(for: HKUnit.literUnit(with: .milli))
                guard totalMl > 0 else { cont.resume(returning: nil); return }
                let glassesPerDay = (totalMl / 250.0) / Double(days)
                cont.resume(returning: Int(glassesPerDay.rounded()))
            }
            store.execute(query)
        }
    }
}
