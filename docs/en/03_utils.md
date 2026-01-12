# Phase 3: Infrastructure and Utilities Analysis

> **Analyzed Files**: `Archive.pm`, `Minion.pm`, `Resizer.pm`  
> **Analysis Date**: 2026-01-11

---

## 📦 Archive Handling (Archive.pm)

### Core Dependencies

| Perl Module | Purpose | Go Alternative |
|-------------|---------|----------------|
| `Archive::Libarchive` | ZIP/RAR/7z formats | `mholt/archiver` or `libarchive` CGO |
| `Archive::Libarchive::Peek` | Peek without extraction | `archive/zip` + streaming |
| GhostScript (CLI) | PDF → JPG conversion | `pdfcpu` / `mupdf` CGO |

### Main Functions

```go
// Go Interface Proposal
type ArchiveHandler interface {
    // Get file list (natural sorted)
    GetFileList(archivePath string, id string) ([]string, error)
    
    // Extract single file to memory
    ExtractSingleFile(archivePath, filePath string) ([]byte, error)
    
    // Extract single file to disk
    ExtractSingleFileToPath(archivePath, filePath, dest string) (string, error)
    
    // Check if file exists in archive
    IsFileInArchive(archivePath, wantedName string) (string, bool)
    
    // Generate thumbnail
    ExtractThumbnail(thumbDir, id string, page int, setCover, useHQ bool) (string, error)
}
```

### File Sorting Logic

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

**Go Implementation:**
```go
import "github.com/facette/natsort"

func SortArchiveFiles(files []string) []string {
    // 1. Natural sort
    natsort.Sort(files)
    
    // 2. Extract cover/credit
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

### PDF Handling

Using GhostScript CLI:
```bash
# Extract all pages
gs -dNOPAUSE -sDEVICE=jpeg -r200 -o "$dest/%d.jpg" "$pdf"

# Extract specific page
gs -dNOPAUSE -dFirstPage=$page -dLastPage=$page -sDEVICE=jpeg -r200 -o "$out" "$pdf"
```

**Go Alternatives:**
- `github.com/pdfcpu/pdfcpu` - Pure Go PDF library
- `github.com/nicferrier/gomupdf` - MuPDF CGO binding

### Apple Resource Fork Filtering

Automatically filters macOS resource fork files:
- `__MACOSX/` directory
- `._*` prefixed files
- AppleDouble/AppleSingle magic number detection

---

## ⚙️ Task Queue (Minion.pm)

### Job Type Definitions

| Job Name | Purpose | Priority | Retry |
|----------|---------|----------|-------|
| `thumbnail_task` | Single thumbnail generation | 0 | 3 |
| `page_thumbnails` | Batch page thumbnails | 0 | 3 |
| `regen_all_thumbnails` | Full library thumbnail rebuild | - | - |
| `find_duplicates` | Find duplicate archives | - | - |
| `build_stat_hashes` | Build statistics index | 3 | - |
| `handle_upload` | Process uploaded file | - | - |
| `download_url` | Download external URL | - | - |
| `run_plugin` | Execute plugin | - | - |

### Parallel Processing (MCE::Loop)

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

**Go Implementation:**
```go
// Using worker pool pattern
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

### Job Progress Tracking

```perl
# Use Minion's note feature for progress tracking
$job->note( $i => "processed", total_pages => $pages );
```

### Duplicate Detection Algorithm

Using **Hamming distance** to compare thumbnail hashes:

```perl
for ( my $i = 0; $i < length( $thumbhashes{$node} ); $i++ ) {
    $distance++ if substr( $hash1, $i, 1 ) ne substr( $hash2, $i, 1 );
    last if $distance > $threshold;  # Early termination optimization
}
```

**Go Implementation:**
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

## 🖼️ Image Resizing (Resizer.pm)

### Factory Pattern

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

### Interface Definition

| Method | Parameters | Purpose |
|--------|------------|---------|
| `resize_thumbnail` | `$data, $quality, $use_hq, $format` | Generate thumbnail |
| `resize_image` | `$data, $quality, $threshold` | Reader image resize |

### Go Alternatives

| Perl Library | Go Alternative | Notes |
|--------------|----------------|-------|
| Image::Magick | `disintegration/imaging` | Pure Go, fewer features |
| libvips (FFI) | `davidbyttow/govips` | CGO, high performance |

