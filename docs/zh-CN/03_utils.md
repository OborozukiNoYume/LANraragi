# 工具模块巡礼：`lib/LANraragi/Utils/`

> 基准 commit `2094cc1d`（2026-09-04）。事实已对照代码核实——生成时已逐条核对引文。

## 概览

`lib/LANraragi/Utils/` 下的所有内容都是无状态的粘合代码，供各类 Model 和 Controller 依托。各模块职责一行一条：

| 模块 | 职责 |
|--------|----------------|
| `Archive.pm` | 读取档案（zip/cbz 经 libarchive，PDF 经 VIPS，CBW 经 HTTP）、解压页面、生成缩略图 |
| `Database.pm` | Redis 中的档案记录：ID 计算、标签/标题/摘要写入、JSON 序列化、索引维护 |
| `Generic.pm` | 大杂烩：图片/档案检测、基于 Redis 的锁、Minion/Shinobu 进程启动、CSS 主题列表 |
| `I18N.pm` | `Locale::Maketext` 子类，从 `locales/template/` 加载 gettext `.po` 文件 |
| `I18NInitializer.pm` | 安装 `lh` Mojolicious helper；解析强制语言或 `Accept-Language` |
| `ImageMagickResizer.pm` | 基于 `Image::Magick` 的备用缩放器实现 |
| `Logging.pm` | 日志器构建（`get_logger`）、插件日志器、日志文件读取 |
| `Login.pm` | `is_logged_in_api()` —— API key / 会话检查 |
| `Metrics.pm` | Prometheus 文本暴露：路由规范化加 `/proc` 计数器 |
| `Minion.pm` | 在 Minion 实例上注册所有后台任务 |
| `OpenAPI.pm` | `apply_openapi_mojo_overrides()` —— `disable_openapi` 时绕过校验，否则照常校验并记录失败日志 |
| `PageCache.pm` | 基于 CHI 的页面缓存（Unix 上用 FastMmap，Windows 上用 Memory） |
| `Path.pm` | 文件系统辅助函数：路径创建/打开、档案路径查找、包<->路径转换 |
| `Plugins.pm` | 插件注册表粘合：列出、加载、参数、在 Redis 中注册 |
| `Redis.pm` | `redis_encode()`/`redis_decode()` UTF-8 边界辅助函数 |
| `Registry.pm` | 获取/校验插件注册表资源（git raw URL、CDN 产物、索引 schema） |
| `Resizer.pm` | `get_resizer()` 工厂：可用时用 libvips，否则用 ImageMagick |
| `RotatingLog.pm` | `Mojo::Log` 子类，带基于大小的轮转和 `flock` 加锁 |
| `Routing.pm` | `apply_routes()` —— 完整路由表、CORS/鉴权桥接、OpenAPI 设置 |
| `String.pm` | 标题清理、修剪、URL 修剪、相似度排序 |
| `Tags.pm` | 标签规则解析与应用（`rewrite_tags`） |
| `TempFolder.pm` | `get_temp()` —— 定位/创建临时文件夹 |
| `Vips.pm` | libvips 的 FFI 绑定，包括 PDF 加载器 |
| `VipsResizer.pm` | 基于 libvips 的首选缩放器实现 |

## 档案、图片与 PDF

`lib/LANraragi/Utils/Archive.pm` 导出 `is_file_in_archive`、`extract_file_from_archive`、
`extract_single_file`、`extract_thumbnail`、`generate_thumbnail`、`get_filelist`、`is_cbw`、
`parse_cbw_urls` 和 `cbw_prefetch`。它依赖三个彼此独立的后端，按文件类型选择：

- **档案（zip/cbz 等）**走 `Archive::Libarchive`（同时使用 `ArchiveRead` 和
  `Peek` 两种接口）。`get_filelist()` 遍历条目，跳过非图片文件和 AppleDouble/
  AppleSingle 垃圾文件（见内部函数 `is_apple_signature()`），做一次自然排序，然后把
  封面页移到最前、致谢页移到最后。
- **PDF 由 VIPS 处理，而非 GhostScript**——整个代码中没有任何 `gs` 调用（Ghostscript 仅作为
  libvips 的打包依赖出现在 Homebrew formula 中）。
  `get_filelist()` 通过 `lib/LANraragi/Utils/Vips.pm` 的
  `vips_image_get_n_pages` 统计页数，`extract_single_file()` 则用
  `pdfload_page_dpi($archive, $page - 1, 200)` 渲染页面，再用 `write_to_buffer()` 将其
  重新编码为 JPEG。
