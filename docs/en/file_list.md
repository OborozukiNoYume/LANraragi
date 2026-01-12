# LANraragi 项目文件分类

> 生成时间: 2026-01-11

本文档按类型分类列出项目中的所有文件。

---

## 📊 文件统计

| 类型 | 数量 |
|------|------|
| Perl 代码文件 (.pm, .pl, .t) | 112 |
| JavaScript 文件 (.js) | 21 |
| 模板/HTML/CSS 文件 | 40 |
| 配置文件 (.json, .yaml, .conf, .xml) | 38 |
| 图片文件 | 14 |
| 文档文件 (.md, .txt) | 57 |
| 脚本文件 (.sh, .ps1) | 8 |
| 本地化文件 (.po) | 14 |

---

## 🔷 Perl 代码文件 (112 个)

### 核心模块
```
lib/
├── LANraragi.pm
├── Shinobu.pm
├── Worker.pm
```

### Controller 层 (API)
```
lib/LANraragi/Controller/Api/
├── Archive.pm
├── Category.pm
├── Database.pm
├── Minion.pm
├── Other.pm
├── Search.pm
├── Shinobu.pm
└── Tankoubon.pm
```

### Controller 层 (页面)
```
lib/LANraragi/Controller/
├── Backup.pm
├── Batch.pm
├── Category.pm
├── Config.pm
├── Duplicates.pm
├── Edit.pm
├── I18N.pm
├── Index.pm
├── Logging.pm
├── Login.pm
├── Plugins.pm
├── Reader.pm
├── Stats.pm
├── Tankoubon.pm
└── Upload.pm
```

### Model 层
```
lib/LANraragi/Model/
├── Archive.pm
├── Backup.pm
├── Category.pm
├── Config.pm
├── Opds.pm
├── Plugins.pm
├── Reader.pm
├── Search.pm
├── Setup.pm
├── Stats.pm
├── Tankoubon.pm
└── Upload.pm
```

### 插件 - 下载
```
lib/LANraragi/Plugin/Download/
├── Chaika.pm
├── EHentai.pm
└── Pixiv.pm
```

### 插件 - 登录
```
lib/LANraragi/Plugin/Login/
├── EHentai.pm
├── Fakku.pm
├── Pixiv.pm
└── nHentai.pm
```

### 插件 - 元数据
```
lib/LANraragi/Plugin/Metadata/
├── Chaika.pm
├── ChaikaFile.pm
├── ComicInfo.pm
├── CopyArchiveTags.pm
├── CopyTags.pm
├── DateAdded.pm
├── EHDLInfo.pm
├── EHentai.pm
├── Eze.pm
├── Fakku.pm
├── GalleryDL.pm
├── HDoujin.pm
├── HatH.pm
├── Hentag.pm
├── HentagOnline.pm
├── Hitomi.pm
├── Koromo.pm
├── Ksk.pm
├── MEMS.pm
├── Pixiv.pm
├── RegexParse.pm
└── nHentai.pm
```

### 插件 - 脚本
```
lib/LANraragi/Plugin/Scripts/
├── FolderToCat.pm
├── SourceFinder.pm
└── nHentaiSourceConverter.pm
```

### 工具类
```
lib/LANraragi/Utils/
├── Archive.pm
├── Database.pm
├── Generic.pm
├── I18N.pm
├── I18NInitializer.pm
├── ImageMagickResizer.pm
├── Logging.pm
├── Minion.pm
├── PageCache.pm
├── Path.pm
├── Plugins.pm
├── Redis.pm
├── Resizer.pm
├── RotatingLog.pm
├── Routing.pm
├── String.pm
├── Tags.pm
├── TempFolder.pm
├── Vips.pm
└── VipsResizer.pm
```

### 测试文件 (.t)
```
tests/
├── backup.t
├── mocks.pl
├── modules.t
├── opds.t
├── plugins.t
├── search.t
├── tankoubon.t
├── LANraragi/Model/
│   └── Plugins.t
├── LANraragi/Plugin/Metadata/
│   ├── Chaika.t
│   ├── ChaikaFile.t
│   ├── ComicInfo.t
│   ├── CopyArchiveTags.t
│   ├── EHDLInfo.t
│   ├── EHentai.t
│   ├── Eze.t
│   ├── Fakku.t
│   ├── GalleryDL.t
│   ├── Generic.t
│   ├── HatH.t
│   ├── Hentag.t
│   ├── HentagOnline.t
│   ├── Hitomi.t
│   ├── Koromo.t
│   ├── Ksk.t
│   ├── Pixiv.t
│   ├── RegexParse.t
│   └── nHentai.t
└── LANraragi/Utils/
    ├── Archive.t
    ├── Generic.t
    ├── ImageMagickResizer.t
    ├── Logging.t
    ├── String.t
    ├── Tags.t
    ├── Vips.t
    └── VipsResizer.t
```

