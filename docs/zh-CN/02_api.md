# HTTP API

> 基准 commit `2094cc1d`（2026-09-04）。端点总表由 `tools/openapi.yaml`（OpenAPI 3.1）机械提取。事实已对照代码核实。

## 概述与路由

几乎所有 `/api/*` 流量都由 **Mojolicious::Plugin::OpenAPI** 处理（少数例外直接注册在 `apply_routes()` 中，列于本文档末尾），该插件在 `lib/LANraragi/Utils/Routing.pm` 的 `apply_routes()` 中加载，以 `tools/openapi.yaml` 作为其规格。该规格的版本为 OpenAPI 3.1.0，声明了唯一的服务器条目 `https://lrr.tvc-16.science/api`；插件从这个服务器 URL 推导出 `/api` 路径前缀，因此下文参考表中列出的每个操作路径都在 `/api` 之下提供服务（例如 `/archives` 即 `GET /api/archives`）。

规格中的每个操作都带有一个 `x-mojo-to` 存根，例如 `api-search#handle_api`，它把操作映射到 `lib/LANraragi/Controller/Api/` 中的控制器方法。在控制器运行之前，插件会依照规格校验传入请求（路径/查询/正文参数）；校验失败由 `lib/LANraragi/Utils/OpenAPI.pm` 中的 `openapi.valid_input` 覆盖转为 400 响应，该覆盖还会在服务器端记录错误。`disableopenapi` 配置标志（在配置 UI 中暴露）会同时绕过请求与响应校验，但保持路由不变。

在 `apply_routes()` 中，两个横切选项被挂接到 API 路由器周围：

- **CORS**（`enablecors`，默认关闭）：路由挂载在 `lib/LANraragi/Controller/Login.pm` 的 `setup_cors()` 之下，后者以 `Access-Control-Allow-Origin: *`、`Access-Control-Allow-Methods: GET, OPTIONS, POST, DELETE, PUT` 应答浏览器预检请求，并显式允许 `Authorization` 头。
- **No-Fun 模式**（`nofunmode`，默认关闭）：整个 OpenAPI 路由器挂载在 `lib/LANraragi/Controller/Login.pm` 的 `logged_in_api()` 之下，因此*每个*请求——包括规格条目为 `security: []` 的端点——都必须通过认证，否则以 401 失败并返回 `{"error": "This API is protected and requires login or an API Key."}` 正文。同时 Web UI 路由也被锁定在会话登录之后。

## 认证

规格命名了一个安全方案 `api_key`；其回调（定义在 `lib/LANraragi/Utils/Routing.pm` 的插件设置中）委托给 `lib/LANraragi/Utils/Login.pm` 中的 `is_logged_in_api()`。满足以下任一条件请求即通过：

1. `Authorization: Bearer {base64(apikey)}` 头，其值为服务器配置页面中所配置原始 API 密钥的 base64 编码。
2. 包含原始密钥的 `?key={apikey}` 查询参数。代码注释称其为“未写入文档，主要就是为 OPDS 准备的”：无法发送自定义头的阅读器会使用它，`lib/LANraragi/Model/Opds.pm` 会把该值贯穿到目录的分页链接中，使导航保持认证状态。
3. 已存在的已登录浏览器会话。
4. 密码保护被完全禁用（`enablepass` 设为 0；默认开启）。

在参考表中，**Auth = "No"** 表示该操作在规格中声明为 `security: []`，无需凭据（除非启用了 No-Fun 模式，见上文）；Auth 列为 **"API key"** 的操作走 `api_key` 方案。

有两个进度端点值得一提。`PUT /api/archives/{id}/progress/{page}` 和 `PUT /api/tankoubons/{id}/progress/{page}` 被声明为 `security: []`，但它们的处理器——`lib/LANraragi/Controller/Api/Archive.pm` 中的 `update_progress()` 和 `lib/LANraragi/Controller/Api/Tankoubon.pm` 中的 `update_tank_progress()`——会自行调用 `is_logged_in_api()`，并在 `authprogress` 设置启用时应答 401，这样随意使用的阅读器就无法伪造其他客户端的进度。当服务器端进度跟踪被禁用（`localprogress` 而无 `authprogress`）或档案没有记录页数时，档案处理器还会额外以 400 拒绝更新（可用未写入文档的 `force` 参数绕过）。

