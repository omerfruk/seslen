import AppKit
import Observation
import UserNotifications

/// Bildirim izninin durumu.
enum BildirimIzni: Sendable, Equatable {
    case bilinmiyor
    case verildi
    case reddedildi
    /// Uygulama paketlenmemiş halde çalışıyor (geliştirme kipi); bildirim kullanılamaz.
    case kullanilamaz

    var aciklama: String {
        switch self {
        case .bilinmiyor: "Henüz sorulmadı"
        case .verildi: "İzin verildi"
        case .reddedildi: "İzin reddedildi"
        case .kullanilamaz: "Kurulu sürümde kullanılabilir"
        }
    }
}

/// Gelen seslenmeleri, kullanıcının ayarlarına göre uyarıya dönüştürür.
///
/// Her uyarı biçimi (ikon, panel, ses, kenar) ayrı ayrı açılıp kapatılabildiği
/// için karar mantığı tek yerde toplanmıştır: `Ayarlar.etkinBicim`.
@MainActor
@Observable
final class UyariYoneticisi {
    /// Menü çubuğu ikonunun dikkat çekmesi gerekiyor mu?
    private(set) var dikkatCekiyor = false
    /// Henüz yanıtlanmamış seslenmeler (menüde rozet olarak gösterilir).
    private(set) var okunmamis: [Seslenme] = []
    /// Bildirim izninin son bilinen durumu.
    private(set) var bildirimIzni: BildirimIzni = .bilinmiyor

    /// Panelde bir yanıt düğmesine basıldığında çağrılır.
    var yanitVerildi: ((_ cagriID: String, _ yanit: Yanit) -> Void)?
    /// Balondaki anket seçeneklerinden birine basıldığında çağrılır.
    var anketOyuVerildi: ((_ anketID: String, _ secenek: Int) -> Void)?

    private let ayarlar: Ayarlar
    private let panel = UyariPaneli()
    private let kenarFlasi = KenarFlasi()
    private let balon = UyariBalonu()
    private let taciz = TacizPenceresi()

    /// Taciz penceresinde birlikte gösterilen çağrılar.
    private var tacizGrubu: [Seslenme] = []

    /// Panelde gösterilmeyi bekleyen seslenmeler.
    private var panelKuyrugu: [Seslenme] = []
    /// Panelde şu anda gösterilen grup. Boşsa panel kapalıdır.
    private var acikGrup: [Seslenme] = []

    init(ayarlar: Ayarlar) {
        self.ayarlar = ayarlar
        bildirimIzni = Bundle.main.bundleIdentifier == nil ? .kullanilamaz : .bilinmiyor
        balon.oySecildi = { [weak self] anketID, secenek in
            self?.anketOyuVerildi?(anketID, secenek)
        }
    }

    // MARK: - Gelen seslenme

    /// Bir seslenmeyi kullanıcının ayarlarına göre işler.
    func isle(_ seslenme: Seslenme) {
        let bicim = ayarlar.etkinBicim(gonderenID: seslenme.gonderenID, seviye: seslenme.seviye)

        // Kullanıcı bu kişiyi tamamen susturmuşsa hiçbir şey yapmıyoruz.
        guard !bicim.sessiz else { return }

        // Taciz kendi tam ekran penceresini açar ve alarmını kendi sürdürür;
        // panel, balon ve tek seferlik ses onun yanında hem gereksiz hem de
        // birbirinin sesini bastırır.
        if seslenme.seviye == .taciz {
            dikkatCekiyor = true
            okunmamis.append(seslenme)
            bildirimGonder(seslenme)
            tacizGoster(seslenme)
            return
        }

        if bicim.ikon {
            dikkatCekiyor = true
            okunmamis.append(seslenme)
            bildirimGonder(seslenme)
        }
        if bicim.ses {
            SesCalar.cal(seviye: seslenme.seviye, siddet: ayarlar.sesSiddeti)
        }
        if bicim.kenar {
            kenarFlasi.goster(sure: seslenme.seviye == .acil ? 4 : 2)
        }
        if bicim.panel {
            panelKuyrugu.append(seslenme)
            panelKuyrugunuIsle()
        } else if bicim.ikon {
            // Panel kapalıyken notu gösteren tek yer balon. Panel açıksa notu
            // zaten o gösteriyor; ikisini birden çıkarmak tekrar olurdu.
            balon.goster(seslenme.balon)
        }
    }

