# 06 - 模型层

> 基准 commit `2094cc1d`（2026-09-04）。事实已对照代码核实——生成时已完成引证核查。

模型层（`lib/LANraragi/Model/`）承载 LANraragi 位于控制器与 Redis 之间的业务逻辑。
每个模块都通过 `LANraragi::Model::Config` 的连接工厂访问 Redis，而大多数长时间运行的工作
（缩略图生成、插件运行、备份）被委派给 Minion 任务——任务本身定义在
`lib/LANraragi/Utils/Minion.pm`，并在“实用工具”（Utilities）一章中介绍；本章仅引用它们。

`lib/LANraragi/Model/` 中的全部 16 个模块：

| 模块 | 一句话职责 |
|---|---|
| `Config.pm` | 配置访问：Redis 连接工厂、带默认值的 `LRR_CONFIG` 读取。 |
| `Search.pm` | 搜索引擎：令牌解析、过滤、排序、结果缓存。 |
| `Archive.pm` | 档案生命周期：页面/缩略图提供、元数据、ToC、删除。 |
| `Upload.pm` | 将上传/下载的文件纳入资料库。 |
| `Backup.pm` | 全部用户元数据的 JSON 导出/导入。 |
| `Category.pm` | 分类（`SET_` 键），包括书签链接。 |
| `Tankoubon.pm` | 单行本（Tankoubon）集合（`TANK_` 键，各为一个 Redis 有序集合）。 |
| `Reader.pm` | 服务器端阅读器支持：页面列表 JSON、基于质量的尺寸调整。 |
| `Plugins.pm` | 插件发现、执行、从注册表安装/卸载。 |
| `Registry.pm` | 插件注册表（GitHub/Gitea/CDN/本地源）。 |
| `Stats.pm` | 搜索索引与标签统计的构建。 |
| `Stamp.pm` | 页面戳记/书签（`STAMPS_*` 键）。 |
| `Opds.pm` | OPDS 1.2 目录 + PSE 页面流式传输。 |
| `Metrics.pm` | Prometheus 指标收集。 |
| `Setup.pm` | 首次安装动作（默认分类 + 默认注册表）。 |
| `Server.pm` | 服务器状态标志（重启待定标记）。 |

## 配置：`Model/Config.pm`

`Config.pm` 在编译期引导加载 `lrr.conf`（可通过 `LRR_REDIS_ADDRESS` 覆盖），并暴露五个逻辑
Redis 数据库：档案（`redis_database` 0）、Minion（`redis_database_minion` 1）、配置
（`redis_database_config` 2）、搜索（`redis_database_search` 3）、指标（`redis_database_metrics` 4），与
`lrr.conf` 中的默认值一致。五个连接工厂发放通往正确数据库的新建连接——
`get_redis()`、`get_redis_config()`、`get_redis_search()`、`get_redis_metrics()`，全部构建于
`get_redis_internal()` 之上——另有 `get_minion()`，为 Minion 数据库构造
`Minion` 客户端。调用方有责任对自己取得的连接调用 `quit()`。

运行时设置位于配置数据库的 `LRR_CONFIG` 哈希中；`get_redis_conf($param, $default)` 返回
存储值或内置默认值，一长串访问器包装函数（返回原始 Redis 字符串）封装了它（`get_pagesize`、
`get_thumbdir`、`get_userdir`、`enable_resize`、`get_threshold`、`get_readquality`、`enable_pass`、
`enable_nofun`、`enable_cors`、`enable_metrics`、`enable_localprogress`、`enable_authprogress`、
`get_replacedupe`、`get_hqthumbpages`、`get_jxlthumbpages`、`get_style`、`get_language`、……）。
`get_baseurl()` 为前端章节所述的路径前缀处理提供输入。

## 搜索：`Model/Search.pm`

`do_search($filter, $category_id, $start, $sortkey, $sortorder, $newonly, $untaggedonly, $grouptanks,
$hidecompleted)` 接收九个参数。在 `LAST_JOB_TIME` 键存在（即索引构建任务运行过一次）之前它拒绝
执行，并返回 `(total, filtered_count, @ids)`。

