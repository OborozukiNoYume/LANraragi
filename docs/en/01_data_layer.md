# Data Layer (Redis)

> Baseline commit `2094cc1d` (2026-09-04). Facts verified against code — cite-checked at generation time.

LANraragi keeps all of its state in a single Redis instance, split across five numbered logical databases: archive metadata, the Minion job queue, server configuration, the search index/cache, and runtime metrics. The filesystem only stores the archives and their thumbnails; everything derivable (tag indexes, title index, statistics) is rebuilt from Redis by `LANraragi::Model::Stats::build_stat_hashes`.

All accessors live in `lib/LANraragi/Model/Config.pm` (`get_redis()`, `get_minion()`, `get_redis_config()`, `get_redis_search()`, `get_redis_metrics()`). Text fields are stored UTF-8 encoded via `LANraragi::Utils::Redis::redis_encode()`, with one deliberate exception: the archive `file` field holds the raw filesystem path without encoding (see `add_archive_to_redis()` in `lib/LANraragi/Utils/Database.pm`).

## The five databases

Database numbers below are the defaults from `lrr.conf`; each is overridable via the matching `redis_database*` key read by `lib/LANraragi/Model/Config.pm`.

| DB | `lrr.conf` key | Handle from | Contents |
|----|----------------|-------------|----------|
| 0 | `redis_database` | `get_redis()` | Archive hashes (40-char IDs), category hashes (`SET_*`), tankoubon ZSETs (`TANK_*`) — plus one stray `LRR_CONFIG` field, see the bookmark note below |
| 1 | `redis_database_minion` | `get_minion()` | Minion job queue. Schema owned entirely by `Minion::Backend::Redis`; LANraragi only enqueues jobs, never writes keys by hand |
| 2 | `redis_database_config` | `get_redis_config()` | `LRR_CONFIG`, `LRR_FILEMAP`, `LRR_TAGRULES`, `LRR_TOTALPAGESTAT`, `LRR_DUPLICATE_GROUPS`, `LRR_PLUGIN_*` |
| 3 | `redis_database_search` | `get_redis_search()` | Search index sets and the search cache (see dedicated section) |
| 4 | `redis_database_metrics` | `get_redis_metrics()` | Runtime metric hashes written by `lib/LANraragi/Model/Metrics.pm` (e.g. `metrics:active_workers`, per-process CPU/memory counters) |

## Entities

### Archive (DB0, Hash)

The key is a 40-character SHA-1 hex ID computed by `compute_id()` in `lib/LANraragi/Utils/Database.pm`: it reads the first 512000 bytes of the file and hashes them (an all-zero digest — an empty file — is rejected). Code that needs "every archive" enumerates 40-character keys with `keys('????????????????????????????????????????')` (e.g. `search_uncached()` in `lib/LANraragi/Model/Search.pm`, `build_stat_hashes()` in `lib/LANraragi/Model/Stats.pm`).

| Field | Meaning | Written by |
|-------|---------|-----------|
| `name` | Filename without extension | `add_archive_to_redis()` in `lib/LANraragi/Utils/Database.pm` |
| `title` | Display title; on write, the lowercased title is also (re)inserted into `LRR_TITLES` | `set_title()` in `lib/LANraragi/Utils/Database.pm` |
| `tags` | Comma-separated tag string; writes go through `update_indexes()` which maintains `INDEX_*`, `LRR_STATS`, `LRR_UNTAGGED`, `LRR_URLMAP` | `set_tags()` in `lib/LANraragi/Utils/Database.pm` |
| `summary` | Free-text description | `set_summary()` in `lib/LANraragi/Utils/Database.pm` |
| `file` | Absolute filesystem path (not redis-encoded) | `add_archive_to_redis()` |
| `arcsize` | File size in bytes | `add_archive_to_redis()` / `add_arcsize()` |
| `isnew` | `"true"`/`"false"`, mirrored into the `LRR_NEW` set | `set_isnew()` in `lib/LANraragi/Utils/Database.pm` |
| `progress` | Current read page | `update_progress` in `lib/LANraragi/Controller/Api/Archive.pm` |
| `pagecount` | Total page count | `add_pagecount()` in `lib/LANraragi/Utils/Database.pm` |
| `lastreadtime` | Unix timestamp of last read, written together with `progress` | `update_progress` in `lib/LANraragi/Controller/Api/Archive.pm` |
| `thumbjob` | Minion job ID of the queued page-thumbnail job; deleted when the job finishes | `generate_page_thumbnails()` in `lib/LANraragi/Model/Archive.pm`, cleanup in `lib/LANraragi/Utils/Minion.pm` |
| `thumbhash` | SHA-1 of the extracted cover image, used by metadata plugins for gallery lookup (e.g. `lookup_gallery()` in `lib/LANraragi/Plugin/Metadata/EHentai.pm`) | `extract_thumbnail()` in `lib/LANraragi/Utils/Archive.pm` |
| `toc` | JSON object mapping page numbers to chapter titles | `add_toc_entry()` / `remove_toc_entry()` in `lib/LANraragi/Model/Archive.pm` |

