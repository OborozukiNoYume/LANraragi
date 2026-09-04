# HTTP API

> Baseline commit `2094cc1d` (2026-09-04). Endpoint table extracted mechanically from `tools/openapi.yaml` (OpenAPI 3.1). Facts verified against code.

## Overview and routing

Nearly all `/api/*` traffic is handled by **Mojolicious::Plugin::OpenAPI** (the few exceptions are registered directly in `apply_routes()` and listed at the end of this document), which is loaded in `apply_routes()` in `lib/LANraragi/Utils/Routing.pm` with `tools/openapi.yaml` as its spec. The spec is versioned as OpenAPI 3.1.0 and declares a single server entry, `https://lrr.tvc-16.science/api`; the plugin derives the `/api` path prefix from that server URL, so every operation path listed in the reference table below is served under `/api` (e.g. `/archives` means `GET /api/archives`).

Each operation in the spec carries an `x-mojo-to` stub such as `api-search#handle_api`, which maps it to a controller method in `lib/LANraragi/Controller/Api/`. The plugin validates incoming requests (path/query/body parameters) against the spec before the controller runs; validation failures are turned into a 400 response by the `openapi.valid_input` override in `lib/LANraragi/Utils/OpenAPI.pm`, which also logs the errors server-side. The `disableopenapi` configuration flag (exposed in the Config UI) bypasses both request and response validation while keeping the routing intact.

Two cross-cutting options are wired around the API router in `apply_routes()`:

- **CORS** (`enablecors`, off by default): routes are mounted under `setup_cors()` in `lib/LANraragi/Controller/Login.pm`, which answers browser preflights with `Access-Control-Allow-Origin: *`, `Access-Control-Allow-Methods: GET, OPTIONS, POST, DELETE, PUT` and explicitly allows the `Authorization` header.
- **No-Fun Mode** (`nofunmode`, off by default): the entire OpenAPI router is mounted under `logged_in_api()` in `lib/LANraragi/Controller/Login.pm`, so *every* request — including endpoints whose spec entry is `security: []` — must be authenticated or it fails with 401 and a `{"error": "This API is protected and requires login or an API Key."}` body. Web UI routes are locked behind a session login at the same time.

## Authentication

The spec names one security scheme, `api_key`; its callback (defined in the plugin setup in `lib/LANraragi/Utils/Routing.pm`) delegates to `is_logged_in_api()` in `lib/LANraragi/Utils/Login.pm`. A request passes if any of the following holds:

1. An `Authorization: Bearer {base64(apikey)}` header, where the value is the base64 encoding of the raw API key configured in the server's Configuration page.
2. A `?key={apikey}` query parameter containing the raw key. The code comments call this "undocumented, mostly just meant for OPDS": readers that cannot send custom headers use it, and `lib/LANraragi/Model/Opds.pm` threads the value through the catalog's pagination links so navigation stays authenticated.
3. An existing logged-in browser session.
4. Password protection is disabled entirely (`enablepass` set to 0; it is on by default).

In the reference table, **Auth = "No"** means the operation is declared `security: []` in the spec and needs no credentials (unless No-Fun Mode is enabled, see above); operations whose Auth column reads **"API key"** go through the `api_key` scheme.

Two progression endpoints deserve a special mention. `PUT /api/archives/{id}/progress/{page}` and `PUT /api/tankoubons/{id}/progress/{page}` are declared `security: []`, but their handlers — `update_progress()` in `lib/LANraragi/Controller/Api/Archive.pm` and `update_tank_progress()` in `lib/LANraragi/Controller/Api/Tankoubon.pm` — call `is_logged_in_api()` themselves and answer 401 when the `authprogress` setting is enabled, so casual readers cannot forge another client's progress. The archive handler additionally refuses the update with 400 when server-side progress tracking is disabled (`localprogress` without `authprogress`) or when the archive has no recorded page count (bypassable with an undocumented `force` parameter).

## Response format and errors

Most mutating endpoints report their outcome through `render_api_response()` in `lib/LANraragi/Utils/Generic.pm`, which produces:

```json
{ "operation": "update_metadata", "success": 1, "error": "", "successMessage": "" }
```

Failures return HTTP 400 with `success: 0` and a message in `error`; successes return HTTP 200 and may carry a `successMessage`. On top of that convention, the OpenAPI layer itself can answer with 400 (request validation, body lists the offending parameters) or 401 (failed security check), and the No-Fun Mode / metrics chain answers with its own 401 JSON shown above.

