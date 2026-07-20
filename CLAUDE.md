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

**4. Onay bekleyen üye de bağlı kalır.**
`hub.KurumaYayinla`, alıcıyı önce onaylı listede sonra bekleyen listede arar.
Yalnızca onaylı listede arayıp bulamayınca oturumu kapatmak, katılan hiç
kimsenin "onay bekleniyor" ekranını görememesine yol açar.

## Uyarı mantığı

Karar tek yerde: `Ayarlar.etkinBicim(gonderenID:seviye:)`.

- Dört uyarı biçimi bağımsızdır: ikon, panel, ses, kenar flaşı.
- Kişi bazlı ayar `Ayarlar.kisisel[uyeID]`, yoksa `Ayarlar.varsayilan`.
- **ACİL kişisel ayarları ezer** (`acilEzsin` açıkken) — yoksa acil seviyenin
  anlamı kalmaz.
- Normal seviye kasten hafiftir: panel ve kenar flaşı devreye girmez.

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
./yayinla.sh 0.1.3            # sunucu + uygulama + brew tap
./yayinla.sh 0.1.3 --deneme   # ne yapacağını gösterir, yayınlamaz
./yayinla.sh --sunucu         # yalnızca sunucuyu günceller
```

Betik sırasıyla: ön kontroller (temiz dizin, origin/main eşleşmesi, etiket
çakışması, sunucu erişimi) → testler → sunucuya kurulum + sağlık ve WebSocket
doğrulaması → DMG → git etiketi → GitHub release → Homebrew tap güncellemesi.

Herhangi bir adım hata verirse durur (`set -euo pipefail`).

Sunucu: `deploy@204.168.229.111:/srv/seslen`, Traefik arkasında
`https://seslen.cidaltime.com`. Farklı bir hedef için `SESLEN_SSH` ve
`SESLEN_ALAN` ortam değişkenleri kullanılır.
