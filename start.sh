#!/bin/sh

set -eu

# --- graceful shutdown ---
child_pid=""

cleanup() {
  echo "Caught interrupt, stopping..."
  if [ -n "${child_pid}" ]; then
    kill "${child_pid}" 2>/dev/null || true
    wait "${child_pid}" 2>/dev/null || true
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

# --- base command ---
CMD="./mtproto-proxy -u nobody -p 8888 -H 443 -S ${MTPROXY_SECRET} proxy-multi.conf -M 1 5 --http-stats"

# --- verbose flag ---
if [ "${MTPROXY_VERBOSE+x}" = "x" ]; then
  CMD="$CMD -v"
fi

# --- MTPROXY_TAG ---
if [ -n "${MTPROXY_TAG:-}" ]; then
  CMD="$CMD -P ${MTPROXY_TAG}"
fi

# --- NAT INFO ---
if [ -n "${MTPROXY_LOCAL_IP:-}" ] && [ -n "${MTPROXY_EXTERNAL_IP:-}" ]; then
  external_ip="$MTPROXY_EXTERNAL_IP"

  # если это не IP — резолвим
  if ! echo "$external_ip" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    resolved_ip=$(getent hosts "$external_ip" | awk '{print $1}' | head -n1 || true)
    if [ -z "$resolved_ip" ]; then
      echo "Error: failed to resolve domain $external_ip"
      exit 1
    fi
    external_ip="$resolved_ip"
  fi

  CMD="$CMD --nat-info ${MTPROXY_LOCAL_IP}:${external_ip}"
fi

# --- AES PASSWORD ---
if [ -n "${MTPROXY_PROXY_SECRET:-}" ]; then
  if [ ! -f "${MTPROXY_PROXY_SECRET}" ]; then
    echo "Error: file ${MTPROXY_PROXY_SECRET} not found"
    exit 1
  fi
  CMD="$CMD --aes-pwd ${MTPROXY_PROXY_SECRET}"
else
  CMD="$CMD --aes-pwd proxy-secret"
fi

echo "Starting mtproto-proxy..."
echo "Command: $CMD"

# --- daily restart ---
(
  sleep 86400
  echo "24h passed, stopping proxy..."
  kill $$ 2>/dev/null || true
) &

timer_pid=$!

# --- run proxy ---
sh -c "$CMD" &
child_pid=$!

wait "$child_pid" || true

kill "$timer_pid" 2>/dev/null || true
wait "$timer_pid" 2>/dev/null || true

echo "Proxy stopped"
