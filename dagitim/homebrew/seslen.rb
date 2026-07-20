# Seslen Homebrew Cask'ı.
#
# Bu dosya `omerfruk/homebrew-seslen` deposundaki `Casks/seslen.rb` yoluna
# konur. Kullanıcı tek komutla kurar:
#
#   brew install --cask omerfruk/seslen/seslen
#
# NEDEN TAM NİTELİKLİ AD: Homebrew 6.0'dan itibaren `HOMEBREW_REQUIRE_TAP_TRUST`
# varsayılan olarak açık; resmi olmayan tap'lerdeki cask'lar yüklenmeden önce
# `brew trust` ile onaylanmalı. Kaynağı `kullanici/tap/cask` biçiminde tam
# yazmak bu onayın yerine geçer (`Trust.trust_fully_qualified_items!`) ve tap'i
# de kendiliğinden ekler. Üstelik güveni tap'in tamamına değil yalnızca bu
# cask'a verdiği için `brew trust omerfruk/seslen`'den dar kapsamlıdır.
#
# SÜRÜM ÇIKARIRKEN: `version` ve `sha256` alanları güncellenmelidir.
# `make dmg` komutu DMG'nin SHA256 özetini ekrana yazar.
cask "seslen" do
  version "0.1.2"
  sha256 "SHA256_YER_TUTUCU"

  url "https://github.com/omerfruk/seslen/releases/download/v#{version}/Seslen-#{version}.dmg"
  name "Seslen"
  desc "Kulaklıkla çalışan ekipler için sessiz seslenme uygulaması"
  homepage "https://github.com/omerfruk/seslen"

  # Sembol biçimi en düşük sürümü belirtir; ">= :sonoma" karşılaştırma
  # biçimi Homebrew tarafından kullanımdan kaldırıldı.
  depends_on macos: :sonoma

  app "Seslen.app"

  # Uygulama Apple Developer sertifikasıyla imzalanmadığı için macOS karantina
  # bayrağı koyar ve açılışta "hasarlı" der. Kullanıcı kaynağı tam adıyla
  # yazarak kurulumu zaten açıkça onayladığından, bayrağı burada temizlemek ek
  # bir sürtünme yaratmıyor; --no-quarantine yazmayı hatırlaması gerekmiyor.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Seslen.app"],
                   sudo: false
  end

  uninstall quit: "com.omerfruk.seslen"

  zap trash: [
    "~/Library/Preferences/com.omerfruk.seslen.plist",
    "~/Library/Caches/com.omerfruk.seslen",
  ]

  caveats <<~METIN
    Seslen menü çubuğunda çalışır; Dock'ta simgesi görünmez.

    İlk açılışta bir sunucu adresi girmeniz gerekir. Ekibinizin yöneticisi
    size sunucu adresini ve 6 haneli katılım kodunu verecektir.

    Uygulama Apple Developer sertifikasıyla imzalanmadığı için macOS yine de
    uyarabilir. O durumda:

      Sistem Ayarları → Gizlilik ve Güvenlik → "Yine de Aç"

    Uygulama içinde İzinler sekmesinde bu sayfayı açan bir kısayol var.
  METIN
end
