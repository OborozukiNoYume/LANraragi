# Build, Test and Deployment

> Baseline commit `2094cc1d` (2026-09-04). Facts verified against code — cite-checked at generation time.

## Prerequisites

- **Perl >= 5.36** and a C toolchain (many CPAN modules are compiled).
- **Node.js / npm** — used both for the build scripts below and for vendoring frontend libraries.
- A Redis-compatible server (the containers ship Valkey; local dev can use Redis or Valkey).

## Dependencies

### Perl (`tools/cpanfile`)

Key requirements as pinned in `tools/cpanfile`:

| Dependency | Version | Purpose |
|---|---|---|
| `perl` | 5.36.0 | language floor |
| `Mojolicious` | 9.39 | web framework |
| `Redis` | 1.995 | Redis client |
| `Minion` | >= 10.31, < 12.0 | job queue |
| `Minion::Backend::Redis` | 0.002 | Minion backend |
| `Mojolicious::Plugin::OpenAPI` | 5.11 | REST API (with `JSON::Validator` 5.19) |
| `Archive::Libarchive::Extract` / `Peek` | 0.03 / 0.04 | archive handling |
| `Archive::Zip` | 1.68 | zip handling |
| `Locale::Maketext` / `::Lexicon` | 1.33 / 1.00 | i18n (see the i18n doc) |
| `CHI` + `CHI::Driver::FastMmap` | 0.61 | cache |
| `FFI::Platypus` | 2.10 | libvips bindings |
| `Proc::Simple`, `Parallel::Loops`, `MCE::Loop`, `File::ChangeNotify` | — | Shinobu background worker |
| `Module::Pluggable` | 5.2 | plugin system |
| `Crypt::Passphrase` + `::Bcrypt` | 0.023 / 0.009 | password hashing |

Test-only deps include `Test::MockObject`, `Test::MockModule`, `Test::Trap`, `Test::Deep`, `App::Prove` and `Test::Harness`.

### npm (`package.json`)

`package.json` (version 0.9.81 "Atomica") holds frontend runtime libraries (jQuery, DataTables, Preact + signals, SweetAlert2, Swiper, marked, DOMPurify, es-module-shims, …) and dev tooling (`eslint`, `@redocly/cli`, `esbuild`, `@stylistic/eslint-plugin`).

### Key build files

| File | Role |
|---|---|
| `tools/cpanfile` | Perl dependency list |
| `package.json` / `package-lock.json` | npm scripts and frontend dependencies |
| `tools/install.pl` | dependency installer + frontend vendoring |
| `lrr.conf` | Redis connection/layout config |
| `tools/build/docker/Dockerfile` | release container (multi-stage, s6) |
| `tools/build/docker/Dockerfile-dev`, `docker-compose.yml` | containerized dev environment |
| `tools/openapi.yaml` + `redocly.yml` | REST API spec and its lint config |
| `tools/build/windows/` | MSYS2/WiX MSI pipeline and the `Karen` installer project |
| `tools/build/homebrew/Lanraragi.rb` | macOS Homebrew formula |
| `.github/workflows/`, `.github/actions/`, `.github/action-run-tests/` | CI/CD pipelines and composite/test actions |
| `.devcontainer/` | VS Code dev container |
| `tools/lanraragi-systemd.service` | example systemd unit |

## Common commands

All invoked as `npm run <script>`; definitions are in `package.json`:

| Script | What it does |
|---|---|
| `test` | `prove -r -l -v tests/` — full Perl test suite |
| `lanraragi-installer` | `perl ./tools/install.pl` — dependency installer (modes below) |
| `start` | `perl ./script/launcher.pl -f ./script/lanraragi` — production start |
| `dev-server` | `perl ./script/launcher.pl -m -v ./script/lanraragi` — dev start |
| `dev-server-verbose` | same with `LRR_DEVSERVER=1` exported |
| `kill-workers` | kills Shinobu/Minion workers and any stray `script/lanraragi` |
| `lint` | `eslint public/` |
| `lint-openapi` | `redocly lint tools/openapi.yaml --config=redocly.yml` |
| `critic` | `perlcritic ./lib/* ./script/* ./tools/install.pl` |
| `tidy` | runs `perltidy` over all `.pl`/`.pm` files |
| `docs` | `python3 docs/generate_docs.py` |
| `docker-build` | `docker build -t difegue/lanraragi -f ./tools/build/docker/Dockerfile .` |
| `backup-db` | `perl ./script/backup` |
| `get-version` | `perl ./script/get_version` |

