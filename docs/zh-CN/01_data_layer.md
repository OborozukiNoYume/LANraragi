# 数据层（Redis）

> 基准 commit `2094cc1d`（2026-09-04）。事实已对照代码核实——生成时已逐条核对引文。

LANraragi 将其全部状态保存在单个 Redis 实例中，并划分到五个带编号的逻辑数据库：档案元数据、Minion 任务队列、服务器配置、搜索索引/缓存以及运行时指标。文件系统只存储档案及其缩略图；所有可派生的内容（标签索引、标题索引、统计信息）都由 `LANraragi::Model::Stats::build_stat_hashes` 从 Redis 重建。

所有访问器都位于 `lib/LANraragi/Model/Config.pm`（`get_redis()`、`get_minion()`、`get_redis_config()`、`get_redis_search()`、`get_redis_metrics()`）。文本字段通过 `LANraragi::Utils::Redis::redis_encode()` 以 UTF-8 编码存储，只有一个有意为之的例外：档案的 `file` 字段保存未经编码的原始文件系统路径（见 `lib/LANraragi/Utils/Database.pm` 中的 `add_archive_to_redis()`）。

## 五个数据库

下表中的数据库编号是 `lrr.conf` 中的默认值；每个编号都可通过 `lib/LANraragi/Model/Config.pm` 读取的对应 `redis_database*` 键覆盖。

| DB | `lrr.conf` 键 | 句柄来源 | 内容 |
|----|----------------|-------------|----------|
| 0 | `redis_database` | `get_redis()` | 档案哈希（40 字符 ID）、分类哈希（`SET_*`）、合集 ZSET（`TANK_*`）——外加一个游离的 `LRR_CONFIG` 字段，见下文书签说明 |
| 1 | `redis_database_minion` | `get_minion()` | Minion 任务队列。其 schema 完全由 `Minion::Backend::Redis` 拥有；LANraragi 只负责将任务入队，从不手工写入键 |
| 2 | `redis_database_config` | `get_redis_config()` | `LRR_CONFIG`、`LRR_FILEMAP`、`LRR_TAGRULES`、`LRR_TOTALPAGESTAT`、`LRR_DUPLICATE_GROUPS`、`LRR_PLUGIN_*` |
| 3 | `redis_database_search` | `get_redis_search()` | 搜索索引集合与搜索缓存（见专门章节） |
| 4 | `redis_database_metrics` | `get_redis_metrics()` | 由 `lib/LANraragi/Model/Metrics.pm` 写入的运行时指标哈希（例如 `metrics:active_workers`、按进程统计的 CPU/内存计数器） |

## 实体

### 档案（DB0，Hash）

键是由 `lib/LANraragi/Utils/Database.pm` 中的 `compute_id()` 计算的 40 字符 SHA-1 十六进制 ID：它读取文件的前 512000 字节并对其求哈希（空输入的摘要 `da39a3ee…`——即空文件——会被拒绝）。需要“全部档案”的代码用 `keys('????????????????????????????????????????')` 枚举 40 字符键（例如 `lib/LANraragi/Model/Search.pm` 中的 `search_uncached()`、`lib/LANraragi/Model/Stats.pm` 中的 `build_stat_hashes()`）。

