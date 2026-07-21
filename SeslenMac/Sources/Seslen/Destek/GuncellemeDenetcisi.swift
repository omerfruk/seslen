import AppKit
import Foundation
import Observation

/// Yayımlanmış bir sürümün istemcinin ilgilendiği alanları.
struct Yayim: Sendable, Equatable {
    var surum: String
    /// Sürümün GitHub sayfası; elle kurmak isteyene gösterilir.
    var sayfa: URL
    /// DMG varlığının doğrudan indirme adresi. Yayımda DMG yoksa nil olur ve
    /// kendi kendine güncelleme o sürüm için kapanır.
    var paket: URL?
}

/// Güncelleme denetiminin o anki hali.
enum GuncellemeDurumu: Equatable, Sendable {
    case bilinmiyor
    case denetleniyor
    case guncel
    case yeniSurumVar(Yayim)
    case indiriliyor(oran: Double)
    case kuruluyor
    case hata(String)
}

/// Yeni bir Seslen sürümü çıkmış mı diye bakar ve isteyene kurar.
///
/// Kurulum Sparkle gibi bir çatı olmadan, kabuk düzeyinde yapılır: DMG indirilir,
/// bağlanır, içindeki uygulama çalışan paketin üzerine kopyalanır ve uygulama
/// yeniden açılır. Apple Developer hesabı gerektirmemesinin sebebi budur —
/// imza ad-hoc kaldığı için değişen tek şey diskteki paket.
///
/// **Değiştirmeyi uygulama kendisi yapamaz.** Kendi paketini silmeye çalışan
/// bir süreç, altından zemini çeker: kopyalama yarıda kalırsa geriye ne eski ne
/// yeni uygulama kalır. Bu yüzden iş, uygulamanın kapanmasını bekleyen ayrı bir
/// kabuk betiğine devredilir (`kurulumBetigi`).
@MainActor
@Observable
final class GuncellemeDenetcisi {
    private(set) var durum: GuncellemeDurumu = .bilinmiyor

    /// Kurulu sürüm. Paketlenmemiş halde çalışırken (`swift run`) boştur.
    let kuruluSurum: String

    /// Homebrew ile kuranlar için güncelleme komutu. Kendi kendine güncelleme
    /// çalışmadığında (yazma izni yoksa) gösterilecek yol budur.
    static let brewKomutu = "brew upgrade --cask omerfruk/seslen/seslen"

    private static let surumAdresi = URL(
        string: "https://api.github.com/repos/omerfruk/seslen/releases/latest"
    )!

    private static var oturumYapilandirmasi: URLSessionConfiguration {
        let yapilandirma = URLSessionConfiguration.ephemeral
        yapilandirma.timeoutIntervalForRequest = 12
        // İndirme uzun sürebilir; istek zaman aşımı kaynağa değil, kaynağın
        // sessiz kalmasına bakar. Kaynak veri akıtmayı sürdürdükçe beklenir.
        yapilandirma.timeoutIntervalForResource = 600
        return yapilandirma
    }

    private let oturum = URLSession(configuration: GuncellemeDenetcisi.oturumYapilandirmasi)

    init() {
        kuruluSurum = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// Uygulama kendi paketinin üstüne yazabiliyor mu?
    ///
    /// /Applications altına kurulmuş bir uygulamayı yönetici olmayan kullanıcı
    /// değiştiremez. Bunu indirmeden önce bilmek gerekiyor: 15 MB indirip
    /// sonunda "izin yok" demek, kullanıcının vaktini boşa harcamaktır.
    var kurabilir: Bool {
        guard let paket = Self.paketDizini else { return false }
        return FileManager.default.isWritableFile(atPath: paket.deletingLastPathComponent().path)
    }

    /// Çalışan uygulamanın .app dizini. Geliştirme kipinde nil.
    private static var paketDizini: URL? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        let yol = Bundle.main.bundleURL
        return yol.pathExtension == "app" ? yol : nil
    }

    private struct YayimYaniti: Decodable {
        var tagName: String
        var htmlUrl: String
        var assets: [Varlik]

