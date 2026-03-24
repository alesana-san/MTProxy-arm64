#!/bin/sh

set -eu

child_pid=""
timer_pid=""

cleanup() {
  echo "Caught interrupt, stopping..."

  if [ -n "$timer_pid" ]; then
    kill "$timer_pid" 2>/dev/null || true
    wait "$timer_pid" 2>/dev/null || true
  fi

  if [ -n "$child_pid" ]; then
    kill "$child_pid" 2>/dev/null || true
    wait "$child_pid" 2>/dev/null || true
  fi

  exit 0
}

trap cleanup INT TERM

# --- MTPROXY_SECRET ---
if [ -z "${MTPROXY_SECRET:-}" ]; then
  echo "MTPROXY_SECRET not set, generating..."
  MTPROXY_SECRET=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
  export MTPROXY_SECRET
  echo "Generated MTPROXY_SECRET: $MTPROXY_SECRET"
fi

# --- config file check ---
if [ ! -f "proxy-multi.conf" ]; then
  echo "Error: proxy-multi.conf not found"
  exit 1
fi

PORT="${MTPROXY_PORT:-443}"

# --- build command as args (без sh -c!) ---
CMD_ARGS="
-u nobody
-p 8888
-H ${PORT}
-S ${MTPROXY_SECRET}
proxy-multi.conf
-M 1
--http-stats
"

[ "${MTPROXY_VERBOSE+x}" = "x" ] && CMD_ARGS="$CMD_ARGS -v"
[ -n "${MTPROXY_TAG:-}" ] && CMD_ARGS="$CMD_ARGS -P ${MTPROXY_TAG}"

# --- NAT INFO ---
if [ -n "${MTPROXY_LOCAL_IP:-}" ] && [ -n "${MTPROXY_EXTERNAL_IP:-}" ]; then
  external_ip="$MTPROXY_EXTERNAL_IP"

  if ! echo "$external_ip" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    resolved_ip=$(nslookup "$external_ip" 2>/dev/null | awk '/^Address: / { print $2 }' | tail -n1)

    if [ -z "$resolved_ip" ]; then
      echo "Error: failed to resolve domain $external_ip"
      exit 1
    fi

    external_ip="$resolved_ip"
  fi

  CMD_ARGS="$CMD_ARGS --nat-info ${MTPROXY_LOCAL_IP}:${external_ip}"
fi

# --- AES PASSWORD ---
if [ -n "${MTPROXY_PROXY_SECRET:-}" ]; then
  if [ ! -f "${MTPROXY_PROXY_SECRET}" ]; then
    echo "Error: file ${MTPROXY_PROXY_SECRET} not found"
    exit 1
  fi
  CMD_ARGS="$CMD_ARGS --aes-pwd ${MTPROXY_PROXY_SECRET}"
else
  CMD_ARGS="$CMD_ARGS --aes-pwd proxy-secret"
fi

# --- MAIN LOOP ---
while true; do
  echo "Starting mtproto-proxy..."

  # запуск напрямую (важно!)
  ./mtproto-proxy $CMD_ARGS &
  child_pid=$!

  # таймер на 24 часа
  (
    sleep 86400
    echo "24h passed, restarting proxy..."
    kill "$child_pid" 2>/dev/null || true
  ) &
  timer_pid=$!

  # ждём завершения proxy
  wait "$child_pid" || true

  # чистим таймер
  kill "$timer_pid" 2>/dev/null || true
  wait "$timer_pid" 2>/dev/null || true

  echo "Proxy stopped, restarting in 2 seconds..."
  sleep 2
done