## Search endpoints in detail

The four search operations live in `lib/LANraragi/Controller/Api/Search.pm`; the three queries (`GET /api/search`, `GET /api/search/ids`, `GET /api/search/random`) are backed by `do_search()` in `lib/LANraragi/Model/Search.pm`, while `DELETE /api/search/cache` just calls `invalidate_cache()`. `GET /api/search` and `GET /api/search/ids` accept the same parameters:

| Parameter | Default | Meaning |
|---|---|---|
| `filter` | — | Search query; syntax below |
| `category` | — | Category ID to restrict the search to. Static categories intersect their archive list; dynamic categories contribute their own search predicate as extra filter tokens |
| `start` | `0` | Offset into the result list, paginated by the server-side page size (`pagesize`, default 100). `-1` returns the full, unpaged result set |
| `sortby` | `title` | `title`, `lastread`, or **any tag namespace** (`artist`, `date_added`, …) |
| `order` | `asc` | Sort direction, `asc` or `desc` |
| `newonly` | `false` | Restrict to archives flagged new |
| `untaggedonly` | `false` | Restrict to untagged archives |
| `groupby_tanks` | `true` | When enabled, Tankoubons appear in results in place of the archives they contain (this also changes `recordsTotal`) |
| `hidecompleted` | `false` | Hide archives whose progress exceeds 85% of their page count |

Responses carry `{recordsTotal, recordsFiltered, data}`; for `/api/search` the `data` array holds full archive metadata JSON objects, for `/api/search/ids` only the archive IDs. If the search engine has not been initialized yet (no `LAST_JOB_TIME` marker in the search Redis database), both endpoints return **HTTP 204** instead of results.

Sorting notes, from `sort_results()` in `lib/LANraragi/Model/Search.pm`:

- Sorting by an arbitrary namespace partitions the results: archives that carry the namespace (naturally sorted by its value) come first, those without it are pushed to the back. For `date_added`/`timestamp`, Tankoubons inherit a date from their member archives.
- `lastread` requires server-side progress tracking and silently drops IDs that have never been read.

`GET /api/search/random` takes `filter`, `category`, `newonly`, `untaggedonly`, `groupby_tanks`, `hidecompleted` and a `count` (default 5); it draws random entries out of the full filtered set and returns full metadata objects. Every query is cached in the search Redis database (`LRR_SEARCHCACHE`, including reuse of inverted sort orders); `DELETE /api/search/cache` maps to `invalidate_cache()` in `lib/LANraragi/Utils/Database.pm` to drop it.

### Filter syntax

The `filter` string is parsed by `compute_search_filter()` in `lib/LANraragi/Model/Search.pm`; the cases below are exercised by `tests/search.t`.

- Terms are comma-separated and combined with AND logic.
- A bare keyword matches tags **and** titles fuzzily (substring match).
- `namespace:value` restricts the match to that tag namespace; without a namespace the term matches tags in any namespace.
- Double quotes (`"male:very cool"`) make the term an exact string match and allow spaces inside it.
- A leading `-` excludes the term that follows (`-character:ereshkigal`); it must sit *outside* quotes to work.
- A trailing `$` forces an exact tag match (`character:segata$`).
- `?` or `_` match any single character; `*` or `%` match any run of characters. Both pairs are interchangeable.
- `pages:` and `read:` compare against the page count and the pages-read counter respectively, accepting `=` (implicit), `>`, `>=`, `<`, `<=` — e.g. `pages:>150`, `read:<11, read:>9`.
- Terms are lowercased before matching.

## Endpoint reference

87 operations across 64 paths, grouped by spec tag. Paths are relative to the `/api` prefix; handlers are `x-mojo-to` values resolved against `lib/LANraragi/Controller/Api/`. Auth "API key" corresponds to the `api_key` security scheme, "No" to `security: []`.
**archives** (20 operations)

