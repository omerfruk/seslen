import AppKit
import Foundation
import Observation

/// Bağlantının o anki hali.
enum BaglantiDurumu: Equatable, Sendable {
    case kopuk
    case baglaniyor
    case bagli
    case hata(String)

    var baslik: String {
        switch self {
        case .kopuk: "Bağlı değil"
        case .baglaniyor: "Bağlanıyor…"
        case .bagli: "Bağlı"
        case .hata(let mesaj): mesaj
        }
    }

    var iyi: Bool { self == .bagli }
}

/// Sunucuya bağlanırken oluşabilecek hatalar.
enum IstemciHatasi: LocalizedError {
    case adresGecersiz
    case sunucu(String)
    case agErisimi(String)

    var errorDescription: String? {
        switch self {
        case .adresGecersiz:
            "Sunucu adresi geçersiz. Ayarlardan kontrol edin."
        case .sunucu(let mesaj):
            mesaj
        case .agErisimi(let mesaj):
            "Sunucuya ulaşılamadı: \(mesaj)"
        }
    }
}

/// Sunucu ile konuşan tek merkez. Uygulamanın tüm canlı durumu burada tutulur.
@MainActor
@Observable
final class SunucuIstemcisi {
    // MARK: Yayınlanan durum

    private(set) var baglanti: BaglantiDurumu = .kopuk
    private(set) var kurum: Kurum?
    private(set) var ben: Uye?
    private(set) var uyeler: [Uye] = []
    private(set) var bekleyen: [Uye] = []
    /// Biz meşgulken kuyruğa alınmış çağrı sayısı; müsaite dönünce sıfırlanır.
    private(set) var bekleyenCagri: Int = 0
    /// Kurumda görünen anketler. Yalnızca oy verilebilecek durumda olanlar
    /// tutulur: biten anket zaten geçmişte, panelde yer kaplamasının anlamı yok.
    private(set) var anketler: [Anket] = []
    /// Geçmiş ekranı açılınca doldurulur; bitmişler dahil son anketler.
    private(set) var anketGecmisi: [Anket] = []
    /// Geçmiş ekranı açılınca doldurulur; alınan ve gönderilen son seslenmeler.
    private(set) var cagriGecmisi: [GecmisSeslenme] = []
    /// Kullanıcıya gösterilecek son hata mesajı (menüde kısa süre görünür).
    var sonHata: String?
    /// Hata olmayan ama kullanıcının bilmesi gereken son durum (menüde görünür).
    var sonBilgi: String?

    /// Oturum açılmış mı? Token varsa evet.
    var oturumAcik: Bool { token != nil }

    /// Kendimiz hariç, seslenilebilecek kişiler.
    var digerUyeler: [Uye] {
        uyeler.filter { $0.id != ben?.id }
    }

    /// Panelde gösterilecek anketler: yalnızca hâlâ oy verilebilenler.
    ///
    /// Süzme burada da yapılır çünkü sürenin dolması bir sunucu mesajı üretmez;
    /// yalnızca `anketiYerlestir`'e güvenmek, süresi dolan anketin panelde
    /// asılı kalması demek olurdu.
    var acikAnketler: [Anket] {
        anketler.filter(\.acik)
    }

    // MARK: Olay geri çağrıları

    /// Yeni bir seslenme geldiğinde çağrılır.
    var seslenmeGeldi: ((Seslenme) -> Void)?
    /// Bize ulaştırılamamış çağrılar toplu olarak geldiğinde çağrılır: biz
    /// çevrimdışıyken bağlanınca, meşgulken müsaite dönünce.
    var kacirilanlarGeldi: (([Seslenme], KacirilmaSebebi) -> Void)?
    /// Gönderdiğimiz bir çağrıya yanıt geldiğinde çağrılır.
    var yanitGeldi: ((YanitGeldiVeri) -> Void)?
    /// Yeni bir anket açıldığında çağrılır (olay). Yeniden bağlanmada gelen
    /// açık anketler bunu tetiklemez — durum, olay değil.
    var anketGeldi: ((AnketGeldiVeri) -> Void)?

    // MARK: Özel

    /// Kullanıcının X ile kapattığı anketler; geri gelmemeleri için tutulur.
    private var gizlenenAnketler: Set<String> = []