## 响应格式与错误

大多数变更型端点通过 `lib/LANraragi/Utils/Generic.pm` 中的 `render_api_response()` 报告结果，其输出为：

```json
{ "operation": "update_metadata", "success": 1, "error": "", "successMessage": "" }
```

失败时返回 HTTP 400，带 `success: 0` 以及 `error` 中的消息；成功时返回 HTTP 200，可能附带 `successMessage`。在这一约定之上，OpenAPI 层本身可能以 400（请求校验失败，正文列出问题参数）或 401（安全检查失败）应答，而 No-Fun 模式 / 指标链路会以其自有的 401 JSON 应答，如上所示。

## 搜索端点详解

四个搜索操作位于 `lib/LANraragi/Controller/Api/Search.pm`；三个查询端点（`GET /api/search`、`GET /api/search/ids`、`GET /api/search/random`）由 `lib/LANraragi/Model/Search.pm` 中的 `do_search()` 支撑，而 `DELETE /api/search/cache` 只调用 `invalidate_cache()`。`GET /api/search` 和 `GET /api/search/ids` 接受相同的参数：

| 参数 | 默认值 | 含义 |
|---|---|---|
| `filter` | — | 搜索查询；语法见下文 |
| `category` | — | 限定搜索范围的分类 ID。静态分类会将其档案列表取交集；动态分类会把自身的搜索谓词作为额外的过滤词元加入 |
| `start` | `0` | 结果列表中的偏移量，按服务器端页面大小（`pagesize`，默认 100）分页。`-1` 返回完整的、未分页的结果集 |
| `sortby` | `title` | `title`、`lastread` 或**任意标签命名空间**（`artist`、`date_added`、……） |
| `order` | `asc` | 排序方向，`asc` 或 `desc` |
| `newonly` | `false` | 限定为标记为新档的档案 |
| `untaggedonly` | `false` | 限定为无标签档案 |
| `groupby_tanks` | `true` | 启用时，合集会取代其包含的档案出现在结果中（这也会改变 `recordsTotal`） |
| `hidecompleted` | `false` | 隐藏进度超过其页数 85% 的档案 |

响应携带 `{recordsTotal, recordsFiltered, data}`；对 `/api/search`，`data` 数组保存完整的档案元数据 JSON 对象；对 `/api/search/ids`，只保存档案 ID。如果搜索引擎尚未初始化（搜索 Redis 数据库中没有 `LAST_JOB_TIME` 标记），两个端点都会返回 **HTTP 204** 而非结果。

排序说明，来自 `lib/LANraragi/Model/Search.pm` 中的 `sort_results()`：

- 按任意命名空间排序会对结果分区：带有该命名空间的档案（按其值自然排序）在前，没有该命名空间的被排到末尾。对 `date_added`/`timestamp`，合集从其成员档案继承日期。
- `lastread` 需要服务器端进度跟踪，并会静默丢弃从未阅读过的 ID。

`GET /api/search/random` 接受 `filter`、`category`、`newonly`、`untaggedonly`、`groupby_tanks`、`hidecompleted` 以及 `count`（默认 5）；它从完整过滤集中随机抽取条目并返回完整的元数据对象。每个查询都缓存在搜索 Redis 数据库中（`LRR_SEARCHCACHE`，包括对倒序排序的复用）；`DELETE /api/search/cache` 映射到 `lib/LANraragi/Utils/Database.pm` 中的 `invalidate_cache()` 来丢弃缓存。

### 过滤器语法

`filter` 字符串由 `lib/LANraragi/Model/Search.pm` 中的 `compute_search_filter()` 解析；下面的各种情形由 `tests/search.t` 覆盖。

