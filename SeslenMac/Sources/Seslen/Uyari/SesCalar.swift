import AppKit

/// Uyarı seslerini çalar. macOS'un yerleşik sistem sesleri kullanılır;
/// böylece uygulamaya ses dosyası gömmek gerekmez.
@MainActor
enum SesCalar {
    /// Seviyeye göre sistem sesi adı.
    private static func sesAdi(_ seviye: Seviye) -> String {
        switch seviye {
        case .normal: "Tink"      // kısa, yumuşak
        case .onemli: "Ping"      // belirgin
        case .acil: "Sosumi"      // keskin, dikkat çekici
        case .taciz: "Basso"      // boğuk ve rahatsız edici
        }
    }

    /// ACİL seslenmede sesin kaç kez tekrarlanacağı.
    private static let acilTekrar = 3
    private static let acilAralik: TimeInterval = 0.55

    private nonisolated(unsafe) static var calan: NSSound?

    /// Seviyeye uygun sesi verilen şiddette çalar.
    static func cal(seviye: Seviye, siddet: Double) {
        calmaAdimi(seviye: seviye, siddet: siddet, kalan: seviye == .acil ? acilTekrar : 1)
    }

    private static func calmaAdimi(seviye: Seviye, siddet: Double, kalan: Int) {
        guard kalan > 0 else { return }
        guard let ses = NSSound(named: sesAdi(seviye)) ?? NSSound(named: "Ping") else { return }

        ses.volume = Float(max(0, min(1, siddet)))
        // Aynı NSSound örneği hâlâ çalıyorken tekrar play() çağrısı sessiz kalır;
        // referansı tutup önce durduruyoruz.
        calan?.stop()
        calan = ses
        ses.play()

        if kalan > 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + acilAralik) {
                calmaAdimi(seviye: seviye, siddet: siddet, kalan: kalan - 1)
            }
        }
    }

    /// Taciz alarmının iki çalış arasında beklediği süre.
    private static let tacizAralik: TimeInterval = 1.2

    private static var tacizGorevi: Task<Void, Never>?

    /// Taciz alarmını başlatır; `tacizDurdur` çağrılana kadar durmadan çalar.
    /// Diğer seviyelerden farkı bu: taciz sesinin sonu yoktur, yanıtı vardır.
    static func tacizBaslat(siddet: Double) {
        guard tacizGorevi == nil else { return }
        tacizGorevi = Task { @MainActor in
            while !Task.isCancelled {
                onizle(seviye: .taciz, siddet: siddet)
                try? await Task.sleep(for: .seconds(tacizAralik))
            }
        }
    }

    /// Taciz alarmını susturur.
    static func tacizDurdur() {
        tacizGorevi?.cancel()
        tacizGorevi = nil
        calan?.stop()
    }

    /// Ayar ekranında önizleme için tek sefer çalar.
    static func onizle(seviye: Seviye, siddet: Double) {
        guard let ses = NSSound(named: sesAdi(seviye)) ?? NSSound(named: "Ping") else { return }
        ses.volume = Float(max(0, min(1, siddet)))
        calan?.stop()
        calan = ses
        ses.play()
    }
}
