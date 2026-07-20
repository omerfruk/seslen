import AppKit
import ServiceManagement

/// macOS Sistem Ayarları ile ilgili yardımcılar.
///
/// Seslen imzasız dağıtıldığı için kullanıcı bazı izinleri elle vermek zorunda kalır.
/// Buradaki işlevler kullanıcıyı doğrudan ilgili ayar sayfasına götürür ki
/// "Sistem Ayarları'nı açın, şuraya gidin..." tarifiyle uğraşmasın.
@MainActor
enum SistemAyarlari {
    /// Bildirim izinleri sayfasını açar.
    static func bildirimleriAc() {
        ac("x-apple.systempreferences:com.apple.preference.notifications")
    }

    /// Giriş Öğeleri (açılışta başlat) sayfasını açar.
    static func girisOgeleriniAc() {
        ac("x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
    }

    /// Gizlilik ve Güvenlik ana sayfasını açar.
    /// İmzasız uygulama ilk açılışta engellendiğinde "Yine de Aç" düğmesi buradadır.
    static func gizlilikVeGuvenlikAc() {
        ac("x-apple.systempreferences:com.apple.preference.security")
    }

    private static func ac(_ adres: String) {
        guard let url = URL(string: adres) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Uygulamanın açılışta kendiliğinden başlaması ayarını uygular.
    /// Başarısız olursa kullanıcıya gösterilecek bir mesaj döner, aksi halde nil.
    static func acilistaBaslatmayiAyarla(_ acik: Bool) -> String? {
        // SMAppService yalnızca paketlenmiş (.app) ve en azından ad-hoc imzalı
        // uygulamalarda çalışır; `swift run` ile geliştirme yaparken çalışmaz.
        guard Bundle.main.bundleIdentifier != nil else {
            return "Bu ayar yalnızca kurulu uygulamada çalışır."
        }
        do {
            if acik {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return "Açılışta başlatma ayarlanamadı: \(error.localizedDescription)"
        }
    }
}
