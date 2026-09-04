# 构建、测试与部署

> 基准 commit `2094cc1d`（2026-09-04）。事实已对照代码核实——生成时已逐条核查引用。

## 前置条件

- **Perl >= 5.36** 和一套 C 工具链（许多 CPAN 模块需要编译）。
- **Node.js / npm** —— 既用于下文的构建脚本，也用于前端库的 vendoring。
- 一个兼容 Redis 的服务器（容器内置 Valkey；本地开发可使用 Redis 或 Valkey）。

## 依赖

### Perl（`tools/cpanfile`）

`tools/cpanfile` 中固定的关键依赖：

| 依赖 | 版本 | 用途 |
|---|---|---|
| `perl` | 5.36.0 | 语言版本下限 |
| `Mojolicious` | 9.39 | Web 框架 |
| `Redis` | 1.995 | Redis 客户端 |
| `Minion` | >= 10.31, < 12.0 | 任务队列 |
| `Minion::Backend::Redis` | 0.002 | Minion 后端 |
| `Mojolicious::Plugin::OpenAPI` | 5.11 | REST API（含 `JSON::Validator` 5.19） |
| `Archive::Libarchive::Extract` / `Peek` | 0.03 / 0.04 | 压缩包处理 |
| `Archive::Zip` | 1.68 | zip 处理 |
| `Locale::Maketext` / `::Lexicon` | 1.33 / 1.00 | i18n（见 i18n 文档） |
| `CHI` + `CHI::Driver::FastMmap` | 0.61 | 缓存 |
| `FFI::Platypus` | 2.10 | libvips 绑定 |
| `Proc::Simple`, `Parallel::Loops`, `MCE::Loop`, `File::ChangeNotify` | — | Shinobu 后台工作进程 |
| `Module::Pluggable` | 5.2 | 插件系统 |
| `Crypt::Passphrase` + `::Bcrypt` | 0.023 / 0.009 | 密码哈希 |

仅测试使用的依赖包括 `Test::MockObject`、`Test::MockModule`、`Test::Trap`、`Test::Deep`、`App::Prove` 和 `Test::Harness`。

### npm（`package.json`）

`package.json`（版本 0.9.81 "Atomica"）包含前端运行时库（jQuery、DataTables、Preact + signals、SweetAlert2、Swiper、marked、DOMPurify、es-module-shims 等）和开发工具（`eslint`、`@redocly/cli`、`esbuild`、`@stylistic/eslint-plugin`）。

### 关键构建文件

| 文件 | 作用 |
|---|---|
| `tools/cpanfile` | Perl 依赖清单 |
| `package.json` / `package-lock.json` | npm 脚本与前端依赖 |
| `tools/install.pl` | 依赖安装器 + 前端库 vendoring |
| `lrr.conf` | Redis 连接/布局配置 |
| `tools/build/docker/Dockerfile` | 发布容器（多阶段，s6） |
| `tools/build/docker/Dockerfile-dev`, `docker-compose.yml` | 容器化开发环境 |
| `tools/openapi.yaml` + `redocly.yml` | REST API 规范及其 lint 配置 |
| `tools/build/windows/` | MSYS2/WiX MSI 流水线和 `Karen` 安装器项目 |
| `tools/build/homebrew/Lanraragi.rb` | macOS Homebrew formula |
| `.github/workflows/`, `.github/actions/`, `.github/action-run-tests/` | CI/CD 流水线及复合/测试 action |
| `.devcontainer/` | VS Code 开发容器 |
| `tools/lanraragi-systemd.service` | systemd unit 示例 |

## 常用命令

均通过 `npm run <script>` 调用；定义位于 `package.json`：

| 脚本 | 作用 |
|---|---|
| `test` | `prove -r -l -v tests/` —— 完整 Perl 测试套件 |
| `lanraragi-installer` | `perl ./tools/install.pl` —— 依赖安装器（模式见下文） |
| `start` | `perl ./script/launcher.pl -f ./script/lanraragi` —— 生产启动 |
| `dev-server` | `perl ./script/launcher.pl -m -v ./script/lanraragi` —— 开发启动 |
| `dev-server-verbose` | 同上，但导出了 `LRR_DEVSERVER=1` |
| `kill-workers` | 杀掉 Shinobu/Minion 工作进程以及任何游离的 `script/lanraragi` |
| `lint` | `eslint public/` |
| `lint-openapi` | `redocly lint tools/openapi.yaml --config=redocly.yml` |
| `critic` | `perlcritic ./lib/* ./script/* ./tools/install.pl` |
| `tidy` | 对所有 `.pl`/`.pm` 文件运行 `perltidy` |
| `docs` | `python3 docs/generate_docs.py` |
| `docker-build` | `docker build -t difegue/lanraragi -f ./tools/build/docker/Dockerfile .` |
| `backup-db` | `perl ./script/backup` |
| `get-version` | `perl ./script/get_version` |

