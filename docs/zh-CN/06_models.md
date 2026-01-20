# 模型层深度分析

> 分析日期：2026-01-11

本文档提供模型层业务逻辑的详细分析。

---

## 📊 模块概览

| 模块 | 行数 | 主要功能 |
|------|------|----------|
| `Reader.pm` | 86 | 图像缩放、页面列表生成 |
| `Upload.pm` | 268 | 文件上传处理、重复检测、自动插件执行 |
| `Backup.pm` | 183 | 数据库备份/恢复（JSON 格式） |
| `Opds.pm` | 161 | OPDS 目录生成 |
| `Search.pm` | 524 | **核心** 搜索引擎 |
| `Tankoubon.pm` | 527 | 合集（有序档案集） |
| `Stats.pm` | ~300 | 统计计算 |
| `Category.pm` | ~350 | 分类管理 |

---

## 🔍 Search.pm - 核心搜索引擎

### 核心函数

#### `do_search($filter, $category_id, $start, $sortkey, $sortorder, $newonly, $untaggedonly, $grouptanks)`

主搜索入口点：

```perl
sub do_search {
    # 1. Check search cache
    my ($cachehit, @filtered) = check_cache($cachekey, $cachekey_inv);
    
    # 2. If cache miss, execute full search
    unless ($cachehit && $sortkey ne "lastread") {
        @filtered = search_uncached(...);
        $redis->hset("LRR_SEARCHCACHE", $cachekey, nfreeze \@filtered);
    }
    
    # 3. Return paginated results
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
    A[Search Request] --> B{Cache Hit?}
    B -->|Yes| C[Return Cache]
    B -->|No| D[Parse Search Terms]
    D --> E[Get Initial ID Set]
    E --> F{Static Category?}
    F -->|Yes| G[Intersect with Category Archives]
    F -->|No| H[Add to Search Conditions]
    G --> I[Apply newonly/untagged Filter]
    H --> I
    I --> J[Iterate Search Tokens]
    J --> K{Exact Match?}
    K -->|Yes| L[Query INDEX_tag]
    K -->|No| M[Query INDEX_*tag*]
    L --> N[Title Fuzzy Search]
    M --> N
    N --> O[Result Intersection/Difference]
    O --> P[Sort]
    P --> Q[Cache Results]
    Q --> R[Return Paginated]
```

### 排序优化 (Lua 脚本)

```perl
# Use Lua to batch fetch data, reduce network requests
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

Tankoubon（単行本）是有序的档案合集，类似于"播放列表"。

### Redis 存储结构

```
TANK_1589141306 (Sorted Set):
  score 0: "name_Collection Name"    # Metadata
  score -1: "summary_Description"
  score -2: "tags_Tags"
  score 1: "archive_id_1"           # Archives in order
  score 2: "archive_id_2"
  score 3: "archive_id_3"
```

### 核心函数

| 函数 | 用途 |
|------|------|
| `create_tankoubon($name, $tank_id)` | 创建合集 |
| `get_tankoubon($tank_id, $fulldata, $page)` | 获取合集详情 |
| `add_to_tankoubon($tank_id, $arc_id)` | 添加档案 |
| `remove_from_tankoubon($tank_id, $arc_id)` | 移除档案（自动重排序） |
| `update_archive_list($tank_id, $data)` | 批量更新顺序 |

### Tank 分组（搜索聚合）

启用 Tank 分组时：
- 合集中的档案从主搜索中隐藏
- 合集作为整体出现在搜索结果中
- 使用 `LRR_TANKGROUPED` Redis Set 进行跟踪

## 🔧 Reader.pm - 阅读器模型

### 核心函数

#### `resize_image($content, $quality, $threshold)`
按需图像压缩以节省带宽：

```perl
sub resize_image ( $content, $quality, $threshold ) {
    # Only compress if file size exceeds threshold
    if ( ( length($content) / 1024 ) > $threshold ) {
        return $resampler->resize_page( $content, $quality, "jpg" );
    }
    return $content;
}
```

**参数：**
- `$content`：图像二进制数据
- `$quality`：JPEG 质量 (0-100)
- `$threshold`：触发压缩的文件大小阈值 (KB)

#### `build_reader_JSON($self, $id, $force)`
构建阅读器页面列表：

```perl
sub build_reader_JSON ( $self, $id, $force ) {
    my $archive = get_archive_path( $redis, $id );
    my @images = get_filelist($archive, $id);
    
    foreach my $imgpath (@images) {
        # URI encoding
        $imgpath = uri_escape_utf8(redis_decode($imgpath));
        $imgpath =~ s!%2F!/!g;  # Preserve slashes
        
        # Build API URL
        push @images_browser, "/api/archives/$id/page?path=$imgpath";
    }
    
    # Update page count
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
    A[Receive File] --> B{Is Archive?}
    B -->|No| C[Return 415]
    B -->|Yes| D[Compute ID]
    D --> E{Already Exists?}
    E -->|Yes and No Replace| F[Return 409]
    E -->|Yes and Replace| G[Delete Old Archive]
    E -->|No| H[Add to Redis]
    G --> H
    H --> I[Set tags/title/summary]
    I --> J[Move File to Content Dir]
    J --> K[Add timestamp/pagecount/size]
    K --> L[Generate Thumbnail]
    L --> M[Execute autoplugin]
    M --> N{Category Specified?}
    N -->|Yes| O[Add to Category]
    N -->|No| P[Return Success]
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

4. **两阶段文件移动**（防止 Shinobu 提前检测）
```perl
move_path( $tempfile, $output_file . ".upload" );  # First move as .upload
rename_path( $output_file . ".upload", $output_file );  # Then rename to trigger update
```

5. **来源 URL 索引**
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
    
    # Content-Disposition parsing
    if ( $content_disp =~ /filename="(.*)"/ ) {
        $filename = $1;
    } elsif ( $content_disp =~ /filename\*=UTF-8''(.*)/ ) {
        $filename = uri_unescape($1);  # RFC 5987
    }
    
    # Windows illegal character cleanup
    $filename =~ s@[\\/:\\"*?<>|]+@@g;
    
    # Filename length limit (CryptoFS: 143, Normal: 255)
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
      "title": "Comic Title",
      "tags": "artist:name, parody:series",
      "summary": "Description",
      "thumbhash": "def456...",
      "filename": "file.zip"
    }
  ],
  "categories": [
    {
      "catid": "SET_123456",
      "name": "Favorites",
      "search": "",
      "archives": ["abc123", "def456"]
    }
  ],
  "tankoubons": [
    {
      "tankid": "TANK_789012",
      "name": "Collection Name",
      "archives": ["abc123", "def456"]
    }
  ]
}
```

### `build_backup_JSON()`

```perl
# Backup categories
my @cats = $redis->keys('SET_??????????');
foreach my $key (@cats) {
    my %data = $redis->hgetall($key);
    push @{$backup{categories}}, {
        catid => $key,
        name => redis_decode($data{name}),
        archives => decode_json($data{archives})
    };
}

