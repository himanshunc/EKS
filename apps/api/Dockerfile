# ── Stage 1: Build ───────────────────────────────────────────────────────────
# Use the official Go builder image — compiles to a static binary.
# CGO_ENABLED=0 produces a fully static binary with no libc dependency.
FROM golang:1.22-alpine AS builder

WORKDIR /app

# Copy go.mod first so Docker can cache the dependency download layer.
# The layer only re-runs when go.mod changes, not on every code change.
COPY go.mod ./
RUN go mod download

COPY . .

# Build a static Linux binary — no CGO, no external libs.
# -ldflags="-s -w" strips debug symbols → smaller image.
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o server .

# ── Stage 2: Runtime ─────────────────────────────────────────────────────────
# Minimal Alpine image — only the binary and ca-certificates (for HTTPS).
# The final image is ~10 MB vs ~300 MB for the full Go builder image.
FROM alpine:3.19

# ca-certificates — needed if the app makes outbound HTTPS calls
RUN apk --no-cache add ca-certificates

WORKDIR /app
COPY --from=builder /app/server .

# Run as non-root user — security best practice
RUN addgroup -S app && adduser -S app -G app
USER app

EXPOSE 8080

CMD ["./server"]