### 启动脚本
```
script/
├── backup
├── get_version
├── lanraragi
└── launcher.pl
```

---

## 🟡 JavaScript 文件 (21 个)

### 前端功能模块
```
public/js/
├── backup.js
├── batch.js
├── category.js
├── common.js
├── config.js
├── duplicates.js
├── edit.js
├── index.js
├── index_datatables.js
├── logs.js
├── plugins.js
├── reader.js
├── server.js
├── stats.js
└── upload.js
```

### 测试/工具
```
tests/samples/hitomi/
└── 2261881.js

tools/k6/
├── covers_cold.js
├── page_fetching.js
├── single_archive_cold.js
└── single_archive_warm.js
```

### 其他
```
docs/
└── generate_tree.py
```

---

## 🟢 模板/HTML/CSS 文件 (40 个)

### CSS 样式
```
public/css/
├── config.css
└── lrr.css

public/themes/
├── ex.css
├── g.css
├── modern.css
├── modern_clear.css
└── modern_red.css
```

### 页面模板 (Template Toolkit)
```
templates/
├── backup.html.tt2
├── batch.html.tt2
├── category.html.tt2
├── config.html.tt2
├── duplicates.html.tt2
├── edit.html.tt2
├── footer.html.tt2
├── i18n.html.tt2
├── index.html.tt2
├── login.html.tt2
├── logs.html.tt2
├── opds.html.tt2
├── opds_entry.html.tt2
├── plugins.html.tt2
├── reader.html.tt2
├── stats.html.tt2
├── upload.html.tt2
└── templates_config/
    ├── config_files.html.tt2
    ├── config_global.html.tt2
    ├── config_security.html.tt2
    ├── config_shinobu.html.tt2
    ├── config_tags.html.tt2
    └── config_theme.html.tt2
```

### 错误页面 (Mojolicious EP)
```
templates/
├── exception.production.html.ep
└── not_found.production.html.ep
```

### 测试样本 HTML
```
tests/samples/
├── eh/002_search_results.html
├── fakku/001_search_response.html
├── fakku/002_gallery_front.html
├── nh/001_search_results.html
├── nh/002_gid_52249.html
└── pixiv/ssr/
    ├── illust.html
    ├── manga_1.html
    └── manga_2.html
```

---

## ⚙️ 配置文件 (38 个)

### 项目配置
```
./
├── lrr.conf
├── package.json
└── package-lock.json
```

### Docker/构建配置
```
tools/build/docker/
├── docker-compose.yml
├── redis.conf
└── wsl.conf

tools/build/homebrew/
└── redis.conf

tools/build/windows/
└── redis.conf
```

### API 规范
```
tools/
└── openapi.yaml
```

### 测试样本数据
```
tests/samples/
├── chaika/
│   ├── 001_gid_27240.json
│   └── 002_sha1_response.json
├── comicinfo/
│   ├── 00_sample.xml
│   ├── 01_sample.xml
│   ├── 02_sample.xml
│   └── 03_sample.xml
├── eh/
│   └── 001_gid-1866546.json
├── eze/
│   ├── eze_broken.json
│   ├── eze_full_sample.json
│   └── eze_lite_sample.json
├── gallerydl/
│   ├── gallerydl_arrayfulltags_sample.json
│   ├── gallerydl_arraysingletags_sample.json
│   ├── gallerydl_broken.json
│   └── gallerydl_hashtags_sample.json
├── hentag/
│   ├── 00_sample.json
│   ├── 01_sample.json
│   ├── 02_search_response.json
│   ├── 03_search_response_multiple.json
│   ├── 04_search_response_multiple_same_language.json
│   └── 05_search_response_multiple_similar_titles.json
├── koromo/
│   ├── koromo_multiauthor.json
│   ├── koromo_multimag.json
│   └── koromo_sample.json
├── ksk/
│   ├── fake.yaml
│   └── fake_koharu.yaml
├── opds/
│   └── opds_sample.xml
└── pixiv/ajax/
    ├── illust.json
    ├── manga_1.json
    └── manga_2.json
```

---

## 🖼️ 图片文件 (14 个)

### 网站图标和 UI 图片
```
public/
├── favicon.ico
└── img/
    ├── empty.png
    ├── flubbed.gif
    ├── logo.png
    ├── noThumb.png
    ├── notfound.jpg
    └── wait_warmly.jpg
```

### 主题预览图
```
public/img/theme_preview/
├── hachikuji.png
├── hverse.png
├── nadeko.png
├── sadpanda.png
└── yotsugi.png
```

### 测试/工具图片
```
tests/samples/
└── reader.jpg

tools/
└── repository-open-graph-template.jpg
```