| 字段 | 含义 | 写入方 |
|-------|---------|-----------|
| `name` | 不含扩展名的文件名 | `lib/LANraragi/Utils/Database.pm` 中的 `add_archive_to_redis()` |
| `title` | 显示标题；写入时，小写化的标题也会（重新）插入 `LRR_TITLES` | `lib/LANraragi/Utils/Database.pm` 中的 `set_title()` |
| `tags` | 逗号分隔的标签字符串；写入经由 `update_indexes()`，后者维护 `INDEX_*`、`LRR_STATS`、`LRR_UNTAGGED`、`LRR_URLMAP` | `lib/LANraragi/Utils/Database.pm` 中的 `set_tags()` |
| `summary` | 自由文本描述 | `lib/LANraragi/Utils/Database.pm` 中的 `set_summary()` |
| `file` | 绝对文件系统路径（不经 redis 编码） | `add_archive_to_redis()` |
| `arcsize` | 文件大小（字节） | `add_archive_to_redis()` / `add_arcsize()` |
| `isnew` | `"true"`/`"false"`，同时镜像到 `LRR_NEW` 集合 | `lib/LANraragi/Utils/Database.pm` 中的 `set_isnew()` |
| `progress` | 当前阅读页 | `lib/LANraragi/Controller/Api/Archive.pm` 中的 `update_progress` |
| `pagecount` | 总页数 | `lib/LANraragi/Utils/Database.pm` 中的 `add_pagecount()` |
| `lastreadtime` | 上次阅读的 Unix 时间戳，与 `progress` 一同写入 | `lib/LANraragi/Controller/Api/Archive.pm` 中的 `update_progress` |
| `thumbjob` | 已入队的页面缩略图任务的 Minion 任务 ID；任务完成后删除 | `lib/LANraragi/Model/Archive.pm` 中的 `generate_page_thumbnails()`，清理位于 `lib/LANraragi/Utils/Minion.pm` |
| `thumbhash` | 提取出的封面图像的 SHA-1，供元数据插件用于画廊查找（例如 `lib/LANraragi/Plugin/Metadata/EHentai.pm` 中的 `lookup_gallery()`） | `lib/LANraragi/Utils/Archive.pm` 中的 `extract_thumbnail()` |
| `toc` | 将页码映射到章节标题的 JSON 对象 | `lib/LANraragi/Model/Archive.pm` 中的 `add_toc_entry()` / `remove_toc_entry()` |

**ID 生命周期。** `add_archive_to_redis()` 创建哈希后，立即把档案注册进 `LRR_TANKGROUPED`（新档案尚不可能属于任何合集）并打上 `isnew` 标记。如果文件内容的变化足以改变其哈希，`lib/LANraragi/Utils/Database.pm` 中的 `change_archive_id()` 会把哈希改名为新 ID，刷新 `arcsize`，并在所有引用旧 ID 的分类和合集中迁移成员关系。`clean_database()` 扫描 DB0 中后备文件已不存在的 40 字符键，并利用配置库的 `LRR_FILEMAP` 重新关联计算出的 ID 已发生漂移的文件。

### 分类（DB0，Hash）

键：`SET_` 后接 10 位 Unix 时间戳（共 14 字符——这也是 `get_category()` 中的有效性检查）。`lib/LANraragi/Model/Category.pm` 中的 `create_category()` 会持续把时间戳向前递增，直到该键空闲为止。分类通过 `get_category_list()` 中的 `keys('SET_??????????')` 枚举。

| 字段 | 含义 |
|-------|---------|
| `name` | 分类名称 |
| `search` | 搜索谓词；非空即让该分类成为动态分类 |
| `pinned` | 置顶标志 |
| `archives` | 档案 ID 的 JSON 数组；仅对静态分类有意义——对动态分类，`get_category()` 始终返回 `[]` |

### 合集（DB0，Sorted Set）

键：`TANK_` 后接 10 位 Unix 时间戳（共 15 字符，在 `get_tankoubon()` 中检查）。与档案和分类不同，合集是单个有序集合，其分值同时编码元数据和成员顺序（`lib/LANraragi/Model/Tankoubon.pm` 中的 `%TANK_METADATA` 映射；成员由 `update_metadata_field()` 以 `field_value` 字符串形式写入）：

| 分值 | 成员 |
|-------|--------|
| `>= 1` | 档案 ID；分值即阅读顺序中的位置（用 `zrangebyscore($tank_id, 1, "+inf")` 读回） |
| `0` | `name_<tank name>` |
| `-1` | `summary_<text>` |
| `-2` | `tags_<comma-separated tags>` |
| `-3` | `progress_<page>` |

## 搜索数据库（DB3）的键

