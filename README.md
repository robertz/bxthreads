# bxThreads

A public [BoxLang](https://boxlang.io/) port of DismalThreads — a Reddit-style forum app — built on [boxlang-express](https://boxlang.io) instead of ColdBox, with no cbwire. Plain server-rendered HTML, fetch()-driven actions, and a STOMP-based realtime layer for comments, votes, and notifications.

## Requirements

- [BoxLang](https://boxlang.io/) + [CommandBox](https://www.ortussolutions.com/products/commandbox)
- MySQL (the `dismal` datasource)

## Setup

The fastest path — installs dependencies, prompts for every `.env` value, and creates the database + an `admin`/`admin` login if it doesn't exist yet:

```bash
boxlang setup.bxs
```

(or `box run-script setup`). Re-running it is safe — it reuses whatever's already in `.env` as the new defaults and never touches a database that already exists. See [`setup.bxs`](setup.bxs) for exactly what it does, or do it by hand:

```bash
box install
```

Copy the env template and fill in real values:

```bash
cp .env.example .env
```

Apply the schema to a fresh MySQL server (see [`db/README.md`](db/README.md)):

```bash
mysql -u root -p < db/schema.sql
```

| Variable | Purpose |
| --- | --- |
| `APP_PORT` | HTTP port (default `3000`) |
| `APP_ENV` | `development` enables `reloadOnChange` and verbose error responses |
| `SITE_URL`, `SITE_NAME` | Canonical URL / brand name used in OG tags, sitemap |
| `API_KEY` | Required `X-Api-Key` header for `/api/*` admin routes — generate with `uuidgen` |
| `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USER`, `DB_PASSWORD` | MySQL connection for the `dismal` datasource |

## Running

```bash
boxlang --bx-config ./boxlang.json app.bxs
```

Serves on `http://localhost:$APP_PORT`.

## Testing

```bash
box run-script test
```

Runs the TestBox suite (`tests/specs/unit`, `tests/specs/integration`) via `tests/runner.bxs`.

## Scripts

```bash
box run-script backfill-achievements
```

Runs `scripts/backfill-achievements.bxs`.

## Project layout

| Path | Contents |
| --- | --- |
| `app.bxs` | Entry point — DI registry, middleware, routers, WebSocket mount |
| `setup.bxs` | First-run setup — installs dependencies, writes `.env`, creates the database + admin login |
| `db/` | `schema.sql` — MySQL DDL for the `dismal` datasource, plus achievement catalog seed data |
| `lib/` | Framework-ish infrastructure: config, DI container (`AppContext`), sessions, view rendering, SQL helper, request context |
| `models/beans` | Plain data beans (`Post`, `Comment`, `User`, `Forum`, `Vote`, ...) |
| `models/dao` | `DismalDAO` — raw data access |
| `models/services` | Business logic (users, activity, achievements, sitemap, spider detection, ...) |
| `routes/` | `AppRouter` (page routes), `ActionsRouter` (session-authenticated mutations), `ApiRouter` (X-Api-Key admin REST API) |
| `views/` | `.bxm` templates, composed through `lib/View.bx` (no built-in layout support in boxlang-express) |
| `ws/` | STOMP broker (`Stomp.bx`), broadcast (`Broadcast.bx`), and forum presence (`Presence.bx`) |
| `public/` | Static assets, mounted at root to match the source app's webroot paths |
| `tests/` | TestBox specs |
| `scripts/` | One-off/maintenance BoxLang scripts |

## Architecture notes

- **DI**: `lib/AppContext.bx` is a simple registry — services/DAOs/beans are registered once in `app.bxs` and scanned from `models/beans`, `models/dao`, `models/services`.
- **Sessions**: cookie name `dt_sid`, 30-day maxAge, backed by boxlang-express's in-memory session middleware. The same store instance is shared with the WebSocket layer since `app.ws()` routes sit outside the HTTP middleware chain.
- **Realtime**: one shared STOMP broker (`ws/Stomp.bx`) drives comment/vote/notification broadcasts and forum presence over `/stomp`.
- **Two auth models**: page + action routes (`AppRouter`, `ActionsRouter`) use the session cookie; `/api/*` (`ApiRouter`) requires the `X-Api-Key` header instead.
- **Error handling**: full error messages only in `APP_ENV=development`; production returns a generic 500.

## Status

This is a phased port — see the top-of-file comment in [`app.bxs`](app.bxs) for what's landed vs. still in progress.
