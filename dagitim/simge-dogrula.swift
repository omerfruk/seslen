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

/// `simge` özelliklerinin gövdesindeki çıplak dizgileri yakalar.
///
/// `Seviye.simge` gibi hesaplanan özellikler adı `switch` içinde döndürür ve
/// çağrı yerine değişken olarak geçer (`Image(systemName: seviye.simge)`).
/// Yalnızca birinci desene bakılsaydı bu adların hiçbiri denetlenmezdi —
/// oysa menü çubuğunu görünmez yapan hata tam olarak buradan gelmişti.
let dizgiDeseni = try! NSRegularExpression(pattern: #""([^"]+)""#)

/// Satırın gövdesi olan bir `simge` özelliğini açıp açmadığını söyler.
///
/// Süslü parantez şartı önemlidir: `BalonOgesi.simge` gibi saklanan özellikler
/// de "var simge: String" biçimindedir ama gövdeleri yoktur. Onları blok
/// başlangıcı saymak, taramayı dosyanın geri kalanına taşırıp alakasız
/// dizgileri simge sanmaya yol açar.
func simgeOzelligiMi(_ satir: String) -> Bool {
    let kirpik = satir.trimmingCharacters(in: .whitespaces)
    guard kirpik.contains("simge"), kirpik.contains("String"), kirpik.contains("{") else {
        return false
    }
    return kirpik.hasPrefix("var ") || kirpik.hasPrefix("func ")
        || kirpik.hasPrefix("private var ") || kirpik.hasPrefix("private func ")
        || kirpik.hasPrefix("static var ") || kirpik.hasPrefix("static func ")
}

/// Bir `simge` özelliğinin gövdesindeki tüm dizgileri toplar.
func simgeAdlariniTopla(_ icerik: String) -> Set<String> {
    var bulunanlar = Set<String>()
    var derinlik = 0
    var icerideyiz = false

    for satir in icerik.split(separator: "\n", omittingEmptySubsequences: false) {
        let metin = String(satir)

        if !icerideyiz, simgeOzelligiMi(metin) {
            icerideyiz = true
            derinlik = 0
        }
        guard icerideyiz else { continue }

        let aralik = NSRange(metin.startIndex..., in: metin)
        for eslesme in dizgiDeseni.matches(in: metin, range: aralik) {
            if let r = Range(eslesme.range(at: 1), in: metin) {
                bulunanlar.insert(String(metin[r]))
            }
        }

        derinlik += metin.filter { $0 == "{" }.count
        derinlik -= metin.filter { $0 == "}" }.count
        // Açılış satırındaki süslü parantez kapandığında özellik bitmiştir.
        if derinlik <= 0, metin.contains("}") { icerideyiz = false }
    }
    return bulunanlar
}

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
    adlar.formUnion(simgeAdlariniTopla(icerik))
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
