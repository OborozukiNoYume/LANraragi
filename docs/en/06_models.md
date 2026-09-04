# 06 - Model Layer

> Baseline commit `2094cc1d` (2026-09-04). Facts verified against code — cite-checked at generation time.

The Model layer (`lib/LANraragi/Model/`) holds LANraragi's business logic between the Controllers and Redis.
Every module reaches Redis through `LANraragi::Model::Config`'s connection factories, and most long-running work
(thumbnail generation, plugin runs, backups) is delegated to Minion jobs — the tasks themselves are defined in
`lib/LANraragi/Utils/Minion.pm` and covered in the Utilities chapter; this chapter only references them.

All 16 modules in `lib/LANraragi/Model/`:

| Module | One-line role |
|---|---|
| `Config.pm` | Configuration access: Redis connection factories, `LRR_CONFIG` reads with defaults. |
| `Search.pm` | The search engine: token parsing, filtering, sorting, result caching. |
| `Archive.pm` | Archive lifecycle: page/thumbnail serving, metadata, ToC, deletion. |
| `Upload.pm` | Ingesting uploaded/downloaded files into the library. |
| `Backup.pm` | JSON export/import of all user metadata. |
| `Category.pm` | Categories (`SET_` keys), including the bookmark link. |
| `Tankoubon.pm` | Tankoubon collections (`TANK_` keys, one Redis Sorted Set each). |
| `Reader.pm` | Server-side reader support: page list JSON, quality-based resizing. |
| `Plugins.pm` | Plugin discovery, execution, install/uninstall from registries. |
| `Registry.pm` | Plugin registries (GitHub/Gitea/CDN/local sources). |
| `Stats.pm` | Search-index and tag-statistic construction. |
| `Stamp.pm` | Page stamps/bookmarks (`STAMPS_*` keys). |
| `Opds.pm` | OPDS 1.2 catalog + PSE page streaming. |
| `Metrics.pm` | Prometheus metrics collection. |
| `Setup.pm` | First-install actions (default category + default registry). |
| `Server.pm` | Server-state flags (restart-pending marker). |

## Configuration: `Model/Config.pm`

`Config.pm` bootstraps `lrr.conf` at compile time (overridable via `LRR_REDIS_ADDRESS`) and exposes five logical
Redis databases: archives (`redis_database` 0), Minion (`redis_database_minion` 1), config
(`redis_database_config` 2), search (`redis_database_search` 3), metrics (`redis_database_metrics` 4), matching
the defaults in `lrr.conf`. Five connection factories hand out fresh connections to the right DB —
`get_redis()`, `get_redis_config()`, `get_redis_search()`, `get_redis_metrics()`, all built on
`get_redis_internal()` — plus `get_minion()`, which constructs the `Minion` client for the Minion DB.
Callers are responsible for `quit()`ing what they take.

Runtime settings live in the `LRR_CONFIG` hash of the config DB; `get_redis_conf($param, $default)` returns the
stored value or the built-in default, and a long tail of accessor wrappers (returning raw Redis strings)
wraps it (`get_pagesize`,
`get_thumbdir`, `get_userdir`, `enable_resize`, `get_threshold`, `get_readquality`, `enable_pass`,
`enable_nofun`, `enable_cors`, `enable_metrics`, `enable_localprogress`, `enable_authprogress`,
`get_replacedupe`, `get_hqthumbpages`, `get_jxlthumbpages`, `get_style`, `get_language`, ...). `get_baseurl()`
feeds the path-prefix handling described in the Frontend chapter.

## Search: `Model/Search.pm`

`do_search($filter, $category_id, $start, $sortkey, $sortorder, $newonly, $untaggedonly, $grouptanks,
$hidecompleted)` takes nine parameters. It refuses to run until the `LAST_JOB_TIME` key exists (i.e. until the
index-building job has run once) and returns `(total, filtered_count, @ids)`.

