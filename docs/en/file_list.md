# LANraragi Project File List

> Auto-generated from `git ls-files` — do not edit by hand. Baseline commit `2094cc1d`, 2026-09-04.

## File Statistics

| Type | Count |
|------|------|
| Perl modules (.pm) | 101 |
| Perl scripts/tests (.pl, .t) | 45 |
| JavaScript (.js) | 25 |
| Templates (.tt2, .ep) | 26 |
| Translations (.po) | 14 |
| Styles (.css) | 7 |
| Docs (.md) | 70 |
| Shell/PowerShell (.sh, .ps1) | 9 |
| Other | 184 |

**Total tracked files: 481**

## Files by Area

### Server entry & config (3)

- `lib/LANraragi.pm`
- `lib/Shinobu.pm`
- `lrr.conf`

### lib/LANraragi/Controller (pages) (26)

- `lib/LANraragi/Controller/Api/Archive.pm`
- `lib/LANraragi/Controller/Api/Category.pm`
- `lib/LANraragi/Controller/Api/Database.pm`
- `lib/LANraragi/Controller/Api/Metrics.pm`
- `lib/LANraragi/Controller/Api/Minion.pm`
- `lib/LANraragi/Controller/Api/Other.pm`
- `lib/LANraragi/Controller/Api/Plugins.pm`
- `lib/LANraragi/Controller/Api/Registry.pm`
- `lib/LANraragi/Controller/Api/Search.pm`
- `lib/LANraragi/Controller/Api/Shinobu.pm`
- `lib/LANraragi/Controller/Api/Stamp.pm`
- `lib/LANraragi/Controller/Api/Tankoubon.pm`
- `lib/LANraragi/Controller/Backup.pm`
- `lib/LANraragi/Controller/Batch.pm`
- `lib/LANraragi/Controller/Category.pm`
- `lib/LANraragi/Controller/Config.pm`
- `lib/LANraragi/Controller/Duplicates.pm`
- `lib/LANraragi/Controller/Edit.pm`
- `lib/LANraragi/Controller/I18N.pm`
- `lib/LANraragi/Controller/Index.pm`
- `lib/LANraragi/Controller/Logging.pm`
- `lib/LANraragi/Controller/Login.pm`
- `lib/LANraragi/Controller/Plugins.pm`
- `lib/LANraragi/Controller/Reader.pm`
- `lib/LANraragi/Controller/Stats.pm`
- `lib/LANraragi/Controller/Upload.pm`

### lib/LANraragi/Model (16)

- `lib/LANraragi/Model/Archive.pm`
- `lib/LANraragi/Model/Backup.pm`
- `lib/LANraragi/Model/Category.pm`
- `lib/LANraragi/Model/Config.pm`
- `lib/LANraragi/Model/Metrics.pm`
- `lib/LANraragi/Model/Opds.pm`
- `lib/LANraragi/Model/Plugins.pm`
- `lib/LANraragi/Model/Reader.pm`
- `lib/LANraragi/Model/Registry.pm`
- `lib/LANraragi/Model/Search.pm`
- `lib/LANraragi/Model/Server.pm`
- `lib/LANraragi/Model/Setup.pm`
- `lib/LANraragi/Model/Stamp.pm`
- `lib/LANraragi/Model/Stats.pm`
- `lib/LANraragi/Model/Tankoubon.pm`
- `lib/LANraragi/Model/Upload.pm`

### lib/LANraragi/Utils (24)

