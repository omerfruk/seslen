#!/usr/bin/env bash
# Seslen'i canlıya çıkarır. Elle çalıştırılır — her push'ta değil.
#
# Sürüm numarası son git etiketinden okunup kendiliğinden artırılır.
#
#   ./yayinla.sh            → yama artır (0.1.2 → 0.1.3) ve yayınla
#   ./yayinla.sh --yan      → yan sürüm artır (0.1.2 → 0.2.0)
#   ./yayinla.sh --ana      → ana sürüm artır (0.1.2 → 1.0.0)
#   ./yayinla.sh 0.4.0      → sürümü elle belirt
#   ./yayinla.sh --deneme   → hiçbir şey yayınlamaz, ne yapacağını gösterir
#   ./yayinla.sh --sunucu   → yalnızca sunucuyu günceller, sürüm üretmez
#   ./yayinla.sh --uygulama → yalnızca macOS uygulamasını yayınlar
#
# Ortam değişkenleriyle geçersiz kılınabilir:
#   SESLEN_SSH   (varsayılan deploy@204.168.229.111)
#   SESLEN_ALAN  (varsayılan seslen.cidaltime.com)

set -euo pipefail

KOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$KOK"

SSH_HEDEF="${SESLEN_SSH:-deploy@204.168.229.111}"
ALAN="${SESLEN_ALAN:-seslen.cidaltime.com}"
TAP_DEPO="https://github.com/omerfruk/homebrew-seslen.git"
SUNUCU_DIZIN="/srv/seslen"

# --- Renkli çıktı ---
kirmizi() { printf "\033[31m%s\033[0m\n" "$*"; }
yesil()   { printf "\033[32m%s\033[0m\n" "$*"; }
sari()    { printf "\033[33m%s\033[0m\n" "$*"; }
baslik()  { printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }

hata() { kirmizi "HATA: $*"; exit 1; }

# --- Argümanları çöz ---
SURUM=""
ARTIS="yama"          # yama | yan | ana
YALNIZ_UYGULAMA=0
YALNIZ_SUNUCU=0
DENEME=0

for arg in "$@"; do
  case "$arg" in
    --uygulama) YALNIZ_UYGULAMA=1 ;;
    --sunucu)   YALNIZ_SUNUCU=1 ;;
    --deneme)   DENEME=1 ;;
    --yama)     ARTIS="yama" ;;
    --yan)      ARTIS="yan" ;;
    --ana)      ARTIS="ana" ;;
    -h|--yardim|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -18
      exit 0 ;;
    -*) hata "bilinmeyen seçenek: $arg" ;;
    *)  SURUM="$arg" ;;
  esac
done

# Etiket listesi güncel olmadan sonraki sürüm doğru hesaplanamaz.
git fetch -q --tags origin 2>/dev/null || true

# En son yayınlanan sürümü bulur. Etiketler sürüm sırasına göre sıralanır;
# alfabetik sıralama v0.1.10'u v0.1.9'dan önce koyardı.
son_surum() {
  git tag -l 'v[0-9]*' --sort=-v:refname | head -1 | sed 's/^v//'
}

# Verilen sürümü, istenen bileşeni artırarak bir sonrakine taşır.
sonraki_surum() {
  local mevcut="$1" ana yan yama
  IFS=. read -r ana yan yama <<< "$mevcut"
  case "$ARTIS" in
    ana) ana=$((ana + 1)); yan=0; yama=0 ;;
    yan) yan=$((yan + 1)); yama=0 ;;
    *)   yama=$((yama + 1)) ;;
  esac
  echo "$ana.$yan.$yama"
}