- 词元以逗号分隔，按 AND 逻辑组合。
- 裸关键字模糊匹配标签**和**标题（子串匹配）。
- `namespace:value` 将匹配限定到该标签命名空间；不带命名空间时，词元匹配任意命名空间中的标签。
- 双引号（`"male:very cool"`）使词元成为精确字符串匹配，并允许其中包含空格。
- 前导 `-` 排除其后的词元（`-character:ereshkigal`）；它必须位于引号*之外*才有效。
- 尾部 `$` 强制精确标签匹配（`character:segata$`）。
- `?` 或 `_` 匹配任意单个字符；`*` 或 `%` 匹配任意字符序列。两对可以互换。
- `pages:` 和 `read:` 分别与页数和已读页数计数器比较，接受 `=`（隐含）、`>`、`>=`、`<`、`<=`——例如 `pages:>150`、`read:<11, read:>9`。
- 词元在匹配前会转为小写。

## 端点参考

64 条路径上的 87 个操作，按规格标签分组。路径相对于 `/api` 前缀；处理器是相对于 `lib/LANraragi/Controller/Api/` 解析的 `x-mojo-to` 值。Auth 为 "API key" 对应 `api_key` 安全方案，"No" 对应 `security: []`。
**archives**（20 个操作）

| 方法 | 路径 | 处理器 | Auth | 描述 |
|---|---|---|---|---|
| `GET` | `/archives` | `api-archive#serve_archivelist` | No | 获取全部档案 |
| `GET` | `/archives/untagged` | `api-archive#serve_untagged_archivelist` | No | 获取全部无标签档案 |
| `PUT` | `/archives/upload` | `api-archive#create_archive` | API key | 🔑 上传档案 |
| `DELETE` | `/archives/{id}` | `api-archive#delete_archive` | API key | 🔑 删除档案 |
| `GET` | `/archives/{id}` | `api-archive#serve_metadata` | No | 获取档案元数据（已弃用） |
| `GET` | `/archives/{id}/categories` | `api-archive#get_categories` | No | 获取档案的分类 |
| `GET` | `/archives/{id}/download` | `api-archive#serve_file` | No | 下载档案 |
| `GET` | `/archives/{id}/files` | `api-archive#get_file_list` | No | 解压档案 |
| `POST` | `/archives/{id}/files/thumbnails` | `api-archive#generate_page_thumbnails` | No | 提取页面缩略图 |
| `DELETE` | `/archives/{id}/isnew` | `api-archive#clear_new` | No | 清除档案的新档标志 |
| `PUT` | `/archives/{id}/isnew` | `api-archive#add_new` | API key | 🔑 设置档案的新档标志 |
| `GET` | `/archives/{id}/metadata` | `api-archive#serve_metadata` | No | 获取档案元数据 |
| `PUT` | `/archives/{id}/metadata` | `api-archive#update_metadata` | API key | 🔑 更新档案元数据 |
| `GET` | `/archives/{id}/page` | `api-archive#serve_page` | No | 获取档案的某一页 |
| `PUT` | `/archives/{id}/progress/{page}` | `api-archive#update_progress` | No | 更新阅读进度 |
| `GET` | `/archives/{id}/tankoubons` | `api-tankoubon#get_tankoubons_file` | No | 获取档案所属合集 |
| `GET` | `/archives/{id}/thumbnail` | `api-archive#serve_thumbnail` | No | 获取档案缩略图 |
| `PUT` | `/archives/{id}/thumbnail` | `api-archive#update_thumbnail` | API key | 🔑 更新档案缩略图 |
| `DELETE` | `/archives/{id}/toc` | `api-archive#remove_toc` | API key | 🔑 从档案目录中移除条目 |
| `PUT` | `/archives/{id}/toc` | `api-archive#add_toc` | API key | 🔑 向档案目录添加条目 |

**categories**（10 个操作）

