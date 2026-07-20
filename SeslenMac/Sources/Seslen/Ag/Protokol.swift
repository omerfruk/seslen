import Foundation

/// WebSocket mesaj tipleri.
/// Sunucudaki `internal/protokol/protokol.go` ile birebir eşleşir;
/// biri değişince diğeri de değişmelidir.
enum MesajTipi: String, Codable, Sendable {
    // İstemci → Sunucu
    case seslen
    case yanitla
    case durumBildir = "durum_bildir"
    case uyeGuncelle = "uye_guncelle"
    case uyeOnayla = "uye_onayla"
    case uyeSil = "uye_sil"
    case kodYenile = "kod_yenile"
    case nabiz

    // Sunucu → İstemci
    case durumTam = "durum_tam"
    case seslenmeGeldi = "seslenme_geldi"
    case yanitGeldi = "yanit_geldi"
    case hata
    case nabizYanit = "nabiz_yanit"
}

// MARK: - Giden gövdeler

struct SeslenIstek: Encodable, Sendable {
    var aliciID: String
    var seviye: Seviye
    var not: String
}

struct YanitlaIstek: Encodable, Sendable {
    var cagriID: String
    var yanit: Yanit
}

struct DurumBildirIstek: Encodable, Sendable {
    var durum: Durum
}

struct UyeGuncelleIstek: Encodable, Sendable {
    var uyeID: String
    var rol: Rol
    var maxSeviye: Seviye
}

struct UyeIDIstek: Encodable, Sendable {
    var uyeID: String
}

/// Gövdesiz mesajlar için yer tutucu.
struct BosGovde: Encodable, Sendable {}

// MARK: - Gelen gövdeler

struct DurumTamVeri: Decodable, Sendable {
    var kurum: Kurum
    var ben: Uye
    var uyeler: [Uye]
    var bekleyen: [Uye]

    enum CodingKeys: String, CodingKey { case kurum, ben, uyeler, bekleyen }

    init(from decoder: any Decoder) throws {
        let k = try decoder.container(keyedBy: CodingKeys.self)
        kurum = try k.decode(Kurum.self, forKey: .kurum)
        ben = try k.decode(Uye.self, forKey: .ben)
        uyeler = try k.decodeIfPresent([Uye].self, forKey: .uyeler) ?? []
        bekleyen = try k.decodeIfPresent([Uye].self, forKey: .bekleyen) ?? []
    }
}

struct SeslenmeGeldiVeri: Decodable, Sendable {
    var cagriID: String
    var gonderenID: String
    var gonderenAd: String
    var seviye: Seviye
    var not: String
    var gonderildi: Int
}

struct YanitGeldiVeri: Decodable, Sendable {
    var cagriID: String
    var aliciID: String
    var aliciAd: String
    var yanit: Yanit
    var yanitTarih: Int
}

struct HataVeri: Decodable, Sendable {
    var kod: String
    var mesaj: String
}

// MARK: - Zarf

/// Gelen mesajın dış kabuğu. `tip` okunur, gövde sonra istenen türe çözülür.
struct GelenZarf: Decodable {
    let tip: MesajTipi
    private let kap: KeyedDecodingContainer<CodingKeys>

    enum CodingKeys: String, CodingKey { case tip, veri }

    init(from decoder: any Decoder) throws {
        kap = try decoder.container(keyedBy: CodingKeys.self)
        tip = try kap.decode(MesajTipi.self, forKey: .tip)
    }

    /// Gövdeyi istenen türe çözer.
    func veri<T: Decodable>(_ tur: T.Type) throws -> T {
        try kap.decode(T.self, forKey: .veri)
    }
}

/// Giden mesajın dış kabuğu.
struct GidenZarf<Govde: Encodable>: Encodable {
    let tip: MesajTipi
    let veri: Govde?
}

// MARK: - JSON kodlayıcılar

/// RFC3339 tarihlerini çözer. Go tarafı kesirli saniyeyi bazen yazar bazen yazmaz,
/// bu yüzden iki biçim de denenir.
///
/// `ISO8601DateFormatter` yalnızca okuma için iş parçacığı güvenlidir; biçim
/// seçenekleri kurulumdan sonra hiç değişmediği için `@unchecked Sendable` güvenlidir.
private final class TarihCozucu: @unchecked Sendable {
    static let ortak = TarihCozucu()

    private let kesirli: ISO8601DateFormatter
    private let sade: ISO8601DateFormatter

    private init() {
        kesirli = ISO8601DateFormatter()
        kesirli.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        sade = ISO8601DateFormatter()
        sade.formatOptions = [.withInternetDateTime]
    }

    func coz(_ metin: String) -> Date? {
        kesirli.date(from: metin) ?? sade.date(from: metin)
    }
}

enum JSONAraci {
    static let cozucu: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let metin = try decoder.singleValueContainer().decode(String.self)
            guard let tarih = TarihCozucu.ortak.coz(metin) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "tarih çözümlenemedi: \(metin)")
                )
            }
            return tarih
        }
        return d
    }()

    static let kodlayici = JSONEncoder()
}