| Method | Path | Handler | Auth | Description |
|---|---|---|---|---|
| `GET` | `/archives` | `api-archive#serve_archivelist` | No | Get all Archives |
| `GET` | `/archives/untagged` | `api-archive#serve_untagged_archivelist` | No | Get all untagged archives |
| `PUT` | `/archives/upload` | `api-archive#create_archive` | API key | 🔑 Upload Archive |
| `DELETE` | `/archives/{id}` | `api-archive#delete_archive` | API key | 🔑 Delete archive |
| `GET` | `/archives/{id}` | `api-archive#serve_metadata` | No | Get archive metadata (deprecated) |
| `GET` | `/archives/{id}/categories` | `api-archive#get_categories` | No | Get archive categories |
| `GET` | `/archives/{id}/download` | `api-archive#serve_file` | No | Download archive |
| `GET` | `/archives/{id}/files` | `api-archive#get_file_list` | No | Extract an Archive |
| `POST` | `/archives/{id}/files/thumbnails` | `api-archive#generate_page_thumbnails` | No | Extract page thumbnails |
| `DELETE` | `/archives/{id}/isnew` | `api-archive#clear_new` | No | Clear Archive New flag |
| `PUT` | `/archives/{id}/isnew` | `api-archive#add_new` | API key | 🔑 Set Archive New flag |
| `GET` | `/archives/{id}/metadata` | `api-archive#serve_metadata` | No | Get archive metadata |
| `PUT` | `/archives/{id}/metadata` | `api-archive#update_metadata` | API key | 🔑 Update archive metadata |
| `GET` | `/archives/{id}/page` | `api-archive#serve_page` | No | Get an archive page |
| `PUT` | `/archives/{id}/progress/{page}` | `api-archive#update_progress` | No | Update reading progression |
| `GET` | `/archives/{id}/tankoubons` | `api-tankoubon#get_tankoubons_file` | No | Get archive tankoubons |
| `GET` | `/archives/{id}/thumbnail` | `api-archive#serve_thumbnail` | No | Get archive thumbnail |
| `PUT` | `/archives/{id}/thumbnail` | `api-archive#update_thumbnail` | API key | 🔑 Update archive thumbnail |
| `DELETE` | `/archives/{id}/toc` | `api-archive#remove_toc` | API key | 🔑 Remove entry from Archive Table of Contents |
| `PUT` | `/archives/{id}/toc` | `api-archive#add_toc` | API key | 🔑 Add entry to Archive Table of Contents |

**categories** (10 operations)

| Method | Path | Handler | Auth | Description |
|---|---|---|---|---|
| `GET` | `/categories` | `api-category#get_category_list` | No | Get all Categories |
| `PUT` | `/categories` | `api-category#create_category` | API key | 🔑 Create a Category |
| `DELETE` | `/categories/bookmark_link` | `api-category#remove_bookmark_link` | API key | 🔑 Disable bookmark feature |
| `GET` | `/categories/bookmark_link` | `api-category#get_bookmark_link` | No | Get bookmark-linked Category |
| `PUT` | `/categories/bookmark_link/{id}` | `api-category#update_bookmark_link` | API key | 🔑 Update bookmark-linked Category |
| `DELETE` | `/categories/{id}` | `api-category#delete_category` | API key | 🔑 Delete Category |
| `GET` | `/categories/{id}` | `api-category#get_category` | No | Get a single Category |
| `PUT` | `/categories/{id}` | `api-category#update_category` | API key | 🔑 Update Category |
| `DELETE` | `/categories/{id}/{archive}` | `api-category#remove_from_category` | API key | 🔑 Remove an Archive from a Category |
| `PUT` | `/categories/{id}/{archive}` | `api-category#add_to_category` | API key | 🔑 Add an Archive to a Category |

**database** (8 operations)

| Method | Path | Handler | Auth | Description |
|---|---|---|---|---|
| `GET` | `/database/backup` | `api-database#serve_backup` | API key | 🔑 Get a backup JSON |
| `POST` | `/database/backup` | `api-database#queue_backup` | API key | 🔑 Queue a backup job |
| `GET` | `/database/backup/{jobid}` | `api-database#download_backup` | API key | 🔑 Download backup JSON from completed job |
| `POST` | `/database/clean` | `api-database#clean_database` | API key | 🔑 Clean the Database |
| `POST` | `/database/drop` | `api-database#drop_database` | API key | 🔑 Drop the Database |
| `DELETE` | `/database/isnew` | `api-database#clear_new_all` | API key | 🔑 Clear All "New" flags |
| `POST` | `/database/restore` | `api-database#queue_restore` | API key | 🔑 Queue a restore job |
| `GET` | `/database/stats` | `api-database#serve_tag_stats` | No | Get Statistics |

**minion** (3 operations)

