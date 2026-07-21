import SwiftUI

/// Seslenme ve anket geçmişinin birlikte tutulduğu ekran.
///
/// İkisi tek ekranda çünkü panelin üst şeridi zaten dolu; ayrı düğmeler
/// eklemek şeridi kalabalıklaştırırdı. Biten anket ve okunmuş seslenme
/// panelde durmaz — "zamanı geçti" — merak eden buraya bakar.
struct Gecmis: View {
    let geriDon: () -> Void

    @Environment(SunucuIstemcisi.self) private var istemci

    @State private var sekme: Sekme = .seslenmeler

    enum Sekme: String, CaseIterable, Identifiable {
        case seslenmeler = "Seslenmeler"
        case anketler = "Anketler"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            baslik
            Divider()

            Picker("", selection: $sekme) {
                ForEach(Sekme.allCases) { secenek in
                    Text(secenek.rawValue).tag(secenek)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            switch sekme {
            case .seslenmeler: seslenmeListesi
            case .anketler: anketListesi
            }
        }
        // Her açılışta tazelenir: geçmiş sen bakmadan önce değişmiş olabilir.
        .onAppear(perform: tazele)
        .onChange(of: sekme) { _, _ in tazele() }
    }

    private func tazele() {
        switch sekme {
        case .seslenmeler: istemci.cagriGecmisiniIste()
        case .anketler: istemci.anketGecmisiniIste()
        }
    }

    // MARK: - Seslenmeler

    @ViewBuilder
    private var seslenmeListesi: some View {
        if istemci.cagriGecmisi.isEmpty {
            bosListe(simge: "megaphone", metin: "Henüz seslenme yok")
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(istemci.cagriGecmisi) { seslenme in
                        GecmisSeslenmeSatiri(seslenme: seslenme, benimID: istemci.ben?.id)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
            }
            .frame(minHeight: 140, maxHeight: 420)
        }
    }

    // MARK: - Anketler

    @ViewBuilder
    private var anketListesi: some View {
        if istemci.anketGecmisi.isEmpty {
            bosListe(simge: "checklist", metin: "Henüz anket açılmamış")
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
            .frame(minHeight: 140, maxHeight: 420)
        }
    }

    // MARK: - Ortak

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
                Text("Geçmiş").font(.system(size: 13, weight: .semibold))
                Text(istemci.kurum?.ad ?? "Kurum")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func bosListe(simge: String, metin: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: simge)
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text(metin)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

/// Geçmişteki tek bir seslenme satırı.
private struct GecmisSeslenmeSatiri: View {
    let seslenme: GecmisSeslenme
    let benimID: String?

    private var giden: Bool { seslenme.giden(benimID: benimID) }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Yön oku: gelen ve gidenin tek listede karışmaması için.
            Image(systemName: giden ? "arrow.up.right" : "arrow.down.left")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(giden ? .secondary : seslenme.seviye.renk)
                .frame(width: 12)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(giden
                        ? "\(seslenme.karsiTaraf(benimID: benimID))'e"
                        : seslenme.karsiTaraf(benimID: benimID))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)

                    Text(seslenme.seviye.baslik)
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.3)
                        .foregroundStyle(seslenme.seviye.renk)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(seslenme.seviye.renk.opacity(0.18))
                        }
                        .fixedSize()

                    Spacer(minLength: 4)

                    Text(seslenme.gonderildi.kisaAralik)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                if !seslenme.not.isEmpty {
                    Text(seslenme.not)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                yanitEtiketi
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.primary.opacity(0.04))
        }
    }

    @ViewBuilder
    private var yanitEtiketi: some View {
        if let yanit = seslenme.yanit {
            HStack(spacing: 3) {
                Image(systemName: yanit.simge)
                Text(yanit.baslik)
            }
            .font(.system(size: 10))
            .foregroundStyle(.green)
        } else {
            Text("yanıtsız")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

extension Date {
    /// "5dk", "3sa", "2g" gibi kısa aralık. Sistem biçimlendiricisi Türkçede
    /// "5 dakika önce" gibi uzun metin veriyor ve dar satıra sığmıyor.
    var kisaAralik: String {
        let saniye = Int(Date().timeIntervalSince(self))
        switch saniye {
        case ..<60: return "az önce"
        case ..<3600: return "\(saniye / 60)dk"
        case ..<86400: return "\(saniye / 3600)sa"
        default: return "\(saniye / 86400)g"
        }
    }
}
