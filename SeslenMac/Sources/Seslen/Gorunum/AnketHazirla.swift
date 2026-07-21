import SwiftUI

/// Kuruma çoktan seçmeli kısa bir soru sorulan ekran.
///
/// `HaykirHazirla`'nın kardeşi: seviye seçtirilmez, süre sorulmaz. Anket her
/// zaman en hafif biçimde gider ve sunucuda beş dakika açık kalır. Amaç
/// masalarda dolaşıp "kim çay ister" diye tek tek sormayı ortadan kaldırmak.
struct AnketHazirla: View {
    let geriDon: () -> Void

    @Environment(SunucuIstemcisi.self) private var istemci

    @State private var soru: String = ""
    @State private var secenekler: [String] = ["", ""]
    @FocusState private var soruOdakta: Bool

    /// Sunucudaki `model.AnketEnAzSecenek` / `AnketEnCokSecenek` ile aynı
    /// sınırlar. Buradaki kontrol yalnızca kolaylık; yaptırım sunucuda.
    private let enAz = 2
    private let enCok = 5

    private var dolular: [String] {
        secenekler
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var gonderilebilir: Bool {
        !soru.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && dolular.count >= enAz
            && istemci.baglanti.iyi
    }

    var body: some View {
        VStack(spacing: 0) {
            baslik
            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Soru")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("örn. Kim çay ister?", text: $soru)
                    .textFieldStyle(.roundedBorder)
                    .focused($soruOdakta)

                HStack {
                    Text("Seçenekler")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if secenekler.count < enCok {
                        Button("Seçenek ekle") {
                            secenekler.append("")
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
                .padding(.top, 4)

                ForEach(secenekler.indices, id: \.self) { dizin in
                    HStack(spacing: 6) {
                        TextField("örn. Çay", text: $secenekler[dizin])
                            .textFieldStyle(.roundedBorder)

                        // En az iki seçenek her zaman kalmalı.
                        if secenekler.count > enAz {
                            Button {
                                secenekler.remove(at: dizin)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text("Kimsenin ekranını kesmez, 5 dakika açık kalır.")
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)

            Divider()

            HStack {
                Button("Vazgeç", action: geriDon)
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button(action: gonder) {
                    Label("Anketi aç", systemImage: "checklist")
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!gonderilebilir)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .onAppear { soruOdakta = true }
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
                    Image(systemName: "checklist")
                        .font(.system(size: 11))
                        .foregroundStyle(.teal)
                }

            VStack(alignment: .leading, spacing: 0) {
                Text("Anket aç").font(.system(size: 13, weight: .semibold))
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

    private func gonder() {
        guard gonderilebilir else { return }
        istemci.anketGonder(
            soru: soru.trimmingCharacters(in: .whitespacesAndNewlines),
            secenekler: dolular
        )
        geriDon()
    }
}
