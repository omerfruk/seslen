// Package api, Seslen sunucusunun HTTP uçlarını tanımlar.
package api

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"github.com/gorilla/websocket"

	"github.com/omerfruk/seslen/seslen-sunucu/internal/hub"
	"github.com/omerfruk/seslen/seslen-sunucu/internal/model"
	"github.com/omerfruk/seslen/seslen-sunucu/internal/store"
)

// Sunucu, HTTP işleyicilerini bağımlılıklarıyla birlikte tutar.
type Sunucu struct {
	depo    *store.Store
	merkez  *hub.Hub
	kayit   *slog.Logger
	yukselt websocket.Upgrader
}

// Yeni, HTTP sunucusunu kurar.
func Yeni(depo *store.Store, merkez *hub.Hub, kayit *slog.Logger) *Sunucu {
	return &Sunucu{
		depo:   depo,
		merkez: merkez,
		kayit:  kayit,
		yukselt: websocket.Upgrader{
			ReadBufferSize:  1024,
			WriteBufferSize: 1024,
			// İstemci bir masaüstü uygulaması; tarayıcı kaynaklı CSRF riski yok
			// ve kimlik doğrulama token ile yapılıyor.
			CheckOrigin: func(*http.Request) bool { return true },
		},
	}
}

// Yonlendirici, tüm uçları bağlayan HTTP yönlendiricisini döner.
func (s *Sunucu) Yonlendirici() http.Handler {
	yol := http.NewServeMux()
	yol.HandleFunc("GET /saglik", s.saglik)
	yol.HandleFunc("POST /api/kurum/olustur", s.kurumOlustur)
	yol.HandleFunc("POST /api/kurum/katil", s.kurumaKatil)
	yol.HandleFunc("GET /api/ben", s.ben)
	yol.HandleFunc("GET /ws", s.websocket)
	return kayitAraKatmani(s.kayit, yol)
}

// --- Yardımcılar ---

func jsonYaz(w http.ResponseWriter, kod int, govde any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(kod)
	json.NewEncoder(w).Encode(govde)
}

func hataYaz(w http.ResponseWriter, kod int, mesaj string) {
	jsonYaz(w, kod, map[string]string{"hata": mesaj})
}

// tokenAl, Authorization başlığından ya da sorgu parametresinden token okur.
// WebSocket bağlantısı özel başlık gönderemediği için sorgu parametresi de destekleniyor.
func tokenAl(r *http.Request) string {
	if basli := r.Header.Get("Authorization"); strings.HasPrefix(basli, "Bearer ") {
		return strings.TrimSpace(strings.TrimPrefix(basli, "Bearer "))
	}
	return strings.TrimSpace(r.URL.Query().Get("token"))
}

// dogrula, istekteki token'a karşılık gelen üyeyi bulur.
func (s *Sunucu) dogrula(r *http.Request) (model.Uye, bool) {
	token := tokenAl(r)
	if token == "" {
		return model.Uye{}, false
	}
	uye, err := s.depo.UyeTokenIle(token)
	if err != nil {
		return model.Uye{}, false
	}
	return uye, true
}

func kayitAraKatmani(kayit *slog.Logger, sonraki http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		kayit.Debug("istek", "yontem", r.Method, "yol", r.URL.Path, "kaynak", r.RemoteAddr)
		sonraki.ServeHTTP(w, r)
	})
}

// --- Uçlar ---

func (s *Sunucu) saglik(w http.ResponseWriter, _ *http.Request) {
	jsonYaz(w, http.StatusOK, map[string]string{"durum": "calisiyor", "servis": "seslen"})
}

type kurumOlusturIstek struct {
	KurumAd  string `json:"kurumAd"`
	KurucuAd string `json:"kurucuAd"`
}

type kimlikYanit struct {
	Token string      `json:"token"`
	Kurum model.Kurum `json:"kurum"`
	Ben   model.Uye   `json:"ben"`
}

