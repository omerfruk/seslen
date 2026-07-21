// Package model, Seslen sunucusunun temel veri tiplerini tanımlar.
package model

import (
	"strings"
	"time"
	"unicode"

	"golang.org/x/text/unicode/norm"
)

// Seviye, bir seslenmenin aciliyetini belirtir.
type Seviye string

const (
	SeviyeNormal Seviye = "normal"
	SeviyeOnemli Seviye = "onemli"
	SeviyeAcil   Seviye = "acil"
	// SeviyeTaciz, yanıtsız kalan ACİL çağrıların üstüne çıkan son basamaktır.
	// Alıcının ekranında kapanmayan, geri sayan ve sürekli çalan bir uyarı açar.
	SeviyeTaciz Seviye = "taciz"
)

// siralama, seviyelerin birbirine göre ağırlığını verir.
var siralama = map[Seviye]int{
	SeviyeNormal: 1,
	SeviyeOnemli: 2,
	SeviyeAcil:   3,
	SeviyeTaciz:  4,
}

// Gecerli, seviyenin tanımlı değerlerden biri olup olmadığını söyler.
func (s Seviye) Gecerli() bool {
	_, ok := siralama[s]
	return ok
}

// Kapsar, bu seviyenin verilen seviyeyi göndermeye yetip yetmediğini söyler.
// Örnek: SeviyeOnemli.Kapsar(SeviyeNormal) == true
func (s Seviye) Kapsar(diger Seviye) bool {
	return siralama[s] >= siralama[diger]
}

// MesguldeBekler, alıcı meşgulken bu seviyenin bekletilip anında iletilmeyeceğini
// söyler.
//
// Acil ve tacizin geçmesi kasıtlıdır: meşgul acili susturabilseydi acil
// seviyesinin anlamı kalmazdı. Bu, istemcideki `Ayarlar.acilEzsin` mantığının
// sunucu tarafındaki karşılığıdır.
func (s Seviye) MesguldeBekler() bool {
	return siralama[s] < siralama[SeviyeAcil]
}

// Rol, üyenin kurum içindeki konumudur.
type Rol string

const (
	RolKurucu   Rol = "kurucu"
	RolYonetici Rol = "yonetici"
	RolUye      Rol = "uye"
)

// YonetimYetkisi, rolün kurum ayarlarını değiştirip değiştiremeyeceğini söyler.
func (r Rol) YonetimYetkisi() bool {
	return r == RolKurucu || r == RolYonetici
}

// Durum, üyenin o anki müsaitlik bilgisidir.
//
// Veritabanındaki kolon yalnızca kullanıcının *tercihini* tutar: musait veya
// mesgul. Çevrimiçilik ayrı bir eksendir ve hub'ın canlı bağlantı kaydından
// türetilir (`KurumaYayinla`). Eskiden bağlantı kopunca kolona "cevrimdisi"
// yazılıyordu; bu, varlığın tercihi ezmesi demekti ve kullanıcının meşgul
// seçimi her kopuşta sessizce siliniyordu.
type Durum string

const (
	DurumMusait Durum = "musait"
	DurumMesgul Durum = "mesgul"
	// DurumCevrimdisi yalnızca tel üstünde geçerlidir; veritabanına yazılmaz.
	DurumCevrimdisi Durum = "cevrimdisi"
)

// Gecerli, durumun tanımlı değerlerden biri olup olmadığını söyler.
func (d Durum) Gecerli() bool {
	return d == DurumMusait || d == DurumMesgul || d == DurumCevrimdisi
}

// Kurum, birlikte çalışan ekibi temsil eder.
type Kurum struct {
	ID          string    `json:"id"`
	Ad          string    `json:"ad"`
	KatilimKodu string    `json:"katilimKodu"`
	Olusturuldu time.Time `json:"olusturuldu"`
}