- **CBW（ComicBookWeb）**文件是指向远程页面图片的 XML。`parse_cbw_urls()`
  解析该 XML（变量替换加经内部函数 `expand_cbw_range()` 完成的 `[format:a-b]` 区间
  展开）；`get_filelist()` 经内部函数 `cbw_page_name()` 合成补零的页面名，
  `extract_single_file()` 通过
  `fetch_cbw_image()` 代理远程字节。页面被提供后，`cbw_prefetch()` 会把接下来的几页
  预热进 `PageCache`。

缩略图流水线：`extract_thumbnail()` 解压所请求的页面（对 CBW 档案——无论是否封面——都会把
页面字节存入 PageCache），为封面图片在 Redis 中计算 SHA-1 `thumbhash`，然后调用
`generate_thumbnail()`，后者生成一张适配到 500x1000 以内（即至多 500px 宽）的图片，JPEG
质量 50（启用 `use_hq` 时为
80，启用 `get_jxlthumbpages` 时为 JPEG XL）。非封面缩略图落在按两个字符命名的子文件夹加
档案 ID 之下。内部函数 `extract_single_file_to_file()`（未导出）支撑着
`extract_file_from_archive()`，后者是面向插件的变体，解包到 `/temp/plugin`。

### 一对缩放器

`lib/LANraragi/Utils/Resizer.pm` 只暴露一个 `get_resizer()` 工厂，用 `state` 做了
记忆化。当 `Vips::is_vips_loaded()` 为真时返回一个 `LANraragi::Utils::VipsResizer`，
否则返回 `LANraragi::Utils::ImageMagickResizer`。两个实现都恰好实现两个方法：

- `resize_page($content, $quality, $format)` —— 缩放到 1064px 宽以供阅读。
- `resize_thumbnail($content, $quality, $use_hq, $format)` —— 适配到 500x1000 以内。

`lib/LANraragi/Utils/Vips.pm` 不使用 Perl 绑定模块；它用 `FFI::Platypus` 直接挂接 C
库（通过 `FFI::CheckLib::find_lib(lib => ['vips', 'vips-42'])` 发现）。`init()` 调用
`vips_cache_set_max(0)` 禁用操作缓存；若库缺失，所有挂接的函数都会被替换成直接 die
的桩函数。除 `vips_image_new_from_file` 及其同伴外，它还提供 `fit_resize`、
`stretch_resize`、`cover_resize`、`resize_to_width`、`crop`、`grayscale`、
`jpegsave`/`pngsave`、`write_to_buffer` 和 `unref_image`（即 `g_object_unref` 的包装，
必须调用它来释放 VipsImage 句柄）。

`ImageMagickResizer` 在 `try` 内部惰性地 `require` `Image::Magick`，设置
`jpeg:size` 解码器提示以避免解码全分辨率帧，并为缩略图选择 `Sample`（快）或
`Scale`（高质量）。若 PerlMagick 不可用，`require` 会 die，`catch` 块只在 debug 级别记一条
日志，随后方法返回的是该日志调用的返回值而非 `undef`——因此 `generate_thumbnail()` 里基于
definedness 的检查（本应记录 Couldn't create thumbnail! 日志）可能漏判这一失败。这是一个
潜在的代码怪癖，此处仅作注记而不修改代码。

## Minion 任务

`lib/LANraragi/Utils/Minion.pm` 在 `add_tasks()` 中注册了十二个任务：

| 任务 | 用途 |
|------|---------|
| `thumbnail_task` | 为档案某一页生成缩略图（第 0 页 = 封面） |
| `tank_thumbnail_task` | 为 tankoubon 生成缩略图，取自其第一个档案 |
| `page_thumbnails` | 为一个档案生成所有页面缩略图；Unix 上用 `MCE::Loop` 并行 |
| `regen_all_thumbnails` | 全库缩略图重新生成，包括 tankoubon |
| `find_duplicates` | 按 `thumbhash` 值之间的汉明距离将档案分组到 `LRR_DUPLICATE_GROUPS` |
| `build_stat_hashes` | 委托给 `LANraragi::Model::Stats::build_stat_hashes` |
| `handle_upload` | 经 `LANraragi::Model::Upload::handle_incoming_file` 接收上传的文件 |
| `download_url` | 下载某个 URL（若有匹配的下载器插件则经其下载）并接收入库 |
| `run_plugin` | 按命名空间经 `use_plugin()` 执行插件 |
| `install_plugin` | 在 `plugin-write:` 锁（TTL 300 秒）下安装托管插件 |
| `backup_json` | 经 `LANraragi::Model::Backup::build_backup_JSON` 将备份 JSON 写入临时文件夹 |
| `restore_backup` | 经 `restore_from_JSON` 从备份 JSON 恢复 |

