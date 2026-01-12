# 基础设施和工具类

> **分析文件**: `Archive.pm`, `Minion.pm`, `Resizer.pm`, `Tags.pm`, `Generic.pm`

---

## 📦 Archive 处理 (Archive.pm)

### 核心依赖

| Perl 模块 | 用途 |
|-----------|------|
| `Archive::Libarchive` | ZIP/RAR/7z 格式 |
| `Archive::Libarchive::Peek` | 无需解压预览 |
| GhostScript (CLI) | PDF → JPG 转换 |

### 主要函数

| 函数 | 用途 |
|------|------|
| `get_filelist($archive, $id)` | 获取文件列表（自然排序） |
| `extract_file_from_archive($archive, $file)` | 解压单个文件到临时目录 |
| `extract_single_file_to_path($archive, $file, $dest)` | 解压到指定路径 |
| `is_file_in_archive($archive, $wanted)` | 检查文件是否存在于压缩包 |
| `extract_thumbnail($thumbdir, $id, $page, $setcover, $usehq)` | 生成缩略图 |

### 文件排序逻辑

```perl
# 自然排序：将数字补齐为 4 位
sub expand {
    my $file = shift;
    $file =~ s{(\d+)}{sprintf "%04d", $1}eg;
    return lc($file);
}

# 特殊排序：封面优先，制作人员信息在最后
@files = ( @cover_pages, @other_pages, @credit_pages );
```

### PDF 处理

使用 GhostScript CLI：
```bash
# 解压所有页面
gs -dNOPAUSE -sDEVICE=jpeg -r200 -o "$dest/%d.jpg" "$pdf"

# 解压指定页面
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

| 任务名称 | 用途 | 优先级 | 重试次数 |
|----------|------|--------|----------|
| `thumbnail_task` | 单个缩略图生成 | 0 | 3 |
| `page_thumbnails` | 批量页面缩略图 | 0 | 3 |
| `regen_all_thumbnails` | 全库缩略图重建 | - | - |
| `find_duplicates` | 查找重复存档 | - | - |
| `build_stat_hashes` | 构建统计索引 | 3 | - |
| `handle_upload` | 处理上传文件 | - | - |
| `download_url` | 下载外部 URL | - | - |
| `run_plugin` | 执行插件 | - | - |

### 并行处理 (MCE::Loop)

```perl
# Unix: 多进程并行
if ( IS_UNIX ) {
    mce_loop {
        $sub->(@{ $_ });
    } \@keys;
    MCE::Loop->finish;
} else {
    # Windows: 串行执行（libarchive 不支持线程）
    $sub->(@keys);
}
```

### 任务进度追踪

```perl
# 使用 Minion 的 note 功能追踪进度
$job->note( $i => "processed", total_pages => $pages );
```

### 重复检测算法

使用**汉明距离**比较缩略图哈希：

```perl
for ( my $i = 0; $i < length( $thumbhashes{$node} ); $i++ ) {
    $distance++ if substr( $hash1, $i, 1 ) ne substr( $hash2, $i, 1 );
    last if $distance > $threshold;  # 早期终止优化
}
```

---

## 🖼️ 图片缩放 (Resizer.pm)

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
| `resize_image` | `$data, $quality, $threshold` | 阅读器图片缩放 |

---

## 🏷️ Tags.pm - 标签处理工具

### 核心功能

标签规则系统支持多种规则类型：

| 规则类型 | 语法 | 示例 | 描述 |
|----------|------|------|------|
| `remove` | `-tag` 或 `tag` | `-yaoi` | 删除指定标签 |
| `remove_ns` | `-namespace:*` | `-misc:*` | 删除整个命名空间 |
| `strip_ns` | `~namespace` | `~language` | 保留标签但去除命名空间 |
| `replace` | `old -> new` | `serie:* -> parody:*` | 替换标签 |
| `replace_ns` | `ns1:* -> ns2:*` | `category:* -> genre:*` | 替换命名空间 |
| `hash_replace` | `old => new` | `foobar => correct_tag` | 高性能哈希替换（最后执行） |

### 标签规则语法

```
# 黑名单
-already uploaded
-forbidden content
ongoing

# 命名空间删除
-misc:*

# 命名空间替换
serie:* -> parody:*

# 命名空间剥离（仅保留值）
~language

# 大小写不敏感匹配，保留替换后的大小写
serie:one piece -> parody:One Piece

# 哈希替换（更快，在所有其他规则之后运行）
various => various artists
```

**转换示例：**
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

# 标签分割/合并
@tags = split_tags_to_array("tag1, tag2, tag3");
$str = join_tags_to_string(@tags);
```

---

## 🔧 Generic.pm - 通用工具函数

### 主要函数分类

| 函数 | 用途 |
|------|------|
| `is_image($file)` | 检查文件是否为图片 (png/jpg/jpeg/jfif/gif/bmp/webp/avif/heif/heic/jxl) |
| `is_archive($file)` | 检查文件是否为压缩包 (zip/rar/7z/tar/tar.gz/lzma/xz/cbz/cbr/cb7/cbt/pdf/epub/tar.zst/zst) |
| `render_api_response($mojo, $op, $err, $msg)` | 标准 API JSON 响应 |
| `get_tag_with_namespace($ns, $tags, $default)` | 按命名空间从标签字符串提取值 |
| `shasum_str($data, $algo)` | 计算 SHA 哈希（用于 E-H 反向搜索） |

### 进程管理

```perl
# 启动 Shinobu（文件监视进程）
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
# 交集或差集
@result = intersect_arrays(\@arr1, \@arr2, $is_neg);

# 按 CPU 数量分割工作负载
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

## ✅ 总结

| 组件 | Perl 依赖 | 用途 |
|------|-----------|------|
| Archive | Archive::Libarchive | ZIP/RAR/7z 解压 |
| PDF | GhostScript CLI | PDF 转图片 |
| Image | libvips / ImageMagick | 图片缩放 |
| Task Queue | Minion (Redis) | 后台任务处理 |
| Parallel | MCE::Loop | 多进程并行 |