**ID lifecycle.** `add_archive_to_redis()` creates the hash and immediately registers the archive in `LRR_TANKGROUPED` (new archives cannot be in a tank yet) and flags `isnew`. If a file's content changes enough to alter its hash, `change_archive_id()` in `lib/LANraragi/Utils/Database.pm` renames the hash to the new ID, refreshes `arcsize`, and migrates membership in every category and tankoubon that referenced the old ID. `clean_database()` sweeps DB0 for 40-character keys whose backing file no longer exists, and uses the config DB's `LRR_FILEMAP` to re-link files whose computed ID has drifted.

### Category (DB0, Hash)

Key: `SET_` followed by a 10-digit Unix timestamp (14 characters total — this is also the validity check in `get_category()`). `create_category()` in `lib/LANraragi/Model/Category.pm` bumps the timestamp forward until the key is free. Categories are enumerated with `keys('SET_??????????')` in `get_category_list()`.

| Field | Meaning |
|-------|---------|
| `name` | Category name |
| `search` | Search predicate; non-empty makes the category dynamic |
| `pinned` | Pin flag |
| `archives` | JSON array of archive IDs; only meaningful for static categories — `get_category()` always returns `[]` for dynamic ones |

### Tankoubon (DB0, Sorted Set)

Key: `TANK_` followed by a 10-digit Unix timestamp (15 characters total, checked in `get_tankoubon()`). Unlike archives and categories, a tankoubon is a single Sorted Set whose scores encode both metadata and member order (the `%TANK_METADATA` map in `lib/LANraragi/Model/Tankoubon.pm`; members are written as `field_value` strings by `update_metadata_field()`):

| Score | Member |
|-------|--------|
| `>= 1` | Archive IDs; the score is the position in reading order (read back with `zrangebyscore($tank_id, 1, "+inf")`) |
| `0` | `name_<tank name>` |
| `-1` | `summary_<text>` |
| `-2` | `tags_<comma-separated tags>` |
| `-3` | `progress_<page>` |

## Search database (DB3) keys

| Key | Type | Contents |
|-----|------|----------|
| `LRR_TITLES` | Sorted Set (all scores 0) | Members are `"<lowercased title>\0<id>"` for both archives and tanks. Fuzzy filtering uses `ZSCAN` matching and title sorting uses `ZRANGEBYLEX` (`lib/LANraragi/Model/Search.pm`); the null-byte separator survives because titles are trimmed of CR/LF (`set_title()`, `build_stat_hashes()`) |
| `INDEX_<tag>` | Set | IDs of archives (and tanks) carrying the lowercased tag. Tanks are indexed under their *unified* tagset — own tags plus tags imputed from member archives — by `update_tank_imputed_indexes()` in `lib/LANraragi/Model/Tankoubon.pm` |
| `LRR_NEW` | Set | IDs with `isnew = true` |
| `LRR_UNTAGGED` | Set | Archives with no tag outside the "basic" namespaces (`artist`, `parody`, `series`, `language`, `event`, `group`, `date_added`, `timestamp`, `source` — see `update_indexes()` in `lib/LANraragi/Utils/Database.pm`) |
| `LRR_TANKGROUPED` | Set | The grouping-aware visible set: every tank ID plus every archive ID not contained in any tank; maintained by `lib/LANraragi/Model/Tankoubon.pm` and used as the base ID list when tank grouping is enabled (`do_search()` / `search_uncached()`) |
| `LRR_URLMAP` | Hash | `source:` tag URL to archive ID; consulted by `is_url_recorded()` in `lib/LANraragi/Model/Stats.pm` |
| `LRR_STATS` | ZSet | Tag to occurrence count; powers the tag cloud via `build_tag_stats()` in `lib/LANraragi/Model/Stats.pm` |
| `LRR_SEARCHCACHE` | Hash | Search results cache, detailed below |
| `LAST_JOB_TIME` | String | Timestamp set at the end of `build_stat_hashes()`; while absent, `do_search()` reports the engine as uninitialized (returns `-1`) |

All of these are rebuildable. `build_stat_hashes()` WATCHes the index keys, `flushdb`s the whole search database inside a MULTI, and rewrites everything from DB0; `invalidate_cache(1)` enqueues it as the `build_stat_hashes` Minion task.

### How a search executes

