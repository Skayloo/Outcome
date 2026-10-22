# Outcome

*Living chat — your server, your rules.*

**🇷🇺 [Читать по-русски → README.ru.md](README.ru.md)**

> **Early Alpha.** Outcome is under active development and not yet production-hardened.
> Don't use it for sensitive communications yet. Issue reports are very welcome — file them here.

**Outcome** is a self-hosted, Discord-style chat platform that runs entirely on **your**
hardware — no cloud dependency, **no telemetry**, no paid tiers. This repository is the
**deployment kit**: one compose file + prebuilt Docker images. You don't build anything
from source, and a working instance is one `docker compose up -d` away.

<p align="center">
  <img src="docs/images/app.png" alt="Outcome — main chat" width="900">
</p>
<p align="center">
  <img src="docs/images/login.png" alt="Outcome — login" width="445">
  <img src="docs/images/admin.png" alt="Outcome — admin console" width="445">
</p>
<p align="center">
  <img src="docs/images/mobile-login.png" alt="Outcome for iOS — sign in" width="215">
  <img src="docs/images/mobile-chat.png" alt="Outcome for iOS — a channel" width="215">
  <img src="docs/images/mobile-drawer.png" alt="Outcome for iOS — direct messages" width="215">
  <img src="docs/images/mobile-settings.png" alt="Outcome for iOS — settings" width="215">
</p>

## Why Outcome

- **Real-time everything** — messaging over WebSocket with replies, reactions, pins,
  typing indicators, read markers, full-text search, drag-and-drop uploads.
- **Voice messages** — record in a channel or DM; normalized server-side to m4a so every
  platform plays them, with a seekable waveform (web + mobile).
- **Voice & video channels** — group voice, cameras, screen sharing (LiveKit SFU).
  Media is encrypted in transit (DTLS-SRTP) between each participant and the SFU.
- **Guest voice links** — invite someone into a voice channel with a link, no account needed.
- **Direct messages, friends, blocking** — one-to-one conversations with the same feature
  set as channels.
- **1-on-1 calls** — ring a friend, phone-style incoming-call screen; offline calls are
  parked and delivered when they open the app.
- **A real native mobile app** for iOS and Android — not a webview wrapper: voice channels,
  calls and DMs, push-to-talk, the full feature set in your pocket. Store releases are
  rolling out; it connects to any self-hosted instance by hostname.
- **Multi-instance web client** — the login screen has a server picker (like a Matrix
  homeserver field): one web app can sign into any Outcome instance.
- **Roles, invites, moderation** — owner, admins and moderators in every server, the
  instance's own administrators above them; open or invite-only registration.
- **Web admin console** — users, roles, audit log, live server logs, metrics, bug reports.
- **Sign-in hardening** — TOTP two-factor authentication, Argon2id password hashing,
  session management with one-click "revoke all".
- **Scales down and up** — idles under 2 GB RAM; the API is stateless and replicated
  behind PgBouncer + Redis when you need more.

Everything around the two Outcome images is stock open source pulled from public registries:

