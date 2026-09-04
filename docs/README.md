# LANraragi Developer Documentation

> Developer-oriented technical docs for this fork, generated from the actual codebase.
> Baseline commit `2094cc1d` (2026-09-04). 中文版见 [zh-CN/](zh-CN/)。

The complete, always-current user manual lives in [`tools/Documentation/`](../tools/Documentation/) (GitBook),
and the authoritative API specification is [`tools/openapi.yaml`](../tools/openapi.yaml) (lint via `npm run lint-openapi`).
The documents below are a code-level companion for developers.

## Topics

| # | Topic | EN | 中文 |
|---|-------|----|------|
| 01 | Data layer — 5 Redis databases, keys and fields | [en](en/01_data_layer.md) | [zh-CN](zh-CN/01_data_layer.md) |
| 02 | HTTP API — 87 operations, 64 paths, 12 tags | [en](en/02_api.md) | [zh-CN](zh-CN/02_api.md) |
| 03 | Utils — 24 modules (archives, VIPS, Minion, locks) | [en](en/03_utils.md) | [zh-CN](zh-CN/03_utils.md) |
| 04 | Plugin system — 4 types, 32 built-in plugins | [en](en/04_plugins.md) | [zh-CN](zh-CN/04_plugins.md) |
| 05 | Frontend — ES modules under `public/js/mod/` | [en](en/05_frontend.md) | [zh-CN](zh-CN/05_frontend.md) |
| 06 | Models — all 16 `LANraragi::Model` modules | [en](en/06_models.md) | [zh-CN](zh-CN/06_models.md) |
| 07 | Internationalization | [en](en/07_i18n.md) | [zh-CN](zh-CN/07_i18n.md) |
| 08 | Build, CI, tests, Docker | [en](en/08_build.md) | [zh-CN](zh-CN/08_build.md) |

Supporting files (auto-generated, do not edit by hand):

- [project_tree.md](project_tree.md) — full tree of tracked files
- [en/file_list.md](en/file_list.md) / [zh-CN/file_list.md](zh-CN/file_list.md) — files grouped by area with live counts

## Regeneration

File listings and statistics are machine-derived and never hand-written:

```bash
python3 docs/generate_docs.py   # or: npm run docs
python3 docs/generate_docs.py --check   # CI-style staleness check
```

Narrative documents are hand-verified against code at the baseline commit named in
each file's header; after significant code changes they need a manual review pass.

## Codebase snapshot (at baseline)

| Metric | Value |
|--------|-------|
| Tracked files | 481 |
| Perl modules / scripts+tests | 101 / 45 |
| Model / Utils modules | 16 / 24 |
| Built-in plugins (login/metadata/download/script) | 4 / 21 / 3 / 4 |
| Core frontend ES modules (`public/js/mod/`) | 9 |
| API operations / paths / tags (openapi.yaml) | 87 / 64 / 12 |
| Loadable UI languages | 12 |
