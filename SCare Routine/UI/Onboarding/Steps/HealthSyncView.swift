import SwiftUI

/// Adım 4/6 — Opsiyonel sağlık bilgileri.
///
/// Üç yol sunar:
///  1. **Health'ten oku** — Apple Health'ten otomatik snapshot
///  2. **Elle gir** — sheet ile doğum tarihi, cinsiyet, uyku, su
///  3. **Şimdilik atla** — hiçbir şey kaydetme, sonra profilden eklensin
///
/// Hiçbiri zorunlu değil. CTA "Devam" her zaman aktiftir.
struct HealthSyncView: View {
    @Bindable var flow: OnboardingFlow

    // Manuel entry sheet state
    @State private var showManualSheet: Bool = false

    // Sheet draft state (kaydedilene kadar flow'a yazılmaz)
    @State private var draftBirthDate: Date = Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now
    @State private var draftSex: String? = nil
    @State private var draftSleep: Double = 7.5
    // draftWater kaldırıldı — feature drop
    @State private var draftSmoking: String? = nil       // never | occasionally | daily
    @State private var draftAlcohol: String? = nil       // never | rarely | weekly | daily
    @State private var draftPregnancy: Bool? = nil       // only asked if draftSex == "female"

    private var snapshot: HealthKitSnapshot? { flow.healthKit }

    /// Kullanıcı en az bir manuel alan girdi mi?
    private var hasManualData: Bool {
        flow.manualBirthDate != nil
            || flow.manualBiologicalSex != nil
            || flow.manualSleepHours != nil
    }

    /// Health'ten gelen snapshot var ve içinde gerçek veri var mı?
    private var hasHealthData: Bool {
        snapshot?.hasAnyData == true
    }