缓存：完整结果列表经 Storable `nfreeze` 后存入搜索数据库的 `LRR_SEARCHCACHE` 哈希，缓存
键由九个参数中的八个构成（不含 `$start`，它在切分缓存列表时才应用）。`check_cache()` 还会查找排序顺序*相反*的键——由于反转一个已排序的列表
会得到相反的顺序，这将缓存空间减半（只有带键的前缀被反转，因此缺少排序命名空间的档案仍留在
末尾）。存在两种绕过：`lastread` 排序总是不经缓存运行（阅读进度的更新不会使缓存失效），而任何
结构性变更都会调用 `LANraragi::Utils::Database` 的 `invalidate_cache()`。

过滤（`search_uncached()`）从全部 40 字符的档案 ID 出发——或在 `$grouptanks` 将单行本与其档案
分组时改用 `LRR_TANKGROUPED` 集合——然后逐令牌与下列项求交集：

- 标签匹配使用 `INDEX_<tag>` 集合（未加引号时为模糊匹配；令牌中的命名空间会锚定索引扫描），
- 标题匹配使用对 `LRR_TITLES` 有序集合的 `zscan`（成员为 `title\0id`），
- 集合过滤器：分类档案或动态分类自身的搜索令牌、`LRR_UNTAGGED`、`LRR_NEW`，
- `$hidecompleted`：一个 Lua 脚本按 ID 批量检查 `progress/pagecount > 0.85`（带逐 ID 的 HGET 回退），
- `pages:`/`read:` 令牌以 `=`、`>`、`>=`、`<`、`<=` 与 `pagecount`/`progress` 哈希字段比较。

搜索语法：令牌化由 `compute_search_filter()` 完成——逗号分隔的令牌；`"quoted"` 或末尾的 `$` 强制精确
匹配；前导 `-` 表示排除；`?`/`_` 匹配单个字符，`*`/`%` 匹配任意数量字符（重写为 Redis glob
元字符）——而 `namespace:value` 的限定由 `search_uncached()` 应用，它把索引扫描锚定到
`INDEX_<ns>:tag*` 而非 `INDEX_*tag*` 键上。排序（`sort_results()`）要么按标题经由
`LRR_TITLES` 的自然排序，要么按任意标签命名空间（用正则提取，缺失值作为 `zzzz` 沉到
末尾），要么按 `lastreadtime`——lastread 与标签路径通过 Lua 脚本（`script_load` + `evalsha`）
批量取值，并带有纯 Perl 回退（`_fallback_lastread`、`_fallback_tags`），而
`_impute_tank_date_tags()` 从成员档案为单行本推断 `date_added`/`timestamp` 排序键。

## 档案：`Model/Archive.pm`

- `serve_page($id, $path)`：按需从档案中提取文件，经由
  `get_page_data()`/`LANraragi::Utils::PageCache`（缓存键 `page/$id/$path`）；启用尺寸调整时，
  结果会经过 `Model::Reader::resize_image()` 并缓存于 `resize_page/$id/$path/$threshold/$quality`。
  CBW（网络流式）档案还会触发 `cbw_prefetch()` 预热接下来的页面。
- `serve_thumbnail($id)` / `update_thumbnail($id)`：缩略图位于缩略图目录之下，按 ID 的前两个字符
  分目录存放，格式为 `jpg` 或 `jxl`（取决于 `get_jxlthumbpages()`），并带跨格式回退。缺失的
  缩略图要么返回 `public/img/noThumb.png`，要么——当客户端传入 `no_fallback=true` 时——将
  `thumbnail_task` Minion 任务入队并返回 `202` 与任务 ID。
- `generate_page_thumbnails($id)`：扫描缺失的逐页缩略图并将 `page_thumbnails` Minion
  任务入队（以 `thumbjob` 哈希字段去重；已入队任务处于 pending 或 running 时返回 `202`）。
- `update_metadata($id, $title, $tags, $summary)`：修剪输入，经由数据库工具写入，并使缓存失效。
- ToC 管理：`add_toc_entry($id, $page, $title)` / `remove_toc_entry($id, $page)` 维护档案的
  `toc` JSON 哈希（{ page → title }），阅读器覆盖层将其转换为章节。
