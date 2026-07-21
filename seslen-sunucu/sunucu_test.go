package main

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"

	"github.com/omerfruk/seslen/seslen-sunucu/internal/api"
	"github.com/omerfruk/seslen/seslen-sunucu/internal/hub"
	"github.com/omerfruk/seslen/seslen-sunucu/internal/model"
	"github.com/omerfruk/seslen/seslen-sunucu/internal/protokol"
	"github.com/omerfruk/seslen/seslen-sunucu/internal/store"
)

// ortam, test için ayağa kaldırılmış bir sunucuyu temsil eder.
type ortam struct {
	t   *testing.T
	srv *httptest.Server
}

func ortamKur(t *testing.T) *ortam {
	t.Helper()

	depo, err := store.Ac(filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatalf("veritabanı açılamadı: %v", err)
	}
	t.Cleanup(func() { depo.Kapat() })

	sessiz := slog.New(slog.NewTextHandler(io.Discard, nil))
	merkez := hub.Yeni(depo, sessiz)
	srv := httptest.NewServer(api.Yeni(depo, merkez, sessiz).Yonlendirici())
	t.Cleanup(srv.Close)

	return &ortam{t: t, srv: srv}
}

// gonderJSON, bir POST isteği atıp yanıtı çözümler.
func (o *ortam) gonderJSON(yol string, govde any) (int, map[string]any) {
	o.t.Helper()
	ham, _ := json.Marshal(govde)
	yanit, err := http.Post(o.srv.URL+yol, "application/json", bytes.NewReader(ham))
	if err != nil {
		o.t.Fatalf("istek başarısız (%s): %v", yol, err)
	}
	defer yanit.Body.Close()

	var cozum map[string]any
	json.NewDecoder(yanit.Body).Decode(&cozum)
	return yanit.StatusCode, cozum
}

// istemci, testte kullanılan tek bir WebSocket oturumudur.
type istemci struct {
	t     *testing.T
	ws    *websocket.Conn
	token string
	id    string
}

func (o *ortam) baglan(token, id string) *istemci {
	o.t.Helper()
	wsURL := "ws" + strings.TrimPrefix(o.srv.URL, "http") + "/ws?token=" + url.QueryEscape(token)
	ws, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		o.t.Fatalf("websocket bağlanamadı: %v", err)
	}
	o.t.Cleanup(func() { ws.Close() })
	return &istemci{t: o.t, ws: ws, token: token, id: id}
}

func (c *istemci) yolla(tip protokol.Tip, veri any) {
	c.t.Helper()
	ham, err := protokol.Paketle(tip, veri)
	if err != nil {
		c.t.Fatalf("paketlenemedi: %v", err)
	}
	if err := c.ws.WriteMessage(websocket.TextMessage, ham); err != nil {
		c.t.Fatalf("yazılamadı: %v", err)
	}
}

// bekle, belirtilen tipte bir mesaj gelene kadar okur; diğer mesajları atlar.
func (c *istemci) bekle(tip protokol.Tip, sure time.Duration) protokol.Zarf {
	c.t.Helper()
	bitis := time.Now().Add(sure)
	for {
		if time.Now().After(bitis) {
			c.t.Fatalf("%q mesajı %v içinde gelmedi", tip, sure)
		}
		c.ws.SetReadDeadline(bitis)
		_, ham, err := c.ws.ReadMessage()
		if err != nil {
			c.t.Fatalf("%q beklenirken okuma hatası: %v", tip, err)
		}
		var zarf protokol.Zarf
		if err := json.Unmarshal(ham, &zarf); err != nil {
			c.t.Fatalf("çözümlenemedi: %v", err)
		}
		if zarf.Tip == tip {
			return zarf
		}
	}
}

// beklemeyen, sinir tipindeki mesaja kadar okur ve arada istenmeyen tipte bir
// mesaj görürse testi düşürür. Bir şeyin gönderilMEdiğini doğrulamak içindir:
// tek bir bağlantıda mesaj sırası korunduğu için, sınır mesajı geldiğinde
// öncesindeki her şey okunmuş olur.
func (c *istemci) beklemeyen(istenmeyen, sinir protokol.Tip, sure time.Duration) {
	c.t.Helper()
	bitis := time.Now().Add(sure)
	for {
		if time.Now().After(bitis) {
			c.t.Fatalf("%q mesajı %v içinde gelmedi", sinir, sure)
		}
		c.ws.SetReadDeadline(bitis)
		_, ham, err := c.ws.ReadMessage()
		if err != nil {
			c.t.Fatalf("%q beklenirken okuma hatası: %v", sinir, err)
		}
		var zarf protokol.Zarf
		if err := json.Unmarshal(ham, &zarf); err != nil {
			c.t.Fatalf("çözümlenemedi: %v", err)
		}
		if zarf.Tip == istenmeyen {
			c.t.Fatalf("%q mesajı gönderilmemeliydi", istenmeyen)
		}
		if zarf.Tip == sinir {
			return
		}
	}
}

// kurumOrtami, kurucusu Ömer ve onaylı üyesi Ali olan hazır bir kurumdur.
type kurumOrtami struct {
	omer, ali           *istemci
	omerID, aliID       string
	omerToken, aliToken string
}

// ikiKisilikKurum, iki kişilik onaylı bir kurum kurup ikisini de bağlar.
// Meşgul senaryolarının tamamı bu iskeleti paylaşıyor.
func ikiKisilikKurum(o *ortam) kurumOrtami {
	o.t.Helper()

	_, yanit := o.gonderJSON("/api/kurum/olustur", map[string]string{
		"kurumAd": "HAY Teknoloji", "kurucuAd": "Ömer",
	})
	k := kurumOrtami{
		omerToken: yanit["token"].(string),
		omerID:    yanit["ben"].(map[string]any)["id"].(string),
	}
	katilimKodu := yanit["kurum"].(map[string]any)["katilimKodu"].(string)

	_, yanit = o.gonderJSON("/api/kurum/katil", map[string]string{
		"kod": katilimKodu, "adSoyad": "Ali Veli",
	})
	k.aliToken = yanit["token"].(string)
	k.aliID = yanit["ben"].(map[string]any)["id"].(string)

	k.omer = o.baglan(k.omerToken, k.omerID)
	k.omer.bekle(protokol.TipDurumTam, 2*time.Second)
	k.ali = o.baglan(k.aliToken, k.aliID)
	k.ali.bekle(protokol.TipDurumTam, 2*time.Second)
	k.omer.yolla(protokol.TipUyeOnayla, protokol.UyeIDIstek{UyeID: k.aliID})
	k.ali.bekle(protokol.TipDurumTam, 2*time.Second)

	return k
}

// mesgulOl, üyeyi meşgule çeker ve değişikliğin işlendiğini doğrular.
func (c *istemci) mesgulOl() {
	c.t.Helper()
	c.yolla(protokol.TipDurumBildir, protokol.DurumBildirIstek{Durum: model.DurumMesgul})
	c.bekle(protokol.TipDurumTam, 2*time.Second)
}

// bilgiMetni, gelen bilgi mesajının gövdesini okur.
func (c *istemci) bilgiMetni(sure time.Duration) string {
	c.t.Helper()
	zarf := c.bekle(protokol.TipBilgi, sure)
	var bilgi protokol.BilgiVeri
	json.Unmarshal(zarf.Veri, &bilgi)
	return bilgi.Mesaj
}

