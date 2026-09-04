# 05 - 前端架构

> 基准 commit `2094cc1d`（2026-09-04）。事实已对照代码核实——生成时已完成引证核查。

LANraragi 前端是一个混合技术栈：应用代码使用现代 **ES Modules**，通过标准的
[import map](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/script/type/importmap)（导入映射）加载；同时用经典
`<script>` 标签承载基于 jQuery 的旧版组件（DataTables、contextMenu、文件上传）。本章描述
脚本的加载方式、`public/js/mod/` 下的共享模块、位于 `public/js/` 根目录的按页面划分的脚本、
阅读器的客户端状态机，以及模板/主题层。

## 加载架构

每个页面模板都包含 `templates/common/importmap.html.tt2`，它输出一个 `<script type="importmap">`
块，将裸模块标识符映射到带版本的 URL，例如 `preact` → `/js/$version/vendor/preact.module.js`、
`react-toastify` → `/js/$version/vendor/react-toastify.esm.js`、`swiper` → `/js/$version/vendor/swiper-bundle.js`。
它还会异步加载 `es-module-shims.js`（来自 `es-module-shims` npm 包），为不支持原生
import map 的浏览器提供 polyfill。

入口点遵循 `/js/{version}/mod/<module>.js` 模式，其中 `{version}` 来自 `LRR_VERSION` 助手
（以 `$version` 注入模板，其值由 `LANraragi::Utils::Generic` 的 `get_version()` 从
`package.json` 的 `version` 字段取得）。版本号纯粹是缓存破坏（cache buster）手段：`lib/LANraragi/Utils/Routing.pm`
中定义的路由匹配 `/js/:version/*filepath`，从 `public/js/` 提供文件，并附带
`Cache-Control: public, max-age=31536000, immutable`。

另有两个相关机制补充完整：

- `/js/i18n.js` 不是静态文件——它由 `LANraragi::Controller::I18N` 渲染，后者将
  `templates/i18n.html.tt2` 以 `application/javascript` 提供。因此整个 i18n 词典就是一个 ES 模块
  （几乎每个脚本中都会出现 `import I18N from "i18n"`），无需任何客户端 i18n 库。
- `lrr_baseurl` 是由 `lib/LANraragi.pm` 中 `before_dispatch` 钩子设置的 cookie（面向部署在
  路径前缀之下的场景）。`public/js/mod/common.js` 中的 `ApiURL` 类读取它，并将基础 URL
  前置到每个应用内部 URL 上；所有 API 调用都经由它进行。

`public/js/vendor/` 下的第三方 ESM 文件**不提交到仓库**——它们由 `tools/install.pl` 在安装时从
`node_modules` 准备：大多数经 `@vendor_js` 列表原样复制，而 `swiper-bundle.js` 则由 esbuild 依照
仅有一项的 `@vendor_bundle` 列表打包。jQuery 及其他经典
脚本（`jquery.min.js`、`jquery.dataTables.min.js`、`jquery.contextMenu.min.js`、`awesomplete.min.js`、
`tippy-bundle.umd.min.js` 等）通过页面模板中的普通 `<script src>` 标签加载（参见
`templates/index.html.tt2` 和 `templates/reader.html.tt2`），并在模块代码中作为全局变量（`$`、`tippy`、……）
使用。模板通常用一个内联 `<script type="module">` 引导：导入该页面的模块，并在
`jQuery(...)` ready 回调中启动 `initializeAll()`（阅读器模板是例外，它在模块顶层直接 await
`initializeAll()`）。

## 核心模块：`public/js/mod/`

九个共享模块实现了所有跨页面逻辑：

