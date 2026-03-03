# ===== Stage 1: download artifacts =====
FROM alpine:3.6 AS builder

WORKDIR /app

RUN apk add --no-cache curl ca-certificates \
    && curl -L -o mtproto-proxy \
        https://github.com/mihele95/MTProxy-arm64/releases/download/v1.0.0/mtproto-proxy \
    && curl -s https://core.telegram.org/getProxySecret -o proxy-secret \
    && curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf \
    && chmod +x mtproto-proxy


# ===== Stage 2: minimal runtime =====
FROM alpine:3.6

WORKDIR /app

COPY --from=builder /app/mtproto-proxy .
COPY --from=builder /app/proxy-secret .
COPY --from=builder /app/proxy-multi.conf .

EXPOSE 443 8888

ENTRYPOINT ["sh", "-c", "\
SECRET=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \\n'); \
echo \"==============================\"; \
echo \"MTProxy Secret: $SECRET\"; \
echo \"==============================\"; \
exec ./mtproto-proxy -u nobody -p 8888 -H 443 -S $SECRET --aes-pwd proxy-secret proxy-multi.conf -M 1 \
"]
