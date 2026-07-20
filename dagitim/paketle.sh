#!/usr/bin/env bash
# Seslen.app paketini ve dağıtım DMG'sini üretir.
#
# Kullanım:
#   dagitim/paketle.sh              → Seslen.app üretir
#   dagitim/paketle.sh --dmg        → ayrıca Seslen-<surum>.dmg üretir
#   SURUM=1.2.0 dagitim/paketle.sh  → sürümü elle belirler

set -euo pipefail

KOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_DIZIN="$KOK/SeslenMac"
CIKIS="$KOK/cikti"
UYGULAMA="$CIKIS/Seslen.app"

# Sürüm: elle verilmezse en son git etiketinden, o da yoksa 0.1.0.
SURUM="${SURUM:-$(git -C "$KOK" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.1.0")}"

echo "==> Seslen $SURUM paketleniyor"

rm -rf "$UYGULAMA"
mkdir -p "$UYGULAMA/Contents/MacOS" "$UYGULAMA/Contents/Resources"

# --- 1. Simge adlarını doğrula ---
# Geçersiz bir SF Symbol adı derleme hatası vermez, sadece boş çizilir.
# Menü çubuğunda bu simgenin tamamen kaybolması demektir.
echo "==> SF Symbol adları doğrulanıyor"
swift "$KOK/dagitim/simge-dogrula.swift" "$SWIFT_DIZIN/Sources"

# --- 2. Evrensel ikili (Intel + Apple Silicon) ---
echo "==> Derleniyor (arm64 + x86_64)"
swift build \
  --package-path "$SWIFT_DIZIN" \
  --configuration release \
  --arch arm64 --arch x86_64

IKILI="$(swift build --package-path "$SWIFT_DIZIN" --configuration release --arch arm64 --arch x86_64 --show-bin-path)/Seslen"
cp "$IKILI" "$UYGULAMA/Contents/MacOS/Seslen"

# --- 3. Info.plist ---
sed "s/SURUM_YER_TUTUCU/$SURUM/g" \
  "$SWIFT_DIZIN/Sources/Seslen/Resources/Info.plist" \
  > "$UYGULAMA/Contents/Info.plist"

# --- 4. İkon ---
echo "==> İkon üretiliyor"
IKON_GECICI="$(mktemp -d)"
swift "$KOK/dagitim/ikon-uret.swift" "$IKON_GECICI/Seslen.iconset" > /dev/null
iconutil -c icns "$IKON_GECICI/Seslen.iconset" -o "$UYGULAMA/Contents/Resources/Seslen.icns"
rm -rf "$IKON_GECICI"

# --- 5. Ad-hoc imza ---
# Apple Developer hesabı olmadığı için gerçek imza atılamıyor. Ad-hoc imza,
# uygulamaya kararlı bir kimlik verir; Anahtar Zinciri erişimi ve açılışta
# başlatma bunun olmadan çalışmaz. Gatekeeper yine de ilk açılışta uyarır.
echo "==> Ad-hoc imzalanıyor"
codesign --force --deep --sign - "$UYGULAMA"
codesign --verify --verbose=1 "$UYGULAMA" 2>&1 | sed 's/^/    /'

echo "==> Hazır: $UYGULAMA"

# --- 6. DMG (isteğe bağlı) ---
if [[ "${1:-}" == "--dmg" ]]; then
  DMG="$CIKIS/Seslen-$SURUM.dmg"
  echo "==> DMG üretiliyor"
  rm -f "$DMG"

  SAHNE="$(mktemp -d)"
  cp -R "$UYGULAMA" "$SAHNE/"
  # Kullanıcı sürükleyip bıraksın diye Uygulamalar kısayolu.
  ln -s /Applications "$SAHNE/Uygulamalar"

  hdiutil create \
    -volname "Seslen $SURUM" \
    -srcfolder "$SAHNE" \
    -ov -format UDZO \
    "$DMG" > /dev/null
  rm -rf "$SAHNE"

  echo "==> Hazır: $DMG"
  echo "    SHA256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
fi
