# 05 - Frontend Architecture

> Baseline commit `2094cc1d` (2026-09-04). Facts verified against code — cite-checked at generation time.

The LANraragi frontend is a hybrid stack: modern **ES Modules** for application code, loaded through a standard
[import map](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/script/type/importmap), alongside classic
`<script>` tags for legacy jQuery-based widgets (DataTables, contextMenu, file upload). This chapter describes how
scripts are loaded, the shared modules under `public/js/mod/`, the per-page scripts at the root of `public/js/`,
the Reader's client-side state machine, and the template/theme layer.

## Loading architecture

Every page template includes `templates/common/importmap.html.tt2`, which emits one `<script type="importmap">`
block mapping bare module specifiers to versioned URLs, e.g. `preact` → `/js/$version/vendor/preact.module.js`,
`react-toastify` → `/js/$version/vendor/react-toastify.esm.js`, `swiper` → `/js/$version/vendor/swiper-bundle.js`.
It also loads `es-module-shims.js` (from the `es-module-shims` npm package) asynchronously as a polyfill for
browsers without native import-map support.

Entry points follow the pattern `/js/{version}/mod/<module>.js`, where `{version}` is the `LRR_VERSION` helper
(piped into templates as `$version`, sourced from the `version` field of `package.json` via
`LANraragi::Utils::Generic`'s `get_version()`). The version is purely a cache buster: the route defined in
`lib/LANraragi/Utils/Routing.pm` matches `/js/:version/*filepath` and serves the file from `public/js/` with
`Cache-Control: public, max-age=31536000, immutable`.

Two related mechanisms round this out:

- `/js/i18n.js` is not a static file — it is rendered by `LANraragi::Controller::I18N`, which serves
  `templates/i18n.html.tt2` as `application/javascript`. The whole i18n dictionary is therefore a single ES module
  (`import I18N from "i18n"` appears in nearly every script) with no client-side i18n library.
- `lrr_baseurl` is a cookie set by the `before_dispatch` hook in `lib/LANraragi.pm` (for deployments under a path
  prefix). The `ApiURL` class in `public/js/mod/common.js` reads it and prepends the base URL to every
  app-internal URL; all API calls go through it.

The vendor ESM files under `public/js/vendor/` are **not committed** — they are bundled from `node_modules` at
install time by esbuild, driven by the `@vendor_bundle` list in `tools/install.pl`. jQuery and the other classic
scripts (`jquery.min.js`, `jquery.dataTables.min.js`, `jquery.contextMenu.min.js`, `awesomplete.min.js`,
`tippy-bundle.umd.min.js`, etc.) are loaded via plain `<script src>` tags in the page templates (see
`templates/index.html.tt2` and `templates/reader.html.tt2`) and used as globals (`$`, `tippy`, ...) from module
code. Templates typically bootstrap with an inline `<script type="module">` that imports the page's modules and
kicks off `initializeAll()` inside a `jQuery(...)` ready callback.

## Core modules: `public/js/mod/`

Nine shared modules implement all cross-page logic:

| Module | Responsibilities (verified exports) |
|---|---|
| `common.js` | DOM/string helpers shared by every page: `isUserLogged()` (reads `body[data-user-logged]`), `splitTagsByNamespace()`, `buildTagList()`, `buildTagsDiv()`, `buildThumbnailDiv()`, `buildStatusDiv()`, `buildBookmarkIconElement()`, `colorCodeTags()`, `getProgress()`, `encodeHTML()`, `convertTimestamp()`, the `ApiURL` class, `getArchiveData()` (session cache of archive data keyed by ID), and the toast/popup layer described below. |
| `server.js` | Generic API access: `callAPI()`, `callAPISilent()`, `callAPIBody()` (fetch wrappers that understand both LRR `success/error` JSON and OpenAPI-style `errors` payloads), `checkJobStatus()` (Minion job polling), `saveFormData()`, `triggerScript()`, `deleteArchive()`, `deleteTankoubon()`, `regenerateThumbnails()`, `addArchiveToCategory()`/`removeArchiveFromCategory()`, `updateTagsFromArchive()`/`updateTagsFromTankoubon()`, `loadBookmarkCategoryId()`, `updateServerSideProgress()`. |
| `index.js` | Archive Index features outside the table: category selector, quick search with Awesomplete tag suggestions (`loadTagSuggestions()`), the Swiper carousel (`toggleCarousel()`/`updateCarousel()` exports plus the internal `loadCarousel()` hitting `/api/search` variants such as `/api/search/random?count=15`), multi-select mode with Tankoubon merge (`toggleMultiSelectMode()` export plus the internal `mergeSelectionIntoTankoubon()`), version check and changelog rendering via `marked` + `DOMPurify` (`checkVersion()`, `fetchChangelog()`), localStorage→server progress migration (`migrateProgress()`). |
| `index_datatables.js` | The DataTables-backed archive table: `initializeAll()`, `doSearch()`, column renderers (`renderTitle()`, `renderTags()`), thumbnail view (`initializeThumbView()`), URL state sync (`buildURLParameters()`/`consumeURLParameters()`), row/cell callbacks. Split from `index.js` so the table layer could be swapped out independently. |
| `index_contextmenu.js` | The right-click menu on archive thumbnails: `initialize(catListData)`, delete/rating/category actions wired through `handleContextMenu()`. Records whether the menu was opened from the carousel or the table (sessionStorage `navigationState`) so the Reader can restore navigation context. |
| `reader_common.js` | Reader entrypoint and shared state (see next section). Exports `initializeAll()`, `state`, `goToPage()`, `applyContainerWidth()`, `stopAutoNextPage()`, `getCurrentChapter()`, `loadContentData()`, `toggleOverlay()`, `getArchiveForPage()`. |
| `reader_options.js` | The Reader settings panel, rendered with Preact + `htm` (`SettingsPanel()`), writing options back into `state` signals. |
| `reader_stamps.js` | Stamp/bookmark markers on Reader pages: `initializeStamps()`, `renderMarkers()`, `clearMarkers()`, `updateStamps(page)`, plus marker-mode context menu handling. |
| `reader_archive_overlay.js` | The archive info overlay (categories, table of contents, stamped-page list): `initializeArchiveOverlay()`, `toggleArchiveOverlay()`, `updateArchiveOverlay()`, `addTocSection()`, `checkStampedPages()`. |

The toast system in `common.js`'s `toast()` is explicitly a **compatibility layer** migrating the old
`jquery-toast-plugin` options object (`heading`, `text`, `icon`, `hideAfter`, ...) onto `react-toastify`,
rendering the container with Preact (`initializeToasts()`). Dialogs go through `showPopUp()`, a thin wrapper over
`sweetalert2`. Old call sites did not need to change when the underlying libraries were swapped.

Two API conventions in `server.js` are worth knowing when adding new calls:

- Responses may carry errors in either the LRR legacy shape (`{ success: 0, error }`) or the OpenAPI
  validation shape (`{ errors: [{ message }] }`); both `callAPI()` and `callAPISilent()` translate them into
  thrown `Error`s. `callAPIBody()` adds a request body and optional `Content-Type` to the same flow.
- `checkJobStatus(jobId, useDetail, callback, failureCallback, progressCallback)` polls
  `/api/minion/{id}` (or `/api/minion/{id}/detail`, which requires a logged-in user) with different intervals
  per job state: 5 s while `inactive`, 1 s while `active` (invoking `progressCallback` with the job `notes`),
  and the `finished` state triggers `callback`. It recurses via `setTimeout`, so page navigation simply stops
  the polling. This is the client-side counterpart of every long-running Minion operation (thumbnail
  regeneration, plugin runs, backups).

## Page scripts: `public/js/*.js`

Each admin page has a small root-level ES module that imports the shared modules and wires its page-specific
DOM. All follow the same shape (`import * as Server from "./mod/server.js"; import * as LRR from "./mod/common.js";`
+ an `initializeAll()` on jQuery ready):

| Script | Page |
|---|---|
| `backup.js` | Backup import/export (blueimp jQuery-File-Upload for restore files). |
| `batch.js` | Batch tag/plugin operations. |
| `category.js` | Category management. |
| `config.js` | Server configuration (all settings tabs). |
| `duplicates.js` | Duplicate detection UI. |
| `edit.js` | Archive metadata editing; tag input via `@jcubic/tagger` and SortableJS tag ordering, both loaded as classic globals (`tagger.js`, `Sortable.min.js`) by `templates/edit.html.tt2`. |
| `logs.js` | Log viewer. |
| `plugins.js` | Plugin management and upload. |
| `reader.js` | One-line re-export: `export { initializeAll } from "./mod/reader_common.js";` — kept so `templates/reader.html.tt2` can load a stable URL while the implementation lives in `mod/`. |
| `stats.js` | Statistics dashboard (jqCloud via `templates/stats.html.tt2`). |
| `upload.js` | Upload page (jQuery-File-Upload). |

## The Reader

`public/js/mod/reader_common.js` is the largest client module. Its exported `state` object is the reader's single
source of truth. Plain fields hold volatile data (`currentPage`, `pages`, `maxPage`, `archiveIds`,
`spaceScroll`, `preloadedImg`), while user preferences are **Preact signals** persisted to `localStorage` on
write: `containerWidth`, `mangaMode`, `doublePageMode`, `ignoreProgress`, `infiniteScroll`, `fitMode`,
`hideHeader`, `showOverlayByDefault`, `preloadCount`, `AutoNextPageInterval`, `markersVisible`. This is why the
settings panel and stamps module can react to toggles without manual event plumbing (`reader_stamps.js` uses
`effect()` from `@preact/signals` to re-render markers when `markersVisible` changes).

Keyboard handling lives in `handleShortcuts()`, bound to both `keyup` and (spacebar-only) `keydown`:
arrows/`a`/`d` page turn (shift = first/last), spacebar smooth-scroll with configurable snap
(`state.scrollConfig`), `b` bookmark, `f` fullscreen (via `fscreen`), `g` go-to-page prompt, `h` help, `m` manga
reading direction, `n` auto-next-page timer, `o` settings overlay, `p` double-page mode, `q` archive overlay,
`r` random archive, backspace returns to index, `,`/`.` jump to previous/next archive.

Reading progress is reported by `updateProgress()` with a three-way policy mirrored from server settings passed
by the template (`trackProgressLocally`, `authenticateProgress`):

- authenticated + logged in → `Server.updateServerSideProgress()` in `mod/server.js`, which issues
  `PUT /api/archives/{id}/progress/{page}` (or `/api/tankoubons/TANK_.../progress/{page}` for tanks) and
  tolerates the 423 returned when Redis is briefly locked;
- local tracking → `localStorage.setItem("<id>-reader", page)`;
- unauthenticated server tracking → same PUT without auth.

Image prefetching is `preloadImages()`: it fetches the next `state.preloadCount.value` pages (doubled in
double-page mode, plus one previous page) as blobs via `loadImage()` and keeps `URL.createObjectURL()` results in
`state.preloadedImg`, recording byte sizes in `state.preloadedSizes` for the fileinfo display. Cross-archive
next/prev navigation (`readNextArchive()`/`readPreviousArchive()`) restores the originating DataTables page from
`localStorage` keys such as `currArchiveIds`/`nextArchiveIds` so the user lands back where they started.

## Frontend dependencies

Versions below are copied verbatim from `package.json` at the baseline commit (`^` ranges as declared — treat
`package.json` as the source of truth). Only entries with direct frontend usage are listed:

| Package | Version (per `package.json`) | Used for |
|---|---|---|
| `preact` / `@preact/signals` | `^10.29.2` / `^2.9.2` | UI fragments (settings panel, toasts), reactive reader state. |
| `react-toastify` | `9.0.0-rc-2` | Toast notifications behind the compat layer. |
| `sweetalert2` | `11.22.4` | Confirm/input dialogs (`showPopUp()`). |
| `jquery` | `3.6.0` | Legacy DOM/event layer, still imported as a global. |
| `datatables.net` | `1.11.5` | Archive index table (`index_datatables.js`). |
| `jquery-contextmenu` | `2.9.2` | Right-click menus on index and reader stamps. |
| `swiper` | `^14.0.2` | Index carousel and multi-select carousel. |
| `marked` + `dompurify` | `^18.0.4` + `^3.4.13` | Rendering the GitHub changelog markdown safely. |
| `awesomplete` | `1.1.5` | Tag search autocompletion. |
| `@jcubic/tagger` | `0.4.2` | Tag input on the edit page. |
| `sortablejs` | `1.15.6` | Drag-ordering tag rules/entries. |
| `tippy.js` | `6.3.7` | Tag tooltips (`buildTagTooltip()`). |
| `fscreen` | `1.2.0` | Fullscreen API wrapper. |
| `blueimp-file-upload` | `10.32.0` | Upload/backup/restore file widgets. |
| `clsx` / `htm` | `1.1.1` / `^3.1.1` | Class strings / JSX-free Preact templating. |
| `es-module-shims` | `^2.8.2` | Import-map polyfill. |
| `jqcloud2` / `clipboard` / `allcollapsible` / `raty-js` / `geist` / `inter-ui` / `@fortawesome/fontawesome-free` | `2.0.3` / `2.0.11` / `1.1.0` / `^4.3.0` / `1.0.0` / `3.19.3` / `^6.7.2` | Tag cloud (stats), clipboard button, collapsible sections, star ratings (reader), fonts, icons. |

On the i18n side, templates translate server-side strings at render time with `c.lh(...)` (see
`templates/i18n.html.tt2`, which turns those lookups into the `I18N` dictionary served at `/js/i18n.js`);
client-side scripts interpolate through generated template functions (e.g. `I18N.CleanDatabaseMsg(data.deleted)`
in `server.js`'s `cleanDatabase()`), so page scripts rarely hard-code user-visible text.

## Templates and themes

- `templates/` holds 26 files: 24 Template Toolkit templates (`.tt2`) plus 2 production error pages
  (`exception.production.html.ep`, `not_found.production.html.ep` rendered by Mojolicious' `.ep` handler).
  `templates/config.html.tt2` composes the six settings tabs from `templates/templates_config/`
  (`config_global`, `config_theme`, `config_security`, `config_files`, `config_tags`, `config_shinobu`).
  The app sets Template Toolkit as its default renderer in `lib/LANraragi.pm` (`default_handler('tt2')`).
- Themes are plain stylesheets in `public/themes/` — five at baseline: `ex.css`, `g.css`, `modern.css`,
  `modern_clear.css`, `modern_red.css`. `generate_themes_header()` in `lib/LANraragi/Utils/Generic.pm` emits a
  `<link>` for each (default) or `alternate stylesheet` (others), tagged with friendly names
  (Sad Panda, H-Verse, Hachikuji, Yotsugi, Nadeko respectively); the selected one is stored as the `theme` key in
  the config database. Any CSS file dropped into the folder is automatically pickable.
- Shared page chrome (`lrr.css`, `config.css` and vendor CSS) lives under `public/css/`.
