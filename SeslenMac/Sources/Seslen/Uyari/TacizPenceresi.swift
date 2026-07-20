import AppKit
import SwiftUI

/// Kenarlıksız pencerelerin klavye odağı alabilmesi için gereken alt sınıf.
private final class TacizPencereKabi: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Taciz seviyesindeki çağrılar için ekranı kaplayan, yalnızca yanıt verilince
/// kapanan uyarı.
///
/// Geri sayım ve "imha" metni kasten şakadır. Tam da bu yüzden pencerenin en
/// üstünde her zaman Seslen başlığı ve kimin çağırdığı yazar: şaka olduğu
/// anlaşılmayan bir tam ekran geri sayım kullanıcıyı gerçekten korkutur,
/// kurumsal bir makinede fidye yazılımı sanılıp güvenlik ihbarına yol açar.
@MainActor
final class TacizPenceresi {
    private var pencere: NSWindow?
    private var barindirici: NSHostingView<TacizGorunumu>?
    private var yanitlandiGeri: ((Yanit) -> Void)?
    private var siddet: Double = 0.8

    /// Pencere şu anda ekranda mı?
    var acik: Bool { pencere != nil }

    /// Pencereyi açar ve alarmı başlatır.
    func goster(grup: SeslenmeGrubu, siddet: Double, yanitlandi: @escaping (Yanit) -> Void) {
        kapat()

        yanitlandiGeri = yanitlandi
        self.siddet = siddet

        let barindirici = NSHostingView(rootView: gorunum(grup))
        let cerceve = (NSScreen.main ?? NSScreen.screens.first)?.frame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let pencere = TacizPencereKabi(
            contentRect: cerceve,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        pencere.isOpaque = false
        pencere.backgroundColor = .clear
        // Panel ve kenar flaşıyla aynı seviye: tam ekran uygulamaların ve
        // Rahatsız Etmeyin kipinin üstünde görünür.
        pencere.level = .screenSaver
        pencere.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        pencere.contentView = barindirici
        pencere.setFrame(cerceve, display: true)
        pencere.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.barindirici = barindirici
        self.pencere = pencere

        SesCalar.tacizBaslat(siddet: siddet)
    }

    /// Açık pencerenin içeriğini tazeler. Aynı kişiden yeni bir taciz çağrısı
    /// geldiğinde pencereyi kapatıp yeniden açmak geri sayımı sıfırlar ve
    /// alarmı bir an kesintiye uğratır; onun yerine sayaç yerinde artar.
    func tazele(_ grup: SeslenmeGrubu) {
        barindirici?.rootView = gorunum(grup)
    }

    private func gorunum(_ grup: SeslenmeGrubu) -> TacizGorunumu {
        TacizGorunumu(grup: grup, yanitSecildi: { [weak self] yanit in
            guard let self else { return }
            let geri = self.yanitlandiGeri
            self.kapat()
            geri?(yanit)
        })
    }

    /// Pencereyi kapatır ve alarmı susturur. Geri bildirim çağrılmaz.
    func kapat() {
        SesCalar.tacizDurdur()
        pencere?.orderOut(nil)
        pencere = nil
        barindirici = nil
        yanitlandiGeri = nil
    }
}

/// Taciz penceresinin içeriği.
private struct TacizGorunumu: View {
    let grup: SeslenmeGrubu
    let yanitSecildi: (Yanit) -> Void

    /// Şaka geri sayımının başlangıcı.
    private static let baslangic = 60

    @State private var kalan = TacizGorunumu.baslangic
    @State private var nabiz = false

    private var anaRenk: Color { Seviye.taciz.renk }

    var body: some View {
        ZStack {
            // Ekranı karartıyoruz ama tamamen kapatmıyoruz: kullanıcı arkada ne
            // yaptığını görebilmeli, uyarı ekranı ele geçirmiş gibi durmamalı.
            Rectangle()
                .fill(.black.opacity(0.55))
                .ignoresSafeArea()

            VStack(spacing: 26) {
                seslenBasligi
                cagiranKisi
                geriSayim
                yanitDugmeleri
            }
            .padding(44)
            .frame(maxWidth: 640)
            .background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(anaRenk, lineWidth: 4)
                    }
            }
        }
        .task {
            nabiz = true
            // Sayaç sıfırda durur; pencere kapanmaz. Kapanması yanıt vermeye
            // bağlı olmasaydı taciz olmazdı.
            while kalan > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                kalan -= 1
            }
        }
    }

    /// Uyarının kimden geldiğini söyleyen başlık. Her zaman en üstte durur ki
    /// pencere bir an bile kimliği belirsiz görünmesin.
    private var seslenBasligi: some View {
        HStack(spacing: 8) {
            Image(systemName: "megaphone.fill")
            Text("SESLEN")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .tracking(3)
            Spacer()
            Text("TACİZ MODU")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(anaRenk)
        }
        .foregroundStyle(.secondary)
    }

    private var cagiranKisi: some View {
        VStack(spacing: 10) {
            Image(systemName: Seviye.taciz.simge)
                .font(.system(size: 46))
                .foregroundStyle(anaRenk)
                .opacity(nabiz ? 1 : 0.35)
                .animation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true), value: nabiz)

            Text(grup.gonderenAd.uppercased())
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .lineLimit(2)

            Text(grup.adet > 1 ? "SENİ \(grup.adet) KEZ ÇAĞIRDI" : "SENİ ÇAĞIRIYOR")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .tracking(2)
                .foregroundStyle(anaRenk)

            if !grup.not.isEmpty {
                Text("“\(grup.not)”")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
    }

    private var geriSayim: some View {
        VStack(spacing: 6) {
            Text(kalan > 0 ? "\(kalan)" : "0")
                .font(.system(size: 64, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(anaRenk)

            Text(kalan > 0
                 ? "saniye içinde bu bilgisayar imha edilecek"
                 : "İmha iptal edildi. Ama o hâlâ bekliyor.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("şaka — sadece yanıt verilene kadar kapanmaz")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(anaRenk.opacity(0.10))
        }
    }

    private var yanitDugmeleri: some View {
        HStack(spacing: 10) {
            ForEach(Yanit.allCases, id: \.self) { yanit in
                Button {
                    yanitSecildi(yanit)
                } label: {
                    Label(yanit.baslik, systemImage: yanit.simge)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(yanit == .geliyorum ? anaRenk : Color.secondary.opacity(0.5))
            }
        }
    }
}