        struct Varlik: Decodable {
            var name: String
            var browserDownloadUrl: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadUrl = "browser_download_url"
            }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
            case assets
        }
    }

    // MARK: - Denetleme

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

            let yayim = try JSONDecoder().decode(YayimYaniti.self, from: veri)
            let sonSurum = yayim.tagName.hasPrefix("v")
                ? String(yayim.tagName.dropFirst())
                : yayim.tagName

            guard Self.dahaYeni(sonSurum, kuruluSurum), let sayfa = URL(string: yayim.htmlUrl) else {
                durum = .guncel
                return
            }

            let dmg = yayim.assets
                .first { $0.name.lowercased().hasSuffix(".dmg") }
                .flatMap { URL(string: $0.browserDownloadUrl) }

            durum = .yeniSurumVar(Yayim(surum: sonSurum, sayfa: sayfa, paket: dmg))
        } catch {
            durum = .hata("Denetlenemedi: \(error.localizedDescription)")
        }
    }

    // MARK: - Kurulum

    /// Yeni sürümü indirir, kurar ve uygulamayı yeniden başlatır.
    ///
    /// Başarılı olursa geri dönmez: son adımı uygulamayı kapatmaktır.
    func guncelle() async {
        guard case .yeniSurumVar(let yayim) = durum else { return }
        guard let paketAdresi = yayim.paket else {
            durum = .hata("Bu sürümde indirilebilir paket yok — sayfasından kurun")
            return
        }
        guard let hedef = Self.paketDizini, kurabilir else {
            durum = .hata("Uygulama klasörüne yazılamıyor — brew komutuyla güncelleyin")
            return
        }

        do {
            durum = .indiriliyor(oran: 0)
            let dmg = try await indir(paketAdresi)

            durum = .kuruluyor
            let birim = try bagla(dmg)
            do {
                let kaynak = try uygulamayiBul(birim)
                try surumDogrula(kaynak)
                try baslatVeKapat(kaynak: kaynak, hedef: hedef, birim: birim, dmg: dmg)
            } catch {
                // Bağlanmış birim açıkta kalmasın: kurulum başlamadan hata
                // alındığında betik hiç çalışmıyor, temizliği kimse yapmıyor.
                _ = try? kabuk("/usr/bin/hdiutil", ["detach", birim.path, "-quiet", "-force"])
                try? FileManager.default.removeItem(at: dmg)
                throw error
            }
        } catch {
            durum = .hata((error as? GuncellemeHatasi)?.aciklama ?? error.localizedDescription)
        }
    }

    /// DMG'yi geçici dizine indirir; ilerlemeyi `durum` üzerinden bildirir.
    ///
    /// İki yaklaşım ölçülerek elendi. `URLSession.bytes` ilerlemeyi verirdi ama
    /// akışı **bayt bayt** dolaşmak gerekiyor: yerel ağda bile megabayt başına
    /// ~11 saniye, yani 15 MB'lık bir DMG için dakikalar. `download(from:)`
    /// hızlı ama **oturum vekilini hiç çağırmıyor** — kendi iç vekilini
    /// kullanıyor, dolayısıyla ilerleme çubuğu kalıcı olarak sıfırda kalıyordu.
    /// Geriye klasik indirme görevi kaldı: hızı `download`'ın, ilerlemesi
    /// vekilin.
    private func indir(_ adres: URL) async throws -> URL {
        let indirici = Indirici { [weak self] oran in
            Task { @MainActor in
                // Kurulum aşamasına geçildiyse geç gelen ilerleme bildirimi
                // durumu indirmeye geri çekmemeli.
                guard let self, case .indiriliyor = self.durum else { return }
                self.durum = .indiriliyor(oran: oran)
            }
        }
        let indirmeOturumu = URLSession(
            configuration: Self.oturumYapilandirmasi, delegate: indirici, delegateQueue: nil
        )
        // Oturum, geçersiz kılınana kadar vekile güçlü referans tutar.
        defer { indirmeOturumu.finishTasksAndInvalidate() }

        return try await indirici.indir(adres, oturum: indirmeOturumu)
    }

    /// İndirilen paketin kurulu sürümden eski olmadığını doğrular.
    ///
    /// DMG'nin içinden ne çıktığına bakmadan kurmak, yayıma yanlış varlık
    /// yüklendiğinde kullanıcıyı sessizce eski sürüme düşürürdü — üstelik
    /// güncelleme düğmesine bastığı için yükseldiğini sanarak.
    private func surumDogrula(_ uygulama: URL) throws {
        let plist = uygulama.appendingPathComponent("Contents/Info.plist")
        guard let veri = try? Data(contentsOf: plist),
              let sozluk = try? PropertyListSerialization.propertyList(
                  from: veri, format: nil) as? [String: Any],
              let indirilen = sozluk["CFBundleShortVersionString"] as? String
        else {
            throw GuncellemeHatasi.paketteUygulamaYok
        }
        if Self.dahaYeni(kuruluSurum, indirilen) {
            throw GuncellemeHatasi.eskiSurum(indirilen)
        }
    }

    /// DMG'yi bağlar ve bağlandığı dizini döner.
    private func bagla(_ dmg: URL) throws -> URL {
        // -nobrowse: birim Finder'da görünmesin, kullanıcı ortada duran bir
        // diski elle çıkarmaya çalışmasın. -mountrandom: sabit bir yol yerine
        // benzersiz dizin; aynı adlı bir birim zaten bağlıysa çakışmasın.
        // `-noverify` bilerek kullanılmıyor: sağlama denetimi yarım inen ya da
        // bozulmuş bir DMG'yi kurulmadan önce yakalar. Kazandırdığı saniye,
        // bozuk bir uygulamayı yerine koymanın bedelini karşılamaz.
        let cikti = try kabuk("/usr/bin/hdiutil", [
            "attach", dmg.path, "-nobrowse", "-quiet",
            "-mountrandom", NSTemporaryDirectory(),
        ])
        // hdiutil çıktısı sekmeyle ayrılmış sütunlardır; bağlanma noktası son sütun.
        guard let nokta = cikti
            .split(separator: "\n")
            .compactMap({ $0.components(separatedBy: "\t").last?.trimmingCharacters(in: .whitespaces) })
            .last(where: { $0.hasPrefix("/") })
        else {
            throw GuncellemeHatasi.baglanamadi
        }
        return URL(fileURLWithPath: nokta)
    }

    private func uygulamayiBul(_ birim: URL) throws -> URL {
        let icerik = (try? FileManager.default.contentsOfDirectory(
            at: birim, includingPropertiesForKeys: nil
        )) ?? []
        guard let uygulama = icerik.first(where: { $0.pathExtension == "app" }) else {
            throw GuncellemeHatasi.paketteUygulamaYok
        }
        return uygulama
    }

    /// Kurulum betiğini yazar, arka planda başlatır ve uygulamadan çıkar.
    private func baslatVeKapat(kaynak: URL, hedef: URL, birim: URL, dmg: URL) throws {
        let betikYolu = FileManager.default.temporaryDirectory
            .appendingPathComponent("seslen-kur-\(UUID().uuidString).sh")
        try Self.kurulumBetigi.write(to: betikYolu, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: betikYolu.path
        )

        let surec = Process()
        surec.executableURL = URL(fileURLWithPath: "/bin/bash")
        surec.arguments = [
            betikYolu.path,
            hedef.path, kaynak.path, birim.path, dmg.path,
            String(ProcessInfo.processInfo.processIdentifier),
        ]
        try surec.run()

        // Beklemiyoruz: betiğin ilk işi bizim kapanmamızı beklemek.
        NSApp.terminate(nil)
    }

    /// Uygulamanın kapanmasını bekleyip paketi değiştiren betik.
    ///
    /// Eski paket silinmez, yeniden adlandırılır: kopyalama yarıda kalırsa geri
    /// alınabilecek bir şey kalsın. Kopya `ditto` ile yapılır — `cp -R`,
    /// uygulama paketlerindeki sembolik bağları ve genişletilmiş öznitelikleri
    /// olduğu gibi taşımaz.
    ///
    /// Karantina bayrağı elle silinir; Homebrew cask'ındaki `postflight` ile
    /// aynı gerekçe: imzasız uygulama aksi halde "hasarlı" uyarısıyla açılmaz.
    private static let kurulumBetigi = """
    #!/bin/bash
    hedef="$1"; kaynak="$2"; birim="$3"; dmg="$4"; pid="$5"

    temizle() {
      /usr/bin/hdiutil detach "$birim" -quiet -force 2>/dev/null
      /bin/rm -f "$dmg"
      /bin/rm -f "$0"
    }

    # Uygulama kapanana kadar bekle; en fazla 20 saniye.
    for _ in $(seq 1 200); do
      /bin/kill -0 "$pid" 2>/dev/null || break
      /bin/sleep 0.1
    done

    yedek="$hedef.guncelleme-yedegi"
    /bin/rm -rf "$yedek"
    /bin/mv "$hedef" "$yedek" || { temizle; /usr/bin/open "$hedef"; exit 1; }

    if /usr/bin/ditto "$kaynak" "$hedef"; then
      /usr/bin/xattr -dr com.apple.quarantine "$hedef" 2>/dev/null
      /bin/rm -rf "$yedek"
    else
      # Kopya tutmadı: eski sürüme dön. Kullanıcı güncellenmemiş ama çalışan
      # bir uygulamayla kalır; hiç uygulamasız kalmaktan iyidir.
      /bin/rm -rf "$hedef"
      /bin/mv "$yedek" "$hedef"
    fi

    temizle
    /usr/bin/open "$hedef"
    """

    @discardableResult
    private func kabuk(_ yol: String, _ argumanlar: [String]) throws -> String {
        let surec = Process()
        surec.executableURL = URL(fileURLWithPath: yol)
        surec.arguments = argumanlar

        let boru = Pipe()
        surec.standardOutput = boru
        surec.standardError = Pipe()

        try surec.run()
        let cikti = boru.fileHandleForReading.readDataToEndOfFile()
        surec.waitUntilExit()

        guard surec.terminationStatus == 0 else { throw GuncellemeHatasi.baglanamadi }
        return String(data: cikti, encoding: .utf8) ?? ""
    }

    // MARK: - Sürüm karşılaştırma

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