- `lib/LANraragi/Utils/Archive.pm`
- `lib/LANraragi/Utils/Database.pm`
- `lib/LANraragi/Utils/Generic.pm`
- `lib/LANraragi/Utils/I18N.pm`
- `lib/LANraragi/Utils/I18NInitializer.pm`
- `lib/LANraragi/Utils/ImageMagickResizer.pm`
- `lib/LANraragi/Utils/Logging.pm`
- `lib/LANraragi/Utils/Login.pm`
- `lib/LANraragi/Utils/Metrics.pm`
- `lib/LANraragi/Utils/Minion.pm`
- `lib/LANraragi/Utils/OpenAPI.pm`
- `lib/LANraragi/Utils/PageCache.pm`
- `lib/LANraragi/Utils/Path.pm`
- `lib/LANraragi/Utils/Plugins.pm`
- `lib/LANraragi/Utils/Redis.pm`
- `lib/LANraragi/Utils/Registry.pm`
- `lib/LANraragi/Utils/Resizer.pm`
- `lib/LANraragi/Utils/RotatingLog.pm`
- `lib/LANraragi/Utils/Routing.pm`
- `lib/LANraragi/Utils/String.pm`
- `lib/LANraragi/Utils/Tags.pm`
- `lib/LANraragi/Utils/TempFolder.pm`
- `lib/LANraragi/Utils/Vips.pm`
- `lib/LANraragi/Utils/VipsResizer.pm`

### lib/LANraragi/Plugin/Login (4)

- `lib/LANraragi/Plugin/Login/EHentai.pm`
- `lib/LANraragi/Plugin/Login/Fakku.pm`
- `lib/LANraragi/Plugin/Login/Pixiv.pm`
- `lib/LANraragi/Plugin/Login/nHentai.pm`

### lib/LANraragi/Plugin/Metadata (21)

- `lib/LANraragi/Plugin/Metadata/Chaika.pm`
- `lib/LANraragi/Plugin/Metadata/ChaikaFile.pm`
- `lib/LANraragi/Plugin/Metadata/ComicInfo.pm`
- `lib/LANraragi/Plugin/Metadata/CopyArchiveTags.pm`
- `lib/LANraragi/Plugin/Metadata/CopyTags.pm`
- `lib/LANraragi/Plugin/Metadata/DateAdded.pm`
- `lib/LANraragi/Plugin/Metadata/EHDLInfo.pm`
- `lib/LANraragi/Plugin/Metadata/EHentai.pm`
- `lib/LANraragi/Plugin/Metadata/Eze.pm`
- `lib/LANraragi/Plugin/Metadata/Fakku.pm`
- `lib/LANraragi/Plugin/Metadata/GalleryDL.pm`
- `lib/LANraragi/Plugin/Metadata/HDoujin.pm`
- `lib/LANraragi/Plugin/Metadata/HatH.pm`
- `lib/LANraragi/Plugin/Metadata/Hentag.pm`
- `lib/LANraragi/Plugin/Metadata/Hitomi.pm`
- `lib/LANraragi/Plugin/Metadata/Koromo.pm`
- `lib/LANraragi/Plugin/Metadata/Ksk.pm`
- `lib/LANraragi/Plugin/Metadata/MEMS.pm`
- `lib/LANraragi/Plugin/Metadata/Pixiv.pm`
- `lib/LANraragi/Plugin/Metadata/RegexParse.pm`
- `lib/LANraragi/Plugin/Metadata/nHentai.pm`

### lib/LANraragi/Plugin/Download (3)

- `lib/LANraragi/Plugin/Download/Chaika.pm`
- `lib/LANraragi/Plugin/Download/EHentai.pm`
- `lib/LANraragi/Plugin/Download/Pixiv.pm`

### lib/LANraragi/Plugin/Scripts (4)

- `lib/LANraragi/Plugin/Scripts/EhTagAutoUpdater.pm`
- `lib/LANraragi/Plugin/Scripts/FolderToCat.pm`
- `lib/LANraragi/Plugin/Scripts/SourceFinder.pm`
- `lib/LANraragi/Plugin/Scripts/nHentaiSourceConverter.pm`

### public/js (page scripts) (21)

- `public/js/.gitignore`
- `public/js/backup.js`
- `public/js/batch.js`
- `public/js/category.js`
- `public/js/config.js`
- `public/js/duplicates.js`
- `public/js/edit.js`
- `public/js/logs.js`
- `public/js/mod/common.js`
- `public/js/mod/index.js`
- `public/js/mod/index_contextmenu.js`
- `public/js/mod/index_datatables.js`
- `public/js/mod/reader_archive_overlay.js`
- `public/js/mod/reader_common.js`
- `public/js/mod/reader_options.js`
- `public/js/mod/reader_stamps.js`
- `public/js/mod/server.js`
- `public/js/plugins.js`
- `public/js/reader.js`
- `public/js/stats.js`
- `public/js/upload.js`

