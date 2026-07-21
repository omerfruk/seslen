import Foundation
import SwiftUI

/// Seslenmenin aciliyet seviyesi. Sunucudaki `model.Seviye` ile birebir eşleşir.
enum Seviye: String, Codable, CaseIterable, Sendable, Comparable {
    case normal
    case onemli
    case acil
    /// Yanıtsız kalan ACİL çağrıların üstündeki son basamak. Alıcının ekranında
    /// yanıtlanana kadar kapanmayan, geri sayan ve çalmayı sürdüren uyarı açar.
    case taciz

    var baslik: String {
        switch self {
        case .normal: "Normal"
        case .onemli: "Önemli"
        case .acil: "ACİL"
        case .taciz: "TACİZ"
        }
    }

    var simge: String {
        switch self {
        case .normal: "bubble.left.fill"
        case .onemli: "exclamationmark.triangle.fill"
        case .acil: "exclamationmark.octagon.fill"
        case .taciz: "bell.and.waves.left.and.right.fill"
        }
    }

    /// Seviyenin arayüz boyunca kullanılan rengi. `simge` gibi bu da sunucuda
    /// karşılığı olmayan, yalnızca gösterime ait bir bilgidir.
    var renk: Color {
        switch self {
        case .normal: .blue
        case .onemli: .orange
        case .acil: .red
        // Kırmızı ACİL'in, mor da yayının; taciz ikisiyle karışmamalı.
        case .taciz: Color(red: 0.85, green: 0.09, blue: 0.45)
        }
    }

    var aciklama: String {
        switch self {
        case .normal: "Hafif uyarı — menü çubuğu ve bildirim"
        case .onemli: "Ekranda panel ve ses"
        case .acil: "Tam ekran uyarı, ses ve kenar flaşı"
        case .taciz: "Yanıtlanana kadar kapanmayan tam ekran alarm"
        }
    }

    /// Alıcı meşgulken bu seviye bekletilir mi? Sunucudaki `Seviye.MesguldeBekler`
    /// ile aynı kuralı taşır — burada yalnızca arayüzü doğru yazmak için var,
    /// yaptırım sunucudadır.
    var mesguldeBekler: Bool { self < .acil }

    /// Seviyelerin birbirine göre ağırlığı; yetki karşılaştırması için.
    private var agirlik: Int {
        switch self {
        case .normal: 1
        case .onemli: 2
        case .acil: 3
        case .taciz: 4
        }
    }

    /// Bu seviyenin verilen seviyeyi göndermeye yetip yetmediğini söyler.
    func kapsar(_ diger: Seviye) -> Bool { self >= diger }

    static func < (sol: Seviye, sag: Seviye) -> Bool { sol.agirlik < sag.agirlik }

    /// Tanımadığı seviyeyi hata saymaz.
    ///
    /// Sunucu istemciden yeni bir seviye tanıyabilir (taciz eklendiğinde tam
    /// olarak bu oldu). Çözümlemeyi patlatmak yalnızca o alanı değil, içinde
    /// bulunduğu `durum_tam` mesajının tamamını düşürür; uygulama kimseyi
    /// göremez hale gelir ve sebebi hiçbir yerde görünmez. Bunun yerine
    /// bilinmeyen seviye ACİL sayılır: eksik uyarmaktansa fazla uyarmak yeğdir
    /// ve yetki kararı zaten sunucuda verilir.
    init(from decoder: any Decoder) throws {
        let ham = try decoder.singleValueContainer().decode(String.self)
        self = Seviye(rawValue: ham) ?? .acil
    }
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
    /// Ayar ekranından üretilmiş deneme çağrısı mı? Sunucuda karşılığı yoktur;
    /// yanıtı gönderilirse "çağrı bulunamadı" hatası döner.
    var onizleme: Bool = false
}

/// Panelde birlikte gösterilen, aynı kişiden gelen seslenmeler.
///
/// Arka arkaya gelen çağrılar tek pencerede toplanır: üç ACİL için üç ayrı
/// pencere kapatmak gerekmez ve verilen tek yanıt hepsine birden gider.
struct SeslenmeGrubu: Sendable, Equatable {
    var gonderenAd: String
    var seviye: Seviye
    var not: String
    var yayin: Bool
    /// Gruptaki çağrı sayısı; birden fazlaysa panelde belirtilir.
    var adet: Int

    /// Boş listeden grup kurulamaz; panelin her zaman gösterecek bir şeyi olur.
    init?(_ seslenmeler: [Seslenme]) {
        guard let sonuncu = seslenmeler.last else { return nil }
        gonderenAd = sonuncu.gonderenAd
        yayin = sonuncu.yayin
        adet = seslenmeler.count
        // Panelin rengini ve şiddetini gruptaki en yüksek seviye belirler:
        // araya bir ACİL karışmışsa pencere ACİL görünmelidir.
        seviye = seslenmeler.map(\.seviye).max() ?? sonuncu.seviye
        // Son çağrının notu boş olabilir; o zaman not yazan en son çağrıya düşülür,
        // yoksa kullanıcının yazdığı açıklama sırf ardına boş bir çağrı geldi diye kaybolur.
        not = seslenmeler.last { !$0.not.isEmpty }?.not ?? ""
    }
}

