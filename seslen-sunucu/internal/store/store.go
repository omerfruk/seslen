// Package store, Seslen verilerinin SQLite üzerinde kalıcı saklanmasını sağlar.
package store

import (
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/omerfruk/seslen/seslen-sunucu/internal/model"

	_ "modernc.org/sqlite" // saf Go SQLite sürücüsü
)

// Yaygın hatalar.
var (
	ErrBulunamadi = errors.New("kayıt bulunamadı")
	ErrKodGecersiz = errors.New("katılım kodu geçersiz")
	ErrIsimDolu   = errors.New("bu isimde bir üye zaten var")
)

// Store, veritabanı bağlantısını sarar.
type Store struct {
	db *sql.DB
}

const semaSQL = `
CREATE TABLE IF NOT EXISTS kurumlar (
	id           TEXT PRIMARY KEY,
	ad           TEXT NOT NULL,
	katilim_kodu TEXT NOT NULL UNIQUE,
	olusturuldu  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS uyeler (
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
CREATE INDEX IF NOT EXISTS idx_uyeler_kurum ON uyeler(kurum_id);

CREATE TABLE IF NOT EXISTS cagrilar (
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
CREATE INDEX IF NOT EXISTS idx_cagrilar_kurum ON cagrilar(kurum_id, gonderildi);
`

// Ac, veritabanını açar ve şemayı hazırlar.
func Ac(yol string) (*Store, error) {
	db, err := sql.Open("sqlite", yol+"?_pragma=busy_timeout(5000)&_pragma=journal_mode(WAL)&_pragma=foreign_keys(1)")
	if err != nil {
		return nil, fmt.Errorf("veritabanı açılamadı: %w", err)
	}
	// SQLite tek yazar destekler; havuzu küçük tutmak kilit çakışmasını azaltır.
	db.SetMaxOpenConns(1)

	if _, err := db.Exec(semaSQL); err != nil {
		db.Close()
		return nil, fmt.Errorf("şema oluşturulamadı: %w", err)
	}
	return &Store{db: db}, nil
}

// Kapat, bağlantıyı kapatır.
func (s *Store) Kapat() error { return s.db.Close() }

// --- Kimlik üretimi ---

// kodAlfabesi, karışması kolay harfleri (I, O, 0, 1) dışarıda bırakır.
const kodAlfabesi = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

func yeniID() string {
	b := make([]byte, 16)
	rand.Read(b)
	return hex.EncodeToString(b)
}

func yeniToken() string {
	b := make([]byte, 32)
	rand.Read(b)
	return hex.EncodeToString(b)
}

func tokenOzeti(token string) string {
	toplam := sha256.Sum256([]byte(token))
	return hex.EncodeToString(toplam[:])
}

// yeniKatilimKodu, XXX-XXX biçiminde okunabilir bir kod üretir.
func yeniKatilimKodu() string {
	b := make([]byte, 6)
	rand.Read(b)
	var sb strings.Builder
	for i, v := range b {
		if i == 3 {
			sb.WriteByte('-')
		}
		sb.WriteByte(kodAlfabesi[int(v)%len(kodAlfabesi)])
	}
	return sb.String()
}

// --- Kurum işlemleri ---