| 模块 | 职责（经核实的导出） |
|---|---|
| `common.js` | 每个页面共享的 DOM/字符串助手：`isUserLogged()`（读取 `body[data-user-logged]`）、`splitTagsByNamespace()`、`buildTagList()`、`buildTagsDiv()`、`buildThumbnailDiv()`、`buildStatusDiv()`、`buildBookmarkIconElement()`、`colorCodeTags()`、`getProgress()`、`encodeHTML()`、`convertTimestamp()`、`ApiURL` 类、`getArchiveData()`（按 ID 键控的档案数据会话缓存），以及下文描述的 toast/弹窗层。 |
| `server.js` | 通用 API 访问：`callAPI()`、`callAPISilent()`、`callAPIBody()`（fetch 封装——前两者同时理解 LRR `success/error` JSON 与 OpenAPI 风格 `errors` 载荷）、`checkJobStatus()`（Minion 任务轮询）、`saveFormData()`、`triggerScript()`、`deleteArchive()`、`deleteTankoubon()`、`regenerateThumbnails()`、`addArchiveToCategory()`/`removeArchiveFromCategory()`、`updateTagsFromArchive()`/`updateTagsFromTankoubon()`、`loadBookmarkCategoryId()`、`updateServerSideProgress()`。 |
| `index.js` | 档案索引中表格之外的功能：分类选择器、带 Awesomplete 标签建议的快速搜索（`loadTagSuggestions()`）、Swiper 轮播（`toggleCarousel()`/`updateCarousel()` 导出，另有内部函数 `loadCarousel()`，请求 `/api/search` 的变体如 `/api/search/random?count=15`）、带单行本合并的多选模式（`toggleMultiSelectMode()` 导出，另有内部函数 `mergeSelectionIntoTankoubon()`）、通过 `marked` + `DOMPurify` 渲染的版本检查与更新日志（`checkVersion()`、`fetchChangelog()`）、localStorage→服务器阅读进度迁移（`migrateProgress()`）。 |
| `index_datatables.js` | 基于 DataTables 的档案表格：`initializeAll()`、`doSearch()`、列渲染器（`renderTitle()`、`renderTags()`）、缩略图视图（`initializeThumbView()`）、URL 状态同步（`buildURLParameters()`/`consumeURLParameters()`）、行/单元格回调。从 `index.js` 拆分出来，以便表格层可以独立替换。 |
| `index_contextmenu.js` | 档案缩略图上的右键菜单：`initialize(catListData)`、通过 `handleContextMenu()` 接线的删除/评分/分类操作。记录菜单是从轮播还是表格打开（sessionStorage `navigationState`），以便阅读器恢复导航上下文。 |
| `reader_common.js` | 阅读器入口与共享状态（见下一节）。导出 `initializeAll()`、`state`、`goToPage()`、`applyContainerWidth()`、`stopAutoNextPage()`、`getCurrentChapter()`、`loadContentData()`、`toggleOverlay()`、`getArchiveForPage()`。 |
| `reader_options.js` | 阅读器设置面板，用 Preact + `htm` 渲染（`SettingsPanel()`），将选项写回 `state` 信号。 |
| `reader_stamps.js` | 阅读器页面上的戳记/书签标记：`initializeStamps()`、`renderMarkers()`、`clearMarkers()`、`updateStamps(page)`，以及标记模式下的右键菜单处理。 |
| `reader_archive_overlay.js` | 档案信息覆盖层（分类、目录、已加戳页面列表）：`initializeArchiveOverlay()`、`toggleArchiveOverlay()`、`updateArchiveOverlay()`、`addTocSection()`、`checkStampedPages()`。 |

`common.js` 中 `toast()` 的 toast 系统明确是一个**兼容层**，把旧的
`jquery-toast-plugin` 选项对象（`heading`、`text`、`icon`、`hideAfter`、……）迁移到
`react-toastify` 上，并用 Preact 渲染容器（`initializeToasts()`）。对话框走
`showPopUp()`——`sweetalert2` 的一层薄封装。底层库被替换时，旧调用点无需改动。

`server.js` 中有两个 API 约定，在新增调用时值得了解：

- 响应可能以 LRR 旧格式（`{ success: 0, error }`）或 OpenAPI
  校验格式（`{ errors: [{ message }] }`）携带错误；`callAPI()` 和 `callAPISilent()` 都会将其转换成
  抛出的 `Error`。`callAPIBody()` 增加请求体和可选的 `Content-Type`，但只理解
  `success`/`error` 格式——它没有对 OpenAPI `errors` 载荷的处理。
- `checkJobStatus(jobId, useDetail, callback, failureCallback, progressCallback)` 轮询
  `/api/minion/{id}`（或需要已登录用户的 `/api/minion/{id}/detail`），并按任务状态使用不同的
  轮询间隔：`inactive` 时 5 秒，`active` 时 1 秒（以任务 `notes` 调用 `progressCallback`），
  `finished` 状态触发 `callback`。它通过 `setTimeout` 递归，因此页面导航会自然停止
  轮询。这是每个长时间运行的 Minion 操作（缩略图重新生成、插件运行、备份）的客户端对应物。

