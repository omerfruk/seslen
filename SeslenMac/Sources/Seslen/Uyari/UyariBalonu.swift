import AppKit
import SwiftUI

/// Menü çubuğunun altında, ekranın sağ üst köşesinde beliren küçük balon.
///
/// Normal seviyede panel ve kenar flaşı kapalı olduğu için gelen notu görmenin
/// başka yolu kalmıyor: menü çubuğu ikonundaki değişim notu göstermiyor, sistem
/// bildirimi ise izin verilmemişse hiç çıkmıyor. Balon bu boşluğu doldurur.
///
/// Balonlar kendiliğinden kapanmaz. Eskiden altı saniye sonra siliniyorlardı ve
/// kullanıcılar mesajı okumaya fırsat bulamadan kaçırdıklarını bildirdi; artık
/// yalnızca "Okudum" düğmesiyle kapanırlar.
/// İlk tıklamayı yutmadan içeriğe ileten barındırıcı.
///
/// Balon penceresi bilerek hiçbir zaman anahtar pencere olmaz; olsaydı
/// kullanıcının yazdığı yerden odağı çalardı. Ama macOS, etkin olmayan bir
/// pencereye yapılan ilk tıklamayı yalnızca pencereyi öne getirmek için harcar.
/// Bu olmadan "Okudum" düğmesine iki kez basmak gerekirdi.
private final class BalonBarindirici: NSHostingView<BalonYigini> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    required init(rootView: BalonYigini) { super.init(rootView: rootView) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("storyboard'dan kurulmuyor") }
}

@MainActor
final class UyariBalonu {
    /// Aynı anda ekranda çizilecek en fazla balon.
    ///
    /// Fazlası düşürülmez, kuyrukta bekler ve alttaki sayaçta görünür. Eskiden
    /// en eski balon sessizce siliniyordu; kendiliğinden kapanma kalkınca bu,
    /// okunmamış bir seslenmenin hiç görülmemesi demek olurdu.
    private let enFazla = 4

    private let genislik: CGFloat = 360
    private let satirYuksekligi: CGFloat = 78
    /// Anket satırı seçenek düğmeleri için fazladan yer ister.
    private let anketSatirYuksekligi: CGFloat = 104
    private let tasmaYuksekligi: CGFloat = 30
    private let aralik: CGFloat = 8
    /// Ekran kenarına bırakılan boşluk.
    private let kenarBosluk: CGFloat = 12

    private var pencere: NSWindow?
    private var barindirici: BalonBarindirici?
    /// Okunmayı bekleyen tüm öğeler; baştakiler en eskisidir.
    private var bekleyenler: [BalonOgesi] = []

    /// Anket seçeneğine basıldığında haber verir. Kurulumdan sonra atanır:
    /// `UyariYoneticisi` `@Observable` olduğu için orada `lazy` kullanılamıyor.
    var oySecildi: ((String, Int) -> Void)?

    /// Öğenin çizileceği yükseklik.
    private func yukseklik(_ oge: BalonOgesi) -> CGFloat {
        switch oge.icerik {
        case .okundu: satirYuksekligi
        case .anket: anketSatirYuksekligi
        }
    }

    /// Bir öğeyi balon olarak gösterir.
    func goster(_ oge: BalonOgesi) {
        // Aynı öğeyi iki kez eklemeyelim: kaçırılanlar özeti yeniden bağlanmada
        // tekrar gelebiliyor ve kullanıcı aynı balonu iki kez kapatmak zorunda kalır.
        guard !bekleyenler.contains(where: { $0.id == oge.id }) else { return }
        bekleyenler.append(oge)
        yenile()
    }

    /// Tüm balonları anında kaldırır.
    func kapat() {
        bekleyenler.removeAll()
        pencere?.orderOut(nil)
        pencere = nil
        barindirici = nil
    }

    private func kaldir(_ ogeID: String) {
        bekleyenler.removeAll { $0.id == ogeID }
        yenile()
    }

    private func yenile() {
        guard !bekleyenler.isEmpty else {
            kapat()
            return
        }
        guard let ekran = NSScreen.main else { return }

        // Kuyruğun başı çizilir: en eski okunmamış balon hiçbir zaman altta
        // kalmasın, kullanıcı geldikleri sırayla temizlesin.
        let gorunenler = Array(bekleyenler.prefix(enFazla))
        let tasma = bekleyenler.count - gorunenler.count

        let yukseklikler: [CGFloat] = gorunenler.map { yukseklik($0) }

        let icerik = BalonYigini(
            ogeler: gorunenler,
            yukseklikler: yukseklikler,
            tasma: tasma,
            genislik: genislik,
            tasmaYuksekligi: tasmaYuksekligi,
            aralik: aralik,
            okundu: { [weak self] ogeID in self?.kaldir(ogeID) },
            oySecildi: { [weak self] anketID, secenek, ogeID in
                self?.oySecildi?(anketID, secenek)
                // Oy vermek açık bir okuma+eylemdir; balon burada kapanabilir.
                // "Kendiliğinden kapanmaz" kuralı okunmamış mesaj kaybolmasın
                // diyeydi. Canlı sonuç balonun değil menünün işi.
                self?.kaldir(ogeID)
            },
            hepsiniKapat: { [weak self] in self?.kapat() }
        )

        // Yükseklik öğelerden toplanır; böylece pencere boyutu için SwiftUI'nin
        // ölçüm turunu beklemek gerekmez. Anket satırları daha uzun olduğu için
        // düz çarpma yetmiyor, ama yaklaşım aynı kalıyor: ölçme değil, hesapla.
        var toplamYukseklik: CGFloat = 0
        for satir in yukseklikler { toplamYukseklik += satir }
        toplamYukseklik += CGFloat(gorunenler.count - 1) * aralik
        if tasma > 0 { toplamYukseklik += aralik + tasmaYuksekligi }

        let alan = ekran.visibleFrame
        let cerceve = NSRect(
            x: alan.maxX - genislik - kenarBosluk,
            y: alan.maxY - toplamYukseklik - kenarBosluk,
            width: genislik,
            height: toplamYukseklik
        )

        if let barindirici {
            barindirici.rootView = icerik
        } else {
            barindirici = BalonBarindirici(rootView: icerik)
        }

        let pencere = self.pencere ?? pencereKur()
        pencere.contentView = barindirici
        pencere.setFrame(cerceve, display: true)
        pencere.orderFrontRegardless()
        self.pencere = pencere
    }