注意 Windows 上的不对称性：`MCE::Loop` 并行仅限 Unix（libarchive 线程），因此缩略图
与查重任务在 Windows 上退回顺序执行。

### 重复检测端到端

`find_duplicates` 值得细看，因为它的结果支撑着一整个页面。任务扫描所有 40 字符档案 ID 的
`thumbhash`（合集没有该字段），随后用洪水填充聚类哈希。当两个哈希的 SHA-1 十六进制字符串
至多有 `$threshold` 个*字符*不同时即视为"接近"——距离逐字符计数（并非逐位），一旦超过
阈值就提前退出。查重页面把阈值写死：`public/js/duplicates.js` 以
`/api/minion/find_duplicates/queue?args=[5]&priority=0` 入队该任务。包含两个及以上成员的
分组会写入 `LRR_DUPLICATE_GROUPS`（配置数据库），字段为 `dupgp_<key>`，其中 key 是组内
成员按排序后各自 ID 前 10 个字符的拼接——因此同一组档案总是映射到同一字段。一个结构性
怪癖：`visited` 集合在 MCE worker 之间共享，因此与已被其他 worker 分组吸收的档案接近的
哈希会被跳过，而仅剩单个成员的残余组会被 `>= 2` 过滤器丢弃——边缘分组因此可能被漏报。

`lib/LANraragi/Controller/Duplicates.pm` 用该哈希渲染 `/duplicates` 页面：修剪过期分组
（只剩一对时删除整个字段，否则重写 JSON 去掉已消失的 ID），并在 `delete` 请求参数存在时
清空全部分组。`public/js/duplicates.js` 把各组显示在一张带分隔行的 DataTable 中，提供
自动勾选规则（按标签更少/体积更小/页数更少/更早/更晚挑出"较差"的重复项），并通过
`DELETE /api/archives/{id}` 删除档案。这种视觉匹配与上传时的重复拒绝（`replacedupe`）
彼此独立，后者比较的是精确 ID 与文件名。

### 谁入队哪个任务

代码库中的全部入队点（服务端 `->enqueue(` 调用加客户端队列 API），以及各任务的参数与
显式 Minion 选项：

| 任务 | 入队方 | 参数 | 选项 |
|------|-----------|------|---------|
| `thumbnail_task` | `lib/LANraragi/Model/Archive.pm` 的 `serve_thumbnail()`（缩略图缺失且 `no_fallback`） | `($thumbdir, $id, $page)` | priority 0，3 次尝试 |
| `tank_thumbnail_task` | `lib/LANraragi/Model/Tankoubon.pm` 的 `serve_tankoubon_thumbnail()`；`lib/LANraragi/Controller/Api/Tankoubon.pm` 的 `update_tankoubon()`/`remove_from_tankoubon()` | `($thumbdir, $tank_id)` | priority 0，3 次尝试 |
| `page_thumbnails` | `lib/LANraragi/Model/Archive.pm` 的 `generate_page_thumbnails()`（经 `thumbjob` 去重） | `($id, $force)` | priority 0，3 次尝试 |
| `regen_all_thumbnails` | `lib/LANraragi/Controller/Api/Other.pm` 的 `regen_thumbnails()`（`POST /api/regen_thumbs`） | `($thumbdir, $force)` | priority 0 |
| `find_duplicates` | 仅客户端——`public/js/duplicates.js` | `($threshold)`（写死为 5） | priority 0 |
| `build_stat_hashes` | `lib/LANraragi.pm` 的 `startup()`（每次启动）；`lib/LANraragi/Utils/Database.pm` 的 `invalidate_cache(1)` | — | 默认 / priority 3 |
| `handle_upload` | `lib/LANraragi/Controller/Upload.pm` 的 `process_upload()` | `($tempfile, $catid)` | priority 2 |
| `download_url` | `lib/LANraragi/Controller/Api/Other.pm` 的 `download_url()`（`POST /api/download_url`） | `($url, $catid)` | priority 1，5 次尝试 |
| `run_plugin` | `lib/LANraragi/Controller/Api/Other.pm` 的 `use_plugin_async()`（`POST /api/plugins/queue`） | `($namespace, $id, $scriptarg)` | 客户端提供的 priority |
| `install_plugin` | `lib/LANraragi/Controller/Api/Plugins.pm` 的 `install_plugin()` | `($namespace, $registry_id, $version, $force)` | priority 0，1 次尝试（不重试） |
| `backup_json` | `lib/LANraragi/Controller/Api/Database.pm` 的 `queue_backup()` | — | priority 0 |
| `restore_backup` | `lib/LANraragi/Controller/Api/Database.pm` 的 `queue_restore()` | `($json_data)` | priority 0 |