## 页面脚本：`public/js/*.js`

每个管理页面都有一个位于根目录的小型 ES 模块，导入共享模块并装配其页面专属的
DOM。它们都遵循相同形态（`import * as Server from "./mod/server.js"; import * as LRR from "./mod/common.js";`
+ jQuery ready 时的 `initializeAll()`）：

| 脚本 | 页面 |
|---|---|
| `backup.js` | 备份导入/导出（恢复文件使用 blueimp jQuery-File-Upload）。 |
| `batch.js` | 批量标签/插件操作。从 `/api/archives` 加载档案清单（并经 `/api/archives/untagged` 预勾选无标签档案），或从索引多选模式写入的 `localStorage.msmSelection` 加载子集（`TANK_` id 经 `/api/tankoubons/{id}` + `/api/archives/{id}/metadata` 展开），随后驱动 websocket。 |
| `category.js` | 分类管理。 |
| `config.js` | 服务器配置（全部设置标签页）。 |
| `duplicates.js` | 重复检测界面。 |
| `edit.js` | 档案元数据编辑；标签输入使用 `@jcubic/tagger`，标签排序使用 SortableJS，二者均由 `templates/edit.html.tt2` 作为经典全局脚本加载（`tagger.js`、`Sortable.min.js`）。 |
| `logs.js` | 日志查看器。 |
| `plugins.js` | 插件管理与上传。 |
| `reader.js` | 一行再导出：`export { initializeAll } from "./mod/reader_common.js";` —— 保留它是为了让 `templates/reader.html.tt2` 能加载一个稳定的 URL，而实现放在 `mod/` 中。 |
| `stats.js` | 统计仪表盘（jqCloud，经 `templates/stats.html.tt2`）。 |
| `upload.js` | 上传页面（jQuery-File-Upload）。 |

## 阅读器

`public/js/mod/reader_common.js` 是最大的客户端模块。其导出的 `state` 对象是阅读器的单一
数据源。普通字段保存易失数据（`currentPage`、`pages`、`maxPage`、`archiveIds`、
`spaceScroll`、`preloadedImg`），而用户偏好是写入时持久化到 `localStorage` 的 **Preact 信号**：
`containerWidth`、`mangaMode`、`doublePageMode`、`ignoreProgress`、`infiniteScroll`、`fitMode`、
`hideHeader`、`showOverlayByDefault`、`preloadCount`、`AutoNextPageInterval`、`markersVisible`。正因如此，
设置面板和戳记模块无需手动事件管线即可响应开关切换（`reader_stamps.js` 使用
`@preact/signals` 的 `effect()` 在 `markersVisible` 变化时重新渲染标记）。

键盘处理位于 `handleShortcuts()` 中，同时绑定 `keyup` 与（仅空格键的）`keydown`：
方向键/`a`/`d` 翻页（shift = 首页/末页），空格键带可配置吸附的平滑滚动
（`state.scrollConfig`），`b` 书签，`f` 全屏（通过 `fscreen`），`g` 跳页提示，`h` 帮助，`m` 漫画
阅读方向，`n` 自动翻页计时器，`o` 设置覆盖层，`p` 双页模式，`q` 档案覆盖层，
`r` 随机档案，退格键返回索引，`,`/`.` 跳转到上一个/下一个档案。

阅读进度由 `updateProgress()` 上报，采用由模板传入的服务器设置镜像而来的三路策略
（`trackProgressLocally`、`authenticateProgress`）：

- 已认证且已登录 → `mod/server.js` 中的 `Server.updateServerSideProgress()`，它发起
  `PUT /api/archives/{id}/progress/{page}`（单行本则为 `/api/tankoubons/TANK_.../progress/{page}`），
  并容忍 Redis 被短暂锁定时返回的 423；
- 本地跟踪 → `localStorage.setItem("<id>-reader", page)`；
- 未认证的服务器端跟踪 → 同样的 PUT，但不带认证。

