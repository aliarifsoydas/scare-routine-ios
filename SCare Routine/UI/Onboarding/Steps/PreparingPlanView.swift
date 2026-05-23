import SwiftUI

/// "Hadi başlayalım" basıldıktan sonra gösterilen hazırlanıyor animasyonu.
///
/// Cal AI 29 tarzı: yüzde + alt başlık + adım adım ilerleyen ipucu listesi.
/// Backend submit'i ile paralel çalışır; her ikisi (min 2.4s animasyon ve gerçek API)
/// tamamlandığında `onComplete` çağrılır.
///
/// Bu mikro-an "AI gerçekten bir şey yapıyor" hissi verir ve kullanıcının yeni
/// ekrana spawn etmesi yerine "hazırlanmış bir plan"a girdiği algısı yaratır.
struct PreparingPlanView: View {
    let onComplete: () -> Void

    @State private var progress: Double = 0.0
    @State private var currentStep: Int = 0

    /// Sahte adım listesi — her biri ~0.7sn yanar
    private let steps: [(symbol: String, label: String)] = [
        ("person.crop.circle.badge.checkmark", "Profilin kaydediliyor"),
        ("drop.fill", "Cilt tipine uygun aktifler eşleştiriliyor"),
        ("sparkles", "İlk öneriler hazırlanıyor")
    ]

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            VStack(spacing: 36) {
                Spacer()

                // Yüzde + başlık
                VStack(spacing: 14) {
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 56, weight: .bold, design: .default))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: progress))

                    Text(L("Senin için hazırlıyorum…"))
                        .font(Theme.Typo.title)
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                }

                // Progress bar
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Theme.surface)
                            .frame(height: 6)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Theme.success, Theme.ink],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, proxy.size.width * progress), height: 6)
                    }
                }
                .frame(height: 6)
                .padding(.horizontal, 40)
                .animation(.easeOut(duration: 0.5), value: progress)

                // Adım listesi
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { idx, item in
                        stepRow(symbol: item.symbol, label: item.label, isActive: idx <= currentStep, isDone: idx < currentStep)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.surface)
                )
                .padding(.horizontal, 28)

                Spacer()
                Spacer()
            }
        }
        .task {
            await runAnimation()
        }
    }

    // MARK: - Row

    private func stepRow(symbol: String, label: String, isActive: Bool, isDone: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isActive ? Theme.ink : Theme.surface)
                    .frame(width: 28, height: 28)

                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.onAccent)
                } else if isActive {
                    ProgressView()
                        .tint(Theme.onAccent)
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Theme.inkMute)
                }
            }
            Text(label)
                .font(Theme.Typo.body)
                .foregroundStyle(isActive ? Theme.ink : Theme.inkSoft)
                .lineLimit(2)
            Spacer()
        }
        .animation(.easeInOut(duration: 0.3), value: isActive)
        .animation(.easeInOut(duration: 0.3), value: isDone)
    }

    // MARK: - Animation orchestrator

    /// 3 adım, her biri ~0.8sn. Toplam ~2.4sn. Tamamlanınca onComplete().
    @MainActor
    private func runAnimation() async {
        Haptics.light()
        let stepDuration: UInt64 = 800_000_000 // 0.8sn

        for i in 0..<steps.count {
            currentStep = i
            // Yüzdeyi sıçramalı doldur (Cal AI 18% gibi sahte)
            withAnimation(.easeOut(duration: 0.5)) {
                progress = Double(i + 1) / Double(steps.count + 1)
            }
            try? await Task.sleep(nanoseconds: stepDuration)
        }

        // Son: %100 — animation bitince user'ın "bitti" hissi yaşaması için
        // ekranın görünür kalmasını sağla (1.2s).
        currentStep = steps.count
        withAnimation(.easeOut(duration: 0.5)) {
            progress = 1.0
        }
        // Anim 0.5s + post-wait 1.2s = %100 ekranda toplam ~1.2s görünür
        try? await Task.sleep(nanoseconds: 500_000_000)
        Haptics.success()
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        onComplete()
    }
}
