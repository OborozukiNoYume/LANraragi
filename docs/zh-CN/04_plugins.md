# 插件系统架构

> **分析文件**: `Utils/Plugins.pm`, `Model/Plugins.pm`, `Plugin/Metadata/EHentai.pm`

---

## 🔌 插件系统概览

### 插件发现机制

使用 `Module::Pluggable` 自动发现插件：
```perl
use Module::Pluggable require => 1, search_path => ['LANraragi::Plugin'];
```

---

## 📋 插件类型定义

| 类型 | 必需方法 | 用途 | 数量 |
|------|----------|------|------|
| `metadata` | `get_tags` | 获取档案元数据 | 22 |
| `login` | `do_login` | 网站认证 | 4 |
| `download` | `provide_url` | 下载外部资源 | 3 |
| `script` | `run_script` | 通用脚本执行 | 3 |

---

## 📝 plugin_info 契约

每个插件必须实现 `plugin_info()` 返回元数据：

```perl
sub plugin_info {
    return (
        name        => "E-Hentai",           # Display name
        type        => "metadata",           # Plugin type
        namespace   => "ehplugin",           # Unique identifier
        author      => "Difegue",            # Author
        version     => "2.6",                # Version number
        description => "Searches...",        # HTML description
        icon        => "data:image/png;...", # Base64 icon
        
        # Optional fields
        login_from  => "ehlogin",            # Dependent login plugin
        cooldown    => 4,                    # Cooldown time (seconds)
        url_regex   => "e-hentai\\.org",     # Download plugin URL match
        oneshot_arg => "E-H Gallery URL",    # One-shot execution param description
        
        # Parameter definitions (array or Hash)
        parameters  => [
            { type => "string", desc => "Language" },
            { type => "bool",   desc => "Use thumbnails" },
        ],
    );
}
```

---

## 🔧 插件执行流程

### 登录插件

必需方法：`do_login`

| 输入 | 描述 |
|------|------|
| `$params` | 用户定义的插件参数 |

| 输出 | 描述 |
|------|------|
| `Mojo::UserAgent` | 配置好的 UA 对象（含 Cookie） |

```perl
sub do_login {
    shift;
    my ($params) = @_;
    my $ua = Mojo::UserAgent->new;
    $ua->cookie_jar->add(...);  # Add login cookies
    return $ua;
}
```

### 下载插件

必需方法：`provide_url`
必需元数据：`url_regex`

| 输入 (`$lrr_info`) | 描述 |
|--------------------|------|
| `url` | 待下载的 URL |
| `user_agent` | 预配置的 Mojo::UserAgent |
| `tempdir` | 本地文件组装的临时目录 |

| 输出 | 描述 |
|------|------|
| `download_url => "..."` | 直接下载 URL |
| `file_path => "..."` | 本地文件路径（已下载） |

```perl
sub provide_url {
    shift;
    my $lrr_info = shift;
    my $url = $lrr_info->{url};
    # ... process URL ...
    return ( download_url => "https://direct.link/file.zip" );
    # OR
    return ( file_path => "/path/to/local/file.zip" );
}
```

### 脚本插件

必需方法：`run_script`

| 输入 (`$lrr_info`) | 描述 |
|--------------------|------|
| `oneshot_param` | 用户提供的运行时参数 |
| `user_agent` | 预配置的 Mojo::UserAgent |

| 输出 | 描述 |
|------|------|
| 任意哈希 | 直接返回给调用者 |
| `error => "..."` | 错误消息 |

```perl
sub run_script {
    shift;
    my ($lrr_info, $params) = @_;
    # ... perform operations ...
    return ( total => $count, ids => \@list );
}
```

### 元数据插件

```mermaid
sequenceDiagram
    participant API as Controller
    participant Exec as Model::Plugins
    participant Login as LoginPlugin
    participant Meta as MetadataPlugin
    participant DB as Redis
    
    API->>Exec: exec_metadata_plugin(plugin, id, args)
    Exec->>DB: Get archive info (title, tags, thumbhash)
    
    alt Login required
        Exec->>Login: do_login(args)
        Login-->>Exec: Mojo::UserAgent (with Cookie)
    end
    
    Exec->>Meta: get_tags(info_hash, args)
    Meta-->>Exec: {tags, title?, summary?}
    
    Exec->>Exec: Apply tag rules
    Exec->>Exec: Filter duplicate tags
    Exec-->>API: {new_tags, title?, summary?}
```