| 方法 | 路径 | 处理器 | Auth | 描述 |
|---|---|---|---|---|
| `GET` | `/categories` | `api-category#get_category_list` | No | 获取全部分类 |
| `PUT` | `/categories` | `api-category#create_category` | API key | 🔑 创建分类 |
| `DELETE` | `/categories/bookmark_link` | `api-category#remove_bookmark_link` | API key | 🔑 禁用书签功能 |
| `GET` | `/categories/bookmark_link` | `api-category#get_bookmark_link` | No | 获取书签关联的分类 |
| `PUT` | `/categories/bookmark_link/{id}` | `api-category#update_bookmark_link` | API key | 🔑 更新书签关联的分类 |
| `DELETE` | `/categories/{id}` | `api-category#delete_category` | API key | 🔑 删除分类 |
| `GET` | `/categories/{id}` | `api-category#get_category` | No | 获取单个分类 |
| `PUT` | `/categories/{id}` | `api-category#update_category` | API key | 🔑 更新分类 |
| `DELETE` | `/categories/{id}/{archive}` | `api-category#remove_from_category` | API key | 🔑 从分类中移除档案 |
| `PUT` | `/categories/{id}/{archive}` | `api-category#add_to_category` | API key | 🔑 向分类添加档案 |

**database**（8 个操作）

| 方法 | 路径 | 处理器 | Auth | 描述 |
|---|---|---|---|---|
| `GET` | `/database/backup` | `api-database#serve_backup` | API key | 🔑 获取备份 JSON |
| `POST` | `/database/backup` | `api-database#queue_backup` | API key | 🔑 将备份任务入队 |
| `GET` | `/database/backup/{jobid}` | `api-database#download_backup` | API key | 🔑 从已完成任务下载备份 JSON |
| `POST` | `/database/clean` | `api-database#clean_database` | API key | 🔑 清理数据库 |
| `POST` | `/database/drop` | `api-database#drop_database` | API key | 🔑 清空数据库 |
| `DELETE` | `/database/isnew` | `api-database#clear_new_all` | API key | 🔑 清除全部“新档”标志 |
| `POST` | `/database/restore` | `api-database#queue_restore` | API key | 🔑 将恢复任务入队 |
| `GET` | `/database/stats` | `api-database#serve_tag_stats` | No | 获取统计信息 |

**minion**（3 个操作）

| 方法 | 路径 | 处理器 | Auth | 描述 |
|---|---|---|---|---|
| `GET` | `/minion/{jobid}` | `api-minion#minion_job_status` | No | 获取 Minion 任务的基本状态 |
| `GET` | `/minion/{jobid}/detail` | `api-minion#minion_job_detail` | API key | 🔑 获取 Minion 任务的完整状态 |
| `POST` | `/minion/{jobname}/queue` | `api-minion#queue_minion_job` | API key | 🔑 将 Minion 任务入队 |

**misc**（4 个操作）

| 方法 | 路径 | 处理器 | Auth | 描述 |
|---|---|---|---|---|
| `POST` | `/download_url` | `api-other#download_url` | API key | 将 URL 下载入队 |
| `GET` | `/info` | `api-other#serve_serverinfo` | No | 获取服务器信息 |
| `POST` | `/regen_thumbs` | `api-other#regen_thumbnails` | API key | 重新生成缩略图 |
| `DELETE` | `/tempfolder` | `api-other#clean_tempfolder` | API key | 清理临时文件夹 |

**opds**（3 个操作）

| 方法 | 路径 | 处理器 | Auth | 描述 |
|---|---|---|---|---|
| `GET` | `/opds` | `api-other#serve_opds_catalog` | No | 获取 OPDS 目录 |
| `GET` | `/opds/{id}` | `api-other#serve_opds_item` | No | 通过 OPDS 获取特定档案 |
| `GET` | `/opds/{id}/pse` | `api-other#serve_opds_page` | No | OPDS-PSE |

**plugins**（5 个操作）

| 方法 | 路径 | 处理器 | Auth | 描述 |
|---|---|---|---|---|
| `POST` | `/plugins/install` | `api-plugins#install_plugin` | API key | 🔑 安装插件 |
| `DELETE` | `/plugins/installed/{plugin_namespace}` | `api-plugins#uninstall_plugin` | API key | 🔑 卸载插件 |
| `POST` | `/plugins/queue` | `api-other#use_plugin_async` | API key | 🔑 异步使用插件 |
| `POST` | `/plugins/use` | `api-other#use_plugin_sync` | API key | 🔑 使用插件 |
| `GET` | `/plugins/{type}` | `api-other#list_plugins` | API key | 🔑 列出可用插件 |