Step-by-step through `do_search()` / `search_uncached()` in `lib/LANraragi/Model/Search.pm` — a useful map of how the keys above cooperate:

1. If `LAST_JOB_TIME` does not exist, the engine is not initialized; the API returns `-1`.
2. Build the eight-segment cache key and probe `LRR_SEARCHCACHE` (including the inverted-sort twin); `lastread`-sorted queries skip the cache entirely.
3. Seed the candidate list: members of `LRR_TANKGROUPED` when tank grouping is on, otherwise all 40-character keys in DB0.
4. Apply the category: a dynamic category's `search` string is parsed into extra filter tokens; a static category's `archives` JSON list is intersected with the candidates.
5. Apply toggles: untagged-only intersects `LRR_UNTAGGED`; new-only intersects `LRR_NEW` (a tank matches if any member archive is new); hide-completed drops archives whose `progress`/`pagecount` exceeds 85% — checked in bulk against the DB0 hashes with a Lua script, falling back to per-ID `HGET`s.
6. Apply filter tokens: exact tags read `INDEX_<tag>` directly, inexact tags glob `INDEX_*` keys, and every token also fuzzy-matches titles via `ZSCAN` over `LRR_TITLES`. The special `read:`/`pages:` tokens compare the DB0 `progress`/`pagecount` fields numerically (supports `>`, `<`, `>=`, `<=`).
7. Sort: by title via `nsort` over `ZRANGEBYLEX LRR_TITLES`; by `lastread` via `lastreadtime` (tanks use the maximum across member archives); by any other key via the first tag value in that namespace, with IDs missing the namespace pushed to the back.
8. The final ID list (prefixed with the keyed count) is frozen into `LRR_SEARCHCACHE` under the cache key.

## Config database (DB2) keys

| Key | Type | Contents |
|-----|------|----------|
| `LRR_CONFIG` | Hash | Server settings, read through `get_redis_conf(param, default)` in `lib/LANraragi/Model/Config.pm` |
| `LRR_FILEMAP` | Hash | Absolute file path to archive ID; written by the Shinobu watcher (`lib/Shinobu.pm`), read by `clean_database()` in `lib/LANraragi/Utils/Database.pm` and `lib/LANraragi/Model/Upload.pm` |
| `LRR_TAGRULES` | List | Flattened tag rules (`save_computed_tagrules()` / `get_computed_tagrules()` in `lib/LANraragi/Utils/Database.pm`) |
| `LRR_TOTALPAGESTAT` | String | Counter of total pages read, INCR'd on every progress update (`update_progress` in `lib/LANraragi/Controller/Api/Archive.pm`), read by `get_page_stat()` in `lib/LANraragi/Model/Stats.pm` |
| `LRR_DUPLICATE_GROUPS` | Hash | `dupgp_<key>` to JSON array of archive IDs; produced by the duplicate-detection Minion task (`lib/LANraragi/Utils/Minion.pm`), surfaced by `lib/LANraragi/Controller/Duplicates.pm` |
| `LRR_PLUGIN_<NAMESPACE>` | Hash | Per-plugin state, namespace uppercased: `enabled`, `customargs` (JSON array), `installed_path`, `installed_version`, `installed_registry`, `installed_sha256`, `type` (`lib/LANraragi/Utils/Plugins.pm`, `lib/LANraragi/Model/Plugins.pm`) |

`LRR_CONFIG` fields the code reads (non-exhaustive — the configuration page can write others; defaults shown as read by `lib/LANraragi/Model/Config.pm`):

| Field | Default | Field | Default |
|-------|---------|-------|---------|
| `dirname` | `./content` | `apikey` | *(empty)* |
| `thumbdir` | `./thumb` | `localprogress` | `0` |
| `devmode` | `0` | `authprogress` | `0` |
| `password` | bcrypt hash | `tagruleson` | `1` |
| `tagrules` | exclusion list | `enableresize` | `0` |
| `disableopenapi` | `0` | `sizethreshold` | `1000` |
| `htmltitle` | `LANraragi` | `readerquality` | `50` |
| `motd` | welcome string | `theme` | `modern.css` |
| `tempmaxsize` | `500` | `usedateadded` | `1` |
| `pagesize` | `100` | `usedatemodified` | `0` |
| `enablepass` | `1` | `enablecryptofs` | `0` |
| `nofunmode` | `0` | `hqthumbpages` | `0` |
| `enablecors` | `0` | `jxlthumbpages` | `0` |
| `enablemetrics` | `0` | `replacedupe` | `0` |
| `language` | `auto` | `replacetitles` | `1` |
| `excludednamespaces` | `source, date_added` | | |

### The `bookmark_link` caveat