// KurumOlustur, yeni bir kurum ve onun kurucusunu yaratır.
// Dönen token istemcide saklanır ve sonraki tüm isteklerde kimlik olarak kullanılır.
func (s *Store) KurumOlustur(kurumAd, kurucuAd string) (model.Kurum, model.Uye, string, error) {
	simdi := time.Now()
	kurum := model.Kurum{
		ID:          yeniID(),
		Ad:          strings.TrimSpace(kurumAd),
		KatilimKodu: yeniKatilimKodu(),
		Olusturuldu: simdi,
	}
	kurucu := model.Uye{
		ID:          yeniID(),
		KurumID:     kurum.ID,
		AdSoyad:     strings.TrimSpace(kurucuAd),
		Rol:         model.RolKurucu,
		MaxSeviye:   model.SeviyeAcil,
		Onayli:      true,
		Durum:       model.DurumCevrimdisi,
		SonGorulme:  simdi,
		Olusturuldu: simdi,
	}
	token := yeniToken()

	islem, err := s.db.Begin()
	if err != nil {
		return model.Kurum{}, model.Uye{}, "", err
	}
	defer islem.Rollback()

	if _, err := islem.Exec(
		`INSERT INTO kurumlar (id, ad, katilim_kodu, olusturuldu) VALUES (?, ?, ?, ?)`,
		kurum.ID, kurum.Ad, kurum.KatilimKodu, kurum.Olusturuldu.Unix(),
	); err != nil {
		return model.Kurum{}, model.Uye{}, "", fmt.Errorf("kurum yazılamadı: %w", err)
	}
	if _, err := islem.Exec(
		`INSERT INTO uyeler (id, kurum_id, ad_soyad, rol, max_seviye, onayli, durum, token_ozet, son_gorulme, olusturuldu)
		 VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?, ?)`,
		kurucu.ID, kurucu.KurumID, kurucu.AdSoyad, kurucu.Rol, kurucu.MaxSeviye,
		kurucu.Durum, tokenOzeti(token), kurucu.SonGorulme.Unix(), kurucu.Olusturuldu.Unix(),
	); err != nil {
		return model.Kurum{}, model.Uye{}, "", fmt.Errorf("kurucu yazılamadı: %w", err)
	}
	if err := islem.Commit(); err != nil {
		return model.Kurum{}, model.Uye{}, "", err
	}
	return kurum, kurucu, token, nil
}

// KurumaKatil, katılım kodu ile yeni bir üyeyi onay bekler durumda ekler.
func (s *Store) KurumaKatil(kod, adSoyad string) (model.Kurum, model.Uye, string, error) {
	kod = strings.ToUpper(strings.TrimSpace(kod))
	adSoyad = strings.TrimSpace(adSoyad)

	kurum, err := s.kurumKodIle(kod)
	if err != nil {
		return model.Kurum{}, model.Uye{}, "", err
	}

	// Aynı isimde üye varsa listede kimin kim olduğu anlaşılmaz; baştan engelliyoruz.
	var sayi int
	if err := s.db.QueryRow(
		`SELECT COUNT(*) FROM uyeler WHERE kurum_id = ? AND LOWER(ad_soyad) = LOWER(?)`,
		kurum.ID, adSoyad,
	).Scan(&sayi); err != nil {
		return model.Kurum{}, model.Uye{}, "", err
	}
	if sayi > 0 {
		return model.Kurum{}, model.Uye{}, "", ErrIsimDolu
	}

	simdi := time.Now()
	uye := model.Uye{
		ID:          yeniID(),
		KurumID:     kurum.ID,
		AdSoyad:     adSoyad,
		Rol:         model.RolUye,
		MaxSeviye:   model.SeviyeNormal,
		Onayli:      false,
		Durum:       model.DurumCevrimdisi,
		SonGorulme:  simdi,
		Olusturuldu: simdi,
	}
	token := yeniToken()

	if _, err := s.db.Exec(
		`INSERT INTO uyeler (id, kurum_id, ad_soyad, rol, max_seviye, onayli, durum, token_ozet, son_gorulme, olusturuldu)
		 VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, ?)`,
		uye.ID, uye.KurumID, uye.AdSoyad, uye.Rol, uye.MaxSeviye,
		uye.Durum, tokenOzeti(token), uye.SonGorulme.Unix(), uye.Olusturuldu.Unix(),
	); err != nil {
		return model.Kurum{}, model.Uye{}, "", fmt.Errorf("üye yazılamadı: %w", err)
	}
	return kurum, uye, token, nil
}

