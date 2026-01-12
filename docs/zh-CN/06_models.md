# Model 层深度分析

> 分析日期: 2026-01-11

本文档提供 Model 层业务逻辑的详细分析。

---

## 📊 模块概述

| 模块 | 行数 | 主要功能 |
|------|------|----------|
| `Reader.pm` | 86 | 图片缩放、页面列表生成 |
| `Upload.pm` | 268 | 文件上传处理、重复检测、自动插件执行 |
| `Backup.pm` | 183 | 数据库备份/恢复（JSON 格式） |
| `Opds.pm` | 161 | OPDS Catalog 生成 |
| `Search.pm` | 524 | **核心**搜索引擎 |
| `Tankoubon.pm` | 527 | 合集（有序存档集合） |
| `Stats.pm` | ~300 | 统计计算 |
| `Category.pm` | ~350 | 分类管理 |

---

## 🔍 Search.pm - 核心搜索引擎

### 核心函数

#### `do_search($filter, $category_id, $start, $sortkey, $sortorder, $newonly, $untaggedonly, $grouptanks)`

主搜索入口：

```perl
sub do_search {
    # 1. 检查搜索缓存
    my ($cachehit, @filtered) = check_cache($cachekey, $cachekey_inv);
    
    # 2. 缓存未命中则执行完整搜索
    unless ($cachehit && $sortkey ne "lastread") {
        @filtered = search_uncached(...);
        $redis->hset("LRR_SEARCHCACHE", $cachekey, nfreeze \@filtered);
    }
    
    # 3. 返回分页结果
    return ($total, $#filtered + 1, @filtered[$start..$end]);
}
```

### 搜索语法解析 (`compute_search_filter`)

| 语法 | 含义 | 示例 |
|------|------|------|
| `keyword` | 模糊匹配标题/标签 | `fate` |
| `"exact"` | 精确匹配 | `"fate grand order"` |
| `-keyword` | 排除 | `-yaoi` |
| `namespace:value` | 命名空间搜索 | `artist:wada` |
| `pages:>20` | 页数过滤 | `pages:>=50` |
| `read:>0` | 已读页数 | `read:10` |
| `?` `_` | 单字符通配符 | `fate_go` |
| `*` `%` | 多字符通配符 | `fate*` |

### 搜索流程

```mermaid
flowchart TD
    A[搜索请求] --> B{缓存命中?}
    B -->|是| C[返回缓存]
    B -->|否| D[解析搜索词]
    D --> E[获取初始 ID 集合]
    E --> F{静态分类?}
    F -->|是| G[与分类存档取交集]
    F -->|否| H[添加到搜索条件]
    G --> I[应用 newonly/untagged 过滤器]
    H --> I
    I --> J[迭代搜索 Token]
    J --> K{精确匹配?}
    K -->|是| L[查询 INDEX_tag]
    K -->|否| M[查询 INDEX_*tag*]
    L --> N[标题模糊搜索]
    M --> N
    N --> O[结果交集/差集]
    O --> P[排序]
    P --> Q[缓存结果]
    Q --> R[返回分页]
```

### 排序优化（Lua 脚本）

```perl
# 使用 Lua 批量获取数据，减少网络请求
my $script = <<'LUA';
local result = {}
for i=1,#ARGV do
    local id = ARGV[i]
    local value = redis.call('HGET', id, 'lastreadtime')
    result[i] = {id, value or "0"}
end
return cjson.encode(result)
LUA
```

---

## 📚 Tankoubon.pm - 合集系统

### 概念

Tankoubon（単行本）是有序的存档集合，类似于"播放列表"。

### Redis 存储结构

```
TANK_1589141306 (Sorted Set):
  score 0: "name_合集名称"    # 元数据
  score -1: "summary_描述"
  score -2: "tags_标签"
  score 1: "archive_id_1"     # 按顺序的存档
  score 2: "archive_id_2"
  score 3: "archive_id_3"
```

### 核心函数