// TestMesgulNormalVeOnemliKuyrugaGirer, meşgul üyeye gönderilen hafif
// seviyelerin bastırıldığını, kaybolmayıp müsaite dönüldüğünde tek seferde
// iletildiğini doğrular.
func TestMesgulNormalVeOnemliKuyrugaGirer(t *testing.T) {
	o := ortamKur(t)
	k := ikiKisilikKurum(o)
	k.ali.mesgulOl()

	for _, seviye := range []model.Seviye{model.SeviyeNormal, model.SeviyeOnemli} {
		k.omer.yolla(protokol.TipSeslen, protokol.SeslenIstek{
			AliciID: k.aliID, Seviye: seviye, Not: "kahve içelim mi",
		})
		if mesaj := k.omer.bilgiMetni(2 * time.Second); !strings.Contains(mesaj, "meşgul") {
			t.Errorf("%q için meşgul bilgisi beklenirdi, gelen: %q", seviye, mesaj)
		}
	}

	// Ali'nin ekranında hiçbir şey belirmemeli.
	k.ali.yolla(protokol.TipNabiz, nil)
	k.ali.beklemeyen(protokol.TipSeslenmeGeldi, protokol.TipNabizYanit, 2*time.Second)

	// Müsaite dönünce ikisi birden, "meşgul" sebebiyle gelmeli.
	k.ali.yolla(protokol.TipDurumBildir, protokol.DurumBildirIstek{Durum: model.DurumMusait})
	zarf := k.ali.bekle(protokol.TipKacirilanlar, 2*time.Second)
	var kacirilanlar protokol.KacirilanlarVeri
	json.Unmarshal(zarf.Veri, &kacirilanlar)
	if len(kacirilanlar.Cagrilar) != 2 {
		t.Fatalf("2 bekleyen çağrı olmalıydı, gelen: %d", len(kacirilanlar.Cagrilar))
	}
	if kacirilanlar.Sebep != protokol.SebepMesgul {
		t.Errorf("sebep %q olmalıydı, gelen: %q", protokol.SebepMesgul, kacirilanlar.Sebep)
	}

	// İkinci kez müsait bildirmek aynı çağrıları tekrar getirmemeli.
	k.ali.yolla(protokol.TipDurumBildir, protokol.DurumBildirIstek{Durum: model.DurumMusait})
	k.ali.yolla(protokol.TipNabiz, nil)
	k.ali.beklemeyen(protokol.TipKacirilanlar, protokol.TipNabizYanit, 2*time.Second)
}

// TestMesgulAciliSusturmaz, meşgulün acil seviyesini engellemediğini doğrular.
// Engelleseydi acil seviyesinin anlamı kalmazdı.
func TestMesgulAciliSusturmaz(t *testing.T) {
	o := ortamKur(t)
	k := ikiKisilikKurum(o)
	k.ali.mesgulOl()

	k.omer.yolla(protokol.TipSeslen, protokol.SeslenIstek{
		AliciID: k.aliID, Seviye: model.SeviyeAcil, Not: "sunucu düştü",
	})

	zarf := k.ali.bekle(protokol.TipSeslenmeGeldi, 2*time.Second)
	var gelen protokol.SeslenmeGeldiVeri
	json.Unmarshal(zarf.Veri, &gelen)
	if gelen.Seviye != model.SeviyeAcil {
		t.Errorf("acil seviye beklenirdi, gelen: %q", gelen.Seviye)
	}

	// Çağrı ulaştığı için gönderene bekletme bilgisi gitmemeli.
	k.omer.yolla(protokol.TipNabiz, nil)
	k.omer.beklemeyen(protokol.TipBilgi, protokol.TipNabizYanit, 2*time.Second)
}

// TestMesguldeTacizYukseltmesiCalisir, yükseltmenin bastırma kontrolünden önce
// yapıldığını kilitler. Sıra tersine çevrilirse üçüncü yanıtsız ACİL tacize
// yükselmeden meşgulde ölür ve yükseltme mekanizması sessizce işlevsizleşir.
func TestMesguldeTacizYukseltmesiCalisir(t *testing.T) {
	o := ortamKur(t)
	k := ikiKisilikKurum(o)
	k.ali.mesgulOl()

	beklenen := []model.Seviye{model.SeviyeAcil, model.SeviyeAcil, model.SeviyeTaciz}
	for sira, seviye := range beklenen {
		k.omer.yolla(protokol.TipSeslen, protokol.SeslenIstek{
			AliciID: k.aliID, Seviye: model.SeviyeAcil, Not: "neredesin",
		})
		zarf := k.ali.bekle(protokol.TipSeslenmeGeldi, 2*time.Second)
		var gelen protokol.SeslenmeGeldiVeri
		json.Unmarshal(zarf.Veri, &gelen)
		if gelen.Seviye != seviye {
			t.Errorf("%d. çağrı %q olmalıydı, gelen: %q", sira+1, seviye, gelen.Seviye)
		}
	}
}

// TestMesgulDurumYenidenBaglantidaKorunur, uyku veya ağ kesintisi sonrası meşgul
// seçiminin kaybolmadığını doğrular. Eskiden hem çıkışta "cevrimdisi" hem
// girişte "musait" yazılıyor, kullanıcının tercihi sessizce siliniyordu.
func TestMesgulDurumYenidenBaglantidaKorunur(t *testing.T) {
	o := ortamKur(t)
	k := ikiKisilikKurum(o)
	k.ali.mesgulOl()

	// Kopuşun işlendiğini kuruma giden tam durum yayınından anlıyoruz.
	k.ali.ws.Close()
	k.omer.bekle(protokol.TipDurumTam, 2*time.Second)

	ali2 := o.baglan(k.aliToken, k.aliID)
	zarf := ali2.bekle(protokol.TipDurumTam, 2*time.Second)
	var durum protokol.DurumTamVeri
	json.Unmarshal(zarf.Veri, &durum)
	if durum.Ben.Durum != model.DurumMesgul {
		t.Errorf("meşgul tercihi korunmalıydı, gelen: %q", durum.Ben.Durum)
	}
}

// TestCevrimdisiUyeMesgulSayilmaz, meşgulken kopan üyeye seslenildiğinde
// gönderene "meşgul" değil "çevrimdışı" dendiğini doğrular. Durum kolonu artık
// kopuşta sıfırlanmadığı için bu ayrımı çevrimiçilik kontrolü yapıyor.
func TestCevrimdisiUyeMesgulSayilmaz(t *testing.T) {
	o := ortamKur(t)
	k := ikiKisilikKurum(o)
	k.ali.mesgulOl()

	k.ali.ws.Close()
	k.omer.bekle(protokol.TipDurumTam, 2*time.Second)

	k.omer.yolla(protokol.TipSeslen, protokol.SeslenIstek{
		AliciID: k.aliID, Seviye: model.SeviyeNormal, Not: "müsait misin",
	})
	mesaj := k.omer.bilgiMetni(2 * time.Second)
	if !strings.Contains(mesaj, "çevrimdışı") {
		t.Errorf("çevrimdışı bilgisi beklenirdi, gelen: %q", mesaj)
	}
	if strings.Contains(mesaj, "meşgul") {
		t.Errorf("çevrimdışı üye için meşgul denmemeliydi, gelen: %q", mesaj)
	}
}

// TestMesguldeYayinBastirilir, haykırışın meşgul üyeye ulaşmadığını ve kuyruğa
// da girmediğini doğrular. Yayın kuyruğa girseydi saatler sonra teslim edilen
// bir "herkese sesleniyorum" gürültü olurdu.
func TestMesguldeYayinBastirilir(t *testing.T) {
	o := ortamKur(t)
	k := ikiKisilikKurum(o)
	k.ali.mesgulOl()

	k.omer.yolla(protokol.TipHaykir, protokol.HaykirIstek{Not: "toplantı başlıyor"})

	// Ekipteki tek kişi meşgul: "kimse çevrimiçi değil" demek yalan olurdu,
	// bu yüzden hata değil bilgi dönmeli.
	if mesaj := k.omer.bilgiMetni(2 * time.Second); !strings.Contains(mesaj, "meşgul") {
		t.Errorf("meşgul bilgisi beklenirdi, gelen: %q", mesaj)
	}

	k.ali.yolla(protokol.TipNabiz, nil)
	k.ali.beklemeyen(protokol.TipSeslenmeGeldi, protokol.TipNabizYanit, 2*time.Second)

	// Müsaite dönünce de gelmemeli: yayın teslim edilmiş sayılır.
	k.ali.yolla(protokol.TipDurumBildir, protokol.DurumBildirIstek{Durum: model.DurumMusait})
	k.ali.yolla(protokol.TipNabiz, nil)
	k.ali.beklemeyen(protokol.TipKacirilanlar, protokol.TipNabizYanit, 2*time.Second)
}