### public/themes (5)

- `public/themes/ex.css`
- `public/themes/g.css`
- `public/themes/modern.css`
- `public/themes/modern_clear.css`
- `public/themes/modern_red.css`

### templates (26)

- `templates/backup.html.tt2`
- `templates/batch.html.tt2`
- `templates/category.html.tt2`
- `templates/common/importmap.html.tt2`
- `templates/config.html.tt2`
- `templates/duplicates.html.tt2`
- `templates/edit.html.tt2`
- `templates/exception.production.html.ep`
- `templates/footer.html.tt2`
- `templates/i18n.html.tt2`
- `templates/index.html.tt2`
- `templates/login.html.tt2`
- `templates/logs.html.tt2`
- `templates/not_found.production.html.ep`
- `templates/opds.html.tt2`
- `templates/opds_entry.html.tt2`
- `templates/plugins.html.tt2`
- `templates/reader.html.tt2`
- `templates/stats.html.tt2`
- `templates/templates_config/config_files.html.tt2`
- `templates/templates_config/config_global.html.tt2`
- `templates/templates_config/config_security.html.tt2`
- `templates/templates_config/config_shinobu.html.tt2`
- `templates/templates_config/config_tags.html.tt2`
- `templates/templates_config/config_theme.html.tt2`
- `templates/upload.html.tt2`

### locales/template (14)

- `locales/template/as.po`
- `locales/template/de.po`
- `locales/template/en.po`
- `locales/template/es.po`
- `locales/template/fr.po`
- `locales/template/id.po`
- `locales/template/it.po`
- `locales/template/ja.po`
- `locales/template/ko.po`
- `locales/template/nb_NO.po`
- `locales/template/pt.po`
- `locales/template/vi.po`
- `locales/template/zh.po`
- `locales/template/zh_Hant.po`

### tests (96)

