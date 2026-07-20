# 📣 Seslen

Aynı ortamda kulaklıkla çalışan ekipler için sessiz seslenme uygulaması.

Birine seslenmek istediğinizde odadaki 3-5 kişiyi rahatsız etmek yerine,
yalnızca o kişinin ekranında uyarı belirir. macOS menü çubuğunda yaşar.

---

## Nasıl çalışır?

```
┌─────────────────┐         ┌──────────────────┐         ┌─────────────────┐
│  Ömer'in Mac'i  │◄───────►│   seslen-sunucu  │◄───────►│  Ali'nin Mac'i  │
│  (menü çubuğu)  │   ws    │   (Go + SQLite)  │   ws    │  (menü çubuğu)  │
└─────────────────┘         └──────────────────┘         └─────────────────┘
```

- **`seslen-sunucu/`** — Go ile yazılmış WebSocket sunucusu. Tek binary, CGO yok.
- **`SeslenMac/`** — SwiftUI menü çubuğu uygulaması. Evrensel (Intel + Apple Silicon).

---

## Aciliyet seviyeleri

| Seviye | Kim gönderebilir | Alıcıda ne olur |
|---|---|---|
| 💬 **Normal** | Herkes | Menü çubuğu simgesi + bildirim |
| ⚠️ **Önemli** | Yetki verilenler | Bildirim + ekranda panel + ses |
| 🚨 **ACİL** | Kurucu ve yöneticiler | Tam ekran panel + ses + ekran kenarı flaşı |

Her kişi, **kimden gelen** seslenmede **hangi uyarının** çalışacağını ayrı ayrı
seçebilir (Ayarlar → Kişiler). ACİL seviyesi bu kişisel ayarları ezer — bu
davranış Ayarlar → Uyarılar'dan kapatılabilir.

Ekran paneli, ses ve kenar flaşı **Rahatsız Etmeyin (Focus) kipinde bile
çalışır**, çünkü sistem bildirimi değil uygulamanın kendi penceresidir.

---

## Kurulum

### Kullanıcılar için

```bash
brew tap omerfruk/seslen
brew install --cask seslen
```

Uygulama Apple Developer sertifikasıyla imzalanmadığı için macOS ilk açılışta
uyarabilir. O durumda: **Sistem Ayarları → Gizlilik ve Güvenlik → "Yine de Aç"**.
Uygulamanın **İzinler** sekmesinde bu sayfayı açan bir kısayol düğmesi vardır.

### Geliştiriciler için

```bash
make test        # sunucu testlerini çalıştır
make calistir    # sunucuyu yerelde başlat (http://localhost:8787)
make kur         # Seslen.app'i derle, /Applications'a kur, başlat
make dmg         # dağıtım DMG'si üret
```

---

## İlk kullanım

**1. Sunucuyu başlatın**

```bash
make calistir
# ya da doğrudan:
./cikti/seslen-sunucu -adres :8787 -vt seslen.db
```

**2. Kurumu oluşturun** — Seslen'i açın, "Kurum Oluştur" sekmesine geçin,
kurum adınızı ve adınızı yazın. Sunucu adresini de burada girebilirsiniz.

**3. Arkadaşlarınızı davet edin** — Menü çubuğu → **Kurum**. Orada 6 haneli
katılım kodu (`ABC-123` biçiminde) görünür. Bu kodu ve sunucu adresini
arkadaşlarınıza verin.

**4. Katılanları onaylayın** — Biri katıldığında menüde turuncu bir şerit belirir.
Kurum penceresinden **Onayla** deyin.

**5. Yetki verin** — Kurum penceresindeki tabloda her kişinin rolünü ve
gönderebileceği en yüksek seviyeyi ayarlayın. Yeni üyeler varsayılan olarak
yalnızca **Normal** seviye gönderebilir.

---

## Sunucu adresi

Uygulama üç senaryoyu da destekler; Ayarlar → Genel'den değiştirilir:

