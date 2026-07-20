// Package hub, canlı WebSocket bağlantılarını yönetir ve mesajları yönlendirir.
package hub

import (
	"encoding/json"
	"log/slog"
	"sync"
	"time"

	"github.com/gorilla/websocket"

	"github.com/omerfruk/seslen/seslen-sunucu/internal/model"
	"github.com/omerfruk/seslen/seslen-sunucu/internal/protokol"
	"github.com/omerfruk/seslen/seslen-sunucu/internal/store"
)

const (
	yazmaSuresi   = 10 * time.Second
	nabizAraligi  = 30 * time.Second
	okumaSuresi   = 60 * time.Second // nabızdan uzun olmalı
	maksMesajBoyu = 8 * 1024
	kuyrukBoyu    = 32
)

// Baglanti, tek bir istemcinin canlı oturumudur.
type Baglanti struct {
	hub     *Hub
	ws      *websocket.Conn
	uyeID   string
	kurumID string
	gonder  chan []byte
	kapat   sync.Once
}

// Hub, tüm bağlantıların merkezi kaydıdır.
type Hub struct {
	mu          sync.RWMutex
	baglantilar map[string]*Baglanti          // üyeID -> bağlantı
	kurumUyesi  map[string]map[string]struct{} // kurumID -> üyeID kümesi
	depo        *store.Store
	kayit       *slog.Logger
}

// Yeni, boş bir hub oluşturur.
func Yeni(depo *store.Store, kayit *slog.Logger) *Hub {
	return &Hub{
		baglantilar: make(map[string]*Baglanti),
		kurumUyesi:  make(map[string]map[string]struct{}),
		depo:        depo,
		kayit:       kayit,
	}
}

// Baglat, doğrulanmış bir üye için WebSocket oturumunu başlatır ve bloklar.
func (h *Hub) Baglat(ws *websocket.Conn, uye model.Uye) {
	b := &Baglanti{
		hub:     h,
		ws:      ws,
		uyeID:   uye.ID,
		kurumID: uye.KurumID,
		gonder:  make(chan []byte, kuyrukBoyu),
	}

	h.ekle(b)
	defer h.cikar(b)

	// Bağlanan üye varsayılan olarak müsait sayılır.
	if err := h.depo.DurumGuncelle(uye.ID, model.DurumMusait); err != nil {
		h.kayit.Error("durum yazılamadı", "uye", uye.ID, "hata", err)
	}
	h.KurumaYayinla(uye.KurumID)

	go b.yazmaDongusu()
	b.okumaDongusu()
}

// ekle, bağlantıyı kaydeder. Aynı üyenin eski oturumu varsa düşürülür.
func (h *Hub) ekle(b *Baglanti) {
	h.mu.Lock()
	eski, varsa := h.baglantilar[b.uyeID]
	h.baglantilar[b.uyeID] = b
	if h.kurumUyesi[b.kurumID] == nil {
		h.kurumUyesi[b.kurumID] = make(map[string]struct{})
	}
	h.kurumUyesi[b.kurumID][b.uyeID] = struct{}{}
	h.mu.Unlock()

	if varsa {
		// Kullanıcı ikinci bir cihazdan/kopyadan bağlandı; tek oturum tutuyoruz.
		eski.Kapat()
	}
}

// cikar, bağlantıyı kayıttan siler ve üyeyi çevrimdışı işaretler.
func (h *Hub) cikar(b *Baglanti) {
	h.mu.Lock()
	// Yalnızca hâlâ kayıtlı olan bağlantı bizsek silelim; aksi halde yeni oturumu bozarız.
	if mevcut, varsa := h.baglantilar[b.uyeID]; varsa && mevcut == b {
		delete(h.baglantilar, b.uyeID)
		if uyeler, varsa := h.kurumUyesi[b.kurumID]; varsa {
			delete(uyeler, b.uyeID)
			if len(uyeler) == 0 {
				delete(h.kurumUyesi, b.kurumID)
			}
		}
		h.mu.Unlock()

		if err := h.depo.DurumGuncelle(b.uyeID, model.DurumCevrimdisi); err != nil {
			h.kayit.Error("çıkışta durum yazılamadı", "uye", b.uyeID, "hata", err)
		}
		h.KurumaYayinla(b.kurumID)
	} else {
		h.mu.Unlock()
	}

	b.Kapat()
}

// Cevrimici, üyenin şu anda bağlı olup olmadığını söyler.
func (h *Hub) Cevrimici(uyeID string) bool {
	h.mu.RLock()
	defer h.mu.RUnlock()
	_, varsa := h.baglantilar[uyeID]
	return varsa
}

// UyeyeGonder, tek bir üyeye ham mesaj iletir. Üye çevrimdışıysa false döner.
func (h *Hub) UyeyeGonder(uyeID string, mesaj []byte) bool {
	h.mu.RLock()
	b, varsa := h.baglantilar[uyeID]
	h.mu.RUnlock()
	if !varsa {
		return false
	}
	return b.Yolla(mesaj)
}