Caching: the full result list is Storable-`nfreeze`d into the `LRR_SEARCHCACHE` hash (search DB) under a cache
key built from eight of the nine parameters (everything but `$start`, which is applied when slicing the cached
list). `check_cache()` also looks for a key with the *inverted* sort order — since
reversing a sorted list yields the opposite order, this halves the cache space (only the keyed prefix is
reversed, so archives missing the sort namespace stay at the back). Two bypasses exist: `lastread` sorts always
run uncached (reading updates don't invalidate the cache), and any structural change calls
`invalidate_cache()` from `LANraragi::Utils::Database`.

Filtering (`search_uncached()`) starts from all 40-character archive IDs — or the `LRR_TANKGROUPED` set when
`$grouptanks` groups tanks with their archives — then intersects, per token, against:

- `INDEX_<tag>` sets for tag matches (fuzzy unless quoted; a namespace in the token anchors the index scan),
- a `zscan` over the `LRR_TITLES` sorted set (members are `title\0id`) for title matches,
- set filters: category archives or the dynamic category's own search tokens, `LRR_UNTAGGED`, `LRR_NEW`,
- `$hidecompleted`: a Lua script bulk-checks `progress/pagecount > 0.85` per ID (with a per-ID HGET fallback),
- `pages:`/`read:` tokens comparing against the `pagecount`/`progress` hash fields with `=`, `>`, `>=`, `<`, `<=`.

Search syntax: `compute_search_filter()` does the tokenizing — comma-separated tokens; `"quoted"` or a trailing `$` forces exact
matching; a leading `-` excludes; `?`/`_` match one character and `*`/`%` any number (rewritten to Redis glob
metacharacters) — while the `namespace:value` restriction is applied by `search_uncached()`, anchoring the
index scan on `INDEX_<ns>:tag*` rather than `INDEX_*tag*` keys. Sorting (`sort_results()`) is either by title via
the natural sort of `LRR_TITLES`, or by any tag namespace (extracted with a regex, missing values sink to the
back as `zzzz`), or by `lastreadtime` — the lastread and tag paths fetch values in bulk via Lua scripts
(`script_load` + `evalsha`) with pure-Perl fallbacks (`_fallback_lastread`, `_fallback_tags`), and
`_impute_tank_date_tags()` infers `date_added`/`timestamp` sort keys for tanks from their member archives.

## Archives: `Model/Archive.pm`

- `serve_page($id, $path)`: extracts a file from the archive on demand through
  `get_page_data()`/`LANraragi::Utils::PageCache` (cache key `page/$id/$path`); when resizing is enabled the
  result goes through `Model::Reader::resize_image()` and is cached under `resize_page/$id/$path/$threshold/$quality`.
  CBW (web-streaming) archives additionally trigger `cbw_prefetch()` to warm the next pages.
- `serve_thumbnail($id)` / `update_thumbnail($id)`: thumbnails live under the thumb dir keyed by the first two
  ID characters, in `jpg` or `jxl` depending on `get_jxlthumbpages()`, with cross-format fallback. A missing
  thumbnail either returns `public/img/noThumb.png` or — when the client passes `no_fallback=true` — queues the
  `thumbnail_task` Minion job and returns `202` with the job ID.
- `generate_page_thumbnails($id)`: scans for missing per-page thumbnails and queues the `page_thumbnails` Minion
  job (deduplicated by the `thumbjob` hash field; `202` while the queued job is pending or running).
- `update_metadata($id, $title, $tags, $summary)`: trims inputs, writes via the Database utils, invalidates cache.
- ToC management: `add_toc_entry($id, $page, $title)` / `remove_toc_entry($id, $page)` maintain the archive's
  `toc` JSON hash ({ page → title }), which the reader overlay turns into chapters.
- `delete_archive($id)`: removes the archive from every containing Tankoubon and category, unlinks the file and
  thumbnails, and drops the Redis entry.

## Ingest: `Model/Upload.pm`

`handle_incoming_file($tempfile, $catid, $tags, $title, $summary)` returns `(status, id, name, message)`:

1. rejects non-archives with `415`; computes the ID with `compute_id()` (SHA-1 of the first 512 KB of the file,
   via Database utils);
2. **upload-time duplicate rejection** (the `replacedupe` check) — if the ID exists (and its file is on disk) or a same-named file exists, returns
   `409` unless the `replacedupe` setting allows replacement, in which case the old archive/file is deleted
   first (filename collisions are resolved through the `LRR_FILEMAP` hash);
3. registers the archive in Redis, applies caller-supplied tags — a `source:<url>` tag is also written into the
   `LRR_URLMAP` hash (search DB) so URL lookups resolve without a full reindex — then optional title/summary;
4. moves the file in two phases: temp → `<target>.upload` → rename inside the content folder, so the Shinobu
   file watcher only sees complete files (a `500` message is returned if either move fails);
5. adds `date_added`/pagecount/size, generates the thumbnail, runs autoplugins
   (`Plugins::exec_enabled_plugins_on_file`), optionally adds to a category, and invalidates the search cache.

`download_url($url, $ua)` implements the downloader half: retries for a `Content-Disposition` header, decodes the
filename (UTF-8/Latin-1/RFC 5987/URL-tail fallbacks), strips Windows-illegal characters, truncates to the
filesystem byte limit (143/255 depending on `enable_cryptofs`), and stages the file in a `File::Temp` dir for
`handle_incoming_file`.

## Backup: `Model/Backup.pm`

`build_backup_JSON($job)` walks Redis and produces a JSON document with four top-level arrays — `categories`
(from `SET_` keys: catid/name/search/archives), `tankoubons` (via `Tankoubon::get_tankoubon_list(-1)`:
tankid/name/summary/tags/archives), `stamps` (from `STAMPS_*` keys: stamp_id/content/position/archive_id), and
`archives` (all 40-char IDs with arcid/title/tags/summary/thumbhash/filename plus the archive-level `stamps`
list and `toc` fields). When invoked as a Minion job it reports progress via `$job->note(...)`.

`restore_from_JSON($json, $job)` first calls `clean_database()` to strip existing user metadata, then recreates
categories (`Category::create_category` + `add_to_category`), Tankoubons (`create_tankoubon`,
`update_metadata`, `set_tank_tags`, `update_archive_list`), archive metadata **only for IDs that still exist**
(title/tags/summary/thumbhash/stamps/toc — `stamps`/`toc` default to `[]`/`{}` when absent), and finally the
`STAMPS_*` hashes, again only if their archive survived. `invalidate_cache()` fires at the end.

## Collections: `Model/Category.pm` and `Model/Tankoubon.pm`

Categories are `SET_<timestamp>` hashes with `name`, `search` (dynamic categories) and `archives` (a JSON array;
static categories). `create_category()` can reuse a caller-supplied ID (used by backup restore);
`add_to_category()`/`remove_from_category()` maintain the array; `get_bookmark_link()`/`update_bookmark_link()`
manage the special category wired to the reader's bookmark button (exposed to the frontend as
`/api/categories/bookmark_link` and cached in localStorage as `bookmarkCategoryId`).

