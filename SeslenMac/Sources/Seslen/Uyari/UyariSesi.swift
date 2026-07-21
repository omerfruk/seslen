import AppKit
import Foundation

/// Seslenme seviyelerinde çalınabilecek sesler.
///
/// İki kaynak var: **gömülü** sesler çalışma anında üretilir, gerisi macOS'un
/// yerleşik sesleridir. Üretme yoluna gidilmesinin sebebi macOS'ta iPhone'un
/// bildirim sesine benzeyen bir sesin bulunmamasıdır — sistem seslerinin hepsi
/// tek vuruşluk ve ya çok cılız (Tink) ya da boğuk (Basso). Ses dosyası
/// paketlemek yerine üretmek, dağıtıma bir varlık eklemeden aynı sonucu verir.
/// `rawValue`'lar açıkça yazılı: bu değerler kullanıcının ayar dosyasına
/// yazılıyor. Örtük bırakılsaydı bir case'i yeniden adlandırmak diskteki
/// seçimi sessizce geçersiz kılardı — `Ayarlar.Kayit.sesler` bunu tolere ediyor
/// ama o hoşgörü, adları kararlı tutma sorumluluğunun yerine geçmez.
enum UyariSesi: String, Codable, CaseIterable, Sendable {
    // Gömülü.
    case ucNota = "ucNota"
    case ciftDing = "ciftDing"
    case yumusakDing = "yumusakDing"
    case keskinUyari = "keskinUyari"
    case alarm = "alarm"
    // macOS yerleşikleri. Ham değer, sistem sesinin dosya adının küçük harflisi
    // olmalı: `sistemAdi` onu buradan türetiyor.
    case glass = "glass"
    case hero = "hero"
    case sosumi = "sosumi"
    case ping = "ping"
    case tink = "tink"
    case pop = "pop"
    case submarine = "submarine"
    case bottle = "bottle"
    case funk = "funk"
    case morse = "morse"
    case basso = "basso"

    var baslik: String {
        switch self {
        case .ucNota: "Üç nota (iPhone tarzı)"
        case .ciftDing: "Çift ding"
        case .yumusakDing: "Yumuşak ding"
        case .keskinUyari: "Keskin uyarı"
        case .alarm: "Alarm"
        case .glass: "Glass"
        case .hero: "Hero"
        case .sosumi: "Sosumi"
        case .ping: "Ping"
        case .tink: "Tink"
        case .pop: "Pop"
        case .submarine: "Submarine"
        case .bottle: "Bottle"
        case .funk: "Funk"
        case .morse: "Morse"
        case .basso: "Basso"
        }
    }

    /// Gömülü sesler listede ayrı bir başlık altında toplanır.
    var gomulu: Bool { notalar != nil }

    /// macOS yerleşik sesinin adı; gömülü seslerde nil.
    var sistemAdi: String? {
        guard !gomulu else { return nil }
        return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    /// Gömülü sesin tarifi. Sistem seslerinde nil.
    ///
    /// Frekanslar eşit tamperemanlı gamdan alındı; rastgele sayılar birbirine
    /// yakın düştüğünde ses akortsuz bir zil gibi duyuluyor.
    var notalar: [SesNotasi]? {
        switch self {
        // Yükselen üçlü: C6-E6-G6. Aralıklar notaların sönümünden kısa, böylece
        // üç ayrı vuruş değil tek bir ezgi duyulur.
        case .ucNota: [
            SesNotasi(frekans: 1046.50, baslangic: 0.00),
            SesNotasi(frekans: 1318.51, baslangic: 0.085),
            SesNotasi(frekans: 1567.98, baslangic: 0.170, sure: 0.55),
        ]
        case .ciftDing: [
            SesNotasi(frekans: 1318.51, baslangic: 0.00),
            SesNotasi(frekans: 1760.00, baslangic: 0.13, sure: 0.50),
        ]
        case .yumusakDing: [
            SesNotasi(frekans: 880.00, baslangic: 0.00, sure: 0.55, siddet: 0.7),
        ]
        // Aynı yüksek notanın hızlı tekrarı: ezgi değil, ısrar.
        case .keskinUyari: [
            SesNotasi(frekans: 1760.00, baslangic: 0.00, sure: 0.16),
            SesNotasi(frekans: 1760.00, baslangic: 0.16, sure: 0.16),
            SesNotasi(frekans: 2093.00, baslangic: 0.32, sure: 0.40),
        ]
        // Alçak ve iki notalı: hoş duyulmaması kasıtlı, taciz sesidir.
        case .alarm: [
            SesNotasi(frekans: 440.00, baslangic: 0.00, sure: 0.22, siddet: 1.0, tini: .duz),
            SesNotasi(frekans: 349.23, baslangic: 0.22, sure: 0.22, siddet: 1.0, tini: .duz),
            SesNotasi(frekans: 440.00, baslangic: 0.44, sure: 0.22, siddet: 1.0, tini: .duz),
            SesNotasi(frekans: 349.23, baslangic: 0.66, sure: 0.30, siddet: 1.0, tini: .duz),
        ]
        default: nil
        }
    }

    /// Seviyelerin varsayılan sesleri.
    ///
    /// Ayrımın duyulabilir olması şart: kullanıcı ekrana bakmadan hangi
    /// seviyede seslenildiğini anlayabilmeli. Bu yüzden yalnızca yükseklik
    /// değil, nota sayısı ve ritim de seviyeden seviyeye değişir.
    static func varsayilan(_ seviye: Seviye) -> UyariSesi {
        switch seviye {
        case .normal: .ucNota
        case .onemli: .ciftDing
        case .acil: .keskinUyari
        case .taciz: .alarm
        }
    }
}

/// Gömülü seslerdeki tek bir nota.
struct SesNotasi: Sendable {
    /// Notanın rengi.
    enum Tini: Sendable {
        /// Zil gibi: taşıyıcının üstüne sönük bir üst ses binerek metalik bir
        /// tok ses verir. Bildirimlerin çoğu böyledir.
        case zil
        /// Katıksız sinüs. Alarm için: hoş duyulmaz, dikkat çeker.
        case duz
    }

