import SwiftUI

/// Yeni rutin oluşturma flow'u. Minimum bilgi: ad + zaman dilimi.
/// İleri seviyede: kategori, emoji, renk, hatırlatma — opsiyonel.
struct CreateRoutineSheet: View {
    @Environment(\.dismiss) private var dismiss

    var onCreated: (RoutineResponse) -> Void

    @State private var name: String = ""
    @State private var timeOfDay: TimeSlot = .morning
    @State private var hour: Int = 8
    @State private var minute: Int = 0
    @State private var category: CategoryOption = .skincare
    @State private var emoji: String = "✨"
    @State private var reminder: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var submitError: String?

    enum TimeSlot: String, CaseIterable, Identifiable {
        case morning, evening, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .morning: return L("timeslot_morning")
            case .evening: return L("timeslot_evening")
            case .custom: return L("timeslot_midday")
            }
        }
        var systemImage: String {
            switch self {
            case .morning: return "sun.max"
            case .evening: return "moon.stars"
            case .custom: return "clock"
            }
        }
        var defaultHour: Int {
            switch self {
            case .morning: return 8
            case .evening: return 21
            case .custom: return 12
            }
        }
        var suggestedName: String {
            switch self {
            case .morning: return L("routine_name_morning")
            case .evening: return L("routine_name_evening")
            case .custom: return ""
            }
        }
    }

    enum CategoryOption: String, CaseIterable, Identifiable {
        case skincare, haircare, bodycare, makeup
        var id: String { rawValue }
        var label: String {
            switch self {
            case .skincare: return L("category_option_skincare")
            case .haircare: return L("category_option_haircare")
            case .bodycare: return L("category_option_bodycare")
            case .makeup: return L("category_option_makeup")
            }
        }
        var emoji: String {
            switch self {
            case .skincare: return "🧴"
            case .haircare: return "💆"
            case .bodycare: return "🧖"
            case .makeup: return "💄"
            }
        }
    }

    private let emojiOptions = ["✨", "🧴", "💆", "🧖", "💄", "☀️", "🌙", "🌿", "💧", "🧪"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        ForEach(TimeSlot.allCases) { slot in
                            slotButton(slot)
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    .listRowBackground(Color.clear)
                } header: {
                    Text(L("Ne zaman?"))
                }

                Section {
                    TextField(L("Örn. Sabah Rutini"), text: $name)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text(L("Adı"))
                }

                Section {
                    HStack(spacing: 0) {
                        Picker(L("Saat"), selection: $hour) {
                            ForEach(0..<24) { Text(String(format: "%02d", $0)).tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        Picker(L("Dakika"), selection: $minute) {
                            ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: 110)
                    Toggle(L("Bildirim hatırlat"), isOn: $reminder)
                } header: {
                    Text(L("Saat"))
                }

                Section {
                    Picker(L("Kategori"), selection: $category) {
                        ForEach(CategoryOption.allCases) { c in
                            HStack {
                                Text(c.emoji)
                                Text(c.label)
                            }
                            .tag(c)
                        }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                        ForEach(emojiOptions, id: \.self) { e in
                            Button {
                                Haptics.selection()
                                emoji = e
                            } label: {
                                Text(e)
                                    .font(.system(size: 24))
                                    .frame(width: 44, height: 44)
                                    .background(
                                        Circle()
                                            .fill(emoji == e ? Theme.ink.opacity(0.12) : Theme.surface.opacity(0.5))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text(L("Kategori & emoji"))
                }

                if let err = submitError {
                    Section {
                        Text(err)
                            .foregroundStyle(Theme.alert)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle(L("Yeni Rutin"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("İptal")) { dismiss() }
                        .foregroundStyle(Theme.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSubmitting {
                        ProgressView().tint(Theme.inkSoft)
                    } else {
                        Button(L("Oluştur")) {
                            Task { await submit() }
                        }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .onChange(of: timeOfDay) { _, newValue in
                hour = newValue.defaultHour
                if name.isEmpty {
                    name = newValue.suggestedName
                }
            }
            .onAppear {
                // Akşam saatinde (>=14) açtıysa akşam preset
                let h = Calendar.current.component(.hour, from: Date())
                if timeOfDay == .morning && h >= 14 {
                    timeOfDay = .evening
                    hour = TimeSlot.evening.defaultHour
                }
            }
        }
    }

    @ViewBuilder
    private func slotButton(_ slot: TimeSlot) -> some View {
        Button {
            Haptics.selection()
            timeOfDay = slot
        } label: {
            VStack(spacing: 6) {
                Image(systemName: slot.systemImage)
                    .font(.system(size: 18, weight: .regular))
                Text(slot.label)
                    .font(Theme.Typo.caption.weight(.semibold))
            }
            .foregroundStyle(timeOfDay == slot ? Theme.onAccent : Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(timeOfDay == slot ? Theme.ink : Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(timeOfDay == slot ? Color.clear : Theme.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func submit() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }

        var schedule = RoutineSchedulePayload()
        schedule.time = String(format: "%02d:%02d", hour, minute)
        schedule.tz = TimeZone.current.identifier
        schedule.frequency = "daily"

        let req = RoutineCreateRequest(
            name: trimmedName,
            categoryId: category.rawValue,
            schedule: schedule,
            reminder: reminder,
            colorHex: nil,
            emoji: emoji,
            orderIndex: timeOfDay == .morning ? 0 : (timeOfDay == .evening ? 100 : 50),
            steps: []
        )

        do {
            let (routine, _) = try await RoutineService.shared.createRoutine(req)
            Haptics.success()
            onCreated(routine)
            dismiss()
        } catch {
            submitError = L("Oluşturulamadı. Bağlantını kontrol et.")
            Haptics.error()
        }
    }
}
