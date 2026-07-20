import Foundation
import SwiftUI

/// Seslenmenin aciliyet seviyesi. Sunucudaki `model.Seviye` ile birebir eşleşir.
enum Seviye: String, Codable, CaseIterable, Sendable {
    case normal
    case onemli
    case acil

    var baslik: String {
        switch self {
        case .normal: "Normal"
        case .onemli: "Önemli"
        case .acil: "ACİL"
        }
    }

    var simge: String {
        switch self {
        case .normal: "bubble.left.fill"
        case .onemli: "exclamationmark.triangle.fill"
        case .acil: "exclamationmark.octagon.fill"
        }
    }

    /// Seviyenin arayüz boyunca kullanılan rengi. `simge` gibi bu da sunucuda
    /// karşılığı olmayan, yalnızca gösterime ait bir bilgidir.
    var renk: Color {
        switch self {
        case .normal: .blue
        case .onemli: .orange
        case .acil: .red
        }
    }

    var aciklama: String {
        switch self {
        case .normal: "Hafif uyarı — menü çubuğu ve bildirim"
        case .onemli: "Ekranda panel ve ses"
        case .acil: "Tam ekran uyarı, ses ve kenar flaşı"
        }
    }

    /// Seviyelerin birbirine göre ağırlığı; yetki karşılaştırması için.
    private var agirlik: Int {
        switch self {
        case .normal: 1
        case .onemli: 2
        case .acil: 3
        }
    }

    /// Bu seviyenin verilen seviyeyi göndermeye yetip yetmediğini söyler.
    func kapsar(_ diger: Seviye) -> Bool { agirlik >= diger.agirlik }
}

/// Üyenin kurum içindeki rolü.
enum Rol: String, Codable, Sendable {
    case kurucu
    case yonetici
    case uye

    var baslik: String {
        switch self {
        case .kurucu: "Kurucu"
        case .yonetici: "Yönetici"
        case .uye: "Üye"
        }
    }

    var yonetimYetkisi: Bool { self == .kurucu || self == .yonetici }
}

/// Üyenin müsaitlik durumu.
enum Durum: String, Codable, CaseIterable, Sendable {
    case musait
    case mesgul
    case cevrimdisi

    var baslik: String {
        switch self {
        case .musait: "Müsait"
        case .mesgul: "Meşgul"
        case .cevrimdisi: "Çevrimdışı"
        }
    }

    /// Kullanıcının kendi seçebileceği durumlar. Çevrimdışı bağlantıdan türetilir,
    /// elle seçilemez.
    static var secilebilir: [Durum] { [.musait, .mesgul] }
}

/// Birlikte çalışan ekip.
struct Kurum: Codable, Sendable, Identifiable {
    var id: String
    var ad: String
    /// Yalnızca yöneticilere gönderilir; diğerlerinde boş gelir.
    var katilimKodu: String
    var olusturuldu: Date

    enum CodingKeys: String, CodingKey {
        case id, ad, katilimKodu, olusturuldu
    }

    init(from decoder: any Decoder) throws {
        let k = try decoder.container(keyedBy: CodingKeys.self)
        id = try k.decode(String.self, forKey: .id)
        ad = try k.decode(String.self, forKey: .ad)
        katilimKodu = try k.decodeIfPresent(String.self, forKey: .katilimKodu) ?? ""
        olusturuldu = try k.decodeIfPresent(Date.self, forKey: .olusturuldu) ?? .distantPast
    }

    init(id: String = "", ad: String = "", katilimKodu: String = "", olusturuldu: Date = .distantPast) {
        self.id = id
        self.ad = ad
        self.katilimKodu = katilimKodu
        self.olusturuldu = olusturuldu
    }
}

/// Kuruma bağlı bir kullanıcı.
struct Uye: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var adSoyad: String
    var rol: Rol
    var maxSeviye: Seviye
    var onayli: Bool
    var durum: Durum
    var sonGorulme: Date
    var cevrimici: Bool

    enum CodingKeys: String, CodingKey {
        case id, adSoyad, rol, maxSeviye, onayli, durum, sonGorulme, cevrimici
    }

    init(from decoder: any Decoder) throws {
        let k = try decoder.container(keyedBy: CodingKeys.self)
        id = try k.decode(String.self, forKey: .id)
        adSoyad = try k.decode(String.self, forKey: .adSoyad)
        rol = try k.decodeIfPresent(Rol.self, forKey: .rol) ?? .uye
        maxSeviye = try k.decodeIfPresent(Seviye.self, forKey: .maxSeviye) ?? .normal
        onayli = try k.decodeIfPresent(Bool.self, forKey: .onayli) ?? false
        durum = try k.decodeIfPresent(Durum.self, forKey: .durum) ?? .cevrimdisi
        sonGorulme = try k.decodeIfPresent(Date.self, forKey: .sonGorulme) ?? .distantPast
        cevrimici = try k.decodeIfPresent(Bool.self, forKey: .cevrimici) ?? false
    }

    init(
        id: String, adSoyad: String, rol: Rol = .uye, maxSeviye: Seviye = .normal,
        onayli: Bool = false, durum: Durum = .cevrimdisi,
        sonGorulme: Date = .distantPast, cevrimici: Bool = false
    ) {
        self.id = id
        self.adSoyad = adSoyad
        self.rol = rol
        self.maxSeviye = maxSeviye
        self.onayli = onayli
        self.durum = durum
        self.sonGorulme = sonGorulme
        self.cevrimici = cevrimici
    }

    /// Listede gösterilecek etkin durum: bağlı değilse her zaman çevrimdışı.
    var etkinDurum: Durum { cevrimici ? durum : .cevrimdisi }

    /// Ad ve soyadın baş harfleri; avatar için.
    var basHarfler: String {
        let parcalar = adSoyad.split(separator: " ").prefix(2)
        return parcalar.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

/// Gelen bir seslenme. Uygulama içinde uyarı göstermek için kullanılır.
struct Seslenme: Identifiable, Sendable, Equatable {
    var id: String
    var gonderenID: String
    var gonderenAd: String
    var seviye: Seviye
    var not: String
    var geldiginde: Date
    /// Kurumdaki herkese giden bir yayın mı? Uyarı metni buna göre değişir.
    var yayin: Bool = false
}

/// Alıcının çağrıya verebileceği hazır cevaplar.
enum Yanit: String, Codable, Sendable, CaseIterable {
    case geliyorum
    case bekle
    case gordum

    var baslik: String {
        switch self {
        case .geliyorum: "Geliyorum"
        case .bekle: "2 dk sonra"
        case .gordum: "Gördüm"
        }
    }

    var simge: String {
        switch self {
        case .geliyorum: "figure.walk"
        case .bekle: "clock"
        case .gordum: "eye"
        }
    }
}