func (s *Store) kurumKodIle(kod string) (model.Kurum, error) {
	var k model.Kurum
	var ts int64
	err := s.db.QueryRow(
		`SELECT id, ad, katilim_kodu, olusturuldu FROM kurumlar WHERE katilim_kodu = ?`, kod,
	).Scan(&k.ID, &k.Ad, &k.KatilimKodu, &ts)
	if errors.Is(err, sql.ErrNoRows) {
		return model.Kurum{}, ErrKodGecersiz
	}
	if err != nil {
		return model.Kurum{}, err
	}
	k.Olusturuldu = time.Unix(ts, 0)
	return k, nil
}

// KurumGetir, kurumu kimliğiyle okur.
func (s *Store) KurumGetir(id string) (model.Kurum, error) {
	var k model.Kurum
	var ts int64
	err := s.db.QueryRow(
		`SELECT id, ad, katilim_kodu, olusturuldu FROM kurumlar WHERE id = ?`, id,
	).Scan(&k.ID, &k.Ad, &k.KatilimKodu, &ts)
	if errors.Is(err, sql.ErrNoRows) {
		return model.Kurum{}, ErrBulunamadi
	}
	if err != nil {
		return model.Kurum{}, err
	}
	k.Olusturuldu = time.Unix(ts, 0)
	return k, nil
}

// KodYenile, kurumun katılım kodunu değiştirir; eski kod artık çalışmaz.
func (s *Store) KodYenile(kurumID string) (string, error) {
	kod := yeniKatilimKodu()
	if _, err := s.db.Exec(`UPDATE kurumlar SET katilim_kodu = ? WHERE id = ?`, kod, kurumID); err != nil {
		return "", err
	}
	return kod, nil
}

// --- Üye işlemleri ---

const uyeSecim = `SELECT id, kurum_id, ad_soyad, rol, max_seviye, onayli, durum, son_gorulme, olusturuldu FROM uyeler`

func uyeTara(tarayici interface{ Scan(...any) error }) (model.Uye, error) {
	var u model.Uye
	var onayli int
	var sonGorulme, olusturuldu int64
	err := tarayici.Scan(&u.ID, &u.KurumID, &u.AdSoyad, &u.Rol, &u.MaxSeviye, &onayli, &u.Durum, &sonGorulme, &olusturuldu)
	if err != nil {
		return model.Uye{}, err
	}
	u.Onayli = onayli == 1
	u.SonGorulme = time.Unix(sonGorulme, 0)
	u.Olusturuldu = time.Unix(olusturuldu, 0)
	return u, nil
}

// UyeTokenIle, istemcinin sakladığı token ile üyeyi bulur.
func (s *Store) UyeTokenIle(token string) (model.Uye, error) {
	satir := s.db.QueryRow(uyeSecim+` WHERE token_ozet = ?`, tokenOzeti(token))
	u, err := uyeTara(satir)
	if errors.Is(err, sql.ErrNoRows) {
		return model.Uye{}, ErrBulunamadi
	}
	return u, err
}

// UyeGetir, üyeyi kimliğiyle okur.
func (s *Store) UyeGetir(id string) (model.Uye, error) {
	satir := s.db.QueryRow(uyeSecim+` WHERE id = ?`, id)
	u, err := uyeTara(satir)
	if errors.Is(err, sql.ErrNoRows) {
		return model.Uye{}, ErrBulunamadi
	}
	return u, err
}

// UyeleriGetir, kurumun onaylı üyelerini ada göre sıralı döner.
func (s *Store) UyeleriGetir(kurumID string) ([]model.Uye, error) {
	return s.uyeListesi(kurumID, true)
}

// BekleyenleriGetir, henüz onaylanmamış katılım isteklerini döner.
func (s *Store) BekleyenleriGetir(kurumID string) ([]model.Uye, error) {
	return s.uyeListesi(kurumID, false)
}

func (s *Store) uyeListesi(kurumID string, onayli bool) ([]model.Uye, error) {
	deger := 0
	if onayli {
		deger = 1
	}
	satirlar, err := s.db.Query(uyeSecim+` WHERE kurum_id = ? AND onayli = ? ORDER BY ad_soyad COLLATE NOCASE`, kurumID, deger)
	if err != nil {
		return nil, err
	}
	defer satirlar.Close()

	liste := []model.Uye{}
	for satirlar.Next() {
		u, err := uyeTara(satirlar)
		if err != nil {
			return nil, err
		}
		liste = append(liste, u)
	}
	return liste, satirlar.Err()
}

