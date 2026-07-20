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
    private var kapatmaGorevi: Task<Void, Never>?

    /// Panel şu anda ekranda mı?
    var acik: Bool { pencere != nil }

    /// Paneli gösterir. `yanitla` bir düğmeye basılınca, `kapandi` panel
    /// her kapandığında (yanıtla ya da süre dolarak) çağrılır.
    func goster(
        seslenme: Seslenme,
        otomatikKapanma: TimeInterval,
        yanitla: @escaping (Yanit) -> Void,
        kapandi: @escaping () -> Void
    ) {
        kapat()

        let icerik = PanelGorunumu(
            seslenme: seslenme,
            yanitSecildi: { [weak self] yanit in
                yanitla(yanit)
                self?.kapat()
                kapandi()
            },
            kapat: { [weak self] in
                self?.kapat()
                kapandi()
            }
        )

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
        pencere.contentView = NSHostingView(rootView: icerik)
        pencere.center()
        pencere.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.pencere = pencere

        if otomatikKapanma > 0 {
            kapatmaGorevi = Task { [weak self] in
                try? await Task.sleep(for: .seconds(otomatikKapanma))
                guard !Task.isCancelled else { return }
                self?.kapat()
                kapandi()
            }
        }
    }

    /// Paneli kapatır.
    func kapat() {
        kapatmaGorevi?.cancel()
        kapatmaGorevi = nil
        pencere?.orderOut(nil)
        pencere = nil
    }
}

/// Panelin içeriği.
private struct PanelGorunumu: View {
    let seslenme: Seslenme
    let yanitSecildi: (Yanit) -> Void
    let kapat: () -> Void

    @State private var nabiz = false

    private var anaRenk: Color { seslenme.seviye.renk }

    var body: some View {
        VStack(spacing: 18) {
            simgeSeridi

            VStack(spacing: 6) {
                Text(seslenme.gonderenAd.uppercased())
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)

                Text("SANA SESLENİYOR")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(anaRenk)
            }

            if !seslenme.not.isEmpty {
                Text("“\(seslenme.not)”")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .lineLimit(3)
            }

            HStack(spacing: 10) {
                ForEach(Yanit.allCases, id: \.self) { yanit in
                    Button {
                        yanitSecildi(yanit)
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

            Button("Kapat", action: kapat)
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
        if seslenme.seviye == .acil {
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
            Image(systemName: seslenme.seviye.simge)
                .font(.system(size: 40))
                .foregroundStyle(anaRenk)
        }
    }
}
