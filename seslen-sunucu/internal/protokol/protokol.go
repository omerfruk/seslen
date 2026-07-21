// Package protokol, istemci ile sunucu arasındaki WebSocket mesaj sözleşmesidir.
// Swift tarafındaki Sources/Seslen/Ag/Protokol.swift bu dosyanın birebir karşılığıdır;
// biri değişince diğeri de değişmelidir.
package protokol

import (
	"encoding/json"

	"github.com/omerfruk/seslen/seslen-sunucu/internal/model"
)

// Tip, zarfın taşıdığı mesaj türüdür.
type Tip string

// İstemciden sunucuya giden mesaj tipleri.
const (
	TipSeslen      Tip = "seslen"       // birine seslen
	TipHaykir      Tip = "haykir"       // kurumdaki herkese birden seslen
	TipYanitla     Tip = "yanitla"      // gelen çağrıya yanıt ver
	TipDurumBildir Tip = "durum_bildir" // kendi durumunu değiştir
	TipUyeGuncelle Tip = "uye_guncelle" // (yönetim) üye rolü/yetkisi değiştir
	TipUyeOnayla   Tip = "uye_onayla"   // (yönetim) bekleyen üyeyi onayla
	TipUyeSil      Tip = "uye_sil"      // (yönetim) üyeyi kurumdan çıkar
	TipKodYenile   Tip = "kod_yenile"   // (yönetim) katılım kodunu yenile
	TipNabiz       Tip = "nabiz"        // bağlantı canlılık kontrolü
)

// Sunucudan istemciye giden mesaj tipleri.
const (
	TipDurumTam      Tip = "durum_tam"      // kurumun tam anlık görüntüsü
	TipSeslenmeGeldi Tip = "seslenme_geldi" // sana biri sesleniyor
	TipKacirilanlar  Tip = "kacirilanlar"   // sen yokken birikenler
	TipYanitGeldi    Tip = "yanit_geldi"    // seslendiğin kişi yanıtladı
	TipBilgi         Tip = "bilgi"          // işlem kabul edildi, bilgi notu var
	TipHata          Tip = "hata"           // işlem reddedildi
	TipNabizYanit    Tip = "nabiz_yanit"    // nabız cevabı
)

// Zarf, tüm mesajların dış kabuğudur. Veri alanı Tip'e göre çözümlenir.
type Zarf struct {
	Tip  Tip             `json:"tip"`
	Veri json.RawMessage `json:"veri,omitempty"`
}

// --- İstemci → Sunucu gövdeleri ---

// SeslenIstek, bir üyeye seslenme talebidir.
type SeslenIstek struct {
	AliciID string       `json:"aliciID"`
	Seviye  model.Seviye `json:"seviye"`
	Not     string       `json:"not"`
}

// HaykirIstek, kurumdaki herkese aynı anda seslenme talebidir.
// Seviye taşımaz: yayın her zaman normal seviyede gider.
type HaykirIstek struct {
	Not string `json:"not"`
}

// YanitlaIstek, gelen bir çağrıya verilen cevaptır.
type YanitlaIstek struct {
	CagriID string `json:"cagriID"`
	Yanit   string `json:"yanit"`
}

// DurumBildirIstek, kullanıcının kendi müsaitlik durumunu günceller.
type DurumBildirIstek struct {
	Durum model.Durum `json:"durum"`
}

// UyeGuncelleIstek, bir üyenin rolünü ve gönderebileceği en yüksek seviyeyi ayarlar.
type UyeGuncelleIstek struct {
	UyeID     string       `json:"uyeID"`
	Rol       model.Rol    `json:"rol"`
	MaxSeviye model.Seviye `json:"maxSeviye"`
}

// UyeIDIstek, tek bir üyeyi hedefleyen basit işlemler için kullanılır.
type UyeIDIstek struct {
	UyeID string `json:"uyeID"`
}

// --- Sunucu → İstemci gövdeleri ---

