import AppKit

/// Uyarı seslerini çalar.
///
/// Hangi sesin çalınacağını kullanıcı seçer (`Ayarlar.ses(seviye:)`); burada
/// yalnızca çalma ve tekrar mantığı var.
@MainActor
enum SesCalar {
    /// ACİL seslenmede sesin kaç kez tekrarlanacağı.
    private static let acilTekrar = 3
    private static let acilAralik: TimeInterval = 0.65

    private static var calan: NSSound?

    /// Her çalma isteğinin sıra numarası.
    ///
    /// ACİL tekrarları `asyncAfter` ile zincirleniyor ve iptal edilemiyorlardı.
    /// Sonuç: ACİL tacize yükseldiğinde uçuştaki zincir adımı `calan?.stop()`
    /// diyerek **alarmı ortasından kesiyor**, kullanıcı tacizi yanıtlayıp her
    /// şeyi kapattıktan sonra da iki hayalet bip duyuyordu. Artık her yeni istek
    /// nesli artırıyor ve eski zincir uyandığında kendini geçersiz buluyor.
    private static var nesil = 0

    /// Verilen sesi belirtilen şiddette çalar.
    static func cal(_ ses: UyariSesi, siddet: Double, tekrar: Int = 1) {
        nesil &+= 1
        calmaAdimi(ses, siddet: siddet, kalan: tekrar, nesli: nesil)
    }

    private static func calmaAdimi(_ ses: UyariSesi, siddet: Double, kalan: Int, nesli: Int) {
        guard kalan > 0, nesli == nesil, let calinacak = hazirla(ses) else { return }

        calinacak.volume = Float(max(0, min(1, siddet)))
        // Aynı NSSound örneği hâlâ çalıyorken tekrar play() çağrısı sessiz kalır;
        // referansı tutup önce durduruyoruz.
        calan?.stop()
        calan = calinacak
        calinacak.play()

        if kalan > 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + acilAralik) {
                MainActor.assumeIsolated {
                    calmaAdimi(ses, siddet: siddet, kalan: kalan - 1, nesli: nesli)
                }
            }
        }
    }

    /// Seviyeye uygun sesi kullanıcının ayarına göre çalar.
    static func cal(seviye: Seviye, ayarlar: Ayarlar) {
        cal(
            ayarlar.ses(seviye),
            siddet: ayarlar.sesSiddeti,
            tekrar: seviye == .acil ? acilTekrar : 1
        )
    }

    /// NSSound örneği üretir: gömülü sesler sentezlenen veriden, gerisi
    /// macOS'un ses kitaplığından gelir.
    ///
    /// Her çalışta yeni örnek gerekiyor — aynı NSSound'u yeniden kullanmak,
    /// tekrarlı ACİL'de ikinci vuruşun sessiz kalmasına yol açıyor.
    private static func hazirla(_ ses: UyariSesi) -> NSSound? {
        if let veri = SesUretici.veri(ses) {
            return NSSound(data: veri)
        }
        if let ad = ses.sistemAdi, let sistem = NSSound(named: ad) {
            return sistem
        }
        // Kullanıcının seçtiği ses bir şekilde yüklenemediyse sessiz kalmaktansa
        // duyulan bir şey çalınmalı: sessizlik, kaçırılmış seslenme demek.
        return NSSound(named: "Ping")
    }

    /// Taciz alarmının iki çalış arasında beklediği süre.
    private static let tacizAralik: TimeInterval = 1.2

    private static var tacizGorevi: Task<Void, Never>?

    /// Taciz alarmını başlatır; `tacizDurdur` çağrılana kadar durmadan çalar.
    /// Diğer seviyelerden farkı bu: taciz sesinin sonu yoktur, yanıtı vardır.
    static func tacizBaslat(_ ses: UyariSesi, siddet: Double) {
        guard tacizGorevi == nil else { return }
        tacizGorevi = Task { @MainActor in
            while !Task.isCancelled {
                cal(ses, siddet: siddet)
                try? await Task.sleep(for: .seconds(tacizAralik))
            }
        }
    }

    /// Taciz alarmını susturur.
    static func tacizDurdur() {
        tacizGorevi?.cancel()
        tacizGorevi = nil
        // Nesli ilerletmek uçuştaki tekrar zincirlerini de geçersiz kılar;
        // yoksa alarm sustuktan sonra eski bir ACİL adımı çalmayı sürdürürdü.
        nesil &+= 1
        calan?.stop()
    }

    /// Ayar ekranında önizleme için tek sefer çalar.
    static func onizle(_ ses: UyariSesi, siddet: Double) {
        cal(ses, siddet: siddet)
    }
}
