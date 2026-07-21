import SwiftUI

/// Ayarlar penceresi. Sunucu adresi, uyarı biçimleri, kişi bazlı ayarlar ve izinler.
struct AyarlarPenceresi: View {
    var body: some View {
        TabView {
            GenelSekmesi()
                .tabItem { Label("Genel", systemImage: "gearshape") }
            UyariSekmesi()
                .tabItem { Label("Uyarılar", systemImage: "bell.badge") }
            KisilerSekmesi()
                .tabItem { Label("Kişiler", systemImage: "person.2") }
            IzinlerSekmesi()
                .tabItem { Label("İzinler", systemImage: "checkmark.shield") }
        }
        .frame(minWidth: 600, minHeight: 520)
    }
}

// MARK: - Genel

private struct GenelSekmesi: View {
    @Environment(Ayarlar.self) private var ayarlar
    @Environment(SunucuIstemcisi.self) private var istemci

    @State private var acilisMesaji: String?

    var body: some View {
        @Bindable var ayarlar = ayarlar

        Form {
            Section("Bağlantı") {
                HStack {
                    Circle()
                        .fill(istemci.baglanti.iyi ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(istemci.baglanti.baslik)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Yeniden bağlan") { istemci.yenidenBaglan() }
                }
            }

            Section("Uygulama") {
                Toggle("Bilgisayar açılışında başlat", isOn: Binding(
                    get: { ayarlar.acilistaBaslat },
                    set: { yeni in
                        ayarlar.acilistaBaslat = yeni
                        acilisMesaji = SistemAyarlari.acilistaBaslatmayiAyarla(yeni)
                    }
                ))
                if let acilisMesaji {
                    Text(acilisMesaji)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if let kurum = istemci.kurum, let ben = istemci.ben {
                Section("Oturum") {
                    LabeledContent("Kurum", value: kurum.ad)
                    AdDuzenleyici(mevcut: ben.adSoyad)
                    LabeledContent("Rol", value: ben.rol.baslik)
                    LabeledContent("Seslenme yetkiniz", value: ben.maxSeviye.baslik)
                    Button("Oturumu kapat", role: .destructive) {
                        istemci.cikisYap()
                    }
                }
            }

            SurumBolumu()

            // Sunucu adresi normalde gizli: uygulamaya gömülüdür ve
            // kullanıcıların onunla uğraşmasına gerek yoktur. Geliştirme ya da
            // sunucu taşıma durumları için buradan erişilebilir kalıyor.
            Section {
                DisclosureGroup("Gelişmiş") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sunucu adresi")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("", text: $ayarlar.sunucuAdresi)
                            .font(.system(size: 12, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Button("Varsayılana dön") {
                                ayarlar.sunucuAdresi = Ayarlar.varsayilanSunucu
                                istemci.yenidenBaglan()
                            }
                            .disabled(ayarlar.sunucuAdresi == Ayarlar.varsayilanSunucu)
                            Spacer()
                            Button("Bağlan") { istemci.yenidenBaglan() }
                        }
                        .controlSize(.small)
                        Text("Bu adresi yalnızca ekibin sunucusu taşındıysa değiştirin.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Kullanıcının kendi görünen adını değiştirdiği alan.
///
/// Yazdıkça değil, "Kaydet" ile gönderilir: her tuş vuruşunda sunucuya mesaj
/// yollamak, ekipteki herkesin listesini "A", "Al", "Ali" diye üç kez
/// tazelemek demek olurdu.
private struct AdDuzenleyici: View {
    /// Sunucudaki güncel ad. Kayıt sonrası buradan geri gelir.
    let mevcut: String

    @Environment(SunucuIstemcisi.self) private var istemci
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
        LabeledContent("Ad Soyad") {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    TextField("", text: $taslak)
                        .textFieldStyle(.roundedBorder)
                        .focused($odakta)
                        .onSubmit(kaydet)

                    Button("Kaydet", action: kaydet)
                        .disabled(!gecerli || !istemci.baglanti.iyi)
                }

                // Sunucunun cevabı burada gösterilmeli. `sonHata` yalnızca menü
                // panelinde ve Kurum penceresinde çiziliyor; bu alan Ayarlar'dan
                // sunucuya yazan ilk denetim olduğu için reddedilen bir ad
                // ("bu isimde bir üye zaten var") kullanıcıya hiç ulaşmıyor,
                // ekranda hiçbir şey olmamış gibi duruyordu.
                if let hata = istemci.sonHata {
                    yanitSatiri(hata, renk: .red, simge: "exclamationmark.circle.fill")
                } else if let bilgi = istemci.sonBilgi {
                    yanitSatiri(bilgi, renk: .green, simge: "checkmark.circle.fill")
                }
            }
        }
        // Sunucu adı kabul edince (ya da başka bir cihazdan değişince) alan
        // güncel değere döner. Kullanıcı yazarken ezmemek için odak dışarıdayken.
        .onChange(of: mevcut, initial: true) { _, yeni in
            if !odakta { taslak = yeni }
        }
    }

    private func yanitSatiri(_ mesaj: String, renk: Color, simge: String) -> some View {
        Label(mesaj, systemImage: simge)
            .font(.caption)
            .foregroundStyle(renk)
            .fixedSize(horizontal: false, vertical: true)
            .task(id: mesaj) {
                try? await Task.sleep(for: .seconds(5))
                istemci.sonHata = nil
                istemci.sonBilgi = nil
            }
    }

    private func kaydet() {
        guard gecerli else { return }
        // Önceki cevabı temizliyoruz: aksi halde eski "güncellendi" yazısı yeni
        // isteğin cevabı sanılırdı.
        istemci.sonHata = nil
        istemci.sonBilgi = nil
        istemci.adDegistir(temiz)
        odakta = false
    }
}

/// Kurulu sürümü gösterir, yenisi çıkmış mı diye bakar ve isteyene kurar.
private struct SurumBolumu: View {
    @State private var denetci = GuncellemeDenetcisi()
    @State private var kopyalandi = false

    var body: some View {
        Section("Sürüm") {
            LabeledContent("Kurulu sürüm") {
                Text(denetci.kuruluSurum.isEmpty ? "geliştirme kipi" : denetci.kuruluSurum)
                    .foregroundStyle(.secondary)
            }

            HStack {
                durumMetni
                Spacer()
                Button("Güncellemeleri denetle") {
                    Task { await denetci.denetle() }
                }
                .disabled(mesgul)
            }

            if case .indiriliyor(let oran) = denetci.durum {
                ProgressView(value: oran)
                    .progressViewStyle(.linear)
            }

            if case .yeniSurumVar(let yayim) = denetci.durum {
                yeniSurumEylemleri(yayim)
            }
        }
    }

    /// Denetleme veya kurulum sürerken düğmeler kilitlenir; ikinci bir indirme
    /// başlatmak yarım kalmış kurulumun üstüne yazardı.
    private var mesgul: Bool {
        switch denetci.durum {
        case .denetleniyor, .indiriliyor, .kuruluyor: true
        default: false
        }
    }

    @ViewBuilder
    private func yeniSurumEylemleri(_ yayim: Yayim) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if yayim.paket != nil, denetci.kurabilir {
                Button("\(yayim.surum) sürümüne güncelle") {
                    Task { await denetci.guncelle() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(mesgul)

                Text("Seslen kapanacak, yeni sürüm kurulacak ve kendiliğinden yeniden açılacak.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Kurulum yapılamıyor: ya yayımda DMG yok ya da uygulama
                // klasörüne yazma izni yok. Elle kurmanın iki yolu da burada.
                Text("Bu bilgisayarda uygulamayı kendiliğinden güncelleyemiyorum. Aşağıdaki komutu terminalde çalıştırabilirsiniz:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text(GuncellemeDenetcisi.brewKomutu)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.secondary.opacity(0.12))
                        }
                    Button(kopyalandi ? "Kopyalandı" : "Kopyala") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            GuncellemeDenetcisi.brewKomutu, forType: .string)
                        kopyalandi = true
                    }
                    .controlSize(.small)
                }
            }

            Button("\(yayim.surum) sürümünün sayfasını aç") {
                NSWorkspace.shared.open(yayim.sayfa)
            }
            .controlSize(.small)
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var durumMetni: some View {
        switch denetci.durum {
        case .bilinmiyor:
            EmptyView()
        case .denetleniyor:
            Text("Denetleniyor…").font(.caption).foregroundStyle(.secondary)
        case .guncel:
            Label("En güncel sürümü kullanıyorsunuz", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .yeniSurumVar(let yayim):
            Label("\(yayim.surum) sürümü çıktı", systemImage: "arrow.down.circle.fill")
                .font(.caption)
                .foregroundStyle(.blue)
        case .indiriliyor(let oran):
            Text("İndiriliyor… %\(Int(oran * 100))")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .kuruluyor:
            Text("Kuruluyor…").font(.caption).foregroundStyle(.secondary)
        case .hata(let mesaj):
            Label(mesaj, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

// MARK: - Uyarılar

private struct UyariSekmesi: View {
    @Environment(Ayarlar.self) private var ayarlar
    @Environment(UyariYoneticisi.self) private var uyari

    var body: some View {
        @Bindable var ayarlar = ayarlar

        Form {
            Section {
                UyariBicimiSecici(bicim: $ayarlar.varsayilan)
            } header: {
                Text("Varsayılan uyarı biçimi")
            } footer: {
                Text("Kişiye özel ayarı olmayan herkes için geçerlidir. Kişi bazlı değişiklikleri **Kişiler** sekmesinden yapabilirsiniz.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("ACİL seviyesi kişisel ayarları ezsin", isOn: $ayarlar.acilEzsin)
                Text("Açıkken, sesini kapattığınız bir kişi bile ACİL gönderdiğinde tüm uyarılar devreye girer. Kapatırsanız ACİL de kişisel ayarlarınıza uyar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Aciliyet")
            }

            Section {
                HStack {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: $ayarlar.sesSiddeti, in: 0...1)
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }
            } header: {
                Text("Ses şiddeti")
            }

            Section {
                ForEach(Seviye.allCases, id: \.self) { seviye in
                    SesSecici(seviye: seviye)
                }
            } header: {
                Text("Seviye sesleri")
            } footer: {
                Text("Seslerin birbirinden ayrılması önemli: ekrana bakmadan hangi seviyede seslenildiğini duyabilmelisiniz.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Panel") {
                Picker("Kendiliğinden kapanma", selection: $ayarlar.panelSuresi) {
                    Text("10 saniye").tag(10.0)
                    Text("20 saniye").tag(20.0)
                    Text("45 saniye").tag(45.0)
                    Text("Kapanmasın").tag(0.0)
                }
            }

            Section {
                HStack(spacing: 8) {
                    ForEach(Seviye.allCases, id: \.self) { seviye in
                        Button("\(seviye.baslik) dene") {
                            uyari.onizle(seviye: seviye)
                        }
                    }
                }
            } header: {
                Text("Deneme")
            } footer: {
                Text("Uyarının nasıl göründüğünü ve duyulduğunu buradan sınayabilirsiniz.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Tek bir seviyenin sesini seçer ve dinletir.
private struct SesSecici: View {
    let seviye: Seviye

    @Environment(Ayarlar.self) private var ayarlar

    var body: some View {
        HStack(spacing: 8) {
            Picker(selection: Binding(
                get: { ayarlar.ses(seviye) },
                set: { ayarlar.sesSec(seviye, $0) }
            )) {
                // Gömülü sesler ayrı bölümde: listede sistem sesleriyle
                // karışınca hangisinin Seslen'e ait olduğu anlaşılmıyor.
                Section("Seslen sesleri") {
                    ForEach(UyariSesi.allCases.filter(\.gomulu), id: \.self) { ses in
                        Text(ses.baslik).tag(ses)
                    }
                }
                Section("macOS sesleri") {
                    ForEach(UyariSesi.allCases.filter { !$0.gomulu }, id: \.self) { ses in
                        Text(ses.baslik).tag(ses)
                    }
                }
            } label: {
                Label(seviye.baslik, systemImage: seviye.simge)
                    .foregroundStyle(seviye.renk)
            }

            Button {
                SesCalar.onizle(ayarlar.ses(seviye), siddet: ayarlar.sesSiddeti)
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.plain)
            .help("\(seviye.baslik) sesini dinle")
        }
    }
}

/// Dört uyarı biçimini açıp kapatan ortak denetim.
struct UyariBicimiSecici: View {
    @Binding var bicim: UyariBicimi

    var body: some View {
        Toggle(isOn: $bicim.ikon) {
            Label("Menü çubuğu ve bildirim", systemImage: "menubar.arrow.up.rectangle")
        }
        Toggle(isOn: $bicim.panel) {
            Label("Ekranda panel", systemImage: "rectangle.inset.filled")
        }
        Toggle(isOn: $bicim.ses) {
            Label("Ses", systemImage: "speaker.wave.2.fill")
        }
        Toggle(isOn: $bicim.kenar) {
            Label("Ekran kenarı flaşı", systemImage: "rectangle.dashed")
        }
    }
}

// MARK: - Kişiler

private struct KisilerSekmesi: View {
    @Environment(Ayarlar.self) private var ayarlar
    @Environment(SunucuIstemcisi.self) private var istemci

    var body: some View {
        VStack(spacing: 0) {
            baslik
            Divider()

            if istemci.digerUyeler.isEmpty {
                Spacer()
                Text("Kurumda başka kimse yok")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        satir(
                            ad: "Varsayılan (herkes)",
                            altYazi: "Kişisel ayarı olmayanlar",
                            bicim: Binding(
                                get: { ayarlar.varsayilan },
                                set: { ayarlar.varsayilan = $0 }
                            ),
                            ozel: false,
                            sifirla: nil
                        )
                        .background(Color.primary.opacity(0.04))

                        Divider()

                        ForEach(istemci.digerUyeler) { uye in
                            satir(
                                ad: uye.adSoyad,
                                altYazi: uye.rol == .uye ? nil : uye.rol.baslik,
                                bicim: Binding(
                                    get: { ayarlar.bicim(uye.id) },
                                    set: { ayarlar.kisisel[uye.id] = $0 }
                                ),
                                ozel: ayarlar.kisisel[uye.id] != nil,
                                sifirla: { ayarlar.kisiselSifirla(uye.id) }
                            )
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var baslik: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Kişi bazlı uyarılar").font(.headline)
                Text("Her kişiden gelen seslenmede neyin devreye gireceğini ayrı ayrı seçin")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ForEach(["İkon", "Panel", "Ses", "Kenar"], id: \.self) { sutun in
                Text(sutun)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 52)
            }
            Color.clear.frame(width: 26)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func satir(
        ad: String,
        altYazi: String?,
        bicim: Binding<UyariBicimi>,
        ozel: Bool,
        sifirla: (() -> Void)?
    ) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(ad).font(.system(size: 13))
                    if ozel {
                        Text("özel")
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                    }
                }
                if let altYazi {
                    Text(altYazi).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Spacer()

            kutu(bicim.ikon)
            kutu(bicim.panel)
            kutu(bicim.ses)
            kutu(bicim.kenar)

            // Varsayılan satırında sıfırlama düğmesi yok; hizayı korumak için boşluk.
            Group {
                if let sifirla {
                    Button {
                        sifirla()
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ozel ? Color.accentColor : Color.secondary.opacity(0.3))
                    .disabled(!ozel)
                    .help("Varsayılana döndür")
                } else {
                    Color.clear
                }
            }
            .frame(width: 26)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func kutu(_ deger: Binding<Bool>) -> some View {
        Toggle("", isOn: deger)
            .labelsHidden()
            .toggleStyle(.checkbox)
            .frame(width: 52)
    }
}

// MARK: - İzinler

private struct IzinlerSekmesi: View {
    @Environment(UyariYoneticisi.self) private var uyari

    var body: some View {
        Form {
            Section {
                HStack {
                    Label("Bildirimler", systemImage: "bell.badge")
                    Spacer()
                    Text(uyari.bildirimIzni.aciklama)
                        .foregroundStyle(uyari.bildirimIzni == .verildi ? .green : .secondary)
                        .font(.callout)
                }

                if uyari.bildirimIzni != .verildi {
                    HStack {
                        Button("İzin ver") {
                            Task { await uyari.bildirimIzniIste() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(uyari.bildirimIzni == .kullanilamaz)

                        Button("Sistem Ayarları'nı aç") {
                            SistemAyarlari.bildirimleriAc()
                        }
                    }
                }
            } header: {
                Text("Bildirim izni")
            } footer: {
                Text("Bildirim izni yalnızca menü çubuğu uyarısı içindir. Ekran paneli, ses ve kenar flaşı izin gerektirmez ve **Rahatsız Etmeyin** kipinde bile çalışır.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Button("Gizlilik ve Güvenlik'i aç") {
                    SistemAyarlari.gizlilikVeGuvenlikAc()
                }
                Button("Giriş Öğeleri'ni aç") {
                    SistemAyarlari.girisOgeleriniAc()
                }
            } header: {
                Text("Sistem Ayarları kısayolları")
            } footer: {
                Text("Seslen imzasız dağıtıldığı için ilk açılışta macOS engelleyebilir. **Gizlilik ve Güvenlik** sayfasının altındaki \"Yine de Aç\" düğmesiyle izin verebilirsiniz.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .task { await uyari.izinDurumunuYenile() }
    }
}