---

## 📝 文档文件 (57 个)

### 项目根目录
```
./
├── CONTRIBUTING.md
├── README.md
└── COPYING (LICENSE)
```

### 本项目文档
```
docs/
└── project_tree.md
```

### 官方文档
```
tools/Documentation/
├── README.md
├── SUMMARY.md
├── advanced-usage/
│   ├── backup-and-restore.md
│   ├── batch-tagging.md
│   ├── categories.md
│   ├── downloading.md
│   ├── external-readers.md
│   ├── network-interfaces.md
│   ├── proxy-setup.md
│   └── tag-rules.md
├── api-documentation/
│   ├── archive-api.md
│   ├── category-api.md
│   ├── database-api.md
│   ├── getting-started.md
│   ├── minion-api.md
│   ├── miscellaneous-other-api.md
│   ├── opds-catalog.md
│   ├── plugin-api.md
│   ├── search-api.md
│   ├── shinobu-api.md
│   └── tankoubon-api.md
├── basic-operations/
│   ├── archives.md
│   ├── first-steps.md
│   ├── metadata.md
│   ├── searching.md
│   ├── stats.md
│   └── themes.md
├── extending-lanraragi/
│   ├── architecture.md
│   ├── index.md
│   └── translations.md
├── installing-lanraragi/
│   ├── community.md
│   ├── docker.md
│   ├── jail.md
│   ├── macos.md
│   ├── methods.md
│   ├── source.md
│   └── windows.md
└── plugin-docs/
    ├── code-examples.md
    ├── download.md
    ├── index.md
    ├── login.md
    ├── metadata.md
    └── scripts.md
```

### 测试样本文本
```
tests/samples/
├── ehdl/
│   ├── info_flat.txt
│   ├── info_invalid.txt
│   ├── info_original.txt
│   ├── info_pipe.txt
│   └── info_translated.txt
├── hath/
│   └── galleryinfo.txt
└── pixiv/
    ├── illust_pixiv_comment_unescaped.txt
    ├── manga_1_pixiv_comment_unescaped.txt
    ├── manga_2_pixiv_comment_unescaped.txt
    └── manga_2_pixiv_comment_with_script.txt
```

### 其他
```
public/
└── robots.txt
```

---

## 🔧 Shell/PowerShell 脚本 (8 个)

### Docker 构建
```
tools/build/docker/
└── install-everything.sh
```

### Windows 构建
```
tools/build/windows/
├── build-installer.ps1
├── cleanup.sh
├── create-dist.sh
├── install-deps.sh
├── install.sh
├── run.ps1
└── utf8-support.ps1
```

---

## 🌍 本地化文件 (14 个)

```
locales/template/
├── as.po      (阿萨姆语)
├── de.po      (德语)
├── en.po      (英语)
├── es.po      (西班牙语)
├── fr.po      (法语)
├── id.po      (印尼语)
├── it.po      (意大利语)
├── ja.po      (日语)
├── ko.po      (韩语)
├── nb_NO.po   (挪威语)
├── pt.po      (葡萄牙语)
├── vi.po      (越南语)
├── zh.po      (简体中文)
└── zh_Hant.po (繁体中文)
```

---

## 📁 其他重要文件

### Docker 配置
```
tools/build/docker/
├── Dockerfile
├── Dockerfile-dev
├── Dockerfile-legacy
└── s6/ (服务管理配置)
```

### Homebrew 配置
```
tools/build/homebrew/
├── Lanraragi.rb
└── lanraragi
```

### Perl 依赖
```
tools/
├── cpanfile
└── install.pl
```

### 开发配置
```
./
├── .eslintrc.json
├── .perlcriticrc
├── .perltidyrc
├── .gitignore
├── .gitattributes
├── .gitmodules
└── .dockerignore
```

---

## 📐 项目结构概览

```
LANraragi/
├── lib/                    # Perl 后端代码
│   ├── LANraragi/
│   │   ├── Controller/    # MVC Controller
│   │   ├── Model/         # MVC Model
│   │   ├── Plugin/        # 插件系统
│   │   └── Utils/         # 工具类
│   ├── LANraragi.pm
│   ├── Shinobu.pm
│   └── Worker.pm
├── public/                 # 静态资源
│   ├── css/               # 样式表
│   ├── js/                # JavaScript
│   ├── img/               # 图片
│   └── themes/            # 主题
├── templates/              # 页面模板
├── locales/                # 国际化
├── tests/                  # 测试文件
├── tools/                  # 工具和文档
│   ├── Documentation/     # 官方文档
│   └── build/             # 构建脚本
├── script/                 # 启动脚本
├── log/                    # 日志目录
└── docs/                   # 项目文档（新建）
```