- `delete_archive($id)`：将档案从每个包含它的单行本和分类中移除，删除文件与缩略图
  的链接，并删除 Redis 条目。

## 入库：`Model/Upload.pm`

`handle_incoming_file($tempfile, $catid, $tags, $title, $summary)` 返回 `(status, id, name, message)`：

1. 以 `415` 拒绝非档案文件；用 `compute_id()` 计算 ID（取文件前 512 KB 的 SHA-1，
   经由数据库工具）；
2. **上传时重复拒绝**（`replacedupe` 检查）——如果该 ID 已存在（且其文件在磁盘上）或存在同名文件，返回
   `409`，除非 `replacedupe` 设置允许替换；允许时先删除旧档案/文件（文件名冲突通过
   `LRR_FILEMAP` 哈希解决）；
3. 在 Redis 中登记档案，应用调用方提供的标签——`source:<url>` 标签还会写入
   `LRR_URLMAP` 哈希（搜索数据库），使 URL 查询无需完整重建索引即可解析——随后是可选的标题/摘要；
4. 分两阶段移动文件：temp → `<target>.upload` → 在内容文件夹内重命名，这样 Shinobu
   文件监视器只会看到完整文件（任一移动失败时返回 `500` 消息）；
5. 添加 `date_added`/页数/大小，生成缩略图，运行自动插件
   （`Plugins::exec_enabled_plugins_on_file`），可选地加入分类，并使搜索缓存失效。

`download_url($url, $ua)` 实现下载器的另一半：重试获取 `Content-Disposition` 头，解码
文件名（UTF-8/Latin-1/RFC 5987/URL 尾部回退），去除 Windows 非法字符，按
文件系统字节上限截断（依 `enable_cryptofs` 为 143/255），并将文件暂存在 `File::Temp`
目录中交给 `handle_incoming_file`。

## 备份：`Model/Backup.pm`

`build_backup_JSON($job)` 遍历 Redis，生成包含四个顶层数组的 JSON 文档——`categories`
（来自 `SET_` 键：catid/name/search/archives）、`tankoubons`（经由
`Tankoubon::get_tankoubon_list(-1)`：tankid/name/summary/tags/archives）、`stamps`（来自
`STAMPS_*` 键：stamp_id/content/position/archive_id）和
`archives`（全部 40 字符 ID 及 arcid/title/tags/summary/thumbhash/filename，外加档案级的 `stamps`
列表和 `toc` 字段）。作为 Minion 任务调用时，它通过 `$job->note(...)` 报告任务进度。

`restore_from_JSON($json, $job)` 先调用 `clean_database()` 清除既有用户元数据，然后重建
分类（`Category::create_category` + `add_to_category`）、单行本（`create_tankoubon`、
`update_metadata`、`set_tank_tags`、`update_archive_list`）、**仅针对仍然存在的 ID** 的档案
元数据（title/tags/summary/thumbhash/stamps/toc——缺失时 `stamps`/`toc` 默认为 `[]`/`{}`），最后
是 `STAMPS_*` 哈希，同样仅当其档案幸存时才恢复。结束时触发 `invalidate_cache()`。

## 集合：`Model/Category.pm` 与 `Model/Tankoubon.pm`

分类是带有 `name`、`search`（动态分类）和 `archives`（JSON 数组；
静态分类）的 `SET_<timestamp>` 哈希。`create_category()` 可以复用调用方提供的 ID（供备份
恢复使用）；`add_to_category()`/`remove_from_category()` 维护该数组；`get_bookmark_link()`/
`update_bookmark_link()` 管理与阅读器书签按钮绑定的那个特殊分类（以
`/api/categories/bookmark_link` 暴露给前端，并以 `bookmarkCategoryId` 缓存在 localStorage 中）。

