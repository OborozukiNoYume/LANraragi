# 基础设施与工具

> **分析文件**: `Archive.pm`, `Minion.pm`, `Resizer.pm`, `Tags.pm`, `Generic.pm`

---

## 📦 归档处理 (Archive.pm)

### 核心依赖

| Perl 模块 | 用途 |
|-----------|------|
| `Archive::Libarchive` | ZIP/RAR/7z 格式 |
| `Archive::Libarchive::Peek` | 无需解压即可预览 |
| GhostScript (CLI) | PDF → JPG 转换 |

### 主要函数

| 函数 | 用途 |
|------|------|
| `get_filelist($archive, $id)` | 获取文件列表（自然排序） |
| `extract_file_from_archive($archive, $file)` | 解压单个文件到临时目录 |
| `extract_single_file_to_path($archive, $file, $dest)` | 解压到指定路径 |
| `is_file_in_archive($archive, $wanted)` | 检查文件是否存在于归档中 |
| `extract_thumbnail($thumbdir, $id, $page, $setcover, $usehq)` | 生成缩略图 |

### 文件排序逻辑

```perl
# Natural sort: pad numbers to 4 digits
sub expand {
    my $file = shift;
    $file =~ s{(\d+)}{sprintf "%04d", $1}eg;
    return lc($file);
}

# Special sorting: cover first, credits last
@files = ( @cover_pages, @other_pages, @credit_pages );
```

### PDF 处理

使用 GhostScript CLI：
```bash
# Extract all pages
gs -dNOPAUSE -sDEVICE=jpeg -r200 -o "$dest/%d.jpg" "$pdf"

# Extract specific page
gs -dNOPAUSE -dFirstPage=$page -dLastPage=$page -sDEVICE=jpeg -r200 -o "$out" "$pdf"
```

### Apple 资源分支过滤

自动过滤 macOS 资源分支文件：
- `__MACOSX/` 目录
- `._*` 前缀文件
- AppleDouble/AppleSingle 魔数检测

---

## ⚙️ 任务队列 (Minion.pm)

### 任务类型定义

| 任务名 | 用途 | 优先级 | 重试 |
|--------|------|--------|------|
| `thumbnail_task` | 单个缩略图生成 | 0 | 3 |
| `page_thumbnails` | 批量页面缩略图 | 0 | 3 |
| `regen_all_thumbnails` | 全库缩略图重建 | - | - |
| `find_duplicates` | 查找重复档案 | - | - |
| `build_stat_hashes` | 构建统计索引 | 3 | - |
| `handle_upload` | 处理上传文件 | - | - |
| `download_url` | 下载外部 URL | - | - |
| `run_plugin` | 执行插件 | - | - |

### 并行处理 (MCE::Loop)

```perl
# Unix: multi-process parallel
if ( IS_UNIX ) {
    mce_loop {
        $sub->(@{ $_ });
    } \@keys;
    MCE::Loop->finish;
} else {
    # Windows: serial execution (libarchive doesn't support threads)
    $sub->(@keys);
}
```

### 任务进度跟踪

```perl
# Use Minion's note feature for progress tracking
$job->note( $i => "processed", total_pages => $pages );
```

### 重复检测算法

使用**汉明距离**比较缩略图哈希：

```perl
for ( my $i = 0; $i < length( $thumbhashes{$node} ); $i++ ) {
    $distance++ if substr( $hash1, $i, 1 ) ne substr( $hash2, $i, 1 );
    last if $distance > $threshold;  # Early termination optimization
}
```

---

## 🖼️ 图像缩放 (Resizer.pm)

### 工厂模式

```perl
sub get_resizer() {
    state $resizer = resizer_factory();  # Singleton
    return $resizer;
}

sub resizer_factory {
    if (LANraragi::Utils::Vips::is_vips_loaded) {
        return LANraragi::Utils::VipsResizer->new;
    }
    return LANraragi::Utils::ImageMagickResizer->new;
}
```

### 接口定义

| 方法 | 参数 | 用途 |
|------|------|------|
| `resize_thumbnail` | `$data, $quality, $use_hq, $format` | 生成缩略图 |
| `resize_image` | `$data, $quality, $threshold` | 阅读器图像缩放 |

