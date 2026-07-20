# --- Derleme aşaması ---
# go.mod `go 1.24` diyor ancak bağımlılık ağacındaki modüller en az 1.25
# istiyor; derleyici imajı bu yüzden daha yeni.
FROM golang:1.26-alpine AS derleyici

WORKDIR /kaynak

# Bağımlılıklar önce: kaynak değiştiğinde bu katman önbellekten gelir.
COPY go.mod go.sum ./
RUN go mod download

COPY . .

# CGO kapalı: modernc.org/sqlite saf Go olduğu için C bağımlılığı yok.
# Böylece scratch imajında çalışabilen tamamen statik bir ikili çıkıyor.
RUN CGO_ENABLED=0 GOOS=linux go build \
    -trimpath -ldflags="-s -w" \
    -o /seslen-sunucu .

# --- Çalışma aşaması ---
FROM alpine:3.20

# Sağlık kontrolü için curl, HTTPS için kök sertifikalar.
RUN apk add --no-cache ca-certificates curl tzdata && \
    adduser -D -u 10001 seslen

# Veritabanı kalıcı birimde durur.
RUN mkdir -p /veri && chown seslen:seslen /veri

COPY --from=derleyici /seslen-sunucu /usr/local/bin/seslen-sunucu

USER seslen
WORKDIR /veri
VOLUME ["/veri"]

ENV SESLEN_ADRES=":8787" \
    SESLEN_VT="/veri/seslen.db" \
    TZ="Europe/Istanbul"

EXPOSE 8787

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8787/saglik || exit 1

ENTRYPOINT ["seslen-sunucu"]
