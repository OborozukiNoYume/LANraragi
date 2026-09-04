# The Plugin System

> Baseline commit `2094cc1d` (2026-09-04). Facts verified against code — cite-checked at generation time.

## Overview

LANraragi plugins are plain Perl packages under `lib/LANraragi/Plugin/` that declare their
metadata through a `plugin_info()` function. The system supports four plugin types, each with
one required method, plus an install/uninstall lifecycle for third-party ("managed") plugins
distributed through registries. The execution machinery lives in `lib/LANraragi/Model/Plugins.pm`;
the Redis lookup/registration glue lives in `lib/LANraragi/Utils/Plugins.pm`.

## Plugin Types

| Type | Directory | Count | Required method | Role |
|------|-----------|-------|-----------------|------|
| `login` | `Plugin/Login/` | 4 | `do_login` | Return a `Mojo::UserAgent` with credentials/cookies baked in |
| `metadata` | `Plugin/Metadata/` | 21 | `get_tags` | Fetch or compute tags (and optionally title/summary) for one archive |
| `download` | `Plugin/Download/` | 3 | `provide_url` | Turn a page URL into a direct download URL or a local file path |
| `script` | `Plugin/Scripts/` | 4 | `run_script` | Arbitrary one-shot operations run from Plugin Configuration |

The method contract is enforced at list time: `lib/LANraragi/Utils/Plugins.pm`'s `get_plugins()`
skips any package whose type's required method is missing (`can('run_script')`,
`can('get_tags')`, `can('provide_url')`, `can('do_login')`).

## The `plugin_info` Contract

Every plugin returns a hash from `plugin_info()`. Standard keys (as declared by the built-in
plugins): `name`, `type`, `namespace`, `author`, `version`, `description`, and `icon` (a base64
data URI). Optional keys:

| Key | Used by | Meaning |
|-----|---------|---------|
| `parameters` | Settings UI | Array (positional) or hash (named) of `{ type, desc, default_value }` parameter descriptors |
| `oneshot_arg` | Metadata plugins | Prompt shown for a per-run argument, e.g. a gallery URL override |
| `login_from` | All types | Namespace of a login plugin whose UserAgent should be injected |
| `cooldown` | Batch tagging UI | Suggested delay in seconds between runs for API politeness |
| `url_regex` | Download plugins | Regex deciding which URLs this downloader claims |

Two of these deserve a precision note:

- **`cooldown` is advisory only.** It is declared by `EHentai` (4 s), `MEMS` (4 s) and `Pixiv`
  (1 s) in their `plugin_info`, and the only consumer is the front-end batch-tagger
  (`public/js/batch.js` reads it as the default timeout). No backend code reads or enforces it.
- **`login_from` is a namespace, not a module name.** `lib/LANraragi/Model/Plugins.pm`'s
  `exec_login_plugin()` looks it up through the normal registry path.

## Discovery and Registration

Two mechanisms cooperate:

1. **Compile-time discovery** — `lib/LANraragi/Utils/Plugins.pm` uses
   `Module::Pluggable (search_path => ['LANraragi::Plugin'])`, which finds every package under
   the four plugin directories (including `Managed/` and `Sideloaded/` subdirectories when they
   exist).
2. **Runtime registry** — `lib/LANraragi/Model/Plugins.pm`'s `scan_plugins()` (invoked at
   startup from `lib/LANraragi.pm`) reconciles discovered classes against Redis: it registers
   each discovered namespace via `register_plugin()`, warns on duplicate namespaces or
   case-collisions, and unregisters orphaned `LRR_PLUGIN_*` keys whose files vanished from disk
   (unless the file still exists on disk).

Only registered plugins are callable: `get_plugin()` in `lib/LANraragi/Utils/Plugins.pm`
refuses to load a namespace that has no `installed_path` recorded, so an uninstalled plugin
keeps its user settings but stops being invocable.

## Execution Flows

### Metadata plugins

`use_plugin()` in `lib/LANraragi/Utils/Plugins.pm` dispatches to
`lib/LANraragi/Model/Plugins.pm`'s `exec_metadata_plugin()`, which builds the `$lrr_info` hash
and calls `$plugin->get_tags(\%lrr_info, %settings)`. `$lrr_info` for metadata plugins has
seven fields: `archive_id`, `archive_title`, `existing_tags`, `thumbnail_hash` (regenerated on
the spot via `extract_thumbnail()` if missing), `file_path`, `user_agent` (built by
`exec_login_plugin()` from `login_from`), and `oneshot_param`. The plugin returns
`tags`/`title`/`summary` (or `error`); returned tags are filtered through tag rules when
enabled, deduplicated against `existing_tags`, and written under an `archive-write:$id` lock.
Batch runs use `exec_enabled_plugins_on_file()`, which forces the `regexplugin` namespace
(`Plugin/Metadata/RegexParse.pm`) to run first.

### Script plugins

`exec_script_plugin()` passes `$lrr_info` with just `user_agent` and `oneshot_param`, then
calls `run_script(\%lrr_info, %settings)`. The return hash is free-form and surfaced as-is
through the API. This is the type used by this fork's addition,
`Plugin/Scripts/EhTagAutoUpdater.pm` (namespace `ehtag_auto_updater`): it checks the
EhTagTranslation/Database GitHub releases API, downloads `db.text.json`, applies user-configured
text replacements, and updates the system database.

