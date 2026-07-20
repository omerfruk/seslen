.PHONY: yardim test sunucu uygulama dmg calistir kur temizle

SUNUCU_DIZIN := seslen-sunucu
SWIFT_DIZIN  := SeslenMac
CIKIS        := cikti

yardim:
	@echo "Seslen — kullanılabilir komutlar:"
	@echo ""
	@echo "  make test       Sunucu testlerini çalıştırır"
	@echo "  make sunucu     Sunucu ikilisini derler       → $(CIKIS)/seslen-sunucu"
	@echo "  make calistir   Sunucuyu yerelde başlatır     → http://localhost:8787"
	@echo "  make uygulama   Seslen.app paketini üretir    → $(CIKIS)/Seslen.app"
	@echo "  make kur        Seslen.app'i /Applications'a kurar ve başlatır"
	@echo "  make dmg        Dağıtım DMG'si üretir         → $(CIKIS)/Seslen-<surum>.dmg"
	@echo "  make temizle    Üretilen dosyaları siler"

test:
	cd $(SUNUCU_DIZIN) && go test -race -count=1 ./...

sunucu:
	@mkdir -p $(CIKIS)
	cd $(SUNUCU_DIZIN) && go build -trimpath -ldflags="-s -w" -o ../$(CIKIS)/seslen-sunucu .
	@echo "==> Hazır: $(CIKIS)/seslen-sunucu"

# Yerel deneme için sunucuyu ön planda çalıştırır.
calistir: sunucu
	./$(CIKIS)/seslen-sunucu -adres :8787 -vt $(CIKIS)/seslen.db -ayrinti

uygulama:
	./dagitim/paketle.sh

dmg:
	./dagitim/paketle.sh --dmg

# Geliştirirken hızlı deneme: kur ve başlat.
kur: uygulama
	@osascript -e 'quit app "Seslen"' 2>/dev/null || true
	rm -rf /Applications/Seslen.app
	cp -R $(CIKIS)/Seslen.app /Applications/
	open /Applications/Seslen.app
	@echo "==> Seslen menü çubuğunda çalışıyor"

temizle:
	rm -rf $(CIKIS) $(SWIFT_DIZIN)/.build
	cd $(SUNUCU_DIZIN) && go clean
