#!/usr/bin/env swift
// Seslen uygulama ikonunu üretir.
//
// Dışarıdan tasarım dosyası gerektirmemesi için ikon tamamen programlı çizilir:
// eğimli bir megafon ve ağzından yayılan üç ses dalgası. Üretilen .iconset
// klasörü `iconutil` ile .icns'e çevrilir (bkz. dagitim/paketle.sh).
//
// Kullanım: swift dagitim/ikon-uret.swift <cikis-klasoru>

import AppKit

let cikisYolu = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Seslen.iconset"
let klasor = URL(fileURLWithPath: cikisYolu)
try? FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)

/// macOS'un beklediği iconset dosya adları ve piksel boyutları.
let boyutlar: [(ad: String, piksel: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

/// İkonun yerleşimini birim kare (0…1) içinde tanımlar; böylece her boyutta
/// aynı oranlar korunur.
///
/// Megafon gövdesi için Apple'ın `megaphone.fill` simgesi kullanılır: elle
/// çizilen bir koni bu ölçekte kolayca kalkana benziyor, hazır simge ise her
/// boyutta doğru okunuyor. Ses dalgaları simgede olmadığı için elle ekleniyor.
enum Cizim {
    /// Simgenin eğim açısı (derece). Hafif yukarı bakması ikonu canlandırır.
    static let egim: CGFloat = -15

    /// Megafon gövdesinin merkezi ve genişliği.
    static let govdeMerkezi = NSPoint(x: 0.375, y: 0.50)
    static let govdeGenisligi: CGFloat = 0.44

    /// Ses dalgalarının yayıldığı merkez. Yarıçaplar, yayların megafonun
    /// ağzının sağında kalıp gövdenin arkasında kaybolmayacağı şekilde seçildi.
    static let dalgaMerkezi = NSPoint(x: 0.50, y: 0.50)

    /// Megafon ağzından yayılan üç yay.
    static func dalgaYollari() -> [(yol: NSBezierPath, kalinlik: CGFloat)] {
        [0.145, 0.205, 0.265].map { yaricap in
            let yay = NSBezierPath()
            yay.appendArc(
                withCenter: dalgaMerkezi,
                radius: yaricap,
                startAngle: -40,
                endAngle: 40
            )
            return (yay, 0.038)
        }
    }
}

/// Verilen kenar uzunluğunda tek bir ikon karesi çizer.
func ikonCiz(kenar: Int) -> Data? {
    let olcu = CGFloat(kenar)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: kenar, pixelsHigh: kenar,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    defer { NSGraphicsContext.restoreGraphicsState() }

    // macOS ikon ızgarasında simge, tuvalin kenarlarına yapışmaz.
    let bosluk = olcu * 0.055
    let govde = NSRect(x: bosluk, y: bosluk, width: olcu - bosluk * 2, height: olcu - bosluk * 2)
    let koseYaricap = govde.width * 0.2237  // Apple'ın "squircle" oranına yakın

    // --- Arka plan ---
    let arkaYol = NSBezierPath(roundedRect: govde, xRadius: koseYaricap, yRadius: koseYaricap)
    NSGradient(colors: [
        NSColor(srgbRed: 0.29, green: 0.51, blue: 1.00, alpha: 1),  // canlı mavi
        NSColor(srgbRed: 0.35, green: 0.30, blue: 0.95, alpha: 1),
        NSColor(srgbRed: 0.52, green: 0.20, blue: 0.86, alpha: 1),  // mor
    ])?.draw(in: arkaYol, angle: -68)

    NSGraphicsContext.saveGraphicsState()
    arkaYol.addClip()

    // Üstte yumuşak bir parlaklık, düz rengi kırar.
    NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.26),
        NSColor.white.withAlphaComponent(0.0),
    ])?.draw(in: NSRect(x: govde.minX, y: govde.midY - govde.height * 0.04,
                        width: govde.width, height: govde.height * 0.54), angle: -90)

    // --- Megafon ---
    // Birim kare koordinatlarını gerçek piksel boyutuna taşıyan dönüşüm.
    let olcek = NSAffineTransform()
    olcek.translateX(by: govde.minX, yBy: govde.minY)
    olcek.scale(by: govde.width)

    // Bütün simgeyi hafifçe döndürerek hareket hissi veriyoruz.
    let dondur = NSAffineTransform()
    dondur.translateX(by: 0.5, yBy: 0.5)
    dondur.rotate(byDegrees: Cizim.egim)
    dondur.translateX(by: -0.5, yBy: -0.5)

    func yerlestir(_ yol: NSBezierPath) -> NSBezierPath {
        let kopya = yol.copy() as! NSBezierPath
        kopya.transform(using: dondur as AffineTransform)
        kopya.transform(using: olcek as AffineTransform)
        return kopya
    }

    // Derinlik için simgenin altına yumuşak bir gölge.
    let golge = NSShadow()
    golge.shadowColor = NSColor.black.withAlphaComponent(0.20)
    golge.shadowBlurRadius = govde.width * 0.032
    golge.shadowOffset = NSSize(width: 0, height: -govde.width * 0.016)
    golge.set()

    // Ses dalgaları: ağızdan uzaklaştıkça soluklaşır.
    for (sira, dalga) in Cizim.dalgaYollari().enumerated() {
        let yerlesik = yerlestir(dalga.yol)
        yerlesik.lineWidth = dalga.kalinlik * govde.width
        yerlesik.lineCapStyle = .round
        NSColor.white.withAlphaComponent(1.0 - CGFloat(sira) * 0.28).setStroke()
        yerlesik.stroke()
    }

    // Megafon gövdesi: hazır simgeyi beyaz olarak, döndürülmüş halde çiziyoruz.
    let simgeOlcu = govde.width * Cizim.govdeGenisligi
    let yapilandirma = NSImage.SymbolConfiguration(pointSize: simgeOlcu, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let simge = NSImage(systemSymbolName: "megaphone.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(yapilandirma) {

        let merkez = yerlestir({
            let n = NSBezierPath()
            n.move(to: Cizim.govdeMerkezi)
            return n
        }()).currentPoint

        let boyut = simge.size
        let hedef = NSRect(
            x: merkez.x - boyut.width / 2,
            y: merkez.y - boyut.height / 2,
            width: boyut.width, height: boyut.height
        )

        // Simgeyi kendi merkezi etrafında eğiyoruz.
        NSGraphicsContext.saveGraphicsState()
        let simgeDondur = NSAffineTransform()
        simgeDondur.translateX(by: merkez.x, yBy: merkez.y)
        simgeDondur.rotate(byDegrees: Cizim.egim)
        simgeDondur.translateX(by: -merkez.x, yBy: -merkez.y)
        simgeDondur.concat()
        simge.draw(in: hedef, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
    }

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])
}

for (ad, piksel) in boyutlar {
    guard let veri = ikonCiz(kenar: piksel) else {
        FileHandle.standardError.write("ikon çizilemedi: \(ad)\n".data(using: .utf8)!)
        exit(1)
    }
    try veri.write(to: klasor.appendingPathComponent("\(ad).png"))
}

print("ikonset hazır: \(klasor.path)")
