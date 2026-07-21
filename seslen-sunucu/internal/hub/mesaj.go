package hub

import (
	"encoding/json"
	"strings"
	"time"

	"github.com/omerfruk/seslen/seslen-sunucu/internal/model"
	"github.com/omerfruk/seslen/seslen-sunucu/internal/protokol"
	"github.com/omerfruk/seslen/seslen-sunucu/internal/store"
)

// maksNotUzunlugu, seslenmeye eklenen kısa notun sınırıdır.
const maksNotUzunlugu = 140

// tacizEsigi, kaç yanıtsız ACİL'den sonra çağrının kendiliğinden taciz
// seviyesine yükseleceğidir. Eşiğe ulaşan çağrının kendisi tacize dönüşür.
const tacizEsigi = 3

// tacizPenceresi, yanıtsız ACİL'lerin sayıldığı zaman aralığıdır. Sınır
// olmasaydı sabah yanıtsız kalan iki çağrı, akşam gönderilen sıradan bir
// ACİL'i tacize çevirirdi.
const tacizPenceresi = 15 * time.Minute

// notKisalt, kullanıcının yazdığı notu kırpar ve sınıra sığdırır.
// Sınır harf sayısına göredir: bayt sayarak kesmek Türkçe harflerin
// ortasından bölüp bozuk UTF-8 üretebilir.
func notKisalt(ham string) string {
	not := strings.TrimSpace(ham)
	harfler := []rune(not)
	if len(harfler) > maksNotUzunlugu {
		not = string(harfler[:maksNotUzunlugu])
	}
	return not
}

// mesajIsle, istemciden gelen bir zarfı ilgili işleyiciye yönlendirir.
func (h *Hub) mesajIsle(b *Baglanti, zarf protokol.Zarf) {
	switch zarf.Tip {
	case protokol.TipSeslen:
		h.seslenIsle(b, zarf.Veri)
	case protokol.TipHaykir:
		h.haykirIsle(b, zarf.Veri)
	case protokol.TipYanitla:
		h.yanitlaIsle(b, zarf.Veri)
	case protokol.TipDurumBildir:
		h.durumIsle(b, zarf.Veri)
	case protokol.TipUyeGuncelle:
		h.uyeGuncelleIsle(b, zarf.Veri)
	case protokol.TipUyeOnayla:
		h.uyeOnaylaIsle(b, zarf.Veri)
	case protokol.TipUyeSil:
		h.uyeSilIsle(b, zarf.Veri)
	case protokol.TipKodYenile:
		h.kodYenileIsle(b)
	case protokol.TipNabiz:
		mesaj, _ := protokol.Paketle(protokol.TipNabizYanit, nil)
		b.Yolla(mesaj)
	default:
		b.hata(protokol.HataGecersiz, "bilinmeyen mesaj tipi")
	}
}

// hata, bağlantıya standart bir hata yanıtı yollar.
func (b *Baglanti) hata(kod, mesaj string) {
	b.Yolla(protokol.HataPaketle(kod, mesaj))
}

