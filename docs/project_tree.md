# LANraragi Project Tree

> Auto-generated from `git ls-files` — do not edit by hand.
> Baseline commit `2094cc1d`, 2026-09-04. Total tracked files: 481.

```
├── .devcontainer
│   ├── devcontainer.json
│   └── Dockerfile
├── .dockerignore
├── .gitattributes
├── .github
│   ├── action-run-tests
│   │   ├── Dockerfile
│   │   └── entrypoint.sh
│   ├── actions
│   │   ├── docker-builder
│   │   │   └── action.yml
│   │   └── docker-merge
│   │       └── action.yml
│   ├── FUNDING.yml
│   ├── holopin.yml
│   ├── ISSUE_TEMPLATE
│   │   ├── feature-request-suggestion.md
│   │   └── problem-report.md
│   └── workflows
│       ├── push-brewtest.yml
│       ├── push-continous-delivery.yml
│       ├── push-continuous-integration.yml
│       └── release-delivery.yml
├── .gitignore
├── .gitmodules
├── .perlcriticrc
├── .perltidyrc
├── CONTRIBUTING.md
├── COPYING
├── docs
│   ├── en
│   │   ├── 01_data_layer.md
│   │   ├── 02_api.md
│   │   ├── 03_utils.md
│   │   ├── 04_plugins.md
│   │   ├── 05_frontend.md
│   │   ├── 06_models.md
│   │   ├── 07_i18n.md
│   │   └── 08_build.md
│   ├── generate_docs.py
│   ├── README.md
│   └── zh-CN
│       ├── 01_data_layer.md
│       ├── 02_api.md
│       ├── 03_utils.md
│       ├── 04_plugins.md
│       ├── 05_frontend.md
│       ├── 06_models.md
│       ├── 07_i18n.md
│       └── 08_build.md
├── eslint.config.mjs
├── lib
│   ├── LANraragi
│   │   ├── Controller
│   │   │   ├── Api
│   │   │   │   ├── Archive.pm
│   │   │   │   ├── Category.pm
│   │   │   │   ├── Database.pm
│   │   │   │   ├── Metrics.pm
│   │   │   │   ├── Minion.pm
│   │   │   │   ├── Other.pm
│   │   │   │   ├── Plugins.pm
│   │   │   │   ├── Registry.pm
│   │   │   │   ├── Search.pm
│   │   │   │   ├── Shinobu.pm
│   │   │   │   ├── Stamp.pm
│   │   │   │   └── Tankoubon.pm
│   │   │   ├── Backup.pm
│   │   │   ├── Batch.pm
│   │   │   ├── Category.pm
│   │   │   ├── Config.pm
│   │   │   ├── Duplicates.pm
│   │   │   ├── Edit.pm
│   │   │   ├── I18N.pm
│   │   │   ├── Index.pm
│   │   │   ├── Logging.pm
│   │   │   ├── Login.pm
│   │   │   ├── Plugins.pm
│   │   │   ├── Reader.pm
│   │   │   ├── Stats.pm
│   │   │   └── Upload.pm
│   │   ├── Model
│   │   │   ├── Archive.pm
│   │   │   ├── Backup.pm
│   │   │   ├── Category.pm
│   │   │   ├── Config.pm
│   │   │   ├── Metrics.pm
│   │   │   ├── Opds.pm
│   │   │   ├── Plugins.pm
│   │   │   ├── Reader.pm
│   │   │   ├── Registry.pm
│   │   │   ├── Search.pm
│   │   │   ├── Server.pm
│   │   │   ├── Setup.pm
│   │   │   ├── Stamp.pm
│   │   │   ├── Stats.pm
│   │   │   ├── Tankoubon.pm
│   │   │   └── Upload.pm
│   │   ├── Plugin
│   │   │   ├── Download
│   │   │   │   ├── Chaika.pm
│   │   │   │   ├── EHentai.pm
│   │   │   │   └── Pixiv.pm
│   │   │   ├── Login
│   │   │   │   ├── EHentai.pm
│   │   │   │   ├── Fakku.pm
│   │   │   │   ├── nHentai.pm
│   │   │   │   └── Pixiv.pm
│   │   │   ├── Metadata
│   │   │   │   ├── Chaika.pm
│   │   │   │   ├── ChaikaFile.pm
│   │   │   │   ├── ComicInfo.pm
│   │   │   │   ├── CopyArchiveTags.pm
│   │   │   │   ├── CopyTags.pm
│   │   │   │   ├── DateAdded.pm
│   │   │   │   ├── EHDLInfo.pm
│   │   │   │   ├── EHentai.pm
│   │   │   │   ├── Eze.pm
│   │   │   │   ├── Fakku.pm
│   │   │   │   ├── GalleryDL.pm
│   │   │   │   ├── HatH.pm
│   │   │   │   ├── HDoujin.pm
│   │   │   │   ├── Hentag.pm
│   │   │   │   ├── Hitomi.pm
│   │   │   │   ├── Koromo.pm
│   │   │   │   ├── Ksk.pm
│   │   │   │   ├── MEMS.pm
│   │   │   │   ├── nHentai.pm
│   │   │   │   ├── Pixiv.pm
│   │   │   │   └── RegexParse.pm
│   │   │   └── Scripts
│   │   │       ├── EhTagAutoUpdater.pm
│   │   │       ├── FolderToCat.pm
│   │   │       ├── nHentaiSourceConverter.pm
│   │   │       └── SourceFinder.pm
│   │   └── Utils
│   │       ├── Archive.pm
│   │       ├── Database.pm
│   │       ├── Generic.pm
│   │       ├── I18N.pm
│   │       ├── I18NInitializer.pm
│   │       ├── ImageMagickResizer.pm
│   │       ├── Logging.pm
│   │       ├── Login.pm
│   │       ├── Metrics.pm
│   │       ├── Minion.pm
│   │       ├── OpenAPI.pm
│   │       ├── PageCache.pm
│   │       ├── Path.pm
│   │       ├── Plugins.pm
│   │       ├── Redis.pm
│   │       ├── Registry.pm
│   │       ├── Resizer.pm
│   │       ├── RotatingLog.pm
│   │       ├── Routing.pm
│   │       ├── String.pm
│   │       ├── Tags.pm
│   │       ├── TempFolder.pm
│   │       ├── Vips.pm
│   │       └── VipsResizer.pm
│   ├── LANraragi.pm
│   ├── Shinobu.pm
│   └── Worker.pm
├── locales
│   └── template
│       ├── as.po
│       ├── de.po
│       ├── en.po
│       ├── es.po
│       ├── fr.po
│       ├── id.po
│       ├── it.po
│       ├── ja.po
│       ├── ko.po
│       ├── nb_NO.po
│       ├── pt.po
│       ├── vi.po
│       ├── zh.po
│       └── zh_Hant.po
├── log
│   └── .gitignore
├── lrr.conf
├── package-lock.json
├── package.json
├── public
│   ├── .gitignore
│   ├── app.webappmanifest
│   ├── css
│   │   ├── .gitignore
│   │   ├── config.css
│   │   └── lrr.css
│   ├── favicon.ico
│   ├── img
│   │   ├── .gitignore
│   │   ├── empty.png
│   │   ├── flubbed.gif
│   │   ├── logo.png
│   │   ├── notfound.jpg
│   │   ├── noThumb.png
│   │   ├── theme_preview
│   │   │   ├── ex.png
│   │   │   ├── g.png
│   │   │   ├── modern.png
│   │   │   ├── modern_clear.png
│   │   │   └── modern_red.png
│   │   └── wait_warmly.jpg
│   ├── js
│   │   ├── .gitignore
│   │   ├── backup.js
│   │   ├── batch.js
│   │   ├── category.js
│   │   ├── config.js
│   │   ├── duplicates.js
│   │   ├── edit.js
│   │   ├── logs.js
│   │   ├── mod
│   │   │   ├── common.js
│   │   │   ├── index.js
│   │   │   ├── index_contextmenu.js
│   │   │   ├── index_datatables.js
│   │   │   ├── reader_archive_overlay.js
│   │   │   ├── reader_common.js
│   │   │   ├── reader_options.js
│   │   │   ├── reader_stamps.js
│   │   │   └── server.js
│   │   ├── plugins.js
│   │   ├── reader.js
│   │   ├── stats.js
│   │   └── upload.js
│   ├── robots.txt
│   └── themes
│       ├── ex.css
│       ├── g.css
│       ├── modern.css
│       ├── modern_clear.css
│       └── modern_red.css
├── README.md
├── redocly.yml
├── script
│   ├── backup
│   ├── check_plugin_loads.pl
│   ├── get_version
│   ├── lanraragi
│   └── launcher.pl
├── templates
│   ├── backup.html.tt2
│   ├── batch.html.tt2
│   ├── category.html.tt2
│   ├── common
│   │   └── importmap.html.tt2
│   ├── config.html.tt2
│   ├── duplicates.html.tt2
│   ├── edit.html.tt2
│   ├── exception.production.html.ep
│   ├── footer.html.tt2
│   ├── i18n.html.tt2
│   ├── index.html.tt2
│   ├── login.html.tt2
│   ├── logs.html.tt2
│   ├── not_found.production.html.ep
│   ├── opds.html.tt2
│   ├── opds_entry.html.tt2
│   ├── plugins.html.tt2
│   ├── reader.html.tt2
│   ├── stats.html.tt2
│   ├── templates_config
│   │   ├── config_files.html.tt2
│   │   ├── config_global.html.tt2
│   │   ├── config_security.html.tt2
│   │   ├── config_shinobu.html.tt2
│   │   ├── config_tags.html.tt2
│   │   └── config_theme.html.tt2
│   └── upload.html.tt2
├── tests
│   ├── backup.t
│   ├── category.t
│   ├── cbw.t
│   ├── LANraragi
│   │   ├── Model
│   │   │   └── Plugins.t
│   │   ├── Plugin
│   │   │   └── Metadata
│   │   │       ├── Chaika.t
│   │   │       ├── ChaikaFile.t
│   │   │       ├── ComicInfo.t
│   │   │       ├── CopyArchiveTags.t
│   │   │       ├── EHDLInfo.t
│   │   │       ├── EHentai.t
│   │   │       ├── Eze.t
│   │   │       ├── Fakku.t
│   │   │       ├── GalleryDL.t
│   │   │       ├── Generic.t
│   │   │       ├── HatH.t
│   │   │       ├── Hentag.t
│   │   │       ├── Hitomi.t
│   │   │       ├── Koromo.t
│   │   │       ├── Ksk.t
│   │   │       ├── nHentai.t
│   │   │       ├── Pixiv.t
│   │   │       └── RegexParse.t
│   │   └── Utils
│   │       ├── Archive.t
│   │       ├── Generic.t
│   │       ├── ImageMagickResizer.t
│   │       ├── Logging.t
│   │       ├── Metrics.t
│   │       ├── Path.t
│   │       ├── Registry.t
│   │       ├── Routing.t
│   │       ├── String.t
│   │       ├── Tags.t
│   │       ├── Vips.t
│   │       └── VipsResizer.t
│   ├── mocks.pl
│   ├── modules.t
│   ├── opds.t
│   ├── plugins.t
│   ├── samples
│   │   ├── chaika
│   │   │   ├── 001_gid_27240.json
│   │   │   └── 002_sha1_response.json
│   │   ├── comicinfo
│   │   │   ├── 00_sample.xml
│   │   │   ├── 01_sample.xml
│   │   │   ├── 02_sample.xml
│   │   │   └── 03_sample.xml
│   │   ├── doc.pdf
│   │   ├── eh
│   │   │   ├── 001_gid-1866546.json
│   │   │   └── 002_search_results.html
│   │   ├── ehdl
│   │   │   ├── info_flat.txt
│   │   │   ├── info_invalid.txt
│   │   │   ├── info_original.txt
│   │   │   ├── info_pipe.txt
│   │   │   └── info_translated.txt
│   │   ├── eze
│   │   │   ├── eze_broken.json
│   │   │   ├── eze_full_sample.json
│   │   │   └── eze_lite_sample.json
│   │   ├── fakku
│   │   │   ├── 001_search_response.html
│   │   │   └── 002_gallery_front.html
│   │   ├── gallerydl
│   │   │   ├── gallerydl_arrayfulltags_sample.json
│   │   │   ├── gallerydl_arraysingletags_sample.json
│   │   │   ├── gallerydl_broken.json
│   │   │   └── gallerydl_hashtags_sample.json
│   │   ├── hath
│   │   │   └── galleryinfo.txt
│   │   ├── hentag
│   │   │   ├── 00_sample.json
│   │   │   ├── 01_sample.json
│   │   │   ├── 02_search_response.json
│   │   │   ├── 03_search_response_multiple.json
│   │   │   ├── 04_search_response_multiple_same_language.json
│   │   │   └── 05_search_response_multiple_similar_titles.json
│   │   ├── hitomi
│   │   │   └── 2261881.js
│   │   ├── koromo
│   │   │   ├── koromo_multiauthor.json
│   │   │   ├── koromo_multimag.json
│   │   │   └── koromo_sample.json
│   │   ├── ksk
│   │   │   ├── fake.yaml
│   │   │   └── fake_koharu.yaml
│   │   ├── nh
│   │   │   ├── 001_search_results.json
│   │   │   ├── 002_search_results_empty.json
│   │   │   └── 003_gid_52249.json
│   │   ├── opds
│   │   │   └── opds_sample.xml
│   │   ├── pixiv
│   │   │   ├── ajax
│   │   │   │   ├── illust.json
│   │   │   │   ├── manga_1.json
│   │   │   │   └── manga_2.json
│   │   │   ├── illust_pixiv_comment_unescaped.txt
│   │   │   ├── manga_1_pixiv_comment_unescaped.txt
│   │   │   ├── manga_2_pixiv_comment_unescaped.txt
│   │   │   ├── manga_2_pixiv_comment_with_script.txt
│   │   │   └── ssr
│   │   │       ├── illust.html
│   │   │       ├── manga_1.html
│   │   │       └── manga_2.html
│   │   ├── reader.jpg
│   │   ├── routing
│   │   │   ├── js
│   │   │   │   ├── ok.txt
│   │   │   │   └── safe
│   │   │   │       └── ok2.txt
│   │   │   └── secret.txt
│   │   └── sample.cbw
│   ├── search.t
│   ├── stamp.t
│   └── tankoubon.t
└── tools
    ├── build
    │   ├── docker
    │   │   ├── docker-compose.yml
    │   │   ├── Dockerfile
    │   │   ├── Dockerfile-dev
    │   │   ├── install-perl-deps.sh
    │   │   ├── redis.conf
    │   │   └── s6
    │   │       ├── cont-init.d
    │   │       │   └── 01-lrr-setup
    │   │       ├── fix-attrs.d
    │   │       │   └── 01-lrr-dirs
    │   │       └── s6-rc.d
    │   │           ├── init
    │   │           │   ├── type
    │   │           │   └── up
    │   │           ├── lanraragi
    │   │           │   ├── dependencies.d
    │   │           │   │   ├── init
    │   │           │   │   └── redis
    │   │           │   ├── finish
    │   │           │   ├── run
    │   │           │   └── type
    │   │           ├── redis
    │   │           │   ├── dependencies.d
    │   │           │   │   └── init
    │   │           │   ├── run
    │   │           │   └── type
    │   │           └── user
    │   │               └── contents.d
    │   │                   ├── init
    │   │                   ├── lanraragi
    │   │                   └── redis
    │   ├── homebrew
    │   │   ├── lanraragi
    │   │   ├── Lanraragi.rb
    │   │   └── redis.conf
    │   └── windows
    │       ├── build-installer.ps1
    │       ├── cleanup.sh
    │       ├── create-dist.sh
    │       ├── install-deps.sh
    │       ├── install.sh
    │       ├── Karen
    │       ├── perl.exe.manifest
    │       ├── redis.conf
    │       ├── run.ps1
    │       └── utf8-support.ps1
    ├── cpanfile
    ├── Documentation
    │   ├── .gitbook
    │   │   └── assets
    │   │       ├── add-chapter.png
    │   │       ├── archive_list.png
    │   │       ├── archive_thumb.png
    │   │       ├── backup.png
    │   │       ├── batch.png
    │   │       ├── batchlog.png
    │   │       ├── bookmark_button.png
    │   │       ├── bookmark_config.png
    │   │       ├── brew.jpg
    │   │       ├── categories.png
    │   │       ├── category_filtered.png
    │   │       ├── cfg.png
    │   │       ├── cfg_plugin.png
    │   │       ├── chapters.jpg
    │   │       ├── chapters_sicp.jpg
    │   │       ├── cloud.PNG
    │   │       ├── download.png
    │   │       ├── downloaders.png
    │   │       ├── duplicates.png
    │   │       ├── dureader.jpg
    │   │       ├── edit.png
    │   │       ├── favtags.jpg
    │   │       ├── ichaival.png
    │   │       ├── jails.jpg
    │   │       ├── karen-dark.png
    │   │       ├── karen-light.png
    │   │       ├── karen-startmenu.png
    │   │       ├── karen.png
    │   │       ├── login.png
    │   │       ├── lrr_react.jpg
    │   │       ├── metrics_settings.png
    │   │       ├── mountpoints.jpg
    │   │       ├── msm.png
    │   │       ├── opds.jpg
    │   │       ├── openssl-error.png
    │   │       ├── ratings.png
    │   │       ├── reader.jpg
    │   │       ├── reader_options.png
    │   │       ├── reader_overlay.jpg
    │   │       ├── search.png
    │   │       ├── shell.jpg
    │   │       ├── shiggy.png
    │   │       ├── stamp-toggle.jpg
    │   │       ├── stamps.jpg
    │   │       ├── tachiyomi.jpg
    │   │       ├── tank_creation.jpg
    │   │       ├── tank_edition.png
    │   │       ├── themes.png
    │   │       ├── thumbchange.png
    │   │       ├── uploading.png
    │   │       ├── utf8-popup.png
    │   │       ├── utf8-region.png
    │   │       ├── utf8-restart.png
    │   │       └── webext.png
    │   ├── .gitbook.yaml
    │   ├── advanced-usage
    │   │   ├── backup-and-restore.md
    │   │   ├── batch-tagging.md
    │   │   ├── downloading.md
    │   │   ├── duplicate-detection.md
    │   │   ├── external-readers.md
    │   │   ├── network-interfaces.md
    │   │   ├── plugin-registries.md
    │   │   ├── proxy-setup.md
    │   │   ├── stamps.md
    │   │   ├── tag-rules.md
    │   │   └── tankoubons-and-chapters.md
    │   ├── api-documentation
    │   │   ├── archive-api.md
    │   │   ├── category-api.md
    │   │   ├── database-api.md
    │   │   ├── getting-started.md
    │   │   ├── minion-api.md
    │   │   ├── miscellaneous-other-api.md
    │   │   ├── opds-catalog.md
    │   │   ├── plugin-api.md
    │   │   ├── registry-api.md
    │   │   ├── search-api.md
    │   │   ├── shinobu-api.md
    │   │   ├── stamp-api.md
    │   │   └── tankoubon-api.md
    │   ├── basic-operations
    │   │   ├── archives.md
    │   │   ├── categories.md
    │   │   ├── first-steps.md
    │   │   ├── metadata.md
    │   │   ├── searching.md
    │   │   ├── stats.md
    │   │   └── themes.md
    │   ├── extending-lanraragi
    │   │   ├── architecture.md
    │   │   ├── index.md
    │   │   └── translations.md
    │   ├── installing-lanraragi
    │   │   ├── community.md
    │   │   ├── docker.md
    │   │   ├── jail.md
    │   │   ├── macos.md
    │   │   ├── methods.md
    │   │   ├── source.md
    │   │   └── windows.md
    │   ├── plugin-docs
    │   │   ├── code-examples.md
    │   │   ├── download.md
    │   │   ├── index.md
    │   │   ├── login.md
    │   │   ├── metadata.md
    │   │   └── scripts.md
    │   ├── README.md
    │   └── SUMMARY.md
    ├── generate_registry.pl
    ├── install.pl
    ├── k6
    │   ├── covers_cold.js
    │   ├── page_fetching.js
    │   ├── single_archive_cold.js
    │   └── single_archive_warm.js
    ├── lanraragi-systemd.service
    ├── openapi.yaml
    └── repository-open-graph-template.jpg
```
