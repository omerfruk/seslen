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

Betik üç biçimi tarar:

1. `systemName:`/`systemImage:`/`systemSymbolName:` çağrılarının argümanı —
   dizgi doğrudan değil, **kapanış parantezine kadarki metinden** çıkarılır.
   Böylece `Image(systemName: kosul ? "a" : "b")` gibi üçlü koşulların içindeki
   adlar da denetlenir. Eskiden dizgi iki noktadan hemen sonra beklenirdi ve bu
   biçim gözden kaçıyordu. Parantezde durmak kasıtlı: satırın tamamı alınsaydı
   `Image(systemName: "x").help("Bir şey")` satırındaki "Bir şey" simge sanılır
   ve paketleme uydurma bir hatayla dururdu.
2. `Seviye.simge` gibi **gövdesi olan `simge` özelliklerinin** içindeki çıplak
   dizgiler. Bu olmadan `Image(systemName: seviye.simge)` hiç denetlenmiyordu —
   tarihî hata tam olarak oradaydı.
3. Süslü parantez şartı sayesinde `BalonOgesi.simge` gibi **saklanan**
   özellikler blok başlangıcı sayılmaz; sayılsaydı tarama dosyanın geri kalanına
   taşıp alakasız dizgileri simge sanardı.

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

**Anket gizli oylama değildir.** `AnketSonucVeri.Oylayanlar` kimin neye oy
verdiğini taşır; kart altındaki ok bunu açar. "Kim çay ister"in cevabı zaten
çayı kime götüreceğindir — sayı tek başına işe yaramaz. Arayüz bunu baştan
belli etmeli ki kimse oyunu gizli sanmasın. Oy sahipleri üye listesi sırasında
paketlenir; map üzerinde dönmek sırayı her yayında değiştirirdi.

İsimleri açan düğme kartta **tek** bir yerde, satır başına değil: satıra
tıklamak oy vermek demek, aynı hareketi iki işe koşmak karışıklık olurdu.

**Panelde yalnızca açık anket durur.** Biten anket kendiliğinden düşer ve
`AnketGecmisi` ekranına havale edilir; kullanıcıların bitmiş anketleri tek tek
temizlemek zorunda kalması şikayet konusuydu ("zamanı geçti, görünmesin").

Süzme iki yerde birden yapılır ve ikisi de gerekli: `anketiYerlestir` gelen
mesajda kapalıysa listeden çıkarır, `acikAnketler` ise her çizimde yeniden
süzer. Yalnızca birincisi olsaydı, **sürenin dolması bir sunucu mesajı
üretmediği için** süresi biten anket panelde asılı kalırdı.

X düğmesi açık ankette de vardır: ilgilenmediğin bir anketi kapatabilmelisin ve
kapattığın geçmişten yine bulunabilir. Gizlenen kimlik
`SunucuIstemcisi.gizlenenAnketler` içinde tutulur ki geç gelen bir sonuç mesajı
kapatılan kartı geri getirmesin.

**Anket bitince hiçbir uyarı çıkmaz.** Kapanış balonu kasten yok: biten anketi
gözden uzak tutmak istenirken kapanışta ekrana bir şey çıkarmak, giderilmeye
çalışılan gürültünün ta kendisi olurdu. Sonucu merak eden geçmişe bakar.

## Geçmiş

Seslenme ve anket geçmişi tek ekranda (`Gorunum/Gecmis.swift`), iki sekmede.
Ayrı düğmeler eklemek panelin üst şeridini kalabalıklaştırırdı.

İkisi de **istenince** çekilir (`TipAnketGecmisiIste`, `TipCagriGecmisiIste`),
bağlanışta değil: liste yalnızca ekran açılınca gerekiyor, her oturumda
indirmenin anlamı yok. Sınırlar `anketGecmisiSiniri` (20) ve
`cagriGecmisiSiniri` (50) — seslenme çok daha sık bir olay. Sabit sayı tarih
aralığına yeğlendi: tarih sınırı yoğun bir günde uzun, sakin bir haftada boş
liste üretir.

