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

            // Sunucunun reddi burada da görünmeli: ad düzenlemenin tek geri
            // bildirimi bu şerit. Menü paneli açık olmayabilir ve "bu isimde
            // bir üye zaten var" uyarısını göremeyen yönetici, değişikliğin
            // neden geri döndüğünü anlayamazdı.
            if let hata = istemci.sonHata {
                durumSeridi(hata, renk: .red, simge: "exclamationmark.circle.fill")
            } else if let bilgi = istemci.sonBilgi {
                durumSeridi(bilgi, renk: .accentColor, simge: "checkmark.circle.fill")
            }

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

    private func durumSeridi(_ mesaj: String, renk: Color, simge: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: simge)
            Text(mesaj).font(.caption).lineLimit(2)
            Spacer()
        }
        .foregroundStyle(renk)
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .background(renk.opacity(0.12))
        .task(id: mesaj) {
            try? await Task.sleep(for: .seconds(5))
            istemci.sonHata = nil
            istemci.sonBilgi = nil
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
    @State private var arama = ""

    /// Aramada `localizedStandardContains` kullanılır: Türkçede aksanı ve
    /// büyük/küçük harfi birlikte gözeten tek eşleştirme bu. Düz
    /// `contains` "şamil" yazana "Şamil"i bulduramazdı.
    private var suzulmusUyeler: [Uye] {
        let temiz = arama.trimmingCharacters(in: .whitespaces)
        guard !temiz.isEmpty else { return istemci.uyeler }
        return istemci.uyeler.filter { $0.adSoyad.localizedStandardContains(temiz) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Üyeler (\(istemci.uyeler.count))", systemImage: "person.3")
                    .font(.headline)

                Spacer()

                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("Ara", text: $arama)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .frame(width: 150)
                    if !arama.isEmpty {
                        Button {
                            arama = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06))
                )
            }

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
                if suzulmusUyeler.isEmpty {
                    Text("\"\(arama)\" ile eşleşen üye yok")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                } else {
                    ForEach(Array(suzulmusUyeler.enumerated()), id: \.element.id) { sira, uye in
                        if sira > 0 { Divider() }
                        UyeYonetimSatiri(uye: uye) { silinecek = uye }
                    }
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

/// Yerinde düzenlenebilen ad alanı.
///
/// Kutu her zaman görünmez: on kişilik bir listede on metin kutusu, satırların
/// hangisinin okunacak hangisinin doldurulacak olduğunu belirsizleştirir. Ad
/// önce düz metindir, kaleme basınca kutuya döner.
private struct AdAlani: View {
    let mevcut: String
    let kaydet: (String) -> Void

    @State private var duzenleniyor = false
    @State private var taslak = ""
    @FocusState private var odakta: Bool

    private var temiz: String {
        taslak.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Sunucudaki doğrulamanın istemci tarafındaki karşılığı; yaptırım orada.
    private var gecerli: Bool {
        (2...40).contains(temiz.count) && temiz != mevcut
    }

    var body: some View {
        if duzenleniyor {
            HStack(spacing: 4) {
                TextField("", text: $taslak)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(maxWidth: 180)
                    .focused($odakta)
                    .onSubmit(bitir)
                    // Odak kaybı **kaydetmez**, yalnızca düzenlemeyi kapatır.
                    // Kaydetseydi "Ali"yi düzeltmeye başlayıp "Al" yazmışken
                    // arama kutusuna tıklamak, yarım kalmış adı sunucuya yollayıp
                    // `KurumaYayinla` ile tüm kuruma yayardı — üstelik "Al" iki
                    // harf olduğu için doğrulamadan da geçerek.
                    //
                    // Ayarlar'daki `AdDuzenleyici` de kaydetmiyor; iki yeniden
                    // adlandırma arayüzünün zıt davranması başlı başına hataydı.
                    .onChange(of: odakta) { _, yeni in
                        if !yeni { duzenleniyor = false }
                    }

                // Odak kaybı artık kaydetmediği için düğme şart: yoksa
                // kaydetmenin tek yolu Enter olurdu ve bu keşfedilebilir değil.
                Button("Kaydet", action: bitir)
                    .controlSize(.small)
                    .disabled(!gecerli)

                Button("Vazgeç") { duzenleniyor = false }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
            .onAppear {
                taslak = mevcut
                odakta = true
            }
        } else {
            HStack(spacing: 5) {
                Text(mevcut).font(.system(size: 13))
                Button {
                    duzenleniyor = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Adı düzelt")
            }
        }
    }

    private func bitir() {
        defer { duzenleniyor = false }
        guard gecerli else { return }
        kaydet(temiz)
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

    /// Ad, rol ve yetkiden ayrı bir eksen: kurucunun adına da kendisi
    /// dokunabilmeli. Kendi adını düzeltmek yönetim işlemi değildir, bu yüzden
    /// kurucu dokunulmazlığına takılmaz — yalnızca yolu farklıdır.
    private var adDuzenlenebilir: Bool { !kilitli || benMiyim }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(uye.cevrimici ? Color.green : Color.gray.opacity(0.5))
                    .frame(width: 7, height: 7)

                if adDuzenlenebilir {
                    AdAlani(mevcut: uye.adSoyad, kaydet: adiYaz)
                } else {
                    Text(uye.adSoyad).font(.system(size: 13))
                }

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

    /// Kendi adımız için `ad_degistir`, başkasınınki için yönetim mesajı.
    ///
    /// Ayrım sunucudaki iki ayrı kapıya karşılık gelir: kimlik taşımayan istek
    /// hedefi bağlantıdan okur, yönetim isteği ise yetki kontrolünden geçer.
    /// Kurucunun kendi adını yazabilmesinin tek yolu birincisidir.
    private func adiYaz(_ ad: String) {
        if benMiyim {
            istemci.adDegistir(ad)
        } else {
            istemci.uyeAdGuncelle(uyeID: uye.id, adSoyad: ad)
        }
    }
}