**registries**（9 个操作）

| 方法 | 路径 | 处理器 | Auth | 描述 |
|---|---|---|---|---|
| `GET` | `/registries` | `api-registry#list_registries` | API key | 🔑 列出注册表 |
| `POST` | `/registries` | `api-registry#create_registry` | API key | 🔑 创建注册表 |
| `DELETE` | `/registries/default_registry` | `api-registry#remove_default_registry` | API key | 🔑 清除默认仓库 |
| `GET` | `/registries/default_registry` | `api-registry#get_default_registry` | API key | 获取默认仓库 |
| `PUT` | `/registries/default_registry/{id}` | `api-registry#update_default_registry` | API key | 🔑 设置默认仓库 |
| `DELETE` | `/registries/{id}` | `api-registry#delete_registry` | API key | 🔑 删除注册表 |
| `GET` | `/registries/{id}` | `api-registry#get_registry` | API key | 🔑 获取注册表 |
| `PUT` | `/registries/{id}` | `api-registry#update_registry` | API key | 🔑 更新注册表 |
| `POST` | `/registries/{id}/refresh` | `api-registry#refresh_registry` | API key | 🔑 刷新注册表索引 |

**search**（4 个操作）

| 方法 | 路径 | 处理器 | Auth | 描述 |
|---|---|---|---|---|
| `GET` | `/search` | `api-search#handle_api` | No | 搜索档案 |
| `DELETE` | `/search/cache` | `api-search#clear_cache` | API key | 🔑 丢弃搜索缓存 |
| `GET` | `/search/ids` | `api-search#handle_api_ids` | No | 搜索档案 ID |
| `GET` | `/search/random` | `api-search#get_random_archives` | No | 随机搜索档案 |

**shinobu**（4 个操作）

| 方法 | 路径 | 处理器 | Auth | 描述 |
|---|---|---|---|---|
| `GET` | `/shinobu` | `api-shinobu#shinobu_status` | API key | 🔑 获取 Shinobu 状态 |
| `POST` | `/shinobu/rescan` | `api-shinobu#reset_filemap` | API key | 🔑 重新扫描文件映射并重启 Shinobu |
| `POST` | `/shinobu/restart` | `api-shinobu#restart_shinobu` | API key | 🔑 重启 Shinobu |
| `POST` | `/shinobu/stop` | `api-shinobu#stop_shinobu` | API key | 🔑 停止 Shinobu |

**stamps**（6 个操作）

| 方法 | 路径 | 处理器 | Auth | 描述 |
|---|---|---|---|---|
| `GET` | `/archives/{id}/stamps` | `api-stamp#get_stamped_pages` | No | 获取档案中至少包含一个图章的页面 |
| `GET` | `/archives/{id}/stamps/{index}` | `api-stamp#get_stamps_by_page` | No | 获取与该页面关联的图章 |
| `PUT` | `/archives/{id}/stamps/{index}` | `api-stamp#add_stamp` | API key | 🔑 添加图章注解 |
| `DELETE` | `/stamps/{id}` | `api-stamp#delete_stamp` | API key | 🔑 删除图章 |
| `GET` | `/stamps/{id}` | `api-stamp#get_stamp` | No | 获取图章 |
| `PUT` | `/stamps/{id}` | `api-stamp#update_stamp` | API key | 🔑 更新图章 |

**tankoubons**（11 个操作）