# Sunucu-only dışında bir sürüme ihtiyacımız var.
if [[ $YALNIZ_SUNUCU -eq 0 ]]; then
  if [[ -n "$SURUM" ]]; then
    [[ "$SURUM" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
      || hata "sürüm 'X.Y.Z' biçiminde olmalı (gelen: $SURUM)"
    SURUM_KAYNAGI="elle belirtildi"
  else
    ONCEKI="$(son_surum)"
    if [[ -z "$ONCEKI" ]]; then
      # Hiç etiket yoksa ilk sürüm.
      SURUM="0.1.0"
      SURUM_KAYNAGI="ilk sürüm (etiket yok)"
    else
      SURUM="$(sonraki_surum "$ONCEKI")"
      SURUM_KAYNAGI="v$ONCEKI → $ARTIS artırıldı"
    fi
  fi
fi

if [[ $DENEME -eq 1 ]]; then
  sari "DENEME KİPİ — hiçbir şey yayınlanmayacak"
fi

# Sürüm elle yazılmadığında ne yayınlanacağı komuttan anlaşılmaz;
# ilk iş olarak açıkça yazdırıyoruz.
if [[ $YALNIZ_SUNUCU -eq 0 ]]; then
  printf "\n\033[1mYayınlanacak sürüm: \033[1;32mv%s\033[0m  \033[2m(%s)\033[0m\n" \
    "$SURUM" "$SURUM_KAYNAGI"
else
  printf "\n\033[1mYalnızca sunucu güncellenecek\033[0m \033[2m(sürüm üretilmiyor)\033[0m\n"
fi

# --- Ön kontroller ---
baslik "Ön kontroller"

command -v gh >/dev/null || hata "gh (GitHub CLI) kurulu değil"
gh auth status >/dev/null 2>&1 || hata "gh yetkili değil. 'gh auth login' çalıştırın."
yesil "  gh hazır"

if [[ -n "$(git status --porcelain)" ]]; then
  git status --short | sed 's/^/    /'
  hata "çalışma dizini temiz değil. Önce commit edin ya da geri alın."
fi
yesil "  çalışma dizini temiz"

DAL="$(git rev-parse --abbrev-ref HEAD)"
[[ "$DAL" == "main" ]] || sari "  uyarı: 'main' yerine '$DAL' dalındasınız"

# Uzaktaki main ile aynı noktada mıyız?
git fetch -q origin main
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
  hata "yerel dal origin/main ile aynı değil. Önce push/pull yapın."
fi
yesil "  origin/main ile eşleşiyor"

if [[ $YALNIZ_SUNUCU -eq 0 ]] && git rev-parse "v$SURUM" >/dev/null 2>&1; then
  hata "v$SURUM etiketi zaten var. Sürümü artırın."
fi

if [[ $YALNIZ_UYGULAMA -eq 0 ]]; then
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$SSH_HEDEF" 'exit' 2>/dev/null \
    || hata "sunucuya bağlanılamadı: $SSH_HEDEF"
  yesil "  sunucuya erişim var"
fi

# --- Testler ---
baslik "Testler"
if [[ $DENEME -eq 1 ]]; then
  sari "  (deneme) atlandı"
else
  (cd seslen-sunucu && go test -race -count=1 ./... 2>&1 | grep -v "no test files" | sed 's/^/    /')
  yesil "  sunucu testleri geçti"
fi

# --- Sunucu yayını ---
if [[ $YALNIZ_UYGULAMA -eq 0 ]]; then
  baslik "Sunucu güncelleniyor ($ALAN)"

  if [[ $DENEME -eq 1 ]]; then
    sari "  (deneme) $SSH_HEDEF üzerinde git pull + docker compose up -d --build"
  else
    ssh -o BatchMode=yes "$SSH_HEDEF" "
      set -e
      cd '$SUNUCU_DIZIN'
      git fetch -q origin main
      git reset -q --hard origin/main
      SESLEN_ALAN='$ALAN' docker compose -f docker-compose.sunucu.yml up -d --build
    " 2>&1 | grep -E "Container|Image|Network|Volume|error|Error" | sed 's/^/    /' || true

    # 1) Kabın kendi sağlık durumu. Bu, yeni kap hakkında kesin bilgi verir;
    #    dışarıdan bakmak eski kaba denk gelebilir.
    printf "    kap sağlığı bekleniyor"
    KAP_HAZIR=0
    for _ in $(seq 1 40); do
      DURUM="$(ssh -o BatchMode=yes "$SSH_HEDEF" \
        'docker inspect --format="{{.State.Health.Status}}" seslen 2>/dev/null' 2>/dev/null || echo "")"
      if [[ "$DURUM" == "healthy" ]]; then KAP_HAZIR=1; break; fi
      printf "."
      sleep 3
    done
    printf "\n"
    [[ $KAP_HAZIR -eq 1 ]] || hata "kap sağlıklı duruma geçmedi (son durum: ${DURUM:-bilinmiyor})"
    yesil "  kap sağlıklı"

    # 2) Dışarıdan erişim. Traefik yeni kaba geçerken kısa bir kesinti olabilir,
    #    bu yüzden tek bir başarı yeterli sayılmaz; art arda üç kez istiyoruz.
    printf "    dışarıdan erişim sınanıyor"
    ARDISIK=0
    DISARI_HAZIR=0
    for _ in $(seq 1 40); do
      if curl -fsS --max-time 5 "https://$ALAN/saglik" >/dev/null 2>&1; then
        ARDISIK=$((ARDISIK + 1))
        if [[ $ARDISIK -ge 3 ]]; then DISARI_HAZIR=1; break; fi
      else
        ARDISIK=0
      fi
      printf "."
      sleep 2
    done
    printf "\n"
    [[ $DISARI_HAZIR -eq 1 ]] || hata "sunucu dışarıdan kararlı yanıt vermedi: https://$ALAN/saglik"
    yesil "  sunucu ayakta: https://$ALAN"

    # WebSocket yükseltmesi ters vekilde en sık kırılan yerdir; ayrıca sınıyoruz.
    KOD="$(curl -s -o /dev/null -w '%{http_code}' --http1.1 --max-time 8 \
      -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
      -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
      "https://$ALAN/ws?token=gecersiz" || true)"
    # Geçersiz token 401 döner: bu, isteğin Traefik'i aşıp sunucuya ulaştığını
    # ve kimlik denetiminin çalıştığını gösterir. 404/502 gelirse yönlendirme bozuktur.
    if [[ "$KOD" == "401" ]]; then
      yesil "  WebSocket yolu çalışıyor (kimlik denetimi devrede)"
    else
      sari "  uyarı: /ws beklenmeyen yanıt verdi (HTTP $KOD) — elle kontrol edin"
    fi
  fi
fi

# --- Uygulama yayını ---
if [[ $YALNIZ_SUNUCU -eq 0 ]]; then
  baslik "Uygulama paketleniyor (v$SURUM)"

  if [[ $DENEME -eq 1 ]]; then
    sari "  (deneme) DMG üretimi, etiket, GitHub release, tap güncellemesi"
  else
    SURUM="$SURUM" ./dagitim/paketle.sh --dmg 2>&1 \
      | grep -vE "^[0-9]+%|Compiling|Building|Target dep" | sed 's/^/    /'

    DMG="cikti/Seslen-$SURUM.dmg"
    [[ -f "$DMG" ]] || hata "DMG üretilemedi: $DMG"
    SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"

    baslik "Etiket ve GitHub release"
    git tag -a "v$SURUM" -m "Seslen $SURUM"
    git push -q origin "v$SURUM"

    gh release create "v$SURUM" "$DMG" \
      --title "Seslen $SURUM" \
      --notes "## Kurulum

\`\`\`bash
brew install --cask omerfruk/seslen/seslen
\`\`\`

Zaten kuruluysa: \`brew upgrade --cask seslen\`

macOS 14 (Sonoma) ve üzeri · Intel + Apple Silicon" >/dev/null
    yesil "  release yayında: v$SURUM"

    baslik "Homebrew tap güncelleniyor"
    TAP_GECICI="$(mktemp -d)"
    trap 'rm -rf "$TAP_GECICI"' EXIT

    git clone -q "$TAP_DEPO" "$TAP_GECICI"
    sed -e "s/^  version .*/  version \"$SURUM\"/" \
        -e "s/^  sha256 .*/  sha256 \"$SHA\"/" \
        dagitim/homebrew/seslen.rb > "$TAP_GECICI/Casks/seslen.rb"

    # Yer tutucu kaldıysa cask bozuk demektir.
    grep -q "SHA256_YER_TUTUCU" "$TAP_GECICI/Casks/seslen.rb" \
      && hata "cask'ta sha256 yer tutucusu kaldı"

    (cd "$TAP_GECICI"
     git add -A
     git commit -q -m "Seslen $SURUM"
     git push -q origin main)
    yesil "  tap güncellendi: $SURUM ($SHA)"

    # Depodaki cask sürümünü de güncel tut.
    sed -i '' "s/^  version .*/  version \"$SURUM\"/" dagitim/homebrew/seslen.rb
    if [[ -n "$(git status --porcelain)" ]]; then
      git add -A
      git commit -q -m "Cask $SURUM'e güncellendi"
      git push -q origin main
    fi
  fi
fi

baslik "Bitti"
if [[ $DENEME -eq 1 ]]; then
  sari "Deneme kipiydi, hiçbir şey değişmedi."
else
  [[ $YALNIZ_UYGULAMA -eq 0 ]] && echo "  sunucu    https://$ALAN"
  [[ $YALNIZ_SUNUCU -eq 0 ]]   && echo "  uygulama  brew upgrade --cask seslen   (v$SURUM)"
  echo
  yesil "Canlıya çıkıldı."
fi