// KurumaYayinla, kurumdaki her bağlı üyeye güncel tam durumu gönderir.
// Her üyenin "ben" alanı farklı olduğu için mesaj kişiye özel hazırlanır.
func (h *Hub) KurumaYayinla(kurumID string) {
	h.mu.RLock()
	alicilar := make([]string, 0, len(h.kurumUyesi[kurumID]))
	for uyeID := range h.kurumUyesi[kurumID] {
		alicilar = append(alicilar, uyeID)
	}
	h.mu.RUnlock()

	if len(alicilar) == 0 {
		return
	}

	kurum, err := h.depo.KurumGetir(kurumID)
	if err != nil {
		h.kayit.Error("kurum okunamadı", "kurum", kurumID, "hata", err)
		return
	}
	uyeler, err := h.depo.UyeleriGetir(kurumID)
	if err != nil {
		h.kayit.Error("üyeler okunamadı", "kurum", kurumID, "hata", err)
		return
	}
	bekleyen, err := h.depo.BekleyenleriGetir(kurumID)
	if err != nil {
		h.kayit.Error("bekleyenler okunamadı", "kurum", kurumID, "hata", err)
		return
	}

	// Çevrimiçi bilgisi veritabanında değil hub'da; listeyi burada zenginleştiriyoruz.
	for i := range uyeler {
		uyeler[i].Cevrimici = h.Cevrimici(uyeler[i].ID)
		if !uyeler[i].Cevrimici {
			uyeler[i].Durum = model.DurumCevrimdisi
		}
	}

	for _, aliciID := range alicilar {
		ben, bulundu := uyeBul(uyeler, aliciID)
		if !bulundu {
			// Onay bekleyenler de bağlı kalır: uygulamaları "onay bekleniyor"
			// ekranını gösterebilsin diye kendi bilgilerini almalılar.
			ben, bulundu = uyeBul(bekleyen, aliciID)
		}
		if !bulundu {
			// Üye kurumdan tamamen silinmiş; oturumunu kapatıyoruz.
			h.OturumuKapat(aliciID)
			continue
		}

		veri := protokol.DurumTamVeri{Kurum: kurum, Ben: ben, Bekleyen: []model.Uye{}}
		switch {
		case !ben.Onayli:
			// Henüz kurumun bir parçası değil; ekip listesini göstermiyoruz.
			veri.Kurum.KatilimKodu = ""
			veri.Uyeler = []model.Uye{}
		case ben.Rol.YonetimYetkisi():
			// Bekleyen katılım istekleri ve katılım kodu yalnızca yönetimi ilgilendirir.
			veri.Uyeler = uyeler
			veri.Bekleyen = bekleyen
		default:
			veri.Kurum.KatilimKodu = ""
			veri.Uyeler = uyeler
		}

		mesaj, err := protokol.Paketle(protokol.TipDurumTam, veri)
		if err != nil {
			h.kayit.Error("durum paketlenemedi", "hata", err)
			continue
		}
		h.UyeyeGonder(aliciID, mesaj)
	}
}

// OturumuKapat, üyenin varsa açık bağlantısını sonlandırır.
func (h *Hub) OturumuKapat(uyeID string) {
	h.mu.RLock()
	b, varsa := h.baglantilar[uyeID]
	h.mu.RUnlock()
	if varsa {
		b.Kapat()
	}
}

func uyeBul(liste []model.Uye, id string) (model.Uye, bool) {
	for _, u := range liste {
		if u.ID == id {
			return u, true
		}
	}
	return model.Uye{}, false
}

// --- Bağlantı düzeyi ---

// Yolla, mesajı bağlantının gönderim kuyruğuna koyar.
// Kuyruk doluysa istemci yavaş demektir; mesaj düşürülür ve false döner.
func (b *Baglanti) Yolla(mesaj []byte) bool {
	select {
	case b.gonder <- mesaj:
		return true
	default:
		b.hub.kayit.Warn("gönderim kuyruğu dolu, mesaj düşürüldü", "uye", b.uyeID)
		return false
	}
}

// Kapat, bağlantıyı bir kez güvenle kapatır.
func (b *Baglanti) Kapat() {
	b.kapat.Do(func() {
		close(b.gonder)
		b.ws.Close()
	})
}

func (b *Baglanti) okumaDongusu() {
	b.ws.SetReadLimit(maksMesajBoyu)
	b.ws.SetReadDeadline(time.Now().Add(okumaSuresi))
	b.ws.SetPongHandler(func(string) error {
		return b.ws.SetReadDeadline(time.Now().Add(okumaSuresi))
	})

	for {
		_, ham, err := b.ws.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseNormalClosure, websocket.CloseGoingAway) {
				b.hub.kayit.Info("bağlantı beklenmedik kapandı", "uye", b.uyeID, "hata", err)
			}
			return
		}

		var zarf protokol.Zarf
		if err := json.Unmarshal(ham, &zarf); err != nil {
			b.Yolla(protokol.HataPaketle(protokol.HataGecersiz, "mesaj çözümlenemedi"))
			continue
		}
		b.hub.mesajIsle(b, zarf)
	}
}

func (b *Baglanti) yazmaDongusu() {
	nabiz := time.NewTicker(nabizAraligi)
	defer func() {
		nabiz.Stop()
		b.ws.Close()
	}()

	for {
		select {
		case mesaj, acik := <-b.gonder:
			b.ws.SetWriteDeadline(time.Now().Add(yazmaSuresi))
			if !acik {
				b.ws.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := b.ws.WriteMessage(websocket.TextMessage, mesaj); err != nil {
				return
			}
		case <-nabiz.C:
			b.ws.SetWriteDeadline(time.Now().Add(yazmaSuresi))
			if err := b.ws.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}
