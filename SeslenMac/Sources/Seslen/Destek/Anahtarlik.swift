import Foundation
import Security

/// Oturum token'ını macOS Anahtar Zinciri'nde saklar.
/// Token, kullanıcının kimliğidir; UserDefaults gibi düz metin bir yerde tutulmamalı.
enum Anahtarlik {
    private static let servis = "com.omerfruk.seslen"
    private static let hesap = "oturum-token"

    /// Token'ı yazar. Var olan kayıt varsa üzerine yazılır.
    static func tokenYaz(_ token: String) {
        guard let veri = token.data(using: .utf8) else { return }

        let sorgu: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servis,
            kSecAttrAccount as String: hesap,
        ]
        SecItemDelete(sorgu as CFDictionary)

        var ekle = sorgu
        ekle[kSecValueData as String] = veri
        // Cihaz kilitliyken arka planda bağlanmamız gerekmiyor; en dar erişim yeterli.
        ekle[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        SecItemAdd(ekle as CFDictionary, nil)
    }

    /// Saklanan token'ı okur; yoksa nil döner.
    static func tokenOku() -> String? {
        let sorgu: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servis,
            kSecAttrAccount as String: hesap,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var sonuc: CFTypeRef?
        guard SecItemCopyMatching(sorgu as CFDictionary, &sonuc) == errSecSuccess,
              let veri = sonuc as? Data,
              let token = String(data: veri, encoding: .utf8)
        else { return nil }
        return token
    }

    /// Token'ı siler (çıkış yaparken).
    static func tokenSil() {
        let sorgu: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servis,
            kSecAttrAccount as String: hesap,
        ]
        SecItemDelete(sorgu as CFDictionary)
    }
}