    private let ayarlar: Ayarlar
    private var token: String?
    private var soket: URLSessionWebSocketTask?
    private var baglantiGorevi: Task<Void, Never>?
    private var yenidenDenemeSayisi = 0
    private var kapatiliyor = false
    /// Her bağlantı döngüsünün sıra numarası.
    ///
    /// `baglan()` eskisini iptal edip yenisini başlatır ama `Task.cancel()`
    /// döngüyü o anda durdurmaz: iptal edilen döngü daha sonra uyanıp kendi
    /// temizliğini yapar ve `soket = nil` + `baglanti = .kopuk` yazar. O yazma,
    /// bu arada kurulmuş **yeni ve sağlıklı** bağlantının üstüne biniyordu;
    /// ekranda "Sunucuya bağlı değilsiniz" görünürken listenin güncellenmeye
    /// devam etmesinin sebebi buydu. Artık yalnızca güncel nesil durum yazabilir.
    private var nesil = 0

    private let oturum: URLSession = {
        let yapilandirma = URLSessionConfiguration.default
        yapilandirma.timeoutIntervalForRequest = 15
        yapilandirma.waitsForConnectivity = false
        return URLSession(configuration: yapilandirma)
    }()

    init(ayarlar: Ayarlar) {
        self.ayarlar = ayarlar
        self.token = Anahtarlik.tokenOku()
        uyanmayiIzle()
    }