    private func pencereKur() -> NSWindow {
        let pencere = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        pencere.isOpaque = false
        pencere.backgroundColor = .clear
        pencere.hasShadow = true
        // Panel ve kenar flaşıyla aynı seviye: tam ekran uygulamaların ve
        // Rahatsız Etmeyin kipinin üstünde görünür.
        pencere.level = .screenSaver
        pencere.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        return pencere
    }
}

/// Ekranda üst üste duran balonlar.
private struct BalonYigini: View {
    let ogeler: [BalonOgesi]
    /// `ogeler` ile aynı sırada, satır başına yükseklik.
    let yukseklikler: [CGFloat]
    /// Ekrana sığmayıp kuyrukta bekleyen balon sayısı.
    let tasma: Int
    let genislik: CGFloat
    let tasmaYuksekligi: CGFloat
    let aralik: CGFloat
    let okundu: (String) -> Void
    let oySecildi: (String, Int, String) -> Void
    let hepsiniKapat: () -> Void

    var body: some View {
        VStack(spacing: aralik) {
            ForEach(Array(ogeler.enumerated()), id: \.element.id) { dizin, oge in
                BalonSatiri(
                    oge: oge,
                    okundu: { okundu(oge.id) },
                    oySecildi: { anketID, secenek in oySecildi(anketID, secenek, oge.id) }
                )
                .frame(width: genislik, height: yukseklikler[dizin])
            }
            if tasma > 0 {
                tasmaSatiri
                    .frame(width: genislik, height: tasmaYuksekligi)
            }
        }
    }

    /// Kuyrukta bekleyenleri haber verir. Bu satır olmasaydı sığmayan balonlar
    /// kullanıcı için hiç var olmamış gibi görünürdü.
    private var tasmaSatiri: some View {
        HStack(spacing: 6) {
            Text("+\(tasma) okunmamış daha")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Tümünü kapat", action: hepsiniKapat)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.blue)
        }
        .padding(.horizontal, 12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
        }
    }
}

/// Tek bir balon: kim, ne dedi. Yalnızca düğmeyle kapanır.
private struct BalonSatiri: View {
    let oge: BalonOgesi
    let okundu: () -> Void
    let oySecildi: (String, Int) -> Void

    private var basHarfler: String {
        let parcalar = oge.baslik.split(separator: " ").prefix(2)
        return parcalar.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 9) {
                ZStack {
                    Circle().fill(oge.renk.opacity(0.18))
                    Text(basHarfler).font(.system(size: 11, weight: .semibold))
                }
                .frame(width: 28, height: 28)

                Text(oge.baslik)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                // Yayın kişisel seslenmeden, yanıt da gelen çağrıdan ayırt
                // edilmeli; yoksa herkese giden mesaj kişisel sanılır ve dönen
                // cevap yeni bir seslenme gibi okunur.
                if !oge.rozet.isEmpty {
                    Text(oge.rozet)
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(oge.renk)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(oge.renk.opacity(0.18))
                        }
                        .fixedSize()
                }

                Spacer(minLength: 0)

                Image(systemName: oge.simge)
                    .font(.system(size: 12))
                    .foregroundStyle(oge.renk)
            }

            switch oge.icerik {
            case .okundu:
                HStack(alignment: .bottom, spacing: 8) {
                    Text(oge.altSatir)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    okudumDugmesi
                }

            case let .anket(anketID, secenekler):
                Text(oge.altSatir)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                anketDugmeleri(anketID: anketID, secenekler: secenekler)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(oge.renk.opacity(0.45), lineWidth: 1)
                }
        }
    }

    /// Anket seçenekleri. Beş seçenek 360pt'ye tek satırda sığmayabildiği için
    /// esnek ızgaraya konur; "Katılma" oy vermeden kapatma yoludur.
    private func anketDugmeleri(anketID: String, secenekler: [String]) -> some View {
        HStack(spacing: 5) {
            ForEach(Array(secenekler.enumerated()), id: \.offset) { dizin, secenek in
                Button { oySecildi(anketID, dizin) } label: {
                    Text(secenek)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(oge.renk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background { Capsule().fill(oge.renk.opacity(0.18)) }
                }
                .buttonStyle(.plain)
            }

            Button("Katılma", action: okundu)
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }

    /// Balonu kapatmanın tek yolu. Gövdeye tıklamak kasten bir şey yapmaz:
    /// balonun okunmadan kapanması zaten giderilmeye çalışılan şikayetti.
    private var okudumDugmesi: some View {
        Button(action: okundu) {
            HStack(spacing: 3) {
                Image(systemName: "checkmark")
                Text("Okudum")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(oge.renk)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background { Capsule().fill(oge.renk.opacity(0.18)) }
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}
