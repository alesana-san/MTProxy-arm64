FROM alpine:3.6

WORKDIR /app

RUN apk add --no-cache --virtual .build-deps curl ca-certificates \
    && curl -L -o mtproto-proxy \
        https://github.com/mihele95/MTProxy-arm64/releases/download/v1.0.0/mtproto-proxy \
    && curl -s https://core.telegram.org/getProxySecret -o proxy-secret \
    && curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf \
    && chmod +x mtproto-proxy \
    && apk del .build-deps

EXPOSE 443 8888

ENTRYPOINT ["sh", "-c", "SECRET=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \\n'); exec ./mtproto-proxy -u nobody -p 8888 -H 443 -S $SECRET --aes-pwd proxy-secret proxy-multi.conf -M 1"]
