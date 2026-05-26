import SwiftUI

/// Subtle "bu yanlış ürün mü?" footer link — overlay/banner değil, alt köşede tek satır.
///
/// **Amaç**: Recognition pipeline'ının yanlış eşleştirme yaptığı durumlarda kullanıcının
/// kolayca "bu yanlış" diyebilmesi için göze batmayan bir CTA. Bu sinyal `confirmRecognition`
/// endpoint'ine `correct: false, correctedProductId: ...` ile gider → fine-tune dataset'i
/// için kritik veri toplama.
///
/// **UX**: Underline link tarzı, küçük bir caption + balon ikonu. Footer pozisyonu host
/// view'ın sorumluluğunda — ürün kartının altına veya CTA bar'ın üstüne yerleştirilir.
/// Tek satır high contrast olmayan inkSoft renkte; kullanıcı yanlış tanıma bilmiyorsa
/// gözüne batmaz, biliyorsa hemen bulur.
///
/// **Gizleme koşulu**: Caller `attemptId == nil` olduğunda footer'ı render etmez
/// (confirmRecognition `attemptId` gerektiriyor — yoksa sinyal gönderilemez).
struct WrongMatchFooter: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            Haptics.light()
            onTap()
        }) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.bubble")
                    .font(.system(size: 12, weight: .regular))
                Text(L("Bu doğru ürün değil mi?"))
                    .font(Theme.Typo.caption)
                    .underline()
            }
            .foregroundStyle(Theme.inkSoft)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityLabel(L("Yanlış ürün bildir"))
    }
}

#Preview {
    WrongMatchFooter(onTap: {})
        .padding()
        .background(Theme.canvas)
}
