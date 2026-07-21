# Seslen — Claude için proje notları

Kulaklıkla çalışan ekipler için sessiz seslenme uygulaması. İki parça:
Go WebSocket sunucusu + SwiftUI macOS menü çubuğu uygulaması.

## Dil ve adlandırma

**Bu projede tüm tanımlayıcılar ve yorumlar Türkçedir.** Tip, işlev, değişken,
paket ve dosya adları Türkçe yazılır (`SunucuIstemcisi`, `uyeGuncelleIsle`,
`kisiselSifirla`). Yeni kod eklerken bu düzeni bozma; İngilizce isim karıştırma.

Yalnızca dilin/çerçevenin dayattığı adlar İngilizce kalır (`body`, `init`,
`main`, `Codable`, protokol JSON anahtarları arası tutarlılık vb.).

Yorumlar **neden** sorusunu yanıtlar, **ne** yaptığını değil. Kodun kendisinden
okunabilen şeyi yorumlama.

## Komutlar

```bash
make test       # Go testleri (-race ile)
make calistir   # sunucuyu yerelde başlat → http://localhost:8787
make uygulama   # Seslen.app üret → cikti/
make kur        # derle, /Applications'a kur, başlat
make dmg        # dağıtım DMG'si
```

Swift tarafını hızlı derlemek için: `swift build --package-path SeslenMac`

## Mimari

```
seslen-sunucu/internal/
  model/      veri tipleri + yetki kuralları (Seviye.Kapsar, Rol.YonetimYetkisi)
  protokol/   WebSocket mesaj sözleşmesi
  store/      SQLite katmanı (modernc.org/sqlite — saf Go, CGO yok)
  hub/        canlı bağlantılar + mesaj işleme (yetki kontrolleri burada)
  api/        HTTP uçları (kurum oluştur/katıl, /ws yükseltme)

SeslenMac/Sources/Seslen/
  Model/      Go tiplerinin Swift karşılıkları + yerel Ayarlar
  Ag/         Protokol + SunucuIstemcisi (tüm canlı durum burada)
  Gorunum/    SwiftUI ekranları
  Uyari/      panel, kenar flaşı, ses, bildirim
  Destek/     Anahtar Zinciri, Sistem Ayarları kısayolları
```

## Değişmez kurallar

**1. Protokol iki taraflıdır.**
`seslen-sunucu/internal/protokol/protokol.go` ile
`SeslenMac/Sources/Seslen/Ag/Protokol.swift` aynı sözleşmenin iki yüzüdür.
Birinde mesaj tipi veya alan değiştirirsen diğerini de değiştir. JSON
anahtarları birebir eşleşmeli.

**2. Yetki kontrolü sunucuda yapılır.**
İstemcideki kilit simgeleri yalnızca arayüz kolaylığıdır. Yeni bir yetkili işlem
eklerken kontrolü `hub/mesaj.go` içine koy — `yonetimDogrula` yardımcısı hem
yönetici yetkisini hem kurum sınırını hem de kurucu dokunulmazlığını doğrular.

**3. SF Symbol adları doğrulanmalı.**
`Image(systemName:)` geçersiz bir ada **sessizce boş çizim** yapar. Menü
çubuğunda bu, öğenin sıfır genişlikte yani tamamen görünmez olması demektir —
hiçbir hata mesajı çıkmaz. `dagitim/simge-dogrula.swift` paketleme sırasında
tüm adları tarar; bu adım atlanmamalı. (Bu hata bir kez yaşandı:
`megaphone.badge.xmark` diye bir simge yok.)

Betik iki biçimi tarar: `systemName:`/`systemImage:` gibi doğrudan kullanımlar
ve `Seviye.simge` gibi **gövdesi olan `simge` özelliklerinin** içindeki çıplak
dizgiler. İkincisi olmadan `Image(systemName: seviye.simge)` biçimindeki
kullanımlar hiç denetlenmiyordu — tarihî hata da tam olarak oradaydı.

**4. Teslim edilemeyen çağrı kaybolmaz.**
Alıcı çevrimdışıysa çağrı `cagrilar.teslim_tarih = 0` olarak bekler ve üye
bağlandığı anda `kacirilanlariYolla` ile tek bir `kacirilanlar` mesajında
iletilir. Gönderene hata değil **bilgi** döner (`TipBilgi`) — hata dönseydi
kullanıcı seslenmenin kaybolduğunu sanıp tekrar tekrar denerdi.

İki kasıtlı istisna: **yayın kuyruğa girmez** (saatler sonra teslim edilen bir
"herkese sesleniyorum" gürültüdür, gönderildiği anda teslim sayılır) ve kuyruk
`teslimGecmisSiniri` kadar geriye bakar.

