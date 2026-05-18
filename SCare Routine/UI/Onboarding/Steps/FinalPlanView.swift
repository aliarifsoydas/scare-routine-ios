import SwiftUI

/// Adım 6/6 — Kişisel plan reveal + onboarding bitiş.
///
/// Cal AI / Yazio "you're set!" pattern'inin SCare versiyonu: kullanıcının vermiş
/// olduğu cevapları "sana özel plan" olarak geri gösteren bir özet ekran.
/// CTA submit eder (`onStart` → AppState.completeOnboarding).
///
/// Layout:
/// 1. Merkez-ortalı hero: animasyonlu check badge + "Profilin hazır!" + selamlama
/// 2. "Senin için aktif" özet kartı — 4 row, her satır tıklanabilir (gelecekte düzenleme)
/// 3. "Sıradakiler" 3 numaralı checklist
/// 4. "Geri dönüp düzenleyebilirsin" mikro hint
/// 5. CTA: "Hadi başlayalım ✨" — heavy haptic + submit
struct FinalPlanView: View {
    @Bindable var flow: OnboardingFlow
    var userName: String? = nil
    let onStart: () -> Void

    @State private var checkScale: CGFloat = 0.4
    @State private var contentVisible: Bool = false

    var body: some View {
        OnboardingStepContainer {
            heroSection
            activeCard
            nextStepsCard
            editHint
        } cta: {
            OnboardingPrimaryButton(
                title: "Hadi başlayalım ✨",
                isEnabled: !flow.isSubmitting,
                isLoading: flow.isSubmitting,
                hapticStyle: .heavy
            ) {
                Haptics.success()
                onStart()
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) {
                checkScale = 1.0
            }
            withAnimation(.easeOut(duration: 0.45).delay(0.12)) {
                contentVisible = true
            }
            // Hero badge ile birlikte tek başarı haptic'i
            Haptics.success()
        }
    }

    // MARK: - Hero (animated check + title) — merkez ortalı

