# 插件系统

> 基准 commit `2094cc1d`（2026-09-04）。事实已对照代码核实——生成时已逐条核对引文。

## 概览

LANraragi 插件是位于 `lib/LANraragi/Plugin/` 下的普通 Perl 包，通过一个
`plugin_info()` 函数声明元数据。系统支持四种插件类型，各有一个必需方法，另外为通过
注册表分发的第三方（"托管"）插件提供安装/卸载生命周期。执行机制位于
`lib/LANraragi/Model/Plugins.pm`；基于 Redis 的查找/注册粘合代码位于
`lib/LANraragi/Utils/Plugins.pm`。

## 插件类型

| 类型 | 目录 | 数量 | 必需方法 | 角色 |
|------|-----------|-------|-----------------|------|
| `login` | `Plugin/Login/` | 4 | `do_login` | 返回一个内置了凭据/cookie 的 `Mojo::UserAgent` |
| `metadata` | `Plugin/Metadata/` | 21 | `get_tags` | 为一个档案抓取或计算标签（可选地还有标题/摘要） |
| `download` | `Plugin/Download/` | 3 | `provide_url` | 把页面 URL 转成直接下载 URL 或本地文件路径 |
| `script` | `Plugin/Scripts/` | 4 | `run_script` | 从 Plugin Configuration 运行的一次性任意操作 |

方法契约在列取时强制执行：`lib/LANraragi/Utils/Plugins.pm` 的 `get_plugins()`
会跳过其类型所需方法缺失的包（`can('run_script')`、
`can('get_tags')`、`can('provide_url')`、`can('do_login')`）。

## `plugin_info` 契约

每个插件从 `plugin_info()` 返回一个哈希。标准键（由内置插件声明）：`name`、`type`、
`namespace`、`author`、`version` 和 `description`。`icon`（base64 data URI）接近标准：
32 个内置插件中有 21 个声明了它（所有 Login 与 Download 插件均省略）。可选键：

| 键 | 使用者 | 含义 |
|-----|---------|---------|
| `parameters` | 设置界面 | `{ type, desc, default_value }` 参数描述符构成的数组（按位置）或哈希（按名称） |
| `oneshot_arg` | 元数据（及部分脚本）插件 | 每次运行参数的提示输入，例如图库 URL 覆盖 |
| `login_from` | 所有类型 | 应注入其 UserAgent 的登录插件的命名空间 |
| `cooldown` | 批量打标签界面 | 出于对 API 的礼貌，两次运行之间建议的延迟秒数 |
| `url_regex` | 下载插件 | 决定此下载器认领哪些 URL 的正则表达式 |

其中两个需要精确说明：

- **`cooldown` 仅是建议值。** 它由 `EHentai`（4 秒）、`MEMS`（4 秒）和 `Pixiv`
  （1 秒）在其 `plugin_info` 中声明，唯一的消费者在前端：`templates/batch.html.tt2`
  把它渲染进一个隐藏 span，`public/js/batch.js` 再把该值读作默认超时。任何后端
  （`lib/`）代码都不读取或强制执行它。
- **`login_from` 是命名空间，不是模块名。** `lib/LANraragi/Model/Plugins.pm` 的
  `exec_login_plugin()` 通过常规的注册路径查找它。

## 发现与注册

两个机制协同工作：

1. **编译期发现** —— `lib/LANraragi/Utils/Plugins.pm` 使用
   `Module::Pluggable (search_path => ['LANraragi::Plugin'])`，它会找出四个插件
   目录下的所有包（包括存在时的 `Managed/` 与 `Sideloaded/` 子目录）。
2. **运行期注册表** —— `lib/LANraragi/Model/Plugins.pm` 的 `scan_plugins()`（在启动
   时由 `lib/LANraragi.pm` 调用）将发现的类与 Redis 对账：它通过 `register_plugin()`
   注册每个发现的命名空间，对重复命名空间或大小写冲突发出警告，并注销文件已从磁盘
   消失的孤儿 `LRR_PLUGIN_*` 键（除非文件仍存在于磁盘上）。

只有已注册的插件才可调用：`lib/LANraragi/Utils/Plugins.pm` 的 `get_plugin()`
拒绝加载没有记录 `installed_path` 的命名空间，因此已卸载的插件保留其用户设置但不再
可被调用。

## 执行流程

### 元数据插件

