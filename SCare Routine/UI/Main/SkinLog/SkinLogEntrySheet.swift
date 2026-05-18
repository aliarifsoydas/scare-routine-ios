import SwiftUI
import PhotosUI
import UIKit

/// Günlük cilt değerlendirme sheet'i.
///
/// Multi-step wizard yerine tek scrollable form — Cal AI tarzı, hızlıca geçilebilir.
/// Bölümler: selfie (opsiyonel) + 5 metrik slider + semptom chip'leri + notes +
/// uyku/stres. Submit'te:
/// 1. Selfie varsa R2'ye upload edilir (`SkinLogService.uploadSelfie`)
/// 2. `SkinLogCreateRequest` derlenir, profile.defaultPhotoMode set edilir
/// 3. `SkinLogService.create` çağrılır
/// 4. Backend metrics_only modda gözlemleri çıkarttıktan sonra fotoyu siler
struct SkinLogEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    /// Sheet kapanırken parent'a yeni log haberini ver — refetch tetiklesin.
    var onCreated: ((SkinLogResponse) -> Void)?

    // MARK: - Form state

    @State private var selfieImage: UIImage?
    @State private var photosPickerItem: PhotosPickerItem?

    @State private var hydration: Int = 3
    @State private var redness: Int = 3
    @State private var oiliness: Int = 3
    @State private var breakouts: Int = 3
    @State private var overall: Int = 3

    @State private var selectedSymptoms: Set<String> = []
    @State private var notes: String = ""

    @State private var sleepHours: Double = 7.5
    @State private var stressLevel: Int = 3

    // MARK: - Submission state

    @State private var isSubmitting: Bool = false
    @State private var submitError: String?
    @State private var showCamera: Bool = false

    private let availableSymptoms: [String] = [
        "kuruluk", "kaşıntı", "yanma", "kızarıklık",
        "pul pul", "leke", "döküntü", "T-zone yağlanma", "yanaklar kuru"
    ]

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        selfieSection
                        metricsSection
                        symptomsSection
                        notesSection
                        lifestyleSection

                        if let submitError {
                            Text(submitError)
                                .font(Theme.Typo.caption)
                                .foregroundStyle(Theme.alert)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        OnboardingPrimaryButton(
                            title: "Kaydet",
                            isEnabled: !isSubmitting,
                            isLoading: isSubmitting,
                            hapticStyle: .heavy
                        ) {
                            Task { await submit() }
                        }
                        .padding(.top, 8)

                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Bugün cildin nasıl?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.light()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .disabled(isSubmitting)
                }
            }
            .interactiveDismissDisabled(isSubmitting)
            .onChange(of: photosPickerItem) { _, newValue in
                guard let item = newValue else { return }
                Task {
                    if let img = await item.loadUIImage() {
                        selfieImage = img
                    }
                }
            }
            .sheet(isPresented: $showCamera) {
                SkinSelfieCameraPicker { image in
                    selfieImage = image
                }
            }
        }
        .tint(Theme.ink)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(todayLongDate)
                .font(Theme.Typo.body.weight(.medium))
                .foregroundStyle(Theme.inkSoft)
            Text("Hızlı bir öz değerlendirme — birkaç saniye sürer.")
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.inkMute)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selfieSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Selfie ekle (opsiyonel)")

            HStack(spacing: 12) {
                if let img = selfieImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                                .strokeBorder(Theme.divider, lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                        .fill(Theme.surface)
                        .frame(width: 96, height: 96)
                        .overlay(
                            Image(systemName: "person.crop.circle.dashed")
                                .font(.system(size: 32, weight: .light))
                                .foregroundStyle(Theme.inkMute)
                        )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        Haptics.light()
                        showCamera = true
                    } label: {
                        Label("Çek", systemImage: "camera.fill")
                            .font(Theme.Typo.body.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                                    .fill(Theme.ink)
                            )
                            .foregroundStyle(Theme.onAccent)
                    }
                    .buttonStyle(PressedScaleButtonStyle())

                    PhotosPicker(selection: $photosPickerItem, matching: .images) {
                        Label("Galeri", systemImage: "photo.on.rectangle")
                            .font(Theme.Typo.body.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                                    .strokeBorder(Theme.divider, lineWidth: 1)
                            )
                            .foregroundStyle(Theme.ink)
                    }
                }
            }

            if selfieImage != nil {
                Button {
                    Haptics.light()
                    selfieImage = nil
                    photosPickerItem = nil
                } label: {
                    Text("Selfieyi kaldır")
                        .font(Theme.Typo.caption.weight(.medium))
                        .foregroundStyle(Theme.alert)
                }
                .buttonStyle(.plain)
            }

            photoModeHint
        }
    }

    @ViewBuilder
    private var photoModeHint: some View {
        let mode = appState.currentProfile?.defaultPhotoMode ?? "metrics_only"
        let isMetricsOnly = (mode == "metrics_only")
        HStack(spacing: 8) {
            Image(systemName: isMetricsOnly ? "lock.shield" : "photo")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Theme.inkSoft)
            Text(isMetricsOnly
                 ? "Foto modu: Sadece veri — AI gözlem çıkarır, foto silinir."
                 : "Foto modu: Foto saklanır — geçmişte tekrar göreceksin."
            )
            .font(Theme.Typo.caption)
            .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                .fill(Theme.surfaceLow)
        )
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Bugünkü cildin")

            metricRow(label: "Nem", value: $hydration, minLabel: "kuru", maxLabel: "nemli")
            metricRow(label: "Kızarıklık", value: $redness, minLabel: "yok", maxLabel: "çok")
            metricRow(label: "Yağlılık", value: $oiliness, minLabel: "yok", maxLabel: "çok")
            metricRow(label: "Sivilce", value: $breakouts, minLabel: "yok", maxLabel: "çok")
            metricRow(label: "Genel", value: $overall, minLabel: "kötü", maxLabel: "harika")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surface)
        )
    }

    private func metricRow(
        label: String,
        value: Binding<Int>,
        minLabel: String,
        maxLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(Theme.Typo.body.weight(.medium))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(value.wrappedValue)/5")
                    .font(Theme.Typo.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            DotScale(value: value, range: 1...5)
            HStack {
                Text(minLabel)
                Spacer()
                Text(maxLabel)
            }
            .font(Theme.Typo.caption)
            .foregroundStyle(Theme.inkMute)
        }
    }

    private var symptomsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Semptomlar (opsiyonel)")

            // FlowLayout pattern — basit wrap için LazyVGrid kullanıyoruz
            FlowingChips(items: availableSymptoms, selected: selectedSymptoms) { sym in
                if selectedSymptoms.contains(sym) {
                    selectedSymptoms.remove(sym)
                } else {
                    selectedSymptoms.insert(sym)
                }
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Notlar (opsiyonel)")

            TextField(
                "Bugün retinol kullandım, parfümlü bir ürün denedim…",
                text: $notes,
                axis: .vertical
            )
            .font(Theme.Typo.body)
            .foregroundStyle(Theme.ink)
            .lineLimit(3...6)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.surface)
            )
        }
    }

    private var lifestyleSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Ek bilgi (opsiyonel)")

            // Uyku
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Uyku")
                        .font(Theme.Typo.body.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text(String(format: "%.1f saat", sleepHours))
                        .font(Theme.Typo.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
                Slider(value: $sleepHours, in: 0...12, step: 0.5)
                    .tint(Theme.ink)
            }

            // Stres
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Stres")
                        .font(Theme.Typo.body.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(stressLevel)/5")
                        .font(Theme.Typo.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
                DotScale(value: $stressLevel, range: 1...5)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surface)
        )
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typo.headline)
            .foregroundStyle(Theme.ink)
    }

    // MARK: - Helpers

    private var todayLongDate: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "tr_TR")
        fmt.dateFormat = "d MMMM EEEE"
        return fmt.string(from: .now)
    }

    private static func ymdString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = .current
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    // MARK: - Submit

    private func submit() async {
        guard !isSubmitting else { return }
        submitError = nil
        isSubmitting = true
        defer { isSubmitting = false }

        var selfieUrl: String?
        if let img = selfieImage {
            do {
                selfieUrl = try await SkinLogService.shared.uploadSelfie(img)
            } catch {
                submitError = "Selfie yüklenemedi. Tekrar dene veya selfiesiz kaydet."
                Haptics.error()
                return
            }
        }

        let photoMode = appState.currentProfile?.defaultPhotoMode ?? "metrics_only"
        let payload = SkinLogCreateRequest(
            logDate: Self.ymdString(.now),
            category: "face",
            selfieUrl: selfieUrl,
            photoMode: photoMode,
            selfHydration: hydration,
            selfRedness: redness,
            selfOiliness: oiliness,
            selfBreakouts: breakouts,
            selfOverall: overall,
            symptoms: selectedSymptoms.isEmpty ? nil : Array(selectedSymptoms),
            sleepHours: sleepHours,
            stressLevel: stressLevel,
            subjectiveNotes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
        )

        do {
            let created = try await SkinLogService.shared.create(payload)
            Haptics.success()
            onCreated?(created)
            dismiss()
        } catch let APIError.server(_, message, _) {
            submitError = message.isEmpty ? "Kaydedilemedi. Tekrar dene." : message
            Haptics.error()
        } catch {
            submitError = "Kaydedilemedi. Tekrar dene."
            Haptics.error()
        }
    }
}