`redocly.yml` 继承 `recommended` 规则集并禁用 `operation-4xx-response`；`eslint.config.mjs` 负责 JS lint 配置。

npm 之外还有两个实用脚本：`script/get_version` 打印 `package.json` 中的版本对（形如 `0.9.81 - 'Atomica'`），`script/backup` 通过 `LANraragi::Model::Backup` 导出数据库备份 JSON（两者都被上面的 npm 脚本包装）。

## 安装依赖

`tools/install.pl`（通过 `npm run lanraragi-installer [mode]` 调用）支持三种模式：

- `install-front` —— 执行 `npm ci`，并把 `node_modules` 中的前端资源 vendor 到 `public/js/vendor/`、`public/css/vendor/` 和 `public/css/webfonts`（文件清单就在 `tools/install.pl` 内部，`esbuild` 只打包一个 ESM 包：swiper）。
- `install-back` —— 通过 `cpanm` 安装 `tools/cpanfile` 中的 Perl 依赖。
- `install-full` —— 两者兼有；源码安装使用此模式。

Docker 构建路径使用 `tools/build/docker/install-perl-deps.sh`，它会引导 `local::lib` + `cpanm`，手动预装 `Net::IDN::Encode`，然后对 `tools/cpanfile` 运行 `cpanm --installdeps`，再执行 `install-back`。

## 运行时配置：`lrr.conf`

仓库根目录下的 `lrr.conf` 由 `lib/LANraragi/Model/Config.pm` 读取，包含 8 个键：

| 键 | 含义 |
|---|---|
| `redis_address` | Redis 主机:端口（或 UNIX 套接字路径） |
| `redis_password` | 可选的认证 |
| `redis_database` | 档案数据 + 标签索引（默认 `0`） |
| `redis_database_minion` | Minion 任务队列（默认 `1`） |
| `redis_database_config` | 配置哈希（默认 `2`） |
| `redis_database_search` | 搜索索引/缓存（默认 `3`） |
| `redis_database_metrics` | 指标数据（默认 `4`） |
| `base_url_path` | 路径前缀部署 |

`lib/LANraragi/Model/Config.pm` 在启动时还支持环境变量覆盖：`LRR_REDIS_ADDRESS`（替换 `redis_address`）、`LRR_DATA_DIRECTORY` 和 `LRR_THUMB_DIRECTORY`（内容/缩略图路径）、`LRR_FORCE_DEBUG`、`LRR_DEVSERVER`（调试模式）以及 `LRR_DISABLE_OPENAPI`（跳过 OpenAPI 规范的服务）。

## 服务器启动

`npm start` 会进入 `script/launcher.pl`，由它挑选服务器：`-m` 运行 `Mojo::Server::Morbo`
（并设置 `MOJO_MODE=development`），`-d` 运行 `Mojo::Server::Daemon`，默认则是
`Mojo::Server::Prefork`——监听 `LRR_NETWORK`（默认 `http://*:3000`），把 PID 文件写到
`<LRR_TEMP_DIRECTORY>/server.pid`（否则为 `./temp/server.pid`），且除非传入 `-f` 否则守护
进程化。启动器会在对应环境变量存在时创建内容/缩略图/临时目录，然后直接加载应用类
（`script/lanraragi` 本身只是 `Mojolicious::Commands->start_app('LANraragi')`）。