`lib/LANraragi/Utils/Plugins.pm` 的 `use_plugin()` 分派到
`lib/LANraragi/Model/Plugins.pm` 的 `exec_metadata_plugin()`，后者构建 `$lrr_info`
哈希并调用 `$plugin->get_tags(\%lrr_info, %settings)`。元数据插件的 `$lrr_info`
有七个字段：`archive_id`、`archive_title`、`existing_tags`、`thumbnail_hash`（缺失时
当场经 `extract_thumbnail()` 重新生成）、`file_path`、`user_agent`（由
`exec_login_plugin()` 从 `login_from` 构建）和 `oneshot_param`。插件返回
`tags`/`title`/`summary`（或 `error`）；返回的标签在启用时经过标签规则过滤，并与
`existing_tags` 去重——但单次运行路径只把它们*返回*给调用方而不写入。在
`archive-write:$id` 锁下写入的步骤位于自动插件变体 `exec_enabled_plugins_on_file()`
中——它在上传后以及 Shinobu 发现新文件时运行，还会强制 `regexplugin` 命名空间
（`Plugin/Metadata/RegexParse.pm`）最先运行。批量打标签 websocket 走第三条路：
`lib/LANraragi/Controller/Batch.pm` 的 `batch_plugin()` 经 `set_tags`/`set_title`/`set_summary`
写入，*不加* `archive-write:$id` 锁。

### 脚本插件

`exec_script_plugin()` 传入只含 `user_agent` 和 `oneshot_param` 的 `$lrr_info`，然后
调用 `run_script(\%lrr_info, %settings)`。返回哈希为自由格式，经 API 原样呈现。
本 fork 仓库新增的 `Plugin/Scripts/EhTagAutoUpdater.pm`（命名空间
`ehtag_auto_updater`）即属此类型：它查询 EhTagTranslation/Database 的 GitHub releases
API，下载 `db.text.json`，应用一处硬编码的文本替换（`"重新分类"` → `"类别"`——该插件
不声明任何 `parameters`），并更新系统数据库。

### 下载插件

由 URL 摄入触发（`lib/LANraragi/Utils/Minion.pm` 中的 `download_url` Minion 任务）。
`Utils/Plugins.pm` 的 `get_downloader_for_url()` 将 URL 与每个*已注册*下载器的
`url_regex` 匹配（此处不检查 `enabled` 标志）；随后 `exec_download_plugin()` 调用
`provide_url(\%lrr_info, ...)`，`$lrr_info` 含有 `user_agent`、`url` 和 `tempdir`。
插件返回 `download_url`（LRR 用该插件的 UserAgent 下载）或 `file_path`（插件已自行
取回文件）。无论哪种，结果都会交给 `LANraragi::Model::Upload::handle_incoming_file`，
并带上原始 URL 的 `source:` 标签。

### 登录插件

`exec_login_plugin($namespace)` 加载插件及其已保存的参数，然后调用 `do_login`。
返回值必须是 `Mojo::UserAgent`——其他任何值都会被记录并丢弃，改用全新的匿名
UserAgent。登录插件没有 `$lrr_info`；它们只接收自己配置的参数。

## 配置存储

每个插件的设置存放在**配置数据库**（来自
`LANraragi::Model::Config->get_redis_config` 的连接，与档案数据库不同）上一个名为
`LRR_PLUGIN_{uc namespace}` 的 Redis 哈希中。`Utils/Plugins.pm` 的
`get_plugin_parameters()` 先填入 `default_value`，再覆盖以已保存的值。存在两种参数
风格：

- **按位置（旧式）：** `parameters` 是数组；保存的值是 `customargs` 字段下的一个
  JSON 数组，以 `@{ $args{customargs} }` 传给插件。
- **按名称（现行）：** `parameters` 是哈希；每个键作为独立字段存入同一个 Redis
  哈希。声明了 `to_named_params` 的插件会在首次读取时由
  `convert_to_named_params_and_persist()` 迁移其旧的 `customargs`。

同一个哈希还携带注册溯源信息：`installed_path`、`installed_version`、
`installed_registry`、`installed_sha256`、`type` 以及 `enabled` 标志。

## 托管插件、注册表与旁加载

`Utils/Plugins.pm` 的 `infer_plugin_origin()` 把每个插件归类为 `builtin`（随
`Login/`、`Metadata/`、`Download/`、`Scripts/` 发行）、`managed`（从注册表安装到
`Plugin/Managed/{Type}/` 之下，依照 `Utils/Registry.pm` 中的 `MANAGED_TYPE_DIRS`
映射）或 `sideloaded`（手工上传到 `Plugin/Sideloaded/` 之下——`Controller/Plugins.pm`
在上传时创建该目录，并校验包声明了 `LANraragi::Plugin::…` 类型）。

