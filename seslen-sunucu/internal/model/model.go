// Package model, Seslen sunucusunun temel veri tiplerini tanımlar.
package model

import "time"

// Seviye, bir seslenmenin aciliyetini belirtir.
type Seviye string

const (
	SeviyeNormal Seviye = "normal"
	SeviyeOnemli Seviye = "onemli"
	SeviyeAcil   Seviye = "acil"
)

// siralama, seviyelerin birbirine göre ağırlığını verir.
var siralama = map[Seviye]int{
	SeviyeNormal: 1,
	SeviyeOnemli: 2,
	SeviyeAcil:   3,
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
type Durum string

const (
	DurumMusait     Durum = "musait"
	DurumMesgul     Durum = "mesgul"
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