进度上报是例外而非惯例：只有 `page_thumbnails`（逐页 note 外加 `total_pages`/`id`，由
阅读器的缩略图进度 UI 消费）和两个由 Backup 驱动的任务
（`build_backup_JSON`/`restore_from_JSON` 会 note `categories_processed`/`tankoubons_processed`/
`archives_processed`、`total_*` 与 `status` 消息）发布 `$job->note` 数据。

队列 API（`POST /api/minion/{jobname}/queue`）通过 `tools/openapi.yaml` 中 `jobname`
参数上的 `enum` 恰好白名单了九个任务名——即上表中除 `install_plugin`、`backup_json` 和
`restore_backup` 之外的全部，后三者只能经各自的专用端点触达。`GET /api/minion/{jobid}`
渲染经过筛选的 `{task, state, notes, error}` 对象，而 `GET /api/minion/{jobid}/detail`
渲染完整的 `$job->info` 哈希——正是这种广度使它需要 `api_key` 方案。控制器自身不做任何
校验，因此该枚举只在 OpenAPI 校验开启时生效。

## 并发与加锁

`lib/LANraragi/Utils/Generic.pm` 基于 Redis `SET NX EX` 提供两个加锁入口：

- `exec_with_lock($mojo, $lock_name, $operation, $resource_id, $func)` —— 面向控制器的
  五参数变体。发生争用时渲染一个 423 JSON 响应，指明被锁的资源，并返回 false。
- `exec_with_lock_pure(\@lock_names, $func, $redis?, $ttl?)` —— 原语。它获取多把锁
  （默认 TTL 10 秒），每把锁的值是一个随机 SHA-256 令牌，由一段 Lua 脚本在删除前
  比对令牌后释放——这是标准的单实例分布式锁模式，防止 worker 删除不属于自己的锁。
  多锁获取失败时按相反顺序回滚。

同一模块还负责进程生命周期：`start_minion()` 用 `MCE::Util::get_ncpu()` 确定 worker
的并行任务数，并在一个 `Proc::Simple` 子进程中启动它（`minion.pid` 中存的是冻结的
`Proc::Simple` 对象，原始 PID 在 `minion.pid-s6`），
`start_shinobu()` 对文件监视器做同样的事。`split_workload_by_cpu()`
会把数组切成每 CPU 一份，但上述 Minion 任务是把完整 key 列表交给 `mce_loop`、由 MCE
内部切块——目前没有任何调用方使用它。

## Shinobu 文件监视器

`lib/Shinobu.pm` 作为独立进程运行——直接执行该文件就会调用
`initialize_from_new_process()`——`start_shinobu()` 在每次应用启动时拉起它，而
`lib/LANraragi.pm` 的 `startup()` 会先经 `shinobu.pid` 中 Storable 冻结的 `Proc::Simple`
句柄杀掉残留实例（仅 Unix）。监视本身由
`File::ChangeNotify->instantiate_watcher()` 对内容目录完成，过滤正则与
`lib/LANraragi/Utils/Generic.pm` 中 `is_archive()` 的档案扩展名正则相同
（`zip|rar|7z|tar|tar.gz|lzma|xz|cbz|cbr|cb7|cbt|cbw|pdf|epub|tar.zst|zst`），跟随符号链接
并排除 `thumb`/隐藏目录；一个手工循环每秒轮询一次 `new_events()`。