| Component | Role |
|---|---|
| [`skayloo/outcome-server`](https://hub.docker.com/r/skayloo/outcome-server) | **Outcome API** (.NET) — REST, WebSocket realtime, voice signaling |
| [`skayloo/outcome-frontend`](https://hub.docker.com/r/skayloo/outcome-frontend) | **Outcome web app** (React) behind nginx |
| [caddy-docker-proxy](https://github.com/lucaslorentz/caddy-docker-proxy) | Edge TLS, auto Let's Encrypt |
| [PostgreSQL 16](https://hub.docker.com/_/postgres) + [PgBouncer](https://hub.docker.com/r/edoburu/pgbouncer) | Database + connection pooling |
| [Redis](https://hub.docker.com/_/redis) | Realtime fan-out across API replicas |
| [MinIO](https://quay.io/repository/minio/minio) | File storage for uploads |
| [LiveKit](https://hub.docker.com/r/livekit/livekit-server) | Voice/video SFU (WebRTC) |

## Requirements

- A Linux host (x86_64) with a **public IP**. 2 vCPU / 4 GB RAM is a comfortable start.
- **Docker Engine** 24+ with the compose plugin (`docker compose version` should work).
- A **domain** you control.
- Open (or forwarded, if behind NAT) ports:

  | Port | Why |
  |---|---|
  | 80, 443 tcp (+ 443 udp) | Web, API, WebSocket, HTTP/3 |
  | 7881 tcp | Voice/video media — TCP fallback |
  | 7882 udp | Voice/video media — main path |
  | 5349 tcp | TURN relay over TLS, for networks that block the two above (`TURN_TLS_PORT`) |

## DNS

Point these records at your server's IP **before** starting (Caddy needs them resolvable
to obtain certificates):

| Record | Value |
|---|---|
| `A` `@` (or your subdomain) | your server IP |
| `A` `www` | your server IP |
| `A` `turn` | your server IP (the TURN relay's certificate) |

## Quick start

```bash
git clone https://github.com/Skayloo/Outcome.git
cd Outcome
cp .env.example .env
nano .env          # fill everything — the file explains each value and how to generate secrets
docker compose up -d
```

First boot takes a minute or two: Postgres initializes, migrations run (safe with multiple
API replicas — they serialize behind an advisory lock), Caddy obtains certificates.

Then open `https://your-domain` — the **first-run wizard** creates the owner account and
hands you an unlimited invite code for your friends. Registration is open by default; an
invite code puts the new account straight into your server. Make registration invite-only,
or close it, in the admin console (`/admin` → Server settings).

**Forgotten passwords.** The server sends no e-mail, so there is no "reset by e-mail" link:
an administrator sets a new password in `/admin` → Users → the person's menu → "Set
password". It signs the person out everywhere; give them the new password yourself.

The mobile app connects to your instance too — enter your domain in the **"Change
server"** field on its login screen.

## Voice & video

- `LIVEKIT_NODE_IP` in `.env` **must** be the server's public IP — it's advertised to
  browsers for the media connection (media bypasses the HTTP proxy entirely).
- UDP `7882` open = good calls. If UDP is blocked, media falls back to TCP `7881`.
- Voice/video is encrypted in transit (DTLS-SRTP) between each participant and the SFU,
  which decrypts to route it. Guest links (join a voice channel without an account) are
  supported out of the box.

## Already running a web server on 80/443?

The bundled Caddy wants ports 80 and 443 for itself. If another reverse proxy already holds
them, switch Caddy off and publish the web app on a local port instead — create
`docker-compose.override.yml` next to `docker-compose.yml`:

```yaml
services:
  caddy:
    profiles: ["off"]          # not started
  frontend:
    ports:
      - "127.0.0.1:8080:80"
```

Then point your proxy at `http://127.0.0.1:8080` for `your-domain`, with WebSocket
upgrades allowed and request bodies up to 110 MB. For example, Caddy:

```
your-domain {
    request_body { max_size 110MB }
    reverse_proxy 127.0.0.1:8080
}
```

or nginx (inside your `server { … }` for the domain, with its certificate):

```nginx
client_max_body_size 110m;
location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 3600s;
}
```

If the proxy itself runs in Docker, publish no port: put the web app on the proxy's network
and point the proxy at `http://outcome-web:80` instead —

```yaml
services:
  caddy:
    profiles: ["off"]
  frontend:
    networks:
      default: {}
      proxy:
        aliases: ["outcome-web"]
networks:
  proxy:
    external: true
    name: your-proxys-network      # docker network ls
```

(caddy-docker-proxy needs nothing more: the web app already carries the labels it reads.)

Voice still goes straight to LiveKit on 7881/7882, not through the proxy. The TURN relay
on 5349 starts only once the bundled Caddy has a certificate for `turn.your-domain`, so
with Caddy off it stays off and calls use 7881/7882 alone.

## Updating

```bash
docker compose pull
docker compose up -d
```

Database migrations run automatically on API start. Pin `OUTCOME_TAG` in `.env` if you
prefer explicit version bumps over `latest`.

## Backups

All state lives in named Docker volumes: `pgdata` (database), `minio_data` (uploaded
files), `caddy_data` (certificates).

Consistent database dump without stopping anything:

```bash
docker compose exec postgres pg_dump -U outcome -Fc outcome > outcome-$(date +%F).dump
```

Also back up your `.env`.

## Scaling

The API is stateless and already runs replicated (`SERVER_REPLICAS`) behind the built-in
routing, with PgBouncer multiplexing database connections and Redis fanning out realtime
events — raising the replica count on a bigger box is usually all you need.

## Acknowledgements

Outcome stands on excellent open source. Besides the stack components listed above,
special thanks to
[**pabloFuente/livekit-server-sdk-dotnet**](https://github.com/pabloFuente/livekit-server-sdk-dotnet) —
the .NET server SDK for LiveKit that powers Outcome's voice tokens, room management and
webhooks.

## License

The contents of this repository (compose file, configuration, documentation) are
MIT-licensed — see [LICENSE](LICENSE).

The `outcome-server` and `outcome-frontend` Docker images contain proprietary software:
**free to pull and self-host for any personal or commercial use**, but decompiling,
modifying or redistributing the images or their contents is not permitted. The source
code is not public.