    var frekans: Double
    /// Desenin başından itibaren kaçıncı saniyede başladığı.
    var baslangic: Double
    var sure: Double = 0.30
    var siddet: Double = 0.9
    var tini: Tini = .zil
}

/// Nota tariflerini çalınabilir WAV verisine çevirir.
///
/// Üretilen veri örnek başına yeniden hesaplanmaz, `bellek` içinde tutulur:
/// yarım saniyelik ses ~44 KB ve her seslenmede yeniden sentezlemenin
/// kazandıracağı hiçbir şey yok.
@MainActor
enum SesUretici {
    private static let ornekHizi = 44_100.0
    private static var bellek: [UyariSesi: Data] = [:]

    static func veri(_ ses: UyariSesi) -> Data? {
        if let hazir = bellek[ses] { return hazir }
        guard let notalar = ses.notalar else { return nil }
        let uretilen = wav(notalar)
        bellek[ses] = uretilen
        return uretilen
    }

    private static func wav(_ notalar: [SesNotasi]) -> Data {
        let toplamSure = (notalar.map { $0.baslangic + $0.sure }.max() ?? 0.5) + 0.05
        let ornekSayisi = Int(toplamSure * ornekHizi)
        var kanal = [Double](repeating: 0, count: ornekSayisi)

        for nota in notalar {
            let basla = Int(nota.baslangic * ornekHizi)
            let uzunluk = Int(nota.sure * ornekHizi)
            for i in 0..<uzunluk where basla + i < ornekSayisi {
                let t = Double(i) / ornekHizi
                kanal[basla + i] += ornek(nota: nota, t: t)
            }
        }

        // Notalar üst üste bindiğinde toplam 1.0'ı aşıp kırpılabilir; kırpılmış
        // sinüs zil değil cızırtı gibi duyulur. Tepe değere göre ölçeklemek
        // deseni değiştirmeden bunu tamamen önler.
        let tepe = kanal.map(abs).max() ?? 0
        if tepe > 0.99 {
            let carpan = 0.99 / tepe
            for i in kanal.indices { kanal[i] *= carpan }
        }

        return paketle(kanal)
    }

    private static func ornek(nota: SesNotasi, t: Double) -> Double {
        let acisal = 2 * Double.pi * nota.frekans * t

        let taban: Double
        switch nota.tini {
        case .zil:
            // Üst ses tam kat değil biraz kaydırılmış (2.01): tam kat, sesi
            // sentetik bir org tonuna çevirir; hafif kayma metalik tını verir.
            taban = sin(acisal) + 0.32 * sin(2.01 * acisal) + 0.12 * sin(3.02 * acisal)
        case .duz:
            taban = sin(acisal)
        }

        // Hızlı çıkış + üstel sönüm: vurmalı bir çalgının zarfı. Doğrusal
        // sönümde ses sonunda birden kesiliyor ve "tık" duyuluyor.
        let cikis = min(1, t / 0.004)
        let sonum = exp(-t * (nota.tini == .zil ? 7.0 : 12.0))
        return taban * cikis * sonum * nota.siddet * 0.42
    }

    /// 16 bit, tek kanal, 44.1 kHz PCM başlığı + örnekler.
    private static func paketle(_ kanal: [Double]) -> Data {
        let bitDerinligi = 16
        let veriBoyutu = kanal.count * bitDerinligi / 8
        var veri = Data(capacity: 44 + veriBoyutu)

        func yaz32(_ deger: UInt32) { withUnsafeBytes(of: deger.littleEndian) { veri.append(contentsOf: $0) } }
        func yaz16(_ deger: UInt16) { withUnsafeBytes(of: deger.littleEndian) { veri.append(contentsOf: $0) } }

        veri.append(contentsOf: Array("RIFF".utf8))
        yaz32(UInt32(36 + veriBoyutu))
        veri.append(contentsOf: Array("WAVEfmt ".utf8))
        yaz32(16)                                   // fmt bloğunun uzunluğu
        yaz16(1)                                    // PCM
        yaz16(1)                                    // kanal sayısı
        yaz32(UInt32(ornekHizi))
        yaz32(UInt32(ornekHizi) * 2)                // saniyedeki bayt
        yaz16(2)                                    // örnek başına bayt
        yaz16(UInt16(bitDerinligi))
        veri.append(contentsOf: Array("data".utf8))
        yaz32(UInt32(veriBoyutu))

        for deger in kanal {
            let kirpilmis = max(-1, min(1, deger))
            yaz16(UInt16(bitPattern: Int16(kirpilmis * 32_767)))
        }
        return veri
    }
}
