import SwiftUI

/// Quick Scan sonucunda gösterilen 0-100 "fit score" daire göstergesi.
///
/// Skor aralığına göre tint değişir:
/// - ≥85 → success (sıcak peach) → ürün senin profiline çok uyumlu
/// - 60..<85 → accent (dusty rose ink) → kısmi uyumlu, dikkat noktaları var
/// - <60 → alert (kırmızı-pink) → uyarı, kullanmadan önce düşün
///
/// **Görsel**: Arka plan halkası (Theme.surfaceLow) + skora göre trim edilmiş
/// renkli ön halka. Ortada büyük skor sayısı (örn "78") ve altında "/100" caption.
/// Stroke kalınlığı diameter'ın yaklaşık %10'u, hafif gölge ile premium hissi.
///
/// **Animasyon**: `.onAppear`'da 0'dan score/100'e easeOut 0.6s ile trim animasyonu.
struct FitScoreGauge: View {
    let score: Int  // 0-100
    var size: CGFloat = 100  // default diameter

    @State private var animatedProgress: CGFloat = 0

    private var clamped: Int { max(0, min(100, score)) }

    private var progress: CGFloat { CGFloat(clamped) / 100.0 }

    private var tint: Color {
        switch clamped {
        case 85...: return Theme.success
        case 60..<85: return Theme.accent
        default: return Theme.alert
        }
    }

    private var strokeWidth: CGFloat { size * 0.10 }

    private var scoreFontSize: CGFloat { size * 0.32 }
    private var captionFontSize: CGFloat { max(10, size * 0.12) }

    var body: some View {
        ZStack {
            // Background ring (boş kısım)
            Circle()
                .stroke(Theme.surfaceLow, lineWidth: strokeWidth)

            // Foreground ring (animated trim)
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))  // 12 o'clock start

            // Center label
            VStack(spacing: 0) {
                Text("\(clamped)")
                    .font(.system(size: scoreFontSize, weight: .bold, design: .default))
                    .foregroundStyle(tint)
                    .monospacedDigit()

                Text("/100")
                    .font(.system(size: captionFontSize, weight: .regular))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.ink.opacity(0.04), radius: 6, x: 0, y: 2)
        .onAppear {
            animatedProgress = 0
            withAnimation(.easeOut(duration: 0.6)) {
                animatedProgress = progress
            }
        }
        .onChange(of: clamped) { _, _ in
            withAnimation(.easeOut(duration: 0.4)) {
                animatedProgress = progress
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fit score: \(clamped) of 100")
    }
}

#Preview {
    VStack(spacing: 24) {
        HStack(spacing: 20) {
            FitScoreGauge(score: 92)
            FitScoreGauge(score: 72)
            FitScoreGauge(score: 45)
        }
        FitScoreGauge(score: 78, size: 140)
    }
    .padding()
    .background(Theme.canvas)
}