// seslenIsle, bir üyeye seslenme talebini doğrular, kaydeder ve iletir.
func (h *Hub) seslenIsle(b *Baglanti, ham json.RawMessage) {
	var istek protokol.SeslenIstek
	if err := json.Unmarshal(ham, &istek); err != nil {
		b.hata(protokol.HataGecersiz, "istek çözümlenemedi")
		return
	}
	if !istek.Seviye.Gecerli() {
		b.hata(protokol.HataGecersiz, "geçersiz seviye")
		return
	}

	gonderen, err := h.depo.UyeGetir(b.uyeID)
	if err != nil {
		b.hata(protokol.HataSunucu, "gönderen okunamadı")
		return
	}
	if !gonderen.Onayli {
		b.hata(protokol.HataYetkisiz, "üyeliğiniz henüz onaylanmadı")
		return
	}
	// Yetki kontrolü: kimse kendi seviyesinin üstünde seslenemez.
	if !gonderen.MaxSeviye.Kapsar(istek.Seviye) {
		b.hata(protokol.HataYetkisiz, "bu seviyede seslenme yetkiniz yok")
		return
	}

	alici, err := h.depo.UyeGetir(istek.AliciID)
	if err != nil {
		b.hata(protokol.HataBulunamadi, "alıcı bulunamadı")
		return
	}
	// Kurum sınırı: başka kurumdaki birine seslenilemez.
	if alici.KurumID != gonderen.KurumID || !alici.Onayli {
		b.hata(protokol.HataBulunamadi, "alıcı bulunamadı")
		return
	}
	if alici.ID == gonderen.ID {
		b.hata(protokol.HataGecersiz, "kendinize seslenemezsiniz")
		return
	}

	// Yükseltme, meşgul bastırmasından önce yapılır: meşgul birine gönderilen ve
	// tacize yükselmiş bir ACİL geçmelidir. Sıra tersine çevrilirse taciz
	// yükseltmesi meşgulde ölür.
	cagri := model.Cagri{
		ID:         store.YeniCagriID(),
		KurumID:    gonderen.KurumID,
		GonderenID: gonderen.ID,
		AliciID:    alici.ID,
		Seviye:     h.seviyeyiYukselt(gonderen.ID, alici.ID, istek.Seviye),
		Not:        notKisalt(istek.Not),
		Gonderildi: time.Now(),
	}

	mesaj, err := protokol.Paketle(protokol.TipSeslenmeGeldi, protokol.SeslenmeGeldiVeri{
		CagriID:    cagri.ID,
		GonderenID: gonderen.ID,
		GonderenAd: gonderen.AdSoyad,
		Seviye:     cagri.Seviye,
		Not:        cagri.Not,
		Gonderildi: cagri.Gonderildi.Unix(),
	})
	if err != nil {
		b.hata(protokol.HataSunucu, "çağrı paketlenemedi")
		return
	}

	sonuc, err := h.cagriyiTeslimEt(cagri, mesaj)
	if err != nil {
		h.kayit.Error("çağrı kaydedilemedi", "hata", err)
		b.hata(protokol.HataSunucu, "çağrı kaydedilemedi")
		return
	}

	// Her iki halde de gönderene hata değil bilgi dönüyoruz: çağrı kaybolmadı,
	// yalnızca gecikecek. Hata dönseydi kullanıcı seslenmenin yere düştüğünü
	// sanıp tekrar tekrar denerdi.
	switch sonuc {
	case teslimCevrimdisi:
		b.Yolla(protokol.BilgiPaketle(alici.AdSoyad + " şu anda çevrimdışı — bilgisayarını açtığında görecek"))
	case teslimMesgul:
		b.Yolla(protokol.BilgiPaketle(alici.AdSoyad + " şu anda meşgul — müsait olduğunda görecek"))
	}

	h.kayit.Info("seslenme kaydedildi",
		"gonderen", gonderen.AdSoyad, "alici", alici.AdSoyad, "seviye", cagri.Seviye,
		"teslim", sonuc)
}

// teslimSonucu, çağrının alıcıya ulaşıp ulaşmadığını, ulaşmadıysa sebebini söyler.
type teslimSonucu string

const (
	// teslimEdilmedi yalnızca hata dönüşlerinde kullanılır; çağıran önce err'e bakar.
	teslimEdilmedi   teslimSonucu = ""
	teslimEdildi     teslimSonucu = "edildi"
	teslimCevrimdisi teslimSonucu = "cevrimdisi"
	teslimMesgul     teslimSonucu = "mesgul"
)

// cagriyiTeslimEt, çağrıyı kaydeder ve alıcıya ulaştırmayı dener.
//
// Alıcının durumunu okuma, çağrıyı yazma ve teslim kararını verme işleri tek
// kilit altında yürür; gerekçesi Hub.teslimMu'nun yanında yazılı.
func (h *Hub) cagriyiTeslimEt(cagri model.Cagri, mesaj []byte) (teslimSonucu, error) {
	h.teslimMu.Lock()
	defer h.teslimMu.Unlock()

	if err := h.depo.CagriKaydet(cagri); err != nil {
		return teslimEdilmedi, err
	}

	// Çevrimiçilik önce sorulur: alıcı çevrimdışıyken durum kolonu "mesgul"
	// kalabiliyor, ve o halde gönderene "meşgul" değil "çevrimdışı" denmeli.
	if !h.Cevrimici(cagri.AliciID) {
		return teslimCevrimdisi, nil
	}

	alici, err := h.depo.UyeGetir(cagri.AliciID)
	if err == nil && alici.Durum == model.DurumMesgul && cagri.Seviye.MesguldeBekler() {
		// Alıcıya hiçbir şey gönderilmez. Çağrı teslim_tarih = 0 ile kuyrukta
		// kalır ve alıcı müsaite döndüğü anda kacirilanlariYolla ile iletilir.
		return teslimMesgul, nil
	}

	if !h.UyeyeGonder(cagri.AliciID, mesaj) {
		return teslimCevrimdisi, nil
	}
	if err := h.depo.TeslimIsaretle([]string{cagri.ID}); err != nil {
		h.kayit.Error("teslim işaretlenemedi", "cagri", cagri.ID, "hata", err)
	}
	return teslimEdildi, nil
}

