import AppKit
import SwiftUI

/// Menü çubuğuna tıklayınca açılan ana panel.
struct AnaGorunum: View {
    @Environment(Ayarlar.self) private var ayarlar
    @Environment(SunucuIstemcisi.self) private var istemci
    @Environment(UyariYoneticisi.self) private var uyari
    @Environment(\.openWindow) private var pencereAc

    /// Seslenme hazırlanan kişi. Nil ise kişi listesi görünür.
    @State private var secilenUye: Uye?
    /// Herkese haykırma ekranı açık mı?
    @State private var haykirmaAcik = false
    /// Anket oluşturma ekranı açık mı?
    @State private var anketAcik = false
    /// Geçmiş ekranı (seslenmeler + anketler) açık mı?
    @State private var gecmisAcik = false

    var body: some View {
        VStack(spacing: 0) {
            if !istemci.oturumAcik {
                GirisGorunumu()
            } else if let ben = istemci.ben, !ben.onayli {
                OnayBekleniyorGorunumu()
            } else if let uye = secilenUye {
                SeslenmeHazirla(uye: uye) { secilenUye = nil }
            } else if haykirmaAcik {
                HaykirHazirla { haykirmaAcik = false }
            } else if anketAcik {
                AnketHazirla { anketAcik = false }
            } else if gecmisAcik {
                Gecmis { gecmisAcik = false }
            } else {
                kisiListesi
            }

            // Alt şerit her durumda görünür: oturum açılmamışken de kullanıcının
            // ayarlara ulaşabilmesi ve uygulamadan çıkabilmesi gerekir.
            Divider()
            altSerit
        }
        .frame(width: 340)
        .onAppear {
            uyari.hepsiniTemizle()
            if istemci.oturumAcik, !istemci.baglanti.iyi {
                istemci.baglan()
            }
        }
        .task {
            await uyari.izinDurumunuYenile()
        }
    }

    // MARK: - Kişi listesi

    private var kisiListesi: some View {
        VStack(spacing: 0) {
            baslik

            if let ben = istemci.ben, ben.rol.yonetimYetkisi, !istemci.bekleyen.isEmpty {
                onayBekleyenlerSeridi(sayi: istemci.bekleyen.count)
            }

            if let hata = istemci.sonHata {
                hataSeridi(hata)
            }

            if let bilgi = istemci.sonBilgi {
                bilgiSeridi(bilgi)
            }

            eylemSeridi

            // Yalnızca açık anketler: oy vermeden balonu kapatan kişinin
            // ankete ulaşabileceği tek yer burası. Bitenler geçmişe düşer.
            ForEach(istemci.acikAnketler) { anket in
                AnketSonucGorunumu(
                    anket: anket,
                    benimID: istemci.ben?.id,
                    oyVer: { istemci.anketOyVer(anketID: anket.id, secenek: $0) },
                    bitir: { istemci.anketBitir(anketID: anket.id) },
                    gizle: { istemci.anketiGizle(anket.id) }
                )
            }

            Divider()

            if istemci.digerUyeler.isEmpty {
                bosListe
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(istemci.digerUyeler) { uye in
                            UyeSatiri(
                                uye: uye,
                                yetkim: yetkim,
                                hizliSeslen: { istemci.seslen(aliciID: uye.id, seviye: $0) },
                                detay: { secilenUye = uye }
                            )
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                }
                // ScrollView tek başına bırakılınca kalan alana sıkışıp içeriğinden
                // kısa kalıyor; asgari yükseklik listeyi olduğu kadar açık tutar.
                .frame(minHeight: listeAsgariYuksekligi, maxHeight: 460)
            }

            Divider()
            durumSecici
        }
    }

    /// Kullanıcının gönderebileceği en yüksek seviye.
    private var yetkim: Seviye {
        istemci.ben?.maxSeviye ?? .normal
    }

    /// Listenin sıkışmaması için gereken yükseklik; kişi az ise boşluk da bırakmaz.
    private var listeAsgariYuksekligi: CGFloat {
        let satirYuksekligi: CGFloat = 46
        return min(CGFloat(istemci.digerUyeler.count) * satirYuksekligi + 12, 380)
    }

