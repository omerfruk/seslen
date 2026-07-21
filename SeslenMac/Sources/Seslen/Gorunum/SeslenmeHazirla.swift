import SwiftUI

/// Bir kişiye seslenirken seviye ve not seçilen ekran.
struct SeslenmeHazirla: View {
    let uye: Uye
    let geriDon: () -> Void

    @Environment(SunucuIstemcisi.self) private var istemci

    @State private var seviye: Seviye = .normal
    @State private var not: String = ""
    @FocusState private var notOdakta: Bool

    /// Kullanıcının gönderebileceği en yüksek seviye.
    private var yetkim: Seviye {
        istemci.ben?.maxSeviye ?? .normal
    }

    var body: some View {
        VStack(spacing: 0) {
            baslik
            Divider()

            VStack(alignment: .leading, spacing: 10) {
                if uye.etkinDurum == .mesgul {
                    mesgulSeridi
                }

                Text("Aciliyet")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Seviye.allCases, id: \.self) { secenek in
                    SeviyeSatiri(
                        seviye: secenek,
                        secili: seviye == secenek,
                        yetkiVar: yetkim.kapsar(secenek),
                        bekleyecek: uye.etkinDurum == .mesgul && secenek.mesguldeBekler
                    ) {
                        seviye = secenek
                    }
                }

                Text("Not (isteğe bağlı)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                TextField("örn. namaz kılalım mı?", text: $not)
                    .textFieldStyle(.roundedBorder)
                    .focused($notOdakta)
                    .onSubmit(gonder)
            }
            .padding(14)

            Divider()

            HStack {
                Button("Vazgeç", action: geriDon)
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button(action: gonder) {
                    Label("Seslen", systemImage: "megaphone.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!istemci.baglanti.iyi)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .onAppear { notOdakta = true }
    }

    /// Alıcı meşgulken ne olacağını önceden söyler. Yalnızca ipucu: düğmeler
    /// etkin kalır, gerçek karar sunucuda verilir.
    private var mesgulSeridi: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "clock.badge.checkmark")
            Text("\(uye.adSoyad) meşgul — normal ve önemli seslenmeler o müsait olana kadar bekler, ACİL hemen ulaşır.")
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.blue)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    private var baslik: some View {
        HStack(spacing: 10) {
            Button(action: geriDon) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)

            Circle()
                .fill(Color.accentColor.opacity(0.18))
                .frame(width: 26, height: 26)
                .overlay {
                    Text(uye.basHarfler).font(.system(size: 10, weight: .semibold))
                }

            VStack(alignment: .leading, spacing: 0) {
                Text(uye.adSoyad).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                // Üç durum da doğru yazılmalı: burada eskiden iki dallı bir
                // koşul vardı ve çevrimdışı üye "Müsait" görünüyordu.
                Text(uye.etkinDurum.baslik)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func gonder() {
        guard yetkim.kapsar(seviye) else { return }
        istemci.seslen(
            aliciID: uye.id,
            seviye: seviye,
            not: not.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        geriDon()
    }
}

/// Aciliyet seçeneklerinden biri. Yetki yoksa kilitli görünür.
private struct SeviyeSatiri: View {
    let seviye: Seviye
    let secili: Bool
    let yetkiVar: Bool
    /// Alıcı meşgul ve bu seviye bekletilecek mi? Açıklama satırını değiştirir,
    /// düğmeyi kilitlemez — kullanıcı yine de gönderebilmeli.
    var bekleyecek: Bool = false
    let secildi: () -> Void

    private var renk: Color { seviye.renk }

    private var aciklama: String {
        if !yetkiVar { return "Bu seviye için yetkiniz yok" }
        if bekleyecek { return "Meşgul — kuyrukta bekler, müsait olunca görür" }
        return seviye.aciklama
    }

    var body: some View {
        Button {
            guard yetkiVar else { return }
            secildi()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: yetkiVar ? seviye.simge : "lock.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(yetkiVar ? renk : .secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(seviye.baslik)
                        .font(.system(size: 12, weight: secili ? .semibold : .regular))
                    Text(aciklama)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if secili {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(renk)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(secili ? renk.opacity(0.14) : Color.primary.opacity(0.04))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(secili ? renk.opacity(0.5) : .clear, lineWidth: 1)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(yetkiVar ? 1 : 0.55)
    }
}
