import SwiftUI

/// Menü panelinde açık anketi ve canlı sonucunu gösteren kart.
///
/// Sonuç bilerek ayrı bir pencerede değil burada: uygulama `.accessory`
/// kipinde olduğu için pencere açmak `NSApp.activate` gerektirir ve kullanıcıyı
/// yaptığı işten koparır — "kim çay ister" için orantısız. Balon da uygun değil,
/// beş dakika boyunca her şeyin üstünde duran canlı bir kutu olurdu.
///
/// Kart hem gönderende hem alıcılarda görünür: balonu oy vermeden kapatan
/// kişinin ankete ulaşmasının yolu budur.
struct AnketSonucGorunumu: View {
    let anket: Anket
    let benimID: String?
    let oyVer: (Int) -> Void
    let bitir: () -> Void

    private var benimAnketim: Bool { anket.gonderenID == benimID }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ustSerit

            ForEach(anket.secenekler.indices, id: \.self) { dizin in
                secenekSatiri(dizin)
            }

            altSerit
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.teal.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.teal.opacity(0.35), lineWidth: 1)
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var ustSerit: some View {
        HStack(spacing: 6) {
            Image(systemName: "checklist")
                .font(.system(size: 11))
                .foregroundStyle(.teal)

            Text(anket.soru)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            if benimAnketim, anket.acik {
                Button("Bitir", action: bitir)
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.teal)
            }
        }
    }

    private func secenekSatiri(_ dizin: Int) -> some View {
        let secili = anket.benimOyum == dizin
        let sayi = anket.sayimlar.indices.contains(dizin) ? anket.sayimlar[dizin] : 0

        return Button {
            guard anket.acik else { return }
            oyVer(dizin)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: secili ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 10))
                    .foregroundStyle(secili ? .teal : .secondary)

                Text(anket.secenekler[dizin])
                    .font(.system(size: 11, weight: secili ? .semibold : .regular))
                    .lineLimit(1)

                Spacer(minLength: 6)

                // Çubuk genişliği GeometryReader'sız, sabit genişlik × oranla
                // hesaplanır: projenin ölçmek yerine hesaplama alışkanlığı.
                Capsule()
                    .fill(Color.teal.opacity(secili ? 0.85 : 0.45))
                    .frame(width: max(2, 96 * anket.oran(dizin)), height: 6)

                Text("\(sayi)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, alignment: .trailing)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!anket.acik)
    }

    private var altSerit: some View {
        HStack(spacing: 4) {
            Text(anket.kapandi
                ? anket.ozet
                : "\(anket.katilan)/\(anket.beklenen) yanıtladı")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if anket.acik {
                // Geri sayım saat tıkırtısında yenilenmeli; yoksa süre dolduğunda
                // kart sessizce açık kalır.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(kalanSure)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.teal)
                        .monospacedDigit()
                }
            } else {
                Text("Kapandı")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var kalanSure: String {
        let kalan = max(0, Int(anket.bitis.timeIntervalSinceNow))
        return String(format: "%d:%02d", kalan / 60, kalan % 60)
    }
}