**5. Onay bekleyen üye de bağlı kalır.**
`hub.KurumaYayinla`, alıcıyı önce onaylı listede sonra bekleyen listede arar.
Yalnızca onaylı listede arayıp bulamayınca oturumu kapatmak, katılan hiç
kimsenin "onay bekleniyor" ekranını görememesine yol açar.

**6. `uyeler.durum` kolonu yalnızca tercihi tutar.**
Kolonda `musait` veya `mesgul` yazar; çevrimiçilik ayrı bir eksendir ve
`KurumaYayinla` tarafından hub'ın canlı kaydından türetilir. Eskiden `cikar`
her kopuşta `cevrimdisi`, `Baglat` her bağlanışta `musait` yazıyordu — yani
varlık, tercihi eziyordu ve kullanıcının meşgul seçimi uykudan uyandığında
sessizce siliniyordu. `cikar` artık yalnızca `SonGorulmeYaz` çağırır.
`DurumCevrimdisi` tel üstünde hâlâ geçerli bir değerdir, veritabanında değil.

## Meşgul durumu

Meşgul kozmetik değildir; alıcıya ulaşacak çağrıları süzer.

- **normal + önemli** bastırılır: alıcıya hiçbir şey gitmez, çağrı
  `teslim_tarih = 0` ile kuyrukta bekler, kişi müsaite döndüğü anda
  `durumIsle` içinden `kacirilanlariYolla` ile tek mesajda iletilir.
- **acil geçer.** Geçmeseydi meşgul, acil seviyesini anlamsız kılardı — bu,
  istemcideki `Ayarlar.acilEzsin` mantığının sunucu tarafındaki karşılığıdır.