    /// Haykır ve anket yan yana: iki tam genişlik şeridi üst üste koymak
    /// paneli gereksiz uzatırdı.
    private var eylemSeridi: some View {
        HStack(spacing: 0) {
            eylemDugmesi(
                baslik: "Herkese haykır",
                simge: "megaphone.fill",
                renk: .purple
            ) { haykirmaAcik = true }

            Divider().frame(height: 18)

            eylemDugmesi(
                baslik: "Anket aç",
                simge: "checklist",
                renk: .teal
            ) { anketAcik = true }

            Divider().frame(height: 18)

            // Tek geçmiş girişi: hem biten anketler hem eski seslenmeler burada.
            Button {
                gecmisAcik = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.teal)
            .help("Geçmiş")
        }
        .padding(.vertical, 2)
    }

    private func eylemDugmesi(
        baslik: String, simge: String, renk: Color, secildi: @escaping () -> Void
    ) -> some View {
        Button(action: secildi) {
            HStack(spacing: 6) {
                Image(systemName: simge)
                Text(baslik)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(renk)
        .background(Color.purple.opacity(0.14))
        .disabled(!istemci.baglanti.iyi)
    }

    private var baslik: some View {
        HStack(spacing: 8) {
            Image(systemName: "megaphone.fill")
                .foregroundStyle(.tint)
            Text(istemci.kurum?.ad ?? "Seslen")
                .font(.headline)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 5) {
                Circle()
                    .fill(istemci.baglanti.iyi ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(istemci.baglanti.iyi ? "\(cevrimiciSayisi)/\(istemci.uyeler.count)" : istemci.baglanti.baslik)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var cevrimiciSayisi: Int {
        istemci.uyeler.filter(\.cevrimici).count
    }

    /// `.accessory` kipindeki bir uygulama kendiliğinden öne gelmez: `openWindow`
    /// pencereyi açar ama menü çubuğu paneli kapanınca odak bir önceki uygulamaya
    /// döndüğü için pencere onun arkasında kalır. Uygulamayı elle etkinleştirmek
    /// şart. `TacizPenceresi` ve `UyariPaneli` aynı ikiliyi zaten kullanıyor;
    /// eksik olan yalnızca SwiftUI `Window` sahneleriydi.
    private func pencereyiOneGetir(_ kimlik: String) {
        pencereAc(id: kimlik)
        NSApp.activate(ignoringOtherApps: true)
        // Pencere SwiftUI güncelleme döngüsünde oluşuyor; bu tur içinde henüz
        // yoktur, o yüzden anahtar pencere yapmayı bir sonraki tura bırakıyoruz.
        DispatchQueue.main.async {
            NSApp.windows
                .first { $0.identifier?.rawValue == kimlik }?
                .makeKeyAndOrderFront(nil)
        }
    }

    private func onayBekleyenlerSeridi(sayi: Int) -> some View {
        Button {
            pencereyiOneGetir(PencereKimligi.kurum)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "person.badge.clock.fill")
                Text("\(sayi) kişi katılmak için onay bekliyor")
                    .font(.caption)
                Spacer()
                Image(systemName: "chevron.right").font(.caption2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.16))
        }
        .buttonStyle(.plain)
    }

    private func hataSeridi(_ mesaj: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(mesaj).font(.caption).lineLimit(2)
            Spacer()
        }
        .foregroundStyle(.red)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.red.opacity(0.12))
        .task(id: mesaj) {
            // Hata mesajı birkaç saniye sonra kendiliğinden kaybolsun.
            try? await Task.sleep(for: .seconds(5))
            istemci.sonHata = nil
        }
    }

    /// Hata değil bilgi: seslenme kaybolmadı, yalnızca gecikecek. Bu yüzden
    /// kırmızı değil mavi ve daha uzun süre durur — kullanıcı yeniden denemesin.
    private func bilgiSeridi(_ mesaj: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "clock.badge.checkmark")
            Text(mesaj).font(.caption).lineLimit(2)
            Spacer()
        }
        .foregroundStyle(.blue)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.blue.opacity(0.12))
        .task(id: mesaj) {
            try? await Task.sleep(for: .seconds(7))
            istemci.sonBilgi = nil
        }
    }

    private var bosListe: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("Kurumda henüz başka kimse yok")
                .font(.callout)
                .foregroundStyle(.secondary)
            if istemci.ben?.rol.yonetimYetkisi == true {
                Button("Kişi davet et") { pencereyiOneGetir(PencereKimligi.kurum) }
                    .buttonStyle(.link)
                    .font(.callout)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var durumSecici: some View {
        HStack(spacing: 8) {
            Text("Durumum")
                .font(.callout)
                .foregroundStyle(.secondary)

            // Meşgul, geri bildirimi olmayan bir kuyuya dönüşmemeli: kullanıcı
            // kaç kişinin seslendiğini görüp müsaite dönmeye kendi karar versin.
            if istemci.ben?.durum == .mesgul, istemci.bekleyenCagri > 0 {
                Text("· \(istemci.bekleyenCagri) çağrı bekliyor")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help("Müsaite dönünce hepsini bir arada görürsün")
            }

            Spacer()
            Picker("", selection: Binding(
                get: { istemci.ben?.durum == .mesgul ? Durum.mesgul : Durum.musait },
                set: { istemci.durumBildir($0) }
            )) {
                ForEach(Durum.secilebilir, id: \.self) { durum in
                    Text(durum.baslik).tag(durum)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 110)
            .disabled(!istemci.baglanti.iyi)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var altSerit: some View {
        HStack(spacing: 4) {
            Button {
                pencereyiOneGetir(PencereKimligi.ayarlar)
            } label: {
                Label("Ayarlar", systemImage: "gearshape")
            }

            if istemci.ben?.rol.yonetimYetkisi == true {
                Button {
                    pencereyiOneGetir(PencereKimligi.kurum)
                } label: {
                    Label("Kurum", systemImage: "person.3")
                }
            }

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Çıkış", systemImage: "power")
            }
        }
        .buttonStyle(.accessoryBar)
        .labelStyle(.titleAndIcon)
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

// MARK: - Üye satırı

/// Kişi listesindeki tek bir satır. Sağdaki düğmeler tek tıkla seslenir;
/// isme tıklamak not yazılabilen detay ekranını açar.
private struct UyeSatiri: View {
    let uye: Uye
    /// Kullanıcının gönderebileceği en yüksek seviye; düğmeler buna göre görünür.
    let yetkim: Seviye
    let hizliSeslen: (Seviye) -> Void
    let detay: () -> Void

    @State private var uzerinde = false

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: 30, height: 30)
                        .overlay {
                            Text(uye.basHarfler)
                                .font(.system(size: 11, weight: .semibold))
                        }
                    Circle()
                        .fill(durumRengi)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(uye.adSoyad)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Text(durumMetni)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard uye.cevrimici else { return }
                detay()
            }

            HStack(spacing: 2) {
                ForEach(Seviye.allCases, id: \.self) { seviye in
                    if yetkim.kapsar(seviye) {
                        HizliDugme(
                            simge: seviye.simge,
                            renk: seviye.renk,
                            ipucu: "\(seviye.baslik) seslen"
                        ) {
                            hizliSeslen(seviye)
                        }
                    }
                }
                HizliDugme(
                    simge: "ellipsis",
                    renk: .secondary,
                    ipucu: "Not yazarak seslen",
                    eylem: detay
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(uzerinde ? Color.primary.opacity(0.07) : .clear)
        }
        .onHover { uzerinde = $0 }
        // Çevrimdışı kişiye seslenilemez; sunucu da bunu reddeder.
        .disabled(!uye.cevrimici)
        .opacity(uye.cevrimici ? 1 : 0.5)
    }

    private var durumRengi: Color {
        switch uye.etkinDurum {
        case .musait: .green
        case .mesgul: .orange
        case .cevrimdisi: .gray
        }
    }

    private var durumMetni: String {
        switch uye.etkinDurum {
        case .musait: uye.rol == .uye ? "Müsait" : "Müsait · \(uye.rol.baslik)"
        case .mesgul: "Meşgul"
        case .cevrimdisi: "Çevrimdışı"
        }
    }
}

/// Üye satırındaki tek tıklık seslenme düğmesi.
private struct HizliDugme: View {
    let simge: String
    let renk: Color
    let ipucu: String
    let eylem: () -> Void

    @State private var uzerinde = false

    var body: some View {
        Button(action: eylem) {
            Image(systemName: simge)
                .font(.system(size: 11))
                .foregroundStyle(renk)
                .frame(width: 25, height: 25)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(renk.opacity(uzerinde ? 0.25 : 0.10))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { uzerinde = $0 }
        .help(ipucu)
    }
}

// MARK: - Onay bekleniyor

/// Katılım isteği henüz onaylanmamış kullanıcıya gösterilen ekran.
private struct OnayBekleniyorGorunumu: View {
    @Environment(SunucuIstemcisi.self) private var istemci

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hourglass")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text("Onay bekleniyor")
                .font(.headline)
            Text("**\(istemci.kurum?.ad ?? "Kurum")** yöneticisi katılım isteğinizi onayladığında ekip listesi burada görünecek.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Vazgeç ve çık", role: .destructive) {
                istemci.cikisYap()
            }
            .buttonStyle(.link)
            .font(.callout)
            .padding(.top, 4)
        }
        .padding(22)
    }
}