| Senaryo | Adres |
|---|---|
| Aynı makinede deneme | `http://localhost:8787` |
| Ofis yerel ağı | `http://192.168.1.20:8787` (sunucunun IP'si) |
| Uzak sunucu | `https://seslen.ornek.com` |

> Yerel ağda düz `http` kullanılabilmesi için Info.plist'te
> `NSAllowsLocalNetworking` açıktır. Uzak sunucuda **mutlaka `https`**
> kullanın — aksi halde token'lar ağda açık gider.

---

## Sunucuyu kalıcı çalıştırma (Docker)

```bash
git clone https://github.com/omerfruk/seslen.git
cd seslen
docker compose up -d
```

Bu kadar. Sunucu `127.0.0.1:8787`'de dinler, veritabanı `seslen-veri`
biriminde durur, kap kendiliğinden yeniden başlar.

**Durumu görmek:**

```bash
docker compose ps          # sağlık durumu (healthy görmelisiniz)
docker compose logs -f     # canlı günlük
```

**Güncellemek:**

```bash
git pull && docker compose up -d --build
```

### Ters vekil

Sunucuda başka projeler de çalıştığı için Seslen portu internete açmaz.
TLS sonlandırmayı mevcut vekiliniz yapar. `docker-compose.yml` içinde iki
senaryo için de hazır ayar var:

- **Vekil aynı Docker ağındaysa** — `networks` altındaki `vekil-agi` satırını
  açın ve `ports` bölümünü kaldırın. Traefik kullanıyorsanız `labels`
  bloğunu da açın.
- **Vekil ana makinedeyse** — varsayılan ayar zaten bu; port yalnızca
  `127.0.0.1`'e bağlıdır.

Caddy örneği:

```
seslen.ornek.com {
    reverse_proxy 127.0.0.1:8787
}
```

nginx örneği — **WebSocket başlıkları şart**, yoksa bağlantı kurulmaz:

```nginx
location / {
    proxy_pass http://127.0.0.1:8787;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_read_timeout 3600s;   # bağlantılar uzun ömürlüdür
}
```

Caddy bu başlıkları kendiliğinden geçirir, ek ayar gerekmez.

### Docker olmadan (systemd)

```ini
# /etc/systemd/system/seslen.service
[Unit]
Description=Seslen sunucusu
After=network.target

[Service]
Type=simple
User=seslen
WorkingDirectory=/opt/seslen
ExecStart=/opt/seslen/seslen-sunucu -adres 127.0.0.1:8787 -vt /opt/seslen/seslen.db
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

---

## Sunucu seçenekleri

```
-adres    dinlenecek adres         (varsayılan :8787,      ortam: SESLEN_ADRES)
-vt       SQLite dosyası           (varsayılan seslen.db,  ortam: SESLEN_VT)
-ayrinti  ayrıntılı günlük kaydı
```

---

## Güvenlik notları

- Kimlik doğrulama, katılımda üretilen rastgele 32 baytlık **token** ile yapılır.
  Token istemcide **Anahtar Zinciri'nde** saklanır, sunucuda yalnızca SHA-256
  özeti tutulur.
- Katılım kodu ve bekleyen katılım istekleri yalnızca yönetici yetkisi olanlara
  gönderilir; sıradan üyeye sızmaz.
- Seviye yetkisi **sunucuda** doğrulanır. İstemcideki kilit simgesi yalnızca
  arayüz kolaylığıdır; değiştirilmiş bir istemci de yetkisiz seviye gönderemez.
- Kurum sınırı sunucuda zorlanır: başka kurumdaki birine seslenilemez, o kurumun
  üyeleri yönetilemez.

---

## Proje yapısı

```
seslen/
├── Makefile
├── seslen-sunucu/              # Go sunucusu
│   ├── main.go
│   ├── sunucu_test.go          # uçtan uca testler
│   └── internal/
│       ├── model/              # veri tipleri, yetki kuralları
│       ├── protokol/           # WebSocket mesaj sözleşmesi
│       ├── store/              # SQLite katmanı
│       ├── hub/                # bağlantı yönetimi + mesaj işleme
│       └── api/                # HTTP uçları
├── SeslenMac/                  # macOS uygulaması
│   └── Sources/Seslen/
│       ├── Model/              # veri tipleri, yerel ayarlar
│       ├── Ag/                 # protokol + WebSocket istemcisi
│       ├── Gorunum/            # SwiftUI ekranları
│       ├── Uyari/              # panel, kenar flaşı, ses, bildirim
│       └── Destek/             # Anahtar Zinciri, Sistem Ayarları
└── dagitim/
    ├── paketle.sh              # .app ve .dmg üretimi
    ├── ikon-uret.swift         # uygulama ikonu
    └── homebrew/seslen.rb      # Homebrew Cask'ı
```

> `internal/protokol/protokol.go` ile `Sources/Seslen/Ag/Protokol.swift`
> aynı sözleşmenin iki tarafıdır. Biri değişince diğeri de değişmelidir.