| Method | Path | Handler | Auth | Description |
|---|---|---|---|---|
| `GET` | `/minion/{jobid}` | `api-minion#minion_job_status` | No | Get the basic status of a Minion Job |
| `GET` | `/minion/{jobid}/detail` | `api-minion#minion_job_detail` | API key | 🔑 Get the full status of a Minion Job |
| `POST` | `/minion/{jobname}/queue` | `api-minion#queue_minion_job` | API key | 🔑 Queue a Minion job |

**misc** (4 operations)

| Method | Path | Handler | Auth | Description |
|---|---|---|---|---|
| `POST` | `/download_url` | `api-other#download_url` | API key | Queue a URL download |
| `GET` | `/info` | `api-other#serve_serverinfo` | No | Get server info |
| `POST` | `/regen_thumbs` | `api-other#regen_thumbnails` | API key | Regenerate Thumbnails |
| `DELETE` | `/tempfolder` | `api-other#clean_tempfolder` | API key | Clean the Temporary Folder |

**opds** (3 operations)

| Method | Path | Handler | Auth | Description |
|---|---|---|---|---|
| `GET` | `/opds` | `api-other#serve_opds_catalog` | No | Get the OPDS Catalog |
| `GET` | `/opds/{id}` | `api-other#serve_opds_item` | No | Get a specific archive through OPDS |
| `GET` | `/opds/{id}/pse` | `api-other#serve_opds_page` | No | OPDS-PSE |

**plugins** (5 operations)

| Method | Path | Handler | Auth | Description |
|---|---|---|---|---|
| `POST` | `/plugins/install` | `api-plugins#install_plugin` | API key | 🔑 Install a Plugin |
| `DELETE` | `/plugins/installed/{plugin_namespace}` | `api-plugins#uninstall_plugin` | API key | 🔑 Uninstall a Plugin |
| `POST` | `/plugins/queue` | `api-other#use_plugin_async` | API key | 🔑 Use a Plugin Asynchronously |
| `POST` | `/plugins/use` | `api-other#use_plugin_sync` | API key | 🔑 Use a Plugin |
| `GET` | `/plugins/{type}` | `api-other#list_plugins` | API key | 🔑 List available plugins |

**registries** (9 operations)

| Method | Path | Handler | Auth | Description |
|---|---|---|---|---|
| `GET` | `/registries` | `api-registry#list_registries` | API key | 🔑 List Registries |
| `POST` | `/registries` | `api-registry#create_registry` | API key | 🔑 Create a Registry |
| `DELETE` | `/registries/default_registry` | `api-registry#remove_default_registry` | API key | 🔑 Clear Default Repository |
| `GET` | `/registries/default_registry` | `api-registry#get_default_registry` | API key | Get Default Repository |
| `PUT` | `/registries/default_registry/{id}` | `api-registry#update_default_registry` | API key | 🔑 Set Default Repository |
| `DELETE` | `/registries/{id}` | `api-registry#delete_registry` | API key | 🔑 Delete a Registry |
| `GET` | `/registries/{id}` | `api-registry#get_registry` | API key | 🔑 Get a Registry |
| `PUT` | `/registries/{id}` | `api-registry#update_registry` | API key | 🔑 Update a Registry |
| `POST` | `/registries/{id}/refresh` | `api-registry#refresh_registry` | API key | 🔑 Refresh Registry Index |

**search** (4 operations)

| Method | Path | Handler | Auth | Description |
|---|---|---|---|---|
| `GET` | `/search` | `api-search#handle_api` | No | Search Archives |
| `DELETE` | `/search/cache` | `api-search#clear_cache` | API key | 🔑 Discard Search Cache |
| `GET` | `/search/ids` | `api-search#handle_api_ids` | No | Search Archive IDs |
| `GET` | `/search/random` | `api-search#get_random_archives` | No | Search random Archives |

**shinobu** (4 operations)

| Method | Path | Handler | Auth | Description |
|---|---|---|---|---|
| `GET` | `/shinobu` | `api-shinobu#shinobu_status` | API key | 🔑 Get Shinobu status |
| `POST` | `/shinobu/rescan` | `api-shinobu#reset_filemap` | API key | 🔑 Rescan filemap and restart Shinobu |
| `POST` | `/shinobu/restart` | `api-shinobu#restart_shinobu` | API key | 🔑 Restart Shinobu |
| `POST` | `/shinobu/stop` | `api-shinobu#stop_shinobu` | API key | 🔑 Stop Shinobu |

**stamps** (6 operations)

