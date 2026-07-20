import AppKit
import SwiftUI

/// Kenarlıksız pencerelerin klavye odağı alabilmesi için gereken alt sınıf.
/// `.borderless` pencereler öntanımlı olarak anahtar pencere olamaz; bu da
/// paneldeki düğmelerin klavyeyle kullanılmasını engeller.
private final class OdaklanabilirPencere: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Ekranın ortasında beliren, kimin seslendiğini gösteren uyarı paneli.
@MainActor
final class UyariPaneli {
    private var pencere: NSWindow?
    private var barindirici: NSHostingView<PanelGorunumu>?
    private var kapatmaGorevi: Task<Void, Never>?
    /// Panel kapanınca çağrılacak geri bildirim. `tazele` görünümü yeniden
    /// kurarken de buna ihtiyaç duyduğu için saklanır.
    private var kapandiGeri: ((Yanit?) -> Void)?
    private var otomatikKapanma: TimeInterval = 0

    /// Panel şu anda ekranda mı?
    var acik: Bool { pencere != nil }

    /// Paneli gösterir. `kapandi`, panel kapandığında bir kez çağrılır: seçilen
    /// yanıt varsa onu taşır, kullanıcı yanıtsız kapattıysa `nil` gelir.
    func goster(
        grup: SeslenmeGrubu,
        otomatikKapanma: TimeInterval,
        kapandi: @escaping (Yanit?) -> Void
    ) {
        kapat()

        kapandiGeri = kapandi
        self.otomatikKapanma = otomatikKapanma

        let barindirici = NSHostingView(rootView: gorunum(grup))
        let pencere = OdaklanabilirPencere(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 340),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        pencere.isOpaque = false
        pencere.backgroundColor = .clear
        pencere.hasShadow = true
        // Tam ekran sunum/video sırasında bile görünsün. Bu seviye aynı zamanda
        // Rahatsız Etmeyin kipini de aşar; normal bildirimler aşamaz.
        pencere.level = .screenSaver
        pencere.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        pencere.isMovableByWindowBackground = true
        pencere.contentView = barindirici
        pencere.center()
        pencere.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.barindirici = barindirici
        self.pencere = pencere

        zamanlayiciKur()
    }

    /// Açık panelin içeriğini değiştirir.
    ///
    /// Aynı kişiden yeni bir seslenme gelince pencereyi kapatıp yeniden açmak
    /// yerine bu kullanılır; yoksa pencere ekranın ortasına geri sıçrar,
    /// animasyon baştan başlar ve kullanıcının imleci düğmelerden kayar.
    func tazele(_ grup: SeslenmeGrubu) {
        guard let barindirici else { return }
        barindirici.rootView = gorunum(grup)
        // Yeni bir seslenme geldiğine göre otomatik kapanma süresi baştan işlesin.
        zamanlayiciKur()
    }

    private func gorunum(_ grup: SeslenmeGrubu) -> PanelGorunumu {
        PanelGorunumu(
            grup: grup,
            secildi: { [weak self] yanit in self?.bitir(yanit) }
        )
    }

    /// Paneli kapatır ve geri bildirimi tam bir kez çağırır.
    private func bitir(_ yanit: Yanit?) {
        let geri = kapandiGeri
        kapat()
        geri?(yanit)
    }

    private func zamanlayiciKur() {
        kapatmaGorevi?.cancel()
        kapatmaGorevi = nil
        guard otomatikKapanma > 0 else { return }

        let sure = otomatikKapanma
        kapatmaGorevi = Task { [weak self] in
            try? await Task.sleep(for: .seconds(sure))
            guard !Task.isCancelled else { return }
            self?.bitir(nil)
        }
    }

    /// Paneli kapatır. Geri bildirimi çağırmaz; onu `bitir` yürütür.
    func kapat() {
        kapatmaGorevi?.cancel()
        kapatmaGorevi = nil
        pencere?.orderOut(nil)
        pencere = nil
        barindirici = nil
        kapandiGeri = nil
    }
}

/// Panelin içeriği.
private struct PanelGorunumu: View {
    let grup: SeslenmeGrubu
    /// Yanıt seçildiyse onu, yanıtsız kapatıldıysa `nil` taşır.
    let secildi: (Yanit?) -> Void

    @State private var nabiz = false

    private var anaRenk: Color { grup.seviye.renk }

    /// Aynı kişiden birden çok çağrı birikmişse bunu söylemek gerekir; yoksa
    /// kullanıcı tek bir seslenmeye yanıt verdiğini sanır.
    private var altBaslik: String {
        grup.adet > 1 ? "\(grup.adet) KEZ SESLENDİ" : "SANA SESLENİYOR"
    }

    var body: some View {
        VStack(spacing: 18) {
            simgeSeridi

            VStack(spacing: 6) {
                Text(grup.gonderenAd.uppercased())
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)

                Text(altBaslik)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(anaRenk)
            }

            if !grup.not.isEmpty {
                Text("“\(grup.not)”")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .lineLimit(3)
            }

            HStack(spacing: 10) {
                ForEach(Yanit.allCases, id: \.self) { yanit in
                    Button {
                        secildi(yanit)
                    } label: {
                        Label(yanit.baslik, systemImage: yanit.simge)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(yanit == .geliyorum ? anaRenk : Color.secondary.opacity(0.5))
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 4)

            Button("Kapat") { secildi(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.vertical, 28)
        .frame(width: 560, height: 340)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(anaRenk.opacity(0.8), lineWidth: 3)
                }
        }
    }

    /// ACİL seviyede yanıp sönen ünlem şeridi; diğer seviyelerde tek simge.
    @ViewBuilder
    private var simgeSeridi: some View {
        if grup.seviye == .acil {
            HStack(spacing: 14) {
                ForEach(0..<5, id: \.self) { sira in
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.red)
                        .opacity(nabiz ? 1 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(sira) * 0.08),
                            value: nabiz
                        )
                }
            }
            .onAppear { nabiz = true }
        } else {
            Image(systemName: grup.seviye.simge)
                .font(.system(size: 40))
                .foregroundStyle(anaRenk)
        }
    }
}