| 函数 | 用途 |
|------|------|
| `create_tankoubon($name, $tank_id)` | 创建合集 |
| `get_tankoubon($tank_id, $fulldata, $page)` | 获取合集详情 |
| `add_to_tankoubon($tank_id, $arc_id)` | 添加存档 |
| `remove_from_tankoubon($tank_id, $arc_id)` | 移除存档（自动重排序） |
| `update_archive_list($tank_id, $data)` | 批量更新顺序 |

### Tank Grouping（搜索聚合）

启用 Tank Grouping 时：
- 合集中的存档在主搜索中隐藏
- 合集作为一个整体出现在搜索结果中
- 使用 `LRR_TANKGROUPED` Redis Set 进行追踪

## 🔧 Reader.pm - 阅读器模型

### 核心函数

#### `resize_image($content, $quality, $threshold)`
按需图片压缩以节省带宽：

```perl
sub resize_image ( $content, $quality, $threshold ) {
    # 仅当文件大小超过阈值时压缩
    if ( ( length($content) / 1024 ) > $threshold ) {
        return $resampler->resize_page( $content, $quality, "jpg" );
    }
    return $content;
}
```

**参数：**
- `$content`: 图片二进制数据
- `$quality`: JPEG 质量 (0-100)
- `$threshold`: 触发压缩的文件大小阈值 (KB)

#### `build_reader_JSON($self, $id, $force)`
构建阅读器页面列表：

```perl
sub build_reader_JSON ( $self, $id, $force ) {
    my $archive = get_archive_path( $redis, $id );
    my @images = get_filelist($archive, $id);
    
    foreach my $imgpath (@images) {
        # URI 编码
        $imgpath = uri_escape_utf8(redis_decode($imgpath));
        $imgpath =~ s!%2F!/!g;  # 保留斜杠
        
        # 构建 API URL
        push @images_browser, "/api/archives/$id/page?path=$imgpath";
    }
    
    # 更新页数
    $redis->hset( $id, "pagecount", scalar @images );
    
    return { pages => \@images_browser };
}
```

**返回格式：**
```json
{
  "pages": [
    "/api/archives/{id}/page?path=001.jpg",
    "/api/archives/{id}/page?path=002.jpg"
  ]
}
```

---

## 📤 Upload.pm - 上传处理模型

### 核心函数

#### `handle_incoming_file($tempfile, $catid, $tags, $title, $summary)`

完整上传处理流程：

```mermaid
flowchart TD
    A[接收文件] --> B{是压缩包?}
    B -->|否| C[返回 415]
    B -->|是| D[计算 ID]
    D --> E{已存在?}
    E -->|是且不替换| F[返回 409]
    E -->|是且替换| G[删除旧存档]
    E -->|否| H[添加到 Redis]
    G --> H
    H --> I[设置 tags/title/summary]
    I --> J[移动文件到内容目录]
    J --> K[添加 timestamp/pagecount/size]
    K --> L[生成缩略图]
    L --> M[执行 autoplugin]
    M --> N{指定了分类?}
    N -->|是| O[添加到分类]
    N -->|否| P[返回成功]
    O --> P
```

**关键处理步骤：**

1. **文件验证**
```perl
unless ( is_archive($filename) ) {
    return ( 415, "deadbeef", $filename, "Unsupported File Extension" );
}
```

2. **ID 计算**（基于文件内容 SHA1）
```perl
my $id = compute_id($tempfile);
```

3. **重复检测**
```perl
my $isdupe = $redis->exists($id) && -e get_archive_path($redis, $id);
if ( (-e $output_file || $isdupe) && !$replace_dupe ) {
    return ( 409, $id, $filename, "This file already exists" );
}
```

4. **两阶段文件移动**（防止 Shinobu 过早检测）
```perl
move_path( $tempfile, $output_file . ".upload" );  # 先以 .upload 移动
rename_path( $output_file . ".upload", $output_file );  # 然后重命名触发更新
```