图片预取由 `preloadImages()` 完成：它通过 `loadImage()` 以 blob 形式抓取接下来的
`state.preloadCount.value` 页外加前一页（两个计数在双页模式下翻倍；`preloadCount` 为 0 时跳过前一页的预取），把 `URL.createObjectURL()` 的结果保存在
`state.preloadedImg` 中，并将以 KiB 计的大小（`Content-Length` / 1024）记录到 `state.preloadedSizes` 供文件信息显示使用。跨档案的
下一个/上一个导航（`readNextArchive()`/`readPreviousArchive()`）会从
`localStorage` 中诸如 `currArchiveIds`/`nextArchiveIds` 的键恢复来源的 DataTables 页面，使用户回到
出发位置。

### 页面渲染：双页、漫画模式与无限滚动

阅读器从不重排 `state.pages`；各种模式只改变页索引到 DOM 的投影方式。标准视图在弹性容器
`#display` 内有两个 `<img>` 槽位（`#img`、`#img_doublepage`）——空的 `src` 会经 CSS 隐藏第二个
槽位。双页模式（仅在 `currentPage` 既非首页也非末页时生效）下两个槽位依靠 `#display` 始终
开启的弹性布局并排（切换的 `double-mode` 类本身不带任何 CSS）；当跨页的任一半是横图
（"widespread"）时，整个跨页收缩为该单图并置
`showingSinglePage = true`，此后向后导航会多退一页以落在上一个跨页的起点。漫画模式交换跨页
两半进入哪个槽位，并反转 `changePage()` 的方向（含首/末）；`pages` 数组本身不动。这里没有
空白页填充——配对平衡完全依靠横图回退加这条边界规则。

无限滚动则彻底替换这条流水线：首页之后的每一页作为真实的 `<img id="page-N">` 元素追加
（首页复用现有的 `#img` 槽位，不被观察器覆盖），一个
`IntersectionObserver`（阈值 0.5）在页面越过视口中线时更新 `currentPage` 并调用
`updateProgress()`，漫画/双页模式被强制关闭，带 `webtoon` 标签的档案获得零边距样式。
`goToPage()` 会钳制索引、渲染（无限滚动模式则滚动），随后总是运行
`updateArchiveOverlay()` 与 `updateProgress()`——标准视图下它还会在滚回顶部前预取并重新应用
宽度样式。`updateProgress()` 上报
`currentPage + 1`（1 起始），因此一个两页跨页只记录其第一页为已读。章节经 `findChapterForPage()`
在 `common.js` 中 `buildArchiveChapters()` 由档案 `toc` 条目（`{page, name}`）构建的
`{startPage, endPage, chapters}` 树上解析，单行本则按页偏移嵌套各档案的章节。失败处理刻意从
简：页面图片没有 `onerror` 处理器，整档加载失败表现为一条错误 toast
（`flubbed.gif` 回退分支的守卫条件因其 `[]` 初始化而实际不可达），进度 PUT 的
423 则被静默吞掉。

自动翻页定时器是 1 秒一次的 `setInterval` 倒计时（间隔默认 10 秒，可在选项面板调整）；归零时
翻页——或在边界处跨入下一个/上一个档案，经 `sessionStorage autoNextPage` 标志恢复并持有
wake lock。通过翻页控件（按键、点击、分页器、空格键）的手动翻页会重置倒计时；直接的
`goToPage()` 跳转——跳页输入框、覆盖层缩略图、章节选择器——则不会。

## 前端依赖

下列版本逐字复制自基准 commit 时的 `package.json`（`^` 范围按声明原样——请以
`package.json` 为准）。仅列出有直接前端用法的条目：