| 方法 | 路径 | 处理器 | Auth | 描述 |
|---|---|---|---|---|
| `GET` | `/tankoubons` | `api-tankoubon#get_tankoubon_list` | No | 获取全部合集 |
| `PUT` | `/tankoubons` | `api-tankoubon#create_tankoubon` | API key | 🔑 创建合集 |
| `DELETE` | `/tankoubons/{id}` | `api-tankoubon#delete_tankoubon` | API key | 🔑 删除合集 |
| `GET` | `/tankoubons/{id}` | `api-tankoubon#get_tankoubon` | No | 获取单个合集 |
| `PUT` | `/tankoubons/{id}` | `api-tankoubon#update_tankoubon` | API key | 🔑 更新合集的元数据/内容 |
| `GET` | `/tankoubons/{id}/full` | `api-tankoubon#get_tankoubon_full` | No | 获取单个合集的完整细节 |
| `PUT` | `/tankoubons/{id}/progress/{page}` | `api-tankoubon#update_tank_progress` | No | 更新合集阅读进度 |
| `GET` | `/tankoubons/{id}/thumbnail` | `api-tankoubon#serve_tankoubon_thumbnail` | No | 获取合集缩略图 |
| `PUT` | `/tankoubons/{id}/thumbnail` | `api-tankoubon#update_tankoubon_thumbnail` | API key | 🔑 更新合集缩略图 |
| `DELETE` | `/tankoubons/{id}/{archive}` | `api-tankoubon#remove_from_tankoubon` | API key | 🔑 从合集中移除档案 |
| `PUT` | `/tankoubons/{id}/{archive}` | `api-tankoubon#add_to_tankoubon` | API key | 🔑 向合集添加档案 |

## misc 端点详解

在 OpenAPI 操作中，`GET /api/info` 是个例外：它的处理器（`lib/LANraragi/Controller/Api/Other.pm`
中的 `serve_serverinfo()`）跳过 `openapi->valid_input`，直接渲染普通 JSON。它一次性转发
服务器状态——`name` 与 `motd`（`htmltitle`/`motd` 配置字段，经 XML 转义）、
`version`/`version_name`/`version_desc`（分别经 `LRR_VERSION`/`LRR_VERNAME`/`LRR_DESC` 助手取自 `package.json`）、布尔值
`has_password`、`debug_mode`、`nofun_mode`、`server_resizes_images`、`authenticated_progress`、
`server_tracks_progress`（`localprogress` 设置的反值）与 `restart_required`（取自
`LRR_SERVER`），外加 `archives_per_page`（`pagesize`）、`total_pages_read`
（`LRR_TOTALPAGESTAT`）、`total_archives`（`scard LRR_TANKGROUPED`）、`cache_last_cleared`
（`LRR_SEARCHCACHE` 的 `created` 字段）以及 `excluded_namespaces`。前端的 `index.js` 是它
唯一的消费者：GitHub 发行版版本检查、阅读器进度跟踪设置与页面大小都由它驱动。

其余 misc 端点有几处非显而易见的边角：

- `POST /api/download_url` 在 URL 存在时总是回答 `success: 1` 并附带任务 id——重复拒绝发生
  在 Minion 任务内部：它对照 `LRR_URLMAP` 检查 `is_url_recorded()`，并以
  `success: 0, message: "URL already downloaded!"` 结束，只能通过任务轮询看到。
- `DELETE /api/tempfolder` 并不删除任意临时文件：它清空 PageCache（`PageCache::clear()`），
  其响应中的 `newsize` 字段被硬编码为 `0`，尽管规格把它描述为清理后的文件夹大小。
- `POST /api/plugins/use` 与 `/api/plugins/queue` 没有锁/423 路径。在 `/plugins/use` 上，插件
  错误以 HTTP 200 加 `success: 0` 返回；在 `/plugins/queue` 上 HTTP 回答总是携带任务 id 的
  `success: 1`，错误只能通过轮询任务看到。`lib/LANraragi/Utils/Plugins.pm` 中的 `use_plugin()` 只分派 `script` 与
  `metadata` 两种类型——其他类型只会得到空的 `data` 对象。
- `GET /api/plugins/{type}` 除四种类型外还接受 `all`，返回每个插件的 `plugin_info`，并增补
  `parameters`（带名称的数组）、`registry`、`sha256` 与 `origin`——但没有 `enabled` 标志。

## OpenAPI 规格之外的路由

三条与 API 使用者相关的 HTTP 路由直接注册在 `lib/LANraragi/Utils/Routing.pm` 的 `apply_routes()` 中，因此不会出现在 `tools/openapi.yaml` 或上表中：

