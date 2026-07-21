import Foundation

/// WebSocket mesaj tipleri.
/// Sunucudaki `internal/protokol/protokol.go` ile birebir eşleşir;
/// biri değişince diğeri de değişmelidir.
enum MesajTipi: String, Codable, Sendable {
    // İstemci → Sunucu
    case seslen
    case haykir
    case yanitla
    case durumBildir = "durum_bildir"
    case uyeGuncelle = "uye_guncelle"
    case uyeOnayla = "uye_onayla"
    case uyeSil = "uye_sil"
    case kodYenile = "kod_yenile"
    case anket
    case anketOy = "anket_oy"
    case anketBitir = "anket_bitir"
    case nabiz

    // Sunucu → İstemci
    case durumTam = "durum_tam"
    case seslenmeGeldi = "seslenme_geldi"
    case kacirilanlar
    case yanitGeldi = "yanit_geldi"
    case bilgi
    case hata
    case anketGeldi = "anket_geldi"
    case anketSonuc = "anket_sonuc"
    case acikAnketler = "acik_anketler"
    case nabizYanit = "nabiz_yanit"
}

// MARK: - Giden gövdeler

struct SeslenIstek: Encodable, Sendable {
    var aliciID: String
    var seviye: Seviye
    var not: String
}

/// Seviye taşımaz: yayın her zaman normal seviyede gider.
struct HaykirIstek: Encodable, Sendable {
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

/// Kuruma sorulan çoktan seçmeli soru. Seviye taşımaz: anket kesmez.
struct AnketIstek: Encodable, Sendable {
    var soru: String
    var secenekler: [String]
}

/// Ankete verilen oy. Seçenek metinle değil dizinle taşınır: serbest metni
/// eşleştirmek boşluk/harf normalleştirmesi ve tekrar sorunu getirirdi.
struct AnketOyIstek: Encodable, Sendable {
    var anketID: String
    var secenek: Int
}

struct AnketIDIstek: Encodable, Sendable {
    var anketID: String
}

/// Gövdesiz mesajlar için yer tutucu.
struct BosGovde: Encodable, Sendable {}

// MARK: - Gelen gövdeler

struct DurumTamVeri: Decodable, Sendable {
    var kurum: Kurum
    var ben: Uye
    var uyeler: [Uye]
    var bekleyen: [Uye]
    /// Biz meşgulken kuyruğa alınmış çağrı sayısı. Meşgul, geri bildirimi olmayan
    /// bir kuyuya dönüşmemeli: kullanıcı kaç kişinin seslendiğini görüp müsaite
    /// dönmeye kendi karar verebilmeli.
    var bekleyenCagri: Int

    enum CodingKeys: String, CodingKey { case kurum, ben, uyeler, bekleyen, bekleyenCagri }

    init(from decoder: any Decoder) throws {
        let k = try decoder.container(keyedBy: CodingKeys.self)
        kurum = try k.decode(Kurum.self, forKey: .kurum)
        ben = try k.decode(Uye.self, forKey: .ben)
        uyeler = try k.decodeIfPresent([Uye].self, forKey: .uyeler) ?? []
        bekleyen = try k.decodeIfPresent([Uye].self, forKey: .bekleyen) ?? []
        bekleyenCagri = try k.decodeIfPresent(Int.self, forKey: .bekleyenCagri) ?? 0
    }
}

struct SeslenmeGeldiVeri: Decodable, Sendable {
    var cagriID: String
    var gonderenID: String
    var gonderenAd: String
    var seviye: Seviye
    var not: String
    var gonderildi: Int
    /// Çağrı tek kişiye değil kurumdaki herkese gitti mi?
    var yayin: Bool

    enum CodingKeys: String, CodingKey {
        case cagriID, gonderenID, gonderenAd, seviye, not, gonderildi, yayin
    }

    init(from decoder: any Decoder) throws {
        let k = try decoder.container(keyedBy: CodingKeys.self)
        cagriID = try k.decode(String.self, forKey: .cagriID)
        gonderenID = try k.decode(String.self, forKey: .gonderenID)
        gonderenAd = try k.decode(String.self, forKey: .gonderenAd)
        seviye = try k.decode(Seviye.self, forKey: .seviye)
        not = try k.decode(String.self, forKey: .not)
        gonderildi = try k.decode(Int.self, forKey: .gonderildi)
        // Eski sunucu bu alanı hiç göndermez; alanın yokluğu "yayın değil" demektir.
        yayin = try k.decodeIfPresent(Bool.self, forKey: .yayin) ?? false
    }
}

/// Üyeye ulaştırılamamış çağrılar. Tek mesajda gelir ki bilgisayarını açan
/// kullanıcının ekranına arka arkaya paneller yağmasın.
struct KacirilanlarVeri: Decodable, Sendable {
    var cagrilar: [SeslenmeGeldiVeri]
    /// Çağrıların neden biriktiği. Başlık buna göre yazılır: "Sen yokken" ile
    /// "Meşguldeyken" farklı şeylerdir ve ikincisine "yoktun" demek yanıltır.
    var sebep: KacirilmaSebebi

