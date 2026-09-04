# Utility Modules Tour: `lib/LANraragi/Utils/`

> Baseline commit `2094cc1d` (2026-09-04). Facts verified against code — cite-checked at generation time.

## Overview

Everything under `lib/LANraragi/Utils/` is stateless glue that Models and Controllers lean on. The
modules, one line each:

| Module | Responsibility |
|--------|----------------|
| `Archive.pm` | Reading archives (zip/cbz via libarchive, PDF via VIPS, CBW via HTTP), extracting pages, generating thumbnails |
| `Database.pm` | Archive records in Redis: ID computation, tag/title/summary writes, JSON serialization, index upkeep |
| `Generic.pm` | Grab-bag: image/archive detection, Redis-backed locks, Minion/Shinobu process startup, CSS theme listing |
| `I18N.pm` | `Locale::Maketext` subclass loading gettext `.po` files from `locales/template/` |
| `I18NInitializer.pm` | Installs the `lh` Mojolicious helper; resolves forced language or `Accept-Language` |
| `ImageMagickResizer.pm` | Fallback resizer implementation on `Image::Magick` |
| `Logging.pm` | Logger construction (`get_logger`), plugin loggers, log file reading |
| `Login.pm` | `is_logged_in_api()` — API key / session checks |
| `Metrics.pm` | Prometheus text exposition: route normalization plus `/proc` counters |
| `Minion.pm` | Registers all background job tasks on the Minion instance |
| `OpenAPI.pm` | `apply_openapi_mojo_overrides()` — bypasses validation under `disable_openapi`, otherwise validates and logs failures |
| `PageCache.pm` | CHI-based page cache (FastMmap on Unix, Memory on Windows) |
| `Path.pm` | Filesystem helpers: path creation/opening, archive path lookup, package<->path conversion |
| `Plugins.pm` | Plugin registry glue: listing, loading, parameters, registration in Redis |
| `Redis.pm` | `redis_encode()`/`redis_decode()` UTF-8 boundary helpers |
| `Registry.pm` | Fetching/validating plugin-registry resources (git raw URLs, CDN artifacts, index schema) |
| `Resizer.pm` | `get_resizer()` factory: libvips when available, ImageMagick otherwise |
| `RotatingLog.pm` | `Mojo::Log` subclass with size-based rotation and `flock` locking |
| `Routing.pm` | `apply_routes()` — the entire route table, CORS/auth bridges, OpenAPI setup |
| `String.pm` | Title cleanup, trimming, URL trimming, similarity ranking |
| `Tags.pm` | Tag rule parsing and application (`rewrite_tags`) |
| `TempFolder.pm` | `get_temp()` — locates/creates the temporary folder |
| `Vips.pm` | FFI bindings to libvips, including the PDF loader |
| `VipsResizer.pm` | Preferred resizer implementation on libvips |

## Archives, Images, and PDF

`lib/LANraragi/Utils/Archive.pm` exports `is_file_in_archive`, `extract_file_from_archive`,
`extract_single_file`, `extract_thumbnail`, `generate_thumbnail`, `get_filelist`, `is_cbw`,
`parse_cbw_urls`, and `cbw_prefetch`. It relies on three distinct backends, chosen by file type:

- **Archives (zip/cbz and friends)** go through `Archive::Libarchive` (both `ArchiveRead` and
  `Peek` interfaces). `get_filelist()` iterates entries, skips non-images and AppleDouble/
  AppleSingle junk (see the internal `is_apple_signature()`), applies a natural sort, then moves
  cover pages to the front and credit pages to the back.
- **PDFs are handled by VIPS, not GhostScript** — there is no `gs` invocation anywhere in the
  code (Ghostscript appears only as a libvips packaging dependency in the Homebrew formula). `get_filelist()` counts pages via `lib/LANraragi/Utils/Vips.pm`'s
  `vips_image_get_n_pages`, and `extract_single_file()` renders a page
  with `pdfload_page_dpi($archive, $page - 1, 200)` before re-encoding it as JPEG with
  `write_to_buffer()`.
- **CBW (ComicBookWeb)** files are XML pointing at remote page images. `parse_cbw_urls()`
  parses the XML (variable substitution plus `[format:a-b]` range expansion via internal
  `expand_cbw_range()`); `get_filelist()` synthesizes the zero-padded page names through the
  internal `cbw_page_name()`, and `extract_single_file()` proxies
  the remote bytes through `fetch_cbw_image()`. `cbw_prefetch()` warms the next few pages into
  `PageCache` after a page is served.

