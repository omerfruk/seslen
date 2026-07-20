import Foundation
import Observation

/// Güncelleme denetiminin o anki hali.
enum GuncellemeDurumu: Equatable, Sendable {
    case bilinmiyor
    case denetleniyor
    case guncel
    case yeniSurumVar(surum: String, adres: URL)
    case hata(String)
}

/// Yeni bir Seslen sürümü çıkmış mı diye GitHub Releases'e bakar.
///
/// Uygulama kendini güncelleyemez: otomatik güncelleme (Sparkle gibi) imzalı
/// paket ve Apple Developer hesabı ister, ikisi de yok. Yapabileceği şey
/// kullanıcıya yeni sürümü haber verip kurulum yolunu göstermektir.
@MainActor
@Observable
final class GuncellemeDenetcisi {
    private(set) var durum: GuncellemeDurumu = .bilinmiyor

    /// Kurulu sürüm. Paketlenmemiş halde çalışırken (`swift run`) boştur.
    let kuruluSurum: String

    /// Homebrew ile kuranlar için güncelleme komutu.
    static let brewKomutu = "brew upgrade --cask omerfruk/seslen/seslen"

    private static let surumAdresi = URL(
        string: "https://api.github.com/repos/omerfruk/seslen/releases/latest"
    )!

    private let oturum: URLSession = {
        let yapilandirma = URLSessionConfiguration.ephemeral
        yapilandirma.timeoutIntervalForRequest = 12
        return URLSession(configuration: yapilandirma)
    }()

    init() {
        kuruluSurum = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private struct Yayim: Decodable {
        var tagName: String
        var htmlUrl: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
        }
    }

    /// GitHub'daki son yayımı okuyup kurulu sürümle karşılaştırır.
    func denetle() async {
        guard !kuruluSurum.isEmpty else {
            durum = .hata("Sürüm okunamadı — kurulu sürümde deneyin")
            return
        }

        durum = .denetleniyor
        do {
            var istek = URLRequest(url: Self.surumAdresi)
            istek.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

            let (veri, yanit) = try await oturum.data(for: istek)
            guard let http = yanit as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                durum = .hata("GitHub yanıt vermedi")
                return
            }

            let yayim = try JSONDecoder().decode(Yayim.self, from: veri)
            let sonSurum = yayim.tagName.hasPrefix("v")
                ? String(yayim.tagName.dropFirst())
                : yayim.tagName

            if Self.dahaYeni(sonSurum, kuruluSurum), let adres = URL(string: yayim.htmlUrl) {
                durum = .yeniSurumVar(surum: sonSurum, adres: adres)
            } else {
                durum = .guncel
            }
        } catch {
            durum = .hata("Denetlenemedi: \(error.localizedDescription)")
        }
    }

    /// İki sürüm numarasını parça parça karşılaştırır.
    ///
    /// Metin karşılaştırması yapılamaz: "0.1.10" < "0.1.9" çıkardı ve on
    /// yamadan sonra güncellemeler görünmez olurdu.
    static func dahaYeni(_ aday: String, _ mevcut: String) -> Bool {
        let a = parcala(aday)
        let m = parcala(mevcut)
        for sira in 0..<max(a.count, m.count) {
            let sol = sira < a.count ? a[sira] : 0
            let sag = sira < m.count ? m[sira] : 0
            if sol != sag { return sol > sag }
        }
        return false
    }

    private static func parcala(_ surum: String) -> [Int] {
        surum.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }
}
