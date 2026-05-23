import SwiftUI

/// Recognize sonuçlarını gösterir; kullanıcı doğruluk onayı verir ya da manuel doldurur.
/// Submit → AddProductFlowView'a sonuç döner (UserProductResponse).
struct ProductReviewView: View {

    // MARK: - Inputs

    let recognized: ProductRecognizeResponse?
    let capturedImage: UIImage?
    let photoUrl: String?
    let onSubmitted: (UserProductResponse) -> Void
    let onRescan: () -> Void

    // MARK: - State

    @State private var mode: Mode = .review
    @State private var selectedSuggestionID: String?

    @State private var brand: String = ""
    @State private var name: String = ""
    @State private var category: String = ""
    @State private var nickname: String = ""
    @State private var notes: String = ""
    @State private var rating: Int = 0
    @State private var openedToday: Bool = false

    @State private var inciExpanded: Bool = false
    @State private var advancedExpanded: Bool = false

    @State private var isSubmitting = false
    @State private var submitError: String?

    enum Mode { case review, manual }

    private var confidence: Confidence {
        guard let c = recognized?.confidence else { return .none }
        return Confidence(rawValue: c) ?? .none
    }

    private var primaryProduct: RecognizedProduct? {
        if let id = selectedSuggestionID,
           let s = recognized?.suggestions?.first(where: { $0.id == id }) {
            return s
        }
        return recognized?.product
    }

    private var canSubmit: Bool {
        if mode == .manual {
            return !brand.trimmed.isEmpty && !name.trimmed.isEmpty
        }
        return primaryProduct != nil
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if mode == .review {
                    if let product = primaryProduct {
                        productCard(product)
                        // Review insights + ingredient warnings
                        if let s = recognized?.reviewSummary, s.count > 0 {
                            reviewSummaryPanel(s)
                        }
                        if let warnings = recognized?.warnings, !warnings.isEmpty {
                            warningsPanel(warnings)
                        }
                        if let suggestions = recognized?.suggestions, !suggestions.isEmpty {
                            suggestionsSection(suggestions)
                        }
                    } else {
                        noMatchPanel
                    }
                } else {
                    manualForm
                }

                advancedFieldsSection

                if let submitError {
                    Text(submitError)
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.alert)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Debug — eşleşme kaynağı bilgisi sayfanın en altında, çok küçük
                sourceFooter
                    .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Theme.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            footerButtons
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .background(Theme.canvas.opacity(0.95))
        }
        .onAppear {
            // Initial fill — recognize bulamadıysa direkt manual'a düş, fakat
            // suggestion varsa review'da kalalım ki kullanıcı seçebilsin.
            if recognized?.product == nil, (recognized?.suggestions?.isEmpty ?? true) {
                mode = .manual
            }
            seedFormFromRecognized()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(modeTitle)
                .font(Theme.Typo.title)
                .foregroundStyle(Theme.ink)
            if let subtitle = modeSubtitle {
                Text(subtitle)
                    .font(Theme.Typo.body)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modeTitle: String {
        switch mode {
        case .review:
            return primaryProduct == nil
                ? L("Tam tanıyamadım")
                : L("Doğru ürün mü?")
        case .manual:
            return L("Manuel ekle")
        }
    }

    private var modeSubtitle: String? {
        switch mode {
        case .review:
            switch confidence {
            case .high:   return L("Eşleşme güçlü görünüyor.")
            case .medium: return L("Bir alternatif yakaladım — emin değilim, sen onayla.")
            case .low, .none:
                return L("Ürünü göremedim. Aşağıdan manuel eklemeyi deneyebilirsin.")
            }
        case .manual:
            return L("Marka ve ürün adı yeterli. İstersen sonradan düzenleyebilirsin.")
        }
    }

    // MARK: - Sonuç kartı

    private func productCard(_ p: RecognizedProduct) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Üst meta — ince satır: confidence + ayraç + source.
            // Eski filled capsule rahatsız ediyordu, şimdi sadece dot + text.
            metaRow

            HStack(alignment: .top, spacing: 14) {
                AsyncRemoteImage(url: resolveImageURL(p.imageUrl) ?? capturedImageURL)
                    .frame(width: 90, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text((p.brand ?? "").uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                    Text(p.name ?? L("Bilinmeyen ürün"))
                        .font(Theme.Typo.headline)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if let cat = p.subcategory ?? p.category {
                        Text(cat)
                            .font(Theme.Typo.caption)
                            .foregroundStyle(Theme.inkMute)
                    }
                }
                Spacer(minLength: 0)
            }

            // INCI listesi backend'in top-level "ingredients" array'inden geliyor;
            // RecognizedProduct'ta INCI yok (backend D1 row'u verir).
            if let inci = recognized?.inciList, !inci.isEmpty {
                inciDisclosure(inci)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surface)
        )
    }

    /// Kartın üst tarafında SADECE confidence — renkli nokta + label, çok sade.
    @ViewBuilder
    private var metaRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(confidence.foreground)
                .frame(width: 6, height: 6)
            Text(confidence.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(confidence.foreground)
            Spacer(minLength: 0)
        }
    }

