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
                Text("Aciliyet")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Seviye.allCases, id: \.self) { secenek in
                    SeviyeSatiri(
                        seviye: secenek,
                        secili: seviye == secenek,
                        yetkiVar: yetkim.kapsar(secenek)
                    ) {
                        seviye = secenek
                    }
                }

                Text("Not (isteğe bağlı)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                TextField("örn. kahve içelim mi?", text: $not)
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
                Text(uye.etkinDurum == .mesgul ? "Meşgul" : "Müsait")
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
    let secildi: () -> Void

    private var renk: Color {
        switch seviye {
        case .normal: .blue
        case .onemli: .orange
        case .acil: .red
        }
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
                    Text(yetkiVar ? seviye.aciklama : "Bu seviye için yetkiniz yok")
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
