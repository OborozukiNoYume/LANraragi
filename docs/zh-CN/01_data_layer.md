# 数据层：Redis 架构

> **分析文件**: `Redis.pm`, `Database.pm`, `Archive.pm`, `Category.pm`, `Tankoubon.pm`, `Config.pm`

---

## 📊 Redis 多数据库架构

项目使用 **4 个 Redis 数据库**（逻辑分离）：

| DB 编号 | 配置键 | 连接方法 | 用途 |
|---------|--------|----------|------|
| 0 (默认) | `redis_database` | `get_redis()` | 存档元数据存储 |
| 1 | `redis_database_minion` | `get_minion()` | Minion 任务队列 |
| 2 | `redis_database_config` | `get_redis_config()` | 全局配置 + 文件映射 |
| 3 | `redis_database_search` | `get_redis_search()` | 搜索索引 + 缓存 |

---

## 🗂️ 完整架构定义

### 1. Archive（存档）

| 存储类型 | 键格式 | 数据库 |
|----------|--------|--------|
| Redis Hash | `{40字符sha1}` | DB 0 (Archive) |

**字段：**

| 字段 | 类型 | 描述 |
|------|------|------|
| `name` | string | 原始文件名 |
| `title` | string | 显示标题 |
| `tags` | string | 逗号分隔的标签 |
| `summary` | string | 描述 |
| `file` | string | 文件路径（未编码） |
| `arcsize` | int64 | 文件大小（字节） |
| `isnew` | string | "true" 或 "false" |
| `progress` | int | 阅读进度（页码） |
| `pagecount` | int | 总页数 |
| `lastreadtime` | int64 | 最后阅读时间戳 |
| `thumbjob` | string | 缩略图任务 ID (Minion) |
| `thumbhash` | string | 第一张图片的 SHA-1 哈希 |

---

### 2. Category（分类）

| 存储类型 | 键格式 | 数据库 |
|----------|--------|--------|
| Redis Hash | `SET_{timestamp}` (14字符) | DB 0 (Archive) |

**两种类型：**
- **静态分类**：`search` 为空，`archives` 存储 JSON 数组
- **动态分类**：`search` 存储搜索查询，自动匹配存档

**字段：**

| 字段 | 类型 | 描述 |
|------|------|------|
| `name` | string | 分类名称 |
| `search` | string | 动态分类搜索查询（空 = 静态） |
| `pinned` | string | 是否置顶 |
| `archives` | JSON | 静态分类存档 ID 列表 |

**关键实现细节：**
```perl
# Archives 以 JSON 数组存储
$redis->hset( $cat_id, "archives", encode_json( \@cat_archives ) );
```

---

### 3. Tankoubon（合集/卷）

| 存储类型 | 键格式 | 数据库 |
|----------|--------|--------|
| Redis **Sorted Set** | `TANK_{timestamp}` (15字符) | DB 0 (Archive) |

**使用 Sorted Set 实现有序列表：**

| 分数 | 成员 | 用途 |
|------|------|------|
| 0 | `name_{title}` | 合集名称 |
| -1 | `summary_{text}` | 合集摘要 |
| -2 | `tags_{tags}` | 合集标签 |
| 1, 2, 3... | `{archive_id}` | 有序存档列表 |

**元数据存储机制：**
```perl
my %TANK_METADATA = ( "name" => 0, "summary" => -1, "tags" => -2 );
# 分数 0/-1/-2 用于元数据，正整数用于排序
$redis->zadd( $tank_id, $score, $arc_id );  # 添加存档
```

---

### 4. Config（全局配置）

| 存储类型 | 键 | 数据库 |
|----------|-----|--------|
| Redis Hash | `LRR_CONFIG` | DB 2 (Config) |

**主要配置字段：**

| 字段 | 类型 | 描述 |
|------|------|------|
| `dirname` | string | 内容目录（默认 ./content） |
| `thumbdir` | string | 缩略图目录（默认 ./thumb） |
| `htmltitle` | string | 页面标题 |
| `motd` | string | 欢迎信息 |
| `theme` | string | 主题 CSS |
| `pagesize` | int | 每页大小（默认 100） |
| `password` | string | bcrypt 密码哈希 |
| `enablepass` | bool | 启用密码保护 |
| `apikey` | string | API 密钥 |
| `enablecors` | bool | 启用 CORS |
| `devmode` | bool | 开发模式 |
| `enableresize` | bool | 启用图片缩放 |
| `usedateadded` | bool | 添加日期标签 |
| `enablecryptofs` | bool | 加密文件系统 |
| `tagruleson` | bool | 启用标签规则 |
| `localprogress` | bool | 本地进度 |
| `authprogress` | bool | 认证后保存进度 |
| `sizethreshold` | int | 缩放阈值 |
| `readerquality` | int | 阅读器质量 |
| `hqthumbpages` | bool | 高质量缩略图 |
| `jxlthumbpages` | bool | JXL 格式缩略图 |
| `replacedupe` | bool | 替换重复 |
| `replacetitles` | bool | 替换标题 |
| `tagrules` | string | 标签过滤规则 |
| `bookmark_link` | string | 书签分类 ID |