单行本（Tankoubon）是键为 `TANK_<timestamp>`（15 字符）的单个 Redis **有序集合**：成员档案位于
分值 `>= 1`（分值*即*页序），而元数据存放在非正分值的保留成员中——`name` 位于
`0`、`summary` 位于 `-1`、`tags` 位于 `-2`、`progress` 位于 `-3`（参见 `%TANK_METADATA` 映射和
`fetch_metadata_fields()`）。`get_tankoubon()` 重组该对象（通过 `zrangebyscore ...
LIMIT` 分页）；`update_archive_list()`/`add_to_tankoubon()`/`remove_from_tankoubon()` 重写成员分值；
`update_tank_progress($tank_id, $page)` 通过 `update_metadata_field()` 记录阅读位置；
`set_tank_tags()` 还维护标签索引；`get_tank_unified_tags()` 合并成员标签（带推断的
`date_added`）用于搜索/排序。单行本在索引构建期间登记到 `LRR_TANKGROUPED` 集合。

## 阅读器与 OPDS：`Model/Reader.pm`、`Model/Opds.pm`

`Reader.pm` 刻意保持小巧：`build_reader_JSON()` 打开档案，返回面向浏览器的页面
路径（URL 转义，每个指向 `/api/archives/{id}/page?path=...`）并刷新存储的 `pagecount`；
`resize_image($content, $quality, $threshold)` 是模型级的尺寸调整入口，内部对由
`LANraragi::Utils::Resizer` 的 `get_resizer()` 构建的重采样器调用
`resize_page()`（当图片小于尺寸阈值或重采样调用返回 undef 时，原样返回
原始字节）。

`Opds.pm` 渲染 OPDS 1.2 源：`generate_opds_catalog()` 通过
`Search::do_search` 按页/分类列出档案，`generate_opds_item()` 渲染单个条目，二者都经由
`opds`/`opds_entry` 模板。`get_opds_data()` 从 `artist`/`language`/`group`/`event` 标签推导
作者/语言/社团/活动，并映射文件扩展名 → MIME 类型：`.pdf` → `application/pdf`、`.rar`/`.cbr` →
`application/x-cbr`、`.epub` → `application/epub+zip`、`.cbw` → `application/xml`，其余
（zip/cbz）→ `application/x-cbz`。PSE（Page Streamed Extension）支持位于同样的模板中：条目内嵌
指向 `/api/opds/{id}/pse?page={pageNumber}` 的
`http://vaemendis.net/opds-pse/stream` 链接，带 `pse:count`/`pse:lastRead` 属性；该端点
（`Controller/Api/Other.pm` 的 `serve_opds_page`）调用
`Opds::render_archive_page()`，后者根据档案的文件列表解析页码，并经由
`Archive::serve_page()` 提供该页。目录分页按通用的 `pagesize` 设置对 `do_search` 切片，
并输出一个无条件的 `rel="next"` 链接（`start` 前进已提供的条目数；没有 `rel="prev"`），
同时在所有链接中携带 `?key=`；各分类成为 OPDS facet，`thr:count` 仅对没有保存搜索串的分类
输出。源级别的
`<updated>` 时间戳是硬编码的（`templates/opds.html.tt2` 中的
`2010-01-10T10:03:10Z`）；条目时间戳派生自各档案的 `date_added` 标签。在
`render_archive_page()` 中，PSE 页码从 1 开始，超出范围时回绕到第 1 页——负数会
从文件列表末尾开始索引（一个怪癖，未做钳制），不过端点的 `|| 1` 默认值会在到达模型前把
`page=0` 掩盖为 1。

## 插件与注册表：`Model/Plugins.pm`、`Model/Registry.pm`

`Plugins.pm` 涵盖：

- 执行：`exec_enabled_plugins_on_file($id)`（上传后的自动插件轮）、`exec_metadata_plugin()`、
  `exec_script_plugin()`、`exec_download_plugin()`、`exec_login_plugin()`（下载器使用的已配置
  登录插件）。
- 安装状态：插件记录在 `LRR_PLUGIN_<NAMESPACE>` 哈希之下。`install_plugin($namespace, ...)`
  区分内置插件与注册表托管（“managed”）插件，没有 `force` 时拒绝跨注册表覆盖，并从其
  所属注册表复制插件文件进来；`uninstall_plugin()` 删除托管插件文件，以 `403` 拒绝
  卸载内置插件，注销该插件，并通过 `Server::set_restart_pending()` 标记需要
  重启服务器。`scan_plugins()`（也在每次启动时由 `lib/LANraragi.pm` 运行）将发现的
  插件类（经 `LANraragi::Utils::Plugins` 的 `Module::Pluggable` 发现）与 Redis
  登记状态对账。

