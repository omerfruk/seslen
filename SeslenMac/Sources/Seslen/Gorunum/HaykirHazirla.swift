import SwiftUI

/// Kurumdaki herkese birden seslenilen ekran.
///
/// Seviye seçtirilmez: yayın sunucuda her zaman normal seviyede gider, çünkü
/// tek tıkla bütün ekibe tam ekran ACİL uyarı basılabilmesi istenmiyor.
struct HaykirHazirla: View {
    let geriDon: () -> Void

    @Environment(SunucuIstemcisi.self) private var istemci

    @State private var not: String = ""
    @FocusState private var notOdakta: Bool

    /// Yayının ulaşacağı kişi sayısı (kendimiz hariç, çevrimiçi olanlar).
    private var ulasilacak: Int {
        istemci.digerUyeler.filter(\.cevrimici).count
    }

    var body: some View {
        VStack(spacing: 0) {
            baslik
            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Mesaj (isteğe bağlı)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("örn. toplantı başlıyor", text: $not)
                    .textFieldStyle(.roundedBorder)
                    .focused($notOdakta)
                    .onSubmit(gonder)

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text(bilgiMetni)
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
                    Label("Haykır", systemImage: "megaphone.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!istemci.baglanti.iyi || ulasilacak == 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .onAppear { notOdakta = true }
    }

    private var bilgiMetni: String {
        ulasilacak == 0
            ? "Şu anda çevrimiçi kimse yok."
            : "Normal seviyede \(ulasilacak) kişiye gider; kimsenin ekranını kesmez."
    }

    private var baslik: some View {
        HStack(spacing: 10) {
            Button(action: geriDon) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)

            Circle()
                .fill(Color.purple.opacity(0.18))
                .frame(width: 26, height: 26)
                .overlay {
                    Image(systemName: "megaphone.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.purple)
                }

            VStack(alignment: .leading, spacing: 0) {
                Text("Herkese haykır").font(.system(size: 13, weight: .semibold))
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
        guard ulasilacak > 0 else { return }
        istemci.haykir(not: not.trimmingCharacters(in: .whitespacesAndNewlines))
        geriDon()
    }
}