- `tests/LANraragi/Model/Plugins.t`
- `tests/LANraragi/Plugin/Metadata/Chaika.t`
- `tests/LANraragi/Plugin/Metadata/ChaikaFile.t`
- `tests/LANraragi/Plugin/Metadata/ComicInfo.t`
- `tests/LANraragi/Plugin/Metadata/CopyArchiveTags.t`
- `tests/LANraragi/Plugin/Metadata/EHDLInfo.t`
- `tests/LANraragi/Plugin/Metadata/EHentai.t`
- `tests/LANraragi/Plugin/Metadata/Eze.t`
- `tests/LANraragi/Plugin/Metadata/Fakku.t`
- `tests/LANraragi/Plugin/Metadata/GalleryDL.t`
- `tests/LANraragi/Plugin/Metadata/Generic.t`
- `tests/LANraragi/Plugin/Metadata/HatH.t`
- `tests/LANraragi/Plugin/Metadata/Hentag.t`
- `tests/LANraragi/Plugin/Metadata/Hitomi.t`
- `tests/LANraragi/Plugin/Metadata/Koromo.t`
- `tests/LANraragi/Plugin/Metadata/Ksk.t`
- `tests/LANraragi/Plugin/Metadata/Pixiv.t`
- `tests/LANraragi/Plugin/Metadata/RegexParse.t`
- `tests/LANraragi/Plugin/Metadata/nHentai.t`
- `tests/LANraragi/Utils/Archive.t`
- `tests/LANraragi/Utils/Generic.t`
- `tests/LANraragi/Utils/ImageMagickResizer.t`
- `tests/LANraragi/Utils/Logging.t`
- `tests/LANraragi/Utils/Metrics.t`
- `tests/LANraragi/Utils/Path.t`
- `tests/LANraragi/Utils/Registry.t`
- `tests/LANraragi/Utils/Routing.t`
- `tests/LANraragi/Utils/String.t`
- `tests/LANraragi/Utils/Tags.t`
- `tests/LANraragi/Utils/Vips.t`
- `tests/LANraragi/Utils/VipsResizer.t`
- `tests/backup.t`
- `tests/category.t`
- `tests/cbw.t`
- `tests/mocks.pl`
- `tests/modules.t`
- `tests/opds.t`
- `tests/plugins.t`
- `tests/samples/chaika/001_gid_27240.json`
- `tests/samples/chaika/002_sha1_response.json`
- `tests/samples/comicinfo/00_sample.xml`
- `tests/samples/comicinfo/01_sample.xml`
- `tests/samples/comicinfo/02_sample.xml`
- `tests/samples/comicinfo/03_sample.xml`
- `tests/samples/doc.pdf`
- `tests/samples/eh/001_gid-1866546.json`
- `tests/samples/eh/002_search_results.html`
- `tests/samples/ehdl/info_flat.txt`
- `tests/samples/ehdl/info_invalid.txt`
- `tests/samples/ehdl/info_original.txt`
- `tests/samples/ehdl/info_pipe.txt`
- `tests/samples/ehdl/info_translated.txt`
- `tests/samples/eze/eze_broken.json`
- `tests/samples/eze/eze_full_sample.json`
- `tests/samples/eze/eze_lite_sample.json`
- `tests/samples/fakku/001_search_response.html`
- `tests/samples/fakku/002_gallery_front.html`
- `tests/samples/gallerydl/gallerydl_arrayfulltags_sample.json`
- `tests/samples/gallerydl/gallerydl_arraysingletags_sample.json`
- `tests/samples/gallerydl/gallerydl_broken.json`
- `tests/samples/gallerydl/gallerydl_hashtags_sample.json`
- `tests/samples/hath/galleryinfo.txt`
- `tests/samples/hentag/00_sample.json`
- `tests/samples/hentag/01_sample.json`
- `tests/samples/hentag/02_search_response.json`
- `tests/samples/hentag/03_search_response_multiple.json`
- `tests/samples/hentag/04_search_response_multiple_same_language.json`
- `tests/samples/hentag/05_search_response_multiple_similar_titles.json`
- `tests/samples/hitomi/2261881.js`
- `tests/samples/koromo/koromo_multiauthor.json`
- `tests/samples/koromo/koromo_multimag.json`
- `tests/samples/koromo/koromo_sample.json`
- `tests/samples/ksk/fake.yaml`
- `tests/samples/ksk/fake_koharu.yaml`
- `tests/samples/nh/001_search_results.json`
- `tests/samples/nh/002_search_results_empty.json`
- `tests/samples/nh/003_gid_52249.json`
- `tests/samples/opds/opds_sample.xml`
- `tests/samples/pixiv/ajax/illust.json`
- `tests/samples/pixiv/ajax/manga_1.json`
- `tests/samples/pixiv/ajax/manga_2.json`
- `tests/samples/pixiv/illust_pixiv_comment_unescaped.txt`
- `tests/samples/pixiv/manga_1_pixiv_comment_unescaped.txt`
- `tests/samples/pixiv/manga_2_pixiv_comment_unescaped.txt`
- `tests/samples/pixiv/manga_2_pixiv_comment_with_script.txt`
- `tests/samples/pixiv/ssr/illust.html`
- `tests/samples/pixiv/ssr/manga_1.html`
- `tests/samples/pixiv/ssr/manga_2.html`
- `tests/samples/reader.jpg`
- `tests/samples/routing/js/ok.txt`
- `tests/samples/routing/js/safe/ok2.txt`
- `tests/samples/routing/secret.txt`
- `tests/samples/sample.cbw`
- `tests/search.t`
- `tests/stamp.t`
- `tests/tankoubon.t`

### script (5)

- `script/backup`
- `script/check_plugin_loads.pl`
- `script/get_version`
- `script/lanraragi`
- `script/launcher.pl`

