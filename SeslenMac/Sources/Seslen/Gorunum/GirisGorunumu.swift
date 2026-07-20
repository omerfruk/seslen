import SwiftUI

/// İlk açılışta görünen ekran: ya yeni kurum kurulur ya da koda katılınır.
struct GirisGorunumu: View {
    @Environment(Ayarlar.self) private var ayarlar
    @Environment(SunucuIstemcisi.self) private var istemci

    private enum Kip: String, CaseIterable {
        case katil = "Kuruma Katıl"
        case olustur = "Kurum Oluştur"
    }

    @State private var kip: Kip = .katil
    @State private var adSoyad = ""
    @State private var katilimKodu = ""
    @State private var kurumAd = ""
    @State private var calisiyor = false
    @State private var hata: String?

    var body: some View {
        @Bindable var ayarlar = ayarlar

        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.tint)
                Text("Seslen")
                    .font(.title3.bold())
                Text("Kulaklıklı ekipler için sessiz seslenme")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)

            Picker("", selection: $kip) {
                ForEach(Kip.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(spacing: 8) {
                TextField("Ad Soyad", text: $adSoyad)

                switch kip {
                case .katil:
                    TextField("Katılım kodu (örn. ABC-123)", text: $katilimKodu)
                        .textCase(.uppercase)
                case .olustur:
                    TextField("Kurum adı", text: $kurumAd)
                }

                DisclosureGroup("Sunucu adresi") {
                    TextField("http://localhost:8787", text: $ayarlar.sunucuAdresi)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.top, 4)
                    Text("Yerel testte `http://localhost:8787`, ofis ağında sunucunun IP adresi.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
                .padding(.top, 2)
            }
            .textFieldStyle(.roundedBorder)

            if let hata {
                Text(hata)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onayla) {
                if calisiyor {
                    ProgressView().controlSize(.small)
                } else {
                    Text(kip == .katil ? "Katıl" : "Oluştur").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(calisiyor || !girdilerGecerli)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(18)
    }

    private var girdilerGecerli: Bool {
        let ad = adSoyad.trimmingCharacters(in: .whitespaces)
        guard ad.count >= 3 else { return false }
        switch kip {
        case .katil: return katilimKodu.trimmingCharacters(in: .whitespaces).count >= 6
        case .olustur: return kurumAd.trimmingCharacters(in: .whitespaces).count >= 2
        }
    }

    private func onayla() {
        calisiyor = true
        hata = nil
        Task {
            do {
                switch kip {
                case .katil:
                    try await istemci.kurumaKatil(
                        kod: katilimKodu.trimmingCharacters(in: .whitespaces).uppercased(),
                        adSoyad: adSoyad.trimmingCharacters(in: .whitespaces)
                    )
                case .olustur:
                    try await istemci.kurumOlustur(
                        kurumAd: kurumAd.trimmingCharacters(in: .whitespaces),
                        kurucuAd: adSoyad.trimmingCharacters(in: .whitespaces)
                    )
                }
            } catch {
                hata = error.localizedDescription
            }
            calisiyor = false
        }
    }
}
