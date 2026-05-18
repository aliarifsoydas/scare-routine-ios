import SwiftUI
import UIKit

/// SCare Routine brand palette — sade, monokrom, warm.
///
/// Camellia ikonunun peach/coral gradient'i karşısında UI bilinçli olarak sessiz tutulur:
/// sadece warm grayscale tonları, vurgu için tek koyu accent. Bu kontrast modern, premium
/// ve görsel olarak rahatsız etmeyen bir kompozisyon yaratır.
enum Theme {

    // MARK: - Yüzeyler — Dusty Rose Palette
    //
    // Düz siyah ink çok klinik hisseder. Bu palet warm pink/peach tonlarında
    // tutar, kozmetik/skincare app'i için doğal: feminen edge + uniseks
    // okuyabilirlik. Camellia ikonunun peach gradient'i ile mükemmel uyum.

    /// Ana sayfa arka planı — sıcak peach off-white
    static let canvas: Color   = .dynamic(light: 0xFFF6F1, dark: 0x1A1212)

    /// Kart, sheet, modal yüzeyi — soft rose-pink
    static let surface: Color  = .dynamic(light: 0xF7E6E0, dark: 0x2A1F1D)

    /// Daha aşağı katman (input bg, soft divider)
    static let surfaceLow: Color = .dynamic(light: 0xEFD6CD, dark: 0x352825)

    /// İncecik ayraç çizgisi
    static let divider: Color = .dynamic(light: 0xE3C6BB, dark: 0x4A3733)

    // MARK: - Metin

    /// Birincil metin/aksiyon — derin bordo (dusty rose'un koyu tonu).
    /// Önceki #8E5A5A çok açıktı — kontrast yetersizdi. Şimdi yüksek kontrast.
    static let ink: Color      = .dynamic(light: 0x4A1F26, dark: 0xF0D8CE)

    /// İkincil metin — orta rose-brown
    static let inkSoft: Color  = .dynamic(light: 0x8A5050, dark: 0xC4A199)

    /// Üçüncül, placeholder, disabled
    static let inkMute: Color  = .dynamic(light: 0xB89090, dark: 0x8A6D67)

    // MARK: - Aksiyon

    /// Birincil aksiyon (CTA, link, seçili) — dusty rose ink
    static let accent: Color = ink

    /// CTA butonu üzerindeki metin/ikon — krem
    static let onAccent: Color = canvas

    // MARK: - Durum (state)

    /// Hata, dikkat — kırmızı-pink
    static let alert: Color = .dynamic(light: 0xB05050, dark: 0xD9756F)

    /// Başarı — sıcak peach accent
    static let success: Color = .dynamic(light: 0xC07857, dark: 0xD9A78F)

    // MARK: - Kart ve buton stilleri (kısayollar)

    static func primaryButtonBackground(_ enabled: Bool = true) -> Color {
        enabled ? accent : surfaceLow
    }
    static func primaryButtonForeground(_ enabled: Bool = true) -> Color {
        enabled ? onAccent : inkMute
    }
}

// MARK: - Tipografi kısayolları

extension Theme {
    enum Typo {
        /// Onboarding başlığı — büyük, anlamlı
        static let title       = Font.system(size: 28, weight: .semibold, design: .default)
        /// Kart başlık
        static let headline    = Font.system(size: 18, weight: .semibold, design: .default)
        /// Gövde metni
        static let body        = Font.system(size: 16, weight: .regular, design: .default)
        /// Açıklama, küçük metin
        static let caption     = Font.system(size: 13, weight: .regular, design: .default)
        /// Buton etiketi
        static let button      = Font.system(size: 16, weight: .semibold, design: .default)
    }

    /// Standart radius
    static let radius: CGFloat = 14
    static let radiusSmall: CGFloat = 10
}

// MARK: - Color util: hex + light/dark dynamic

extension Color {
    /// 0xRRGGBB int'inden Color
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >>  8) & 0xFF) / 255.0
        let b = Double( hex        & 0xFF) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    /// Light + dark variant'tan dinamik Color (UIKit traitCollection ile bağlanır)
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            let r = CGFloat((hex >> 16) & 0xFF) / 255.0
            let g = CGFloat((hex >>  8) & 0xFF) / 255.0
            let b = CGFloat( hex        & 0xFF) / 255.0
            return UIColor(red: r, green: g, blue: b, alpha: 1)
        })
    }
}