---

## 🔍 搜索索引结构 (DB 3)

| 键 | 类型 | 用途 |
|----|------|------|
| `LRR_TITLES` | Sorted Set | 标题索引（成员：`{title}\0{id}`） |
| `INDEX_{tag}` | Set | 标签索引（成员：存档 ID） |
| `LRR_NEW` | Set | 未读存档 ID |
| `LRR_UNTAGGED` | Set | 未打标签的存档 ID |
| `LRR_TANKGROUPED` | Set | 可搜索项（单独存档或合集） |
| `LRR_URLMAP` | Hash | URL → 存档 ID 映射 |
| `LRR_SEARCHCACHE` | Hash | 搜索缓存 |
| `LRR_STATS` | Sorted Set | 统计/标签云数据 |

---

## 🔧 配置数据库结构 (DB 2)

| 键 | 类型 | 用途 |
|----|------|------|
| `LRR_CONFIG` | Hash | 全局配置设置 |
| `LRR_FILEMAP` | Hash | 文件路径 → 存档 ID 映射 (Shinobu) |
| `LRR_TAGRULES` | List | 计算后的标签过滤规则 |
| `LRR_TOTALPAGESTAT` | String | 总阅读页数计数器 |
| `LRR_DUPLICATE_GROUPS` | Hash | 重复存档组数据 |
| `LRR_PLUGIN_{namespace}` | Hash | 插件设置存储 |

---

## 🔗 实体关系图

```mermaid
erDiagram
    Archive ||--o{ Category : "属于（静态）"
    Archive ||--o{ Tankoubon : "按顺序包含于"
    Category ||--o| Config : "bookmark_link"
    
    Archive {
        string id PK "SHA-1 (40字符)"
        string title
        string tags
        string file
    }
    
    Category {
        string id PK "SET_timestamp (14字符)"
        string name
        string search "空=静态"
        json archives "仅静态"
    }
    
    Tankoubon {
        string id PK "TANK_timestamp (15字符)"
        string name "score=0"
        string summary "score=-1"
        zset archives "score=1,2,3..."
    }
    
    Config {
        string key PK "LRR_CONFIG"
        hash settings
    }
```

---

## ⚠️ 重要说明

### 1. Category 与 Tankoubon 的区别

| 特性 | Category | Tankoubon |
|------|----------|-----------|
| 存储类型 | Hash + JSON | Sorted Set |
| 顺序 | 无序 | 有序（通过分数） |
| 类型 | 静态/动态 | 仅静态 |
| 搜索可见性 | 无影响 | 吸收存档 |

### 2. Tankoubon 搜索可见性逻辑

```perl
# 添加到合集时，从搜索中隐藏单独存档
$redis_search->srem( "LRR_TANKGROUPED", $arc_id );
$redis_search->sadd( "LRR_TANKGROUPED", $tank_id );
```

### 3. 环境变量覆盖

| 变量 | 描述 |
|------|------|
| `LRR_DATA_DIRECTORY` | 内容文件夹覆盖 |
| `LRR_THUMB_DIRECTORY` | 缩略图文件夹覆盖 |
| `LRR_TEMP_DIRECTORY` | 临时文件夹覆盖 |
| `LRR_LOG_DIRECTORY` | 日志文件夹覆盖 |
| `LRR_FORCE_DEBUG` | 强制启用调试模式 |
| `LRR_NETWORK` | 网络接口绑定 |
| `LRR_REDIS_ADDRESS` | Redis 地址覆盖（优先于 lrr.conf） |

---

## 🔑 存档 ID 计算

存档 ID 通过以下方式计算：
1. 读取存档文件的**前 512KB**
2. 从这些数据计算 **SHA-1 哈希**

> **注意**：这意味着两个前 512KB 相同的存档将具有相同的 ID，即使其余部分不同。

---

## 🔍 搜索缓存键格式

搜索结果缓存在 `LRR_SEARCHCACHE` 中，使用复合键：

```
{columnfilter}-{filter}-{sortkey}-{sortorder}-{newonly}
```

示例：`--title-asc-0`（无过滤器，按标题升序排序，非仅新内容）

缓存在以下情况下失效：
- 编辑存档元数据时
- 添加/删除存档时

---

## ✅ 总结

| 实体 | 存储类型 | 键格式 | 数据库 |
|------|----------|--------|--------|
| Archive | Hash | 40字符 SHA-1 | DB 0 |
| Category | Hash | `SET_` + 10位时间戳 | DB 0 |
| Tankoubon | Sorted Set | `TANK_` + 10位时间戳 | DB 0 |
| Config | Hash | `LRR_CONFIG` | DB 2 |
| File Map | Hash | `LRR_FILEMAP` | DB 2 |
| Plugin Settings | Hash | `LRR_PLUGIN_{namespace}` | DB 2 |
| Search Index | Set/ZSet/Hash | 多种 | DB 3 |
