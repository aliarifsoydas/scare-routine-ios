import SwiftUI

/// Quick Scan tarzı AI değerlendirme paneli — inline kullanım için.
///
/// `QuickScanResultPanel` (kullanıcı tarama sonrası "almalı mıyım?" karar verir)
/// ve `ProductReviewView` (kullanıcı arşive eklerken "ne durumda?" görür) tarafından
/// reuse edilir. Yalnızca *loaded* state'i render eder; loading/error host view'ın
/// sorumluluğunda. Backend çağrısı da bu view'da yapılmaz — host hazır
/// `QuickEvaluateResponse` verir.
///
/// Verdict label/subtitle metinleri `context`'e göre farklılaşır:
/// - `.scanning`  → "almalı mıyım?" framing
/// - `.reviewing` → "ekliyorum, riskler neler?" framing (daha yumuşak)
struct QuickEvaluationView: View {
    let result: QuickEvaluateResponse
    /// Context — verdict label/coloring/wording'i ayarlar.
    var context: Context = .scanning

    enum Context {
        /// Quick Scan akışı — "şu an almalı mıyım?"
        case scanning
        /// Arşive ekleme akışı — "ekliyorum, nelere dikkat?"
        case reviewing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Fit score gauge + verdict
            HStack(spacing: 18) {
                FitScoreGauge(score: result.fitScore)
                VStack(alignment: .leading, spacing: 6) {
                    Text(verdictLabel)
                        .font(Theme.Typo.title.weight(.semibold))
                        .foregroundStyle(verdictColor)
                    Text(verdictSubtitle)
                        .font(Theme.Typo.body)
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer()
            }

            // Duplicate warning (verdict == .duplicate veya backend dup ID döndürdüyse)
            if let dupId = result.duplicateProductId, let dupName = result.duplicateProductName {
                DuplicateWarningCard(productId: dupId, productName: dupName)
            }

            // Pros + cons (her ikisi de boşsa render etme)
            if !result.pros.isEmpty || !result.cons.isEmpty {
                ProConsList(pros: result.pros, cons: result.cons)
            }

            // Reasons (bullet list — açıklama)
            if !result.reasons.isEmpty {
                reasonsCard
            }
        }
    }

    // MARK: - Reasons card

    private var reasonsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Neden bu sıralama?"))
                .font(Theme.Typo.caption.weight(.semibold))
                .foregroundStyle(Theme.inkSoft)
                .textCase(.uppercase)
            ForEach(result.reasons, id: \.self) { reason in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundStyle(Theme.inkSoft)
                    Text(reason)
                        .font(Theme.Typo.body)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surfaceLow))
    }

    // MARK: - Verdict copy (context-aware)

    private var verdictLabel: String {
        switch (result.verdict, context) {
        case (.greatFit, _):
            return L("Cildine çok uygun")
        case (.goodFit, _):
            return L("Cildine uygun")
        case (.neutral, _):
            return L("Nötr — denenebilir")
        case (.skip, .scanning):
            return L("Şu an önerilmez")
        case (.skip, .reviewing):
            // Arşive ekleme akışında daha yumuşak — kullanıcı zaten ekliyor.
            return L("Dikkat: aktif uyarılar var")
        case (.duplicate, .scanning):
            return L("Zaten arşivinde var")
        case (.duplicate, .reviewing):
            return L("Zaten arşivinde benzer ürün")
        }
    }

    private var verdictSubtitle: String {
        switch (result.verdict, context) {
        case (.greatFit, _):
            return L("Profilinle iyi eşleşiyor")
        case (.goodFit, _):
            return L("Genel olarak uygun")
        case (.neutral, _):
            return L("Net bir artı/eksi yok")
        case (.skip, .scanning):
            return L("Cildine uygun değil")
        case (.skip, .reviewing):
            // Engelleyici değil — "biliyorsun, sen karar ver".
            return L("Eklemekte özgürsün, patch test öneririz")
        case (.duplicate, _):
            return L("Mevcut ürününe çok benziyor")
        }
    }

    private var verdictColor: Color {
        switch result.verdict {
        case .greatFit, .goodFit:    return Theme.success
        case .neutral, .duplicate:   return Theme.ink
        case .skip:                  return Theme.alert
        }
    }
}

#Preview("Great fit — scanning") {
    QuickEvaluationView(
        result: QuickEvaluateResponse(
            product: .init(id: "p1", name: "Hydrating Cleanser", brand: "CeraVe", categoryId: nil, photoUrl: nil),
            fitScore: 86,
            verdict: .greatFit,
            pros: ["Nemlendirici", "Kokusuz"],
            cons: [],
            duplicateProductId: nil,
            duplicateProductName: nil,
            reasons: ["Kuru cilt için uygun aktifler", "Hassas cilt güvenliği yüksek"],
            via: .preCheck
        ),
        context: .scanning
    )
    .padding(20)
    .background(Theme.canvas)
}

#Preview("Skip — reviewing (softer copy)") {
    QuickEvaluationView(
        result: QuickEvaluateResponse(
            product: .init(id: "p1", name: "Strong Retinol", brand: "Brand", categoryId: nil, photoUrl: nil),
            fitScore: 32,
            verdict: .skip,
            pros: [],
            cons: ["Hassas cilde sert", "Yüksek alkol"],
            duplicateProductId: nil,
            duplicateProductName: nil,
            reasons: ["Cilt tipiyle uyuşmuyor"],
            via: .llm
        ),
        context: .reviewing
    )
    .padding(20)
    .background(Theme.canvas)
}
