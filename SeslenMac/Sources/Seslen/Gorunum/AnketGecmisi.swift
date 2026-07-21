import SwiftUI

/// Bitmiş anketlerin listelendiği ekran.
///
/// Biten anket panelde durmaz — zamanı geçmiş bir anketi tek tek temizlemek
/// zorunda kalmak şikayet konusuydu. Sonucu merak eden buraya bakar. Anketler
/// ve oylar sunucuda kalıcı olduğu için geçmiş uygulama kapansa da durur.
struct AnketGecmisi: View {
    let geriDon: () -> Void

    @Environment(SunucuIstemcisi.self) private var istemci

    var body: some View {
        VStack(spacing: 0) {
            baslik
            Divider()

            if istemci.anketGecmisi.isEmpty {
                bosListe
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(istemci.anketGecmisi) { anket in
                            AnketSonucGorunumu(
                                anket: anket,
                                benimID: istemci.ben?.id,
                                oyVer: { istemci.anketOyVer(anketID: anket.id, secenek: $0) },
                                bitir: { istemci.anketBitir(anketID: anket.id) },
                                gizle: nil
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 120, maxHeight: 420)
            }
        }
        // Ekran her açılışta tazelenir: son anket sen bakmadan önce bitmiş olabilir.
        .onAppear { istemci.anketGecmisiniIste() }
    }

    private var baslik: some View {
        HStack(spacing: 10) {
            Button(action: geriDon) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)

            Circle()
                .fill(Color.teal.opacity(0.18))
                .frame(width: 26, height: 26)
                .overlay {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11))
                        .foregroundStyle(.teal)
                }

            VStack(alignment: .leading, spacing: 0) {
                Text("Anket geçmişi").font(.system(size: 13, weight: .semibold))
                Text("son \(istemci.anketGecmisi.count) anket")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var bosListe: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("Henüz anket açılmamış")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}
