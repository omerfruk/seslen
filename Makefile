.PHONY: yardim test sunucu uygulama dmg calistir kur temizle yayinla

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
	@echo ""
	@echo "  ./yayinla.sh 0.1.3        Canlıya çıkar (sunucu + uygulama + brew)"
	@echo "  ./yayinla.sh 0.1.3 --deneme  Ne yapacağını gösterir, yayınlamaz"
	@echo "  ./yayinla.sh --sunucu     Yalnızca sunucuyu günceller"

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

# Canlıya çıkar. Elle çalıştırılır, her push'ta değil.
#   make yayinla SURUM=0.1.3
yayinla:
	@test -n "$(SURUM)" || { echo "Kullanım: make yayinla SURUM=0.1.3"; exit 1; }
	./yayinla.sh $(SURUM)