// seviyeyiYukselt, yanıtsız kalan ACİL çağrılar birikmişse seslenmeyi taciz
// seviyesine çıkarır.
//
// Bu yükseltme için ayrıca taciz yetkisi aranmaz; yetkiyi veren şey alıcının
// arka arkaya üç acil çağrıyı yanıtsız bırakmış olmasıdır. Elle taciz göndermek
// ise `MaxSeviye` ile sınırlıdır — biri kasten, diğeri hak edilerek gelir.
func (h *Hub) seviyeyiYukselt(gonderenID, aliciID string, istenen model.Seviye) model.Seviye {
	if istenen != model.SeviyeAcil {
		return istenen
	}
	yanitsiz, err := h.depo.YanitsizCagriSayisi(
		gonderenID, aliciID, model.SeviyeAcil, time.Now().Add(-tacizPenceresi))
	if err != nil {
		h.kayit.Error("yanıtsız çağrılar sayılamadı", "hata", err)
		return istenen
	}
	// Sayım bu çağrıyı henüz içermiyor: eşiğe onunla birlikte ulaşılır.
	if yanitsiz+1 >= tacizEsigi {
		h.kayit.Info("çağrı tacize yükseltildi",
			"gonderen", gonderenID, "alici", aliciID, "yanitsiz", yanitsiz)
		return model.SeviyeTaciz
	}
	return istenen
}

// haykirIsle, kurumdaki herkese aynı anda seslenir.
//
// Seviye kasten sabit (normal) ve yetki aranmaz: yayın herkesi ilgilendirdiği
// için en hafif biçimde gider, kimsenin ekranını kesmez. Seviye seçilebilseydi
// tek tıkla bütün ekibe tam ekran ACİL uyarı basmak mümkün olurdu.
func (h *Hub) haykirIsle(b *Baglanti, ham json.RawMessage) {
	var istek protokol.HaykirIstek
	if err := json.Unmarshal(ham, &istek); err != nil {
		b.hata(protokol.HataGecersiz, "istek çözümlenemedi")
		return
	}

	gonderen, err := h.depo.UyeGetir(b.uyeID)
	if err != nil {
		b.hata(protokol.HataSunucu, "gönderen okunamadı")
		return
	}
	if !gonderen.Onayli {
		b.hata(protokol.HataYetkisiz, "üyeliğiniz henüz onaylanmadı")
		return
	}

	uyeler, err := h.depo.UyeleriGetir(gonderen.KurumID)
	if err != nil {
		b.hata(protokol.HataSunucu, "üyeler okunamadı")
		return
	}

	not := notKisalt(istek.Not)
	simdi := time.Now()
	ulasan := 0
	mesgulSayisi := 0
	// Yayın kuyruğa girmez: saatler sonra teslim edilen bir "herkese
	// sesleniyorum" bilgi değil gürültüdür. Bu yüzden yayın çağrıları
	// ulaşsın ulaşmasın teslim edilmiş sayılır.
	yayilanlar := make([]string, 0, len(uyeler))

	for _, alici := range uyeler {
		if alici.ID == gonderen.ID {
			continue
		}

		cagri := model.Cagri{
			ID:         store.YeniCagriID(),
			KurumID:    gonderen.KurumID,
			GonderenID: gonderen.ID,
			AliciID:    alici.ID,
			Seviye:     model.SeviyeNormal,
			Not:        not,
			Gonderildi: simdi,
		}
		if err := h.depo.CagriKaydet(cagri); err != nil {
			h.kayit.Error("yayın çağrısı kaydedilemedi", "alici", alici.ID, "hata", err)
			continue
		}

		mesaj, err := protokol.Paketle(protokol.TipSeslenmeGeldi, protokol.SeslenmeGeldiVeri{
			CagriID:    cagri.ID,
			GonderenID: gonderen.ID,
			GonderenAd: gonderen.AdSoyad,
			Seviye:     cagri.Seviye,
			Not:        cagri.Not,
			Gonderildi: cagri.Gonderildi.Unix(),
			Yayin:      true,
		})
		if err != nil {
			continue
		}
		switch {
		// Meşgul üyeye yayın iletilmez. Meşgulün tanımı "beni kesme"yse,
		// ekipteki herkesin tek tıkla o kalkanı delebilmesi tutarsız olurdu.
		// Kuyruğa da girmez: gecikmiş yayın gürültüdür (yukarıdaki not).
		case alici.Durum == model.DurumMesgul && h.Cevrimici(alici.ID):
			mesgulSayisi++
		// Çevrimdışı üyeye ulaşamamak yayını başarısız yapmaz; tek kişilik
		// seslenmeden farkı bu.
		case h.UyeyeGonder(alici.ID, mesaj):
			ulasan++
		}
		yayilanlar = append(yayilanlar, cagri.ID)
	}

	if err := h.depo.TeslimIsaretle(yayilanlar); err != nil {
		h.kayit.Error("yayın teslimi işaretlenemedi", "hata", err)
	}

	if ulasan == 0 {
		// Herkes çevrimiçi ama meşgulse "kimse yok" demek yalan olur; ayrıca
		// bu bir hata değil, kullanıcının bilmesi gereken bir durum.
		if mesgulSayisi > 0 {
			b.Yolla(protokol.BilgiPaketle("Ekipteki herkes şu anda meşgul — haykırış iletilmedi"))
			return
		}
		b.hata(protokol.HataBulunamadi, "şu anda çevrimiçi kimse yok")
		return
	}

	h.kayit.Info("yayın iletildi",
		"gonderen", gonderen.AdSoyad, "ulasan", ulasan, "mesgul", mesgulSayisi)
}