Veri zaten kalıcıydı; yalnızca sorgu ve mesaj çiftleri eklendi. Bu yüzden
geçmiş uygulama kapansa da durur.

**Sıralama `gonderildi DESC, rowid DESC`.** İkincil sıra şart: zaman saniye
çözünürlüğünde tutuluyor ve aynı saniyede oluşan iki kayıt yoksa belirsiz
sıralanır, liste her sorguda farklı dizilebilir.

Seslenme geçmişi gelen ve gideni tek listede yön okuyla gösterir. Giden de
gösterilir çünkü gönderen yalnızca geçici bir balon görüyor; "Ali'ye seslenmiş
miydim, yanıtladı mı" sorusunun başka cevabı yok. Yalnızca kendi çağrılarınız
gelir (`SonCagrilar` hem alıcı hem gönderen olarak süzer).

Kurumdan çıkarılmış üyenin çağrıları listede kalır, adı "ayrılmış üye" yazılır;
satırı atmak geçmişte açıklanamayan boşluklar bırakırdı.

Özet (`Anket.ozet`) `acik` olmayan her ankette gösterilir, yalnızca `kapandi`
bayrağında değil — anketlerin çoğu elle kapatılarak değil süresi dolarak biter.

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

**Bildirim izni verilmediğinde menü panelinde uyarı çıkar**
(`AnaGorunum.bildirimIzniSeridi`). Ayarlar → İzinler'de zaten görünüyordu ama
oraya kimse kendiliğinden bakmıyor: izin yokken uygulama sessizce yarım çalışır
ve kullanıcı bunu ancak bir seslenmeyi kaçırdığında fark eder. Şerit
kapatılamaz, çünkü çözümü tek tık uzakta.

Uyarı metni **yalnızca macOS bildiriminin gelmeyeceğini** söyler; ses, panel ve
kenar flaşı izin gerektirmez ve çalışmaya devam eder. "Hiçbir şey duymayacaksın"
demek yalan olurdu. Geliştirme kipi (`kullanilamaz`) şeridi tetiklemez —
düzeltilecek bir şey olmayan uyarı yalnızca gürültüdür.

## Sesler

Seviye başına ses `Ayarlar.sesler` içinde tutulur ve kullanıcı değiştirebilir
(Ayarlar → Uyarılar). Varsayılanlar `UyariSesi.varsayilan`'da.

**Gömülü sesler çalışma anında üretilir** (`SesUretici`), pakete ses dosyası
konmaz. Gerekçe: macOS'un yerleşik seslerinin hepsi tek vuruşluk ve ya çok cılız
(Tink) ya boğuk (Basso); iPhone'un bildirim sesine benzeyen bir şey yok.
Üretilen WAV `NSSound(data:)` ile çalınır ve `SesUretici.bellek`'te saklanır.

Seviyeler yalnızca yükseklikle değil **nota sayısı ve ritimle** de ayrılır:
kullanıcı ekrana bakmadan hangi seviyede seslenildiğini duyabilmeli. Bu yüzden
normal üç yükselen nota, önemli çift ding, acil aynı notanın hızlı tekrarı,
taciz iki notalı alçak alarm.

`SesNotasi.tini` iki değer alır. `.zil` taşıyıcının üstüne kaydırılmış üst
sesler bindirir (2.01 ve 3.02 kat) — tam kat kullanmak sesi metalik zilden
sentetik bir org tonuna çevirirdi. `.duz` katıksız sinüstür ve yalnızca alarmda
kullanılır: hoş duyulmaması kasıtlı.

Notalar üst üste bindiğinde toplam genlik 1.0'ı aşabiliyor; `wav` tepe değere
göre ölçekler. Kırpılmış sinüs zil değil cızırtı gibi duyulur.

**Her çalışta yeni `NSSound` örneği kurulur.** Aynı örneği yeniden kullanmak,
tekrarlı ACİL'de ikinci vuruşun sessiz kalmasına yol açıyor.