    private var heroSection: some View {
        VStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.surface)
                    .frame(width: 76, height: 76)
                    .overlay(
                        Circle().strokeBorder(Theme.divider, lineWidth: 1)
                    )
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 38, weight: .regular))
                    .foregroundStyle(Theme.ink)
                    .symbolRenderingMode(.hierarchical)
            }
            .scaleEffect(checkScale)
            .shadow(color: Theme.ink.opacity(0.08), radius: 10, x: 0, y: 4)

            Text("Profilin hazır!")
                .font(Theme.Typo.title)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(Theme.Typo.body)
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 4)
        .opacity(contentVisible ? 1 : 0)
        .offset(y: contentVisible ? 0 : 8)
    }

    private var subtitle: String {
        if let name = userName, !name.isEmpty {
            return "\(name), sana özel hazırladım."
        }
        return "Sana özel hazırladım."
    }

    // MARK: - "Senin için aktif" özet kartı

    private var activeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Senin için aktif")
                .font(Theme.Typo.caption.weight(.semibold))
                .foregroundStyle(Theme.inkSoft)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                summaryRow(
                    symbol: "drop.fill",
                    label: "Cilt tipi",
                    value: skinTypeShort,
                    hint: skinTypeHint
                )
                rowDivider
                summaryRow(
                    symbol: "square.grid.2x2.fill",
                    label: "Kategoriler",
                    value: categoriesValue,
                    hint: nil
                )
                rowDivider
                summaryRow(
                    symbol: "heart.text.square",
                    label: "Sağlık",
                    value: healthSummary,
                    hint: nil
                )
                rowDivider
                summaryRow(
                    symbol: flow.photoMode == .metricsOnly ? "lock.fill" : "photo.on.rectangle.angled",
                    label: "Foto modu",
                    value: flow.photoModeDisplayTR,
                    hint: nil
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 1)
            )
        }
        .opacity(contentVisible ? 1 : 0)
        .offset(y: contentVisible ? 0 : 12)
    }

    private var rowDivider: some View {
        Divider()
            .background(Theme.divider)
            .padding(.leading, 46)
    }

    /// Tek satır = button. Şimdilik aksiyon yok (geri dönüp düzenleme için top chevron var);
    /// haptic verip kullanıcıya "tıklanabilir" hissi yaşatıyoruz.
    private func summaryRow(symbol: String, label: String, value: String, hint: String?) -> some View {
        Button {
            // Şimdilik no-op: kullanıcıya "tıklanabilir" hissi için sadece haptic.
            // Gerçek edit akışı üst chevron ile veya gelecekte step-specific deep-link ile yapılacak.
            Haptics.selection()
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 18, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.inkSoft)
                    Text(value)
                        .font(Theme.Typo.body.weight(.medium))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let hint, !hint.isEmpty {
                        Text("+ \(hint)")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Theme.inkMute)
                            .padding(.top, 1)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkMute)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressedScaleButtonStyle())
        .accessibilityLabel("\(label), \(value). Düzenlemek için dokun.")
    }

    // MARK: - Özet değerleri

    /// "Yağlı" — uzun "Yağlı — Niacinamide, BHA" yerine sadece tip
    private var skinTypeShort: String {
        if let t = flow.selectedSkinType {
            return t.displayTR
        }
        return "Bilinmiyor"
    }

    /// Cilt tipinin altında gösterilecek ingredient ipucu (varsa)
    private var skinTypeHint: String? {
        guard let t = flow.selectedSkinType else { return nil }
        return t.revealHintTR
    }

    private var categoriesValue: String {
        let list = flow.selectedCategoriesDisplayTR
        if list.isEmpty { return "Tümü" }
        if list.count == 4 { return "Tümü" }
        return list.joined(separator: ", ")
    }

    /// Manuel girilen veya HealthKit'ten gelen veriyi özetle.
    /// Hiçbiri yoksa "Atlandı".
    private var healthSummary: String {
        var bits: [String] = []

        // Doğum tarihi (manuel öncelikli)
        if flow.manualBirthDate != nil || flow.healthKit?.birthDate != nil {
            bits.append("doğum tarihi")
        }
        // Cinsiyet
        if flow.manualBiologicalSex != nil || flow.healthKit?.biologicalSex != nil {
            bits.append("cinsiyet")
        }
        // Cilt tonu (yalnızca HK verir)
        if flow.healthKit?.fitzpatrickType != nil {
            bits.append("cilt tonu")
        }
        // Uyku
        if flow.manualSleepHours != nil || flow.healthKit?.avgSleepHoursLast30Days != nil {
            bits.append("uyku")
        }
        // Su
        if flow.manualWaterGlasses != nil || flow.healthKit?.avgWaterGlassesLast30Days != nil {
            bits.append("su")
        }

        if bits.isEmpty { return "Atlandı" }
        if bits.count > 2 {
            return "\(bits.prefix(2).joined(separator: ", ")) +\(bits.count - 2)"
        }
        return bits.joined(separator: ", ").capitalizedFirst
    }

    // MARK: - "Sıradakiler" kartı

    private var nextStepsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sıradakiler")
                .font(Theme.Typo.caption.weight(.semibold))
                .foregroundStyle(Theme.inkSoft)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 14) {
                nextRow(index: 1,
                        title: "İlk rutinini oluştur",
                        subtitle: "sabah / akşam")
                nextRow(index: 2,
                        title: "İlk ürününü ekle",
                        subtitle: "fotoğrafla, otomatik taranır")
                nextRow(index: 3,
                        title: "Cilt günlüğüne başla",
                        subtitle: nil)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.canvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 1)
            )
        }
        .opacity(contentVisible ? 1 : 0)
        .offset(y: contentVisible ? 0 : 16)
    }

    private func nextRow(index: Int, title: String, subtitle: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.surface)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Circle().strokeBorder(Theme.divider, lineWidth: 1)
                    )
                Text("\(index)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typo.body.weight(.medium))
                    .foregroundStyle(Theme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Edit hint (üst chevron geri çalışır hatırlatıcısı)

    private var editHint: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Theme.inkMute)
            Text("Düzenlemek istersen üst köşedeki geri okuyla cevaplarına dönebilirsin.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Theme.inkMute)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .opacity(contentVisible ? 1 : 0)
    }
}

// MARK: - Helpers

private extension String {
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}

// Preview kaldırıldı — @MainActor + #Preview macro çatışıyor.
