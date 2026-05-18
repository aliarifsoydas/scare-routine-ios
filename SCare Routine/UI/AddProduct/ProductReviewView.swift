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
            return primaryProduct == nil ? "Tam tanıyamadım" : "Doğru ürün mü?"
        case .manual:
            return "Manuel ekle"
        }
    }

    private var modeSubtitle: String? {
        switch mode {
        case .review:
            switch confidence {
            case .high:   return "Eşleşme güçlü görünüyor."
            case .medium: return "Bir alternatif yakaladım — emin değilim, sen onayla."
            case .low, .none:
                return "Ürünü göremedim. Aşağıdan manuel eklemeyi deneyebilirsin."
            }
        case .manual:
            return "Marka ve ürün adı yeterli. İstersen sonradan düzenleyebilirsin."
        }
    }

    // MARK: - Sonuç kartı

    private func productCard(_ p: RecognizedProduct) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                AsyncRemoteImage(url: p.imageUrl.flatMap(URL.init(string:)) ?? capturedImageURL)
                    .frame(width: 90, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text((p.brand ?? "").uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                    Text(p.name ?? "Bilinmeyen ürün")
                        .font(Theme.Typo.headline)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if let cat = p.subcategory ?? p.category {
                        Text(cat)
                            .font(Theme.Typo.caption)
                            .foregroundStyle(Theme.inkMute)
                    }
                    confidenceBadge
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

    @ViewBuilder
    private var confidenceBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: confidence.icon)
                .font(.system(size: 11, weight: .semibold))
            Text(confidence.label)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(confidence.foreground)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(confidence.background))
    }

    private func inciDisclosure(_ inci: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Haptics.selection()
                withAnimation(.easeInOut(duration: 0.2)) { inciExpanded.toggle() }
            } label: {
                HStack {
                    Text("İçindekiler (\(inci.count))")
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

    private func suggestionsSection(_ items: [RecognizedProduct]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Belki bu?")
                .font(Theme.Typo.body.weight(.medium))
                .foregroundStyle(Theme.inkSoft)

            ForEach(items) { s in
                let isSelected = s.id == selectedSuggestionID
                Button {
                    Haptics.selection()
                    selectedSuggestionID = (isSelected ? nil : s.id)
                } label: {
                    HStack(spacing: 12) {
                        AsyncRemoteImage(url: s.imageUrl.flatMap(URL.init(string:)))
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
                    Text("Ürünü bulamadım")
                        .font(Theme.Typo.body.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    Text("Manuel ekleyebilir veya tekrar tarayabilirsin.")
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
                    Text("Manuel doldur")
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
                    Text("Tekrar tara")
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
            field(label: "Marka *", text: $brand, placeholder: "CeraVe")
            field(label: "Ürün adı *", text: $name, placeholder: "Hydrating Cleanser")
            field(label: "Kategori", text: $category, placeholder: "Yüz temizleyici")
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
                    Text("Gelişmiş (opsiyonel)")
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
                    field(label: "Takma ad", text: $nickname, placeholder: "Sabah temizleyicim")

                    Toggle(isOn: $openedToday) {
                        Text("Bugün açtım")
                            .font(Theme.Typo.body)
                            .foregroundStyle(Theme.ink)
                    }
                    .tint(Theme.ink)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Puan")
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
                        Text("Notlar")
                            .font(Theme.Typo.caption)
                            .foregroundStyle(Theme.inkSoft)
                        TextField("İstersen kısa not...", text: $notes, axis: .vertical)
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
                title: mode == .manual ? "Manuel ekle" : "Bu doğru, arşive ekle",
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
                    Text("Tekrar tara")
                        .font(Theme.Typo.body.weight(.medium))
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                if mode == .review, recognized?.product != nil {
                    Button {
                        Haptics.light()
                        mode = .manual
                    } label: {
                        Text("Manuel düzenle")
                            .font(Theme.Typo.body.weight(.medium))
                            .foregroundStyle(Theme.inkSoft)
                    }
                } else if mode == .manual, recognized?.product != nil {
                    Button {
                        Haptics.light()
                        mode = .review
                    } label: {
                        Text("Sonuca geri dön")
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
                submitError = "Ürün seçilmedi."
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
}

// MARK: - Confidence görselleştirme

private enum Confidence: String {
    case high, medium, low, none

    var label: String {
        switch self {
        case .high: return "Güçlü eşleşme"
        case .medium: return "Olası eşleşme"
        case .low: return "Zayıf eşleşme"
        case .none: return "Tanınmadı"
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