`bookmark_link` (the category behind the reader's bookmark button) is nominally an `LRR_CONFIG` field, but every read and write goes through `lib/LANraragi/Model/Category.pm` (`get_bookmark_link()`, `update_bookmark_link()`, `remove_bookmark_link()`, `delete_category()`) on the handle from `get_redis()` — meaning it is stored in an `LRR_CONFIG` hash **in DB0**, not in the config database. First-run setup links it via `lib/LANraragi/Model/Setup.pm`. Tools that dump or migrate DB2's `LRR_CONFIG` will not see this field.

## Search cache and invalidation

`do_search()` in `lib/LANraragi/Model/Search.pm` caches results in the `LRR_SEARCHCACHE` hash:

- Field name: the eight search parameters joined by dashes —
  `"$category_id-$filter-$sortkey-$sortorder-$newonly-$untaggedonly-$grouptanks-$hidecompleted"`.
- Value: a Storable `nfreeze` of `[ $keyed_count, @ids ]`, where the leading count says how many IDs carry the sort namespace.
- On a miss, the key with the *inverted* sort order is tried; `check_cache()` then reverses only the keyed prefix so IDs missing the sort key stay at the back.
- Searches sorted by `lastread` never use the cache: setting `lastreadtime` deliberately does not cache-bust, so history sorts always recompute.

`invalidate_cache()` in `lib/LANraragi/Utils/Database.pm` DELETEs `LRR_SEARCHCACHE` and re-seeds it with a `created` timestamp field; passed a true argument it also enqueues the `build_stat_hashes` index-rebuild job (used by the drop/clean database endpoints in `lib/LANraragi/Controller/Api/Database.pm`).

Verified callers of `invalidate_cache()`: `set_tags()` and `set_isnew()` (`lib/LANraragi/Utils/Database.pm`), archive metadata edits (`update_metadata()` in `lib/LANraragi/Model/Archive.pm`), category membership changes (`lib/LANraragi/Model/Category.pm`), every tankoubon mutation (`lib/LANraragi/Model/Tankoubon.pm`), Shinobu's file added/edited/deleted callbacks (`lib/Shinobu.pm`), backup restore (`lib/LANraragi/Model/Backup.pm`), uploads (`lib/LANraragi/Model/Upload.pm`), batch tagging (`lib/LANraragi/Controller/Batch.pm`), the `nHentaiSourceConverter` script plugin (`lib/LANraragi/Plugin/Scripts/nHentaiSourceConverter.pm`), and the search-cache endpoint (`clear_cache()` in `lib/LANraragi/Controller/Api/Search.pm`). The clear-new-flags endpoint (`clear_new_all()` in `lib/LANraragi/Controller/Api/Database.pm`) does *not* touch the search cache — it only resets `isnew` fields and drops `LRR_NEW`.

Notably *not* cache-busting: reading-progress updates (`update_progress` writes `progress`/`lastreadtime` only, as described above) and bare `set_title()`/`set_summary()` calls — the metadata-edit path in `update_metadata()` busts the cache for the UI, so direct model-level title edits only refresh the `LRR_TITLES` index.

## Environment variables

Environment overrides beat both `lrr.conf` and `LRR_CONFIG`:

| Variable | Effect | Read by |
|----------|--------|---------|
| `LRR_REDIS_ADDRESS` | Overrides `redis_address` (host:port or unix socket path) | top of `lib/LANraragi/Model/Config.pm` |
| `LRR_DATA_DIRECTORY` | Overrides the content directory (`dirname`) | `get_userdir()` in `lib/LANraragi/Model/Config.pm`; directory created by `script/launcher.pl` |
| `LRR_THUMB_DIRECTORY` | Overrides the thumbnail directory (`thumbdir`) | `get_thumbdir()` in `lib/LANraragi/Model/Config.pm` |
| `LRR_TEMP_DIRECTORY` | Overrides the temporary folder; also hosts the server PID file | `lib/LANraragi/Utils/TempFolder.pm` and `script/launcher.pl` |
| `LRR_LOG_DIRECTORY` | Overrides the log folder | `lib/LANraragi/Utils/Logging.pm` |
| `LRR_FORCE_DEBUG` | Forces dev mode regardless of the `devmode` setting | `enable_devmode()` in `lib/LANraragi/Model/Config.pm` |
| `LRR_NETWORK` | Overrides the Hypnotoad listen address/port | `script/launcher.pl` |

Two further variables exist in the same family: `LRR_DEVSERVER` (enables the Redis client debug flag in `get_redis_internal()` and a logging mode in `lib/LANraragi/Utils/Logging.pm`) and `LRR_DISABLE_OPENAPI` (forces the OpenAPI docs off in `get_disable_openapi()`).