- **taciz her koşulda geçer.**
- Gönderene hata değil **bilgi** döner ("… şu anda meşgul — müsait olduğunda
  görecek"), çevrimdışı vakasındaki gerekçenin aynısıyla.

**Karar sunucuda verilir** — ve gerekçesi kural 2 değil **kural 4**'tür.
İstemci bastırsaydı çağrı `UyeyeGonder` başarılı olduğu an teslim işaretlenmiş
olurdu; alıcı uygulaması sonradan "gösterme" dediğinde çağrı kaybolurdu.
Kuyruğa alma sunucu işi olduğundan bastırma da onunla aynı yerde olmak zorunda.
`Ayarlar.etkinBicim` bu yüzden hiç değişmedi: o "gelen çağrıyı nasıl
gösteririm" sorusunu yanıtlar, "çağrı gelsin mi" ayrı bir katmandır.

**Yükseltme bastırmadan önce çalışır.** `seviyeyiYukselt`, meşgul kontrolünden
önce çağrılır; yoksa üçüncü yanıtsız ACİL tacize yükselmeden meşgulde ölür ve
yükseltme mekanizması sessizce işlevsizleşir.

**Yayın da meşgule saygı duyar.** Haykırış meşgul üyeye iletilmez ve kuyruğa
girmez (kural 4'ün yayın istisnası burada da geçerli). Meşgulün tanımı "beni
kesme"yse, ekipteki herkesin tek tıkla o kalkanı delebilmesi tutarsız olurdu.
Herkes meşgulse gönderene `HataBulunamadi` değil `TipBilgi` döner — "kimse
çevrimiçi değil" demek o durumda yalan olurdu.

**Meşgul 8 saat sonra kendiliğinden düşer** (`store.mesgulOmru`). Kolon artık
kopuşta sıfırlanmadığı için meşgul kalıcı: Cuma akşamı meşgul seçip kapağı
kapatan biri Pazartesi hâlâ meşgul bağlanır ve haberi olmadan çağrı yutardı.
`BaglantidaDurumTazele` bunu ve eski sürümlerden kalan `cevrimdisi` değerini
tek SQL ifadesinde düzeltir.

**`Hub.teslimMu` silinmemeli.** "Çağrı yaz + teslim kararı ver" ile "durumu
değiştir + kuyruğu boşalt" bölümlerini ayırır. Olmasaydı şu sıra mümkündü:
`seslenIsle` alıcıyı meşgul görür, tam o anda alıcı müsaite geçip kuyruğunu
boşaltır, ardından çağrı `teslim_tarih = 0` ile yazılır — ve saatlerce kuyrukta
unutulur. `h.mu`'dan bilerek ayrıdır: o kilit altında veritabanı işi yapmak
`KurumaYayinla` ve `UyeyeGonder`'i bloklar.

Meşgul bağlanan üyenin kuyruğu `Baglat`'ta **boşaltılmaz**; meşgulün anlamı
tam olarak budur. Kullanıcı biriken sayıyı `DurumTamVeri.BekleyenCagri` ile
menüde görür — meşgul, geri bildirimi olmayan bir kuyuya dönüşmemeli.

## Anket

"Kim çay ister?" gibi çoktan seçmeli kısa soru. Masalarda dolaşıp tek tek
sormanın yerini alır.

**Kuyruk ≠ canlı durum.** Kural 4'ün yayın istisnası anket için de geçerli:
anket `cagrilar` tablosuna hiç girmez, `kacirilanlariYolla` ona dokunmaz.
Ama `Baglat` içinde `acikAnketleriYolla` vardır ve bu kuralı çiğnemez —
kuyruk *geçmiş bir olayı* tekrar oynatır, bu ise *şu anda hâlâ doğru olan bir
durumu* bildirir. Kahve almaya gitmişken açılan ve dönüldüğünde hâlâ açık olan
ankete katılabilmek anketin varlık sebebidir. Kapanmış anket hiç kimseye
sonradan iletilmez. Yeniden bağlanmada gelen anket **uyarı çıkarmaz**; yoksa
titrek bağlantıda aynı anket her seferinde baştan çalardı.

**Kapanış tembeldir.** `anketler.bitis` kolonu süzülür; anket başına goroutine
veya zamanlayıcı yoktur. Sunucu yeniden başladığında da doğru davranır. Süre
sabit 5 dakika (`hub.anketSuresi`) ve kullanıcıya sorulmaz — `HaykirHazirla`'nın
seviye sormamasıyla aynı sadelik. Süresiz anket "3 yanıt bekleniyor" yazısını
hiç çözmez ve açık anket listesini sınırsız büyütürdü.

**Oy metinle değil dizinle taşınır** (`AnketOyIstek.Secenek`). Seçenekler
serbest metin olduğu için metinle eşleştirmek boşluk/harf normalleştirmesi ve
tekrar sorunu getirirdi. `model.SeceneklerGecerli` büyük/küçük harf duyarsız
tekrarı reddeder: "Çay" ve "çay" iki ayrı çubuk olarak çizilirse sonuç okunamaz.

**Oy değiştirilebilir.** Çağrılardaki "yanıt geri alınamaz" kuralı burada
geçmez: "geliyorum" bir taahhüt, anket cevabı bir tercihtir. Dar bir balonda
yanlış tıklamak kolaydır ve geri alma yolu yoksa gönderen yanlış veriyle
hareket eder.

**Anket normal seviyede gelir ama panel ve kenar flaşı hiç devreye girmez** —
kullanıcının `varsayilan.panel` ayarı açık olsa bile. Anket rica eder, kesmez.
Susturulmuş kişi anketle de ulaşamaz: mesaj tipi değiştirerek susturmayı aşmak
mümkün olmamalı. Tacize hiç yükselmez; yanıtsız anket sadece yanıtsız ankettir.

**Kişi başına tek açık anket.** Hız sınırının bedava ve anlaşılır hali.

Sonuç ayrı pencerede değil menü panelinde (`AnketSonucGorunumu`) gösterilir:
uygulama `.accessory` kipinde olduğu için pencere açmak `NSApp.activate`
gerektirir ve kullanıcıyı işinden koparır. Kart hem gönderende hem alıcılarda
görünür — balonu oy vermeden kapatanın ankete ulaşma yolu budur.

Balondaki oy düğmesine basınca balon kapanır. "Kendiliğinden kapanmaz" kuralı
okunmamış mesaj kaybolmasın diyeydi; oy vermek açık bir okuma+eylemdir.

`UyariBalonu.yenile()` pencere yüksekliğini hâlâ **hesaplar**, ölçmez. Anket
satırları daha uzun olduğu için düz çarpma yerine satır satır toplanır
(`yukseklikler` dizisi); SwiftUI ölçüm turunu bekleme yaklaşımına dönülmedi.

## Uyarı mantığı

Karar tek yerde: `Ayarlar.etkinBicim(gonderenID:seviye:)`.

- Dört uyarı biçimi bağımsızdır: ikon, panel, ses, kenar flaşı.
- Kişi bazlı ayar `Ayarlar.kisisel[uyeID]`, yoksa `Ayarlar.varsayilan`.
- **ACİL kişisel ayarları ezer** (`acilEzsin` açıkken) — yoksa acil seviyenin
  anlamı kalmaz.
- **TACİZ her koşulda ezer**, `acilEzsin` kapalı olsa bile. Susturulabilseydi
  taciz olmazdı.
- Normal seviye kasten hafiftir: panel ve kenar flaşı devreye girmez.

**Balonlar kendiliğinden kapanmaz.** Sağ üstteki balon eskiden altı saniyede
siliniyordu ve kullanıcılar okumaya fırsat bulamadıklarını bildirdi; artık
yalnızca "Okudum" düğmesiyle kapanır. Gövdeye tıklamak da kasten bir şey yapmaz.
Zamanlayıcıyı geri koyma. Ekrana sığmayan balonlar düşürülmez, kuyrukta bekleyip
alttaki sayaçta görünür — düşürmek okunmamış seslenmeyi yok etmek olurdu.
Kaçış yolu menüyü açmaktır (`hepsiniTemizle`).

Balon penceresi anahtar pencere olmadığı için barındırıcısı `acceptsFirstMouse`
döndürür; yoksa "Okudum" düğmesine ilk tıklama pencereyi öne getirmek için
harcanır ve iki kez basmak gerekir.

Aynı kişiden arka arkaya gelen çağrılar **tek panelde birleşir**
(`UyariYoneticisi.panelKuyrugunuIsle`). Üç ACİL için üç ayrı pencere açmak,
kullanıcıyı üç kez aynı şeyi kapatmaya zorlar; verilen tek yanıt gruptaki
bütün çağrılara ayrı ayrı gönderilir.

## Taciz seviyesi

`normal < onemli < acil < taciz`. Taciz, alıcının ekranında yanıtlanana kadar
kapanmayan tam ekran pencere (`TacizPenceresi`) ve durmayan alarm açar.

İki yolu var ve ikisinin yetki kuralı **kasten** farklıdır:

- **Elle**: `MaxSeviye` taciz olan biri tek tıkla gönderir. Kurucu bu yetkiyle
  doğar, gerisini o dağıtır.
- **Kendiliğinden**: 15 dakika içinde üçüncü yanıtsız ACİL, `seviyeyiYukselt`
  tarafından tacize çevrilir. Burada ayrıca yetki aranmaz — yetkiyi veren şey
  alıcının üç çağrıyı yanıtsız bırakmış olmasıdır.

Penceredeki geri sayım ve "imha" metni şakadır; bu yüzden en üstte her zaman
Seslen başlığı ve kimin çağırdığı yazar. Şaka olduğu anlaşılmayan bir tam ekran
geri sayım fidye yazılımı sanılır ve kurumsal makinede güvenlik ihbarına yol
açar. Bu çerçeveyi kaldırma.

Panel ve kenar flaşı `.screenSaver` pencere seviyesindedir; tam ekran
uygulamaların ve **Rahatsız Etmeyin kipinin üstünde** görünürler. Sistem
bildirimi bunu yapamaz — bu yüzden bildirime bel bağlanmaz.

## Test

Sunucu testleri `seslen-sunucu/sunucu_test.go` içinde, gerçek WebSocket
istemcileriyle uçtan uca çalışır. Yetki veya akış değiştiren her katkıda
buradaki senaryoları güncelle. Her zaman `-race` ile koştur.

Swift tarafında otomatik test yok; arayüz değişikliklerini `make kur` ile
gerçek uygulamada dene.

## Dağıtım

Apple Developer hesabı **yok**. Uygulama ad-hoc imzalanır (`codesign --sign -`),
DMG olarak GitHub Releases'e yüklenir, Homebrew Cask ile kurulur. Cask'taki
`postflight` karantina bayrağını kaldırır; yoksa kullanıcı "hasarlı" uyarısı alır.

Ad-hoc imza şart: Anahtar Zinciri erişimi ve açılışta başlatma (`SMAppService`)
kararlı bir paket kimliği olmadan çalışmaz.

## Yayınlama

Canlıya çıkış **elle** yapılır, her push'ta değil:

```bash
./yayinla.sh            # yama artır (0.1.3 → 0.1.4), sunucu + uygulama + brew
./yayinla.sh --yan      # yan sürüm artır (0.1.3 → 0.2.0)
./yayinla.sh --ana      # ana sürüm artır (0.1.3 → 1.0.0)
./yayinla.sh --deneme   # ne yapacağını gösterir, yayınlamaz
./yayinla.sh --sunucu   # yalnızca sunucuyu günceller
./yayinla.sh 0.4.0      # sürümü elle belirt
```

Sürüm numarası son git etiketinden okunup artırılır; elle yazmak gerekmez.
Etiketler `--sort=v:refname` ile sıralanır — alfabetik sıralama v0.1.10'u
v0.1.9'dan önce koyardı.

Betik sırasıyla: ön kontroller (temiz dizin, origin/main eşleşmesi, etiket
çakışması, sunucu erişimi) → testler → sunucuya kurulum + sağlık ve WebSocket
doğrulaması → DMG → git etiketi → GitHub release → Homebrew tap güncellemesi.

Herhangi bir adım hata verirse durur (`set -euo pipefail`).

Sunucu hedefi depoda **tutulmaz**. `.yayinla.ornek` dosyasını `.yayinla.yerel`
olarak kopyalayıp `SESLEN_SSH` ve `SESLEN_ALAN` değerlerini doldurun; bu dosya
git tarafından yok sayılır. Sunucuda proje `/srv/seslen` altında, Traefik'in
arkasında çalışır.