### tools/openapi.yaml (1)

- `tools/openapi.yaml`

### tools/build (33)

- `tools/build/docker/Dockerfile`
- `tools/build/docker/Dockerfile-dev`
- `tools/build/docker/docker-compose.yml`
- `tools/build/docker/install-perl-deps.sh`
- `tools/build/docker/redis.conf`
- `tools/build/docker/s6/cont-init.d/01-lrr-setup`
- `tools/build/docker/s6/fix-attrs.d/01-lrr-dirs`
- `tools/build/docker/s6/s6-rc.d/init/type`
- `tools/build/docker/s6/s6-rc.d/init/up`
- `tools/build/docker/s6/s6-rc.d/lanraragi/dependencies.d/init`
- `tools/build/docker/s6/s6-rc.d/lanraragi/dependencies.d/redis`
- `tools/build/docker/s6/s6-rc.d/lanraragi/finish`
- `tools/build/docker/s6/s6-rc.d/lanraragi/run`
- `tools/build/docker/s6/s6-rc.d/lanraragi/type`
- `tools/build/docker/s6/s6-rc.d/redis/dependencies.d/init`
- `tools/build/docker/s6/s6-rc.d/redis/run`
- `tools/build/docker/s6/s6-rc.d/redis/type`
- `tools/build/docker/s6/s6-rc.d/user/contents.d/init`
- `tools/build/docker/s6/s6-rc.d/user/contents.d/lanraragi`
- `tools/build/docker/s6/s6-rc.d/user/contents.d/redis`
- `tools/build/homebrew/Lanraragi.rb`
- `tools/build/homebrew/lanraragi`
- `tools/build/homebrew/redis.conf`
- `tools/build/windows/Karen`
- `tools/build/windows/build-installer.ps1`
- `tools/build/windows/cleanup.sh`
- `tools/build/windows/create-dist.sh`
- `tools/build/windows/install-deps.sh`
- `tools/build/windows/install.sh`
- `tools/build/windows/perl.exe.manifest`
- `tools/build/windows/redis.conf`
- `tools/build/windows/run.ps1`
- `tools/build/windows/utf8-support.ps1`

### tools/Documentation (104)