// yanitlaIsle, alıcının çağrıya verdiği cevabı gönderene ulaştırır.
func (h *Hub) yanitlaIsle(b *Baglanti, ham json.RawMessage) {
	var istek protokol.YanitlaIstek
	if err := json.Unmarshal(ham, &istek); err != nil {
		b.hata(protokol.HataGecersiz, "istek çözümlenemedi")
		return
	}
	if !model.GecerliYanit(istek.Yanit) {
		b.hata(protokol.HataGecersiz, "geçersiz yanıt")
		return
	}

	cagri, err := h.depo.CagriGetir(istek.CagriID)
	if err != nil {
		b.hata(protokol.HataBulunamadi, "çağrı bulunamadı")
		return
	}
	// Yalnızca çağrının alıcısı yanıtlayabilir.
	if cagri.AliciID != b.uyeID {
		b.hata(protokol.HataYetkisiz, "bu çağrı size ait değil")
		return
	}

	guncel, err := h.depo.CagriYanitla(istek.CagriID, istek.Yanit)
	if err != nil {
		// Zaten yanıtlanmışsa sessizce geçiyoruz; kullanıcı iki kez tıklamış olabilir.
		return
	}

	alici, err := h.depo.UyeGetir(b.uyeID)
	if err != nil {
		return
	}

	mesaj, err := protokol.Paketle(protokol.TipYanitGeldi, protokol.YanitGeldiVeri{
		CagriID:    guncel.ID,
		AliciID:    alici.ID,
		AliciAd:    alici.AdSoyad,
		Yanit:      guncel.Yanit,
		YanitTarih: guncel.YanitTarih.Unix(),
	})
	if err != nil {
		return
	}
	h.UyeyeGonder(guncel.GonderenID, mesaj)
}

// durumIsle, kullanıcının kendi müsaitlik durumunu günceller.
func (h *Hub) durumIsle(b *Baglanti, ham json.RawMessage) {
	var istek protokol.DurumBildirIstek
	if err := json.Unmarshal(ham, &istek); err != nil {
		b.hata(protokol.HataGecersiz, "istek çözümlenemedi")
		return
	}
	// Çevrimdışı bağlantı üzerinden bildirilemez; o bilgi hub'ın kendi kaydından gelir.
	if !istek.Durum.Gecerli() || istek.Durum == model.DurumCevrimdisi {
		b.hata(protokol.HataGecersiz, "geçersiz durum")
		return
	}
	h.teslimMu.Lock()
	if err := h.depo.DurumGuncelle(b.uyeID, istek.Durum); err != nil {
		h.teslimMu.Unlock()
		b.hata(protokol.HataSunucu, "durum yazılamadı")
		return
	}
	// Müsaite dönen üyenin meşgulken bekletilen çağrıları hemen iletilir.
	// Kilit, tam bu sırada yazılan bir çağrının kuyrukta unutulmasını önler.
	if istek.Durum == model.DurumMusait {
		h.kacirilanlariYolla(b, protokol.SebepMesgul)
	}
	h.teslimMu.Unlock()

	// Yayın kilidin dışında: h.mu alıp N üyeye mesaj yolluyor, kilit altında
	// tutmanın kazancı yok.
	h.KurumaYayinla(b.kurumID)
}

