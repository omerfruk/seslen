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

    private let ayarlar: Ayarlar
    private let panel = UyariPaneli()
    private let kenarFlasi = KenarFlasi()

    /// Panel meşgulken gelen seslenmeler sıraya alınır.
    private var kuyruk: [Seslenme] = []

    init(ayarlar: Ayarlar) {
        self.ayarlar = ayarlar
        bildirimIzni = Bundle.main.bundleIdentifier == nil ? .kullanilamaz : .bilinmiyor
    }

    // MARK: - Gelen seslenme

    /// Bir seslenmeyi kullanıcının ayarlarına göre işler.
    func isle(_ seslenme: Seslenme) {
        let bicim = ayarlar.etkinBicim(gonderenID: seslenme.gonderenID, seviye: seslenme.seviye)

        // Kullanıcı bu kişiyi tamamen susturmuşsa hiçbir şey yapmıyoruz.
        guard !bicim.sessiz else { return }

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
            panelGoster(seslenme)
        }
    }

    private func panelGoster(_ seslenme: Seslenme) {
        // Panel zaten açıksa üstüne yazmak yerine sıraya alıyoruz;
        // aksi halde arka arkaya gelen iki çağrıdan biri hiç görünmez.
        guard !panel.acik else {
            kuyruk.append(seslenme)
            return
        }

        panel.goster(
            seslenme: seslenme,
            otomatikKapanma: ayarlar.panelSuresi,
            yanitla: { [weak self] yanit in
                self?.yanitVerildi?(seslenme.id, yanit)
                self?.okunduIsaretle(seslenme.id)
            },
            kapandi: { [weak self] in
                self?.siradakiniGoster()
            }
        )
    }

    private func siradakiniGoster() {
        guard !kuyruk.isEmpty else { return }
        let sonraki = kuyruk.removeFirst()
        panelGoster(sonraki)
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
    }

    /// Ayar ekranından uyarıyı denemek için örnek bir seslenme üretir.
    func onizle(seviye: Seviye) {
        isle(Seslenme(
            id: "onizleme-\(UUID().uuidString)",
            gonderenID: "onizleme",
            gonderenAd: "Örnek Kişi",
            seviye: seviye,
            not: "Bu bir deneme uyarısıdır.",
            geldiginde: Date()
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
        icerik.title = "\(seslenme.gonderenAd) sana sesleniyor"
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
}
