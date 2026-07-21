// Package model, Seslen sunucusunun temel veri tiplerini tanımlar.
package model

import (
	"strings"
	"time"
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