| Method | Path | Handler | Auth | Description |
|---|---|---|---|---|
| `GET` | `/archives/{id}/stamps` | `api-stamp#get_stamped_pages` | No | Get pages that contain at least one stamp in the archive |
| `GET` | `/archives/{id}/stamps/{index}` | `api-stamp#get_stamps_by_page` | No | Get the stamps linked to the page |
| `PUT` | `/archives/{id}/stamps/{index}` | `api-stamp#add_stamp` | API key | 🔑 Add a stamp annotation |
| `DELETE` | `/stamps/{id}` | `api-stamp#delete_stamp` | API key | 🔑 Delete Stamp |
| `GET` | `/stamps/{id}` | `api-stamp#get_stamp` | No | Get Stamp |
| `PUT` | `/stamps/{id}` | `api-stamp#update_stamp` | API key | 🔑 Update Stamp |

**tankoubons** (11 operations)

| Method | Path | Handler | Auth | Description |
|---|---|---|---|---|
| `GET` | `/tankoubons` | `api-tankoubon#get_tankoubon_list` | No | Get all Tankoubons |
| `PUT` | `/tankoubons` | `api-tankoubon#create_tankoubon` | API key | 🔑 Create a Tankoubon |
| `DELETE` | `/tankoubons/{id}` | `api-tankoubon#delete_tankoubon` | API key | 🔑 Delete Tankoubon |
| `GET` | `/tankoubons/{id}` | `api-tankoubon#get_tankoubon` | No | Get a single Tankoubon |
| `PUT` | `/tankoubons/{id}` | `api-tankoubon#update_tankoubon` | API key | 🔑 Update Tankoubon metadata/contents |
| `GET` | `/tankoubons/{id}/full` | `api-tankoubon#get_tankoubon_full` | No | Get a single Tankoubon with full detail |
| `PUT` | `/tankoubons/{id}/progress/{page}` | `api-tankoubon#update_tank_progress` | No | Update Tankoubon reading progression |
| `GET` | `/tankoubons/{id}/thumbnail` | `api-tankoubon#serve_tankoubon_thumbnail` | No | Get Tankoubon thumbnail |
| `PUT` | `/tankoubons/{id}/thumbnail` | `api-tankoubon#update_tankoubon_thumbnail` | API key | 🔑 Update Tankoubon thumbnail |
| `DELETE` | `/tankoubons/{id}/{archive}` | `api-tankoubon#remove_from_tankoubon` | API key | 🔑 Remove an Archive from a Tankoubon |
| `PUT` | `/tankoubons/{id}/{archive}` | `api-tankoubon#add_to_tankoubon` | API key | 🔑 Add an Archive to a Tankoubon |

## The misc endpoints in detail

`GET /api/info` is the odd one out among the OpenAPI operations: its handler
(`serve_serverinfo()` in `lib/LANraragi/Controller/Api/Other.pm`) skips `openapi->valid_input`
and renders plain JSON. It forwards server state in one shot — `name` and `motd` (the
`htmltitle`/`motd` config fields, XML-escaped), `version`/`version_name`/`version_desc` (from
`package.json` via the `LRR_VERSION`/`LRR_VERNAME`/`LRR_DESC` helpers), the booleans `has_password`, `debug_mode`,
`nofun_mode`, `server_resizes_images`, `authenticated_progress`, `server_tracks_progress` (the
inverse of the `localprogress` setting) and `restart_required` (from `LRR_SERVER`), plus
`archives_per_page` (`pagesize`), `total_pages_read` (`LRR_TOTALPAGESTAT`), `total_archives`
(`scard LRR_TANKGROUPED`), `cache_last_cleared` (the `created` field of `LRR_SEARCHCACHE`) and
`excluded_namespaces`. The frontend's `index.js` is its only consumer: it drives the GitHub
release version check, reader progress-tracking setup and the page size.

The remaining misc endpoints have a few non-obvious edges:

- `POST /api/download_url` always answers `success: 1` with a job id when a URL is present —
  duplicate rejection happens inside the Minion task, which checks `is_url_recorded()` against
  `LRR_URLMAP` and finishes with `success: 0, message: "URL already downloaded!"`, visible only
  through job polling.
- `DELETE /api/tempfolder` does not delete arbitrary temp files: it clears the PageCache
  (`PageCache::clear()`), and its `newsize` response field is hardcoded to `0` even though the
  spec describes it as the post-cleanup folder size.