5. **Source URL 索引**
```perl
if ( $t =~ /source:(.*)/i ) {
    $redis_search->hset( "LRR_URLMAP", trim_url($url), $id );
}
```

#### `download_url($url, $ua)`

远程文件下载：

```perl
sub download_url ( $url, $ua ) {
    my $tx = $ua->max_response_size(0)->max_redirects(5)->get($url);
    
    # Content-Disposition 解析
    if ( $content_disp =~ /filename="(.*)"/ ) {
        $filename = $1;
    } elsif ( $content_disp =~ /filename\*=UTF-8''(.*)/ ) {
        $filename = uri_unescape($1);  # RFC 5987
    }
    
    # Windows 非法字符清理
    $filename =~ s@[\\/:\\"*?<>|]+@@g;
    
    # 文件名长度限制（CryptoFS: 143, 普通: 255）
    while ( get_bytelength($filename . $ext . ".upload") > $byte_limit ) {
        $filename = substr($filename, 0, -1);
    }
    
    $tx->result->save_to("$tempdir/$filename");
    return "$tempdir/$filename";
}
```

---

## 💾 Backup.pm - 备份/恢复模型

### 备份 JSON 结构

```json
{
  "archives": [
    {
      "arcid": "abc123...",
      "title": "漫画标题",
      "tags": "artist:name, parody:series",
      "summary": "描述",
      "thumbhash": "def456...",
      "filename": "file.zip"
    }
  ],
  "categories": [
    {
      "catid": "SET_123456",
      "name": "收藏夹",
      "search": "",
      "archives": ["abc123", "def456"]
    }
  ],
  "tankoubons": [
    {
      "tankid": "TANK_789012",
      "name": "合集名称",
      "archives": ["abc123", "def456"]
    }
  ]
}
```

### `build_backup_JSON()`

```perl
# 备份分类
my @cats = $redis->keys('SET_??????????');
foreach my $key (@cats) {
    my %data = $redis->hgetall($key);
    push @{$backup{categories}}, {
        catid => $key,
        name => redis_decode($data{name}),
        archives => decode_json($data{archives})
    };
}

# 备份合集
my @tanks = LANraragi::Model::Tankoubon::get_tankoubon_list(-1);
foreach my $tank (@tanks) {
    push @{$backup{tankoubons}}, {...};
}

# 备份存档元数据
my @keys = $redis->keys('?' x 40);  # 40 字符 = 存档 ID
foreach my $id (@keys) {
    push @{$backup{archives}}, {
        arcid => $id,
        title => redis_decode($hash{title}),
        tags => redis_decode($hash{tags}),
        ...
    };
}
```

### `restore_from_JSON($json)`

恢复流程：
1. 调用 `clean_database()` 清理无效条目
2. 恢复 Categories（创建 + 添加成员）
3. 恢复 Tankoubons
4. 恢复 Archives 元数据（仅更新现有）
5. 调用 `invalidate_cache()` 刷新缓存

---

## 📚 Opds.pm - OPDS 协议支持

### OPDS 输出结构

```xml
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>{server_title}</title>
  <entry>
    <title>{archive_title}</title>
    <author><name>{artist}</name></author>
    <dc:language>{language}</dc:language>
    <updated>{lastreaddate}</updated>
    <link rel="http://opds-spec.org/acquisition" 
          type="{mimetype}" 
          href="/api/archives/{id}/download"/>
    <link rel="http://opds-spec.org/image" 
          type="image/jpeg" 
          href="/api/archives/{id}/thumbnail"/>
  </entry>
</feed>
```

### 关键函数

#### `get_opds_data($id)`
从存档元数据生成 OPDS 条目：

```perl
# 从标签提取元数据
$arcdata->{author}   = get_tag_with_namespace("artist", $tags);
$arcdata->{language} = get_tag_with_namespace("language", $tags);
$arcdata->{circle}   = get_tag_with_namespace("group", $tags);

# MIME 类型映射
if ($file =~ /\.pdf$/)     { $arcdata->{mimetype} = "application/pdf"; }
elsif ($file =~ /\.(rar|cbr)$/) { $arcdata->{mimetype} = "application/x-cbr"; }
elsif ($file =~ /\.epub$/) { $arcdata->{mimetype} = "application/epub+zip"; }
else                       { $arcdata->{mimetype} = "application/x-cbz"; }
```