`redocly.yml` extends the `recommended` ruleset and disables `operation-4xx-response`; `eslint.config.mjs` configures the JS lint.

Two further utility scripts exist outside npm: `script/get_version` prints the version pair from `package.json` (`0.9.81 - 'Atomica'` style), and `script/backup` dumps the database backup JSON via `LANraragi::Model::Backup` (both are wrapped by npm scripts above).

## Installing dependencies

`tools/install.pl` (reached via `npm run lanraragi-installer [mode]`) supports three modes:

- `install-front` — `npm ci` and vendor frontend assets from `node_modules` into `public/js/vendor/`, `public/css/vendor/` and `public/css/webfonts` (the file lists live in `tools/install.pl` itself, with `esbuild` bundling exactly one ESM package, swiper).
- `install-back` — install the Perl dependencies from `tools/cpanfile` via `cpanm`.
- `install-full` — both; this is the mode for source installs.

The Docker build path uses `tools/build/docker/install-perl-deps.sh`, which bootstraps `local::lib` + `cpanm`, pre-installs `Net::IDN::Encode` manually, then runs `cpanm --installdeps` against `tools/cpanfile` followed by `install-back`.

## Runtime configuration: `lrr.conf`

The file `lrr.conf` at the repo root is read by `lib/LANraragi/Model/Config.pm` and contains 8 keys:

| Key | Meaning |
|---|---|
| `redis_address` | Redis host:port (or UNIX socket path) |
| `redis_password` | optional auth |
| `redis_database` | archive data + tag indexes (default `0`) |
| `redis_database_minion` | Minion job queue (default `1`) |
| `redis_database_config` | config hash (default `2`) |
| `redis_database_search` | search index/cache (default `3`) |
| `redis_database_metrics` | metrics data (default `4`) |
| `base_url_path` | path-prefix deployment |

`lib/LANraragi/Model/Config.pm` also honors environment overrides at startup: `LRR_REDIS_ADDRESS` (replaces `redis_address`), `LRR_DATA_DIRECTORY` and `LRR_THUMB_DIRECTORY` (content/thumb paths), `LRR_FORCE_DEBUG`, `LRR_DEVSERVER` (debug mode) and `LRR_DISABLE_OPENAPI` (skips serving the OpenAPI spec).

## Server startup

`npm start` reaches `script/launcher.pl`, which picks the server: `-m` runs
`Mojo::Server::Morbo` (setting `MOJO_MODE=development`), `-d` runs `Mojo::Server::Daemon`, and
the default is `Mojo::Server::Prefork` — listening on `LRR_NETWORK` (default `http://*:3000`),
writing its PID file to `<LRR_TEMP_DIRECTORY>/server.pid` (`./temp/server.pid` otherwise), and
daemonizing unless `-f` is passed. The launcher creates the content/thumb/temp directories when
the corresponding env vars are set, then loads the app class directly (`script/lanraragi` itself
is just `Mojolicious::Commands->start_app('LANraragi')`).