// MARK: - DotScale (custom 1-5 dot slider)

/// 5 dot'lu HStack — her dot tap edilebilir. Seçili noktaya kadar olan dot'lar dolu
/// (Theme.ink), sonrası boş (Theme.surfaceLow). Standart Slider yerine ölçek bazlı
/// (1-5) discrete seçim için daha okunaklı.
struct DotScale: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(range), id: \.self) { i in
                Button {
                    Haptics.selection()
                    value = i
                } label: {
                    Circle()
                        .fill(i <= value ? Theme.ink : Theme.surfaceLow)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .strokeBorder(Theme.divider, lineWidth: i <= value ? 0 : 1)
                        )
                        .scaleEffect(i == value ? 1.15 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: value)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("\(i)")
                .accessibilityAddTraits(i == value ? .isSelected : [])
            }
        }
    }
}

// MARK: - Flowing chips wrapping layout

/// SwiftUI native bir wrap layout yok — basit row-wrap implementasyonu.
/// Tek ekran genişliğindeki chip listesi için yeterli, GeometryReader bazlı.
struct FlowingChips: View {
    let items: [String]
    let selected: Set<String>
    let onTap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(items, id: \.self) { item in
                OnboardingChip(
                    title: item,
                    symbol: nil,
                    isSelected: selected.contains(item)
                ) {
                    onTap(item)
                }
            }
        }
    }
}

/// iOS 16+ `Layout` protokolü ile basit horizontal flow (wrap).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if lineWidth + size.width > maxWidth, lineWidth > 0 {
                totalHeight += lineHeight + lineSpacing
                totalWidth = max(totalWidth, lineWidth - spacing)
                lineWidth = 0
                lineHeight = 0
            }
            lineWidth += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        totalHeight += lineHeight
        totalWidth = max(totalWidth, lineWidth - spacing)
        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Camera picker (basit UIImagePickerController sarmalayıcı)

/// Sade selfie kamera — UIImagePickerController ile ön kamera default. Ayrı bir
/// "skin selfie" tasarımına gerek yok; kullanıcı bir foto çeker, biz UIImage alırız.
struct SkinSelfieCameraPicker: UIViewControllerRepresentable {
    var onPicked: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            // Ön kamera mümkünse selfie için tercih et
            if UIImagePickerController.isCameraDeviceAvailable(.front) {
                picker.cameraDevice = .front
            }
        } else {
            picker.sourceType = .photoLibrary
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: SkinSelfieCameraPicker
        init(_ parent: SkinSelfieCameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
        ) {
            if let img = info[.originalImage] as? UIImage {
                parent.onPicked(img)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