在开始监视之前，`update_filemap()` 会做一次完整递归扫描并与 `LRR_FILEMAP` 求差集：已消失
的路径从文件映射中剪除，新档案走与实时事件相同的 `add_to_filemap()` 路径（Unix 上经
`mce_loop` 并行）。实时事件把 `create`/`modify` 映射到 `new_file_callback()`，把 `delete`
映射到 `deleted_file_callback()`：

- **新增或修改的文件。** `add_to_filemap()` 复查 `is_archive()`，等待文件可打开且至少
  512000 字节（每秒一次、最多 5 次后放弃——更小的文件仍可能在写入中途被读取），计算 ID
  并取得 `archive-write:$id` 锁（TTL 60 秒）后才运行 `update_filemap_entry()`。ID 发生
  变化时经 `change_archive_id()` 做非破坏性迁移——Redis 哈希被 `rename`，标签得以保留，
  这与上传时的重复替换不同。全新 ID 会在锁*外*触发 `add_new_file()`：
  `add_archive_to_redis()`、`add_timestamp_tag()`、`add_pagecount()`、
  `extract_thumbnail()`，然后是自动插件轮 `exec_enabled_plugins_on_file()`，最后
  `invalidate_cache()`。`lib/LANraragi/Model/Upload.pm` 的两阶段 `.upload` 暂存正是为了让
  Shinobu 只看到完整文件（`.upload` 既不匹配监视过滤器也不匹配 `is_archive()`）。
- **被删除的文件。** 该路径被从 `LRR_FILEMAP` 中 `hdel`，搜索缓存失效——档案的 Redis
  哈希*不会*被删除，因此它作为孤儿残留，直到 `clean_database()` 清扫它。

`lib/LANraragi/Controller/Api/Shinobu.pm` 中的 API 控制对应四个 `/shinobu` 操作：
`shinobu_status()`（存活标志 + 取自 `shinobu.pid` 的 PID）、`stop_shinobu()`（仅杀死）、
`restart_shinobu()`（杀死后重启），以及 `reset_filemap()`——即 `/shinobu/rescan` 端点，
它 DELETE 掉 `LRR_FILEMAP` 并重启进程，让新进程完成完整重扫。所有触及数据库的回调都用
`eval` 包裹并记录到 `shinobu` 日志；启用指标时该进程约每 30 秒采集一次自身计数器。

## 标签规则

`lib/LANraragi/Utils/Tags.pm` 用 `tags_rules_to_array()` 解析用户书写的规则，并用
`rewrite_tags()` 应用它们。共有六种规则类型：

| 语法 | 类型 | 效果 |
|--------|------|--------|
| `-tag` | `remove` | 删除完全匹配的标签 |
| `-namespace:*` | `remove_ns` | 删除该命名空间下的所有标签 |
| `~namespace` | `strip_ns` | 去掉命名空间前缀，保留值 |
| `match -> replacement` | `replace` | 重写完全匹配的标签 |
| `ns:* -> other:*` | `replace_ns` | 重命名命名空间 |
| `match => replacement` | `hash_replace` | 经查找哈希做 O(1) 精确匹配重写 |

所有匹配在解析时即转为小写。`hash_replace` 规则由
`build_tag_replace_hash()` 拆分到一个不区分大小写的哈希中，`apply_rules()` 在顺序
规则跑完*之后*再查询它，因此它们对标签的最终取值拥有最后决定权。

## 路由、登录与 Web 相关

`lib/LANraragi/Utils/Routing.pm` 的 `apply_routes()` 是唯一的路由表：它把
`Mojolicious::Plugin::OpenAPI` 对接到 `tools/openapi.yaml`，`api_key` 安全方案委托给
`is_logged_in_api()`，可选地桥接 CORS（`login#setup_cors`）和"禁止取乐"的强制鉴权
模式，以不可变缓存头提供带版本的 `/js/:version/*` 静态资源（由 `is_path_within()`
防护路径穿越），并声明 public/、login/、logged-in 三套路由层级。