`LANraragi::startup()` then runs, in order: loads or generates the session secret
(`temp/oshino` combined with the hostname), registers the `RenderFile`/`TemplateToolkit`
plugins (tt2 as default handler) and the `LRR_*` helpers, checks Redis with a `ping` (dying
with a flip-table message if unreachable) followed by an unbounded retry loop with 2-second
sleeps for transient `LOADING` errors, initializes PageCache and i18n, migrates legacy `LRR_*`
keys into the config DB, switches to development mode per `devmode`, redirects Mojo's own log
into the rotating `mojo` logger, runs `scan_plugins()` and refreshes every registry, clears the
restart-pending flag, wires the Minion client (`missing_after(5)`), registers the twelve tasks,
enqueues `build_stat_hashes`, and launches the Minion worker and Shinobu subprocesses.
`first_install_actions()` runs last, before the `before_dispatch` hooks (base-url prefix +
`lrr_baseurl` cookie, plus a lazily-installed SIGINT handler) and the optional metrics hooks are
installed; `apply_routes()` finishes startup. Shutdown handling is SIGINT-only — the handler is
installed on the first request, so a signal before any page load is not trapped — and kills the
Shinobu/Minion subprocesses via their PID files before invoking the default handler.

## Docker

`npm run docker-build` builds `tools/build/docker/Dockerfile` — a three-stage build (`base` → `build` → `runtime`) based on `FROM alpine:3.24`. Alpine packages include `valkey`/`valkey-cli` (the in-container datastore), `s6-overlay` (init + supervision), `vips` with jxl/heif/poppler addons (thumbnails), `perl`, `perl-io-socket-ssl`, `perl-local-lib` and `tzdata`. The `build` stage compiles the CPAN dependencies and vendors npm assets; only the results are copied into `runtime`.

**Process model** — the container runs two processes under s6:

- `redis`: `valkey-server /home/koyomi/lanraragi/tools/build/docker/redis.conf` (`tools/build/docker/s6/s6-rc.d/redis/run`)
- `lanraragi`: `perl script/launcher.pl -f script/lanraragi` (`tools/build/docker/s6/s6-rc.d/lanraragi/run`)

Both run as user `koyomi` via `s6-setuidgid`. `ENTRYPOINT ["//init"]` (the double slash is the Alpine s6-overlay package convention). On boot, `tools/build/docker/s6/cont-init.d/01-lrr-setup` rewrites the `koyomi` user to `LRR_UID`/`LRR_GID`, verifies the content folder exists, and applies permission fixes.

**Environment variables** (defaults from the Dockerfile):

| Variable | Default | Purpose |
|---|---|---|
| `LRR_UID` / `LRR_GID` | `9001` / `9001` | uid/gid mapped onto `koyomi` |
| `LRR_NETWORK` | `http://*:3000` | Mojo listen string |
| `LRR_AUTOFIX_PERMISSIONS` | `1` | run permission fixes at boot |
| `MOJO_PROXY` | `1` | HTTP proxy detection |
| `MOJO_REVERSE_PROXY` | `1` | trust `X-Forwarded-*` headers |
| `LC_ALL`/`LANG`/`LANGUAGE` | `en_US.UTF-8` | UTF-8 locale |
| `S6_KEEP_ENV` | `1` | keep env for services |
| `S6_BEHAVIOUR_IF_STAGE2_FAILS` | `1` | warn if stage2 scripts fail |

**Persistence** — 5 declared volumes: `/home/koyomi/lanraragi/content`, `.../thumb`, `.../database`, `.../lib/LANraragi/Plugin/Sideloaded`, `.../lib/LANraragi/Plugin/Managed`.

`EXPOSE 3000`, and a `HEALTHCHECK` (interval 1m, timeout 10s, 3 retries) that `wget`-spiders `http://127.0.0.1:3000`.

For development there is `tools/build/docker/Dockerfile-dev` plus `tools/build/docker/docker-compose.yml`, which mounts the repo at `/home/koyomi/lanraragi` and links a `valkey:9` service reached via `LRR_REDIS_ADDRESS=redis:6379`.

## CI workflows (`.github/workflows/`)

