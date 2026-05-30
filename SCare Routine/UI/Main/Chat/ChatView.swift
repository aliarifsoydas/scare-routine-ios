import SwiftUI
import Combine

/// AI Chat → Rutin ekranı. Mesaj listesi + canlı rutin taslağı kartı + input bar.
struct ChatView: View {
    @State private var vm: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var inputFocused: Bool
    @State private var showCommitSheet = false
    @State private var showDraftSheet = false
    @State private var didCommit = false

    init(locale: String, existingSessionId: String? = nil) {
        _vm = State(initialValue: ChatViewModel(locale: locale, existingSessionId: existingSessionId))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()
                VStack(spacing: 0) {
                    messageList
                    if let ps = vm.profileSuggestion, !vm.profileSuggestionHandled {
                        profileSuggestionCard(ps)
                    }
                    // Öneri kartları her zaman görünür (taslak kompakt bar olduğu için yer var).
                    if !vm.suggestedProducts.isEmpty { suggestionStrip }
                    if vm.hasDraft { draftBar }
                    inputBar
                }
            }
            .navigationTitle(L("Rutin Asistanı"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { Haptics.light(); dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                    }
                    .tint(Theme.ink)
                }
            }
            .task { await vm.bootstrap() }
            .alert(L("Hata"), isPresented: Binding(get: { vm.errorMessage != nil }, set: { if !$0 { vm.errorMessage = nil } })) {
                Button(L("Tamam"), role: .cancel) {}
            } message: {
                Text(vm.errorMessage ?? "")
            }
            .sheet(isPresented: $showCommitSheet) {
                ChatCommitSheet(vm: vm, defaultName: L("Sabah Rutini")) {
                    didCommit = true
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showDraftSheet) {
                draftSheet
            }
        }
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if vm.isStarting && vm.messages.isEmpty {
                        ProgressView().tint(Theme.inkSoft).padding(.top, 40)
                    }
                    ForEach(vm.messages) { msg in
                        ChatBubble(message: msg).id(msg.id)
                    }
                    if vm.isSending {
                        TypingIndicator().id("typing")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: vm.messages.count) { scrollToBottom(proxy) }
            .onChange(of: vm.isSending) { scrollToBottom(proxy) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            if vm.isSending {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let last = vm.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    // MARK: - Draft (kompakt bar — dokununca tam sheet açılır; yer kaplamasın)

    private var draftBar: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.light(); showDraftSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 13, weight: .semibold))
                    Text(String(format: L("Taslak · %d adım · %%%d"), vm.draft.steps.count, vm.draft.suitabilityScore))
                        .font(Theme.Typo.caption.weight(.semibold))
                    Image(systemName: "chevron.up").font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                Haptics.heavy(); showCommitSheet = true
            } label: {
                Text(didCommit ? L("Kaydedildi ✓") : L("Kaydet"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 14).frame(minHeight: 32)
                    .background(Capsule().fill(canCommit ? Theme.ink : Theme.inkMute))
            }
            .disabled(!canCommit)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Theme.surface)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.divider), alignment: .top)
    }

    private var draftSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(format: L("%d adım · uyum %%%d"), vm.draft.steps.count, vm.draft.suitabilityScore))
                        .font(Theme.Typo.caption).foregroundStyle(Theme.inkSoft)

                    ForEach(vm.draft.steps) { step in
                        let p = vm.productsById[step.userProductId]
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(step.orderIndex + 1)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.onAccent)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Theme.ink))
                            if let u = p?.photoUrl, let url = URL(string: u) {
                                AsyncImage(url: url) { img in
                                    img.resizable().scaledToFit()
                                } placeholder: {
                                    Color.clear
                                }
                                .frame(width: 40, height: 40)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(productName(p))
                                    .font(Theme.Typo.body.weight(.semibold)).foregroundStyle(Theme.ink)
                                    .lineLimit(2)
                                Text(step.rationale).font(Theme.Typo.caption).foregroundStyle(Theme.inkSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let freq = step.frequencyLabel {
                                    Text(freq).font(.system(size: 11)).foregroundStyle(Theme.inkMute)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }

                    if !vm.draft.missingCategories.isEmpty {
                        Text(String(format: L("Eksik: %@"), vm.draft.missingCategories.joined(separator: ", ")))
                            .font(.system(size: 12)).foregroundStyle(Theme.inkMute)
                    }
                }
                .padding(16)
            }
            .background(Theme.canvas)
            .navigationTitle(L("Taslak rutin"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("Kapat")) { showDraftSheet = false }.tint(Theme.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(didCommit ? L("Kaydedildi ✓") : L("Kaydet")) {
                        showDraftSheet = false; Haptics.heavy(); showCommitSheet = true
                    }.disabled(!canCommit).tint(Theme.ink)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Profil önerisi (onaylı kayıt)

    private func profileSuggestionCard(_ ps: ChatProfileSuggestion) -> some View {
        var parts: [String] = []
        if let st = ps.skinType { parts.append("\(L("Cilt tipi")): \(skinTypeLabel(st))") }
        if !ps.concerns.isEmpty { parts.append("\(L("Endişeler")): \(ps.concerns.joined(separator: ", "))") }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.badge.checkmark").font(.system(size: 13, weight: .semibold))
                Text(L("Profiline kaydedeyim mi?")).font(Theme.Typo.caption.weight(.semibold))
            }
            .foregroundStyle(Theme.ink)
            Text(parts.joined(separator: " · ")).font(Theme.Typo.caption).foregroundStyle(Theme.inkSoft)
            HStack(spacing: 8) {
                Button {
                    Haptics.light(); Task { await vm.saveProfile() }
                } label: {
                    Text(L("Kaydet")).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 16).frame(minHeight: 30).background(Capsule().fill(Theme.ink))
                }
                .buttonStyle(.plain)
                Button {
                    Haptics.light(); vm.dismissProfileSuggestion()
                } label: {
                    Text(L("Şimdilik değil")).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, 14).frame(minHeight: 30).background(Capsule().fill(Theme.surfaceLow))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.divider), alignment: .top)
    }

    private func skinTypeLabel(_ code: String) -> String {
        switch code.lowercased() {
        case "oily": return L("Yağlı")
        case "dry": return L("Kuru")
        case "combination": return L("Karma")
        case "sensitive": return L("Hassas")
        case "normal": return L("Normal")
        default: return code
        }
    }

    // MARK: - Önerilen ürünler (sahip olunmayan → Alınacaklara ekle)

    private var suggestionStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Önerilen ürünler"))
                .font(Theme.Typo.caption.weight(.semibold))
                .foregroundStyle(Theme.inkSoft)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(vm.suggestedProducts) { sp in
                        suggestionCard(sp)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 8)
    }

    private func suggestionCard(_ sp: ChatSuggestedProduct) -> some View {
        let added = vm.wishlistedIds.contains(sp.productId)
        return VStack(alignment: .leading, spacing: 6) {
            if let u = sp.imageUrl, let url = URL(string: u) {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFit()
                } placeholder: {
                    Color.clear
                }
                .frame(height: 64)
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            Text([sp.brand, sp.name].compactMap { $0 }.joined(separator: " "))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
            Text(sp.reason)
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                Haptics.light()
                Task { await vm.addToWishlist(sp) }
            } label: {
                Text(added ? L("Eklendi ✓") : L("Alınacaklara ekle"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(added ? Theme.inkSoft : Theme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(added ? Theme.surfaceLow : Theme.ink))
            }
            .disabled(added)
        }
        .padding(10)
        .frame(width: 150, height: 180)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.divider, lineWidth: 1))
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(L("Bir şeyler yaz…"), text: $vm.input, axis: .vertical)
                .font(Theme.Typo.body)
                .lineLimit(1...5)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.surfaceLow))

            Button {
                Haptics.light()
                inputFocused = false   // klavyeyi kapat → yanıt + öneri kartları görünür olsun
                Task { await vm.send() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(canSend ? Theme.ink : Theme.inkMute))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.canvas)
    }

    private var canSend: Bool {
        !vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !vm.isSending
    }

    /// Taslakta en az 1 adım varken kaydedilebilir. ready_to_commit yalnızca yumuşak
    /// bir sinyal (model nadiren true yapıyor) — kaydı bloklamaz.
    private var canCommit: Bool {
        !vm.draft.steps.isEmpty && !didCommit
    }

    private func productName(_ p: UserProductResponse?) -> String {
        guard let p else { return L("Ürün") }
        let parts = [p.brand, p.name].compactMap { $0 }.joined(separator: " ")
        return parts.isEmpty ? (p.nickname ?? L("Ürün")) : parts
    }
}

// MARK: - Bubble

private struct ChatBubble: View {
    let message: ChatMessageDTO

    var body: some View {
        switch message.role {
        case "user":
            HStack {
                Spacer(minLength: 40)
                bubbleText(message.content ?? "", fg: Theme.onAccent, bg: Theme.ink)
            }
        case "assistant":
            HStack {
                bubbleText(message.content ?? "", fg: Theme.ink, bg: Theme.surface)
                Spacer(minLength: 40)
            }
        default: // system
            HStack {
                Spacer()
                Text(message.content ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.surfaceLow))
                Spacer()
            }
        }
    }

    private func bubbleText(_ text: String, fg: Color, bg: Color) -> some View {
        Text(text)
            .font(Theme.Typo.body)
            .foregroundStyle(fg)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(bg))
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Typing indicator

private struct TypingIndicator: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle().fill(Theme.inkMute)
                        .frame(width: 7, height: 7)
                        .opacity(phase == i ? 1 : 0.35)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
            Spacer(minLength: 40)
        }
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
    }
}
