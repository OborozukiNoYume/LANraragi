# Phase 8-9: Testing and Build System Analysis

> Analysis Date: 2026-01-11

This document analyzes LANraragi's test architecture and build/deployment system.

---

## 📊 Testing Architecture Overview

### Test Directory Structure
```
tests/
├── mocks.pl                    # Redis Mock implementation
├── backup.t                    # Backup tests
├── modules.t                   # Module loading tests
├── opds.t                      # OPDS tests
├── plugins.t                   # Plugin system tests
├── search.t                    # Search tests
├── tankoubon.t                # Collection tests
├── LANraragi/
│   ├── Model/
│   │   └── Plugins.t
│   ├── Plugin/Metadata/       # Plugin unit tests (18)
│   │   ├── Chaika.t
│   │   ├── EHentai.t
│   │   └── ...
│   └── Utils/                  # Utility tests (8)
│       ├── Archive.t
│       ├── Tags.t
│       └── ...
└── samples/                    # Test data
    ├── chaika/
    ├── comicinfo/
    ├── eh/
    └── ...
```

---

## 🧪 Mock Implementation (`mocks.pl`)

### Redis Mock

Using `Test::MockObject` to mock Redis:

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

## 📦 Perl Dependencies (`cpanfile`)

### Core Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `perl` | 5.36.0 | Language version |
| `Redis` | 1.995 | Redis client |
| `Archive::Libarchive::*` | 0.03+ | Archive handling |
| `Mojolicious` | 9.39 | Web framework |

### Task Queue

| Package | Version | Purpose |
|---------|---------|---------|
| `Minion` | 10.31 | Task queue |
| `Minion::Backend::Redis` | 0.002 | Redis backend |

### Background Services

| Package | Version | Purpose |
|---------|---------|---------|
| `Proc::Simple` | 1.32 | Process management |
| `MCE::Loop` | 1.901 | Parallel processing |
| `File::ChangeNotify` | 0.31 | File change monitoring |

### I18N

| Package | Version | Purpose |
|---------|---------|---------|
| `Locale::Maketext` | 1.33 | Internationalization |
| `Locale::Maketext::Lexicon` | 1.00 | PO file support |

---

## 🐳 Docker Build

### Dockerfile Key Configuration

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

### Docker Environment Variables (Official)

| Variable | Default | Description |
|----------|---------|-------------|
| `LRR_UID` | 9001 | User ID for container |
| `LRR_GID` | 9001 | Group ID for container |
| `LRR_NETWORK` | `http://*:3000` | Mojo server bind address |
| `LRR_AUTOFIX_PERMISSIONS` | 1 | Auto-fix file permissions on start |
| `MOJO_PROXY` | 1 | Enable HTTP proxy detection |
| `MOJO_REVERSE_PROXY` | 1 | Enable X-Forwarded-For headers |
| `S6_KILL_GRACETIME` | 10000 | Wait 10s before SIGKILL |

### Build Optimizations

1. **Layer copying** - cpanfile before source code for Docker cache
2. **s6-overlay** - Process management, supports Redis + LRR dual process
3. **Health check** - Port 3000 check every minute

---

## ⚙️ Configuration File (`lrr.conf`)

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

| Key | Description |
|-----|-------------|
| `redis_address` | Redis server address |
| `redis_password` | Redis auth password |
| `redis_database` | Archive data (DB 0) |
| `redis_database_minion` | Minion jobs (DB 1) |
| `redis_database_config` | Config storage (DB 2) |
| `redis_database_search` | Search index (DB 3) |
| `base_url_path` | URL path prefix |

---

## 🔄 CI/CD Workflows (GitHub Actions)

| Workflow | Purpose |
|----------|---------|
| `push-continuous-integration.yml` | Run tests on push |
| `push-continous-delivery.yml` | Build nightly Docker images |
| `release-delivery.yml` | Build release Docker images & Windows zip |
| `push-brewtest.yml` | Test Homebrew formula |

---

## 📋 Go Refactoring Key Points

### Test Migration

| Perl | Go |
|------|-----|
| `Test::MockObject` | `testify/mock` |
| `Test::Deep` | `github.com/stretchr/testify/assert` |
| `.t` files | `_test.go` files |
| `prove` | `go test` |

### Dependency Mapping

| Perl Dependency | Go Alternative |
|-----------------|----------------|
| `Redis` | `github.com/redis/go-redis/v9` |
| `Archive::Libarchive` | `github.com/mholt/archiver/v4` |
| `Mojolicious` | `github.com/gin-gonic/gin` |
| `Minion` | `github.com/hibiken/asynq` |
| `File::ChangeNotify` | `github.com/fsnotify/fsnotify` |

### Docker Adaptation

```dockerfile
FROM golang:1.22-alpine AS builder
RUN go build -o lanraragi ./cmd/server

FROM alpine:3.20
COPY --from=builder /app/lanraragi /usr/local/bin/
EXPOSE 3000
VOLUME ["/data/content", "/data/thumb", "/data/database"]
```

---

## ✅ Analysis Completion Statistics

| Phase | Status | Document |
|-------|--------|----------|
| 1. Redis Schema | ✅ | phase1_redis_schema.md |
| 2. API Routing | ✅ | phase2_api_routing.md |
| 3. Infrastructure | ✅ | phase3_infrastructure.md |
| 4. Plugin System | ✅ | phase4_plugin_system.md |
| 5. Frontend | ✅ | phase5_frontend.md |
| 6. Model Deep | ✅ | phase6_model_deep.md |
| 7. Template/I18N | ✅ | phase7_template_i18n.md |
| 8. Tests/Build | ✅ | phase8_9_tests_build.md |