**Go Interface Design:**
```go
type ImageResizer interface {
    // Generate thumbnail (500px height)
    ResizeThumbnail(data []byte, quality int, hq bool, format string) ([]byte, error)
    
    // Reader image resize
    ResizeImage(data []byte, quality int, threshold int) ([]byte, error)
}

// Factory function
func NewResizer() ImageResizer {
    if govips.IsAvailable() {
        return &VipsResizer{}
    }
    return &ImagingResizer{}  // Pure Go fallback
}
```

---

## 🔄 Go Task Queue Design

### Recommended Library: `hibiken/asynq`

```go
package worker

import (
    "github.com/hibiken/asynq"
)

// Task types
const (
    TypeThumbnail      = "thumbnail:generate"
    TypePageThumbnails = "thumbnail:pages"
    TypeUpload         = "upload:handle"
    TypeDownload       = "download:url"
    TypePlugin         = "plugin:run"
    TypeStats          = "stats:build"
    TypeDuplicates     = "duplicates:find"
)

// Thumbnail task
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

## 🏷️ Tags.pm - Tag Processing Utilities (4KB)

### Core Features

Tag rule system supporting multiple rule types:

| Rule Type | Syntax | Example | Description |
|-----------|--------|---------|-------------|
| `remove` | `-tag` or `tag` | `-yaoi` | Remove specified tag |
| `remove_ns` | `-namespace:*` | `-misc:*` | Remove entire namespace |
| `strip_ns` | `~namespace` | `~language` | Keep tag but strip namespace |
| `replace` | `old -> new` | `serie:* -> parody:*` | Replace tag |
| `replace_ns` | `ns1:* -> ns2:*` | `category:* -> genre:*` | Replace namespace |
| `hash_replace` | `old => new` | `foobar => correct_tag` | High-performance hash replace (runs last) |

### Tag Rules Syntax (Official)

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

**Example transformation:**
```
Input:  already uploaded, misc:ongoing, language:english, serie:one piece, various
Output: english, parody:One Piece, various artists
```

### Key Functions

```perl
# Rule parsing
@rules = tags_rules_to_array($text_rules);

# Tag rewriting
@new_tags = rewrite_tags(\@tags, \@rules, \%hash_replace);

# Tag split/join
@tags = split_tags_to_array("tag1, tag2, tag3");
$str = join_tags_to_string(@tags);
```

### Go Implementation Suggestion

```go
type TagRule struct {
    Type  string // remove, remove_ns, strip_ns, replace, replace_ns
    Match string
    Value string
}

func RewriteTags(tags []string, rules []TagRule, hashReplace map[string]string) []string {
    // Iterate and apply rules
}
```

---

## 🔧 Generic.pm - General Utility Functions (11KB)

### Main Function Categories

| Function | Purpose |
|----------|---------|
| `is_image($file)` | Check if file is image (png/jpg/jpeg/jfif/gif/bmp/webp/avif/heif/heic/jxl) |
| `is_archive($file)` | Check if file is archive (zip/rar/7z/tar/tar.gz/lzma/xz/cbz/cbr/cb7/cbt/pdf/epub/tar.zst/zst) |
| `render_api_response($mojo, $op, $err, $msg)` | Standard API JSON response |
| `get_tag_with_namespace($ns, $tags, $default)` | Extract value from tag string by namespace |
| `shasum_str($data, $algo)` | Calculate SHA hash (for E-H reverse search) |

### Process Management

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

### Array/Set Utilities

```perl
# Intersection or difference
@result = intersect_arrays(\@arr1, \@arr2, $is_neg);

# Split workload by CPU count
@sections = split_workload_by_cpu($numCpus, @workload);

# Flatten nested array
@flat = flat(@nested);
```

### Redis Lock Mechanism

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

## ✅ Phase 3 Analysis Summary

| Component | Perl Dependency | Go Alternative | Complexity |
|-----------|-----------------|----------------|------------|
| Archive | Archive::Libarchive | `mholt/archiver` / CGO | ⭐⭐⭐ |
| PDF | GhostScript CLI | `pdfcpu` / MuPDF | ⭐⭐⭐⭐ |
| Image | libvips / ImageMagick | `govips` / `imaging` | ⭐⭐ |
| Task Queue | Minion (Redis) | `hibiken/asynq` | ⭐⭐⭐ |
| Parallel | MCE::Loop | `sync.WaitGroup` + worker pool | ⭐⭐ |

### Key Migration Points

1. **PDF Processing**: Consider using `pdfcpu` instead of GhostScript to reduce external dependencies
2. **Image Processing**: Prefer `govips` (performance), fallback to `imaging` (compatibility)
3. **Task Queue**: `asynq` integrates natively with Redis, supports priority and retry
4. **Parallel Safety**: Note Windows libarchive threading issues
