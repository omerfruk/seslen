# Seslen Homebrew Cask'ı.
#
# Bu dosya `omerfruk/homebrew-seslen` deposundaki `Casks/seslen.rb` yoluna
# konur. Kullanıcı şu komutlarla kurar:
#
#   brew tap omerfruk/seslen
#   brew install --cask seslen
#
# SÜRÜM ÇIKARIRKEN: `version` ve `sha256` alanları güncellenmelidir.
# `make dmg` komutu DMG'nin SHA256 özetini ekrana yazar.
cask "seslen" do
  version "0.1.0"
  sha256 "SHA256_YER_TUTUCU"

  url "https://github.com/omerfruk/seslen/releases/download/v#{version}/Seslen-#{version}.dmg"
  name "Seslen"
  desc "Kulaklıkla çalışan ekipler için sessiz seslenme uygulaması"
  homepage "https://github.com/omerfruk/seslen"

  depends_on macos: ">= :sonoma"

  app "Seslen.app"

  # Uygulama Apple Developer sertifikasıyla imzalanmadığı için macOS'un
  # karantina bayrağını kaldırıyoruz. Aksi halde kullanıcı her açılışta
  # "hasarlı" uyarısı alır.
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

    İlk açılışta bir sunucu adresi girmeniz gerekir. Ekibinizin
    yöneticisi size sunucu adresini ve 6 haneli katılım kodunu verecektir.

    Uygulama imzasız dağıtıldığı için macOS ilk açılışta uyarabilir:
    Sistem Ayarları → Gizlilik ve Güvenlik → "Yine de Aç"
  METIN
end