#### `render_archive_page($mojo, $id, $page)`
直接提供单页图片（用于 OPDS 阅读器）：

```perl
my @images = get_filelist($archive, $id);
my $image = $images[$page - 1];
LANraragi::Model::Archive::serve_page($mojo, $id, $image);
```

---

## 📂 Category.pm - 分类管理模型

### 概念

分类分为两种类型：
- **静态分类**：手动添加的存档集合
- **动态分类**：基于搜索条件自动匹配的集合

### Redis 存储结构

```
SET_1589141306 (Hash):
  name: "分类名称"
  search: ""              # 空字符串 = 静态分类
  pinned: "1"             # 是否置顶
  archives: '["id1","id2"]'  # JSON 数组（仅静态）
```

### 核心函数

| 函数 | 用途 |
|------|------|
| `get_category_list()` | 获取所有分类 |
| `get_static_category_list()` | 仅获取静态分类 |
| `get_categories_containing_archive($id)` | 查找包含存档的分类 |
| `get_category($id)` | 获取单个分类详情 |
| `create_category($name, $favtag, $pinned, $id)` | 创建/更新分类 |
| `delete_category($id)` | 删除分类 |
| `add_to_category($cat_id, $arc_id)` | 添加存档到静态分类 |
| `remove_from_category($cat_id, $arc_id)` | 从分类移除存档 |

### 书签链接功能

```perl
# 将书签按钮链接到静态分类
$redis->hset('LRR_CONFIG', 'bookmark_link', $cat_id);

# 获取/移除书签链接
get_bookmark_link();
update_bookmark_link($cat_id);
remove_bookmark_link();
```

---

## 📊 Stats.pm - 统计和索引构建

### 核心函数

`build_stat_hashes()` 是重建搜索索引的核心函数，构建以下 Redis 结构：

| Redis 键 | 类型 | 用途 |
|----------|------|------|
| `LRR_URLMAP` | Hash | URL → 存档 ID 映射 |
| `LRR_STATS` | Sorted Set | 标签云统计（分数 = 出现次数） |
| `LRR_UNTAGGED` | Set | 未打标签的存档 ID |
| `LRR_NEW` | Set | 新存档 ID (isnew=true) |
| `LRR_TITLES` | Sorted Set | 标题索引（`title\0id` 格式） |
| `LRR_TANKGROUPED` | Set | 合集分组后可见的 ID |
| `INDEX_{tag}` | Set | 每个标签的存档 ID 索引 |

### 索引构建流程

```mermaid
flowchart TD
    A[开始 build_stat_hashes] --> B[获取所有存档 ID]
    B --> C[获取所有 Tankoubons]
    C --> D[迭代 Tanks]
    D --> E[添加 Tank ID 到 TANKGROUPED]
    E --> F[索引 Tank 存档中的标签]
    F --> G[迭代剩余存档]
    G --> H{有标签?}
    H -->|否| I[添加到 LRR_UNTAGGED]
    H -->|是| J[索引标签]
    J --> K{有 source: 标签?}
    K -->|是| L[添加到 LRR_URLMAP]
    K -->|否| M[继续]
    L --> M
    M --> N[添加到 LRR_TITLES]
    N --> O[检查 isnew]
    O --> P[结束]
```

### 其他关键函数

| 函数 | 用途 |
|------|------|
| `get_archive_count()` | 获取存档数量（包括 Tank 分组） |
| `get_page_stat()` | 获取总页数统计 |
| `is_url_recorded($url)` | 检查 URL 是否已在库中 |
| `build_tag_stats($minscore)` | 构建标签云 JSON |
| `compute_content_size()` | 计算库总大小 (GB) |