// TestMesgulTekrarBildirilirseKuyrukBosalmaz, kuyruğun yalnızca müsaite
// dönüldüğünde açıldığını doğrular.
func TestMesgulTekrarBildirilirseKuyrukBosalmaz(t *testing.T) {
	o := ortamKur(t)
	k := ikiKisilikKurum(o)
	k.ali.mesgulOl()

	k.omer.yolla(protokol.TipSeslen, protokol.SeslenIstek{
		AliciID: k.aliID, Seviye: model.SeviyeOnemli, Not: "bekliyorum",
	})
	k.omer.bilgiMetni(2 * time.Second)

	k.ali.yolla(protokol.TipDurumBildir, protokol.DurumBildirIstek{Durum: model.DurumMesgul})
	k.ali.yolla(protokol.TipNabiz, nil)
	k.ali.beklemeyen(protokol.TipKacirilanlar, protokol.TipNabizYanit, 2*time.Second)
}

// TestBaglantidaDurumTazeleme, bağlanışta yalnızca "cevrimdisi" ve bayat
// meşgul değerlerinin müsaite döndüğünü doğrular.
func TestBaglantidaDurumTazeleme(t *testing.T) {
	depo, err := store.Ac(filepath.Join(t.TempDir(), "durum.db"))
	if err != nil {
		t.Fatalf("veritabanı açılamadı: %v", err)
	}
	defer depo.Kapat()

	_, kurucu, _, err := depo.KurumOlustur("HAY Teknoloji", "Ömer")
	if err != nil {
		t.Fatalf("kurum kurulamadı: %v", err)
	}

	for _, d := range []struct {
		yazilan, beklenen model.Durum
	}{
		{model.DurumCevrimdisi, model.DurumMusait},
		{model.DurumMesgul, model.DurumMesgul},
		{model.DurumMusait, model.DurumMusait},
	} {
		if err := depo.DurumGuncelle(kurucu.ID, d.yazilan); err != nil {
			t.Fatalf("durum yazılamadı: %v", err)
		}
		gelen, err := depo.BaglantidaDurumTazele(kurucu.ID)
		if err != nil {
			t.Fatalf("durum tazelenemedi: %v", err)
		}
		if gelen != d.beklenen {
			t.Errorf("%q için %q beklenirdi, gelen: %q", d.yazilan, d.beklenen, gelen)
		}
	}
}

// anketSonucu, bir sonuç mesajını bekleyip çözer.
func (c *istemci) anketSonucu(sure time.Duration) protokol.AnketSonucVeri {
	c.t.Helper()
	zarf := c.bekle(protokol.TipAnketSonuc, sure)
	var sonuc protokol.AnketSonucVeri
	json.Unmarshal(zarf.Veri, &sonuc)
	return sonuc
}

// cayAnketiAc, standart üç seçenekli anketi açar ve gönderene dönen ilk
// sonucu döndürür.
func (k kurumOrtami) cayAnketiAc() protokol.AnketSonucVeri {
	k.omer.yolla(protokol.TipAnket, protokol.AnketIstek{
		Soru: "Kim çay ister?", Secenekler: []string{"Çay", "Kahve", "Yok"},
	})
	return k.omer.anketSonucu(2 * time.Second)
}

// TestAnketAkisi, anketin açılıp alıcılara ulaştığını ve oyların gönderende
// canlı sayıldığını doğrular.
func TestAnketAkisi(t *testing.T) {
	o := ortamKur(t)
	k := ikiKisilikKurum(o)

	sonuc := k.cayAnketiAc()
	if sonuc.Beklenen != 2 {
		t.Errorf("gönderen de kitleye dahil, 2 beklenirdi, gelen: %d", sonuc.Beklenen)
	}
	if sonuc.Katilan != 0 {
		t.Errorf("henüz oy yok, 0 beklenirdi, gelen: %d", sonuc.Katilan)
	}

	// Ali'ye duyuru gitmeli; gönderene gitmez, o sonucu zaten görüyor.
	zarf := k.ali.bekle(protokol.TipAnketGeldi, 2*time.Second)
	var geldi protokol.AnketGeldiVeri
	json.Unmarshal(zarf.Veri, &geldi)
	if len(geldi.Secenekler) != 3 || geldi.Secenekler[0] != "Çay" {
		t.Fatalf("seçenekler bozuk geldi: %v", geldi.Secenekler)
	}

	k.ali.yolla(protokol.TipAnketOy, protokol.AnketOyIstek{AnketID: geldi.AnketID, Secenek: 0})
	sonuc = k.omer.anketSonucu(2 * time.Second)
	if sonuc.Sayimlar[0] != 1 || sonuc.Katilan != 1 {
		t.Errorf("çay 1 oy almalıydı, gelen sayımlar: %v (katılan %d)", sonuc.Sayimlar, sonuc.Katilan)
	}
	// Kim neye oy verdiği taşınmalı: "kim çay ister"in cevabı çayı kime
	// götüreceğindir, salt sayı yetmez.
	if len(sonuc.Oylayanlar) != 1 {
		t.Fatalf("1 oy sahibi beklenirdi, gelen: %v", sonuc.Oylayanlar)
	}
	if sonuc.Oylayanlar[0].UyeID != k.aliID || sonuc.Oylayanlar[0].Secenek != 0 {
		t.Errorf("oy sahibi Ali/çay olmalıydı, gelen: %+v", sonuc.Oylayanlar[0])
	}
	if sonuc.Oylayanlar[0].AdSoyad != "Ali Veli" {
		t.Errorf("oy sahibinin adı taşınmalıydı, gelen: %q", sonuc.Oylayanlar[0].AdSoyad)
	}
	// Gönderen kendi oyunu vermedi; oyu -1 kalmalı.
	if sonuc.BenimOyum != -1 {
		t.Errorf("gönderen oy vermedi, -1 beklenirdi, gelen: %d", sonuc.BenimOyum)
	}
}

// TestAnketOyDegistirme, oyun değiştirilebildiğini ve toplamın şişmediğini
// doğrular. Dar bir balonda yanlış tıklamak kolaydır; geri alma yolu olmalı.
func TestAnketOyDegistirme(t *testing.T) {
	o := ortamKur(t)
	k := ikiKisilikKurum(o)

	k.cayAnketiAc()
	zarf := k.ali.bekle(protokol.TipAnketGeldi, 2*time.Second)
	var geldi protokol.AnketGeldiVeri
	json.Unmarshal(zarf.Veri, &geldi)
	// Anket açılırken boş sonuç herkese gider (alıcının kartı da dolmalı);
	// oy sonuçlarını okumadan önce onu tüketiyoruz.
	k.ali.anketSonucu(2 * time.Second)

	k.ali.yolla(protokol.TipAnketOy, protokol.AnketOyIstek{AnketID: geldi.AnketID, Secenek: 0})
	k.ali.anketSonucu(2 * time.Second)

	k.ali.yolla(protokol.TipAnketOy, protokol.AnketOyIstek{AnketID: geldi.AnketID, Secenek: 1})
	sonuc := k.ali.anketSonucu(2 * time.Second)

	if sonuc.Katilan != 1 {
		t.Errorf("oy değişti, katılan 1 kalmalıydı, gelen: %d", sonuc.Katilan)
	}
	if sonuc.Sayimlar[0] != 0 || sonuc.Sayimlar[1] != 1 {
		t.Errorf("oy kahveye geçmeliydi, gelen sayımlar: %v", sonuc.Sayimlar)
	}
	if sonuc.BenimOyum != 1 {
		t.Errorf("kendi oyum 1 olmalıydı, gelen: %d", sonuc.BenimOyum)
	}
}

// TestAnketKuyrugaGirmez, kapanmış bir anketin sonradan bağlanan üyeye hiçbir
// koşulda iletilmediğini doğrular. Anket, kaçırılan çağrılar gibi davranmaz.
func TestAnketKuyrugaGirmez(t *testing.T) {
	o := ortamKur(t)
	k := ikiKisilikKurum(o)

	k.ali.ws.Close()
	k.omer.bekle(protokol.TipDurumTam, 2*time.Second)

	sonuc := k.cayAnketiAc()
	// Süresinin dolmasını beklemeden aynı kuralı sınamak için erken bitiriyoruz.
	k.omer.yolla(protokol.TipAnketBitir, protokol.AnketIDIstek{AnketID: sonuc.AnketID})
	k.omer.anketSonucu(2 * time.Second)

	ali2 := o.baglan(k.aliToken, k.aliID)
	ali2.yolla(protokol.TipNabiz, nil)
	ali2.beklemeyen(protokol.TipAcikAnketler, protokol.TipNabizYanit, 2*time.Second)
}