    // MARK: - Anket

    /// Gelen anketi gösterir.
    ///
    /// Karar yine `etkinBicim`'den okunur ama yalnızca üç biçimi kullanılır:
    /// **panel ve kenar flaşı, kullanıcının ayarı açık olsa bile hiç devreye
    /// girmez.** Anket rica eder, kesmez — normal seviyenin kasten hafif
    /// tutulmasıyla aynı gerekçe. Susturulmuş kişi anketle de ulaşamaz: mesaj
    /// tipi değiştirerek susturmayı aşmak mümkün olmamalı.
    func anketIsle(_ veri: AnketGeldiVeri) {
        let bicim = ayarlar.etkinBicim(gonderenID: veri.gonderenID, seviye: .normal)
        guard !bicim.sessiz else { return }

        if bicim.ikon {
            dikkatCekiyor = true
            anketBildirimi(veri)
        }
        if bicim.ses {
            SesCalar.cal(seviye: .normal, siddet: ayarlar.sesSiddeti)
        }
        // Anketler `okunmamis` dizisine girmez: o dizi yanıtlanabilir çağrılar
        // içindir ve `okunduIsaretle(cagriID)` ile temizlenir. Anketi karıştırmak
        // rozetteki sayıyı iki anlamlı hale getirirdi.
        balon.goster(.anket(veri))
    }

