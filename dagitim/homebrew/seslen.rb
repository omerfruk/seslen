# Seslen Homebrew Cask'ı.
#
# Bu dosya `omerfruk/homebrew-seslen` deposundaki `Casks/seslen.rb` yoluna
# konur. Kullanıcı şu komutlarla kurar:
#
#   brew tap omerfruk/seslen
#   brew trust omerfruk/seslen
#   brew install --cask seslen
#
# NEDEN `brew trust`: Homebrew 6.0'dan itibaren `HOMEBREW_REQUIRE_TAP_TRUST`
# varsayılan olarak açık ve resmi olmayan tüm tap'ler için bir kereye mahsus
# güven onayı isteniyor. Cask'ın içeriğiyle ilgisi yok, atlanamıyor.
#
# SÜRÜM ÇIKARIRKEN: `version` ve `sha256` alanları güncellenmelidir.
# `make dmg` komutu DMG'nin SHA256 özetini ekrana yazar.
cask "seslen" do
  version "0.1.1"
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
  # bayrağı koyar ve açılışta "hasarlı" der. Kullanıcı tap'e zaten `brew trust`
  # vermek zorunda olduğundan, bayrağı burada temizlemek ek bir sürtünme
  # yaratmıyor; kullanıcının --no-quarantine yazmayı hatırlamasına gerek kalmıyor.
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