// UyeGuncelle, üyenin rolünü ve gönderebileceği en yüksek seviyeyi ayarlar.
func (s *Store) UyeGuncelle(uyeID string, rol model.Rol, maxSeviye model.Seviye) error {
	_, err := s.db.Exec(`UPDATE uyeler SET rol = ?, max_seviye = ? WHERE id = ?`, rol, maxSeviye, uyeID)
	return err
}

// UyeOnayla, bekleyen üyeyi kuruma dahil eder.
func (s *Store) UyeOnayla(uyeID string) error {
	_, err := s.db.Exec(`UPDATE uyeler SET onayli = 1 WHERE id = ?`, uyeID)
	return err
}

// UyeSil, üyeyi kurumdan tamamen çıkarır.
func (s *Store) UyeSil(uyeID string) error {
	_, err := s.db.Exec(`DELETE FROM uyeler WHERE id = ?`, uyeID)
	return err
}

// DurumGuncelle, üyenin müsaitlik durumunu ve son görülme zamanını yazar.
func (s *Store) DurumGuncelle(uyeID string, durum model.Durum) error {
	_, err := s.db.Exec(
		`UPDATE uyeler SET durum = ?, son_gorulme = ? WHERE id = ?`,
		durum, time.Now().Unix(), uyeID,
	)
	return err
}

// --- Çağrı işlemleri ---

// CagriKaydet, gönderilen seslenmeyi kalıcı hale getirir.
func (s *Store) CagriKaydet(c model.Cagri) error {
	_, err := s.db.Exec(
		`INSERT INTO cagrilar (id, kurum_id, gonderen_id, alici_id, seviye, not_metni, gonderildi)
		 VALUES (?, ?, ?, ?, ?, ?, ?)`,
		c.ID, c.KurumID, c.GonderenID, c.AliciID, c.Seviye, c.Not, c.Gonderildi.Unix(),
	)
	return err
}

// CagriYanitla, çağrıya verilen cevabı kaydeder ve güncel çağrıyı döner.
func (s *Store) CagriYanitla(cagriID, yanit string) (model.Cagri, error) {
	simdi := time.Now()
	sonuc, err := s.db.Exec(
		`UPDATE cagrilar SET yanit = ?, yanit_tarih = ? WHERE id = ? AND yanit = ''`,
		yanit, simdi.Unix(), cagriID,
	)
	if err != nil {
		return model.Cagri{}, err
	}
	if n, _ := sonuc.RowsAffected(); n == 0 {
		// Çağrı yok ya da zaten yanıtlanmış.
		return model.Cagri{}, ErrBulunamadi
	}
	return s.CagriGetir(cagriID)
}

// CagriGetir, çağrıyı kimliğiyle okur.
func (s *Store) CagriGetir(id string) (model.Cagri, error) {
	var c model.Cagri
	var gonderildi, yanitTarih int64
	err := s.db.QueryRow(
		`SELECT id, kurum_id, gonderen_id, alici_id, seviye, not_metni, gonderildi, yanit, yanit_tarih
		 FROM cagrilar WHERE id = ?`, id,
	).Scan(&c.ID, &c.KurumID, &c.GonderenID, &c.AliciID, &c.Seviye, &c.Not, &gonderildi, &c.Yanit, &yanitTarih)
	if errors.Is(err, sql.ErrNoRows) {
		return model.Cagri{}, ErrBulunamadi
	}
	if err != nil {
		return model.Cagri{}, err
	}
	c.Gonderildi = time.Unix(gonderildi, 0)
	if yanitTarih > 0 {
		c.YanitTarih = time.Unix(yanitTarih, 0)
	}
	return c, nil
}

// YeniCagriID, çağrı kimliği üretir.
func YeniCagriID() string { return yeniID() }