The thumbnail pipeline: `extract_thumbnail()` extracts the requested page (storing the page
bytes in PageCache for CBW archives, cover or not), computes a SHA-1 `thumbhash` in Redis for cover images, and
calls `generate_thumbnail()`, which produces an image fit within 500x1000 (so at most 500px
wide) at JPEG quality 50 (80 with
`use_hq`, JPEG XL when `get_jxlthumbpages` is enabled). Non-cover thumbnails land under a
two-character subfolder plus archive ID. The internal `extract_single_file_to_file()` (not
exported) backs `extract_file_from_archive()`, the plugin-facing variant that unpacks into
`/temp/plugin`.

### The resizer pair

`lib/LANraragi/Utils/Resizer.pm` exposes a single `get_resizer()` factory, memoized with
`state`. It returns a `LANraragi::Utils::VipsResizer` when `Vips::is_vips_loaded()` is true,
otherwise a `LANraragi::Utils::ImageMagickResizer`. Both implementations implement exactly two
methods:

- `resize_page($content, $quality, $format)` — downscales to 1064px width for reading.
- `resize_thumbnail($content, $quality, $use_hq, $format)` — fits within 500x1000.

`lib/LANraragi/Utils/Vips.pm` does not use a Perl binding module; it attaches the C library
directly with `FFI::Platypus` (discovered via `FFI::CheckLib::find_lib(lib => ['vips',
'vips-42'])`). `init()` calls `vips_cache_set_max(0)` to disable the operation cache, and if the
library is missing, every attached function is replaced by a stub that dies. Beyond
`vips_image_new_from_file` and friends, it offers `fit_resize`, `stretch_resize`,
`cover_resize`, `resize_to_width`, `crop`, `grayscale`, `jpegsave`/`pngsave`,
`write_to_buffer`, and `unref_image` (the `g_object_unref` wrapper you must call to free
VipsImage handles).

