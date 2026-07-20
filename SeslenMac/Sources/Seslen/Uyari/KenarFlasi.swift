import AppKit
import SwiftUI

/// Ekranın kenarlarında kırmızı bir flaş oluşturur.
/// Tıklamaları geçirir, hiçbir pencereyi engellemez; sesi kapalı olan
/// kullanıcının bile gözünden kaçmaz.
@MainActor
final class KenarFlasi {
    private var pencereler: [NSWindow] = []
    private var kapatmaGorevi: Task<Void, Never>?

    /// Tüm ekranların kenarlarını belirtilen süre boyunca yakıp söndürür.
    func goster(sure: TimeInterval = 3.0) {
        kapat()

        for ekran in NSScreen.screens {
            let pencere = NSWindow(
                contentRect: ekran.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            pencere.isOpaque = false
            pencere.backgroundColor = .clear
            pencere.hasShadow = false
            // Tam ekran uygulamaların bile üstünde kalsın.
            pencere.level = .screenSaver
            pencere.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
            // Kritik: fare olaylarını geçirir, kullanıcının işini kesmez.
            pencere.ignoresMouseEvents = true
            pencere.contentView = NSHostingView(rootView: KenarGorunumu())
            pencere.setFrame(ekran.frame, display: true)
            pencere.orderFrontRegardless()
            pencereler.append(pencere)
        }

        kapatmaGorevi = Task { [weak self] in
            try? await Task.sleep(for: .seconds(sure))
            guard !Task.isCancelled else { return }
            self?.kapat()
        }
    }

    /// Flaşı hemen durdurur.
    func kapat() {
        kapatmaGorevi?.cancel()
        kapatmaGorevi = nil
        for pencere in pencereler {
            pencere.orderOut(nil)
        }
        pencereler.removeAll()
    }
}

/// Ekran kenarında nabız gibi atan kırmızı çerçeve.
private struct KenarGorunumu: View {
    @State private var parlak = false

    /// Çerçevenin ekran içine doğru sönümlendiği kalınlık.
    private let kalinlik: CGFloat = 90

    var body: some View {
        GeometryReader { olcu in
            ZStack {
                kenar(.top, olcu.size)
                kenar(.bottom, olcu.size)
                kenar(.leading, olcu.size)
                kenar(.trailing, olcu.size)
            }
            .opacity(parlak ? 1 : 0.25)
            .animation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true), value: parlak)
        }
        .ignoresSafeArea()
        .onAppear { parlak = true }
    }

    @ViewBuilder
    private func kenar(_ yon: Edge, _ boyut: CGSize) -> some View {
        let renkler = [Color.red.opacity(0.85), Color.red.opacity(0)]
        switch yon {
        case .top:
            LinearGradient(colors: renkler, startPoint: .top, endPoint: .bottom)
                .frame(height: kalinlik)
                .frame(maxHeight: .infinity, alignment: .top)
        case .bottom:
            LinearGradient(colors: renkler, startPoint: .bottom, endPoint: .top)
                .frame(height: kalinlik)
                .frame(maxHeight: .infinity, alignment: .bottom)
        case .leading:
            LinearGradient(colors: renkler, startPoint: .leading, endPoint: .trailing)
                .frame(width: kalinlik)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .trailing:
            LinearGradient(colors: renkler, startPoint: .trailing, endPoint: .leading)
                .frame(width: kalinlik)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
