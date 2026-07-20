import Foundation
import Observation

/// Bir seslenme geldiğinde hangi uyarı biçimlerinin devreye gireceği.
struct UyariBicimi: Codable, Sendable, Equatable {
    /// Menü çubuğu ikonu yanıp söner + macOS bildirimi.
    var ikon: Bool = true
    /// Ekranda kimden geldiğini yazan panel belirir.
    var panel: Bool = true
    /// Kulaklıktan ses çalar.
    var ses: Bool = true
    /// Ekranın kenarları kırmızı yanıp söner.
    var kenar: Bool = false

    /// Hiçbir uyarı biçimi açık değilse seslenme sessizce kaybolur.
    var sessiz: Bool { !ikon && !panel && !ses && !kenar }

    /// ACİL seviyede kullanılan, her şeyi açan biçim.
    static let hepsi = UyariBicimi(ikon: true, panel: true, ses: true, kenar: true)
}

/// Kullanıcının bu cihazdaki tercihleri. Sunucuda değil, yerelde saklanır.
@Observable
final class Ayarlar {
    /// Ekibin sunucusu. Uygulamaya gömülüdür: kullanıcılar brew ile kurup
    /// hiçbir ayar yapmadan bağlanabilsin diye giriş ekranında sorulmaz.
    /// Geliştirme sırasında Ayarlar → Genel → Gelişmiş altından değiştirilebilir.
    static let varsayilanSunucu = "https://seslen.cidaltime.com"

    var sunucuAdresi: String = Ayarlar.varsayilanSunucu { didSet { kaydet() } }

    /// Kişiye özel ayarı olmayan herkes için geçerli varsayılan.
    var varsayilan: UyariBicimi = UyariBicimi() { didSet { kaydet() } }

    /// Üye kimliğine göre kişiselleştirilmiş uyarı biçimleri.
    var kisisel: [String: UyariBicimi] = [:] { didSet { kaydet() } }

    /// ACİL seviyesi kişisel kısıtlamaları ezsin mi?
    /// Açıkken, sesini kapattığınız kişi bile ACİL gönderirse tüm uyarılar çalışır.
    var acilEzsin: Bool = true { didSet { kaydet() } }

    /// Uyarı sesinin şiddeti (0.0 - 1.0).
    var sesSiddeti: Double = 0.8 { didSet { kaydet() } }

    /// Sistem açılışında Seslen kendiliğinden başlasın mı?
    var acilistaBaslat: Bool = false { didSet { kaydet() } }

    /// Panel kaç saniye sonra kendiliğinden kapansın? (0 = kapanmasın)
    var panelSuresi: Double = 20 { didSet { kaydet() } }

    private var yukleniyor = false

    init() {
        yukle()
    }

    /// Belirli bir gönderen ve seviye için geçerli olacak uyarı biçimini hesaplar.
    func etkinBicim(gonderenID: String, seviye: Seviye) -> UyariBicimi {
        // ACİL, kullanıcının kişisel kısıtlamalarını ezer — aksi halde
        // "acil" seviyesinin bir anlamı kalmaz.
        if seviye == .acil, acilEzsin { return .hepsi }

        var bicim = kisisel[gonderenID] ?? varsayilan

        // Normal seviye kasten hafiftir: panel ve kenar flaşı devreye girmez.
        if seviye == .normal {
            bicim.panel = false
            bicim.kenar = false
        }
        return bicim
    }

    /// Bir kişinin kişisel ayarını döner; tanımlı değilse varsayılanın kopyasını verir.
    func bicim(_ uyeID: String) -> UyariBicimi {
        kisisel[uyeID] ?? varsayilan
    }

    /// Kişisel ayarı kaldırır; kişi tekrar varsayılanı kullanmaya döner.
    func kisiselSifirla(_ uyeID: String) {
        kisisel.removeValue(forKey: uyeID)
    }

    /// WebSocket adresini sunucu adresinden türetir (http→ws, https→wss).
    func websocketURL(token: String) -> URL? {
        guard var parcalar = URLComponents(string: sunucuAdresi.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        switch parcalar.scheme {
        case "https": parcalar.scheme = "wss"
        case "http": parcalar.scheme = "ws"
        case "ws", "wss": break
        default: return nil
        }
        parcalar.path = "/ws"
        parcalar.queryItems = [URLQueryItem(name: "token", value: token)]
        return parcalar.url
    }

    /// HTTP uç adresini kurar.
    func apiURL(_ yol: String) -> URL? {
        URL(string: sunucuAdresi.trimmingCharacters(in: .whitespaces))?.appendingPathComponent(yol)
    }

    // MARK: - Kalıcılık

    private struct Kayit: Codable {
        var sunucuAdresi: String
        var varsayilan: UyariBicimi
        var kisisel: [String: UyariBicimi]
        var acilEzsin: Bool
        var sesSiddeti: Double
        var acilistaBaslat: Bool
        var panelSuresi: Double
        /// Kayıt biçiminin sürümü; geçiş işlemleri için.
        var surum: Int?
    }

    private static let anahtar = "seslen.ayarlar"

    /// Güncel kayıt sürümü. Artırılınca `yukle` içindeki geçiş kuralı işler.
    private static let guncelSurum = 2

    private func kaydet() {
        guard !yukleniyor else { return }
        let kayit = Kayit(
            sunucuAdresi: sunucuAdresi, varsayilan: varsayilan, kisisel: kisisel,
            acilEzsin: acilEzsin, sesSiddeti: sesSiddeti,
            acilistaBaslat: acilistaBaslat, panelSuresi: panelSuresi,
            surum: Self.guncelSurum
        )
        if let veri = try? JSONEncoder().encode(kayit) {
            UserDefaults.standard.set(veri, forKey: Self.anahtar)
        }
    }

    private func yukle() {
        guard let veri = UserDefaults.standard.data(forKey: Self.anahtar),
              let kayit = try? JSONDecoder().decode(Kayit.self, from: veri)
        else { return }

        yukleniyor = true
        // Sürüm 1'de sunucu adresi kullanıcıya soruluyordu ve varsayılanı
        // localhost'tu. Artık gömülü olduğu için o kayıtları güncel adrese
        // taşıyoruz; aksi halde eski kurulumlar localhost'a bağlanmaya çalışır.
        if (kayit.surum ?? 1) < 2 {
            sunucuAdresi = Self.varsayilanSunucu
        } else {
            sunucuAdresi = kayit.sunucuAdresi
        }
        varsayilan = kayit.varsayilan
        kisisel = kayit.kisisel
        acilEzsin = kayit.acilEzsin
        sesSiddeti = kayit.sesSiddeti
        acilistaBaslat = kayit.acilistaBaslat
        panelSuresi = kayit.panelSuresi
        yukleniyor = false

        // Geçiş uygulandıysa yeni sürümle birlikte diske yaz.
        if (kayit.surum ?? 1) < Self.guncelSurum { kaydet() }
    }
}
