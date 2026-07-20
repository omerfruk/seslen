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
                    LabeledContent("Ad Soyad", value: ben.adSoyad)
                    LabeledContent("Rol", value: ben.rol.baslik)
                    LabeledContent("Seslenme yetkiniz", value: ben.maxSeviye.baslik)
                    Button("Oturumu kapat", role: .destructive) {
                        istemci.cikisYap()
                    }
                }
            }

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

            Section("Ses") {
                HStack {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: $ayarlar.sesSiddeti, in: 0...1)
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }
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
