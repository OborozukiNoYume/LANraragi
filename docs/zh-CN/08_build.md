# 测试和构建系统

> 分析日期: 2026-01-11

本文档分析 LANraragi 的测试架构和构建/部署系统。

---

## 📊 测试架构概述

### 测试目录结构
```
tests/
├── mocks.pl                    # Redis Mock 实现
├── backup.t                    # 备份测试
├── modules.t                   # 模块加载测试
├── opds.t                      # OPDS 测试
├── plugins.t                   # 插件系统测试
├── search.t                    # 搜索测试
├── tankoubon.t                # 合集测试
├── LANraragi/
│   ├── Model/
│   │   └── Plugins.t
│   ├── Plugin/Metadata/       # 插件单元测试 (18)
│   │   ├── Chaika.t
│   │   ├── EHentai.t
│   │   └── ...
│   └── Utils/                  # 工具类测试 (8)
│       ├── Archive.t
│       ├── Tags.t
│       └── ...
└── samples/                    # 测试数据
    ├── chaika/
    ├── comicinfo/
    ├── eh/
    └── ...
```

---

## 🧪 Mock 实现 (`mocks.pl`)

### Redis Mock

使用 `Test::MockObject` 模拟 Redis：

```perl
my %datamodel = (
    "LRR_CONFIG" => { "pagesize" => "100", "devmode" => "1" },
    "SET_1589141306" => {
        "archives" => '["e69e43e1...","e69e43e1..."]',
        "name" => "Segata Sanshiro",
        "search" => ""
    },
    "e69e43e1355267f7d32a4f9b7f2fe108d2401ebf" => {
        "isnew" => "false",
        "pagecount" => 2,
        "tags" => "character:segata sanshiro, male:very cool",
        "title" => "Saturn Backup Cartridge - Japanese Manual"
    }
);

my $redis = Test::MockObject->new();
$redis->mock('keys', sub { grep { /$expr/ } keys %datamodel });
$redis->mock('hget', sub { $datamodel{$_[1]}{$_[2]} });
$redis->mock('hgetall', sub { %{$datamodel{$_[1]}} });
# ...
$redis->fake_module("Redis", new => sub { $redis });
```

### Logger Mock

```perl
sub get_logger_mock {
    my $mock = Test::MockObject->new();
    $mock->mock('error', sub { ... });
    $mock->mock('info', sub { ... });
    $mock->mock('debug', sub { ... });
    return $mock;
}
```

---

## 📦 Perl 依赖 (`cpanfile`)

### 核心依赖

| 包 | 版本 | 用途 |
|----|------|------|
| `perl` | 5.36.0 | 语言版本 |
| `Redis` | 1.995 | Redis 客户端 |
| `Archive::Libarchive::*` | 0.03+ | 压缩包处理 |
| `Mojolicious` | 9.39 | Web 框架 |

### 任务队列

| 包 | 版本 | 用途 |
|----|------|------|
| `Minion` | 10.31 | 任务队列 |
| `Minion::Backend::Redis` | 0.002 | Redis 后端 |

### 后台服务

| 包 | 版本 | 用途 |
|----|------|------|
| `Proc::Simple` | 1.32 | 进程管理 |
| `MCE::Loop` | 1.901 | 并行处理 |
| `File::ChangeNotify` | 0.31 | 文件变更监控 |

### I18N

| 包 | 版本 | 用途 |
|----|------|------|
| `Locale::Maketext` | 1.33 | 国际化 |
| `Locale::Maketext::Lexicon` | 1.00 | PO 文件支持 |

---

## 🐳 Docker 构建

### Dockerfile 关键配置

```dockerfile
FROM alpine:3.20
EXPOSE 3000
ENTRYPOINT ["//init"]  # s6-overlay

ENV LRR_UID=9001 LRR_GID=9001
ENV LRR_NETWORK=http://*:3000
ENV MOJO_PROXY=1
ENV MOJO_REVERSE_PROXY=1
ENV LRR_AUTOFIX_PERMISSIONS=1

VOLUME [ "/home/koyomi/lanraragi/content" ]
VOLUME [ "/home/koyomi/lanraragi/thumb" ]
VOLUME [ "/home/koyomi/lanraragi/database" ]
VOLUME [ "/home/koyomi/lanraragi/lib/LANraragi/Plugin/Sideloaded" ]
```

### Docker 环境变量

| 变量 | 默认值 | 描述 |
|------|--------|------|
| `LRR_UID` | 9001 | 容器用户 ID |
| `LRR_GID` | 9001 | 容器组 ID |
| `LRR_NETWORK` | `http://*:3000` | Mojo 服务器绑定地址 |
| `LRR_AUTOFIX_PERMISSIONS` | 1 | 启动时自动修复文件权限 |
| `MOJO_PROXY` | 1 | 启用 HTTP 代理检测 |
| `MOJO_REVERSE_PROXY` | 1 | 启用 X-Forwarded-For 头 |
| `S6_KILL_GRACETIME` | 10000 | SIGKILL 前等待 10 秒 |

### 构建优化

1. **层复制** - cpanfile 在源代码之前用于 Docker 缓存
2. **s6-overlay** - 进程管理，支持 Redis + LRR 双进程
3. **健康检查** - 每分钟检查端口 3000

---

## ⚙️ 配置文件 (`lrr.conf`)

```perl
{
  redis_address => "127.0.0.1:6379",
  redis_password => "",
  redis_database => "0",
  redis_database_minion => "1",
  redis_database_config => "2",
  redis_database_search => "3",
  base_url_path => "",
}
```

| 键 | 描述 |
|----|------|
| `redis_address` | Redis 服务器地址 |
| `redis_password` | Redis 认证密码 |
| `redis_database` | 存档数据 (DB 0) |
| `redis_database_minion` | Minion 任务 (DB 1) |
| `redis_database_config` | 配置存储 (DB 2) |
| `redis_database_search` | 搜索索引 (DB 3) |
| `base_url_path` | URL 路径前缀 |

---

## 🔄 CI/CD 工作流 (GitHub Actions)

| 工作流 | 用途 |
|--------|------|
| `push-continuous-integration.yml` | 推送时运行测试 |
| `push-continous-delivery.yml` | 构建 nightly Docker 镜像 |
| `release-delivery.yml` | 构建发布版 Docker 镜像和 Windows zip |
| `push-brewtest.yml` | 测试 Homebrew 配方 |

---

## ✅ 总结

### 测试框架

| 组件 | 工具 |
|------|------|
| 测试框架 | Perl `Test::More` |
| Mock | `Test::MockObject` |
| 深度比较 | `Test::Deep` |
| 测试运行器 | `prove` |

### 构建系统

| 平台 | 方法 |
|------|------|
| Docker | 基于 Alpine，s6-overlay |
| macOS | Homebrew 配方 |
| Windows | PowerShell 安装程序 |
| 源码 | 手动 Perl 依赖安装 |

### 关键文件

| 文件 | 用途 |
|------|------|
| `tools/cpanfile` | Perl 依赖 |
| `tools/build/docker/Dockerfile` | Docker 构建 |
| `tools/build/homebrew/Lanraragi.rb` | Homebrew 配方 |
| `tools/build/windows/build-installer.ps1` | Windows 安装程序 |
| `lrr.conf` | 运行时配置 |