`LANraragi::startup()` 随后按顺序执行：加载或生成会话密钥（`temp/oshino` 与主机名拼接），
注册 `RenderFile`/`TemplateToolkit` 插件（tt2 为默认处理器）与各 `LRR_*` 助手，用 `ping`
检查 Redis（不可达时输出掀桌消息并 die），随后进入针对瞬时 `LOADING` 错误、每 2 秒一次的
无限重试循环，初始化 PageCache 与 i18n，把遗留的 `LRR_*` 键迁移进配置数据库，依 `devmode`
切换到开发模式，把 Mojo 自身的日志重定向到轮转的 `mojo` 日志，运行 `scan_plugins()` 并刷新
每个注册表，清除重启待定标志，接线 Minion 客户端（`missing_after(5)`），注册十二个任务，
入队 `build_stat_hashes`，并启动 Minion worker 与 Shinobu 子进程。`first_install_actions()`
最后运行，其后再安装 `before_dispatch` 钩子（基础 URL 前缀 + `lrr_baseurl` cookie，外加
惰性安装的 SIGINT 处理器）与可选的指标钩子；`apply_routes()` 为启动收尾。关停处理仅针对
SIGINT——处理器在首个请求到来时才安装，因此任何页面加载之前的信号不会被捕获——它会先经
PID 文件杀死 Shinobu/Minion 子进程，再调用默认处理器。

## Docker

`npm run docker-build` 构建 `tools/build/docker/Dockerfile` —— 一个基于 `FROM alpine:3.24` 的三阶段构建（`base` → `build` → `runtime`）。Alpine 软件包包括 `valkey`/`valkey-cli`（容器内数据存储）、`s6-overlay`（init + 进程监护）、带 jxl/heif/poppler 扩展的 `vips`（缩略图）、`perl`、`perl-io-socket-ssl`、`perl-local-lib` 和 `tzdata`。`build` 阶段编译 CPAN 依赖并 vendor npm 资源；只有结果会被复制进 `runtime`。

**进程模型** —— 容器在 s6 之下运行两个进程：

- `redis`：`valkey-server /home/koyomi/lanraragi/tools/build/docker/redis.conf`（`tools/build/docker/s6/s6-rc.d/redis/run`）
- `lanraragi`：`perl script/launcher.pl -f script/lanraragi`（`tools/build/docker/s6/s6-rc.d/lanraragi/run`）

两者都通过 `s6-setuidgid` 以用户 `koyomi` 运行。`ENTRYPOINT ["//init"]`（双斜杠是 Alpine s6-overlay 软件包的约定）。启动时，`tools/build/docker/s6/cont-init.d/01-lrr-setup` 会把 `koyomi` 用户改写为 `LRR_UID`/`LRR_GID`，验证内容目录存在，并执行权限修复。

**环境变量**（默认值来自 Dockerfile）：

| 变量 | 默认值 | 用途 |
|---|---|---|
| `LRR_UID` / `LRR_GID` | `9001` / `9001` | 映射到 `koyomi` 的 uid/gid |
| `LRR_NETWORK` | `http://*:3000` | Mojo 监听字符串 |
| `LRR_AUTOFIX_PERMISSIONS` | `1` | 启动时执行权限修复 |
| `MOJO_PROXY` | `1` | HTTP 代理检测 |
| `MOJO_REVERSE_PROXY` | `1` | 信任 `X-Forwarded-*` 头 |
| `LC_ALL`/`LANG`/`LANGUAGE` | `en_US.UTF-8` | UTF-8 语言环境 |
| `S6_KEEP_ENV` | `1` | 为服务保留环境变量 |
| `S6_BEHAVIOUR_IF_STAGE2_FAILS` | `1` | stage2 脚本失败时告警 |

**持久化** —— 声明了 5 个卷：`/home/koyomi/lanraragi/content`、`.../thumb`、`.../database`、`.../lib/LANraragi/Plugin/Sideloaded`、`.../lib/LANraragi/Plugin/Managed`。

`EXPOSE 3000`，以及一个 `HEALTHCHECK`（间隔 1m，超时 10s，重试 3 次），用 `wget` 以 spider 方式访问 `http://127.0.0.1:3000`。

面向开发环境，还有 `tools/build/docker/Dockerfile-dev` 加上 `tools/build/docker/docker-compose.yml`：后者把仓库挂载到 `/home/koyomi/lanraragi`，并链接一个 `valkey:9` 服务，通过 `LRR_REDIS_ADDRESS=redis:6379` 访问。

## CI 工作流（`.github/workflows/`）

| 文件 | 触发条件 | 作用 |
|---|---|---|
| `push-continuous-integration.yml` | push、pull_request、手动 dispatch | ESLint（Node 22）；构建 Docker 镜像并通过 `.github/action-run-tests` 在其中运行测试套件；Perl Critic；随后用外部 `aio-lanraragi` 仓库的 Playwright/pytest 集成测试对本地构建的镜像进行测试 |
| `push-continous-delivery.yml` | push 到 `dev`、`test-builds`、`actions-testing` | 多架构 Docker 构建（arm/v6、arm/v7、arm64 经由 `ubuntu-24.04-arm`，另加 amd64 与 386，合并为单一 manifest）并以 `nightly` 标签推送；同时构建 nightly Windows MSI |
| `release-delivery.yml` | release 发布 | Windows MSI 构建（见下文）以及标记为 `latest` 的 Docker 镜像 |
| `push-brewtest.yml` | push | 在 `macos-latest` 上构建并测试内置的 Homebrew formula |