    var body: some View {
        OnboardingStepContainer {
            OnboardingStepHeader(
                title: L("Sağlık bilgilerin"),
                subtitle: L("Apple Health'ten al ya da elle gir. Hiçbir veri sunucuya yüklenmez."),
                symbol: "heart.text.square"
            )

            optionsStack

            if hasHealthData || hasManualData {
                summaryCard
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                        removal: .opacity
                    ))
            }
        } cta: {
            OnboardingPrimaryButton(title: L("Devam")) {
                flow.goNext()
            }
            .track("continue")
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: hasHealthData)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: hasManualData)
        .sheet(isPresented: $showManualSheet) {
            manualEntrySheet
        }
    }

    // MARK: - 3 seçenek

    private var optionsStack: some View {
        VStack(spacing: 10) {
            BigSelectionCard(
                title: flow.isLoadingHealthKit ? L("Okunuyor...") : L("Health'ten oku"),
                subtitle: L("Doğum, cinsiyet, uyku"),
                symbol: "heart.text.square",
                isSelected: hasHealthData,
                hapticEnabled: false
            ) {
                guard !flow.isLoadingHealthKit else { return }
                Haptics.light()
                Task { await flow.syncFromHealthKit() }
            }

            BigSelectionCard(
                title: L("Elle gir"),
                subtitle: hasManualData ? L("Yapıldı — düzenlemek için dokun") : L("Birkaç soru"),
                symbol: "square.and.pencil",
                isSelected: hasManualData,
                hapticEnabled: false
            ) {
                Haptics.light()
                prefillDraftFromFlow()
                showManualSheet = true
            }

            BigSelectionCard(
                title: L("Şimdilik atla"),
                subtitle: L("Sonra profilden eklersin"),
                symbol: "forward.end",
                isSelected: false,
                hapticEnabled: false
            ) {
                Haptics.light()
                // Önceki seçimleri temizle (kullanıcı bilinçli olarak atlamayı seçti)
                flow.healthKit = nil
                flow.manualBirthDate = nil
                flow.manualBiologicalSex = nil
                flow.manualSleepHours = nil
                flow.goNext()
            }
        }
    }

    // MARK: - Sonuç özeti (snapshot veya manuel)

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.success)
                Text(summaryTitle)
                    .font(Theme.Typo.headline)
                    .foregroundStyle(Theme.ink)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(summaryRows, id: \.label) { row in
                    resultRow(row.label, value: row.value)
                }
            }

            if !summaryRows.isEmpty == false {
                Text(L("Henüz okunacak veri yok. Endişelenme; bunları sonradan profilden ekleyebilirsin."))
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surfaceLow)
        )
    }

    private var summaryTitle: String {
        // Kullanıcı-dostu, "raporu" gibi değil sohbet havasında
        "Profiline eklendi"
    }

    /// Manuel veriler öncelikli — flow.effective* mantığı ile aynı.
    /// Kullanıcı-dostu format: doğum tarihi yerine yaş, ham 'female' yerine 'Kadın',
    /// Fitzpatrick yalın sayı yerine açıklamalı.
    private var summaryRows: [(label: String, value: String)] {
        var rows: [(String, String)] = []

        if let dob = flow.manualBirthDate ?? snapshot?.birthDate {
            rows.append(("Yaş", "\(ageInYears(from: dob))"))
        }
        if let sex = flow.manualBiologicalSex ?? snapshot?.biologicalSex {
            rows.append(("Cinsiyet", displaySex(sex)))
        }
        if let f = snapshot?.fitzpatrickType {
            rows.append(("Cilt tonu", fitzpatrickDescription(f)))
        }
        if let s = flow.manualSleepHours ?? snapshot?.avgSleepHoursLast30Days {
            let hoursStr = s.formatted(.number.precision(.fractionLength(1)))
            rows.append(("Uyku", String(format: L("sleep_hours_per_night"), hoursStr)))
        }

        return rows
    }

    private func resultRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.inkSoft)
            Spacer()
            Text(value)
                .font(Theme.Typo.body.weight(.medium))
                .foregroundStyle(Theme.ink)
        }
    }

    // MARK: - Manuel entry sheet

    private var manualEntrySheet: some View {
        NavigationStack {
            Form {
                Section(L("Doğum tarihi")) {
                    DatePicker(
                        L("Doğum tarihi"),
                        selection: $draftBirthDate,
                        in: minBirthDate...maxBirthDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                Section(L("Biyolojik cinsiyet")) {
                    sexChipGroup
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L("Ortalama uyku"))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text({
                                let hoursStr = draftSleep.formatted(.number.precision(.fractionLength(1)))
                                return String(format: L("sleep_hours_long"), hoursStr)
                            }())
                                .font(Theme.Typo.body.weight(.medium))
                                .foregroundStyle(Theme.ink)
                                .monospacedDigit()
                        }
                        Slider(value: $draftSleep, in: 4...12, step: 0.5)
                    }
                } header: {
                    Text(L("Uyku"))
                }

                // "Günlük su" section kaldırıldı — feature drop

                Section(L("Sigara")) {
                    FlexibleChipRow(items: [
                        (value: "never", label: "Kullanmıyorum"),
                        (value: "occasionally", label: "Ara sıra"),
                        (value: "daily", label: "Her gün")
                    ]) { option in
                        OnboardingChip(
                            title: option.label,
                            symbol: nil,
                            isSelected: draftSmoking == option.value
                        ) {
                            draftSmoking = (draftSmoking == option.value) ? nil : option.value
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }

                Section(L("Alkol")) {
                    FlexibleChipRow(items: [
                        (value: "never", label: "Hiç"),
                        (value: "rarely", label: "Nadiren"),
                        (value: "weekly", label: "Haftada"),
                        (value: "daily", label: "Her gün")
                    ]) { option in
                        OnboardingChip(
                            title: option.label,
                            symbol: nil,
                            isSelected: draftAlcohol == option.value
                        ) {
                            draftAlcohol = (draftAlcohol == option.value) ? nil : option.value
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }

                if draftSex == "female" {
                    Section(L("Hamilelik")) {
                        FlexibleChipRow(items: [
                            (value: "no", label: "Hayır"),
                            (value: "yes", label: "Evet")
                        ]) { option in
                            OnboardingChip(
                                title: option.label,
                                symbol: nil,
                                isSelected: (draftPregnancy == true && option.value == "yes")
                                    || (draftPregnancy == false && option.value == "no")
                            ) {
                                let newVal = option.value == "yes"
                                if draftPregnancy == newVal {
                                    draftPregnancy = nil
                                } else {
                                    draftPregnancy = newVal
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(L("Elle gir"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("İptal")) {
                        Haptics.light()
                        showManualSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Kaydet")) {
                        flow.manualBirthDate = draftBirthDate
                        flow.manualBiologicalSex = draftSex
                        flow.manualSleepHours = draftSleep
                        flow.manualSmoking = draftSmoking
                        flow.manualAlcohol = draftAlcohol
                        // pregnancy yalnızca female için anlamlı; diğer durumlarda nil yaz
                        flow.pregnancyAnswer = (draftSex == "female") ? draftPregnancy : nil
                        Haptics.success()
                        showManualSheet = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// 4 chip akıllı sarılma için FlowLayout yerine basit yatay grid; iki satıra düşebilir
    private var sexChipGroup: some View {
        let options: [(value: String, label: String)] = [
            ("female", "Kadın"),
            ("male", "Erkek"),
            ("non_binary", "Non-binary"),
            ("prefer_not_to_say", "Belirtmek istemiyorum")
        ]
        return FlexibleChipRow(items: options) { option in
            OnboardingChip(
                title: option.label,
                symbol: nil,
                isSelected: draftSex == option.value
            ) {
                draftSex = (draftSex == option.value) ? nil : option.value
            }
        }
    }

    // MARK: - Sheet pre-fill

    private func prefillDraftFromFlow() {
        if let bd = flow.manualBirthDate {
            draftBirthDate = bd
        } else if let bd = snapshot?.birthDate {
            draftBirthDate = bd
        } else {
            draftBirthDate = Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now
        }

        draftSex = flow.manualBiologicalSex ?? snapshot?.biologicalSex

        if let s = flow.manualSleepHours {
            draftSleep = s
        } else if let s = snapshot?.avgSleepHoursLast30Days {
            draftSleep = max(4, min(12, s))
        } else {
            draftSleep = 7.5
        }

        // draftWater kaldırıldı — feature drop

        draftSmoking = flow.manualSmoking
        draftAlcohol = flow.manualAlcohol
        draftPregnancy = flow.pregnancyAnswer
    }

    // MARK: - Tarih aralığı

    private var minBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: -100, to: .now) ?? .distantPast
    }

    private var maxBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: -12, to: .now) ?? .now
    }

    // MARK: - Formatter helpers

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = LanguageManager.shared.effectiveLocale
        f.dateStyle = .medium
        return f.string(from: d)
    }

    /// Doğum tarihinden bugüne kadar geçen tam yıl sayısı.
    private func ageInYears(from birth: Date) -> Int {
        let years = Calendar.current.dateComponents([.year], from: birth, to: .now).year ?? 0
        return max(0, years)
    }

    private func displaySex(_ s: String) -> String {
        switch s {
        case "female": return "Kadın"
        case "male": return "Erkek"
        case "non_binary": return "Non-binary"
        case "prefer_not_to_say": return "Belirtmek istemiyorum"
        default: return s
        }
    }

    /// Fitzpatrick 1-6 cilt tonu skalası → kısa açıklamalı TR etiket.
    private func fitzpatrickDescription(_ type: Int) -> String {
        switch type {
        case 1: return "1 — Çok açık"
        case 2: return "2 — Açık"
        case 3: return "3 — Açık-orta"
        case 4: return "4 — Orta"
        case 5: return "5 — Koyu"
        case 6: return "6 — Çok koyu"
        default: return "Tip \(type)"
        }
    }
}

// MARK: - Flexible chip row (wraps automatically)

/// Basit, native bir wrap-eden chip dizilimi. Form section içinde 4 chip'i
/// yatayda akıtır; dar genişlikte alt satıra düşer.
private struct FlexibleChipRow<Item, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        // iOS 16+: native flow-like wrapping
        FlowHStack(spacing: 8, runSpacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                content(item)
            }
        }
    }
}

/// Hafif, native HStack-benzeri wrap layout. Layout protocol ile yazılmıştır.
private struct FlowHStack: Layout {
    var spacing: CGFloat = 8
    var runSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                y += rowHeight + runSpacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, x - spacing)
        }
        return CGSize(width: min(totalWidth, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth && x > bounds.minX {
                y += rowHeight + runSpacing
                x = bounds.minX
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    HealthSyncView(flow: OnboardingFlow())
        .background(Theme.canvas)
}