# Backup collections
my @tanks = LANraragi::Model::Tankoubon::get_tankoubon_list(-1);
foreach my $tank (@tanks) {
    push @{$backup{tankoubons}}, {...};
}

# Backup archive metadata
my @keys = $redis->keys('?' x 40);  # 40 chars = Archive ID
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
2. 恢复分类（创建 + 添加成员）
3. 恢复单行本
4. 恢复档案元数据（仅更新现有）
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
从档案元数据生成 OPDS 条目：

```perl
# Extract metadata from tags
$arcdata->{author}   = get_tag_with_namespace("artist", $tags);
$arcdata->{language} = get_tag_with_namespace("language", $tags);
$arcdata->{circle}   = get_tag_with_namespace("group", $tags);

# MIME type mapping
if ($file =~ /\.pdf$/)     { $arcdata->{mimetype} = "application/pdf"; }
elsif ($file =~ /\.(rar|cbr)$/) { $arcdata->{mimetype} = "application/x-cbr"; }
elsif ($file =~ /\.epub$/) { $arcdata->{mimetype} = "application/epub+zip"; }
else                       { $arcdata->{mimetype} = "application/x-cbz"; }
```

#### `render_archive_page($mojo, $id, $page)`
直接提供单页图像（用于 OPDS 阅读器）：

```perl
my @images = get_filelist($archive, $id);
my $image = $images[$page - 1];
LANraragi::Model::Archive::serve_page($mojo, $id, $image);
```

---

## 📂 Category.pm - 分类管理模型

### 概念

分类分为两种类型：
- **静态分类**：手动添加的档案集合
- **动态分类**：基于搜索条件自动匹配的集合

### Redis 存储结构

```
SET_1589141306 (Hash):
  name: "Category Name"
  search: ""              # Empty string = Static category
  pinned: "1"             # Is pinned
  archives: '["id1","id2"]'  # JSON array (static only)
```

### 核心函数

| 函数 | 用途 |
|------|------|
| `get_category_list()` | 获取所有分类 |
| `get_static_category_list()` | 仅获取静态分类 |
| `get_categories_containing_archive($id)` | 查找包含档案的分类 |
| `get_category($id)` | 获取单个分类详情 |
| `create_category($name, $favtag, $pinned, $id)` | 创建/更新分类 |
| `delete_category($id)` | 删除分类 |
| `add_to_category($cat_id, $arc_id)` | 添加档案到静态分类 |
| `remove_from_category($cat_id, $arc_id)` | 从分类中移除档案 |

### 书签链接功能

```perl
# Link bookmark button to a static category
$redis->hset('LRR_CONFIG', 'bookmark_link', $cat_id);

# Get/remove bookmark link
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
| `LRR_URLMAP` | Hash | URL → 档案 ID 映射 |
| `LRR_STATS` | Sorted Set | 标签云统计（分数 = 出现次数） |
| `LRR_UNTAGGED` | Set | 未标记档案 ID |
| `LRR_NEW` | Set | 新档案 ID (isnew=true) |
| `LRR_TITLES` | Sorted Set | 标题索引（`title\0id` 格式） |
| `LRR_TANKGROUPED` | Set | 合集分组后的可见 ID |
| `INDEX_{tag}` | Set | 每个标签的档案 ID 索引 |

### 索引构建流程

```mermaid
flowchart TD
    A[Start build_stat_hashes] --> B[Get All Archive IDs]
    B --> C[Get All Tankoubons]
    C --> D[Iterate Tanks]
    D --> E[Add Tank ID to TANKGROUPED]
    E --> F[Index Tags in Tank Archives]
    F --> G[Iterate Remaining Archives]
    G --> H{Has Tags?}
    H -->|No| I[Add to LRR_UNTAGGED]
    H -->|Yes| J[Index Tags]
    J --> K{Has source: Tag?}
    K -->|Yes| L[Add to LRR_URLMAP]
    K -->|No| M[Continue]
    L --> M
    M --> N[Add to LRR_TITLES]
    N --> O[Check isnew]
    O --> P[End]
```

### 其他关键函数

| 函数 | 用途 |
|------|------|
| `get_archive_count()` | 获取档案数量（含 Tank 分组） |
| `get_page_stat()` | 获取总页数统计 |
| `is_url_recorded($url)` | 检查 URL 是否已在库中 |
| `build_tag_stats($minscore)` | 构建标签云 JSON |
| `compute_content_size()` | 计算库总大小 (GB) |