// Uye, bir kuruma bağlı kullanıcıdır.
type Uye struct {
	ID          string    `json:"id"`
	KurumID     string    `json:"-"`
	AdSoyad     string    `json:"adSoyad"`
	Rol         Rol       `json:"rol"`
	MaxSeviye   Seviye    `json:"maxSeviye"`
	Onayli      bool      `json:"onayli"`
	Durum       Durum     `json:"durum"`
	SonGorulme  time.Time `json:"sonGorulme"`
	Olusturuldu time.Time `json:"olusturuldu"`

	// Cevrimici, veritabanında tutulmaz; hub tarafından anlık doldurulur.
	Cevrimici bool `json:"cevrimici"`
}

// Ad uzunluk sınırları. Üst sınır listedeki satırın taşmaması içindir; alt
// sınır tek harflik adın kimseyi tanıtmamasından.
const (
	minAdUzunlugu  = 2
	maksAdUzunlugu = 40
)

// AdDuzelt, kullanıcının yazdığı adı normalleştirir ve kabul edilebilir olup
// olmadığını söyler.
//
// Uzunluk bayta değil harfe göre ölçülür — Türkçe harfler iki bayt tutuyor ve
// bayt saymak "Şükrü Güngör"ü sebepsiz reddederdi.
func AdDuzelt(ham string) (string, bool) {
	// Önce birleşik biçim. macOS'tan (Finder, dosya adları) kopyalanan metin
	// ayrık gelir: "Ö" = O + U+0308. Normalleştirilmezse aynı ad iki farklı
	// bayt dizisi olarak saklanır ve benzersizlik kontrolünden kaçar.
	ad := norm.NFC.String(ham)

	// Görünmez karakterler ayıklanır. Sıfır genişlikli boşluk (U+200B) içeren
	// bir ad ekranda mevcut bir üyeyle **birebir aynı** görünür; süzülmezse
	// isim benzersizliği tek karakterle tamamen atlatılabilir. Yön değiştirme
	// işaretleri (U+202E) ise satırın kalanını ters çizdirir.
	ad = strings.Map(func(r rune) rune {
		// Boşluk sayılanlar ayıklanmaz, düz boşluğa çevrilir: satır sonu ya da
		// sekme bir *ayırıcıdır*, silinseydi "Ali\nVeli" → "AliVeli" olurdu.
		// U+200B bu dalın dışında kalır — Unicode onu boşluk saymaz, biçim
		// karakteri sayar; aşağıdaki kol yakalar.
		if unicode.IsSpace(r) {
			return ' '
		}
		if unicode.Is(unicode.Cf, r) || !unicode.IsGraphic(r) {
			return -1
		}
		return r
	}, ad)

	// Boşluklar toplanır: "Ali   Veli" ile "Ali Veli" listede iki ayrı isim
	// gibi durur ve yine benzersizlik kontrolünü atlatırdı.
	ad = strings.Join(strings.Fields(ad), " ")

	harfler := []rune(ad)
	if len(harfler) < minAdUzunlugu || len(harfler) > maksAdUzunlugu {
		return "", false
	}
	// En az bir harf şart: "12", "!!" ya da yalnızca emoji kimseyi tanıtmaz ve
	// hata metni de zaten "harf" diyor.
	if !strings.ContainsFunc(ad, unicode.IsLetter) {
		return "", false
	}
	return ad, true
}

// adDegistirici, isim anahtarındaki Türkçeye özgü harf çevrimi.
//
// Paket düzeyinde: `isimDolu` her üye için bir kez `AdAnahtari` çağırıyor,
// çeviriciyi her seferinde yeniden kurmanın anlamı yok.
//
// Yalnızca `I` var. `İ` gerekmiyor çünkü Go'nun `ToLower`'ı onu zaten tek rune
// hâlinde `i`'ye çeviriyor; `I` ise İngilizce kuralla `i` olurdu ve "Işıl" ile
// "ışıl" farklı anahtarlar üretirdi.
var adDegistirici = strings.NewReplacer("I", "ı")

