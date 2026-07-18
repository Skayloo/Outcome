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

## Why Outcome

- **Real-time everything** — messaging over WebSocket with replies, reactions, pins,
  typing indicators, read markers, full-text search, drag-and-drop uploads.
- **Voice & video channels** — group voice, cameras, screen sharing (LiveKit SFU), with
  **end-to-end encrypted media frames**: the server only forwards opaque packets.
- **Guest voice links** — invite someone into a voice channel with a link, no account needed.
- **E2EE direct messages** — NaCl box (Curve25519); the server stores only ciphertext, with
  an encrypted key backup so history survives a new device.
- **1-on-1 calls** — ring a friend, phone-style incoming-call screen; offline calls are
  parked and delivered when they open the app.
- **A real native mobile app** for iOS and Android — not a webview wrapper: voice channels,
  E2EE calls and DMs, push-to-talk, the full feature set in your pocket. Store releases are
  rolling out; it connects to any self-hosted instance by hostname.
- **Multi-instance web client** — the login screen has a server picker (like a Matrix
  homeserver field): one web app can sign into any Outcome instance.
- **Roles & permissions, invites, moderation** — Discord-semantics permission bits with
  per-channel overrides, invite-only registration if you want it.
- **Web admin console** — users, roles, audit log, live server logs, metrics, bug reports.
- **Sign-in hardening** — TOTP/email 2FA, Argon2id password hashing, session management
  with one-click "revoke all", optional Google/Yandex SSO.
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
| [MinIO](https://hub.docker.com/r/minio/minio) | File storage (uploads encrypted at rest, AES-256-GCM) |
| [LiveKit](https://hub.docker.com/r/livekit/livekit-server) | Voice/video SFU (WebRTC) |
| [docker-mailserver](https://github.com/docker-mailserver/docker-mailserver) | *Optional:* your own mailboxes + app mail |

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
  | 25, 465, 587, 993 tcp | Only if you enable the bundled mail server |

## DNS

Point these records at your server's IP **before** starting (Caddy needs them resolvable
to obtain certificates):

| Record | Value |
|---|---|
| `A` `@` (or your subdomain) | your server IP |
| `A` `www` | your server IP |

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
hands you an unlimited invite code for your friends. Registration is invite-based:
share invite links from the app; manage everything else in the admin console.

The mobile app connects to your instance too — enter your domain in the **"Change
server"** field on its login screen.

## Voice & video

- `LIVEKIT_NODE_IP` in `.env` **must** be the server's public IP — it's advertised to
  browsers for the media connection (media bypasses the HTTP proxy entirely).
- UDP `7882` open = good calls. If UDP is blocked, media falls back to TCP `7881`.
- Voice/video frames are **end-to-end encrypted** between participants; the SFU only
  forwards opaque packets. Guest links (join a voice channel without an account) are
  supported out of the box.

## Mail (optional)

Without mail, sign-up confirmation codes are printed to the server log
(`docker compose logs server | grep -i code`) — fine for trying things out.

For real deployments, either point `EMAIL_*` in `.env` at any external SMTP provider, or
run the bundled full mail server (Postfix + Dovecot + rspamd + DKIM — your own mailboxes
on your own domain):

1. Add DNS records:

   | Record | Value |
   |---|---|
   | `A` `mail` | your server IP |
   | `MX` `@` | `mail.<your-domain>` (priority 10) |
   | `TXT` `@` | `v=spf1 mx -all` |
   | `TXT` `_dmarc` | `v=DMARC1; p=quarantine; rua=mailto:admin@<your-domain>` |

2. Start it (first boot may restart a few times while Caddy obtains the mail host's
   certificate — that's normal):

   ```bash
   docker compose --profile mail up -d
   ```

3. Create the app's sending account and your mailbox:

   ```bash
   docker compose exec mailserver setup email add no-reply@<your-domain>
   docker compose exec mailserver setup email add you@<your-domain>
   ```

4. Generate DKIM keys and publish the printed TXT record:

   ```bash
   docker compose exec mailserver setup config dkim keysize 2048
   cat mail-config/opendkim/keys/<your-domain>/mail.txt   # → publish as DNS TXT
   docker compose restart mailserver
   ```

5. Point the app at it in `.env` (`EMAIL_HOST=mail.<your-domain>`, port 587,
   `EMAIL_USE_SSL=false`, the no-reply account credentials), then
   `docker compose up -d server`.

6. **Ask your hoster to set the PTR (reverse DNS) record** of your IP to
   `mail.<your-domain>` — without it most providers will spam-folder or refuse your mail.
   Check yourself at [mail-tester.com](https://www.mail-tester.com).

Read your mailbox with any IMAP app: host `mail.<your-domain>`, port 993 (SSL),
SMTP 465/587.

## Updating

```bash
docker compose pull
docker compose up -d
```

Database migrations run automatically on API start. Pin `OUTCOME_TAG` in `.env` if you
prefer explicit version bumps over `latest`.

## Backups

All state lives in named Docker volumes: `pgdata` (database), `minio_data` (uploaded
files), `maildata`/`mailstate` (mail, if enabled), `caddy_data` (certificates).

Consistent database dump without stopping anything:

```bash
docker compose exec postgres pg_dump -U outcome -Fc outcome > outcome-$(date +%F).dump
```

Also back up your `.env` — `MINIO_ENC_KEY` in particular: uploaded files are encrypted
at rest with it and are unreadable without it.

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