---

## 🏷️ Tags.pm - 标签处理工具

### 核心功能

标签规则系统支持多种规则类型：

| 规则类型 | 语法 | 示例 | 描述 |
|----------|------|------|------|
| `remove` | `-tag` 或 `tag` | `-yaoi` | 移除指定标签 |
| `remove_ns` | `-namespace:*` | `-misc:*` | 移除整个命名空间 |
| `strip_ns` | `~namespace` | `~language` | 保留标签但去除命名空间 |
| `replace` | `old -> new` | `serie:* -> parody:*` | 替换标签 |
| `replace_ns` | `ns1:* -> ns2:*` | `category:* -> genre:*` | 替换命名空间 |
| `hash_replace` | `old => new` | `foobar => correct_tag` | 高性能哈希替换（最后运行） |

### 标签规则语法

```
# Blacklist
-already uploaded
-forbidden content
ongoing

# Namespace removal
-misc:*

# Namespace replacement
serie:* -> parody:*

# Namespace stripping (keep value only)
~language

# Case-insensitive match, preserves replacement case
serie:one piece -> parody:One Piece

# Hash replace (faster, runs after all other rules)
various => various artists
```

**转换示例：**
```
Input:  already uploaded, misc:ongoing, language:english, serie:one piece, various
Output: english, parody:One Piece, various artists
```

### 关键函数

```perl
# Rule parsing
@rules = tags_rules_to_array($text_rules);

# Tag rewriting
@new_tags = rewrite_tags(\@tags, \@rules, \%hash_replace);

# Tag split/join
@tags = split_tags_to_array("tag1, tag2, tag3");
$str = join_tags_to_string(@tags);
```

---

## 🔧 Generic.pm - 通用工具函数

### 主要函数分类

| 函数 | 用途 |
|------|------|
| `is_image($file)` | 检查是否为图像 (png/jpg/jpeg/jfif/gif/bmp/webp/avif/heif/heic/jxl) |
| `is_archive($file)` | 检查是否为归档 (zip/rar/7z/tar/tar.gz/lzma/xz/cbz/cbr/cb7/cbt/pdf/epub/tar.zst/zst) |
| `render_api_response($mojo, $op, $err, $msg)` | 标准 API JSON 响应 |
| `get_tag_with_namespace($ns, $tags, $default)` | 按命名空间从标签字符串中提取值 |
| `shasum_str($data, $algo)` | 计算 SHA 哈希（用于 E-H 反向搜索） |

### 进程管理

```perl
# Start Shinobu (file watcher process)
sub start_shinobu {
    my $proc = Proc::Simple->new();
    $proc->start($^X, "./lib/Shinobu.pm");
    store \$proc, get_temp() . "/shinobu.pid";
}

# Start Minion Worker
sub start_minion {
    my $worker = $mojo->app->minion->worker;
    $worker->status->{jobs} = Sys::CpuAffinity::getNumCpus();
    $proc->start(sub { $worker->run });
}
```

### 数组/集合工具

```perl
# Intersection or difference
@result = intersect_arrays(\@arr1, \@arr2, $is_neg);

# Split workload by CPU count
@sections = split_workload_by_cpu($numCpus, @workload);

# Flatten nested array
@flat = flat(@nested);
```

### Redis 锁机制

```perl
sub exec_with_lock {
    my ($mojo, $redis, $lock_name, $operation, $resource_id, $func) = @_;
    my $lock = $redis->set($lock_name, 1, 'NX', 'EX', 10);  # 10s expiry
    if (!$lock) {
        $mojo->render(json => { error => "Locked resource" }, status => 423);
        return 0;
    }
    eval { $func->() };
    $redis->del($lock_name);
    return 1;
}
```

---

## ✅ 总结

| 组件 | Perl 依赖 | 用途 |
|------|-----------|------|
| 归档 | Archive::Libarchive | ZIP/RAR/7z 解压 |
| PDF | GhostScript CLI | PDF 转图像 |
| 图像 | libvips / ImageMagick | 图像缩放 |
| 任务队列 | Minion (Redis) | 后台任务处理 |
| 并行 | MCE::Loop | 多进程并行 |