// yonetimDogrula, isteği yapanın yönetim yetkisi olduğunu ve hedefin aynı kurumda
// bulunduğunu doğrular. Hedef gerekmiyorsa hedefID boş bırakılır.
func (h *Hub) yonetimDogrula(b *Baglanti, hedefID string) (yonetici, hedef model.Uye, tamam bool) {
	yonetici, err := h.depo.UyeGetir(b.uyeID)
	if err != nil {
		b.hata(protokol.HataSunucu, "üye okunamadı")
		return
	}
	if !yonetici.Rol.YonetimYetkisi() {
		b.hata(protokol.HataYetkisiz, "bu işlem için yönetici olmalısınız")
		return
	}
	if hedefID == "" {
		return yonetici, model.Uye{}, true
	}
	hedef, err = h.depo.UyeGetir(hedefID)
	if err != nil || hedef.KurumID != yonetici.KurumID {
		b.hata(protokol.HataBulunamadi, "üye bulunamadı")
		return yonetici, model.Uye{}, false
	}
	// Kurucu dokunulmazdır; yöneticiler onu değiştiremez veya silemez.
	if hedef.Rol == model.RolKurucu {
		b.hata(protokol.HataYetkisiz, "kurucu üzerinde işlem yapılamaz")
		return yonetici, model.Uye{}, false
	}
	return yonetici, hedef, true
}

// uyeGuncelleIsle, bir üyenin rolünü ve en yüksek seslenme seviyesini ayarlar.
func (h *Hub) uyeGuncelleIsle(b *Baglanti, ham json.RawMessage) {
	var istek protokol.UyeGuncelleIstek
	if err := json.Unmarshal(ham, &istek); err != nil {
		b.hata(protokol.HataGecersiz, "istek çözümlenemedi")
		return
	}
	if !istek.MaxSeviye.Gecerli() {
		b.hata(protokol.HataGecersiz, "geçersiz seviye")
		return
	}
	// Kurucu rolü devredilemez; yalnızca yönetici ve üye atanabilir.
	if istek.Rol != model.RolYonetici && istek.Rol != model.RolUye {
		b.hata(protokol.HataGecersiz, "geçersiz rol")
		return
	}

	_, hedef, tamam := h.yonetimDogrula(b, istek.UyeID)
	if !tamam {
		return
	}
	if err := h.depo.UyeGuncelle(hedef.ID, istek.Rol, istek.MaxSeviye); err != nil {
		b.hata(protokol.HataSunucu, "üye güncellenemedi")
		return
	}
	h.KurumaYayinla(b.kurumID)
}

// uyeOnaylaIsle, bekleyen katılım isteğini kabul eder.
func (h *Hub) uyeOnaylaIsle(b *Baglanti, ham json.RawMessage) {
	var istek protokol.UyeIDIstek
	if err := json.Unmarshal(ham, &istek); err != nil {
		b.hata(protokol.HataGecersiz, "istek çözümlenemedi")
		return
	}
	_, hedef, tamam := h.yonetimDogrula(b, istek.UyeID)
	if !tamam {
		return
	}
	if err := h.depo.UyeOnayla(hedef.ID); err != nil {
		b.hata(protokol.HataSunucu, "üye onaylanamadı")
		return
	}
	h.KurumaYayinla(b.kurumID)
}

// uyeSilIsle, üyeyi kurumdan çıkarır ve oturumunu kapatır.
func (h *Hub) uyeSilIsle(b *Baglanti, ham json.RawMessage) {
	var istek protokol.UyeIDIstek
	if err := json.Unmarshal(ham, &istek); err != nil {
		b.hata(protokol.HataGecersiz, "istek çözümlenemedi")
		return
	}
	_, hedef, tamam := h.yonetimDogrula(b, istek.UyeID)
	if !tamam {
		return
	}
	if err := h.depo.UyeSil(hedef.ID); err != nil {
		b.hata(protokol.HataSunucu, "üye silinemedi")
		return
	}
	h.OturumuKapat(hedef.ID)
	h.KurumaYayinla(b.kurumID)
}

// kodYenileIsle, kurumun katılım kodunu değiştirir.
func (h *Hub) kodYenileIsle(b *Baglanti) {
	if _, _, tamam := h.yonetimDogrula(b, ""); !tamam {
		return
	}
	if _, err := h.depo.KodYenile(b.kurumID); err != nil {
		b.hata(protokol.HataSunucu, "kod yenilenemedi")
		return
	}
	h.KurumaYayinla(b.kurumID)
}