    enum CodingKeys: String, CodingKey { case cagrilar, sebep }

    init(from decoder: any Decoder) throws {
        let k = try decoder.container(keyedBy: CodingKeys.self)
        cagrilar = try k.decodeIfPresent([SeslenmeGeldiVeri].self, forKey: .cagrilar) ?? []
        // Eski sunucu bu alanı hiç göndermez; o sürümde tek sebep çevrimdışılıktı.
        sebep = try k.decodeIfPresent(KacirilmaSebebi.self, forKey: .sebep) ?? .cevrimdisi
    }
}

/// Çağrının alıcıya anında ulaşamama sebebi.
enum KacirilmaSebebi: String, Decodable, Sendable {
    case cevrimdisi
    case mesgul

    var baslik: String {
        switch self {
        case .cevrimdisi: "Sen yokken"
        case .mesgul: "Meşguldeyken"
        }
    }

    var rozet: String {
        switch self {
        case .cevrimdisi: "KAÇIRILDI"
        case .mesgul: "MEŞGULDÜN"
        }
    }
}

/// Yeni açılan anketin duyurusu. Uyarıyı tetikleyen **olay** budur;
/// sonrasındaki her güncelleme `AnketSonucVeri` ile gelir.
struct AnketGeldiVeri: Decodable, Sendable {
    var anketID: String
    var gonderenID: String
    var gonderenAd: String
    var soru: String
    var secenekler: [String]
    var gonderildi: Int
    var bitis: Int
}

/// Tek bir oy, sahibiyle birlikte.
struct AnketOycusu: Decodable, Sendable, Equatable {
    var uyeID: String
    var adSoyad: String
    var secenek: Int
}

/// Anketin o anki **durumu**; her oyda yeniden yayınlanır.
struct AnketSonucVeri: Decodable, Sendable {
    var anketID: String
    var gonderenID: String
    var gonderenAd: String
    var soru: String
    var secenekler: [String]
    var sayimlar: [Int]
    /// Kimin neye oy verdiği. Anket gizli oylama değildir.
    var oylayanlar: [AnketOycusu]
    var katilan: Int
    var beklenen: Int
    /// Oy verilmemişse -1.
    var benimOyum: Int
    var kapandi: Bool
    var bitis: Int

    enum CodingKeys: String, CodingKey {
        case anketID, gonderenID, gonderenAd, soru, secenekler
        case sayimlar, oylayanlar, katilan, beklenen, benimOyum, kapandi, bitis
    }

    init(from decoder: any Decoder) throws {
        let k = try decoder.container(keyedBy: CodingKeys.self)
        anketID = try k.decode(String.self, forKey: .anketID)
        gonderenID = try k.decode(String.self, forKey: .gonderenID)
        gonderenAd = try k.decode(String.self, forKey: .gonderenAd)
        soru = try k.decode(String.self, forKey: .soru)
        secenekler = try k.decodeIfPresent([String].self, forKey: .secenekler) ?? []
        sayimlar = try k.decodeIfPresent([Int].self, forKey: .sayimlar) ?? []
        oylayanlar = try k.decodeIfPresent([AnketOycusu].self, forKey: .oylayanlar) ?? []
        katilan = try k.decodeIfPresent(Int.self, forKey: .katilan) ?? 0
        beklenen = try k.decodeIfPresent(Int.self, forKey: .beklenen) ?? 0
        benimOyum = try k.decodeIfPresent(Int.self, forKey: .benimOyum) ?? -1
        kapandi = try k.decodeIfPresent(Bool.self, forKey: .kapandi) ?? false
        bitis = try k.decodeIfPresent(Int.self, forKey: .bitis) ?? 0
    }
}

/// Bağlanınca gelen, hâlâ açık anketler.
///
/// Bu kaçırılanların anket karşılığı DEĞİLDİR: kuyruk geçmiş bir olayı tekrar
/// oynatır, bu ise şu anda hâlâ doğru olan bir durumu bildirir.
struct AcikAnketlerVeri: Decodable, Sendable {
    var anketler: [AnketSonucVeri]

    enum CodingKeys: String, CodingKey { case anketler }

    init(from decoder: any Decoder) throws {
        let k = try decoder.container(keyedBy: CodingKeys.self)
        anketler = try k.decodeIfPresent([AnketSonucVeri].self, forKey: .anketler) ?? []
    }
}

/// Reddedilmemiş ama kullanıcıya söylenmesi gereken bir durum.
struct BilgiVeri: Decodable, Sendable {
    var mesaj: String
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