**ACİL tekrar zinciri `SesCalar.nesil` ile iptal edilir.** `asyncAfter` ile
zincirlenen adımlar iptal edilemiyordu: ACİL tacize yükseldiğinde uçuştaki adım
`calan?.stop()` diyerek alarmı ortasından kesiyor, kullanıcı tacizi yanıtlayıp
her şeyi kapattıktan sonra da iki hayalet bip duyuyordu. Yeni çalma isteği ve
`tacizDurdur` nesli artırır; uyanan eski adım kendini geçersiz bulur.

**`Ayarlar.Kayit.sesler` ham metin olarak saklanır, `UyariSesi` olarak değil.**
Enum olarak çözülseydi tanınmayan tek bir ses adı — yeni sürümde seçip eski
sürüme dönmek buna yeter — `Kayit`'in tamamını çözümlenemez yapar, `yukle` erken
döner ve sunucu adresinden kişisel susturmalara kadar **bütün ayarlar** sessizce
varsayılana düşerdi. Opsiyonel alan yalnızca *yokluğu* karşılar, *tanınmayan
değeri* değil. Yükleme `compactMapValues` ile tanınmayanı düşürür, kaydı değil.

## Ad değiştirme

Kişi kendi adını Ayarlar → Genel'den değiştirir (`ad_degistir`), yönetici
başkasının adını Kurum penceresinden düzeltir (`uye_ad_guncelle`).

**İki ayrı mesaj tipi olması kasıtlı.** `AdDegistirIstek` üye kimliği taşımaz;
hedef bağlantıdan okunur ve böylece başkasına dokunma ihtimali baştan yok olur.
Kimlik alanı eklenseydi sunucu her istekte "bu senin kimliğin mi" kontrolü
yapmak zorunda kalırdı. Yetki isteyen işlem kendi kapısından girer ve
`yonetimDogrula`'nın üç güvencesine tabi olur — kurucunun adına yalnızca
kendisi dokunabilir.

**`AdDuzelt` görünmez karakterleri ayıklar.** Sıfır genişlikli boşluk (U+200B)
içeren bir ad ekranda mevcut bir üyeyle **birebir aynı** görünür; süzülmediği
sürece isim benzersizliği tek karakterle tamamen atlatılabiliyordu (kurucu
"Ömer" varken ikinci bir "Ömer" yaratmak mümkündü). Aynı kol yön değiştirme
işaretlerini (U+202E) ve denetim karakterlerini de düşürür. Boşluk sayılanlar
silinmez, düz boşluğa çevrilir — silinseydi "Ali\nVeli" → "AliVeli" olurdu.

Ad ayrıca **NFC'ye** normalleştirilir: macOS'tan kopyalanan metin ayrık gelir
("Ö" = O + U+0308) ve normalleştirilmezse aynı ad iki farklı bayt dizisi olarak
saklanıp benzersizlikten kaçar. En az bir harf şartı da var; "12", "!!" ya da
yalnızca emoji kimseyi tanıtmaz.

**İsim benzersizliği Go'da denetlenir, SQL'de değil** (`store.isimDolu`).
SQLite'ın `LOWER()`'ı yalnızca ASCII çevirir: "Ömer" ile "ömer" onun gözünde
iki ayrı isimdir ve kural Türkçe adlarda yıllarca sessizce çalışmadı.
`model.AdAnahtari` ayrıca I/İ'yi elle çevirir — Go'nun `ToLower`'ı da Türkçeyi
değil İngilizceyi izler.

Kontrol katılımda **ve** ad değiştirmede yapılır; yalnızca katılımda olsaydı
engellenen çakışma sonradan ad değiştirerek yapılabilirdi. Üyenin kendi satırı
dışarıda bırakılır, yoksa "ali veli" → "Ali Veli" gibi yalnızca büyük harf
düzelten bir değişiklik kendi kendine takılırdı.