### $lrr_info 字段

| 字段 | 描述 |
|------|------|
| `archive_id` | 档案的内部 ID（40 字符 SHA1） |
| `archive_title` | 用户输入的档案标题 |
| `existing_tags` | LRR 中该档案已有的标签 |
| `thumbnail_hash` | 档案首页图像的 SHA-1 哈希 |
| `file_path` | 档案的文件系统路径 |
| `oneshot_param` | 用户设置的一次性参数值 |
| `user_agent` | 用于网络请求的 Mojo::UserAgent 对象（如依赖登录插件则预配置了 Cookie） |

---

## 💾 插件配置存储

### Redis 键格式

```
LRR_PLUGIN_{NAMESPACE}  (Hash)
├── enabled: "1" | "0"
├── param1: "value1"
├── param2: "value2"
└── customargs: "[...]"  (legacy format, JSON array)
```

### 参数迁移（旧 → 新）

```perl
# Old format: positional params (JSON array)
customargs => '["value1", "value2"]'

# New format: named params (Hash fields)
param_name => "value"
```

### to_named_params 字段 (v0.9.3+)

将插件从位置参数转换为命名参数时，添加 `to_named_params` 以保留现有用户配置：

```perl
# Add to plugin_info to convert old config automatically
to_named_params => ['doomsday', 'iterations'],  # Old param order
parameters => {
    'iterations' => {type => "int",  desc => "Number of iterations"},
    'doomsday'   => {type => "bool", desc => "Enable DOOMSDAY"},
    'salvation'  => {type => "bool", desc => "New param (not in migration)"}
}
```

> **注意**：`to_named_params` 仅在转换后首次加载时需要，后续版本可移除。

---

## 🧪 EHentai 插件分析（代表性示例）

### 插件功能

1. **source 标签优先**：优先使用已存在的 `source:e-hentai.org/g/...`
2. **缩略图反向搜索**：使用 SHA-1 哈希搜索
3. **gID 标题搜索**：从标题提取 `[1234567]`
4. **标题文本搜索**：回退方案

### 搜索策略

```perl
# Priority: oneshot_param > source tag > thumbnail search > gID search > title search
if ( $lrr_info->{oneshot_param} =~ /g\/(\d+)\/([0-z]+)/ ) { ... }
elsif ( $lrr_info->{existing_tags} =~ /source:.*e-hentai.org\/g\/(\d+)\/([0-z]+)/ ) { ... }
else { lookup_gallery(...) }
```

### 速率限制

```perl
cooldown => 4  # 4 second cooldown

# Detect EH rate limit warning
if ( index( $dom->to_string, "You are opening" ) != -1 ) {
    my $rand = 15 + int( rand( 51 - 15 ) );  # 15-50 second random wait
    sleep($rand);
}
```

---

## 📝 插件代码示例

### 日志记录
```perl
use LANraragi::Utils::Logging qw(get_plugin_logger);
my $logger = get_plugin_logger();

$logger->debug("Only shows in Debug Mode");
$logger->info("Normal log");
$logger->warn("Warning");
$logger->error("Error");
```

### HTTP 请求
```perl
my $ua = $lrr_info->{user_agent};

# GET request
$ua->get("http://example.com")->result->body;

# POST JSON request
my $rep = $ua->post(
    "https://api.example.com" => json => { key => "value" }
)->result;
my $json = $rep->json;  # Decoded hash
```

### 读取 Redis 值
```perl
my $redis = LANraragi::Model::Config->get_redis;
my $value = $redis->get("key");
```

### 从归档中提取文件
```perl
use LANraragi::Utils::Archive qw(is_file_in_archive extract_file_from_archive);

my $info_path = is_file_in_archive($file, "info.json");
if ($info_path) {
    my $filepath = extract_file_from_archive($file, $info_path);
    # Use extracted file...
    unlink $filepath;  # Delete when done
}
```

---

## ✅ 总结

| 发现 | 详情 |
|------|------|
| **插件发现** | Module::Pluggable 自动扫描 |
| **4 种类型** | metadata, login, download, script |
| **配置存储** | Redis Hash (`LRR_PLUGIN_{NS}`) |
| **登录依赖** | `login_from` 字段指定 |
| **速率限制** | `cooldown` 字段 + 动态等待 |
| **参数迁移** | 位置参数 → 命名参数 |
