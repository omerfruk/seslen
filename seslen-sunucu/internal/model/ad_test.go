package model

import "testing"

// TestAdDuzeltGorunmezKarakterler, isim benzersizliğini atlatmaya yarayan
// karakterlerin ayıklandığını doğrular.
//
// Sıfır genişlikli boşluk içeren bir ad ekranda mevcut bir üyeyle birebir aynı
// görünür; süzülmeseydi "Ömer" varken ikinci bir "Ömer" yaratmak tek karakter
// meselesi olurdu.
func TestAdDuzeltGorunmezKarakterler(t *testing.T) {
	durumlar := []struct {
		ad     string
		girdi  string
		beklen string
	}{
		{"sıfır genişlikli boşluk", "Ömer​", "Ömer"},
		{"sıfır genişlikli birleştirici", "Ö‍mer", "Ömer"},
		{"yön değiştirme işareti", "Ali‮Veli", "AliVeli"},
		{"boş karakter", "Ali\x00Veli", "AliVeli"},
		{"denetim karakteri", "Ali\x01Veli", "AliVeli"},
		{"bölünmez boşluk", "Ali Veli", "Ali Veli"},
		{"fazla boşluk", "  Ali   Veli  ", "Ali Veli"},
		{"satır sonu", "Ali\nVeli", "Ali Veli"},
	}

	for _, d := range durumlar {
		t.Run(d.ad, func(t *testing.T) {
			sonuc, tamam := AdDuzelt(d.girdi)
			if !tamam {
				t.Fatalf("%q reddedildi, kabul edilmeliydi", d.girdi)
			}
			if sonuc != d.beklen {
				t.Errorf("%q → %q, beklenen %q", d.girdi, sonuc, d.beklen)
			}
		})
	}
}

// TestAdDuzeltReddedilenler, harf içermeyen ve sınır dışı adların
// reddedildiğini doğrular.
func TestAdDuzeltReddedilenler(t *testing.T) {
	kotu := []struct{ ad, girdi string }{
		{"tek harf", "A"},
		{"boş", ""},
		{"yalnızca boşluk", "   "},
		{"yalnızca rakam", "12"},
		{"yalnızca noktalama", "!!"},
		{"yalnızca emoji", "🙂🙂"},
		{"yalnızca görünmez", "​​​"},
		{"çok uzun", "AliVeliAliVeliAliVeliAliVeliAliVeliAliVeliX"},
	}

	for _, d := range kotu {
		t.Run(d.ad, func(t *testing.T) {
			if sonuc, tamam := AdDuzelt(d.girdi); tamam {
				t.Errorf("%q kabul edildi (%q), reddedilmeliydi", d.girdi, sonuc)
			}
		})
	}
}

// TestAdAnahtariTurkce, isim karşılaştırmasının Türkçe harflerde doğru
// çalıştığını doğrular.
//
// Her satır ayrı bir kolu koruyor: I→ı çevirisi, ayrık/birleşik biçim (NFC) ve
// SQLite'ın ASCII `LOWER()`'ının yakalayamadığı Ö/Ş/Ç/Ğ/Ü.
func TestAdAnahtariTurkce(t *testing.T) {
	ayni := []struct{ ad, sol, sag string }{
		{"büyük I noktasız ı ile eşleşir", "IŞIL", "ışıl"},
		{"ALI ile alı", "ALI", "alı"},
		{"büyük İ ile i", "ALİ VELİ", "ali veli"},
		{"Ö büyük küçük", "Ömer", "ömer"},
		{"Ş Ç Ğ Ü", "ŞÜKRÜ ÇAĞRI", "şükrü çağrı"},
		// macOS'tan kopyalanan metin ayrık biçimde gelir: "Ö" = O + U+0308.
		{"ayrık ve birleşik biçim", "Ömer", "Ömer"},
		{"ayrık Ş", "Şamil", "Şamil"},
	}

	for _, d := range ayni {
		t.Run(d.ad, func(t *testing.T) {
			if AdAnahtari(d.sol) != AdAnahtari(d.sag) {
				t.Errorf("%q ile %q aynı sayılmalıydı: %q vs %q",
					d.sol, d.sag, AdAnahtari(d.sol), AdAnahtari(d.sag))
			}
		})
	}

	// Farklı isimlerin çakışmaması da aynı ölçüde önemli: fazla hevesli bir
	// normalleştirme meşru adları reddetmeye başlardı.
	farkli := []struct{ ad, sol, sag string }{
		{"ı ile i ayrı harftir", "Işıl", "İşil"},
		{"farklı isimler", "Ali", "Ayşe"},
		{"soyadı olan olmayan", "Ali Veli", "Ali"},
	}

	for _, d := range farkli {
		t.Run(d.ad, func(t *testing.T) {
			if AdAnahtari(d.sol) == AdAnahtari(d.sag) {
				t.Errorf("%q ile %q ayrı sayılmalıydı, ikisi de %q",
					d.sol, d.sag, AdAnahtari(d.sol))
			}
		})
	}
}