`ImageMagickResizer` lazily `require`s `Image::Magick` inside a `try`, sets the
`jpeg:size` decoder hint to avoid decoding full-resolution frames, and picks `Sample` (fast) or
`Scale` (HQ) for thumbnails. If PerlMagick is unavailable the `require` dies, the `catch` block
merely logs at debug level, and the method returns the value of that logging call rather than
`undef` — so the definedness check in `generate_thumbnail()` (which logs "Couldn't create
thumbnail!") can miss the failure. That is a latent code quirk, documented here rather than fixed.

## Minion Tasks

`lib/LANraragi/Utils/Minion.pm` registers twelve tasks in `add_tasks()`:

| Task | Purpose |
|------|---------|
| `thumbnail_task` | Thumbnail for one archive page (page 0 = cover) |
| `tank_thumbnail_task` | Thumbnail for a tankoubon, from its first archive |
| `page_thumbnails` | All page thumbnails for one archive; parallelized with `MCE::Loop` on Unix |
| `regen_all_thumbnails` | Full-library thumbnail regeneration, including tankoubons |
| `find_duplicates` | Groups archives by Hamming distance between `thumbhash` values into `LRR_DUPLICATE_GROUPS` |
| `build_stat_hashes` | Delegates to `LANraragi::Model::Stats::build_stat_hashes` |
| `handle_upload` | Ingests an uploaded file via `LANraragi::Model::Upload::handle_incoming_file` |
| `download_url` | Downloads a URL (through a downloader plugin if one matches) and ingests it |
| `run_plugin` | Executes a plugin by namespace via `use_plugin()` |
| `install_plugin` | Installs a managed plugin under a `plugin-write:` lock (TTL 300s) |
| `backup_json` | Writes a backup JSON to the temp folder via `LANraragi::Model::Backup::build_backup_JSON` |
| `restore_backup` | Restores from backup JSON via `restore_from_JSON` |

Note the Windows asymmetry: `MCE::Loop` parallelism is Unix-only (libarchive threading), so the
thumbnail and duplicate jobs fall back to sequential execution there.

### Duplicate detection, end to end

`find_duplicates` deserves a closer look, since its result powers a whole page. Every
40-character archive ID is scanned for a `thumbhash` (tanks don't carry one); hashes are then
clustered by flood fill. Two hashes are "close" when their SHA-1 hex strings differ in at most
`$threshold` *characters* — the distance is counted character-by-character, not bit-by-bit,
with an early exit once the threshold is exceeded. The duplicates page hardcodes the threshold:
`public/js/duplicates.js` queues the job as
`/api/minion/find_duplicates/queue?args=[5]&priority=0`. Groups of two or more members are
written into `LRR_DUPLICATE_GROUPS` (config DB) under a `dupgp_<key>` field whose key is the
concatenation of each member's first 10 ID characters after sorting the group, so the same set
of archives always maps to the same field. One structural quirk: the `visited` set is shared
across the MCE workers, so a hash close to an archive already absorbed into another worker's
group is skipped, and single-member remainders are dropped by the `>= 2` filter — borderline
groups can therefore be under-reported.

`lib/LANraragi/Controller/Duplicates.pm` renders `/duplicates` from that hash: it prunes stale
groups (drops the whole field when only a pair remains, otherwise rewrites the JSON without the
vanished ID) and wipes all groups when the `delete` request parameter is set.
`public/js/duplicates.js` displays the groups as one DataTable with separator rows, offers
auto-select rules ("worst" duplicate by fewer tags / smaller size / fewer pages / older /
younger) and deletes archives through `DELETE /api/archives/{id}`. This visual matching is
independent of upload-time duplicate rejection (`replacedupe`), which compares exact IDs and
filenames instead.

## Concurrency and Locking

`lib/LANraragi/Utils/Generic.pm` provides two locking entry points over Redis `SET NX EX`:

- `exec_with_lock($mojo, $lock_name, $operation, $resource_id, $func)` — the controller-facing
  five-argument variant. On contention it renders a 423 JSON response naming the locked
  resource and returns false.
- `exec_with_lock_pure(\@lock_names, $func, $redis?, $ttl?)` — the primitive. It acquires
  multiple locks (default TTL 10s), and each lock value is a random SHA-256 token released by a
  Lua script that compares the token before deleting — the standard single-instance distributed
  lock pattern, preventing workers from deleting locks they do not own. Failed multi-lock
  acquisitions roll back in reverse order.

The same module also owns process lifecycle: `start_minion()` sizes the worker's parallel job
count with `MCE::Util::get_ncpu()` and launches it in a `Proc::Simple` subprocess (a frozen
`Proc::Simple` object stored in `minion.pid`, the raw PID in `minion.pid-s6`), while `start_shinobu()` does the same for the file watcher. `split_workload_by_cpu()`
splits an array into per-CPU chunks, but the Minion tasks above hand their full key list to
`mce_loop` and let MCE chunk internally — nothing currently calls it.

## The Shinobu File Watcher

`lib/Shinobu.pm` runs as its own process — executing the file directly calls
`initialize_from_new_process()` — and `start_shinobu()` launches it at every app boot, after
`LANraragi.pm`'s `startup()` kills any stale instance through the Storable-frozen `Proc::Simple`
handle in `shinobu.pid` (Unix only). Watching is done by
`File::ChangeNotify->instantiate_watcher()` over the content folder, filtering on the same
archive-extension regex as `is_archive()` in `lib/LANraragi/Utils/Generic.pm`
(`zip|rar|7z|tar|tar.gz|lzma|xz|cbz|cbr|cb7|cbt|cbw|pdf|epub|tar.zst|zst`), following symlinks
and excluding `thumb`/hidden directories; a manual loop polls `new_events()` once per second.

Before watching, `update_filemap()` runs a full recursive scan and diffs it against
`LRR_FILEMAP`: vanished paths are pruned from the filemap and new archives go through the same
`add_to_filemap()` path as live events (parallelized with `mce_loop` on Unix). Live events map
`create`/`modify` to `new_file_callback()` and `delete` to `deleted_file_callback()`:

- **New or modified file.** `add_to_filemap()` re-checks `is_archive()`, waits for the file to
  be openable and at least 512000 bytes (bailing out after 5 one-second tries — smaller files
  can still be read mid-write), computes the ID and takes the `archive-write:$id` lock (TTL 60 s)
  before `update_filemap_entry()` runs. A changed ID is migrated non-destructively via
  `change_archive_id()` — the Redis hash is `rename`d so tags survive, unlike upload-time
  duplicate replacement. A brand-new ID triggers `add_new_file()` *outside* the lock:
  `add_archive_to_redis()`, `add_timestamp_tag()`, `add_pagecount()`, `extract_thumbnail()`,
  then the auto-plugin pass `exec_enabled_plugins_on_file()`, followed by `invalidate_cache()`.
  The two-phase `.upload` staging in `lib/LANraragi/Model/Upload.pm` exists precisely so
  Shinobu only ever sees complete files (`.upload` matches neither the watcher filter nor
  `is_archive()`).
- **Deleted file.** The path is `hdel`ed from `LRR_FILEMAP` and the search cache invalidated —
  the archive's Redis hash is *not* removed, so it lingers as an orphan until `clean_database()`
  sweeps it.

The API controls in `lib/LANraragi/Controller/Api/Shinobu.pm` map to the four `/shinobu`
operations: `shinobu_status()` (alive flag + PID from `shinobu.pid`), `stop_shinobu()` (kill
only), `restart_shinobu()` (kill + relaunch), and `reset_filemap()` — the `/shinobu/rescan`
endpoint DELETEs `LRR_FILEMAP` and restarts the process, so the fresh boot performs the full
rescan. Every DB-touching callback wraps its work in `eval` and logs to the `shinobu` log; with
metrics enabled the process collects its own counters roughly every 30 seconds.

## Tag Rules

`lib/LANraragi/Utils/Tags.pm` parses user-written rules with `tags_rules_to_array()` and applies
them with `rewrite_tags()`. Six rule types exist:

| Syntax | Type | Effect |
|--------|------|--------|
| `-tag` | `remove` | Drop the exact tag |
| `-namespace:*` | `remove_ns` | Drop every tag in the namespace |
| `~namespace` | `strip_ns` | Remove the namespace prefix, keep the value |
| `match -> replacement` | `replace` | Rewrite the exact tag |
| `ns:* -> other:*` | `replace_ns` | Rename the namespace |
| `match => replacement` | `hash_replace` | O(1) exact-match rewrite via lookup hash |

All matches are lowercased at parse time. `hash_replace` rules are split out by
`build_tag_replace_hash()` into a case-insensitive hash that `apply_rules()` consults *after*
the sequential rules have run, so they act as the final word on a tag's value.

## Routing, Login, and Web Concerns

`lib/LANraragi/Utils/Routing.pm`'s `apply_routes()` is the single route table: it wires
`Mojolicious::Plugin::OpenAPI` against `tools/openapi.yaml` with an `api_key` security scheme
delegating to `is_logged_in_api()`, optionally bridges CORS (`login#setup_cors`) and the
"no-fun-allowed" enforced-auth mode, serves versioned `/js/:version/*` assets with an immutable
cache header (guarded by `is_path_within()` against path traversal), and declares the
public/login/ logged-in route hierarchies.

`lib/LANraragi/Utils/Login.pm`'s `is_logged_in_api()` accepts any of: a `Bearer` + base64 API
key `Authorization` header, a `key` request parameter (used by OPDS), an authenticated session,
or simply having password enforcement disabled. `lib/LANraragi/Utils/OpenAPI.pm`'s
`apply_openapi_mojo_overrides()` re-wires `openapi.valid_input`: with `disableopenapi` set it
bypasses request *and* response validation entirely; otherwise requests are still validated, but
failures are logged server-side and rendered as a 400 body.

Localization lives in `I18N.pm`/`I18NInitializer.pm`: `Locale::Maketext` with gettext lexicons,
exposed to templates as the `lh` helper, honoring a forced language setting before falling back
to `Accept-Language` negotiation. Observability is split between `Logging.pm`/`RotatingLog.pm`
(loggers, plugin loggers, rotation with `flock`) and `Metrics.pm` (Prometheus counters:
`extract_endpoint()` normalizes request paths to route templates to limit label cardinality,
and `read_proc_stat`/`read_proc_statm`/`read_proc_io_bytes` etc. feed process metrics). The
`RotatingLog` rotation trigger is size-based — 1 MiB by default (`LRR_LOGROTATE_SIZE`), checked
every 1000 appended lines — gzipping old files as `<log>.N.gz` and keeping `LRR_LOGROTATE_FILES`
of them (default 7).

## Everything Else

- **Data layer.** `Database.pm` covers archive CRUD (`add_archive_to_redis`, `set_tags`,
  `set_title`, `set_summary`, `get_archive_json_multi`, `compute_id`, `invalidate_cache`,
  `get_computed_tagrules`, `update_indexes`, `clean_database`). `Redis.pm` is just the
  encode/decode pair: `redis_encode()` applies NFC normalization before UTF-8 encoding, while
  `redis_decode()` double-decodes with `FB_CROAK`. `PageCache.pm` wraps CHI — FastMmap driver
  on Unix (data files under the app temp dir), Memory on Windows — capped at
  `max(0, min(tempmaxsize, 4096))` MB. Only two key shapes exist: raw page bytes under
  `page/$id/$path` (written by `get_page_data()` and by the CBW prefetch/thumbnail stash) and
  resized variants under `resize_page/$id/$path/$threshold/$quality`. Entries carry no TTL, and
  nothing invalidates them on archive edit or deletion — the sole clear path is
  `DELETE /api/tempfolder` (`clean_tempfolder()` calling `PageCache::clear()`), so pages of
  deleted archives linger until size eviction.
- **Filesystem.** `Path.pm` (`create_path`, `open_path_or_die`, `get_archive_path`,
  `package_to_path`/`path_to_package`, `compat_path`) and `TempFolder.pm` (`get_temp`).
  `String.pm` holds `clean_title`, `trim`, `trim_url`, and `most_similar` (backed by
  `String::Similarity`).
- **Plugin support.** `Plugins.pm` and `Registry.pm` are covered in
  [04_plugins.md](04_plugins.md); the former is the Redis-backed lookup layer, the latter the
  registry fetch/validation layer used by managed plugin installation.
