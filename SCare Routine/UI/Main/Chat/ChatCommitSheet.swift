import SwiftUI

/// Sohbet taslağını rutine kaydetme sheet'i: yeni rutin (isim + sabah/akşam) veya
/// mevcut rutine ekle (picker). Backend schedule + emoji'yi time_slot'tan türetir.
struct ChatCommitSheet: View {
    @Bindable var vm: ChatViewModel
    let defaultName: String
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var timeSlot: String = "morning"
    @State private var mode: String = "new"
    @State private var targetRoutineId: String?
    @State private var isWorking = false

    init(vm: ChatViewModel, defaultName: String, onDone: @escaping () -> Void) {
        self.vm = vm
        self.defaultName = defaultName
        self.onDone = onDone
        _name = State(initialValue: defaultName)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Picker("", selection: $mode) {
                            Text(L("Yeni rutin")).tag("new")
                            Text(L("Mevcuda ekle")).tag("merge")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: mode) { Haptics.selection() }

                        if mode == "new" {
                            field(L("Rutin adı")) {
                                TextField(L("Rutin adı"), text: $name)
                                    .font(Theme.Typo.body)
                                    .padding(.horizontal, 14).padding(.vertical, 12)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surfaceLow))
                            }
                            field(L("Ne zaman?")) {
                                Picker("", selection: $timeSlot) {
                                    Text("☀️ \(L("Sabah"))").tag("morning")
                                    Text("🌙 \(L("Akşam"))").tag("evening")
                                }
                                .pickerStyle(.segmented)
                                .onChange(of: timeSlot) { Haptics.selection() }
                            }
                        } else {
                            field(L("Hangi rutine eklensin?")) {
                                if vm.existingRoutines.isEmpty {
                                    Text(L("Henüz bir rutinin yok."))
                                        .font(Theme.Typo.caption).foregroundStyle(Theme.inkSoft)
                                } else {
                                    VStack(spacing: 8) {
                                        ForEach(vm.existingRoutines) { r in
                                            routineRow(r)
                                        }
                                    }
                                }
                            }
                        }

                        Text(String(format: L("%d adım kaydedilecek."), vm.draft.steps.count))
                            .font(Theme.Typo.caption).foregroundStyle(Theme.inkMute)
                    }
                    .padding(16)
                }
                VStack {
                    Spacer()
                    PrimaryActionButton(
                        title: L("Kaydet"),
                        isEnabled: canSave && !isWorking,
                        isLoading: isWorking,
                        style: .filled,
                        hapticStyle: .heavy,
                        action: { Task { await save() } }
                    )
                    .padding(16)
                }
            }
            .navigationTitle(L("Rutini Kaydet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("Vazgeç")) { dismiss() }.tint(Theme.ink)
                }
            }
            .task { await vm.loadRoutines() }
        }
    }

    private var canSave: Bool {
        if mode == "merge" { return targetRoutineId != nil }
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() async {
        isWorking = true
        let ok = await vm.commit(
            mode: mode,
            targetRoutineId: mode == "merge" ? targetRoutineId : nil,
            name: mode == "new" ? name.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            timeSlot: timeSlot
        )
        isWorking = false
        if ok { Haptics.success(); onDone(); dismiss() }
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(Theme.Typo.caption.weight(.semibold)).foregroundStyle(Theme.inkSoft)
            content()
        }
    }

    private func routineRow(_ r: RoutineResponse) -> some View {
        Button {
            Haptics.selection(); targetRoutineId = r.id
        } label: {
            HStack(spacing: 10) {
                Text(r.emoji ?? "✨").font(.system(size: 20))
                Text(r.name).font(Theme.Typo.body).foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: targetRoutineId == r.id ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(targetRoutineId == r.id ? Theme.ink : Theme.inkMute)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(targetRoutineId == r.id ? Theme.surface : Theme.surfaceLow))
        }
        .buttonStyle(.plain)
    }
}