// TestAcikAnketYenidenBaglantida, hâlâ açık bir ankete sonradan bağlanan üyenin
// katılabildiğini doğrular. Kahve almaya gidip dönen kişi ankete yetişmeli.
func TestAcikAnketYenidenBaglantida(t *testing.T) {
	o := ortamKur(t)
	k := ikiKisilikKurum(o)

	k.ali.ws.Close()
	k.omer.bekle(protokol.TipDurumTam, 2*time.Second)
	k.cayAnketiAc()

	ali2 := o.baglan(k.aliToken, k.aliID)
	zarf := ali2.bekle(protokol.TipAcikAnketler, 2*time.Second)
	var acik protokol.AcikAnketlerVeri
	json.Unmarshal(zarf.Veri, &acik)
	if len(acik.Anketler) != 1 {
		t.Fatalf("1 açık anket beklenirdi, gelen: %d", len(acik.Anketler))
	}

	ali2.yolla(protokol.TipAnketOy, protokol.AnketOyIstek{
		AnketID: acik.Anketler[0].AnketID, Secenek: 2,
	})
	if sonuc := ali2.anketSonucu(2 * time.Second); sonuc.Sayimlar[2] != 1 {
		t.Errorf("oy sayılmalıydı, gelen sayımlar: %v", sonuc.Sayimlar)
	}
}

// TestAnketDogrulama, seçenek ve soru kurallarının sunucuda uygulandığını
// doğrular.
func TestAnketDogrulama(t *testing.T) {
	o := ortamKur(t)
	k := ikiKisilikKurum(o)

	gecersizler := []protokol.AnketIstek{
		{Soru: "Tek seçenek", Secenekler: []string{"Çay"}},
		{Soru: "Çok seçenek", Secenekler: []string{"a", "b", "c", "d", "e", "f"}},
		{Soru: "  ", Secenekler: []string{"Çay", "Kahve"}},
		// Büyük/küçük harf duyarsız tekrar: iki ayrı çubuk olarak çizilirse
		// sonuç okunamaz hale gelir.
		{Soru: "Tekrarlı", Secenekler: []string{"Çay", "çay"}},
	}
	for _, istek := range gecersizler {
		k.omer.yolla(protokol.TipAnket, istek)
		zarf := k.omer.bekle(protokol.TipHata, 2*time.Second)
		var hata protokol.HataVeri
		json.Unmarshal(zarf.Veri, &hata)
		if hata.Kod != protokol.HataGecersiz {
			t.Errorf("%q için geçersiz hatası beklenirdi, gelen: %q", istek.Soru, hata.Kod)
		}
	}
}

// TestAnketTekAcikAnket, kişi başına tek açık anket kuralını doğrular.
func TestAnketTekAcikAnket(t *testing.T) {
	o := ortamKur(t)
	k := ikiKisilikKurum(o)

	k.cayAnketiAc()
	k.omer.yolla(protokol.TipAnket, protokol.AnketIstek{
		Soru: "Öğle nereye?", Secenekler: []string{"Dışarı", "Ofis"},
	})
	zarf := k.omer.bekle(protokol.TipHata, 2*time.Second)
	var hata protokol.HataVeri
	json.Unmarshal(zarf.Veri, &hata)
	if hata.Kod != protokol.HataGecersiz {
		t.Errorf("ikinci anket reddedilmeliydi, gelen kod: %q", hata.Kod)
	}
}

// TestAnketBitirmeYetkisi, anketi yalnızca açanın kapatabildiğini doğrular.
func TestAnketBitirmeYetkisi(t *testing.T) {
	o := ortamKur(t)
	k := ikiKisilikKurum(o)

	sonuc := k.cayAnketiAc()
	k.ali.bekle(protokol.TipAnketGeldi, 2*time.Second)

	k.ali.yolla(protokol.TipAnketBitir, protokol.AnketIDIstek{AnketID: sonuc.AnketID})
	zarf := k.ali.bekle(protokol.TipHata, 2*time.Second)
	var hata protokol.HataVeri
	json.Unmarshal(zarf.Veri, &hata)
	if hata.Kod != protokol.HataYetkisiz {
		t.Errorf("yetkisiz hatası beklenirdi, gelen: %q", hata.Kod)
	}

	k.omer.yolla(protokol.TipAnketBitir, protokol.AnketIDIstek{AnketID: sonuc.AnketID})
	if kapanan := k.ali.anketSonucu(2 * time.Second); !kapanan.Kapandi {
		t.Error("anket kapandı olarak yayınlanmalıydı")
	}

	// Kapanmış ankete oy verilemez.
	k.ali.yolla(protokol.TipAnketOy, protokol.AnketOyIstek{AnketID: sonuc.AnketID, Secenek: 0})
	zarf = k.ali.bekle(protokol.TipHata, 2*time.Second)
	json.Unmarshal(zarf.Veri, &hata)
	if hata.Kod != protokol.HataGecersiz {
		t.Errorf("kapalı ankete oy reddedilmeliydi, gelen kod: %q", hata.Kod)
	}
}

// TestAnketGecmisi, bitmiş anketin menüden düşse de geçmişte kaldığını
// doğrular. Bitmiş anket kendiliğinden gösterilmiyor; merak eden buraya bakar.
func TestAnketGecmisi(t *testing.T) {
	o := ortamKur(t)
	k := ikiKisilikKurum(o)

	sonuc := k.cayAnketiAc()
	k.ali.bekle(protokol.TipAnketGeldi, 2*time.Second)
	k.ali.yolla(protokol.TipAnketOy, protokol.AnketOyIstek{AnketID: sonuc.AnketID, Secenek: 1})
	k.ali.anketSonucu(2 * time.Second)

	k.omer.yolla(protokol.TipAnketBitir, protokol.AnketIDIstek{AnketID: sonuc.AnketID})
	k.omer.anketSonucu(2 * time.Second)

	// Kapalı olduğu için açık anket listesinde görünmemeli...
	ali2 := o.baglan(k.aliToken, k.aliID)
	ali2.yolla(protokol.TipNabiz, nil)
	ali2.beklemeyen(protokol.TipAcikAnketler, protokol.TipNabizYanit, 2*time.Second)

	// ...ama geçmişte oyuyla birlikte durmalı.
	ali2.yolla(protokol.TipAnketGecmisiIste, nil)
	zarf := ali2.bekle(protokol.TipAnketGecmisi, 2*time.Second)
	var gecmis protokol.AnketGecmisiVeri
	json.Unmarshal(zarf.Veri, &gecmis)

	if len(gecmis.Anketler) != 1 {
		t.Fatalf("geçmişte 1 anket beklenirdi, gelen: %d", len(gecmis.Anketler))
	}
	kayit := gecmis.Anketler[0]
	if !kayit.Kapandi {
		t.Error("geçmişteki anket kapalı görünmeliydi")
	}
	if kayit.BenimOyum != 1 {
		t.Errorf("kendi oyum geçmişte de taşınmalıydı, gelen: %d", kayit.BenimOyum)
	}
	if len(kayit.Oylayanlar) != 1 || kayit.Oylayanlar[0].UyeID != k.aliID {
		t.Errorf("oy sahipleri geçmişte de gelmeliydi, gelen: %v", kayit.Oylayanlar)
	}
}