A Tankoubon is a single Redis **Sorted Set** keyed `TANK_<timestamp>` (15 chars): member archives sit at scores
`>= 1` (the score *is* the page order), while metadata rides in reserved members at non-positive scores — `name` at
`0`, `summary` at `-1`, `tags` at `-2`, `progress` at `-3` (see the `%TANK_METADATA` map and
`fetch_metadata_fields()`). `get_tankoubon()` reassembles the object (with pagination via `zrangebyscore ...
LIMIT`); `update_archive_list()`/`add_to_tankoubon()`/`remove_from_tankoubon()` rewrite member scores;
`update_tank_progress($tank_id, $page)` records reading position through `update_metadata_field()`;
`set_tank_tags()` also maintains the tag indexes; `get_tank_unified_tags()` merges member tags (with imputed
`date_added`) for search/sorting. Tanks register in the `LRR_TANKGROUPED` set during index building.

## Reader & OPDS: `Model/Reader.pm`, `Model/Opds.pm`

`Reader.pm` is deliberately small: `build_reader_JSON()` opens the archive, returns the browser-facing page
paths (URL-escaped, each pointing at `/api/archives/{id}/page?path=...`) and refreshes the stored `pagecount`;
`resize_image($content, $quality, $threshold)` is the Model-level resize entry that internally calls
`resize_page()` on the resampler built by `LANraragi::Utils::Resizer`'s `get_resizer()` (returning the
original bytes unchanged when the image is under the size threshold or the resizer call comes back
undefined).