| 包 | 版本（按 `package.json`） | 用途 |
|---|---|---|
| `preact` / `@preact/signals` | `^10.29.2` / `^2.9.2` | UI 片段（设置面板、toast），响应式阅读器状态。 |
| `react-toastify` | `9.0.0-rc-2` | 兼容层背后的 toast 通知。 |
| `sweetalert2` | `11.22.4` | 确认/输入对话框（`showPopUp()`）。 |
| `jquery` | `3.6.0` | 旧版 DOM/事件层，仍作为全局变量引入。 |
| `datatables.net` | `1.11.5` | 档案索引表格（`index_datatables.js`）。 |
| `jquery-contextmenu` | `2.9.2` | 索引与阅读器戳记上的右键菜单。 |
| `swiper` | `^14.0.2` | 索引轮播与多选轮播。 |
| `marked` + `dompurify` | `^18.0.4` + `^3.4.13` | 安全地渲染 GitHub 更新日志 markdown。 |
| `awesomplete` | `1.1.5` | 标签搜索自动补全。 |
| `@jcubic/tagger` | `0.4.2` | 编辑页的标签输入。 |
| `sortablejs` | `1.15.6` | 拖拽排序标签规则/条目。 |
| `tippy.js` | `6.3.7` | 标签工具提示（`buildTagTooltip()`）。 |
| `fscreen` | `1.2.0` | 全屏 API 封装。 |
| `blueimp-file-upload` | `10.32.0` | 上传/备份/恢复文件组件。 |
| `clsx` / `htm` | `1.1.1` / `^3.1.1` | 类名字符串 / 无 JSX 的 Preact 模板化。 |
| `es-module-shims` | `^2.8.2` | import map polyfill。 |
| `jqcloud2` / `clipboard` / `allcollapsible` / `raty-js` / `geist` / `inter-ui` / `@fortawesome/fontawesome-free` | `2.0.3` / `2.0.11` / `1.1.0` / `^4.3.0` / `1.0.0` / `3.19.3` / `^6.7.2` | 标签云（统计）、剪贴板按钮、可折叠区块、星级评分（阅读器）、字体、图标。 |

在 i18n 方面，模板在渲染时用 `c.lh(...)` 翻译服务器端字符串（参见
`templates/i18n.html.tt2`，它把这些查找转换为在 `/js/i18n.js` 提供的 `I18N` 词典）；
客户端脚本通过生成的模板函数进行插值（例如
`server.js` 的 `cleanDatabase()` 中的 `I18N.CleanDatabaseMsg(data.deleted)`），因此页面脚本很少硬编码用户可见文本。

## 模板与主题

- `templates/` 包含 26 个文件：24 个 Template Toolkit 模板（`.tt2`）外加 2 个生产环境错误页面
  （`exception.production.html.ep`、`not_found.production.html.ep`，由 Mojolicious 的 `.ep` 处理器渲染）。
  `templates/config.html.tt2` 由 `templates/templates_config/` 中的六个设置标签页组合而成
  （`config_global`、`config_theme`、`config_security`、`config_files`、`config_tags`、`config_shinobu`）。
  应用在 `lib/LANraragi.pm` 中将 Template Toolkit 设为默认渲染器（`default_handler('tt2')`）。

十四个模板是由控制器路由渲染的完整页面（鉴权类别以 `lib/LANraragi/Utils/Routing.pm` 的注册为准；
"公开"路由在 No-Fun Mode 下同样会移到会话登录之后）：

| 模板 | 渲染方 | 路由 |
|---|---|---|
| `index.html.tt2` | `Index.pm` 的 `index()` | `/`、`/index`（公开） |
| `reader.html.tt2` | `Reader.pm` 的 `index()` | `/reader`（公开） |
| `stats.html.tt2` | `Stats.pm` 的 `index()` | `/stats`（公开） |
| `login.html.tt2` | `Login.pm` 的 `index()`，密码错误时由 `check()` 重新渲染 | `GET`/`POST /login`（公开） |
| `i18n.html.tt2` | `Controller/I18N.pm` 的 `index()`，以 `application/javascript` 提供 | `/js/i18n.js`（公开） |
| `config.html.tt2` | `Config.pm` 的 `index()` | `/config`（需登录） |
| `plugins.html.tt2` | `Plugins.pm` 的 `index()` | `/config/plugins`（需登录） |
| `category.html.tt2` | `Category.pm` 的 `index()` | `/config/categories`（需登录） |
| `batch.html.tt2` | `Batch.pm` 的 `index()` | `/batch`（需登录） |
| `edit.html.tt2` | `Edit.pm` 的 `index()`，对 `TANK_` 前缀 ID 分派给 `edit_tankoubon()` | `/edit`（需登录） |
| `backup.html.tt2` | `Backup.pm` 的 `index()` | `/backup`（需登录） |
| `upload.html.tt2` | `Upload.pm` 的 `index()` | `/upload`（需登录） |
| `logs.html.tt2` | `Logging.pm` 的 `index()`（`/logs/*` 子页面返回原始文本，而非模板） | `/logs`（需登录） |
| `duplicates.html.tt2` | `Duplicates.pm` 的 `index()` | `/duplicates`（需登录） |

