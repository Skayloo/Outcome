#!/bin/sh
# Start livekit-server, enabling its TURN/TLS relay only if the certificate is actually there.
#
# Why this exists rather than putting `turn:` straight in the config: livekit-server EXITS —
# "TURN tls cert required" — when turn.enabled is set and the file is missing. That is the
# normal state of a first boot, before Caddy has finished issuing, and of any boot where DNS
# for the turn host has not been pointed yet. Refusing to start would take voice down
# completely in order to add a fallback path to it, which is the wrong way round.
#
# So: certificate present → TURN on. Absent → a line in the log and voice as before.
set -e

: "${OUTCOME_DOMAIN:?OUTCOME_DOMAIN is required}"
HOST="turn.$OUTCOME_DOMAIN"
# 5349 is the registered TURNS port, which is exactly why it is worth being able to move:
# consumer routers with a SIP helper intercept 3478/5349 for their own VoIP stack and never
# forward them, silently. LiveKit both listens on this and advertises it to clients, so the
# external and internal port have to be the same number.
PORT="${TURN_TLS_PORT:-5349}"

# Caddy keeps certificates at <data>/caddy/certificates/<issuer>/<host>/<host>.crt. The issuer
# directory is named after the ACME endpoint and changes between staging and production (and
# has been renamed across Caddy versions), so glob it instead of hardcoding one.
CRT=$(ls "/caddy/caddy/certificates/"*"/$HOST/$HOST.crt" 2>/dev/null | head -1)
KEY=$(ls "/caddy/caddy/certificates/"*"/$HOST/$HOST.key" 2>/dev/null | head -1)

printf '%s\n' "$LIVEKIT_CONFIG" > /tmp/livekit.yaml

if [ -n "$CRT" ] && [ -n "$KEY" ]; then
  cat >> /tmp/livekit.yaml <<EOF

turn:
  enabled: true
  domain: $HOST
  tls_port: $PORT
  cert_file: $CRT
  key_file: $KEY
EOF
  echo "livekit: TURN over TLS enabled for $HOST:$PORT"
else
  echo "livekit: no certificate for $HOST yet — starting WITHOUT TURN."
  echo "livekit: point $HOST at this server in DNS; Caddy issues on the next request,"
  echo "livekit: and TURN comes up when this container is next restarted."
fi

exec /livekit-server --config /tmp/livekit.yaml "$@"