`Opds.pm` renders the OPDS 1.2 feed: `generate_opds_catalog()` lists archives per page/category through
`Search::do_search`, `generate_opds_item()` renders one entry, both via the `opds`/`opds_entry` templates.
`get_opds_data()` derives author/language/circle/event from `artist`/`language`/`group`/`event` tags and
maps file extension → MIME type: `.pdf` → `application/pdf`, `.rar`/`.cbr` → `application/x-cbr`, `.epub` →
`application/epub+zip`, `.cbw` → `application/xml`, everything else (zip/cbz) → `application/x-cbz`.
PSE (Page Streamed Extension) support lives in the same templates: entries embed an
`http://vaemendis.net/opds-pse/stream` link pointing at `/api/opds/{id}/pse?page={pageNumber}` with
`pse:count`/`pse:lastRead` attributes; the endpoint (`Controller/Api/Other.pm`'s `serve_opds_page`) calls
`Opds::render_archive_page()`, which resolves the page number against the archive's file list and serves it
through `Archive::serve_page()`. Catalog pagination slices `do_search` by the common `pagesize`
setting and emits an unconditional `rel="next"` link (`start` advanced by the served entry
count; there is no `rel="prev"`), threading `?key=` through every link; categories become OPDS
facets, with `thr:count` only for categories that have no saved search string. The feed-level
`<updated>` timestamp is hardcoded
(`2010-01-10T10:03:10Z` in `templates/opds.html.tt2`); entry timestamps derive from each
archive's `date_added` tag. In `render_archive_page()` the PSE page number is 1-based and wraps
to page 1 when out of range — negative values index from the end of the file list (a quirk, not
clamped), though the endpoint's `|| 1` default masks `page=0` before it reaches the model.

## Plugins & Registries: `Model/Plugins.pm`, `Model/Registry.pm`

`Plugins.pm` (the largest Model module) covers:

- Execution: `exec_enabled_plugins_on_file($id)` (autoplugin pass after upload), `exec_metadata_plugin()`,
  `exec_script_plugin()`, `exec_download_plugin()`, `exec_login_plugin()` (the configured login plugin used by
  downloaders).
- Installation state: plugins record under `LRR_PLUGIN_<NAMESPACE>` hashes. `install_plugin($namespace, ...)`
  distinguishes built-in vs registry-managed ("managed") plugins, rejects cross-registry overwrites without
  `force`, and copies the plugin file in from its registry; `uninstall_plugin()` deletes managed plugin files,
  refuses built-ins with `403`, unregisters the plugin, and flags a server restart via
  `Server::set_restart_pending()`. `scan_plugins()` (also run at every startup from `lib/LANraragi.pm`)
  reconciles discovered plugin classes (`Module::Pluggable` discovery via `LANraragi::Utils::Plugins`) against
  the Redis registration state.

`Registry.pm` manages the sources plugins come from — registry entries (`REG_<timestamp>` IDs) support four
providers (`github`, `gitea`, `cdn`, `local`, per `%PROVIDER_FIELDS`), with create/update/delete/list plus
`refresh_registry()` (fetches and validates the registry index, capped at the 100 MB `MAX_REGISTRY_INDEX_SIZE`)
and the default-registry accessors. `lib/LANraragi.pm` refreshes every registry at startup.

## Small modules

- **`Stamp.pm`** — page stamps ("bookmark a note to page N"). `add_stamp()` creates `STAMPS_<page>_<millis>`
  hashes (content/position/archive_id) and appends the ID to the archive's `stamps` JSON array;
  `get_stamps_by_page()`, `get_stamped_pages()`, `update_stamp()`, `remove_stamp()` round out the CRUD.
- **`Stats.pm`** — `build_stat_hashes()` (run as the `build_stat_hashes` Minion job at startup and on
  database-level rebuilds — only `invalidate_cache(1)`, used by the drop/clean database endpoints, enqueues it)
  rebuilds the entire search DB in one WATCH/MULTI transaction: `flushdb()`, then per
  archive/tank the `INDEX_<tag>` sets, `LRR_TITLES`, `LRR_STATS` (tag counters), `LRR_UNTAGGED`, `LRR_NEW`,
  `LRR_TANKGROUPED`, ending by stamping `LAST_JOB_TIME`. Also exposes `is_url_recorded()` against `LRR_URLMAP`.
  The read side feeds the `/stats` page and the tag-statistics API: `get_archive_count()` is
  `scard(LRR_TANKGROUPED)` (tanks count in place of their archives), `compute_content_size()`
  sums every `arcsize` hash field into GB (two decimals), and `get_page_stat()` reads
  `LRR_TOTALPAGESTAT`; the tag cloud itself is fetched client-side from
  `GET /api/database/stats`, where `serve_tag_stats()` (`minweight`, default 1;
  `hide_excluded_namespaces`, default off — when true it excludes the `excludednamespaces`
  config, `source, date_added` by default) returns `[{namespace, text, weight}]` sliced from
  `LRR_STATS` via `zrangebyscore($minweight, "+inf", WITHSCORES)` in `build_tag_stats()` — tag
  text is lowercased with the namespace prefix split into its own field. `stats.js` and the
  index suggestions request it with `minweight=2&hide_excluded_namespaces=true`; the edit page
  uses `minweight=2` without hiding.
- **`Metrics.pm`** — Prometheus support, gated by the `enablemetrics` setting: `collect_request_metrics()` (via
  the `after_dispatch` hook installed in `lib/LANraragi.pm`, whose `before_dispatch` counterpart only stashes
  the request start time), `collect_process_metrics()` and
  `flush_request_metrics_to_redis()` on a 30 s recurring timer, worker tracking
  (`register_worker`/`unregister_worker`), and the `get_prometheus_*` renderers.
- **`Setup.pm`** — `first_install_actions()` detects a fresh install by the absence of `LRR_CONFIG → htmltitle`,
  creates the default "🔖 Favorites" category, links it to the bookmark button, and seeds the default plugin
  registry ("Ougi", `https://github.com/Difegue/Ougi.git`, branch `main`).
- **`Server.pm`** — a single `LRR_SERVER` hash in the config DB holding the `restart_pending` flag:
  `set_restart_pending()` (after plugin install/uninstall), `clear_restart_pending()` (at startup),
  `is_restart_pending()` (polled by the UI to prompt a restart).
