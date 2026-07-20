import AppKit
import SwiftUI

/// Menü çubuğunun altında, ekranın sağ üst köşesinde beliren küçük balon.
///
/// Normal seviyede panel ve kenar flaşı kapalı olduğu için gelen notu görmenin
/// başka yolu kalmıyor: menü çubuğu ikonundaki değişim notu göstermiyor, sistem
/// bildirimi ise izin verilmemişse hiç çıkmıyor. Balon bu boşluğu doldurur.
@MainActor
final class UyariBalonu {
    /// Aynı anda ekranda duracak en fazla balon. Fazlası en eskiyi düşürür.
    private let enFazla = 3
    /// Bir balonun kendiliğinden kaybolma süresi.
    private let sure: TimeInterval = 6

    private let genislik: CGFloat = 330
    private let satirYuksekligi: CGFloat = 64
    private let aralik: CGFloat = 8
    /// Ekran kenarına bırakılan boşluk.
    private let kenarBosluk: CGFloat = 12

    private var pencere: NSWindow?
    private var barindirici: NSHostingView<BalonYigini>?
    private var gosterilenler: [Seslenme] = []
    private var kapatmaGorevleri: [String: Task<Void, Never>] = [:]

    /// Bir seslenmeyi balon olarak gösterir.
    func goster(_ seslenme: Seslenme) {
        gosterilenler.append(seslenme)
        if gosterilenler.count > enFazla {
            let dusen = gosterilenler.removeFirst()
            kapatmaGorevleri.removeValue(forKey: dusen.id)?.cancel()
        }

        let bekleme = sure
        kapatmaGorevleri[seslenme.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(bekleme))
            guard !Task.isCancelled else { return }
            self?.kaldir(seslenme.id)
        }

        yenile()
    }

    /// Tüm balonları anında kaldırır.
    func kapat() {
        for gorev in kapatmaGorevleri.values { gorev.cancel() }
        kapatmaGorevleri.removeAll()
        gosterilenler.removeAll()
        pencere?.orderOut(nil)
        pencere = nil
        barindirici = nil
    }

    private func kaldir(_ cagriID: String) {
        kapatmaGorevleri.removeValue(forKey: cagriID)?.cancel()
        gosterilenler.removeAll { $0.id == cagriID }
        yenile()
    }

    private func yenile() {
        guard !gosterilenler.isEmpty else {
            kapat()
            return
        }
        guard let ekran = NSScreen.main else { return }

        let icerik = BalonYigini(
            seslenmeler: gosterilenler,
            genislik: genislik,
            satirYuksekligi: satirYuksekligi,
            aralik: aralik,
            kapat: { [weak self] cagriID in self?.kaldir(cagriID) }
        )

        // Yükseklik satır sayısından hesaplanır; böylece pencere boyutu için
        // SwiftUI'nin ölçüm turunu beklemek gerekmez.
        let sayi = CGFloat(gosterilenler.count)
        let yukseklik = sayi * satirYuksekligi + (sayi - 1) * aralik
        let alan = ekran.visibleFrame
        let cerceve = NSRect(
            x: alan.maxX - genislik - kenarBosluk,
            y: alan.maxY - yukseklik - kenarBosluk,
            width: genislik,
            height: yukseklik
        )

        if let barindirici {
            barindirici.rootView = icerik
        } else {
            barindirici = NSHostingView(rootView: icerik)
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
    let seslenmeler: [Seslenme]
    let genislik: CGFloat
    let satirYuksekligi: CGFloat
    let aralik: CGFloat
    let kapat: (String) -> Void

    var body: some View {
        VStack(spacing: aralik) {
            ForEach(seslenmeler) { seslenme in
                BalonSatiri(seslenme: seslenme) { kapat(seslenme.id) }
                    .frame(width: genislik, height: satirYuksekligi)
            }
        }
    }
}

/// Tek bir balon: kim seslendi ve ne yazdı.
private struct BalonSatiri: View {
    let seslenme: Seslenme
    let kapat: () -> Void

    /// Yayın, seviyesi normal olsa da kendi rengiyle ayrışır.
    private var renk: Color {
        seslenme.yayin ? .purple : seslenme.seviye.renk
    }

    private var simge: String {
        seslenme.yayin ? "megaphone.fill" : seslenme.seviye.simge
    }

    /// Not boş bırakılabildiği için balonun ikinci satırı hiçbir zaman boş kalmaz.
    private var altSatir: String {
        if !seslenme.not.isEmpty { return seslenme.not }
        return seslenme.yayin ? "herkese haykırdı" : "sana seslendi"
    }

    private var basHarfler: String {
        let parcalar = seslenme.gonderenAd.split(separator: " ").prefix(2)
        return parcalar.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(renk.opacity(0.18))
                Text(basHarfler).font(.system(size: 11, weight: .semibold))
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(seslenme.gonderenAd)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    // Yayının tek kişilik seslenmeden ayırt edilmesi gerekir;
                    // yoksa herkese giden mesaj kişisel sanılır.
                    if seslenme.yayin {
                        Text("HERKESE")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.4)
                            .foregroundStyle(renk)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(renk.opacity(0.18))
                            }
                            .fixedSize()
                    }
                }
                Text(altSatir)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Image(systemName: simge)
                .font(.system(size: 12))
                .foregroundStyle(renk)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(renk.opacity(0.45), lineWidth: 1)
                }
        }
        // Tıklayınca kapansın; balon pencereye odak vermediği için başka bir
        // kapatma yolu yok.
        .contentShape(Rectangle())
        .onTapGesture(perform: kapat)
    }
}
