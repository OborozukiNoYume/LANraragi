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
| `OpenAPI.pm` | `apply_openapi_mojo_overrides()` 放宽 OpenAPI 请求校验 |
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
- **PDF 由 VIPS 处理，而非 GhostScript**——整个代码库中没有任何 `gs` 调用。
  `get_filelist()` 通过 `lib/LANraragi/Utils/Vips.pm` 的
  `vips_image_get_n_pages` 统计页数，`extract_single_file()` 则用
  `pdfload_page_dpi($archive, $page - 1, 200)` 渲染页面，再用 `write_to_buffer()` 将其
  重新编码为 JPEG。
- **CBW（ComicBookWeb）**文件是指向远程页面图片的 XML。`parse_cbw_urls()`
  解析该 XML（变量替换加经内部函数 `expand_cbw_range()` 完成的 `[format:a-b]` 区间
  展开），合成补零的页面名，`extract_single_file()` 通过
  `fetch_cbw_image()` 代理远程字节。页面被提供后，`cbw_prefetch()` 会把接下来的几页
  预热进 `PageCache`。

缩略图流水线：`extract_thumbnail()` 解压所请求的页面（对 CBW 封面会把页面字节存入
PageCache），为封面图片在 Redis 中计算 SHA-1 `thumbhash`，然后调用
`generate_thumbnail()`，后者生成一张 500px 高、JPEG 质量 50 的图片（启用 `use_hq` 时为
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
`Scale`（高质量）。若 PerlMagick 不可用，它就直接返回 undef，由调用方记录无法创建
缩略图的日志。

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

## 并发与加锁

`lib/LANraragi/Utils/Generic.pm` 基于 Redis `SET NX EX` 提供两个加锁入口：

- `exec_with_lock($mojo, $lock_name, $operation, $resource_id, $func)` —— 面向控制器的
  五参数变体。发生争用时渲染一个 423 JSON 响应，指明被锁的资源，并返回 false。
- `exec_with_lock_pure(\@lock_names, $func, $redis?, $ttl?)` —— 原语。它获取多把锁
  （默认 TTL 10 秒），每把锁的值是一个随机 SHA-256 令牌，由一段 Lua 脚本在删除前
  比对令牌后释放——这是标准的单实例分布式锁模式，防止 worker 删除不属于自己的锁。
  多锁获取失败时按相反顺序回滚。

同一模块还负责进程生命周期：`start_minion()` 用 `MCE::Util::get_ncpu()` 确定 worker
的并行任务数，并在一个 `Proc::Simple` 子进程中启动它（PID 记录在 `minion.pid`），
`start_shinobu()` 对文件监视器做同样的事。`split_workload_by_cpu()`
为上述 Minion 任务使用的 MCE 循环切分工作。

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
`apply_openapi_mojo_overrides()` 在原生行为过于严格之处放宽 OpenAPI 校验。

本地化位于 `I18N.pm`/`I18NInitializer.pm`：基于 gettext 词表的 `Locale::Maketext`，
以 `lh` helper 暴露给模板，优先遵循强制语言设置，再回退到 `Accept-Language` 协商。
可观测性一分为二：`Logging.pm`/`RotatingLog.pm`（日志器、插件日志器、带 `flock` 的
轮转）与 `Metrics.pm`（Prometheus 计数器：`extract_endpoint()` 把请求路径规范化为
路由模板以限制标签基数，`read_proc_stat`/`read_proc_statm`/`read_proc_io_bytes` 等
为进程指标供数）。

## 其余部分

- **数据层。** `Database.pm` 覆盖档案 CRUD（`add_archive_to_redis`、`set_tags`、
  `set_title`、`set_summary`、`get_archive_json_multi`、`compute_id`、`invalidate_cache`、
  `get_computed_tagrules`、`update_indexes`、`clean_database`）。`Redis.pm` 只是带
  Unicode NFC 规范化的编码/解码函数对。`PageCache.pm` 封装 CHI——Unix 上用
  FastMmap 驱动，Windows 上用 Memory——容量上限为 `min(tempmaxsize, 4096)` MB。
- **文件系统。** `Path.pm`（`create_path`、`open_path_or_die`、`get_archive_path`、
  `package_to_path`/`path_to_package`、`compat_path`）与 `TempFolder.pm`（`get_temp`）。
  `String.pm` 持有 `clean_title`、`trim`、`trim_url` 和 `most_similar`（由
  `String::Similarity` 支撑）。
- **插件支持。** `Plugins.pm` 与 `Registry.pm` 在
  [04_plugins.md](04_plugins.md) 中详述；前者是基于 Redis 的查找层，后者是托管插件
  安装所用的注册表获取/校验层。
