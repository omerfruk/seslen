package main

import (
	"bytes"
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