- **`GET /api/info/metrics`** —— 路由到 `lib/LANraragi/Controller/Api/Metrics.pm` 中的 `serve_metrics()`，后者渲染由 `lib/LANraragi/Model/Metrics.pm` 中的 `get_prometheus_metrics()` 构建的 Prometheus 展示格式（`text/plain; version=0.0.4; charset=utf-8`）。该路由只在 `enablemetrics` 设置开启（默认关闭）时注册，并且挂载在 `logged_in_api()` 之下，因此无论该设置如何，始终要求认证。
- **`WebSocket /batch/socket`** —— 批量打标签 websocket，由 `lib/LANraragi/Controller/Batch.pm` 中的 `socket()` 处理。它挂载在基于会话的 Web 登录（`lib/LANraragi/Controller/Login.pm` 中的 `logged_in()`）之下，因此通过浏览器会话或被禁用的密码认证——而非 API 密钥——并保持 80 秒的不活动超时。协议是每条消息一个命令，每条命令只覆盖一个档案：客户端发送 `{operation, plugin, category, args, archive}`，服务器以逐档案的 JSON 回复应答。共分派五种操作：`plugin`（经 `batch_plugin()` → `exec_metadata_plugin()` 运行元数据插件，把返回的标签经 `set_tags(..., 1)` *追加*，外加可选的标题/摘要，并接受逐消息的 `args` 覆盖）、`clearnew`（重置 `isnew`）、`tagrules`（经计算出的标签规则重写该档案的标签，随后使搜索缓存失效）、`addcat`（把档案加入 `category`）以及 `delete`（在 `archive-write:$id` 锁下运行 `delete_archive()`）。未知操作会收到 `success: 0` 回复且套接字保持打开；缺少 `archive` id 或插件名不存在的消息会以代码 1001 关闭套接字。单个插件错误只影响它自己的档案——批处理继续。服务端没有任何节流：档案之间的节奏完全由客户端控制（`batch.js` 按 `#timeout` 输入休眠，该输入由各插件的 `cooldown` 预填，UI 上限 20 秒），队列清空后客户端关闭套接字（代码 1000），随后调用 `DELETE /api/search/cache`。
- **`GET /search`** —— 支撑主档案表的 DataTables 端点，由 `lib/LANraragi/Controller/Api/Search.pm` 中的 `handle_datatables()` 处理。它使用 DataTables 服务器端协议（`draw`、`start`、`length`、`search[value]`、`order[0][column]`、`order[0][dir]`、`columns[i][name]`、`columns[i][search][value]`），外加两个更合理的自定义参数 `grouptanks`（默认 `true`）和 `hidecompleted`（默认 `false`）。`tags` 列的搜索值通常是分类 ID，魔法值 `NEW_ONLY` 和 `UNTAGGED_ONLY` 分别切换相应的过滤器。该路由与 OpenAPI 路由器共享 CORS 和 No-Fun 模式包装，但在其他方面无需认证。

## OPDS

OPDS 订阅源通过常规 OpenAPI 操作暴露（`GET /api/opds`、`GET /api/opds/{id}`、`GET /api/opds/{id}/pse`——见上文 *opds* 标签）。它提供由 `lib/LANraragi/Model/Opds.pm` 生成的 XML，并且是前文所述 `?key=` 认证回退的主要使用者，因为 OPDS 阅读器通常无法发送自定义头。OPDS 的具体风格在 [06_models.md](06_models.md) 的 *Reader & OPDS* 一节中有详细介绍。

## 保持规格健康

`tools/openapi.yaml` 是上述一切的机器可读契约。它通过 `npm run lint-openapi` 进行 lint，该命令运行 `redocly lint tools/openapi.yaml --config=redocly.yml`（见 `package.json`）；`redocly.yml` 配置扩展了 Redocly 的 `recommended` 规则集，并禁用了 `operation-4xx-response` 规则。作为标准的 OpenAPI 3.1 文档，该规格也可以交给任何支持 OpenAPI 的工具来生成客户端或交互式文档。