/// Balonda gösterilen tek satırlık bildirim.
///
/// Hem gelen seslenmeler hem de gönderdiğimiz çağrılara dönen yanıtlar aynı
/// balonu kullanır; balon bu yüzden `Seslenme`'ye değil bu tipe bağlıdır.
struct BalonOgesi: Identifiable, Sendable, Equatable {
    var id: String
    var baslik: String
    var altSatir: String
    var simge: String
    var renk: Color
    /// Başlığın yanındaki küçük etiket ("HERKESE" gibi). Boşsa çizilmez.
    var rozet: String = ""
    /// Balonun alt kısmında ne çizileceği. Varsayılanlı olduğu için mevcut
    /// kurulum yerlerinin hiçbiri değişmek zorunda değil.
    var icerik: BalonIcerigi = .okundu
}

/// Balonun kapanma yolu.
enum BalonIcerigi: Sendable, Equatable {
    /// Tek "Okudum" düğmesi.
    case okundu
    /// Anket seçenekleri; oy verilince balon kapanır.
    case anket(anketID: String, secenekler: [String])
}

extension BalonOgesi {
    /// Gelen anketin balonu. Oy düğmeleri "Okudum"un yerini alır.
    static func anket(_ veri: AnketGeldiVeri) -> BalonOgesi {
        BalonOgesi(
            id: "anket-\(veri.anketID)",
            baslik: veri.gonderenAd,
            altSatir: veri.soru,
            simge: "checklist",
            renk: .teal,
            rozet: "ANKET",
            icerik: .anket(anketID: veri.anketID, secenekler: veri.secenekler)
        )
    }

}

/// Kuruma sorulmuş çoktan seçmeli soru ve güncel sonucu.
struct Anket: Identifiable, Sendable, Equatable {
    var id: String
    var gonderenID: String
    var gonderenAd: String
    var soru: String
    var secenekler: [String]
    var sayimlar: [Int]
    var oylayanlar: [AnketOycusu]
    var katilan: Int
    var beklenen: Int
    /// Oy verilmemişse nil.
    var benimOyum: Int?
    var kapandi: Bool
    var bitis: Date

    init(_ veri: AnketSonucVeri) {
        id = veri.anketID
        gonderenID = veri.gonderenID
        gonderenAd = veri.gonderenAd
        soru = veri.soru
        secenekler = veri.secenekler
        sayimlar = veri.sayimlar
        oylayanlar = veri.oylayanlar
        katilan = veri.katilan
        beklenen = veri.beklenen
        benimOyum = veri.benimOyum >= 0 ? veri.benimOyum : nil
        kapandi = veri.kapandi
        bitis = Date(timeIntervalSince1970: TimeInterval(veri.bitis))
    }

    /// Ankete hâlâ oy verilebilir mi? Sunucudaki `Anket.Acik` ile aynı kural.
    var acik: Bool { !kapandi && Date() < bitis }

    var bekleyen: Int { max(beklenen - katilan, 0) }

    /// Bu seçeneğe oy verenlerin adları.
    func oyVerenler(_ dizin: Int) -> [String] {
        oylayanlar.filter { $0.secenek == dizin }.map(\.adSoyad)
    }

    /// En çok oyu alan seçeneğin dizini. Berabere ise nil — "kazanan" demek
    /// yanıltıcı olurdu.
    var kazanan: Int? {
        guard let enYuksek = sayimlar.max(), enYuksek > 0 else { return nil }
        let kazananlar = sayimlar.indices.filter { sayimlar[$0] == enYuksek }
        return kazananlar.count == 1 ? kazananlar[0] : nil
    }

    /// Çubuğun dolduracağı oran. Toplam oya değil en yüksek sayıma göre
    /// ölçeklenir; yoksa üç seçenekli bir ankette kazanan bile üçte bir dolar.
    func oran(_ dizin: Int) -> Double {
        guard let enYuksek = sayimlar.max(), enYuksek > 0,
              sayimlar.indices.contains(dizin)
        else { return 0 }
        return Double(sayimlar[dizin]) / Double(enYuksek)
    }

    /// Tek satırlık sonuç özeti ("Çay kazandı · 4/7").
    var ozet: String {
        guard let kazanan, secenekler.indices.contains(kazanan) else {
            return katilan == 0 ? "Kimse oy vermedi" : "Berabere · \(katilan)/\(beklenen)"
        }
        return "\(secenekler[kazanan]) kazandı · \(sayimlar[kazanan])/\(beklenen)"
    }
}

extension Seslenme {
    var balon: BalonOgesi {
        BalonOgesi(
            id: id,
            baslik: gonderenAd,
            // Not boş bırakılabildiği için ikinci satır hiçbir zaman boş kalmaz.
            altSatir: not.isEmpty ? (yayin ? "herkese haykırdı" : "sana seslendi") : not,
            simge: yayin ? "megaphone.fill" : seviye.simge,
            // Yayın, seviyesi normal olsa da kendi rengiyle ayrışır.
            renk: yayin ? .purple : seviye.renk,
            rozet: yayin ? "HERKESE" : ""
        )
    }
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

    var renk: Color {
        switch self {
        case .geliyorum: .green
        case .bekle: .orange
        case .gordum: .blue
        }
    }
}

extension BalonOgesi {
    /// Gönderdiğimiz bir çağrıya dönen yanıtı balona çevirir.
    ///
    /// Kimlik çağrı kimliğinden türetilir ama onunla aynı değildir: seslenmenin
    /// kendi balonu hâlâ ekranda olabilir, ikisi birbirini düşürmemeli.
    static func yanit(_ veri: YanitGeldiVeri) -> BalonOgesi {
        BalonOgesi(
            id: "yanit-\(veri.cagriID)",
            baslik: veri.aliciAd,
            altSatir: veri.yanit.baslik,
            simge: veri.yanit.simge,
            renk: veri.yanit.renk,
            rozet: "YANIT"
        )
    }
}