| 键 | 类型 | 内容 |
|-----|------|----------|
| `LRR_TITLES` | 有序集合（所有分值为 0） | 成员是档案与合集的 `"<lowercased title>\0<id>"`。模糊过滤使用 `ZSCAN` 匹配，标题排序使用 `ZRANGEBYLEX`（`lib/LANraragi/Model/Search.pm`）；空字节分隔符之所以得以保留，是因为标题会被去掉 CR/LF（`set_title()`、`build_stat_hashes()`） |
| `INDEX_<tag>` | 集合 | 带有该小写标签的档案（及合集）的 ID。合集按其*统一*标签集——自身标签加上从成员档案推得的标签——由 `lib/LANraragi/Model/Tankoubon.pm` 中的 `update_tank_imputed_indexes()` 建立索引 |
| `LRR_NEW` | 集合 | `isnew = true` 的 ID |
| `LRR_UNTAGGED` | 集合 | 在“基础”命名空间（`artist`、`parody`、`series`、`language`、`event`、`group`、`date_added`、`timestamp`、`source`——见 `lib/LANraragi/Utils/Database.pm` 中的 `update_indexes()`）之外没有任何标签的档案 |
| `LRR_TANKGROUPED` | 集合 | 感知分组的可见集合：全部合集 ID 加上未包含在任何合集中的全部档案 ID；由 `lib/LANraragi/Model/Tankoubon.pm` 维护，并在启用合集分组时用作基础 ID 列表（`do_search()` / `search_uncached()`） |
| `LRR_URLMAP` | 哈希 | `source:` 标签 URL 到档案 ID 的映射；由 `lib/LANraragi/Model/Stats.pm` 中的 `is_url_recorded()` 查询 |
| `LRR_STATS` | 有序集合 | 标签到出现次数的映射；通过 `lib/LANraragi/Model/Stats.pm` 中的 `build_tag_stats()` 支撑标签云 |
| `LRR_SEARCHCACHE` | 哈希 | 搜索结果缓存，详见下文 |
| `LAST_JOB_TIME` | 字符串 | 在 `build_stat_hashes()` 结尾设置的时间戳；该键不存在时，`do_search()` 会报告引擎未初始化（返回 `-1`） |

以上全部均可重建。`build_stat_hashes()` WATCH 这些索引键，在 MULTI 内对整个搜索数据库执行 `flushdb`，然后从 DB0 重写所有内容；`invalidate_cache(1)` 会把它作为 `build_stat_hashes` Minion 任务入队。

### 一次搜索如何执行

下面按步骤走读 `lib/LANraragi/Model/Search.pm` 中的 `do_search()` / `search_uncached()`——这有助于理解上述各键如何协作：

1. 如果 `LAST_JOB_TIME` 不存在，说明引擎未初始化；API 返回 `-1`。
2. 构造八段式缓存键并探测 `LRR_SEARCHCACHE`（包括倒序孪生键）；按 `lastread` 排序的查询完全跳过缓存。
3. 播下候选列表：启用合集分组时取 `LRR_TANKGROUPED` 的成员，否则取 DB0 中全部 40 字符键。
4. 应用分类：动态分类的 `search` 字符串被解析为额外的过滤词元；静态分类的 `archives` JSON 列表与候选取交集。
5. 应用开关：仅看无标签与 `LRR_UNTAGGED` 取交集；仅看新档与 `LRR_NEW` 取交集（任一成员档案为新则合集匹配）；隐藏已读完会丢弃 `progress`/`pagecount` 超过 85% 的档案——先用 Lua 脚本对 DB0 哈希批量检查，并回退到逐 ID 的 `HGET`。
6. 应用过滤词元：精确标签直接读取 `INDEX_<tag>`，非精确标签对 `INDEX_*` 键做通配，每个词元还通过在 `LRR_TITLES` 上的 `ZSCAN` 模糊匹配标题。特殊的 `read:`/`pages:` 词元按数值比较 DB0 的 `progress`/`pagecount` 字段（支持 `>`、`<`、`>=`、`<=`，裸数字表示精确匹配）。
7. 排序：按标题排序通过在 `ZRANGEBYLEX LRR_TITLES` 上的 `nsort`；按 `lastread` 排序通过 `lastreadtime`（合集取成员档案中的最大值）；按其他任意键排序通过该命名空间中的第一个标签值，缺失该命名空间的 ID 被排到末尾。
8. 最终的 ID 列表（以带键计数为前缀）按缓存键固化进 `LRR_SEARCHCACHE`。

## 配置数据库（DB2）的键

