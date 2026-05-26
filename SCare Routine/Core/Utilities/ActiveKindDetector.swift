import SwiftUI

/// AI haftalık plan'da gün cell'lerinin renk + kısa label etiketini üretmek için
/// kullanılan paylaşılan helper. WeeklyCalendarView ve HomeWeeklyStrip tek
/// kaynaktan beslenir.
///
/// Detection rationale string + frequencyLabel + addresses üzerinde keyword
/// match'e dayanır. Backend stabil bir taxonomy dönmediği için string heuristic
/// kullanılır (limit: bilinmeyen aktifler "—" döner).
enum ActiveKind: String, Hashable, CaseIterable {
    case retinoid, bha, aha, vitC, niacinamide, peptide

    /// UI'da rozet (chip) için tam etiket — örn. "Retinol".
    var displayLabel: String {
        switch self {
        case .retinoid:    return L("Retinol")
        case .bha:         return L("BHA")
        case .aha:         return L("AHA")
        case .vitC:        return L("Vit C")
        case .niacinamide: return L("Niasinamid")
        case .peptide:     return L("Peptit")
        }
    }

    /// Cell altındaki 2-3 karakter kısaltma — örn. "Ret".
    var shortLabel: String {
        switch self {
        case .retinoid:    return L("Ret")
        case .bha:         return L("BHA")
        case .aha:         return L("AHA")
        case .vitC:        return L("Vit C")
        case .niacinamide: return L("Nia")
        case .peptide:     return L("Pep")
        }
    }

    /// Renk noktası — Theme dışı palette (canlı + ayırt edilebilir).
    var color: Color {
        switch self {
        case .retinoid:    return .indigo
        case .bha:         return .teal
        case .aha:         return .pink
        case .vitC:        return .yellow
        case .niacinamide: return .mint
        case .peptide:     return .purple
        }
    }
}

enum ActiveKindDetector {
    /// Tek bir blob string'de aktif kategori list'i — order dedup'lu.
    static func detect(in text: String) -> [ActiveKind] {
        let t = text.lowercased()
        var out: [ActiveKind] = []
        if t.contains("retin") || t.contains("tretinoin") || t.contains("retinaldeh") {
            out.append(.retinoid)
        }
        if t.contains("bha") || t.contains("salicy") || t.contains("salisil") {
            out.append(.bha)
        }
        if t.contains("aha") || t.contains("glycol") || t.contains("glikol")
            || t.contains("lactic") || t.contains("laktik") || t.contains("mandel") {
            out.append(.aha)
        }
        if t.contains("vitamin c") || t.contains("vit c")
            || t.contains("ascorb") || t.contains("askorb") {
            out.append(.vitC)
        }
        if t.contains("niacinamide") || t.contains("niasinamid") || t.contains("niasinamit") {
            out.append(.niacinamide)
        }
        if t.contains("peptide") || t.contains("peptit") {
            out.append(.peptide)
        }
        return out
    }

    /// Bir günün morning + evening step'lerinden dedup'lu aktif kategori list'i.
    static func kinds(for day: WeeklyPlanDay) -> [ActiveKind] {
        guard !day.restDay else { return [] }
        let allSteps = day.morningSteps + day.eveningSteps
        var seen: Set<ActiveKind> = []
        var ordered: [ActiveKind] = []
        for step in allSteps {
            let blob = [step.rationale, step.frequencyLabel ?? "", step.addresses.joined(separator: " ")]
                .joined(separator: " ")
            for kind in detect(in: blob) {
                if !seen.contains(kind) {
                    seen.insert(kind)
                    ordered.append(kind)
                }
            }
        }
        return ordered
    }
}