// TestAnketKurumSiniri, başka kurumun anketine oy verilemediğini doğrular.
func TestAnketKurumSiniri(t *testing.T) {
	o := ortamKur(t)
	k := ikiKisilikKurum(o)
	sonuc := k.cayAnketiAc()

	// Bambaşka bir kurum ve onun kurucusu.
	_, yanit := o.gonderJSON("/api/kurum/olustur", map[string]string{
		"kurumAd": "Başka Şirket", "kurucuAd": "Yabancı",
	})
	yabanci := o.baglan(yanit["token"].(string), yanit["ben"].(map[string]any)["id"].(string))
	yabanci.bekle(protokol.TipDurumTam, 2*time.Second)

	yabanci.yolla(protokol.TipAnketOy, protokol.AnketOyIstek{AnketID: sonuc.AnketID, Secenek: 0})
	zarf := yabanci.bekle(protokol.TipHata, 2*time.Second)
	var hata protokol.HataVeri
	json.Unmarshal(zarf.Veri, &hata)
	if hata.Kod != protokol.HataBulunamadi {
		t.Errorf("bulunamadı hatası beklenirdi, gelen: %q", hata.Kod)
	}
}

// TestCevrimdisiTeslimKuyrugu, üye çevrimdışıyken gelen seslenmenin kaybolmayıp
// üye bağlanır bağlanmaz iletildiğini ve ikinci kez iletilmediğini doğrular.
func TestCevrimdisiTeslimKuyrugu(t *testing.T) {
	o := ortamKur(t)

	_, yanit := o.gonderJSON("/api/kurum/olustur", map[string]string{
		"kurumAd": "HAY Teknoloji", "kurucuAd": "Ömer",
	})
	omerToken := yanit["token"].(string)
	omerID := yanit["ben"].(map[string]any)["id"].(string)
	katilimKodu := yanit["kurum"].(map[string]any)["katilimKodu"].(string)

	_, yanit = o.gonderJSON("/api/kurum/katil", map[string]string{
		"kod": katilimKodu, "adSoyad": "Ali Veli",
	})
	aliToken := yanit["token"].(string)
	aliID := yanit["ben"].(map[string]any)["id"].(string)

	omer := o.baglan(omerToken, omerID)
	omer.bekle(protokol.TipDurumTam, 2*time.Second)
	ali := o.baglan(aliToken, aliID)
	ali.bekle(protokol.TipDurumTam, 2*time.Second)

	omer.yolla(protokol.TipUyeOnayla, protokol.UyeIDIstek{UyeID: aliID})
	ali.bekle(protokol.TipDurumTam, 2*time.Second)

	// Ali bilgisayarını kapatır. Kopuşun sunucuya işlendiğini kuruma giden tam
	// durum yayınından anlıyoruz; sabit süre beklemekten güvenli.
	ali.ws.Close()
	omer.bekle(protokol.TipDurumTam, 2*time.Second)

	// Ömer yokken seslenir: seslenme kaybolmadığı için hata değil bilgi dönmeli.
	omer.yolla(protokol.TipSeslen, protokol.SeslenIstek{
		AliciID: aliID, Seviye: model.SeviyeOnemli, Not: "müşteri bekliyor",
	})
	bilgiZarf := omer.bekle(protokol.TipBilgi, 2*time.Second)
	var bilgi protokol.BilgiVeri
	json.Unmarshal(bilgiZarf.Veri, &bilgi)
	if !strings.Contains(bilgi.Mesaj, "çevrimdışı") {
		t.Errorf("çevrimdışı bilgisi beklenirdi, gelen: %q", bilgi.Mesaj)
	}

	// Ali döndüğünde kaçırdığı çağrı bağlanır bağlanmaz gelmeli.
	ali2 := o.baglan(aliToken, aliID)
	kacZarf := ali2.bekle(protokol.TipKacirilanlar, 2*time.Second)
	var kacirilanlar protokol.KacirilanlarVeri
	json.Unmarshal(kacZarf.Veri, &kacirilanlar)
	if len(kacirilanlar.Cagrilar) != 1 {
		t.Fatalf("bir kaçırılmış çağrı beklenirdi, gelen: %d", len(kacirilanlar.Cagrilar))
	}
	if k := kacirilanlar.Cagrilar[0]; k.Not != "müşteri bekliyor" || k.GonderenAd != "Ömer" {
		t.Errorf("kaçırılan çağrı içeriği hatalı: %+v", k)
	}

	// Teslim edilmiş çağrı ikinci bağlantıda yeniden gönderilmemeli; yoksa
	// kullanıcı her açılışta aynı seslenmeleri görür.
	ali2.ws.Close()
	omer.bekle(protokol.TipDurumTam, 2*time.Second)

	ali3 := o.baglan(aliToken, aliID)
	ali3.yolla(protokol.TipNabiz, nil)
	ali3.beklemeyen(protokol.TipKacirilanlar, protokol.TipNabizYanit, 2*time.Second)
}

// TestYayinKuyrugaGirmez, haykırışın çevrimdışı üye için biriktirilmediğini
// doğrular: saatler sonra teslim edilen bir yayın bilgi değil gürültüdür.
func TestYayinKuyrugaGirmez(t *testing.T) {
	o := ortamKur(t)

	_, yanit := o.gonderJSON("/api/kurum/olustur", map[string]string{
		"kurumAd": "HAY Teknoloji", "kurucuAd": "Ömer",
	})
	omerToken := yanit["token"].(string)
	omerID := yanit["ben"].(map[string]any)["id"].(string)
	katilimKodu := yanit["kurum"].(map[string]any)["katilimKodu"].(string)

	_, yanit = o.gonderJSON("/api/kurum/katil", map[string]string{
		"kod": katilimKodu, "adSoyad": "Ali Veli",
	})
	aliToken := yanit["token"].(string)
	aliID := yanit["ben"].(map[string]any)["id"].(string)

	omer := o.baglan(omerToken, omerID)
	omer.bekle(protokol.TipDurumTam, 2*time.Second)
	ali := o.baglan(aliToken, aliID)
	ali.bekle(protokol.TipDurumTam, 2*time.Second)
	omer.yolla(protokol.TipUyeOnayla, protokol.UyeIDIstek{UyeID: aliID})
	ali.bekle(protokol.TipDurumTam, 2*time.Second)

	ali.ws.Close()
	omer.bekle(protokol.TipDurumTam, 2*time.Second)

	omer.yolla(protokol.TipHaykir, protokol.HaykirIstek{Not: "toplantı başlıyor"})

	ali2 := o.baglan(aliToken, aliID)
	ali2.yolla(protokol.TipNabiz, nil)
	ali2.beklemeyen(protokol.TipKacirilanlar, protokol.TipNabizYanit, 2*time.Second)
}

// eskiSemaSQL, teslim kuyruğu eklenmeden önceki şemadır.
//
// Testlerin tamamı sıfırdan veritabanı kurduğu için yükseltme yolu hiç
// sınanmıyordu; bu yüzden şemaya konan bir indeksin, kolonu ekleyen geçişten
// önce çalıştığı fark edilmedi ve sunucu var olan veritabanıyla açılamadı.
const eskiSemaSQL = `
CREATE TABLE kurumlar (
	id           TEXT PRIMARY KEY,
	ad           TEXT NOT NULL,
	katilim_kodu TEXT NOT NULL UNIQUE,
	olusturuldu  INTEGER NOT NULL
);
CREATE TABLE uyeler (
	id          TEXT PRIMARY KEY,
	kurum_id    TEXT NOT NULL REFERENCES kurumlar(id) ON DELETE CASCADE,
	ad_soyad    TEXT NOT NULL,
	rol         TEXT NOT NULL,
	max_seviye  TEXT NOT NULL,
	onayli      INTEGER NOT NULL DEFAULT 0,
	durum       TEXT NOT NULL DEFAULT 'cevrimdisi',
	token_ozet  TEXT NOT NULL UNIQUE,
	son_gorulme INTEGER NOT NULL,
	olusturuldu INTEGER NOT NULL
);
CREATE TABLE cagrilar (
	id          TEXT PRIMARY KEY,
	kurum_id    TEXT NOT NULL,
	gonderen_id TEXT NOT NULL,
	alici_id    TEXT NOT NULL,
	seviye      TEXT NOT NULL,
	not_metni   TEXT NOT NULL DEFAULT '',
	gonderildi  INTEGER NOT NULL,
	yanit       TEXT NOT NULL DEFAULT '',
	yanit_tarih INTEGER NOT NULL DEFAULT 0
);
`