// AdAnahtari, iki adın "aynı isim" sayılıp sayılmayacağını karşılaştırmak için
// kullanılan normal biçimi üretir.
//
// SQLite'ın `LOWER()`'ı yalnızca ASCII çevirir: "Ömer" ile "ömer" onun gözünde
// iki ayrı isimdir ve isim benzersizliği Türkçe adlarda hiç çalışmaz. Bu yüzden
// karşılaştırma veritabanında değil burada yapılır.
func AdAnahtari(ad string) string {
	return strings.ToLower(adDegistirici.Replace(norm.NFC.String(ad)))
}

// Cagri, gönderilmiş bir seslenmenin kaydıdır.
type Cagri struct {
	ID         string    `json:"id"`
	KurumID    string    `json:"-"`
	GonderenID string    `json:"gonderenID"`
	AliciID    string    `json:"aliciID"`
	Seviye     Seviye    `json:"seviye"`
	Not        string    `json:"not"`
	Gonderildi time.Time `json:"gonderildi"`
	Yanit      string    `json:"yanit,omitempty"`
	YanitTarih time.Time `json:"yanitTarih,omitzero"`
}

// Yanıt sabitleri: alıcının çağrıya verebileceği hazır cevaplar.
const (
	YanitGeliyorum = "geliyorum"
	YanitBekle     = "bekle"
	YanitGorduem   = "gordum"
)

// GecerliYanit, yanıt değerinin tanımlı olup olmadığını söyler.
func GecerliYanit(y string) bool {
	return y == YanitGeliyorum || y == YanitBekle || y == YanitGorduem
}

// Anket, kuruma sorulan çoktan seçmeli kısa sorudur ("Kim çay ister?").
//
// Seslenmeden farkı: kesmez, kuyruğa girmez ve bir süresi vardır. Masalarda
// dolaşıp tek tek sormanın yerini alır.
type Anket struct {
	ID         string    `json:"id"`
	KurumID    string    `json:"-"`
	GonderenID string    `json:"gonderenID"`
	Soru       string    `json:"soru"`
	Secenekler []string  `json:"secenekler"`
	Gonderildi time.Time `json:"gonderildi"`
	Bitis      time.Time `json:"bitis"`
	Kapandi    bool      `json:"kapandi"`
}

// Acik, ankete hâlâ oy verilebilir mi? Kapanış tembeldir: arka planda anket
// başına zamanlayıcı tutmak yerine her okumada süre süzülür. Böylece sunucu
// yeniden başladığında da doğru davranır.
func (a Anket) Acik(simdi time.Time) bool {
	return !a.Kapandi && simdi.Before(a.Bitis)
}

// Anket sınırları.
const (
	AnketEnAzSecenek     = 2
	AnketEnCokSecenek    = 5
	AnketSecenekUzunlugu = 24
)

// SeceneklerGecerli, kullanıcının girdiği seçenekleri temizler ve doğrular.
//
// Büyük/küçük harf duyarsız tekrar reddedilir: "Çay" ve "çay" iki ayrı çubuk
// olarak çizilirse sonuç okunamaz hale gelir.
func SeceneklerGecerli(ham []string) ([]string, bool) {
	temiz := make([]string, 0, len(ham))
	gorulen := make(map[string]struct{}, len(ham))

	for _, s := range ham {
		s = strings.TrimSpace(s)
		if s == "" {
			continue
		}
		// Sınır harf sayısına göre: bayt sayarak kesmek Türkçe harflerin
		// ortasından bölüp bozuk UTF-8 üretir.
		if harfler := []rune(s); len(harfler) > AnketSecenekUzunlugu {
			s = string(harfler[:AnketSecenekUzunlugu])
		}
		anahtar := strings.ToLower(s)
		if _, varsa := gorulen[anahtar]; varsa {
			return nil, false
		}
		gorulen[anahtar] = struct{}{}
		temiz = append(temiz, s)
	}

	if len(temiz) < AnketEnAzSecenek || len(temiz) > AnketEnCokSecenek {
		return nil, false
	}
	return temiz, true
}