| 键 | 类型 | 内容 |
|-----|------|----------|
| `LRR_CONFIG` | 哈希 | 服务器设置，通过 `lib/LANraragi/Model/Config.pm` 中的 `get_redis_conf(param, default)` 读取 |
| `LRR_FILEMAP` | 哈希 | 绝对文件路径到档案 ID 的映射；由 Shinobu 监视器（`lib/Shinobu.pm`）写入，由 `lib/LANraragi/Utils/Database.pm` 中的 `clean_database()` 和 `lib/LANraragi/Model/Upload.pm` 读取 |
| `LRR_TAGRULES` | 列表 | 扁平化的标签规则（`lib/LANraragi/Utils/Database.pm` 中的 `save_computed_tagrules()` / `get_computed_tagrules()`） |
| `LRR_TOTALPAGESTAT` | 字符串 | 总阅读页数计数器，每次进度更新时 INCR（`lib/LANraragi/Controller/Api/Archive.pm` 中的 `update_progress`），由 `lib/LANraragi/Model/Stats.pm` 中的 `get_page_stat()` 读取 |
| `LRR_DUPLICATE_GROUPS` | 哈希 | `dupgp_<key>` 到档案 ID 的 JSON 数组的映射；由重复检测 Minion 任务生成（`lib/LANraragi/Utils/Minion.pm`）；由 `lib/LANraragi/Controller/Duplicates.pm` 读取、修剪并重写（成员已消失的分组会被删除或重写，`delete` 请求会清空整个哈希） |
| `LRR_PLUGIN_<NAMESPACE>` | 哈希 | 各插件的状态，插件命名空间转为大写：`enabled`、`customargs`（JSON 数组）、`installed_path`、`installed_version`、`installed_registry`、`installed_sha256`、`type`（`lib/LANraragi/Utils/Plugins.pm`、`lib/LANraragi/Model/Plugins.pm`） |

`LRR_CONFIG` 中代码会读取的字段（非穷举——配置页面还可以写入其他字段；默认值以 `lib/LANraragi/Model/Config.pm` 读取到的为准）：

| 字段 | 默认值 | 字段 | 默认值 |
|-------|---------|-------|---------|
| `dirname` | `./content` | `apikey` | *（空）* |
| `thumbdir` | `./thumb` | `localprogress` | `0` |
| `devmode` | `0` | `authprogress` | `0` |
| `password` | bcrypt 哈希（默认：`kamimamita`） | `tagruleson` | `1` |
| `tagrules` | 排除列表 | `enableresize` | `0` |
| `disableopenapi` | `0` | `sizethreshold` | `1000` |
| `htmltitle` | `LANraragi` | `readerquality` | `50` |
| `motd` | 欢迎语 | `theme` | `modern.css` |
| `tempmaxsize` | `500` | `usedateadded` | `1` |
| `pagesize` | `100` | `usedatemodified` | `0` |
| `enablepass` | `1` | `enablecryptofs` | `0` |
| `nofunmode` | `0` | `hqthumbpages` | `0` |
| `enablecors` | `0` | `jxlthumbpages` | `0` |
| `enablemetrics` | `0` | `replacedupe` | `0` |
| `language` | `auto` | `replacetitles` | `1` |
| `excludednamespaces` | `source, date_added` | | |

### `bookmark_link` 的注意事项

`bookmark_link`（阅读器书签按钮背后的分类）名义上是一个 `LRR_CONFIG` 字段，但其每次读写都经由 `lib/LANraragi/Model/Category.pm`（`get_bookmark_link()`、`update_bookmark_link()`、`remove_bookmark_link()`、`delete_category()`）在 `get_redis()` 返回的句柄上进行——也就是说它存储在 **DB0 中**的 `LRR_CONFIG` 哈希里，而不是配置数据库中。首次运行的初始化通过 `lib/LANraragi/Model/Setup.pm` 建立该关联。转储或迁移 DB2 的 `LRR_CONFIG` 的工具将看不到这个字段。

## 搜索缓存与失效

`lib/LANraragi/Model/Search.pm` 中的 `do_search()` 将结果缓存到 `LRR_SEARCHCACHE` 哈希中：

- 字段名：八个搜索参数以连字符连接后再经 `redis_encode()` 处理——
  `"$category_id-$filter-$sortkey-$sortorder-$newonly-$untaggedonly-$grouptanks-$hidecompleted"`。
