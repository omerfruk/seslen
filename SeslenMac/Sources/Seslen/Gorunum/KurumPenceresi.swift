import AppKit
import SwiftUI

/// Kurum yönetimi penceresi. Yalnızca kurucu ve yöneticiler kullanabilir.
struct KurumPenceresi: View {
    @Environment(SunucuIstemcisi.self) private var istemci

    var body: some View {
        Group {
            if istemci.ben?.rol.yonetimYetkisi == true {
                icerik
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Bu sayfayı yalnızca yöneticiler görebilir")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 680, minHeight: 460)
    }

    private var icerik: some View {
        VStack(spacing: 0) {
            KatilimKoduSeridi()
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !istemci.bekleyen.isEmpty {
                        BekleyenlerBolumu()
                    }
                    UyelerBolumu()
                }
                .padding(18)
            }
        }
    }
}

// MARK: - Katılım kodu

private struct KatilimKoduSeridi: View {
    @Environment(SunucuIstemcisi.self) private var istemci
    @State private var kopyalandi = false
    @State private var yenilemeSoruluyor = false

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(istemci.kurum?.ad ?? "Kurum")
                    .font(.title3.bold())
                Text("\(istemci.uyeler.count) üye · \(istemci.uyeler.filter(\.cevrimici).count) çevrimiçi")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("KATILIM KODU")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Text(istemci.kurum?.katilimKodu ?? "—")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))

                    Button {
                        kopyala()
                    } label: {
                        Image(systemName: kopyalandi ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Kodu kopyala")

                    Button {
                        yenilemeSoruluyor = true
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Yeni kod üret")
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .confirmationDialog(
            "Katılım kodu yenilensin mi?",
            isPresented: $yenilemeSoruluyor
        ) {
            Button("Yenile", role: .destructive) { istemci.kodYenile() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Eski kod geçersiz olur. Henüz katılmamış kişilere yeni kodu iletmeniz gerekir.")
        }
    }

    private func kopyala() {
        guard let kod = istemci.kurum?.katilimKodu, !kod.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(kod, forType: .string)
        kopyalandi = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            kopyalandi = false
        }
    }
}

// MARK: - Onay bekleyenler

private struct BekleyenlerBolumu: View {
    @Environment(SunucuIstemcisi.self) private var istemci

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Onay bekleyenler (\(istemci.bekleyen.count))", systemImage: "person.badge.clock")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(Array(istemci.bekleyen.enumerated()), id: \.element.id) { sira, uye in
                    if sira > 0 { Divider() }
                    HStack {
                        Text(uye.adSoyad).font(.system(size: 13))
                        Spacer()
                        Button("Onayla") { istemci.uyeOnayla(uyeID: uye.id) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        Button("Reddet", role: .destructive) { istemci.uyeSil(uyeID: uye.id) }
                            .controlSize(.small)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
        }
    }
}

// MARK: - Üyeler

private struct UyelerBolumu: View {
    @Environment(SunucuIstemcisi.self) private var istemci
    @State private var silinecek: Uye?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Üyeler (\(istemci.uyeler.count))", systemImage: "person.3")
                .font(.headline)

            HStack(spacing: 0) {
                Text("Ad Soyad").frame(maxWidth: .infinity, alignment: .leading)
                Text("Rol").frame(width: 130, alignment: .leading)
                Text("Seslenme yetkisi").frame(width: 150, alignment: .leading)
                Color.clear.frame(width: 30)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)

            VStack(spacing: 0) {
                ForEach(Array(istemci.uyeler.enumerated()), id: \.element.id) { sira, uye in
                    if sira > 0 { Divider() }
                    UyeYonetimSatiri(uye: uye) { silinecek = uye }
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        }
        .confirmationDialog(
            "\(silinecek?.adSoyad ?? "") kurumdan çıkarılsın mı?",
            isPresented: Binding(get: { silinecek != nil }, set: { if !$0 { silinecek = nil } })
        ) {
            Button("Çıkar", role: .destructive) {
                if let silinecek { istemci.uyeSil(uyeID: silinecek.id) }
                silinecek = nil
            }
            Button("Vazgeç", role: .cancel) { silinecek = nil }
        } message: {
            Text("Bağlantısı hemen kesilir ve tekrar katılmak için yeni bir katılım kodu girmesi gerekir.")
        }
    }
}

/// Üye listesindeki tek satır: rol ve yetki burada değiştirilir.
private struct UyeYonetimSatiri: View {
    let uye: Uye
    let sil: () -> Void

    @Environment(SunucuIstemcisi.self) private var istemci

    /// Kurucu üzerinde işlem yapılamaz; sunucu da bunu reddeder.
    private var kilitli: Bool { uye.rol == .kurucu }
    private var benMiyim: Bool { uye.id == istemci.ben?.id }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(uye.cevrimici ? Color.green : Color.gray.opacity(0.5))
                    .frame(width: 7, height: 7)
                Text(uye.adSoyad).font(.system(size: 13))
                if benMiyim {
                    Text("siz")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if kilitli {
                    Text(uye.rol.baslik).font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    Picker("", selection: Binding(
                        get: { uye.rol },
                        set: { istemci.uyeGuncelle(uyeID: uye.id, rol: $0, maxSeviye: uye.maxSeviye) }
                    )) {
                        Text(Rol.uye.baslik).tag(Rol.uye)
                        Text(Rol.yonetici.baslik).tag(Rol.yonetici)
                    }
                    .labelsHidden()
                    .controlSize(.small)
                }
            }
            .frame(width: 130, alignment: .leading)

            Group {
                if kilitli {
                    Text(uye.maxSeviye.baslik).font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    Picker("", selection: Binding(
                        get: { uye.maxSeviye },
                        set: { istemci.uyeGuncelle(uyeID: uye.id, rol: uye.rol, maxSeviye: $0) }
                    )) {
                        ForEach(Seviye.allCases, id: \.self) { seviye in
                            Text("\(seviye.baslik)'e kadar").tag(seviye)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                }
            }
            .frame(width: 150, alignment: .leading)

            Group {
                if kilitli {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary.opacity(0.5))
                } else {
                    Button(action: sil) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .help("Kurumdan çıkar")
                }
            }
            .frame(width: 30)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}