其余模板是没有自己路由的局部模板：`footer.html.tt2` 被 13 个页面模板 INCLUDE，
`common/importmap.html.tt2` 被 12 个 INCLUDE（除 `login` 和 `i18n` 外的所有页面）；六个
`templates_config/*` 标签页仅被 `config.html.tt2` INCLUDE；两个 OPDS XML 局部模板
（`opds.html.tt2`、`opds_entry.html.tt2`）由 `lib/LANraragi/Model/Opds.pm` 经
`render_to_string()` 渲染，而非任何控制器。`.ep` 文件覆盖 Mojolicious 内置的
`exception`/`not_found` 模板，且只在生产模式下渲染——`lib/LANraragi.pm` 会依据 `devmode`
设置显式设定运行模式。
- 主题是 `public/themes/` 下的普通样式表——基准时有五个：`ex.css`、`g.css`、`modern.css`、
  `modern_clear.css`、`modern_red.css`。`lib/LANraragi/Utils/Generic.pm` 中的 `generate_themes_header()`
  为每个主题输出一个 `<link>`（默认主题）或 `alternate stylesheet`（其余主题），并标注友好名称
  （依次为 Sad Panda、H-Verse、Hachikuji、Yotsugi、Nadeko）；选中的主题作为 `theme` 键存储在
  配置数据库中。放入该文件夹的任何 CSS 文件都会自动变为可选。
- 共享的页面框架样式（`lrr.css`、`config.css` 及第三方 CSS）位于 `public/css/` 之下。

### 配置页面逐标签页详解

`POST /config`（`lib/LANraragi/Controller/Config.pm` 中的 `save_config()`）把请求参数按一份
固定白名单复制进 `LRR_CONFIG`——13 个标量（`htmltitle`、`motd`、`dirname`、`thumbdir`、
`pagesize`、`tagrules`、`tempmaxsize`、`apikey`、`readerquality`、`sizethreshold`、`theme`、
`language`、`excludednamespaces`）和 16 个复选框（POST 中缺席即为 `0`）；表单提交的其余内容
一律忽略。`newpassword` 被特殊处理：提交 `enablepass` 且字段非空时散列为 `{CRYPT}` bcrypt 哈希
（留空则沿用已存储的密码；两次输入不一致会使保存失败），数值字段会做校验，`tagrules` 文本域还会被额外解析进 `LRR_TAGRULES`
列表。响应是普通 JSON，没有任何逻辑会重启服务器——需要重启的标签页只在文案里说明。

哪个标签页拥有哪个键并不总符合直觉：

| 标签页 | 键 / 操作 |
|---|---|
| 全局设置 | `htmltitle`、`motd`、`language`、`pagesize`、`enableresize`、`sizethreshold`、`readerquality`、`localprogress`、`authprogress`、`devmode`、`enablemetrics`——外加清理/清空数据库按钮 |
| 主题 | `theme`（由 `public/themes/` 生成的单选列表） |
| 安全 | `enablepass` 与 `newpassword`/`newpassword2`、`nofunmode`、`apikey`、`enablecors`、`disableopenapi` |
| 档案文件 | `dirname`（设置了 `LRR_DATA_DIRECTORY` 时禁用）、`enablecryptofs`、`tempmaxsize`、`replacedupe`——外加重扫、清理临时目录、重置缓存、清除新档按钮 |
| 标签与缩略图 | `thumbdir`（设置了 `LRR_THUMB_DIRECTORY` 时禁用）、`hqthumbpages`、`jxlthumbpages`、`usedateadded`、`usedatemodified`、`excludednamespaces`、`tagruleson`、`tagrules`——外加缩略图重生成按钮 |
| 后台工作者 | 无可写设置——Shinobu 状态轮询（`GET /api/shinobu`）、重启按钮和指向 `/minion` 的链接 |

`replacetitles` 是唯一的落单者：它的复选框位于插件配置页（`templates/plugins.html.tt2`），
由 `Controller/Plugins.pm` 自己的 `save_config` 经 `POST /config/plugins` 保存，而非主设置
表单。