| File | Trigger | What it does |
|---|---|---|
| `push-continuous-integration.yml` | push, pull_request, manual dispatch | ESLint (Node 22); builds the Docker image and runs the test suite in it via `.github/action-run-tests`; Perl Critic; then Playwright/pytest integration tests from the external `aio-lanraragi` repo against a locally built image |
| `push-continous-delivery.yml` | push to `dev`, `test-builds`, `actions-testing` | multi-arch Docker build (arm/v6, arm/v7, arm64 via `ubuntu-24.04-arm`, plus amd64 and 386, merged into a single manifest) pushed as the `nightly` tag; also builds a nightly Windows MSI |
| `release-delivery.yml` | release published | Windows MSI build (below) plus Docker images tagged `latest` |
| `push-brewtest.yml` | push | on `macos-latest`, builds and tests the bundled Homebrew formula |

`.github/action-run-tests` is a small Docker action based on the just-built `lanraragi:test` image (re-adding `perl-dev`, `g++`, `make`, `imagemagick` for tests) whose entrypoint runs `prove -I /home/koyomi/perl5/lib/perl5 -r -l -v tests/`. The multi-arch delivery pipeline uses the composite actions in `.github/actions/docker-builder` and `.github/actions/docker-merge`.

## Test suite

Run locally with `npm test` (`prove -r -l -v tests/`). Layout under `tests/`:

- Top-level `.t` files: `backup.t`, `category.t`, `cbw.t`, `modules.t`, `opds.t`, `plugins.t`, `search.t`, `stamp.t`, `tankoubon.t`.
- `tests/LANraragi/Utils/` — 12 test files (`Archive.t`, `Generic.t`, `ImageMagickResizer.t`, `Logging.t`, `Metrics.t`, `Path.t`, `Registry.t`, `Routing.t`, `String.t`, `Tags.t`, `Vips.t`, `VipsResizer.t`).
- `tests/LANraragi/Model/Plugins.t` and `tests/LANraragi/Plugin/Metadata/` — 18 metadata-plugin tests (Chaika, Eze, EHentai, Hitomi, Koromo, …).
- `tests/mocks.pl` — `setup_redis_mock()` builds a `Test::MockObject` Redis mock around an in-memory data model, so the suite does not need a live Redis server. Tests `require` it before use (see `tests/search.t`, `tests/modules.t`).
- `tests/samples/` — fixtures consumed by the plugin tests (sample archives, `doc.pdf`, per-source JSON samples).

Running the suite locally only needs the Perl dependencies from `tools/cpanfile` installed (`install-back` or `install-full`) — the Redis mock means no live server is required. In CI the same `prove` command executes inside the `lanraragi:test` container built by the workflow, which is why the Dockerfile must stay test-friendly.

## Windows installer

Two workflows produce the MSI on `windows-2025` with the same pipeline: `release-delivery.yml` (on GitHub releases) and `push-continous-delivery.yml` (nightly). An MSYS2 UCRT64 environment runs `tools/build/windows/install-deps.sh`, `install.sh`, `cleanup.sh` and `create-dist.sh`, then `tools/build/windows/utf8-support.ps1`, and finally `tools/build/windows/build-installer.ps1` produces `tools/build/windows/Karen/Setup/bin/LANraragi.msi` (WiX; the workflows uninstall the chocolatey WiX first), uploaded as the `LANraragi.msi` artifact. The `Karen/` directory holds the installer project; `tools/build/windows/` also contains `redis.conf` and `run.ps1` for local Windows runs.

## Homebrew

`tools/build/homebrew/Lanraragi.rb` is the formula tested by `push-brewtest.yml`: the workflow splices the current commit hash over the `COMMIT_HASH` placeholder, installs the formula `--build-from-source` into a temporary tap, and runs `brew test`.

## Development environment

- **Devcontainers** — `.devcontainer/` provides a Dockerfile and `devcontainer.json` (user `koyomi`, forwarded port 3000, `postCreateCommand` runs `npm run lanraragi-installer install-front` and starts the `valkey-server` service).
- **Local dev** — `npm run dev-server` (add `-verbose` for `LRR_DEVSERVER` debug); stop stray workers with `npm run kill-workers`.
- **systemd** — `tools/lanraragi-systemd.service` is a community example unit running `npm start`; it assumes a host Redis and notes it may need adapting.