- `POST /api/plugins/use` and `/api/plugins/queue` have no lock/423 path. On `/plugins/use`,
  plugin errors come back as HTTP 200 with `success: 0`; on `/plugins/queue` the HTTP answer is
  always `success: 1` with a job id, and errors are visible only by polling the job.
  `use_plugin()` in `lib/LANraragi/Utils/Plugins.pm` only
  dispatches `script` and `metadata` types — anything else yields an empty `data` object.
- `GET /api/plugins/{type}` accepts `all` alongside the four types and returns each plugin's
  `plugin_info` augmented with `parameters` (as a name-bearing array), `registry`, `sha256`
  and `origin` — but no `enabled` flag.

## Routes outside the OpenAPI spec

Three HTTP routes relevant to API consumers are registered directly in `apply_routes()` in `lib/LANraragi/Utils/Routing.pm` and therefore do not appear in `tools/openapi.yaml` or the table above:

- **`GET /api/info/metrics`** — routed to `serve_metrics()` in `lib/LANraragi/Controller/Api/Metrics.pm`, which renders Prometheus exposition format (`text/plain; version=0.0.4; charset=utf-8`) built by `get_prometheus_metrics()` in `lib/LANraragi/Model/Metrics.pm`. The route is only registered when the `enablemetrics` setting is on (off by default), and it is mounted under `logged_in_api()`, so it always requires authentication regardless of that setting.
- **`WebSocket /batch/socket`** — the Batch Tagging websocket, handled by `socket()` in `lib/LANraragi/Controller/Batch.pm`. It is mounted under the session-based web login (`logged_in()` in `lib/LANraragi/Controller/Login.pm`), so it is authenticated by browser session or a disabled password — not by the API key — and keeps an 80-second inactivity timeout. The protocol is one command per message, each covering a single archive: the client sends `{operation, plugin, category, args, archive}` and the server answers with a per-archive JSON reply. Five operations are dispatched: `plugin` (runs a metadata plugin through `batch_plugin()` → `exec_metadata_plugin()`, *appending* the returned tags via `set_tags(..., 1)` plus optional title/summary, honoring per-message `args` overrides), `clearnew` (resets `isnew`), `tagrules` (rewrites the archive's tags through the computed tag rules, then invalidates the search cache), `addcat` (adds the archive to the `category`), and `delete` (runs `delete_archive()` under the `archive-write:$id` lock). An unknown operation gets a `success: 0` reply and the socket stays open; a message without an `archive` id or naming a missing plugin closes the socket with code 1001. A plugin error only fails its own archive — the batch continues. There is no server-side throttling: the pacing between archives is entirely client-side (`batch.js` sleeps for the `#timeout` input, prefilled from each plugin's `cooldown`, capped at 20 s by the UI), and when the queue is drained the client closes the socket (code 1000) and then calls `DELETE /api/search/cache`.
- **`GET /search`** — the DataTables endpoint backing the main archive table, handled by `handle_datatables()` in `lib/LANraragi/Controller/Api/Search.pm`. It speaks the DataTables server-side protocol (`draw`, `start`, `length`, `search[value]`, `order[0][column]`, `order[0][dir]`, `columns[i][name]`, `columns[i][search][value]`) plus two saner custom parameters, `grouptanks` (default `true`) and `hidecompleted` (default `false`). A `tags` column search value is normally a category ID, with the magic values `NEW_ONLY` and `UNTAGGED_ONLY` toggling the respective filters. The route shares the CORS and No-Fun Mode wrappers with the OpenAPI router but is otherwise unauthenticated.

## OPDS

The OPDS feed is exposed through regular OpenAPI operations (`GET /api/opds`, `GET /api/opds/{id}`, `GET /api/opds/{id}/pse` — see the *opds* tag above). It serves XML generated by `lib/LANraragi/Model/Opds.pm` and is the main consumer of the `?key=` authentication fallback described earlier, since OPDS readers typically cannot send custom headers. The OPDS flavor is covered in detail in the *Reader & OPDS* section of [06_models.md](06_models.md).

## Keeping the spec healthy

`tools/openapi.yaml` is the machine-readable contract for everything above. It is linted with `npm run lint-openapi`, which runs `redocly lint tools/openapi.yaml --config=redocly.yml` (see `package.json`); the `redocly.yml` config extends Redocly's `recommended` ruleset with the `operation-4xx-response` rule disabled. Being a standard OpenAPI 3.1 document, the spec can also be fed to any OpenAPI-aware tooling to generate clients or interactive documentation.