// TestEskiSemaAcilir, önceki sürümde oluşmuş bir veritabanının açılabildiğini
// doğrular. Bu geçmediğinde sunucu hiç başlamaz.
func TestEskiSemaAcilir(t *testing.T) {
	yol := filepath.Join(t.TempDir(), "eski.db")

	ham, err := sql.Open("sqlite", yol)
	if err != nil {
		t.Fatalf("sqlite açılamadı: %v", err)
	}
	if _, err := ham.Exec(eskiSemaSQL); err != nil {
		t.Fatalf("eski şema kurulamadı: %v", err)
	}
	// Yükseltmeden önce var olan bir çağrı: geçmişte kalmış sayılmalı, yoksa
	// sürüm yükseltmesinden sonra herkese eski seslenmeler yağar.
	simdi := time.Now().Unix()
	if _, err := ham.Exec(
		`INSERT INTO cagrilar (id, kurum_id, gonderen_id, alici_id, seviye, not_metni, gonderildi)
		 VALUES ('c1', 'k1', 'g1', 'a1', 'normal', 'eski çağrı', ?)`, simdi,
	); err != nil {
		t.Fatalf("eski çağrı yazılamadı: %v", err)
	}
	ham.Close()

	depo, err := store.Ac(yol)
	if err != nil {
		t.Fatalf("eski şemalı veritabanı açılamadı: %v", err)
	}
	defer depo.Kapat()

	bekleyen, err := depo.TeslimEdilmemisCagrilar("a1")
	if err != nil {
		t.Fatalf("teslim kuyruğu okunamadı: %v", err)
	}
	if len(bekleyen) != 0 {
		t.Errorf("yükseltmeden önceki çağrılar teslim edilmiş sayılmalıydı, gelen: %d", len(bekleyen))
	}

	// İkinci açılış da sorunsuz olmalı: geçişler yinelenebilir olmalı.
	depo.Kapat()
	tekrar, err := store.Ac(yol)
	if err != nil {
		t.Fatalf("ikinci açılış başarısız: %v", err)
	}
	tekrar.Kapat()
}

// TestKurucuTacizGecisi, taciz seviyesi eklenmeden önce kurulmuş kurumların
// kurucularının açılışta bu yetkiye kavuştuğunu doğrular.
//
// Kurucu kendi seviyesini arayüzden değiştiremediği (yönetim işlemleri kurucuya
// dokunamaz) için, geçiş çalışmazsa taciz düğmesi o hesaplarda kalıcı olarak
// görünmez kalır.
func TestKurucuTacizGecisi(t *testing.T) {
	yol := filepath.Join(t.TempDir(), "gecis.db")

	depo, err := store.Ac(yol)
	if err != nil {
		t.Fatalf("veritabanı açılamadı: %v", err)
	}
	_, kurucu, _, err := depo.KurumOlustur("HAY Teknoloji", "Ömer")
	if err != nil {
		t.Fatalf("kurum oluşturulamadı: %v", err)
	}
	// Taciz seviyesi eklenmeden önceki hali taklit ediyoruz.
	if err := depo.UyeGuncelle(kurucu.ID, model.RolKurucu, model.SeviyeAcil); err != nil {
		t.Fatalf("üye güncellenemedi: %v", err)
	}
	depo.Kapat()

	// Sunucunun yeniden başlaması geçişi uygulamalı.
	yeni, err := store.Ac(yol)
	if err != nil {
		t.Fatalf("veritabanı yeniden açılamadı: %v", err)
	}
	defer yeni.Kapat()

	guncel, err := yeni.UyeGetir(kurucu.ID)
	if err != nil {
		t.Fatalf("üye okunamadı: %v", err)
	}
	if guncel.MaxSeviye != model.SeviyeTaciz {
		t.Errorf("kurucunun seviyesi tacize yükselmeliydi, gelen: %q", guncel.MaxSeviye)
	}

	// Sıradan üyeler geçişten etkilenmemeli; taciz yetkisi kurucunun dağıtacağı
	// bir şey, herkese kendiliğinden verilen bir şey değil.
	_, uye, _, err := yeni.KurumaKatil(kurucuKodu(t, yeni, kurucu.KurumID), "Ali Veli")
	if err != nil {
		t.Fatalf("kuruma katılınamadı: %v", err)
	}
	if uye.MaxSeviye != model.SeviyeNormal {
		t.Errorf("yeni üyenin seviyesi normal kalmalıydı, gelen: %q", uye.MaxSeviye)
	}
}

// kurucuKodu, kurumun güncel katılım kodunu okur.
func kurucuKodu(t *testing.T, depo *store.Store, kurumID string) string {
	t.Helper()
	kurum, err := depo.KurumGetir(kurumID)
	if err != nil {
		t.Fatalf("kurum okunamadı: %v", err)
	}
	return kurum.KatilimKodu
}

// TestTacizYukseltmesi, yanıtsız kalan ACİL çağrıların eşiğe ulaşınca
// kendiliğinden taciz seviyesine çıktığını ve yanıt verilince sıfırlandığını
// doğrular.
func TestTacizYukseltmesi(t *testing.T) {
	o := ortamKur(t)

	_, yanit := o.gonderJSON("/api/kurum/olustur", map[string]string{
		"kurumAd": "HAY Teknoloji", "kurucuAd": "Ömer",
	})
	omerToken := yanit["token"].(string)
	omerID := yanit["ben"].(map[string]any)["id"].(string)
	katilimKodu := yanit["kurum"].(map[string]any)["katilimKodu"].(string)

	_, yanit = o.gonderJSON("/api/kurum/katil", map[string]string{
		"kod": katilimKodu, "adSoyad": "Ali Veli",
	})
	aliToken := yanit["token"].(string)
	aliID := yanit["ben"].(map[string]any)["id"].(string)

	omer := o.baglan(omerToken, omerID)
	omer.bekle(protokol.TipDurumTam, 2*time.Second)
	ali := o.baglan(aliToken, aliID)
	ali.bekle(protokol.TipDurumTam, 2*time.Second)
	omer.yolla(protokol.TipUyeOnayla, protokol.UyeIDIstek{UyeID: aliID})
	ali.bekle(protokol.TipDurumTam, 2*time.Second)

	// Ali hiçbirini yanıtlamıyor: üçüncü çağrı tacize yükselmeli.
	beklenen := []model.Seviye{model.SeviyeAcil, model.SeviyeAcil, model.SeviyeTaciz}
	var sonCagriIDleri []string
	for sira, seviye := range beklenen {
		omer.yolla(protokol.TipSeslen, protokol.SeslenIstek{
			AliciID: aliID, Seviye: model.SeviyeAcil, Not: "neredesin",
		})
		zarf := ali.bekle(protokol.TipSeslenmeGeldi, 2*time.Second)
		var gelen protokol.SeslenmeGeldiVeri
		json.Unmarshal(zarf.Veri, &gelen)
		if gelen.Seviye != seviye {
			t.Errorf("%d. çağrının seviyesi %q olmalıydı, gelen: %q", sira+1, seviye, gelen.Seviye)
		}
		sonCagriIDleri = append(sonCagriIDleri, gelen.CagriID)
	}

	// Ali hepsini yanıtlayınca sayaç sıfırlanır; sonraki ACİL yine ACİL olmalı.
	for _, cagriID := range sonCagriIDleri {
		ali.yolla(protokol.TipYanitla, protokol.YanitlaIstek{
			CagriID: cagriID, Yanit: model.YanitGeliyorum,
		})
		omer.bekle(protokol.TipYanitGeldi, 2*time.Second)
	}

	omer.yolla(protokol.TipSeslen, protokol.SeslenIstek{
		AliciID: aliID, Seviye: model.SeviyeAcil, Not: "tekrar",
	})
	zarf := ali.bekle(protokol.TipSeslenmeGeldi, 2*time.Second)
	var gelen protokol.SeslenmeGeldiVeri
	json.Unmarshal(zarf.Veri, &gelen)
	if gelen.Seviye != model.SeviyeAcil {
		t.Errorf("yanıtlardan sonra seviye ACİL'e dönmeliydi, gelen: %q", gelen.Seviye)
	}
}

