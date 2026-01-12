# Phase 3: 基础设施与工具分析报告

> **分析文件**: `Archive.pm`, `Minion.pm`, `Resizer.pm`  
> **分析日期**: 2026-01-11

---

## 📦 压缩包处理 (Archive.pm)

### 核心依赖

| Perl 模块 | 用途 | Go 替代方案 |
|-----------|------|-------------|
| `Archive::Libarchive` | ZIP/RAR/7z 等格式 | `mholt/archiver` 或 `libarchive` CGO |
| `Archive::Libarchive::Peek` | 不解压查看文件 | `archive/zip` + 流式读取 |
| GhostScript (命令行) | PDF → JPG 转换 | `pdfcpu` / `mupdf` CGO |

### 主要功能

```go
// Go 接口提案
type ArchiveHandler interface {
    // 获取文件列表 (按自然排序)
    GetFileList(archivePath string, id string) ([]string, error)
    
    // 提取单个文件到内存
    ExtractSingleFile(archivePath, filePath string) ([]byte, error)
    
    // 提取单个文件到磁盘
    ExtractSingleFileToPath(archivePath, filePath, dest string) (string, error)
    
    // 检查文件是否存在于压缩包中
    IsFileInArchive(archivePath, wantedName string) (string, bool)
    
    // 生成缩略图
    ExtractThumbnail(thumbDir, id string, page int, setCover, useHQ bool) (string, error)
}
```

### 文件排序逻辑

```perl
# 自然排序: 将数字填充为4位
sub expand {
    my $file = shift;
    $file =~ s{(\d+)}{sprintf "%04d", $1}eg;
    return lc($file);
}

# 特殊排序: cover 在前，credits 在后
@files = ( @cover_pages, @other_pages, @credit_pages );
```

**Go 实现:**
```go
import "github.com/facette/natsort"

func SortArchiveFiles(files []string) []string {
    // 1. 自然排序
    natsort.Sort(files)
    
    // 2. 提取 cover/credit
    var covers, credits, others []string
    for _, f := range files {
        switch {
        case isCoverPage(f):
            covers = append(covers, f)
        case isCreditPage(f):
            credits = append(credits, f)
        default:
            others = append(others, f)
        }
    }
    return append(append(covers, others...), credits...)
}
```

### PDF 处理

使用 GhostScript 命令行：
```bash
# 提取所有页面
gs -dNOPAUSE -sDEVICE=jpeg -r200 -o "$dest/%d.jpg" "$pdf"

# 提取指定页面
gs -dNOPAUSE -dFirstPage=$page -dLastPage=$page -sDEVICE=jpeg -r200 -o "$out" "$pdf"
```

**Go 替代方案:**
- `github.com/pdfcpu/pdfcpu` - 纯 Go PDF 库
- `github.com/nicferrier/gomupdf` - MuPDF CGO 绑定

### Apple 签名文件过滤

自动过滤 macOS 创建的资源分支文件：
- `__MACOSX/` 目录
- `._*` 开头的文件
- AppleDouble/AppleSingle 魔数检测

---

## ⚙️ 任务队列 (Minion.pm)

### Job 类型定义