    /// Mac uykudan uyandığında hemen yeniden bağlanır.
    ///
    /// Uyku sırasında soket çoktan kopmuştur ama üstel geri çekilme yüzünden
    /// bir sonraki deneme 30 saniyeye kadar gecikebilir. Kullanıcı kapağı
    /// açtığında kendisini bekleyen seslenmeleri yarım dakika sonra değil
    /// hemen görmeli.
    private func uyanmayiIzle() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.oturumAcik, !self.kapatiliyor else { return }
                self.yenidenDenemeSayisi = 0
                self.yenidenBaglan()
            }
        }
    }

    // MARK: - Oturum açma

    /// Yeni kurum kurar ve kurucu olarak oturum açar.
    func kurumOlustur(kurumAd: String, kurucuAd: String) async throws {
        let yanit: KimlikYaniti = try await istekGonder(
            yol: "api/kurum/olustur",
            govde: ["kurumAd": kurumAd, "kurucuAd": kurucuAd]
        )
        oturumKur(yanit)
    }

    /// Katılım kodu ile var olan bir kuruma katılır.
    func kurumaKatil(kod: String, adSoyad: String) async throws {
        let yanit: KimlikYaniti = try await istekGonder(
            yol: "api/kurum/katil",
            govde: ["kod": kod, "adSoyad": adSoyad]
        )
        oturumKur(yanit)
    }

    private func oturumKur(_ yanit: KimlikYaniti) {
        token = yanit.token
        Anahtarlik.tokenYaz(yanit.token)
        kurum = yanit.kurum
        ben = yanit.ben
        baglan()
    }

    /// Oturumu kapatır, token'ı siler ve tüm durumu temizler.
    func cikisYap() {
        kopar()
        Anahtarlik.tokenSil()
        token = nil
        kurum = nil
        ben = nil
        uyeler = []
        bekleyen = []
        bekleyenCagri = 0
        anketler = []
        anketGecmisi = []
        cagriGecmisi = []
        gizlenenAnketler = []
    }

    private struct KimlikYaniti: Decodable {
        var token: String
        var kurum: Kurum
        var ben: Uye
    }

    private struct SunucuHatasi: Decodable {
        var hata: String
    }

    /// Sunucuya POST isteği atar ve yanıtı çözer.
    private func istekGonder<T: Decodable>(yol: String, govde: [String: String]) async throws -> T {
        guard let url = ayarlar.apiURL(yol) else { throw IstemciHatasi.adresGecersiz }

        var istek = URLRequest(url: url)
        istek.httpMethod = "POST"
        istek.setValue("application/json", forHTTPHeaderField: "Content-Type")
        istek.httpBody = try JSONEncoder().encode(govde)

        let veri: Data
        let yanit: URLResponse
        do {
            (veri, yanit) = try await oturum.data(for: istek)
        } catch {
            throw IstemciHatasi.agErisimi(error.localizedDescription)
        }

        guard let http = yanit as? HTTPURLResponse else {
            throw IstemciHatasi.agErisimi("beklenmeyen yanıt")
        }
        guard (200..<300).contains(http.statusCode) else {
            let mesaj = (try? JSONAraci.cozucu.decode(SunucuHatasi.self, from: veri))?.hata
                ?? "sunucu hatası (\(http.statusCode))"
            throw IstemciHatasi.sunucu(mesaj)
        }
        return try JSONAraci.cozucu.decode(T.self, from: veri)
    }

    // MARK: - Bağlantı yönetimi

    /// Sunucuya bağlanır; kopması hâlinde kendiliğinden yeniden dener.
    func baglan() {
        guard token != nil else { return }
        kapatiliyor = false
        nesil &+= 1
        let benimNesil = nesil
        baglantiGorevi?.cancel()
        baglantiGorevi = Task { [weak self] in
            await self?.baglantiDongusu(nesil: benimNesil)
        }
    }

    /// Bağlantı yoksa kurar; süren bir deneme varsa ona dokunmaz.
    ///
    /// Menü her açıldığında koşulsuz `baglan()` çağırmak, tam o sırada el
    /// sıkışmakta olan denemeyi iptal edip baştan başlatıyor ve bağlanmayı
    /// kullanıcı bakmaya devam ettikçe geciktiriyordu. Geri çekilme beklemesi
    /// sırasında durum `.hata` olduğu için o hâlde yeniden denemek serbest —
    /// istenen de bu: kullanıcı menüyü açtıysa 30 saniye beklemesin.
    func gerekirseBaglan() {
        guard oturumAcik, !kapatiliyor, baglanti != .baglaniyor else { return }
        baglan()
    }

    /// Bağlantıyı kapatır ve yeniden denemeyi durdurur.
    func kopar() {
        kapatiliyor = true
        nesil &+= 1
        baglantiGorevi?.cancel()
        baglantiGorevi = nil
        soket?.cancel(with: .goingAway, reason: nil)
        soket = nil
        baglanti = .kopuk
    }

    /// Ayarlardan sunucu adresi değişince bağlantıyı tazeler.
    func yenidenBaglan() {
        kopar()
        baglan()
    }

    private func baglantiDongusu(nesil benimNesil: Int) async {
        while !Task.isCancelled && !kapatiliyor && nesil == benimNesil {
            baglanti = .baglaniyor

            guard let token, let url = ayarlar.websocketURL(token: token) else {
                baglanti = .hata("Sunucu adresi geçersiz")
                return
            }

            let soket = oturum.webSocketTask(with: url)
            self.soket = soket
            soket.resume()

            // İlk mesajı başarıyla okuyana kadar bağlantıyı kurulmuş saymıyoruz:
            // sunucu 401 dönerse soket hemen kapanır.
            do {
                try await mesajDongusu(soket, nesil: benimNesil)
            } catch {
                if !kapatiliyor && !Task.isCancelled && nesil == benimNesil {
                    baglanti = .hata(kisaHata(error))
                }
            }

            // Kendi soketimizi her hâlükârda kapatırız ama paylaşılan alana
            // yalnızca güncel nesil dokunur: aksi halde yenisinin soketini
            // silerdik.
            soket.cancel(with: .goingAway, reason: nil)
            if nesil == benimNesil { self.soket = nil }

            if kapatiliyor || Task.isCancelled || nesil != benimNesil { break }

            // Üstel geri çekilme: 1, 2, 4, 8, 16, en fazla 30 saniye.
            yenidenDenemeSayisi = min(yenidenDenemeSayisi + 1, 5)
            let bekleme = min(pow(2.0, Double(yenidenDenemeSayisi - 1)), 30)
            try? await Task.sleep(for: .seconds(bekleme))
        }

        if !kapatiliyor && nesil == benimNesil {
            baglanti = .kopuk
        }
    }

    private func mesajDongusu(_ soket: URLSessionWebSocketTask, nesil benimNesil: Int) async throws {
        while !Task.isCancelled {
            let mesaj = try await soket.receive()

            // Yerimizi yeni bir bağlantı aldıysa okuduğumuzu işlemeyiz: mesaj
            // zaten yeni soketten de gelir, iki kez işlemek uyarıyı iki kez
            // çıkarırdı.
            guard nesil == benimNesil else { return }

            // İlk başarılı mesaj: bağlantı gerçekten kuruldu.
            if baglanti != .bagli {
                baglanti = .bagli
                yenidenDenemeSayisi = 0
            }

            switch mesaj {
            case .string(let metin):
                if let veri = metin.data(using: .utf8) { gelenIsle(veri) }
            case .data(let veri):
                gelenIsle(veri)
            @unknown default:
                break
            }
        }
    }

    private func kisaHata(_ hata: any Error) -> String {
        let ns = hata as NSError
        switch ns.code {
        case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost:
            return "Sunucuya bağlanılamadı"
        case NSURLErrorTimedOut:
            return "Sunucu yanıt vermiyor"
        case NSURLErrorUserAuthenticationRequired, 401:
            return "Oturum geçersiz, tekrar giriş yapın"
        default:
            return "Bağlantı koptu"
        }
    }

    // MARK: - Anket

    /// Kuruma anket sorar.
    func anketGonder(soru: String, secenekler: [String]) {
        yolla(.anket, AnketIstek(soru: soru, secenekler: secenekler))
    }

    /// Ankete oy verir. Aynı ankete tekrar çağrılırsa oy değişir.
    func anketOyVer(anketID: String, secenek: Int) {
        yolla(.anketOy, AnketOyIstek(anketID: anketID, secenek: secenek))
    }

    /// Kendi anketimizi süresi dolmadan kapatır.
    func anketBitir(anketID: String) {
        yolla(.anketBitir, AnketIDIstek(anketID: anketID))
    }

    /// Geçmiş anketleri sunucudan ister.
    ///
    /// Bağlanışta kendiliğinden çekilmez: liste yalnızca kullanıcı geçmiş
    /// ekranını açınca gerekiyor, her oturumda 20 anket indirmenin anlamı yok.
    func anketGecmisiniIste() {
        yolla(.anketGecmisiIste, BosGovde?.none)
    }

    /// Alınan ve gönderilen son seslenmeleri sunucudan ister.
    func cagriGecmisiniIste() {
        yolla(.cagriGecmisiIste, BosGovde?.none)
    }

    /// Anketi panelden kaldırır.
    ///
    /// Yalnızca bu kullanıcının görünümünü etkiler; anket sunucuda durmaya ve
    /// geçmişte görünmeye devam eder. Kimlik ayrıca tutulur ki geç gelen bir
    /// sonuç mesajı kapatılan kartı geri getirmesin.
    func anketiGizle(_ anketID: String) {
        gizlenenAnketler.insert(anketID)
        anketler.removeAll { $0.id == anketID }
    }

    /// Anketi panele yerleştirir veya günceller.
    ///
    /// Biten anket panelde tutulmaz: "zamanı geçti" — kullanıcının onu tek tek
    /// temizlemek zorunda kalması şikayet konusuydu. Sonucu merak eden geçmiş
    /// ekranına bakar.
    private func anketiYerlestir(_ anket: Anket) {
        guard !gizlenenAnketler.contains(anket.id) else { return }

        guard anket.acik else {
            anketler.removeAll { $0.id == anket.id }
            return
        }
        if let sira = anketler.firstIndex(where: { $0.id == anket.id }) {
            anketler[sira] = anket
        } else {
            anketler.append(anket)
        }
    }

    // MARK: - Gelen mesajlar

    private func gelenIsle(_ veri: Data) {
        guard let zarf = try? JSONAraci.cozucu.decode(GelenZarf.self, from: veri) else { return }

        switch zarf.tip {
        case .durumTam:
            guard let durum = try? zarf.veri(DurumTamVeri.self) else { return }
            kurum = durum.kurum
            ben = durum.ben
            uyeler = durum.uyeler
            bekleyen = durum.bekleyen
            bekleyenCagri = durum.bekleyenCagri

        case .seslenmeGeldi:
            guard let gelen = try? zarf.veri(SeslenmeGeldiVeri.self) else { return }
            seslenmeGeldi?(seslenmeyeCevir(gelen))

        case .kacirilanlar:
            guard let gelen = try? zarf.veri(KacirilanlarVeri.self), !gelen.cagrilar.isEmpty
            else { return }
            kacirilanlarGeldi?(gelen.cagrilar.map(seslenmeyeCevir), gelen.sebep)

        case .yanitGeldi:
            guard let gelen = try? zarf.veri(YanitGeldiVeri.self) else { return }
            yanitGeldi?(gelen)

        case .anketGeldi:
            guard let gelen = try? zarf.veri(AnketGeldiVeri.self) else { return }
            anketGeldi?(gelen)

        case .anketSonuc:
            guard let gelen = try? zarf.veri(AnketSonucVeri.self) else { return }
            anketiYerlestir(Anket(gelen))

        case .acikAnketler:
            guard let gelen = try? zarf.veri(AcikAnketlerVeri.self) else { return }
            // Uyarı çıkarılmaz: bu bir olay değil, bağlanma anındaki durumdur.
            // Aksi halde titrek bağlantıda aynı anket her seferinde çalardı.
            for veri in gelen.anketler { anketiYerlestir(Anket(veri)) }

        case .anketGecmisi:
            guard let gelen = try? zarf.veri(AnketGecmisiVeri.self) else { return }
            // Geçmiş sunucudan olduğu gibi alınır; gizleme yalnızca paneli
            // ilgilendirir, kullanıcı kapattığı anketi geçmişte bulabilmeli.
            anketGecmisi = gelen.anketler.map(Anket.init)

        case .cagriGecmisi:
            guard let gelen = try? zarf.veri(CagriGecmisiVeri.self) else { return }
            cagriGecmisi = gelen.cagrilar.map(GecmisSeslenme.init)

        case .bilgi:
            guard let gelen = try? zarf.veri(BilgiVeri.self) else { return }
            sonBilgi = gelen.mesaj

        case .hata:
            guard let hata = try? zarf.veri(HataVeri.self) else { return }
            sonHata = hata.mesaj

        case .nabizYanit:
            break

        default:
            break
        }
    }

    private func seslenmeyeCevir(_ gelen: SeslenmeGeldiVeri) -> Seslenme {
        Seslenme(
            id: gelen.cagriID,
            gonderenID: gelen.gonderenID,
            gonderenAd: gelen.gonderenAd,
            seviye: gelen.seviye,
            not: gelen.not,
            geldiginde: Date(timeIntervalSince1970: TimeInterval(gelen.gonderildi)),
            yayin: gelen.yayin
        )
    }

    // MARK: - Giden mesajlar

    private func yolla<Govde: Encodable>(_ tip: MesajTipi, _ govde: Govde?) {
        guard let soket, baglanti.iyi else {
            sonHata = "Sunucuya bağlı değilsiniz"
            // Bağlantıyı burada da dürtüyoruz: kullanıcı bir şey yapmaya
            // çalıştıysa beklemeyi sürdürmenin anlamı yok, geri çekilmenin
            // ortasında da olsa hemen denenir.
            gerekirseBaglan()
            return
        }
        guard let veri = try? JSONAraci.kodlayici.encode(GidenZarf(tip: tip, veri: govde)),
              let metin = String(data: veri, encoding: .utf8)
        else { return }

        soket.send(.string(metin)) { [weak self] hata in
            guard let hata else { return }
            Task { @MainActor in
                self?.sonHata = "Gönderilemedi: \(hata.localizedDescription)"
            }
        }
    }

    /// Bir üyeye seslenir.
    func seslen(aliciID: String, seviye: Seviye, not: String = "") {
        yolla(.seslen, SeslenIstek(aliciID: aliciID, seviye: seviye, not: not))
    }

    /// Kurumdaki herkese birden seslenir. Seviye sunucuda sabittir (normal).
    func haykir(not: String = "") {
        yolla(.haykir, HaykirIstek(not: not))
    }

    /// Gelen bir çağrıyı yanıtlar.
    func yanitla(cagriID: String, yanit: Yanit) {
        yolla(.yanitla, YanitlaIstek(cagriID: cagriID, yanit: yanit))
    }

    /// Kendi müsaitlik durumumuzu değiştirir.
    func durumBildir(_ durum: Durum) {
        yolla(.durumBildir, DurumBildirIstek(durum: durum))
    }

    /// Kendi görünen adımızı değiştirir.
    ///
    /// Yerel durum burada tazelenmez: sunucu değişikliği `durum_tam` ile
    /// kuruma yayınlıyor ve biz de o listenin içindeyiz. Adı burada da yazmak,
    /// sunucu isteği reddettiğinde ekranda tutulan yalan bir isim bırakırdı.
    func adDegistir(_ adSoyad: String) {
        yolla(.adDegistir, AdDegistirIstek(adSoyad: adSoyad))
    }

    /// (Yönetim) Üyenin rolünü ve en yüksek seslenme seviyesini ayarlar.
    func uyeGuncelle(uyeID: String, rol: Rol, maxSeviye: Seviye) {
        yolla(.uyeGuncelle, UyeGuncelleIstek(uyeID: uyeID, rol: rol, maxSeviye: maxSeviye))
    }

    /// (Yönetim) Başka bir üyenin görünen adını düzeltir.
    ///
    /// Kendi adımız için `adDegistir` kullanılır; sunucu kurucuyu yönetim
    /// işlemlerine kapattığı için kurucunun adına ancak o yoldan dokunulabilir.
    func uyeAdGuncelle(uyeID: String, adSoyad: String) {
        yolla(.uyeAdGuncelle, UyeAdGuncelleIstek(uyeID: uyeID, adSoyad: adSoyad))
    }

    /// (Yönetim) Bekleyen katılım isteğini onaylar.
    func uyeOnayla(uyeID: String) {
        yolla(.uyeOnayla, UyeIDIstek(uyeID: uyeID))
    }

    /// (Yönetim) Üyeyi kurumdan çıkarır.
    func uyeSil(uyeID: String) {
        yolla(.uyeSil, UyeIDIstek(uyeID: uyeID))
    }

    /// (Yönetim) Katılım kodunu yeniler; eski kod geçersiz olur.
    func kodYenile() {
        yolla(.kodYenile, BosGovde())
    }
}
