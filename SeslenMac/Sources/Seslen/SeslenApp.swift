import AppKit
import SwiftUI

@main
struct SeslenApp: App {
    @State private var ayarlar: Ayarlar
    @State private var istemci: SunucuIstemcisi
    @State private var uyari: UyariYoneticisi

    @NSApplicationDelegateAdaptor(UygulamaTemsilcisi.self) private var temsilci

    init() {
        let ayarlar = Ayarlar()
        let istemci = SunucuIstemcisi(ayarlar: ayarlar)
        let uyari = UyariYoneticisi(ayarlar: ayarlar)

        // İki yönlü bağ: gelen seslenme uyarıya, panelden verilen yanıt sunucuya gider.
        istemci.seslenmeGeldi = { [weak uyari] seslenme in
            uyari?.isle(seslenme)
        }
        uyari.yanitVerildi = { [weak istemci] cagriID, yanit in
            istemci?.yanitla(cagriID: cagriID, yanit: yanit)
        }

        _ayarlar = State(initialValue: ayarlar)
        _istemci = State(initialValue: istemci)
        _uyari = State(initialValue: uyari)
    }

    var body: some Scene {
        MenuBarExtra {
            AnaGorunum()
                .environment(ayarlar)
                .environment(istemci)
                .environment(uyari)
        } label: {
            MenuCubuguSimgesi(uyari: uyari, baglanti: istemci.baglanti)
        }
        .menuBarExtraStyle(.window)

        Window("Seslen Ayarları", id: PencereKimligi.ayarlar) {
            AyarlarPenceresi()
                .environment(ayarlar)
                .environment(istemci)
                .environment(uyari)
        }
        .defaultSize(width: 620, height: 560)
        .windowResizability(.contentMinSize)

        Window("Kurum Yönetimi", id: PencereKimligi.kurum) {
            KurumPenceresi()
                .environment(ayarlar)
                .environment(istemci)
        }
        .defaultSize(width: 720, height: 520)
        .windowResizability(.contentMinSize)
    }
}

/// Pencere kimlikleri tek yerde tutulur ki `openWindow(id:)` çağrıları yazım
/// hatasına açık olmasın.
enum PencereKimligi {
    static let ayarlar = "seslen-ayarlar"
    static let kurum = "seslen-kurum"
}

/// Menü çubuğunda görünen simge. Bekleyen seslenme varsa dikkat çeker.
///
/// Buradaki simge adı her zaman var olan bir SF Symbol olmalıdır: geçersiz bir ad
/// `Image(systemName:)` tarafından sessizce boş çizilir ve menü çubuğu öğesi
/// sıfır genişlikte, yani görünmez olur. Bu yüzden tek bir doğrulanmış ad
/// (`megaphone` / `megaphone.fill`) kullanıp durumu renk ve dolgu ile anlatıyoruz.
private struct MenuCubuguSimgesi: View {
    let uyari: UyariYoneticisi
    let baglanti: BaglantiDurumu

    var body: some View {
        if uyari.dikkatCekiyor {
            Image(systemName: "megaphone.fill")
                .symbolEffect(.pulse, options: .repeating)
                .foregroundStyle(.red)
        } else if baglanti.iyi {
            Image(systemName: "megaphone")
        } else {
            // Bağlantı yokken simge soluk görünür; kullanıcı durumu anlar.
            Image(systemName: "megaphone")
                .opacity(0.45)
        }
    }
}

/// Uygulamanın yaşam döngüsüyle ilgili işleri yürütür.
final class UygulamaTemsilcisi: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock'ta ikon görünmesin; Seslen yalnızca menü çubuğunda yaşar.
        // Info.plist'teki LSUIElement bunu zaten yapar, ancak paketlenmemiş
        // halde (`swift run`) çalışırken de aynı davranışı istiyoruz.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Ayarlar penceresi kapanınca uygulama kapanmamalı.
        false
    }
}
