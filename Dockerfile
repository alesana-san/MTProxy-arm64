# ---- Stage 1: downloader ----
FROM alpine:3.20 AS builder

# Install curl and CA certificates
RUN apk add --no-cache curl ca-certificates

WORKDIR /build

# Download MTProto proxy binary, configs and start script
RUN curl -fsSL https://github.com/mihele95/MTProxy-arm64/releases/download/v1.0.0/mtproto-proxy -o mtproto-proxy && \
    curl -fsSL https://core.telegram.org/getProxySecret -o proxy-secret && \
    curl -fsSL https://core.telegram.org/getProxyConfig -o proxy-multi.conf && \
    curl -fsSL https://raw.githubusercontent.com/alesana-san/MTProxy-arm64/refs/heads/master/start.sh -o start.sh && \
    chmod +x mtproto-proxy start.sh


# ---- Stage 2: runtime ----
FROM alpine:3.20

# Install runtime dependencies
RUN apk add --no-cache ca-certificates busybox-extras

# Create a non-root user
RUN addgroup -S mtproxy && adduser -S -G mtproxy mtproxy

WORKDIR /app

# Copy only necessary files from builder stage
COPY --from=builder /build/mtproto-proxy .
COPY --from=builder /build/proxy-secret .
COPY --from=builder /build/proxy-multi.conf .
COPY --from=builder /build/start.sh .

# Ensure correct permissions
RUN chmod +x mtproto-proxy start.sh && \
    chown -R mtproxy:mtproxy /app

# Switch to non-root user
USER mtproxy

# Healthcheck: checks localhost port (default 443 or value from MTPROXY_PORT env)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD sh -c 'nc -z 127.0.0.1 ${MTPROXY_PORT:-443} || exit 1'

# Command to run MTProto proxy
CMD ["sh", "start.sh"]