- `tools/Documentation/.gitbook.yaml`
- `tools/Documentation/.gitbook/assets/add-chapter.png`
- `tools/Documentation/.gitbook/assets/archive_list.png`
- `tools/Documentation/.gitbook/assets/archive_thumb.png`
- `tools/Documentation/.gitbook/assets/backup.png`
- `tools/Documentation/.gitbook/assets/batch.png`
- `tools/Documentation/.gitbook/assets/batchlog.png`
- `tools/Documentation/.gitbook/assets/bookmark_button.png`
- `tools/Documentation/.gitbook/assets/bookmark_config.png`
- `tools/Documentation/.gitbook/assets/brew.jpg`
- `tools/Documentation/.gitbook/assets/categories.png`
- `tools/Documentation/.gitbook/assets/category_filtered.png`
- `tools/Documentation/.gitbook/assets/cfg.png`
- `tools/Documentation/.gitbook/assets/cfg_plugin.png`
- `tools/Documentation/.gitbook/assets/chapters.jpg`
- `tools/Documentation/.gitbook/assets/chapters_sicp.jpg`
- `tools/Documentation/.gitbook/assets/cloud.PNG`
- `tools/Documentation/.gitbook/assets/download.png`
- `tools/Documentation/.gitbook/assets/downloaders.png`
- `tools/Documentation/.gitbook/assets/duplicates.png`
- `tools/Documentation/.gitbook/assets/dureader.jpg`
- `tools/Documentation/.gitbook/assets/edit.png`
- `tools/Documentation/.gitbook/assets/favtags.jpg`
- `tools/Documentation/.gitbook/assets/ichaival.png`
- `tools/Documentation/.gitbook/assets/jails.jpg`
- `tools/Documentation/.gitbook/assets/karen-dark.png`
- `tools/Documentation/.gitbook/assets/karen-light.png`
- `tools/Documentation/.gitbook/assets/karen-startmenu.png`
- `tools/Documentation/.gitbook/assets/karen.png`
- `tools/Documentation/.gitbook/assets/login.png`
- `tools/Documentation/.gitbook/assets/lrr_react.jpg`
- `tools/Documentation/.gitbook/assets/metrics_settings.png`
- `tools/Documentation/.gitbook/assets/mountpoints.jpg`
- `tools/Documentation/.gitbook/assets/msm.png`
- `tools/Documentation/.gitbook/assets/opds.jpg`
- `tools/Documentation/.gitbook/assets/openssl-error.png`
- `tools/Documentation/.gitbook/assets/ratings.png`
- `tools/Documentation/.gitbook/assets/reader.jpg`
- `tools/Documentation/.gitbook/assets/reader_options.png`
- `tools/Documentation/.gitbook/assets/reader_overlay.jpg`
- `tools/Documentation/.gitbook/assets/search.png`
- `tools/Documentation/.gitbook/assets/shell.jpg`
- `tools/Documentation/.gitbook/assets/shiggy.png`
- `tools/Documentation/.gitbook/assets/stamp-toggle.jpg`
- `tools/Documentation/.gitbook/assets/stamps.jpg`
- `tools/Documentation/.gitbook/assets/tachiyomi.jpg`
- `tools/Documentation/.gitbook/assets/tank_creation.jpg`
- `tools/Documentation/.gitbook/assets/tank_edition.png`
- `tools/Documentation/.gitbook/assets/themes.png`
- `tools/Documentation/.gitbook/assets/thumbchange.png`
- `tools/Documentation/.gitbook/assets/uploading.png`
- `tools/Documentation/.gitbook/assets/utf8-popup.png`
- `tools/Documentation/.gitbook/assets/utf8-region.png`
- `tools/Documentation/.gitbook/assets/utf8-restart.png`
- `tools/Documentation/.gitbook/assets/webext.png`
- `tools/Documentation/README.md`
- `tools/Documentation/SUMMARY.md`
- `tools/Documentation/advanced-usage/backup-and-restore.md`
- `tools/Documentation/advanced-usage/batch-tagging.md`
- `tools/Documentation/advanced-usage/downloading.md`
- `tools/Documentation/advanced-usage/duplicate-detection.md`
- `tools/Documentation/advanced-usage/external-readers.md`
- `tools/Documentation/advanced-usage/network-interfaces.md`
- `tools/Documentation/advanced-usage/plugin-registries.md`
- `tools/Documentation/advanced-usage/proxy-setup.md`
- `tools/Documentation/advanced-usage/stamps.md`
- `tools/Documentation/advanced-usage/tag-rules.md`
- `tools/Documentation/advanced-usage/tankoubons-and-chapters.md`
- `tools/Documentation/api-documentation/archive-api.md`
- `tools/Documentation/api-documentation/category-api.md`
- `tools/Documentation/api-documentation/database-api.md`
- `tools/Documentation/api-documentation/getting-started.md`
- `tools/Documentation/api-documentation/minion-api.md`
- `tools/Documentation/api-documentation/miscellaneous-other-api.md`
- `tools/Documentation/api-documentation/opds-catalog.md`
- `tools/Documentation/api-documentation/plugin-api.md`
- `tools/Documentation/api-documentation/registry-api.md`
- `tools/Documentation/api-documentation/search-api.md`
- `tools/Documentation/api-documentation/shinobu-api.md`
- `tools/Documentation/api-documentation/stamp-api.md`
- `tools/Documentation/api-documentation/tankoubon-api.md`
- `tools/Documentation/basic-operations/archives.md`
- `tools/Documentation/basic-operations/categories.md`
- `tools/Documentation/basic-operations/first-steps.md`
- `tools/Documentation/basic-operations/metadata.md`
- `tools/Documentation/basic-operations/searching.md`
- `tools/Documentation/basic-operations/stats.md`
- `tools/Documentation/basic-operations/themes.md`
- `tools/Documentation/extending-lanraragi/architecture.md`
- `tools/Documentation/extending-lanraragi/index.md`
- `tools/Documentation/extending-lanraragi/translations.md`
- `tools/Documentation/installing-lanraragi/community.md`
- `tools/Documentation/installing-lanraragi/docker.md`
- `tools/Documentation/installing-lanraragi/jail.md`
- `tools/Documentation/installing-lanraragi/macos.md`
- `tools/Documentation/installing-lanraragi/methods.md`
- `tools/Documentation/installing-lanraragi/source.md`
- `tools/Documentation/installing-lanraragi/windows.md`
- `tools/Documentation/plugin-docs/code-examples.md`
- `tools/Documentation/plugin-docs/download.md`
- `tools/Documentation/plugin-docs/index.md`
- `tools/Documentation/plugin-docs/login.md`
- `tools/Documentation/plugin-docs/metadata.md`
- `tools/Documentation/plugin-docs/scripts.md`