`lib/LANraragi/Utils/Login.pm` 的 `is_logged_in_api()` 接受以下任意一种：`Bearer` 加
base64 API key 的 `Authorization` 头、`key` 请求参数（OPDS 使用）、已认证的会话，或者
干脆已禁用密码强制。`lib/LANraragi/Utils/OpenAPI.pm` 的
`apply_openapi_mojo_overrides()` 重新接管 `openapi.valid_input`：设置 `disableopenapi` 时
完全绕过请求*与*响应校验；否则请求照常校验，但失败会在服务端记录日志并渲染为 400 响应体。

Web 会话是与 API 鉴权相互独立的机制。`login#check` 经由 `lib/LANraragi/Utils/Generic.pm` 中
`get_authenticator()` 构建的 `Crypt::Passphrase` 认证器，把提交的密码与 `LRR_CONFIG →
password` 中存储的 bcrypt 哈希（默认为 `kamimamita` 的哈希）比对，存储的哈希需要升级时会
透明地重新散列，成功后设置 `session(is_logged => 1)` 并给予 24 小时有效期；`lib/LANraragi/Controller/Login.pm`
中的 `logged_in()` 守卫 Web 路由，`/logout` 使会话过期。Mojolicious 会话密钥是一个持久化到
`temp/oshino` 的随机十六进制串，启动时与主机名拼接（`lib/LANraragi.pm`）。这里没有强制的
密码更换：只要默认密码仍能通过验证，首页只会弹一条警告 toast（`Index.pm` 会置
`usingdefpass`）；密码通过普通的配置保存修改——`lib/LANraragi/Controller/Config.pm` 的
`save_config()` 用同一认证器散列 `newpassword`，但仅在提交了 `enablepass` 时才写入。代码中
不存在任何 CSRF 令牌；签名的会话 cookie 是唯一的请求完整性机制。

本地化位于 `I18N.pm`/`I18NInitializer.pm`：基于 gettext 词表的 `Locale::Maketext`，
以 `lh` helper 暴露给模板，优先遵循强制语言设置，再回退到 `Accept-Language` 协商。
可观测性一分为二：`Logging.pm`/`RotatingLog.pm`（日志器、插件日志器，以及基于大小的
轮转——默认 1 MiB 经 `LRR_LOGROTATE_SIZE`，每追加 1000 行检查一次，旧文件 gzip 为
`<log>.N.gz` 并保留 `LRR_LOGROTATE_FILES`（默认 7）份——配合 `flock` 加锁）与
`Metrics.pm`（Prometheus 计数器：`extract_endpoint()` 把请求路径规范化为
路由模板以限制标签基数，`read_proc_stat`/`read_proc_statm`/`read_proc_io_bytes` 等
为进程指标供数）。

## 其余部分

- **数据层。** `Database.pm` 覆盖档案 CRUD（`add_archive_to_redis`、`set_tags`、
  `set_title`、`set_summary`、`get_archive_json_multi`、`compute_id`、`invalidate_cache`、
  `get_computed_tagrules`、`update_indexes`、`clean_database`）。`Redis.pm` 只是编码/解码
  函数对：`redis_encode()` 在 UTF-8 编码前先做 NFC 规范化，`redis_decode()` 则以
  `FB_CROAK` 做双重解码。`PageCache.pm` 封装 CHI——Unix 上用
  FastMmap 驱动（数据文件位于应用临时目录），Windows 上用 Memory——容量上限为
  `max(0, min(tempmaxsize, 4096))` MB。缓存中只有两种键形态：`page/$id/$path` 下的原始
  页面字节（由 `get_page_data()` 及 CBW 预取/缩略图暂存写入），以及
  `resize_page/$id/$path/$threshold/$quality` 下的调整尺寸变体。条目没有 TTL，档案编辑或
  删除时也没有任何失效逻辑——唯一的清除路径是 `DELETE /api/tempfolder`
  （`clean_tempfolder()` 调用 `PageCache::clear()`），因此被删档案的页面会一直留到容量
  逐出为止。
- **文件系统。** `Path.pm`（`create_path`、`open_path_or_die`、`get_archive_path`、
  `package_to_path`/`path_to_package`、`compat_path`）与 `TempFolder.pm`（`get_temp`）。
  `String.pm` 持有 `clean_title`、`trim`、`trim_url` 和 `most_similar`（由
  `String::Similarity` 支撑）。
- **插件支持。** `Plugins.pm` 与 `Registry.pm` 在
  [04_plugins.md](04_plugins.md) 中详述；前者是基于 Redis 的查找层，后者是托管插件
  安装所用的注册表获取/校验层。