注册表是 `registry.json` 索引的 git/CDN/本地来源，由
`lib/LANraragi/Model/Registry.pm` 管理（`create_registry`、`get_registry`、
`refresh_registry`、`get_default_registry`）。`Model/Setup.pm` 会种下一个默认
注册表：**Ougi**（`https://github.com/Difegue/Ougi.git`）。`Utils/Registry.pm` 提供
获取与校验原语（`fetch_registry_resource`、`validate_registry_index`、
`find_package_conflict`、`find_namespace_conflict`、`resolve_max_version`）。

注册表条目存放在 `REG_<10位时间戳>` 哈希中（字段为 `%PROVIDER_FIELDS` 中的提供方字段，
外加 `created`/`updated`），`refresh_registry()` 会把抓取到的索引原文缓存进一个
`REG_INDEX_<后缀>` 字符串键——安装时读取该缓存，缺失即失败并返回 `409 No registry index
cached. Run refresh first.`。`validate_registry_index()` 强制执行的索引 schema：根对象含
`version`（必须为 1）、`generated_at`（UTC RFC3339）与 `plugins`；每个插件以其小写的
`[a-z0-9_-]` 命名空间为键，携带 `type`（四种托管类型之一）和一个 `versions` 映射——映射键
是不带前导 `v` 的 SemVer 2.0.0 字符串，每个条目必须有 `name`、`author`、`description`、
`artifact`（安全的相对路径）、64 个字符的小写 `sha256` 和 `published_at`。产物 URL 按提供方解析
（`resolve_git_raw_url()`/`resolve_cdn_artifact_url()`）：GitHub →
`https://raw.githubusercontent.com/<owner>/<repo>/<ref>/<path>`，Gitea →
`https://<host>/api/v1/repos/<owner>/<repo>/raw/<path>?ref=<ref>`，CDN → 转义后的产物路径
拼接到基础 URL，本地 → 注册表根目录之下的路径（带逃逸检查）。`install_plugin()` 默认挑选
最大的 SemVer 版本，除非调用方固定了版本。默认注册表并不是专用键，而是 `LRR_CONFIG` 哈希
中的 `default_registry` 字段。

安装是事务性的：`Model/Plugins.pm` 的 `install_plugin()`（由 `install_plugin`
Minion 任务驱动，经 `exec_with_lock_pure` 的 `plugin-write:{NAMESPACE}` 锁串行化）
获取产物，对照索引校验其 SHA-256，将声明的包名与预期的 `Managed/{Type}/` 路径核对，
写入文件并带有分阶段回滚（先备份上一个产物，失败时由一段 Lua 脚本恢复溯源字段），
最后运行 `check_plugin_loads()`——一个 20 秒超时、执行 `script/check_plugin_loads.pl`
的子进程，用以证明模块能通过编译。只有托管插件可升级；跨注册表覆盖需要 `force`
标志。`uninstall_plugin()` 删除文件与溯源信息（用户设置保留），并拒绝触碰内置插件。

## 内置插件清单

截至基准 commit，随发行内置的 32 个插件为：

- **登录（4 个）：** `EHentai.pm`、`Fakku.pm`、`Pixiv.pm`、`nHentai.pm`
- **元数据（21 个）：** `Chaika.pm`、`ChaikaFile.pm`、`ComicInfo.pm`、`CopyArchiveTags.pm`、
  `CopyTags.pm`、`DateAdded.pm`、`EHDLInfo.pm`、`EHentai.pm`、`Eze.pm`、`Fakku.pm`、
  `GalleryDL.pm`、`HDoujin.pm`、`HatH.pm`、`Hentag.pm`、`Hitomi.pm`、`Koromo.pm`、`Ksk.pm`、
  `MEMS.pm`、`Pixiv.pm`、`RegexParse.pm`、`nHentai.pm`
- **下载（3 个）：** `Chaika.pm`、`EHentai.pm`、`Pixiv.pm`
- **脚本（4 个）：** `EhTagAutoUpdater.pm`、`FolderToCat.pm`、`SourceFinder.pm`、
  `nHentaiSourceConverter.pm` —— 其中 `EhTagAutoUpdater.pm` 为本 fork 仓库专有，
  而非上游 LANraragi 自带。

`Utils/Plugins.pm` 与 `Utils/Registry.pm` 的一行式概览见
[03_utils.md](03_utils.md)；它们的内部机制在本页描述。