// DurumTamVeri, istemcinin ekranı çizmek için ihtiyaç duyduğu her şeyi taşır.
type DurumTamVeri struct {
	Kurum    model.Kurum `json:"kurum"`
	Ben      model.Uye   `json:"ben"`
	Uyeler   []model.Uye `json:"uyeler"`
	Bekleyen []model.Uye `json:"bekleyen"`

	// BekleyenCagri, alıcı meşgulken kuyruğa alınmış çağrı sayısıdır. Yalnızca
	// "ben" meşgulken doldurulur: meşgul, geri bildirimi olmayan bir kuyuya
	// dönüşmemeli — kullanıcı kaç kişinin seslendiğini görüp müsaite dönmeye
	// kendi karar verebilmeli. Başkalarının kuyruk derinliği kimseyi ilgilendirmez.
	BekleyenCagri int `json:"bekleyenCagri"`
}

// SeslenmeGeldiVeri, alıcıya iletilen çağrıdır.
type SeslenmeGeldiVeri struct {
	CagriID    string       `json:"cagriID"`
	GonderenID string       `json:"gonderenID"`
	GonderenAd string       `json:"gonderenAd"`
	Seviye     model.Seviye `json:"seviye"`
	Not        string       `json:"not"`
	Gonderildi int64        `json:"gonderildi"` // unix saniye
	// Yayin, çağrının tek kişiye değil kurumdaki herkese gittiğini söyler.
	// İstemci uyarıyı buna göre "haykırdı" diye yazar.
	Yayin bool `json:"yayin"`
}

// KacirilanlarVeri, üye çevrimdışıyken biriken çağrıları tek mesajda taşır.
//
// Her biri ayrı ayrı `seslenme_geldi` olarak yollansaydı, bilgisayarını açan
// kullanıcının ekranına arka arkaya paneller yağardı; istemci bunu tek bir
// "sen yokken 3 seslenme" özeti olarak gösterir.
type KacirilanlarVeri struct {
	Cagrilar []SeslenmeGeldiVeri `json:"cagrilar"`
	// Sebep, çağrıların neden birikmiş olduğunu söyler. İstemci başlığı buna
	// göre yazar: "Sen yokken 3 seslenme" ile "Meşguldeyken 3 seslenme" farklı
	// şeylerdir ve ikincisine "yoktun" demek kullanıcıyı yanıltır.
	Sebep string `json:"sebep"`
}

// Kaçırılma sebepleri.
const (
	SebepCevrimdisi = "cevrimdisi"
	SebepMesgul     = "mesgul"
)

// BilgiVeri, reddedilmemiş ama kullanıcıya söylenmesi gereken bir durumu taşır.
type BilgiVeri struct {
	Mesaj string `json:"mesaj"`
}

// YanitGeldiVeri, gönderene dönen cevaptır.
type YanitGeldiVeri struct {
	CagriID    string `json:"cagriID"`
	AliciID    string `json:"aliciID"`
	AliciAd    string `json:"aliciAd"`
	Yanit      string `json:"yanit"`
	YanitTarih int64  `json:"yanitTarih"`
}

// HataVeri, reddedilen bir isteğin sebebini taşır.
type HataVeri struct {
	Kod   string `json:"kod"`
	Mesaj string `json:"mesaj"`
}

// Hata kodları.
const (
	HataYetkisiz   = "yetkisiz"
	HataBulunamadi = "bulunamadi"
	HataGecersiz   = "gecersiz"
	HataSunucu     = "sunucu"
)

// Paketle, bir gövdeyi zarfa sarıp JSON'a çevirir.
func Paketle(tip Tip, veri any) ([]byte, error) {
	zarf := Zarf{Tip: tip}
	if veri != nil {
		ham, err := json.Marshal(veri)
		if err != nil {
			return nil, err
		}
		zarf.Veri = ham
	}
	return json.Marshal(zarf)
}

// HataPaketle, hata zarfını hazırlar.
func HataPaketle(kod, mesaj string) []byte {
	ham, _ := Paketle(TipHata, HataVeri{Kod: kod, Mesaj: mesaj})
	return ham
}

// BilgiPaketle, bilgi zarfını hazırlar.
func BilgiPaketle(mesaj string) []byte {
	ham, _ := Paketle(TipBilgi, BilgiVeri{Mesaj: mesaj})
	return ham
}