### Root files (9)

- `.devcontainer/Dockerfile`
- `.devcontainer/devcontainer.json`
- `CONTRIBUTING.md`
- `COPYING`
- `README.md`
- `eslint.config.mjs`
- `package-lock.json`
- `package.json`
- `redocly.yml`

### Other (66)

- `.dockerignore`
- `.gitattributes`
- `.github/FUNDING.yml`
- `.github/ISSUE_TEMPLATE/feature-request-suggestion.md`
- `.github/ISSUE_TEMPLATE/problem-report.md`
- `.github/action-run-tests/Dockerfile`
- `.github/action-run-tests/entrypoint.sh`
- `.github/actions/docker-builder/action.yml`
- `.github/actions/docker-merge/action.yml`
- `.github/holopin.yml`
- `.github/workflows/push-brewtest.yml`
- `.github/workflows/push-continous-delivery.yml`
- `.github/workflows/push-continuous-integration.yml`
- `.github/workflows/release-delivery.yml`
- `.gitignore`
- `.gitmodules`
- `.perlcriticrc`
- `.perltidyrc`
- `docs/README.md`
- `docs/en/01_data_layer.md`
- `docs/en/02_api.md`
- `docs/en/03_utils.md`
- `docs/en/04_plugins.md`
- `docs/en/05_frontend.md`
- `docs/en/06_models.md`
- `docs/en/07_i18n.md`
- `docs/en/08_build.md`
- `docs/generate_docs.py`
- `docs/zh-CN/01_data_layer.md`
- `docs/zh-CN/02_api.md`
- `docs/zh-CN/03_utils.md`
- `docs/zh-CN/04_plugins.md`
- `docs/zh-CN/05_frontend.md`
- `docs/zh-CN/06_models.md`
- `docs/zh-CN/07_i18n.md`
- `docs/zh-CN/08_build.md`
- `lib/Worker.pm`
- `log/.gitignore`
- `public/.gitignore`
- `public/app.webappmanifest`
- `public/css/.gitignore`
- `public/css/config.css`
- `public/css/lrr.css`
- `public/favicon.ico`
- `public/img/.gitignore`
- `public/img/empty.png`
- `public/img/flubbed.gif`
- `public/img/logo.png`
- `public/img/noThumb.png`
- `public/img/notfound.jpg`
- `public/img/theme_preview/ex.png`
- `public/img/theme_preview/g.png`
- `public/img/theme_preview/modern.png`
- `public/img/theme_preview/modern_clear.png`
- `public/img/theme_preview/modern_red.png`
- `public/img/wait_warmly.jpg`
- `public/robots.txt`
- `tools/cpanfile`
- `tools/generate_registry.pl`
- `tools/install.pl`
- `tools/k6/covers_cold.js`
- `tools/k6/page_fetching.js`
- `tools/k6/single_archive_cold.js`
- `tools/k6/single_archive_warm.js`
- `tools/lanraragi-systemd.service`
- `tools/repository-open-graph-template.jpg`

