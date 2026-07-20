// Seslen sunucusu: aynı ortamda kulaklıkla çalışan ekiplerin birbirine
// rahatsız etmeden seslenmesini sağlayan WebSocket sunucusu.
package main

import (
	"context"
	"errors"
	"flag"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/omerfruk/seslen/seslen-sunucu/internal/api"
	"github.com/omerfruk/seslen/seslen-sunucu/internal/hub"
	"github.com/omerfruk/seslen/seslen-sunucu/internal/store"
)

func main() {
	adres := flag.String("adres", cevreDegeri("SESLEN_ADRES", ":8787"), "dinlenecek adres (örn. :8787)")
	vtYolu := flag.String("vt", cevreDegeri("SESLEN_VT", "seslen.db"), "SQLite veritabanı dosyası")
	ayrinti := flag.Bool("ayrinti", false, "ayrıntılı günlük kaydı")
	flag.Parse()

	seviye := slog.LevelInfo
	if *ayrinti {
		seviye = slog.LevelDebug
	}
	kayit := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: seviye}))

	depo, err := store.Ac(*vtYolu)
	if err != nil {
		kayit.Error("veritabanı açılamadı", "hata", err)
		os.Exit(1)
	}
	defer depo.Kapat()

	merkez := hub.Yeni(depo, kayit)
	sunucu := &http.Server{
		Addr:              *adres,
		Handler:           api.Yeni(depo, merkez, kayit).Yonlendirici(),
		ReadHeaderTimeout: 10 * time.Second,
		// WriteTimeout bilinçli olarak ayarlanmadı: WebSocket bağlantıları
		// uzun ömürlüdür ve zaman aşımı onları koparır.
	}

	go func() {
		kayit.Info("Seslen sunucusu başladı", "adres", *adres, "veritabani", *vtYolu)
		if err := sunucu.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			kayit.Error("sunucu durdu", "hata", err)
			os.Exit(1)
		}
	}()

	dur := make(chan os.Signal, 1)
	signal.Notify(dur, os.Interrupt, syscall.SIGTERM)
	<-dur

	kayit.Info("kapatılıyor...")
	ctx, iptal := context.WithTimeout(context.Background(), 10*time.Second)
	defer iptal()
	if err := sunucu.Shutdown(ctx); err != nil {
		kayit.Error("düzgün kapatılamadı", "hata", err)
	}
}

// cevreDegeri, ortam değişkenini okur; yoksa varsayılanı döner.
func cevreDegeri(anahtar, varsayilan string) string {
	if deger := os.Getenv(anahtar); deger != "" {
		return deger
	}
	return varsayilan
}
