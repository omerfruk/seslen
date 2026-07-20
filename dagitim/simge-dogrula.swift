#!/usr/bin/env swift
// Kaynak kodda kullanılan tüm SF Symbol adlarının gerçekten var olduğunu doğrular.
//
// Neden gerekli: `Image(systemName:)` geçersiz bir ada sessizce boş çizim yapar.
// Menü çubuğu simgesinde bu, öğenin sıfır genişlikte — yani tamamen görünmez —
// olmasına yol açar ve hiçbir hata mesajı vermez. Bu betik paketleme sırasında
// çalışır ve böyle bir adı derlemeden önce yakalar.
//
// Kullanım: swift dagitim/simge-dogrula.swift <kaynak-klasoru>

import AppKit
import Foundation

let kaynakYolu = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "SeslenMac/Sources"
let kok = URL(fileURLWithPath: kaynakYolu)

/// `systemName: "..."`, `systemImage: "..."` ve `systemSymbolName: "..."` yakalar.
let desen = try! NSRegularExpression(
    pattern: #"system(?:Name|Image|SymbolName):\s*"([^"]+)""#
)

var adlar = Set<String>()

guard let gezgin = FileManager.default.enumerator(at: kok, includingPropertiesForKeys: nil) else {
    FileHandle.standardError.write("kaynak klasörü okunamadı: \(kok.path)\n".data(using: .utf8)!)
    exit(1)
}

for durum in gezgin {
    guard let dosya = durum as? URL, dosya.pathExtension == "swift" else { continue }
    guard let icerik = try? String(contentsOf: dosya, encoding: .utf8) else { continue }

    let aralik = NSRange(icerik.startIndex..., in: icerik)
    for eslesme in desen.matches(in: icerik, range: aralik) {
        if let r = Range(eslesme.range(at: 1), in: icerik) {
            adlar.insert(String(icerik[r]))
        }
    }
}

var eksikler: [String] = []
for ad in adlar.sorted() where NSImage(systemSymbolName: ad, accessibilityDescription: nil) == nil {
    eksikler.append(ad)
}

if eksikler.isEmpty {
    print("✅ \(adlar.count) SF Symbol adının tamamı geçerli")
    exit(0)
}

FileHandle.standardError.write("""
❌ Geçersiz SF Symbol adı bulundu:
\(eksikler.map { "   - \($0)" }.joined(separator: "\n"))

Bu adlar sessizce boş çizilir. Menü çubuğunda kullanılırsa simge hiç görünmez.

""".data(using: .utf8)!)
exit(1)