- 值：`[ $keyed_count, @ids ]` 的 Storable `nfreeze` 结果，其中开头的计数表示有多少 ID 带有排序命名空间。
- 未命中时会尝试排序顺序*相反*的键；`check_cache()` 随后只反转带键前缀，使缺失排序键的 ID 仍留在末尾。
- 按 `lastread` 排序的搜索从不使用缓存：设置 `lastreadtime` 有意不做缓存失效，因此历史排序总是重新计算。

`lib/LANraragi/Utils/Database.pm` 中的 `invalidate_cache()` DELETE 掉 `LRR_SEARCHCACHE` 并重新写入一个 `created` 时间戳字段；传入真值参数时，它还会将 `build_stat_hashes` 索引重建任务入队（供 `lib/LANraragi/Controller/Api/Database.pm` 中的数据库清空/清理端点使用）。

`invalidate_cache()` 的已核实调用方：`set_tags()` 和 `set_isnew()`（`lib/LANraragi/Utils/Database.pm`）、档案元数据编辑（`lib/LANraragi/Model/Archive.pm` 中的 `update_metadata()`）、分类成员变更（`lib/LANraragi/Model/Category.pm`）、所有合集变更（`lib/LANraragi/Model/Tankoubon.pm`）、Shinobu 的文件新增/编辑/删除回调（`lib/Shinobu.pm`）、备份恢复（`lib/LANraragi/Model/Backup.pm`）、上传（`lib/LANraragi/Model/Upload.pm`）、批量打标签（`lib/LANraragi/Controller/Batch.pm`）、`nHentaiSourceConverter` 脚本插件（`lib/LANraragi/Plugin/Scripts/nHentaiSourceConverter.pm`），以及搜索缓存端点（`lib/LANraragi/Controller/Api/Search.pm` 中的 `clear_cache()`）。清除新档标志端点（`lib/LANraragi/Controller/Api/Database.pm` 中的 `clear_new_all()`）*不*触碰搜索缓存——它只重置 `isnew` 字段并删除 `LRR_NEW`。

值得注意的*不*触发缓存失效的操作：阅读进度更新（`update_progress` 只写入 `progress`/`lastreadtime`，如上所述）以及单纯的 `set_title()`/`set_summary()` 调用——`update_metadata()` 中的元数据编辑路径会为 UI 失效缓存，因此直接的模型级标题编辑只会刷新 `LRR_TITLES` 索引。

## 环境变量

环境变量覆盖的优先级高于 `lrr.conf` 和 `LRR_CONFIG`：

| 变量 | 作用 | 读取方 |
|----------|--------|---------|
| `LRR_REDIS_ADDRESS` | 覆盖 `redis_address`（host:port 或 unix socket 路径） | `lib/LANraragi/Model/Config.pm` 顶部 |
| `LRR_DATA_DIRECTORY` | 覆盖内容目录（`dirname`） | `lib/LANraragi/Model/Config.pm` 中的 `get_userdir()`；目录由 `script/launcher.pl` 创建 |
| `LRR_THUMB_DIRECTORY` | 覆盖缩略图目录（`thumbdir`） | `lib/LANraragi/Model/Config.pm` 中的 `get_thumbdir()` |
| `LRR_TEMP_DIRECTORY` | 覆盖临时文件夹；同时存放服务器 PID 文件 | `lib/LANraragi/Utils/TempFolder.pm` 和 `script/launcher.pl` |
| `LRR_LOG_DIRECTORY` | 覆盖日志文件夹 | `lib/LANraragi/Utils/Logging.pm` |
| `LRR_FORCE_DEBUG` | 无视 `devmode` 设置强制开启开发模式 | `lib/LANraragi/Model/Config.pm` 中的 `enable_devmode()` |
| `LRR_NETWORK` | 覆盖 Hypnotoad 监听地址/端口 | `script/launcher.pl` |

同族还有另外两个变量：`LRR_DEVSERVER`（在 `get_redis_internal()` 中启用 Redis 客户端调试标志，并在 `lib/LANraragi/Utils/Logging.pm` 中启用一种日志模式）和 `LRR_DISABLE_OPENAPI`（在 `get_disable_openapi()` 中强制关闭 OpenAPI 文档）。