| Job 名称 | 用途 | 优先级 | 重试 |
|----------|------|--------|------|
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
# Unix 下使用多进程并行
if ( IS_UNIX ) {
    mce_loop {
        $sub->(@{ $_ });
    } \@keys;
    MCE::Loop->finish;
} else {
    # Windows 下串行执行 (libarchive 不支持线程)
    $sub->(@keys);
}
```

**Go 实现:**
```go
// 使用 worker pool 模式
func ProcessThumbnails(ids []string, workers int) {
    sem := make(chan struct{}, workers)
    var wg sync.WaitGroup
    
    for _, id := range ids {
        wg.Add(1)
        sem <- struct{}{}
        go func(id string) {
            defer wg.Done()
            defer func() { <-sem }()
            generateThumbnail(id)
        }(id)
    }
    wg.Wait()
}
```

### Job 进度追踪

```perl
# 使用 Minion 的 note 功能追踪进度
$job->note( $i => "processed", total_pages => $pages );
```

### 重复检测算法

使用 **Hamming 距离** 比较缩略图哈希：

```perl
for ( my $i = 0; $i < length( $thumbhashes{$node} ); $i++ ) {
    $distance++ if substr( $hash1, $i, 1 ) ne substr( $hash2, $i, 1 );
    last if $distance > $threshold;  # 早停优化
}
```

**Go 实现:**
```go
func HammingDistance(hash1, hash2 string) int {
    distance := 0
    for i := 0; i < len(hash1) && i < len(hash2); i++ {
        if hash1[i] != hash2[i] {
            distance++
        }
    }
    return distance
}
```

---

## 🖼️ 图像缩放 (Resizer.pm)

### 工厂模式

```perl
sub get_resizer() {
    state $resizer = resizer_factory();  # 单例
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

### Go 替代方案

| Perl 库 | Go 替代 | 说明 |
|---------|---------|------|
| Image::Magick | `disintegration/imaging` | 纯 Go，功能较少 |
| libvips (FFI) | `davidbyttow/govips` | CGO，高性能 |

**Go 接口设计:**
```go
type ImageResizer interface {
    // 生成缩略图 (500px 高度)
    ResizeThumbnail(data []byte, quality int, hq bool, format string) ([]byte, error)
    
    // 阅读器图像缩放
    ResizeImage(data []byte, quality int, threshold int) ([]byte, error)
}

// 工厂函数
func NewResizer() ImageResizer {
    if govips.IsAvailable() {
        return &VipsResizer{}
    }
    return &ImagingResizer{}  // 纯 Go fallback
}
```

---

## 🔄 Go 任务队列设计

### 推荐库: `hibiken/asynq`

```go
package worker

import (
    "github.com/hibiken/asynq"
)

// 任务类型
const (
    TypeThumbnail      = "thumbnail:generate"
    TypePageThumbnails = "thumbnail:pages"
    TypeUpload         = "upload:handle"
    TypeDownload       = "download:url"
    TypePlugin         = "plugin:run"
    TypeStats          = "stats:build"
    TypeDuplicates     = "duplicates:find"
)

// 缩略图任务
type ThumbnailPayload struct {
    ID       string `json:"id"`
    Page     int    `json:"page"`
    SetCover bool   `json:"set_cover"`
    UseHQ    bool   `json:"use_hq"`
}

func NewThumbnailTask(id string, page int) *asynq.Task {
    payload, _ := json.Marshal(ThumbnailPayload{
        ID:   id,
        Page: page,
    })
    return asynq.NewTask(TypeThumbnail, payload,
        asynq.Queue("thumbnails"),
        asynq.MaxRetry(3),
    )
}
```

---

## 🏷️ Tags.pm - 标签处理工具 (4KB)

### 核心功能

标签规则系统，支持多种规则类型：

| 规则类型 | 语法 | 示例 | 说明 |
|----------|------|------|------|
| `remove` | `-tag` 或 `tag` | `-yaoi` | 移除指定标签 |
| `remove_ns` | `-namespace:*` | `-misc:*` | 移除整个命名空间 |
| `strip_ns` | `~namespace` | `~language` | 保留标签但去除命名空间 |
| `replace` | `old -> new` | `serie:* -> parody:*` | 替换标签 |
| `replace_ns` | `ns1:* -> ns2:*` | `category:* -> genre:*` | 替换命名空间 |
| `hash_replace` | `old => new` | `foobar => correct_tag` | 高性能哈希替换 (最后执行) |

### 标签规则语法 (官方)

```
# 黑名单
-already uploaded
-forbidden content
ongoing

# 移除命名空间
-misc:*

# 替换命名空间
serie:* -> parody:*

# 剥离命名空间 (仅保留值)
~language

# 大小写不敏感匹配，保留替换内容的大小写
serie:one piece -> parody:One Piece

# 哈希替换 (更快，在所有其他规则后执行)
various => various artists
```

**转换示例:**
```
输入:  already uploaded, misc:ongoing, language:english, serie:one piece, various
输出: english, parody:One Piece, various artists
```

### 关键函数

```perl
# 规则解析
@rules = tags_rules_to_array($text_rules);

# 标签重写
@new_tags = rewrite_tags(\@tags, \@rules, \%hash_replace);

# 标签拆分/合并
@tags = split_tags_to_array("tag1, tag2, tag3");
$str = join_tags_to_string(@tags);
```

### Go 实现建议

```go
type TagRule struct {
    Type  string // remove, remove_ns, strip_ns, replace, replace_ns
    Match string
    Value string
}

func RewriteTags(tags []string, rules []TagRule, hashReplace map[string]string) []string {
    // 遍历并应用规则
}
```

---

## 🔧 Generic.pm - 通用工具函数 (11KB)

### 主要功能分类

| 函数 | 用途 |
|------|------|
| `is_image($file)` | 检查是否为图片 (png/jpg/jpeg/jfif/gif/bmp/webp/avif/heif/heic/jxl) |
| `is_archive($file)` | 检查是否为压缩包 (zip/rar/7z/tar/tar.gz/lzma/xz/cbz/cbr/cb7/cbt/pdf/epub/tar.zst/zst) |
| `render_api_response($mojo, $op, $err, $msg)` | 标准 API JSON 响应 |
| `get_tag_with_namespace($ns, $tags, $default)` | 从标签字符串提取指定命名空间的值 |
| `shasum_str($data, $algo)` | 计算 SHA 哈希 (用于 E-H 逆向搜索) |

### 进程管理

```perl
# 启动 Shinobu (文件监控进程)
sub start_shinobu {
    my $proc = Proc::Simple->new();
    $proc->start($^X, "./lib/Shinobu.pm");
    store \$proc, get_temp() . "/shinobu.pid";
}

# 启动 Minion Worker
sub start_minion {
    my $worker = $mojo->app->minion->worker;
    $worker->status->{jobs} = Sys::CpuAffinity::getNumCpus();
    $proc->start(sub { $worker->run });
}
```

### 数组/集合工具

```perl
# 求交集或差集
@result = intersect_arrays(\@arr1, \@arr2, $is_neg);

# 按 CPU 数量拆分工作负载
@sections = split_workload_by_cpu($numCpus, @workload);

# 扁平化嵌套数组
@flat = flat(@nested);
```

### Redis 锁机制

```perl
sub exec_with_lock {
    my ($mojo, $redis, $lock_name, $operation, $resource_id, $func) = @_;
    my $lock = $redis->set($lock_name, 1, 'NX', 'EX', 10);  # 10秒过期
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

## ✅ Phase 3 分析总结

| 组件 | Perl 依赖 | Go 替代方案 | 复杂度 |
|------|-----------|-------------|--------|
| 压缩包 | Archive::Libarchive | `mholt/archiver` / CGO | ⭐⭐⭐ |
| PDF | GhostScript CLI | `pdfcpu` / MuPDF | ⭐⭐⭐⭐ |
| 图像 | libvips / ImageMagick | `govips` / `imaging` | ⭐⭐ |
| 任务队列 | Minion (Redis) | `hibiken/asynq` | ⭐⭐⭐ |
| 并行处理 | MCE::Loop | `sync.WaitGroup` + worker pool | ⭐⭐ |

### 关键迁移点

1. **PDF 处理**: 考虑使用 `pdfcpu` 替代 GhostScript 减少外部依赖
2. **图像处理**: 优先 `govips` (性能)，fallback 到 `imaging` (兼容性)
3. **任务队列**: `asynq` 与 Redis 原生集成，支持优先级和重试
4. **并行安全**: 注意 Windows 下 libarchive 线程问题