Kontrol ile yazma arasında `store.isimMu` kilidi var ve **ikisi de aynı kilidi
kullanır** (`AdGuncelle` ve `KurumaKatil`). Kilitsiz hâlde yarış teorik değil
pratikti: `SetMaxOpenConns(1)` yüzünden biri okumayı bitirip bağlantıyı bırakınca
sıradaki hemen okuyor, iki yazma da sona kalıyordu — denemede 25/25 çift isim.
Tabloda UNIQUE kısıt yok, oluşan çift kalıcı olurdu.

**Ad kutusundan odak kaybı kaydetmez** (hem `AdDuzenleyici` hem `AdAlani`).
Kaydetseydi "Ali"yi düzeltmeye başlayıp "Al" yazmışken başka yere tıklamak,
yarım kalmış adı `KurumaYayinla` ile tüm kuruma yayardı — üstelik iki harf
olduğu için doğrulamadan da geçerek. Kaydetmenin yolu Enter ya da düğme.

Sunucunun cevabı Ayarlar penceresinde de gösterilir. `sonHata` yalnızca menü
panelinde ve Kurum penceresinde çiziliyordu; ad alanı Ayarlar'dan sunucuya yazan
ilk denetim olduğu için "bu isimde bir üye zaten var" kullanıcıya hiç ulaşmıyor,
ekranda hiçbir şey olmamış gibi duruyordu.

Değişiklik `KurumaYayinla` ile tüm kuruma gider: ad herkesin listesinde ve gelen
çağrı balonlarında görünür. Geçmiş kayıtlar ada göre değil kimliğe göre
saklandığı için eski seslenmeler de yeni adla görünür — istenen de bu, yanlış
yazılmış bir isim geçmişte de düzelmeli.

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

### Kendi kendine güncelleme

`GuncellemeDenetcisi` yalnızca haber vermiyor, kuruyor: son yayımın DMG'sini
indirir, bağlar ve içindeki paketi çalışan uygulamanın üzerine kopyalar. Sparkle
kullanılmadı — imzalı paket ve Apple hesabı ister, ikisi de yok. Ad-hoc imza
bunu engellemiyor; değişen tek şey diskteki paket.

**Değiştirmeyi uygulama kendisi yapamaz.** Kendi paketini silen bir süreç
altından zemini çeker: kopyalama yarıda kalırsa ne eski ne yeni uygulama kalır.
İş, uygulamanın kapanmasını bekleyen ayrı bir kabuk betiğine devredilir
(`kurulumBetigi`) ve o betik eski paketi silmez, **yeniden adlandırır** —
kopya tutmazsa geri dönecek bir şey kalsın.

**DMG `-plist` ile bağlanır, çıktısı ayrıştırılarak.** `hdiutil attach` çağrısına
`-quiet` **verilmez**: `-quiet`, çıkış kodunu 0 bırakır ama bağlama noktası
çıktısını da bastırır — geriye ayrıştıracak hiçbir şey kalmaz, `bagla` nokta
bulamaz ve kurulum "İndirilen paket açılamadı" ile ölür. Bu hata bir kez
yayınlandı (v0.1.7) çünkü indirme izole test edilmiş ama attach→kopyala zinciri
uçtan uca hiç çalıştırılmamıştı. Kendi kendine güncellemeye dokunan her katkı
gerçek bir DMG'yi indirip bağlamalı, "derlendi"yle yetinmemeli. `-quiet`, tıpkı
SF Symbol'ün sessizce boş çizmesi gibi, hatayı çalışma anına erteleyen bir
"sessizce boş çıktı" tuzağıdır.

Kopya `ditto` ile yapılır; `cp -R` uygulama paketlerindeki sembolik bağları ve
genişletilmiş öznitelikleri olduğu gibi taşımaz. Karantina bayrağı elle silinir,
gerekçesi Cask'taki `postflight` ile aynı.

Yazma izni **indirmeden önce** sorulur (`kurabilir`): /Applications altındaki bir
uygulamayı yönetici olmayan kullanıcı değiştiremez ve 15 MB indirip sonunda
"izin yok" demek kullanıcının vaktini harcamaktır. O durumda brew komutu
gösterilir — eski davranış kaybolmadı, yedeğe düştü.

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
