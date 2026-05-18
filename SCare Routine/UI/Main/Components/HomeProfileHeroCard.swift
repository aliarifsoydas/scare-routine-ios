import SwiftUI

/// Anasayfa profil özet kartı.
///
/// Profil eksikse "Profilini tamamla" davetkar CTA gösterir.
/// Profil hazırsa cilt tipi + ton özetini gösterir + "Düzenle" CTA.
///
/// Tap edildiğinde haptic feedback verir ve `onTap` callback'ini çağırır;
/// parent view bunu uygun aksiyon ile bağlar (Profile tab'ına geçiş, vb.).
struct HomeProfileHeroCard: View {
    let profile: ProfileData?
    let onTap: () -> Void

    private var isComplete: Bool {
        guard let p = profile else { return false }
        return p.skinType != nil && p.birthDate != nil
    }

    private var skinTypeTR: String? {
        guard let raw = profile?.skinType, let t = SkinType(rawValue: raw) else { return nil }
        return t.displayTR
    }

    private var fitzpatrickTR: String? {
        guard let t = profile?.fitzpatrickType else { return nil }
        switch t {
        case 1: return "Çok açık"
        case 2: return "Açık"
        case 3: return "Açık-orta"
        case 4: return "Orta"
        case 5: return "Koyu"
        case 6: return "Çok koyu"
        default: return nil
        }
    }

    private var ageDisplay: String? {
        guard let bd = profile?.birthDate else { return nil }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        guard let parsed = f.date(from: bd) else { return nil }
        let years = Calendar.current.dateComponents([.year], from: parsed, to: .now).year ?? 0
        return "\(years) yaşında"
    }

    var body: some View {
        Button {
            Haptics.light()
            onTap()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Theme.surface)
                        .frame(width: 48, height: 48)
                    Image(systemName: isComplete ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.plus")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(Theme.ink)
                        .symbolRenderingMode(.hierarchical)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(isComplete ? "Profilin hazır" : "Profilini tamamla")
                        .font(Theme.Typo.headline)
                        .foregroundStyle(Theme.ink)

                    Text(summaryLine)
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkMute)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.canvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 1)
            )
        }
        .buttonStyle(PressedScaleButtonStyle())
        .accessibilityLabel(isComplete ? "Profil hazır" : "Profilini tamamla")
    }

    private var summaryLine: String {
        if isComplete {
            var parts: [String] = []
            if let s = skinTypeTR { parts.append("Cilt: \(s)") }
            if let t = fitzpatrickTR { parts.append("Ton: \(t)") }
            if let a = ageDisplay { parts.append(a) }
            return parts.isEmpty ? "Tüm bilgilerin hazır." : parts.joined(separator: " · ")
        } else {
            return "Sana daha doğru öneriler sunabilmek için cilt tipini ve yaşını ekle."
        }
    }
}