    /// Kartın en altında ince kaynak ipucu — küçük ikon + tek satır insancıl label.
    /// `parallel:consensus (sources=visual+fts score=1.34)` gibi internal via'lar
    /// kullanıcı için anlamsız, kısa label'a çevrilir.
    @ViewBuilder
    private var sourceFooter: some View {
        if let info = sourceInfo {
            HStack(spacing: 6) {
                Image(systemName: info.icon)
                    .font(.system(size: 9, weight: .regular))
                Text(info.label)
                    .font(.system(size: 10, weight: .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.inkMute)
        }
    }

    @available(*, deprecated, message: "Kapsül badge kullanılmıyor, metaRow ile birleştirildi")
    @ViewBuilder
    private var confidenceBadge: some View {
        EmptyView()
    }

    /// Backend response'unda source: hangi yoldan tanındı?
    /// "obf" → OpenBeautyFacts DB (internal)
    /// "incidecoder" → INCIDecoder canlı scrape
    /// "serper_extracted" → AI + web search
    /// "ai_partial" → kaynaksız AI (legacy, kullanılmıyor)
    /// "user_contributed" → daha önce başka kullanıcı eklemiş, DB'de mevcut
    /// "manual" → manuel giriş
    @available(*, deprecated, message: "Kapsül badge kullanılmıyor, metaRow ile birleştirildi")
    @ViewBuilder
    private var sourceBadge: some View {
        EmptyView()
    }

    /// Bu çağrıda nereden bulundu? Önce backend `via` (runtime path), yoksa `source`.
    private var sourceInfo: (label: String, icon: String)? {
        if let via = recognized?.via {
            // Bilinen exact match'ler
            switch via {
            case "d1_cache":      return (L("DB önbellek"), "bolt.fill")
            case "barcode_match": return (L("Barkod"), "barcode")
            case "barcode_back":  return (L("Barkod (arka)"), "barcode")
            case "db_first":      return (L("Katalog eşleşmesi"), "checkmark.seal.fill")
            case "barcode_obf":   return (L("Barkod (OBF)"), "barcode")
            case "incidecoder":   return ("INCIDecoder", "globe")
            case "multi_source":  return (L("Çoklu kaynak"), "rectangle.stack")
            case "serper_ai":     return (L("AI + web"), "sparkles")
            default: break
            }
            // Parallel signal pipeline output'ları — prefix-based human label
            if via.hasPrefix("parallel:barcode")    { return (L("Barkod"), "barcode") }
            if via.hasPrefix("parallel:consensus")  { return (L("Görsel + metin"), "checkmark.seal.fill") }
            if via.hasPrefix("parallel:inci_rerank"){ return (L("İçerik eşleşmesi"), "list.bullet.rectangle") }
            if via.hasPrefix("parallel:visual_strong") || via.hasPrefix("parallel:visual_only") {
                return (L("Görsel eşleşme"), "eye.fill")
            }
            if via.hasPrefix("parallel:visual_weak") || via.hasPrefix("parallel:visual_brand_mismatch") {
                return (L("Görsel (zayıf)"), "eye")
            }
            if via.hasPrefix("parallel:llm_clean_fts") { return (L("Akıllı metin eşleşmesi"), "text.viewfinder") }
            if via.hasPrefix("parallel:fts_only")      { return (L("Metin eşleşmesi"), "text.magnifyingglass") }
            // Bilinmiyor — generic
            return (L("Eşleşme bulundu"), "tag")
        }
        guard let raw = recognized?.source else { return nil }
        switch raw {
        case "obf":              return (L("DB (OBF)"), "checkmark.shield.fill")
        case "user_contributed": return (L("Topluluk"), "person.2.fill")
        case "incidecoder":      return ("INCIDecoder", "globe")
        case "serper_extracted": return (L("Web + AI"), "sparkles.rectangle.stack")
        case "ai_partial":       return (L("AI tahmin"), "sparkles")
        case "manual":           return (L("Manuel"), "pencil")
        default:                 return (raw, "tag")
        }
    }

    private func inciDisclosure(_ inci: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Haptics.selection()
                withAnimation(.easeInOut(duration: 0.2)) { inciExpanded.toggle() }
            } label: {
                HStack {
                    Text("\(L("İçindekiler")) (\(inci.count))")
                        .font(Theme.Typo.body.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: inciExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .buttonStyle(.plain)

            if inciExpanded {
                Text(inci.joined(separator: ", "))
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                .fill(Theme.canvas)
        )
    }

    // MARK: - Suggestion listesi

    // MARK: - Review summary panel (rating + concerns + pros)
    //
    // 'direct': bu spesifik ürünün yorumlarından. 'cluster': aynı formülasyon kümesindeki
    // ürünlerin yorumlarından (yeni/yorumsuz ürün için fallback).

    private func reviewSummaryPanel(_ s: ReviewSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(L("Kullanıcı yorumları"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if s.source == "cluster" {
                    Text(L("benzer formüller"))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Theme.inkMute)
                }
            }

            // Rating + count row
            HStack(spacing: 10) {
                if let avg = s.avgRating {
                    HStack(spacing: 3) {
                        Text(String(format: "%.1f", avg))
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.success)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(s.count) \(L("yorum"))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                    if s.posCount + s.negCount > 0 {
                        Text("\(s.posCount) \(L("olumlu")) · \(s.negCount) \(L("olumsuz"))")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Theme.inkMute)
                    }
                }
                Spacer()
            }

            // Top pros / concerns chips
            if !s.topPros.isEmpty {
                tagRow(label: L("Beğenilen"), items: s.topPros, color: Theme.success)
            }
            if !s.topConcerns.isEmpty {
                tagRow(label: L("Bildirilen"), items: s.topConcerns, color: Theme.alert)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surface)
        )
    }

    /// Beğenilen/bildirilen chip satırı — yatay scroll, count etiketli.
    private func tagRow(label: String, items: [ReviewTopItem], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
                .textCase(.uppercase)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(items.prefix(5), id: \.key) { item in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(color)
                                .frame(width: 5, height: 5)
                            Text(humanize(item.key))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.ink)
                            Text("\(item.count)")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(Theme.inkMute)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.surfaceLow))
                    }
                }
            }
        }
    }

    /// concern/pros key → kullanıcı dostu metin
    private func humanize(_ key: String) -> String {
        switch key {
        case "breakout": return L("Sivilce")
        case "irritation": return L("Tahriş")
        case "burning": return L("Yanma")
        case "redness": return L("Kızarıklık")
        case "dryness": return L("Kuruluk")
        case "oiliness": return L("Yağlanma")
        case "allergy": return L("Alerji")
        case "sensitivity": return L("Hassasiyet")
        case "pilling": return L("Topaklanma")
        case "sticky": return L("Yapışkanlık")
        case "fragrance_bad": return L("Koku rahatsız")
        case "moisturizing": return L("Nemlendirici")
        case "soothing": return L("Yatıştırıcı")
        case "brightening": return L("Aydınlatıcı")
        case "anti_aging": return L("Anti-aging")
        case "non_greasy": return L("Yağsız")
        case "fragrance_free": return L("Kokusuz")
        case "cleared_acne": return L("Akneyi geçirdi")
        case "smooth": return L("Pürüzsüzleştirici")
        default: return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // MARK: - Ingredient warnings panel
    //
    // Kullanıcının cilt tipinde, bu ürünün içerdiği ingredient'larla ilgili
    // toplanan endişeler. ratio (%X yorum bu concern'i belirtmiş) + count.

    private func warningsPanel(_ items: [IngredientWarning]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.alert)
                Text(L("İçerikler hakkında"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.alert)
                Spacer()
            }
            ForEach(items) { w in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(w.ingredientName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Text("→")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkMute)
                        Text(humanize(w.concern))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.alert)
                        Spacer()
                    }
                    // Provenance — kaç user, hangi oran (locale-aware percent)
                    Text("\(w.count) \(L("yorumun")) \(w.ratio, format: .percent.precision(.fractionLength(0)))\(L("'inde bildirildi"))")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Theme.inkMute)
                }
            }
            Text(L("Aynı içeriği içeren diğer ürünlerin yorumlarından çıkarılmıştır. Bu ürün için kesin bir sonuç değildir; patch test öneririz."))
                .font(.system(size: 10, weight: .regular, design: .serif).italic())
                .foregroundStyle(Theme.inkMute)
                .padding(.top, 4)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.alert.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                        .strokeBorder(Theme.alert.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func suggestionsSection(_ items: [RecognizedProduct]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Belki bu?"))
                .font(Theme.Typo.body.weight(.medium))
                .foregroundStyle(Theme.inkSoft)

            ForEach(items) { s in
                let isSelected = s.id == selectedSuggestionID
                Button {
                    Haptics.selection()
                    selectedSuggestionID = (isSelected ? nil : s.id)
                } label: {
                    HStack(spacing: 12) {
                        AsyncRemoteImage(url: resolveImageURL(s.imageUrl))
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.brand ?? "")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.inkSoft)
                            Text(s.name ?? "")
                                .font(Theme.Typo.body)
                                .foregroundStyle(Theme.ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? Theme.ink : Theme.inkMute)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                            .fill(isSelected ? Theme.surfaceLow : Theme.surface)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - "Eşleşme yok" paneli

    private var noMatchPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Theme.inkSoft)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Ürünü bulamadım"))
                        .font(Theme.Typo.body.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    Text(L("Manuel ekleyebilir veya tekrar tarayabilirsin."))
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                Button {
                    Haptics.light()
                    mode = .manual
                    seedFormFromRecognized()
                } label: {
                    Text(L("Manuel doldur"))
                        .font(Theme.Typo.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: Theme.radiusSmall).fill(Theme.ink))
                        .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(PrimaryPressedScaleButtonStyle())

                Button {
                    Haptics.light()
                    onRescan()
                } label: {
                    Text(L("Tekrar tara"))
                        .font(Theme.Typo.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.radiusSmall).strokeBorder(Theme.ink, lineWidth: 1.5)
                        )
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(PrimaryPressedScaleButtonStyle())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface)
        )
    }

    // MARK: - Manuel form

    private var manualForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            field(label: L("Marka *"), text: $brand, placeholder: "CeraVe")
            field(label: L("Ürün adı *"), text: $name, placeholder: "Hydrating Cleanser")
            field(label: L("Kategori"), text: $category, placeholder: L("Yüz temizleyici"))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface)
        )
    }

    // MARK: - Gelişmiş

    private var advancedFieldsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                Haptics.selection()
                withAnimation(.easeInOut(duration: 0.2)) { advancedExpanded.toggle() }
            } label: {
                HStack {
                    Text(L("Gelişmiş (opsiyonel)"))
                        .font(Theme.Typo.body.weight(.medium))
                        .foregroundStyle(Theme.inkSoft)
                    Spacer()
                    Image(systemName: advancedExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .buttonStyle(.plain)

            if advancedExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    field(label: L("Takma ad"), text: $nickname, placeholder: L("Sabah temizleyicim"))

                    Toggle(isOn: $openedToday) {
                        Text(L("Bugün açtım"))
                            .font(Theme.Typo.body)
                            .foregroundStyle(Theme.ink)
                    }
                    .tint(Theme.ink)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Puan"))
                            .font(Theme.Typo.caption)
                            .foregroundStyle(Theme.inkSoft)
                        HStack(spacing: 6) {
                            ForEach(1...5, id: \.self) { i in
                                Button {
                                    Haptics.selection()
                                    rating = (rating == i) ? 0 : i
                                } label: {
                                    Image(systemName: i <= rating ? "star.fill" : "star")
                                        .font(.system(size: 22))
                                        .foregroundStyle(i <= rating ? Theme.ink : Theme.inkMute)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("Notlar"))
                            .font(Theme.Typo.caption)
                            .foregroundStyle(Theme.inkSoft)
                        TextField(L("İstersen kısa not..."), text: $notes, axis: .vertical)
                            .lineLimit(2...4)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.radiusSmall)
                                    .fill(Theme.canvas)
                            )
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface)
                )
            }
        }
    }

    // MARK: - Footer

    private var footerButtons: some View {
        VStack(spacing: 10) {
            PrimaryActionButton(
                title: mode == .manual ? L("Manuel ekle") : L("Bu doğru, arşive ekle"),
                systemImage: "checkmark",
                isEnabled: canSubmit,
                isLoading: isSubmitting,
                hapticStyle: .heavy
            ) {
                Task { await submit() }
            }

            HStack {
                Button {
                    Haptics.light()
                    onRescan()
                } label: {
                    Text(L("Tekrar tara"))
                        .font(Theme.Typo.body.weight(.medium))
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                if mode == .review, recognized?.product != nil {
                    Button {
                        Haptics.light()
                        mode = .manual
                    } label: {
                        Text(L("Manuel düzenle"))
                            .font(Theme.Typo.body.weight(.medium))
                            .foregroundStyle(Theme.inkSoft)
                    }
                } else if mode == .manual, recognized?.product != nil {
                    Button {
                        Haptics.light()
                        mode = .review
                    } label: {
                        Text(L("Sonuca geri dön"))
                            .font(Theme.Typo.body.weight(.medium))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
            }
        }
    }

    // MARK: - Form helper

    private func field(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.inkSoft)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall)
                        .fill(Theme.canvas)
                )
        }
    }

    // MARK: - Seeding

    private func seedFormFromRecognized() {
        if let p = primaryProduct {
            brand = p.brand ?? ""
            name = p.name ?? ""
            category = p.subcategory ?? p.category ?? ""
        }
    }

    private var capturedImageURL: URL? { nil }

    // MARK: - Submit

    @MainActor
    private func submit() async {
        submitError = nil
        isSubmitting = true
        defer { isSubmitting = false }

        let openedAt: Int? = openedToday ? Int(Date().timeIntervalSince1970) : nil
        let ratingValue: Int? = rating > 0 ? rating : nil
        let notesValue: String? = notes.trimmed.isEmpty ? nil : notes.trimmed
        let nicknameValue: String? = nickname.trimmed.isEmpty ? nil : nickname.trimmed

        let request: UserProductCreateRequest
        switch mode {
        case .review:
            guard let p = primaryProduct else {
                submitError = L("Ürün seçilmedi.")
                Haptics.error()
                return
            }
            request = UserProductCreateRequest(
                productId: p.id,
                nickname: nicknameValue,
                photoUrl: photoUrl,
                openedAt: openedAt,
                rating: ratingValue,
                notes: notesValue,
                addedVia: "scan",
                manualBrand: nil,
                manualName: nil,
                manualCategory: nil
            )
        case .manual:
            request = UserProductCreateRequest(
                productId: nil,
                nickname: nicknameValue,
                photoUrl: photoUrl,
                openedAt: openedAt,
                rating: ratingValue,
                notes: notesValue,
                addedVia: photoUrl == nil ? "manual" : "scan",
                manualBrand: brand.trimmed,
                manualName: name.trimmed,
                manualCategory: category.trimmed.isEmpty ? nil : category.trimmed
            )
        }

        do {
            let result = try await ProductScanService.shared.addToArchive(request)
            Haptics.success()
            onSubmitted(result)
        } catch {
            Haptics.error()
            submitError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    /// Backend `image_url` field'i bazen relative ("/v1/images/...") bazen absolute döner.
    /// Relative ise AppConfig.baseURL ile birleştir.
    private func resolveImageURL(_ raw: String?) -> URL? {
        guard let raw = raw, !raw.isEmpty else { return nil }
        if let abs = URL(string: raw), abs.scheme != nil { return abs }
        // Relative path — baseURL'e ekle
        return URL(string: raw, relativeTo: AppConfig.baseURL)?.absoluteURL
    }
}

// MARK: - Confidence görselleştirme

private enum Confidence: String {
    case high, medium, low, none

    var label: String {
        switch self {
        case .high: return L("Güçlü eşleşme")
        case .medium: return L("Olası eşleşme")
        case .low: return L("Zayıf eşleşme")
        case .none: return L("Tanınmadı")
        }
    }
    var icon: String {
        switch self {
        case .high: return "checkmark.seal.fill"
        case .medium: return "checkmark.seal"
        case .low: return "exclamationmark.triangle"
        case .none: return "questionmark.circle"
        }
    }
    var foreground: Color {
        switch self {
        case .high: return Theme.success
        case .medium: return Theme.ink
        case .low, .none: return Theme.alert
        }
    }
    var background: Color {
        switch self {
        case .high: return Theme.success.opacity(0.15)
        case .medium: return Theme.surfaceLow
        case .low, .none: return Theme.alert.opacity(0.12)
        }
    }
}

// MARK: - String trim helper

extension String {
    fileprivate var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