`.github/action-run-tests` 是一个小型 Docker action，基于刚构建好的 `lanraragi:test` 镜像（为测试重新添加 `perl-dev`、`g++`、`make`、`imagemagick`），其入口点运行 `prove -I /home/koyomi/perl5/lib/perl5 -r -l -v tests/`。多架构交付流水线使用 `.github/actions/docker-builder` 和 `.github/actions/docker-merge` 中的复合 action。

## 测试套件

本地使用 `npm test`（`prove -r -l -v tests/`）运行。`tests/` 下的布局：

- 顶层的 `.t` 文件：`backup.t`、`category.t`、`cbw.t`、`modules.t`、`opds.t`、`plugins.t`、`search.t`、`stamp.t`、`tankoubon.t`。
- `tests/LANraragi/Utils/` —— 12 个测试文件（`Archive.t`、`Generic.t`、`ImageMagickResizer.t`、`Logging.t`、`Metrics.t`、`Path.t`、`Registry.t`、`Routing.t`、`String.t`、`Tags.t`、`Vips.t`、`VipsResizer.t`）。
- `tests/LANraragi/Model/Plugins.t` 和 `tests/LANraragi/Plugin/Metadata/` —— 18 个元数据插件测试（Chaika、Eze、EHentai、Hitomi、Koromo 等）。
- `tests/mocks.pl` —— `setup_redis_mock()` 基于内存数据模型构建一个 `Test::MockObject` 的 Redis 模拟，因此测试套件不需要真实运行的 Redis 服务器。各测试在使用前 `require` 它（见 `tests/search.t`、`tests/modules.t`）。
- `tests/samples/` —— 供插件测试使用的夹具（示例压缩包、`doc.pdf`、各来源的 JSON 样本）。

在本地运行测试套件只需安装 `tools/cpanfile` 中的 Perl 依赖（`install-back` 或 `install-full`）——Redis 模拟意味着无需真实服务器。在 CI 中，同一条 `prove` 命令在工作流构建的 `lanraragi:test` 容器内执行，这也是 Dockerfile 必须保持测试友好的原因。

## Windows 安装器

两个工作流在 `windows-2025` 上以相同的流水线产出 MSI：`release-delivery.yml`（针对 GitHub release）和 `push-continous-delivery.yml`（nightly）。MSYS2 UCRT64 环境运行 `tools/build/windows/install-deps.sh`、`install.sh`、`cleanup.sh` 和 `create-dist.sh`，然后运行 `tools/build/windows/utf8-support.ps1`，最后 `tools/build/windows/build-installer.ps1` 产出 `tools/build/windows/Karen/Setup/bin/LANraragi.msi`（WiX；工作流会先卸载 chocolatey 的 WiX），并作为 `LANraragi.msi` 构建产物上传。`Karen/` 目录存放安装器项目；`tools/build/windows/` 还包含用于本地 Windows 运行的 `redis.conf` 和 `run.ps1`。

## Homebrew

`tools/build/homebrew/Lanraragi.rb` 是由 `push-brewtest.yml` 测试的 formula：该工作流将当前 commit 哈希拼接到 `COMMIT_HASH` 占位符上，以 `--build-from-source` 把 formula 安装到一个临时 tap，然后运行 `brew test`。

## 开发环境

- **开发容器（Devcontainer）** —— `.devcontainer/` 提供一个 Dockerfile 和 `devcontainer.json`（用户 `koyomi`，转发端口 3000，`postCreateCommand` 运行 `npm run lanraragi-installer install-front` 并启动 `valkey-server` 服务）。
- **本地开发** —— `npm run dev-server`（加 `-verbose` 可启用 `LRR_DEVSERVER` 调试）；用 `npm run kill-workers` 停掉游离的工作进程。
- **systemd** —— `tools/lanraragi-systemd.service` 是一个运行 `npm start` 的社区示例 unit；它假定宿主机上已有 Redis，并注明可能需要自行调整。