// TestTacizYetkisi, taciz seviyesinin elle gönderiminin yetkiye bağlı olduğunu
// doğrular: yükseltme hak edilerek gelir, düğme ise yetkiyle.
func TestTacizYetkisi(t *testing.T) {
	o := ortamKur(t)

	_, yanit := o.gonderJSON("/api/kurum/olustur", map[string]string{
		"kurumAd": "HAY Teknoloji", "kurucuAd": "Ömer",
	})
	omerToken := yanit["token"].(string)
	omerID := yanit["ben"].(map[string]any)["id"].(string)
	katilimKodu := yanit["kurum"].(map[string]any)["katilimKodu"].(string)

	_, yanit = o.gonderJSON("/api/kurum/katil", map[string]string{
		"kod": katilimKodu, "adSoyad": "Ali Veli",
	})
	aliToken := yanit["token"].(string)
	aliID := yanit["ben"].(map[string]any)["id"].(string)

	omer := o.baglan(omerToken, omerID)
	omer.bekle(protokol.TipDurumTam, 2*time.Second)
	ali := o.baglan(aliToken, aliID)
	ali.bekle(protokol.TipDurumTam, 2*time.Second)
	omer.yolla(protokol.TipUyeOnayla, protokol.UyeIDIstek{UyeID: aliID})
	ali.bekle(protokol.TipDurumTam, 2*time.Second)

	// Ali'nin yetkisi normal; taciz gönderemez.
	ali.yolla(protokol.TipSeslen, protokol.SeslenIstek{
		AliciID: omerID, Seviye: model.SeviyeTaciz, Not: "hop",
	})
	hataZarf := ali.bekle(protokol.TipHata, 2*time.Second)
	var hata protokol.HataVeri
	json.Unmarshal(hataZarf.Veri, &hata)
	if hata.Kod != protokol.HataYetkisiz {
		t.Errorf("yetkisiz taciz reddedilmeliydi, gelen: %q", hata.Kod)
	}

	// Kurucu taciz yetkisiyle doğar; tek tıkla gönderebilmeli.
	omer.yolla(protokol.TipSeslen, protokol.SeslenIstek{
		AliciID: aliID, Seviye: model.SeviyeTaciz, Not: "gel artık",
	})
	zarf := ali.bekle(protokol.TipSeslenmeGeldi, 2*time.Second)
	var gelen protokol.SeslenmeGeldiVeri
	json.Unmarshal(zarf.Veri, &gelen)
	if gelen.Seviye != model.SeviyeTaciz {
		t.Errorf("kurucunun taciz çağrısı iletilmeliydi, gelen: %q", gelen.Seviye)
	}
}

// TestSeslenmeAkisi, kurum kurmaktan seslenip yanıt almaya kadar tüm akışı doğrular.
func TestSeslenmeAkisi(t *testing.T) {
	o := ortamKur(t)

	// 1. Kurucu kurumu oluşturur.
	kod, yanit := o.gonderJSON("/api/kurum/olustur", map[string]string{
		"kurumAd": "HAY Teknoloji", "kurucuAd": "Ömer Faruk Taşdemir",
	})
	if kod != http.StatusCreated {
		t.Fatalf("kurum oluşturma başarısız: %d %v", kod, yanit)
	}
	omerToken := yanit["token"].(string)
	omerID := yanit["ben"].(map[string]any)["id"].(string)
	katilimKodu := yanit["kurum"].(map[string]any)["katilimKodu"].(string)

	if !strings.Contains(katilimKodu, "-") || len(katilimKodu) != 7 {
		t.Errorf("katılım kodu XXX-XXX biçiminde olmalı, gelen: %q", katilimKodu)
	}

	// 2. Ali koda katılır; onay bekler durumda olmalı.
	kod, yanit = o.gonderJSON("/api/kurum/katil", map[string]string{
		"kod": katilimKodu, "adSoyad": "Ali Veli",
	})
	if kod != http.StatusCreated {
		t.Fatalf("katılım başarısız: %d %v", kod, yanit)
	}
	aliToken := yanit["token"].(string)
	aliID := yanit["ben"].(map[string]any)["id"].(string)
	if onayli := yanit["ben"].(map[string]any)["onayli"].(bool); onayli {
		t.Error("yeni üye onay beklemeden kuruma girmemeli")
	}
	// Yeni üyeye katılım kodu sızmamalı.
	if k := yanit["kurum"].(map[string]any)["katilimKodu"].(string); k != "" {
		t.Errorf("katılım kodu yeni üyeye gönderilmemeli, gelen: %q", k)
	}

	// 3. Her ikisi de bağlanır.
	omer := o.baglan(omerToken, omerID)
	omer.bekle(protokol.TipDurumTam, 2*time.Second)

	ali := o.baglan(aliToken, aliID)
	ali.bekle(protokol.TipDurumTam, 2*time.Second)

	// 4. Onaylanmamış Ali seslenmeyi denerse reddedilmeli.
	ali.yolla(protokol.TipSeslen, protokol.SeslenIstek{
		AliciID: omerID, Seviye: model.SeviyeNormal, Not: "merhaba",
	})
	hataZarf := ali.bekle(protokol.TipHata, 2*time.Second)
	var hata protokol.HataVeri
	json.Unmarshal(hataZarf.Veri, &hata)
	if hata.Kod != protokol.HataYetkisiz {
		t.Errorf("onaysız üye reddedilmeliydi, gelen kod: %q", hata.Kod)
	}

	// 5. Kurucu Ali'yi onaylar.
	omer.yolla(protokol.TipUyeOnayla, protokol.UyeIDIstek{UyeID: aliID})
	durumZarf := ali.bekle(protokol.TipDurumTam, 2*time.Second)
	var durum protokol.DurumTamVeri
	json.Unmarshal(durumZarf.Veri, &durum)
	if !durum.Ben.Onayli {
		t.Fatal("onaydan sonra üye onaylı görünmeli")
	}
	if durum.Kurum.KatilimKodu != "" {
		t.Error("sıradan üye katılım kodunu görmemeli")
	}

	// 6. Ali normal seviyede seslenebilmeli.
	ali.yolla(protokol.TipSeslen, protokol.SeslenIstek{
		AliciID: omerID, Seviye: model.SeviyeNormal, Not: "kahve?",
	})
	gelenZarf := omer.bekle(protokol.TipSeslenmeGeldi, 2*time.Second)
	var gelen protokol.SeslenmeGeldiVeri
	json.Unmarshal(gelenZarf.Veri, &gelen)
	if gelen.GonderenAd != "Ali Veli" || gelen.Not != "kahve?" {
		t.Errorf("çağrı içeriği hatalı: %+v", gelen)
	}

	// 7. Ali ACİL gönderemez (varsayılan yetkisi normal).
	ali.yolla(protokol.TipSeslen, protokol.SeslenIstek{
		AliciID: omerID, Seviye: model.SeviyeAcil, Not: "acil",
	})
	hataZarf = ali.bekle(protokol.TipHata, 2*time.Second)
	json.Unmarshal(hataZarf.Veri, &hata)
	if hata.Kod != protokol.HataYetkisiz {
		t.Errorf("yetkisiz ACİL reddedilmeliydi, gelen: %q", hata.Kod)
	}

	// 8. Ömer çağrıyı yanıtlar, Ali yanıtı almalı.
	omer.yolla(protokol.TipYanitla, protokol.YanitlaIstek{
		CagriID: gelen.CagriID, Yanit: model.YanitGeliyorum,
	})
	yanitZarf := ali.bekle(protokol.TipYanitGeldi, 2*time.Second)
	var gelenYanit protokol.YanitGeldiVeri
	json.Unmarshal(yanitZarf.Veri, &gelenYanit)
	if gelenYanit.Yanit != model.YanitGeliyorum || gelenYanit.AliciAd != "Ömer Faruk Taşdemir" {
		t.Errorf("yanıt hatalı: %+v", gelenYanit)
	}

	// 9. Kurucu Ali'ye ACİL yetkisi verir, artık gönderebilmeli.
	omer.yolla(protokol.TipUyeGuncelle, protokol.UyeGuncelleIstek{
		UyeID: aliID, Rol: model.RolYonetici, MaxSeviye: model.SeviyeAcil,
	})
	ali.bekle(protokol.TipDurumTam, 2*time.Second)

	ali.yolla(protokol.TipSeslen, protokol.SeslenIstek{
		AliciID: omerID, Seviye: model.SeviyeAcil, Not: "müşteri geldi",
	})
	gelenZarf = omer.bekle(protokol.TipSeslenmeGeldi, 2*time.Second)
	json.Unmarshal(gelenZarf.Veri, &gelen)
	if gelen.Seviye != model.SeviyeAcil {
		t.Errorf("ACİL seslenme iletilmeliydi, gelen seviye: %q", gelen.Seviye)
	}
}