/// İndirmeyi yürüten ve ilerlemesini bildiren oturum vekili.
///
/// Ayrı bir sınıf olması şart: `URLSession` vekilini yalnızca kurulurken alıyor
/// ve `@MainActor` bir tipi oraya veremiyoruz. İlerleme bildirimi ana aktöre
/// `Task` ile atlatılır.
private final class Indirici: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let ilerleme: @Sendable (Double) -> Void

    /// Vekil geri çağrıları kendi kuyruğunda çalışıyor; sürdürücüye iki
    /// yerden birden dokunulabilir.
    private let kilit = NSLock()
    private var surdurucu: CheckedContinuation<URL, any Error>?

    init(ilerleme: @escaping @Sendable (Double) -> Void) {
        self.ilerleme = ilerleme
    }

    func indir(_ adres: URL, oturum: URLSession) async throws -> URL {
        try await withCheckedThrowingContinuation { surdurucu in
            kilit.lock()
            self.surdurucu = surdurucu
            kilit.unlock()
            oturum.downloadTask(with: adres).resume()
        }
    }

    /// Sürdürücüyü tam olarak bir kez devam ettirir.
    ///
    /// Hem `didFinishDownloadingTo` hem `didCompleteWithError` çağrılabiliyor;
    /// ikinci kez `resume` çağırmak çalışma anında çökme demektir.
    private func bitir(_ sonuc: Result<URL, any Error>) {
        kilit.lock()
        let bekleyen = surdurucu
        surdurucu = nil
        kilit.unlock()
        bekleyen?.resume(with: sonuc)
    }

    func urlSession(
        _ oturum: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData: Int64,
        totalBytesWritten yazilan: Int64,
        totalBytesExpectedToWrite beklenen: Int64
    ) {
        // Sunucu uzunluk bildirmediyse (chunked) oran hesaplanamaz; çubuk
        // sıfırda kalır ama indirme sürer.
        guard beklenen > 0 else { return }
        ilerleme(Double(yazilan) / Double(beklenen))
    }

    func urlSession(
        _ oturum: URLSession,
        downloadTask gorev: URLSessionDownloadTask,
        didFinishDownloadingTo konum: URL
    ) {
        // HTTP durumu burada denetlenmeli: 404 gövdesi de "başarıyla" inmiş bir
        // dosyadır ve denetlenmeseydi DMG sanılıp bağlanmaya çalışılırdı.
        guard let http = gorev.response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else {
            bitir(.failure(GuncellemeHatasi.indirilemedi))
            return
        }

        // `konum` bu metot döner dönmez siliniyor; taşımak zorunlu.
        let hedef = FileManager.default.temporaryDirectory
            .appendingPathComponent("Seslen-guncelleme-\(UUID().uuidString).dmg")
        do {
            try FileManager.default.moveItem(at: konum, to: hedef)
            bitir(.success(hedef))
        } catch {
            bitir(.failure(error))
        }
    }

    func urlSession(
        _ oturum: URLSession, task: URLSessionTask, didCompleteWithError hata: (any Error)?
    ) {
        // Hatasız tamamlanma `didFinishDownloadingTo` ile zaten karşılandı;
        // `bitir` ikinci çağrıyı yutar.
        if let hata { bitir(.failure(hata)) }
    }
}

/// Kurulum sırasında çıkabilecek, kullanıcıya anlamlı gelen hatalar.
enum GuncellemeHatasi: Error {
    case indirilemedi
    case baglanamadi
    case paketteUygulamaYok
    case eskiSurum(String)

    var aciklama: String {
        switch self {
        case .indirilemedi: "Paket indirilemedi"
        case .baglanamadi: "İndirilen paket açılamadı"
        case .paketteUygulamaYok: "İndirilen pakette uygulama bulunamadı"
        case .eskiSurum(let gelen): "İndirilen paket daha eski (\(gelen)) — kurulmadı"
        }
    }
}