func (s *Sunucu) kurumOlustur(w http.ResponseWriter, r *http.Request) {
	var istek kurumOlusturIstek
	if err := json.NewDecoder(r.Body).Decode(&istek); err != nil {
		hataYaz(w, http.StatusBadRequest, "istek çözümlenemedi")
		return
	}
	if strings.TrimSpace(istek.KurumAd) == "" || strings.TrimSpace(istek.KurucuAd) == "" {
		hataYaz(w, http.StatusBadRequest, "kurum adı ve kurucu adı zorunlu")
		return
	}

	kurum, kurucu, token, err := s.depo.KurumOlustur(istek.KurumAd, istek.KurucuAd)
	if err != nil {
		s.kayit.Error("kurum oluşturulamadı", "hata", err)
		hataYaz(w, http.StatusInternalServerError, "kurum oluşturulamadı")
		return
	}
	s.kayit.Info("kurum oluşturuldu", "kurum", kurum.Ad, "kod", kurum.KatilimKodu)
	jsonYaz(w, http.StatusCreated, kimlikYanit{Token: token, Kurum: kurum, Ben: kurucu})
}

type kurumaKatilIstek struct {
	Kod     string `json:"kod"`
	AdSoyad string `json:"adSoyad"`
}

func (s *Sunucu) kurumaKatil(w http.ResponseWriter, r *http.Request) {
	var istek kurumaKatilIstek
	if err := json.NewDecoder(r.Body).Decode(&istek); err != nil {
		hataYaz(w, http.StatusBadRequest, "istek çözümlenemedi")
		return
	}
	if strings.TrimSpace(istek.Kod) == "" || strings.TrimSpace(istek.AdSoyad) == "" {
		hataYaz(w, http.StatusBadRequest, "katılım kodu ve ad soyad zorunlu")
		return
	}

	kurum, uye, token, err := s.depo.KurumaKatil(istek.Kod, istek.AdSoyad)
	switch {
	case errors.Is(err, store.ErrKodGecersiz):
		hataYaz(w, http.StatusNotFound, "katılım kodu geçersiz")
		return
	case errors.Is(err, store.ErrIsimDolu):
		hataYaz(w, http.StatusConflict, "bu isimde bir üye zaten var")
		return
	case err != nil:
		s.kayit.Error("kuruma katılınamadı", "hata", err)
		hataYaz(w, http.StatusInternalServerError, "kuruma katılınamadı")
		return
	}

	// Katılım kodu yönetim bilgisidir; yeni üyeye geri göndermiyoruz.
	kurum.KatilimKodu = ""
	s.kayit.Info("katılım isteği alındı", "kurum", kurum.Ad, "uye", uye.AdSoyad)

	// Yöneticiler bekleyen isteği anında görsün.
	s.merkez.KurumaYayinla(kurum.ID)

	jsonYaz(w, http.StatusCreated, kimlikYanit{Token: token, Kurum: kurum, Ben: uye})
}

// ben, saklanan token'ın hâlâ geçerli olup olmadığını kontrol etmek için kullanılır.
func (s *Sunucu) ben(w http.ResponseWriter, r *http.Request) {
	uye, tamam := s.dogrula(r)
	if !tamam {
		hataYaz(w, http.StatusUnauthorized, "geçersiz token")
		return
	}
	kurum, err := s.depo.KurumGetir(uye.KurumID)
	if err != nil {
		hataYaz(w, http.StatusInternalServerError, "kurum okunamadı")
		return
	}
	if !uye.Rol.YonetimYetkisi() {
		kurum.KatilimKodu = ""
	}
	jsonYaz(w, http.StatusOK, kimlikYanit{Kurum: kurum, Ben: uye})
}

func (s *Sunucu) websocket(w http.ResponseWriter, r *http.Request) {
	uye, tamam := s.dogrula(r)
	if !tamam {
		hataYaz(w, http.StatusUnauthorized, "geçersiz token")
		return
	}

	ws, err := s.yukselt.Upgrade(w, r, nil)
	if err != nil {
		// Upgrade başarısızsa yanıtı kendisi yazmıştır.
		s.kayit.Warn("websocket yükseltilemedi", "hata", err)
		return
	}
	s.kayit.Info("bağlandı", "uye", uye.AdSoyad, "onayli", uye.Onayli)
	s.merkez.Baglat(ws, uye)
	s.kayit.Info("ayrıldı", "uye", uye.AdSoyad)
}