`Registry.pm` 管理插件的来源——注册表条目（`REG_<timestamp>` ID）支持四种
提供方（`github`、`gitea`、`cdn`、`local`，见 `%PROVIDER_FIELDS`），提供创建/更新/删除/列表操作，外加
`refresh_registry()`（抓取并校验注册表索引，上限为 100 MB 的 `MAX_REGISTRY_INDEX_SIZE`）
和默认注册表访问器。`lib/LANraragi.pm` 在启动时刷新每个注册表。

## 小型模块

- **`Stamp.pm`** —— 页面戳记（“给第 N 页 bookmark 一条笔记”）。`add_stamp()` 创建
  `STAMPS_<page>_<millis>` 哈希（content/position/archive_id）并把 ID 追加到档案的 `stamps`
  JSON 数组；`get_stamps_by_page()`、`get_stamped_pages()`、`update_stamp()`、`remove_stamp()`
  补全 CRUD。
- **`Stats.pm`** —— `build_stat_hashes()`（作为 `build_stat_hashes` Minion 任务在启动时和数据库级
  重建时运行——只有 `invalidate_cache(1)`，即清空/清理数据库端点，会将其入队）
  在一个 WATCH/MULTI 事务中重建整个搜索数据库：`flushdb()`，然后逐
  档案/单行本构建 `INDEX_<tag>` 集合、`LRR_TITLES`、`LRR_STATS`（标签计数器）、`LRR_UNTAGGED`、
  `LRR_NEW`、`LRR_TANKGROUPED`，最后写入 `LAST_JOB_TIME` 时间戳。还暴露针对 `LRR_URLMAP` 的
  `is_url_recorded()`。读取侧为 `/stats` 页面和标签统计 API 供数：`get_archive_count()` 是
  `scard(LRR_TANKGROUPED)`（单行本替代其成员档案计数）、`compute_content_size()` 把每个
  `arcsize` 哈希字段求和为 GB（两位小数），`get_page_stat()` 读取 `LRR_TOTALPAGESTAT`；标签
  云本身由客户端从 `GET /api/database/stats` 抓取——`serve_tag_stats()`（`minweight`，默认 1；
  `hide_excluded_namespaces`，默认关——为 true 时排除 `excludednamespaces` 配置，默认
  `source, date_added`）经 `build_tag_stats()` 用
  `zrangebyscore($minweight, "+inf", WITHSCORES)` 从 `LRR_STATS` 切片，返回
  `[{namespace, text, weight}]`——标签文本为小写，命名空间前缀拆分进独立字段。`stats.js` 与
  首页建议以 `minweight=2&hide_excluded_namespaces=true` 请求它；编辑页使用 `minweight=2`
  且不隐藏。
- **`Metrics.pm`** —— Prometheus 支持，由 `enablemetrics` 设置门控：
  `collect_request_metrics()`（经由安装在 `lib/LANraragi.pm` 中的 `after_dispatch`
  钩子，其 `before_dispatch` 对应钩子只暂存请求起始时间）、按 30 秒循环定时器运行的 `collect_process_metrics()` 和
  `flush_request_metrics_to_redis()`、worker 跟踪（`register_worker`/`unregister_worker`），
  以及 `get_prometheus_*` 渲染器。
- **`Setup.pm`** —— `first_install_actions()` 通过 `LRR_CONFIG → htmltitle` 的缺失检测全新
  安装，创建默认的“🔖 Favorites”分类，将其链接到书签按钮，并播种默认插件
  注册表（“Ougi”、`https://github.com/Difegue/Ougi.git`、分支 `main`）。
- **`Server.pm`** —— 配置数据库中仅有的一个 `LRR_SERVER` 哈希，持有 `restart_pending`
  标志：`set_restart_pending()`（插件卸载后，以及替换已注册插件的安装后）、`clear_restart_pending()`（启动时）、
  `is_restart_pending()`（由 UI 轮询以提示重启）。