    private func anketBildirimi(_ veri: AnketGeldiVeri) {
        guard Bundle.main.bundleIdentifier != nil, bildirimIzni == .verildi else { return }

        let icerik = UNMutableNotificationContent()
        icerik.title = "\(veri.gonderenAd) soruyor"
        icerik.body = veri.soru
        // Anket acil değildir; kullanıcı ona kendi zamanında bakar.
        icerik.interruptionLevel = .passive
        icerik.sound = nil

        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "anket-\(veri.anketID)", content: icerik, trigger: nil
        ))
    }

    /// Bize ulaştırılamamış çağrıları toplu olarak gösterir.
    ///
    /// Bunlar `isle` üzerinden geçmez: her biri kendi panelini açsaydı,
    /// bilgisayarını açan kullanıcı arka arkaya beş tam ekran pencere kapatmak
    /// zorunda kalırdı. Geçmişte kalmış bir çağrı ekranı kesmemeli; tek bir
    /// özet yeterlidir. Rozet ve liste yine dolar, kimse gözden kaçmaz.
    func kacirilanlariIsle(_ seslenmeler: [Seslenme], sebep: KacirilmaSebebi) {
        let gorunecekler = seslenmeler.filter {
            !ayarlar.etkinBicim(gonderenID: $0.gonderenID, seviye: $0.seviye).sessiz
        }
        guard !gorunecekler.isEmpty else { return }

        okunmamis.append(contentsOf: gorunecekler)
        dikkatCekiyor = true

        let adlar = gorunecekler.map(\.gonderenAd)
        // Tekrarlı adlar özeti şişirir: aynı kişi beş kez seslenmiş olabilir.
        var benzersiz: [String] = []
        for ad in adlar where !benzersiz.contains(ad) { benzersiz.append(ad) }

        balon.goster(BalonOgesi(
            id: "kacirilanlar-\(gorunecekler.map(\.id).joined())",
            baslik: "\(sebep.baslik) \(gorunecekler.count) seslenme",
            altSatir: benzersiz.joined(separator: ", "),
            simge: "clock.arrow.circlepath",
            renk: gorunecekler.map(\.seviye).max()?.renk ?? .blue,
            rozet: sebep.rozet
        ))
        kacirilanBildirimi(adet: gorunecekler.count, adlar: benzersiz, sebep: sebep)
    }

    /// Gönderdiğimiz bir çağrıya dönen yanıtı gösterir.
    ///
    /// Yanıt uyarı biçimi ayarlarına bakmaz: kullanıcı bu çağrıyı kendi
    /// başlattığı için cevabını görmek ister, sessize alma gelen seslenmeler
    /// içindir.
    func yanitiGoster(_ veri: YanitGeldiVeri) {
        balon.goster(.yanit(veri))
    }

    // MARK: - Taciz

    private func tacizGoster(_ seslenme: Seslenme) {
        tacizGrubu.append(seslenme)
        guard let grup = SeslenmeGrubu(tacizGrubu) else { return }

        if taciz.acik {
            taciz.tazele(grup)
            return
        }
        taciz.goster(grup: grup, siddet: ayarlar.sesSiddeti) { [weak self] yanit in
            self?.tacizYanitlandi(yanit)
        }
    }

    private func tacizYanitlandi(_ yanit: Yanit) {
        // Tek yanıt gruptaki bütün taciz çağrılarını kapatır; aksi halde
        // pencere kapanır kapanmaz bir sonraki çağrı için yeniden açılırdı.
        for seslenme in tacizGrubu {
            if !seslenme.onizleme { yanitVerildi?(seslenme.id, yanit) }
            okunduIsaretle(seslenme.id)
        }
        tacizGrubu = []
    }

    // MARK: - Panel kuyruğu

    /// Panel kuyruğunu gözden geçirir.
    ///
    /// Aynı kişiden gelen çağrılar tek panelde toplanır: arka arkaya üç ACİL
    /// gelince üç ayrı pencereyi tek tek kapatmak gerekmesin, tek "geliyorum"
    /// üçüne birden yanıt olsun.
    private func panelKuyrugunuIsle() {
        // Panel açıkken aynı kişiden yeni seslenme geldiyse pencereyi tazeliyoruz.
        if let gonderenID = acikGrup.first?.gonderenID {
            let ekler = panelKuyrugu.filter { $0.gonderenID == gonderenID }
            guard !ekler.isEmpty else { return }
            panelKuyrugu.removeAll { $0.gonderenID == gonderenID }
            acikGrup.append(contentsOf: ekler)
            if let grup = SeslenmeGrubu(acikGrup) { panel.tazele(grup) }
            return
        }

        // Sırayı en yüksek seviyeli bekleyen belirler; araya giren bir ACİL
        // normal seslenmelerin arkasında beklemesin.
        guard let oncelikli = panelKuyrugu.max(by: { $0.seviye < $1.seviye }) else { return }
        let gonderenID = oncelikli.gonderenID

        acikGrup = panelKuyrugu.filter { $0.gonderenID == gonderenID }
        panelKuyrugu.removeAll { $0.gonderenID == gonderenID }

        guard let grup = SeslenmeGrubu(acikGrup) else { return }
        panel.goster(
            grup: grup,
            otomatikKapanma: ayarlar.panelSuresi,
            kapandi: { [weak self] yanit in self?.grupKapandi(yanit) }
        )
    }

    private func grupKapandi(_ yanit: Yanit?) {
        if let yanit {
            // Tek yanıt gruptaki bütün çağrılara gider. Sunucu her çağrıyı ayrı
            // tuttuğu için hepsine tek tek yollamak gerekir; kullanıcı bunu
            // görmez, onun için tek tıktır.
            for seslenme in acikGrup {
                // Deneme çağrısının sunucuda karşılığı yok; yanıtını yollamak
                // kullanıcıya sebepsiz bir "çağrı bulunamadı" hatası gösterir.
                if !seslenme.onizleme { yanitVerildi?(seslenme.id, yanit) }
                okunduIsaretle(seslenme.id)
            }
        }
        acikGrup = []
        panelKuyrugunuIsle()
    }

    /// Bir seslenmeyi okunmuş sayar.
    func okunduIsaretle(_ cagriID: String) {
        okunmamis.removeAll { $0.id == cagriID }
        if okunmamis.isEmpty { dikkatCekiyor = false }
    }

    /// Menü açıldığında tüm bekleyen uyarıları temizler.
    func hepsiniTemizle() {
        okunmamis.removeAll()
        dikkatCekiyor = false
        // Kullanıcı listeyi menüde gördü; balonların ekranda kalmasına gerek yok.
        balon.kapat()
        // Kuyrukta bekleyen paneller de artık gereksiz: hepsi menüde görüldü,
        // sırayla açılmaları kullanıcıyı boşuna pencere kapatmaya zorlar.
        // Açık panel bilerek dokunulmaz; kullanıcı ona yanıt veriyor olabilir.
        panelKuyrugu.removeAll()
    }

    /// Ayar ekranından uyarıyı denemek için örnek bir seslenme üretir.
    func onizle(seviye: Seviye) {
        isle(Seslenme(
            id: "onizleme-\(UUID().uuidString)",
            gonderenID: "onizleme",
            gonderenAd: "Örnek Kişi",
            seviye: seviye,
            not: "Bu bir deneme uyarısıdır.",
            geldiginde: Date(),
            onizleme: true
        ))
    }

    // MARK: - Bildirimler

    /// Bildirim izin durumunu sorgular.
    func izinDurumunuYenile() async {
        guard Bundle.main.bundleIdentifier != nil else {
            bildirimIzni = .kullanilamaz
            return
        }
        let ayar = await UNUserNotificationCenter.current().notificationSettings()
        bildirimIzni = switch ayar.authorizationStatus {
        case .authorized, .provisional, .ephemeral: .verildi
        case .denied: .reddedildi
        default: .bilinmiyor
        }
    }

    /// Bildirim izni ister. Kullanıcı daha önce reddettiyse sistem penceresi
    /// bir daha çıkmaz; o durumda Sistem Ayarları'na yönlendiriyoruz.
    func bildirimIzniIste() async {
        guard Bundle.main.bundleIdentifier != nil else {
            bildirimIzni = .kullanilamaz
            return
        }
        if bildirimIzni == .reddedildi {
            SistemAyarlari.bildirimleriAc()
            return
        }
        do {
            let verildi = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            bildirimIzni = verildi ? .verildi : .reddedildi
        } catch {
            bildirimIzni = .reddedildi
        }
    }

    private func bildirimGonder(_ seslenme: Seslenme) {
        guard Bundle.main.bundleIdentifier != nil, bildirimIzni == .verildi else { return }

        let icerik = UNMutableNotificationContent()
        icerik.title = seslenme.yayin
            ? "\(seslenme.gonderenAd) herkese haykırdı"
            : "\(seslenme.gonderenAd) sana sesleniyor"
        icerik.body = seslenme.not.isEmpty ? seslenme.seviye.baslik : seslenme.not
        icerik.interruptionLevel = seslenme.seviye == .acil ? .critical : .timeSensitive
        // Sesi biz çalıyoruz; bildirimin kendi sesi çift ses olmasın.
        icerik.sound = nil

        let istek = UNNotificationRequest(
            identifier: seslenme.id,
            content: icerik,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(istek)
    }

    /// Kaçırılan çağrılar için tek bir özet bildirimi yollar.
    private func kacirilanBildirimi(adet: Int, adlar: [String], sebep: KacirilmaSebebi) {
        guard Bundle.main.bundleIdentifier != nil, bildirimIzni == .verildi else { return }

        let icerik = UNMutableNotificationContent()
        icerik.title = "\(sebep.baslik) \(adet) seslenme"
        icerik.body = adlar.joined(separator: ", ")
        // Geçmişte kalmış çağrı acil değildir; kullanıcı ona kendi zamanında bakar.
        icerik.interruptionLevel = .passive
        icerik.sound = nil

        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "kacirilanlar-\(adet)-\(Date().timeIntervalSince1970)",
            content: icerik,
            trigger: nil
        ))
    }
}