// TestYetkiSinirlari, yetki ve kurum sınırlarının aşılamadığını doğrular.
func TestYetkiSinirlari(t *testing.T) {
	o := ortamKur(t)

	// İki ayrı kurum kuruyoruz.
	_, y1 := o.gonderJSON("/api/kurum/olustur", map[string]string{
		"kurumAd": "Kurum A", "kurucuAd": "Ayşe"})
	ayseToken := y1["token"].(string)
	ayseID := y1["ben"].(map[string]any)["id"].(string)

	_, y2 := o.gonderJSON("/api/kurum/olustur", map[string]string{
		"kurumAd": "Kurum B", "kurucuAd": "Mehmet"})
	mehmetToken := y2["token"].(string)
	mehmetID := y2["ben"].(map[string]any)["id"].(string)

	ayse := o.baglan(ayseToken, ayseID)
	ayse.bekle(protokol.TipDurumTam, 2*time.Second)
	mehmet := o.baglan(mehmetToken, mehmetID)
	mehmet.bekle(protokol.TipDurumTam, 2*time.Second)

	// Ayşe başka kurumdaki Mehmet'e seslenememeli.
	ayse.yolla(protokol.TipSeslen, protokol.SeslenIstek{
		AliciID: mehmetID, Seviye: model.SeviyeNormal})
	zarf := ayse.bekle(protokol.TipHata, 2*time.Second)
	var hata protokol.HataVeri
	json.Unmarshal(zarf.Veri, &hata)
	if hata.Kod != protokol.HataBulunamadi {
		t.Errorf("kurum sınırı aşılmamalı, gelen: %q", hata.Kod)
	}

	// Ayşe başka kurumdaki Mehmet'i silememeli.
	ayse.yolla(protokol.TipUyeSil, protokol.UyeIDIstek{UyeID: mehmetID})
	zarf = ayse.bekle(protokol.TipHata, 2*time.Second)
	json.Unmarshal(zarf.Veri, &hata)
	if hata.Kod != protokol.HataBulunamadi {
		t.Errorf("başka kurumun üyesi silinememeli, gelen: %q", hata.Kod)
	}
}

// TestGecersizToken, kimliksiz bağlantının reddedildiğini doğrular.
func TestGecersizToken(t *testing.T) {
	o := ortamKur(t)
	wsURL := "ws" + strings.TrimPrefix(o.srv.URL, "http") + "/ws?token=uydurma"
	_, yanit, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err == nil {
		t.Fatal("geçersiz token ile bağlanılmamalıydı")
	}
	if yanit == nil || yanit.StatusCode != http.StatusUnauthorized {
		t.Errorf("401 beklenirdi, gelen: %v", yanit)
	}
}

// TestAyniIsimReddedilir, aynı kurumda isim çakışmasını doğrular.
func TestAyniIsimReddedilir(t *testing.T) {
	o := ortamKur(t)
	_, y := o.gonderJSON("/api/kurum/olustur", map[string]string{
		"kurumAd": "Test", "kurucuAd": "Ali Veli"})
	kodu := y["kurum"].(map[string]any)["katilimKodu"].(string)

	kod, _ := o.gonderJSON("/api/kurum/katil", map[string]string{
		"kod": kodu, "adSoyad": "ali veli"})
	if kod != http.StatusConflict {
		t.Errorf("aynı isim reddedilmeliydi, gelen durum: %d", kod)
	}
}

// TestHaykirmaAkisi, herkese yayının kurumdaki diğer üyelere ulaştığını,
// gönderene geri dönmediğini ve onaysız üyeye kapalı olduğunu doğrular.
func TestHaykirmaAkisi(t *testing.T) {
	o := ortamKur(t)

	_, yanit := o.gonderJSON("/api/kurum/olustur", map[string]string{
		"kurumAd": "HAY Teknoloji", "kurucuAd": "Ömer Faruk Taşdemir",
	})
	omerToken := yanit["token"].(string)
	omerID := yanit["ben"].(map[string]any)["id"].(string)
	katilimKodu := yanit["kurum"].(map[string]any)["katilimKodu"].(string)

	katil := func(ad string) (token, id string) {
		_, y := o.gonderJSON("/api/kurum/katil", map[string]string{
			"kod": katilimKodu, "adSoyad": ad,
		})
		return y["token"].(string), y["ben"].(map[string]any)["id"].(string)
	}
	aliToken, aliID := katil("Ali Veli")
	ayseToken, ayseID := katil("Ayşe Yılmaz")

	omer := o.baglan(omerToken, omerID)
	omer.bekle(protokol.TipDurumTam, 2*time.Second)
	ali := o.baglan(aliToken, aliID)
	ali.bekle(protokol.TipDurumTam, 2*time.Second)

	// Onaysız üye haykıramaz.
	ali.yolla(protokol.TipHaykir, protokol.HaykirIstek{Not: "erkenden"})
	hataZarf := ali.bekle(protokol.TipHata, 2*time.Second)
	var hata protokol.HataVeri
	json.Unmarshal(hataZarf.Veri, &hata)
	if hata.Kod != protokol.HataYetkisiz {
		t.Errorf("onaysız üyenin haykırması reddedilmeliydi, gelen kod: %q", hata.Kod)
	}

	omer.yolla(protokol.TipUyeOnayla, protokol.UyeIDIstek{UyeID: aliID})
	ali.bekle(protokol.TipDurumTam, 2*time.Second)

	ayse := o.baglan(ayseToken, ayseID)
	ayse.bekle(protokol.TipDurumTam, 2*time.Second)
	omer.yolla(protokol.TipUyeOnayla, protokol.UyeIDIstek{UyeID: ayseID})
	ayse.bekle(protokol.TipDurumTam, 2*time.Second)

	// Sıradan üye de haykırabilir: yayın yetki gerektirmez.
	ali.yolla(protokol.TipHaykir, protokol.HaykirIstek{Not: "toplantı başlıyor"})

	for _, alici := range []struct {
		ad string
		c  *istemci
	}{{"Ömer", omer}, {"Ayşe", ayse}} {
		zarf := alici.c.bekle(protokol.TipSeslenmeGeldi, 2*time.Second)
		var gelen protokol.SeslenmeGeldiVeri
		json.Unmarshal(zarf.Veri, &gelen)
		if !gelen.Yayin {
			t.Errorf("%s yayın bayrağını almalıydı: %+v", alici.ad, gelen)
		}
		if gelen.Seviye != model.SeviyeNormal {
			t.Errorf("%s: yayın normal seviyede gitmeli, gelen: %q", alici.ad, gelen.Seviye)
		}
		if gelen.GonderenAd != "Ali Veli" || gelen.Not != "toplantı başlıyor" {
			t.Errorf("%s: yayın içeriği hatalı: %+v", alici.ad, gelen)
		}
	}

	// Gönderen kendi yayınını almamalı. Ömer'in doğrudan seslenmesi Ali'ye ulaşan
	// ilk çağrı olmalı; yayın da gelseydi sırada ondan önce dururdu.
	omer.yolla(protokol.TipSeslen, protokol.SeslenIstek{
		AliciID: aliID, Seviye: model.SeviyeNormal, Not: "sadece sana",
	})
	zarf := ali.bekle(protokol.TipSeslenmeGeldi, 2*time.Second)
	var aliyeGelen protokol.SeslenmeGeldiVeri
	json.Unmarshal(zarf.Veri, &aliyeGelen)
	if aliyeGelen.Yayin || aliyeGelen.Not != "sadece sana" {
		t.Errorf("gönderen kendi yayınını almamalı, Ali'ye ulaşan: %+v", aliyeGelen)
	}
}
