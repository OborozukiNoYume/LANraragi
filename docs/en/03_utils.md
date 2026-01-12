# Infrastructure and Utilities

> **Analyzed Files**: `Archive.pm`, `Minion.pm`, `Resizer.pm`, `Tags.pm`, `Generic.pm`

---

## 📦 Archive Handling (Archive.pm)

### Core Dependencies

| Perl Module | Purpose |
|-------------|---------|
| `Archive::Libarchive` | ZIP/RAR/7z formats |
| `Archive::Libarchive::Peek` | Peek without extraction |
| GhostScript (CLI) | PDF → JPG conversion |

### Main Functions

| Function | Purpose |
|----------|---------|
| `get_filelist($archive, $id)` | Get file list (natural sorted) |
| `extract_file_from_archive($archive, $file)` | Extract single file to temp |
| `extract_single_file_to_path($archive, $file, $dest)` | Extract to specific path |
| `is_file_in_archive($archive, $wanted)` | Check if file exists in archive |
| `extract_thumbnail($thumbdir, $id, $page, $setcover, $usehq)` | Generate thumbnail |

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

### PDF Handling

Using GhostScript CLI:
```bash
# Extract all pages
gs -dNOPAUSE -sDEVICE=jpeg -r200 -o "$dest/%d.jpg" "$pdf"

# Extract specific page
gs -dNOPAUSE -dFirstPage=$page -dLastPage=$page -sDEVICE=jpeg -r200 -o "$out" "$pdf"
```

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

---

## 🏷️ Tags.pm - Tag Processing Utilities

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

### Tag Rules Syntax

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

---

## 🔧 Generic.pm - General Utility Functions

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

## ✅ Summary

| Component | Perl Dependency | Purpose |
|-----------|-----------------|---------|
| Archive | Archive::Libarchive | ZIP/RAR/7z extraction |
| PDF | GhostScript CLI | PDF to image conversion |
| Image | libvips / ImageMagick | Image resizing |
| Task Queue | Minion (Redis) | Background job processing |
| Parallel | MCE::Loop | Multi-process parallelism |