### Download plugins

Triggered by URL ingestion (the `download_url` Minion task in
`lib/LANraragi/Utils/Minion.pm`). `get_downloader_for_url()` in `Utils/Plugins.pm` matches the
URL against every enabled downloader's `url_regex`; `exec_download_plugin()` then calls
`provide_url(\%lrr_info, ...)` with `$lrr_info` containing `user_agent`, `url`, and `tempdir`.
The plugin returns either `download_url` (LRR downloads it with the plugin's UserAgent) or
`file_path` (the plugin already fetched the file). Either way the result goes to
`LANraragi::Model::Upload::handle_incoming_file` with a `source:` tag of the original URL.

### Login plugins

`exec_login_plugin($namespace)` loads the plugin and its saved parameters, then calls
`do_login`. The return value must be a `Mojo::UserAgent` — anything else is logged and
discarded in favor of a fresh, anonymous UserAgent. Login plugins have no `$lrr_info`; they
receive only their configured parameters.

## Configuration Storage

Each plugin's settings live in a Redis hash named `LRR_PLUGIN_{uc namespace}` on the **config
database** (the connection from `LANraragi::Model::Config->get_redis_config`, distinct from the
archive database). `get_plugin_parameters()` in `Utils/Plugins.pm` fills in `default_value`s
first, then overlays saved values. Two parameter styles exist:

- **Positional (legacy):** `parameters` is an array; saved values are a JSON array under the
  `customargs` field, passed to the plugin as `@$settings{customargs}`.
- **Named (current):** `parameters` is a hash; each key is stored as its own field in the same
  Redis hash. A plugin declaring `to_named_params` gets its old `customargs` migrated on first
  read by `convert_to_named_params_and_persist()`.

The same hash also carries registration provenance: `installed_path`, `installed_version`,
`installed_registry`, `installed_sha256`, `type`, and the `enabled` flag.

## Managed Plugins, Registries, and Sideloads

`infer_plugin_origin()` in `Utils/Plugins.pm` classifies every plugin as `builtin` (shipped in
`Login/`, `Metadata/`, `Download/`, `Scripts/`), `managed` (installed from a registry under
`Plugin/Managed/{Type}/`, per the `MANAGED_TYPE_DIRS` map in `Utils/Registry.pm`), or
`sideloaded` (uploaded manually under `Plugin/Sideloaded/` — `Controller/Plugins.pm` creates
that directory on upload and validates the package declares a `LANraragi::Plugin::…` type).

Registries are git/CDN/local sources of a `registry.json` index, managed by
`lib/LANraragi/Model/Registry.pm` (`create_registry`, `get_registry`, `refresh_registry`,
`get_default_registry`). `Model/Setup.pm` seeds one default registry: **Ougi**
(`https://github.com/Difegue/Ougi.git`). `Utils/Registry.pm` supplies the fetching and
validation primitives (`fetch_registry_resource`, `validate_registry_index`,
`find_package_conflict`, `find_namespace_conflict`, `resolve_max_version`).

Installation is transactional: `install_plugin()` in `Model/Plugins.pm` (driven by the
`install_plugin` Minion task, serialized by an `exec_with_lock_pure` `plugin-write:{NAMESPACE}`
lock) fetches the artifact, verifies its SHA-256 against the index, validates the declared
package name against the expected `Managed/{Type}/` path, writes the file with staged rollback
(previous artifact backed up, provenance fields restored from a Lua script on failure), and
finally runs `check_plugin_loads()` — a 20-second-timeout subprocess executing
`script/check_plugin_loads.pl` to prove the module compiles. Only managed plugins can be
upgraded; cross-registry overwrites require a `force` flag. `uninstall_plugin()` deletes the
file and provenance (user settings survive) and refuses to touch builtin plugins.

## Built-in Plugin Inventory

As of the baseline commit, the 32 shipped plugins are:

- **Login (4):** `EHentai.pm`, `Fakku.pm`, `Pixiv.pm`, `nHentai.pm`
- **Metadata (21):** `Chaika.pm`, `ChaikaFile.pm`, `ComicInfo.pm`, `CopyArchiveTags.pm`,
  `CopyTags.pm`, `DateAdded.pm`, `EHDLInfo.pm`, `EHentai.pm`, `Eze.pm`, `Fakku.pm`,
  `GalleryDL.pm`, `HDoujin.pm`, `HatH.pm`, `Hentag.pm`, `Hitomi.pm`, `Koromo.pm`, `Ksk.pm`,
  `MEMS.pm`, `Pixiv.pm`, `RegexParse.pm`, `nHentai.pm`
- **Download (3):** `Chaika.pm`, `EHentai.pm`, `Pixiv.pm`
- **Scripts (4):** `EhTagAutoUpdater.pm`, `FolderToCat.pm`, `SourceFinder.pm`,
  `nHentaiSourceConverter.pm` — of which `EhTagAutoUpdater.pm` is specific to this fork rather
  than upstream LANraragi.

See [03_utils.md](03_utils.md) for the `Utils/Plugins.pm` and `Utils/Registry.pm` internals
referenced throughout this page.
