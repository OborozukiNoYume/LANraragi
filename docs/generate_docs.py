#!/usr/bin/env python3
"""Generate docs/project_tree.md and docs/{en,zh-CN}/file_list.md from git-tracked files.

Machine-derived facts only (file names, counts). Rerun after code changes:
    python3 docs/generate_docs.py          (or: npm run docs)
"""
import argparse
import datetime
import os
import re
import subprocess
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Outputs are excluded from their own listings.
SELF_EXCLUDE = {
    "docs/project_tree.md",
    "docs/en/file_list.md",
    "docs/zh-CN/file_list.md",
}

I18N = {
    "en": {
        "title": "# LANraragi Project File List",
        "generated": "Auto-generated from `git ls-files` — do not edit by hand.",
        "stats": "## File Statistics",
        "type": "Type", "count": "Count",
        "listing": "## Files by Area",
    },
    "zh-CN": {
        "title": "# LANraragi 项目文件清单",
        "generated": "由 `git ls-files` 自动生成——请勿手工编辑。",
        "stats": "## 文件统计",
        "type": "类型", "count": "数量",
        "listing": "## 按区域文件列表",
    },
}

TYPE_LABELS = [
    ("Perl modules (.pm)", lambda f: f.endswith(".pm")),
    ("Perl scripts/tests (.pl, .t)", lambda f: f.endswith(".pl") or f.endswith(".t")),
    ("JavaScript (.js)", lambda f: f.endswith(".js")),
    ("Templates (.tt2, .ep)", lambda f: f.endswith(".tt2") or f.endswith(".ep")),
    ("Translations (.po)", lambda f: f.endswith(".po")),
    ("Styles (.css)", lambda f: f.endswith(".css")),
    ("Docs (.md)", lambda f: f.endswith(".md")),
    ("Shell/PowerShell (.sh, .ps1)", lambda f: f.endswith(".sh") or f.endswith(".ps1")),
]

AREAS = [
    ("Server entry & config", ["lib/LANraragi.pm", "lib/Shinobu.pm", "lrr.conf"]),
    ("lib/LANraragi/Controller (pages)", "lib/LANraragi/Controller/"),
    ("lib/LANraragi/Controller/Api", "lib/LANraragi/Controller/Api/"),
    ("lib/LANraragi/Model", "lib/LANraragi/Model/"),
    ("lib/LANraragi/Utils", "lib/LANraragi/Utils/"),
    ("lib/LANraragi/Plugin/Login", "lib/LANraragi/Plugin/Login/"),
    ("lib/LANraragi/Plugin/Metadata", "lib/LANraragi/Plugin/Metadata/"),
    ("lib/LANraragi/Plugin/Download", "lib/LANraragi/Plugin/Download/"),
    ("lib/LANraragi/Plugin/Scripts", "lib/LANraragi/Plugin/Scripts/"),
    ("public/js (page scripts)", "public/js/"),
    ("public/js/mod (core ES modules)", "public/js/mod/"),
    ("public/themes", "public/themes/"),
    ("templates", "templates/"),
    ("locales/template", "locales/template/"),
    ("tests", "tests/"),
    ("script", "script/"),
    ("tools/openapi.yaml", ["tools/openapi.yaml"]),
    ("tools/build", "tools/build/"),
    ("tools/Documentation", "tools/Documentation/"),
    ("Root files", ["package.json", "package-lock.json", "eslint.config.mjs", "redocly.yml",
                    "README.md", "CONTRIBUTING.md", "COPYING", "Dockerfile", ".devcontainer/"]),
]


def tracked_files():
    out = subprocess.run(["git", "ls-files"], cwd=REPO_ROOT, capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"git ls-files failed: {out.stderr.strip()}")
    files = [f for f in out.stdout.splitlines() if f and f not in SELF_EXCLUDE]
    return sorted(files)


def baseline_commit():
    out = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=REPO_ROOT,
                         capture_output=True, text=True)
    return out.stdout.strip() if out.returncode == 0 else "unknown"


def area_files(files, area):
    if isinstance(area, list):
        return [f for f in files if f in area or any(f.startswith(p) and f != p for p in area)]
    prefix = area.rstrip("/") + "/"
    return [f for f in files if f.startswith(prefix)]


def render_file_list(files, lang, commit, date):
    t = I18N[lang]
    lines = [t["title"], "",
             f"> {t['generated']} Baseline commit `{commit}`, {date}.", "",
             t["stats"], "",
             f"| {t['type']} | {t['count']} |", "|------|------|"]
    matched = set()
    for label, pred in TYPE_LABELS:
        hits = [f for f in files if pred(f)]
        matched.update(hits)
        lines.append(f"| {label} | {len(hits)} |")
    lines.append(f"| Other | {len(files) - len(matched)} |")
    lines += ["", f"**Total tracked files: {len(files)}**", "", t["listing"], ""]
    listed = set()
    for title, area in AREAS:
        hits = [f for f in area_files(files, area) if f not in listed]
        if not hits:
            continue
        lines.append(f"### {title} ({len(hits)})")
        lines.append("")
        lines += [f"- `{f}`" for f in hits]
        listed.update(hits)
        lines.append("")
    rest = [f for f in files if f not in listed]
    if rest:
        lines.append(f"### Other ({len(rest)})")
        lines.append("")
        lines += [f"- `{f}`" for f in rest]
        lines.append("")
    return "\n".join(lines)


def render_tree(files, commit, date):
    lines = ["# LANraragi Project Tree", "",
             "> Auto-generated from `git ls-files` — do not edit by hand.",
             f"> Baseline commit `{commit}`, {date}. Total tracked files: {len(files)}.", "",
             "```"]
    tree = {}
    for f in files:
        node = tree
        for part in f.split("/"):
            node = node.setdefault(part, {})
    def walk(node, prefix):
        entries = sorted(node.items(), key=lambda kv: (not isinstance(kv[1], dict), kv[0].lower()))
        for i, (name, child) in enumerate(entries):
            last = i == len(entries) - 1
            lines.append(prefix + ("└── " if last else "├── ") + name)
            if child:
                walk(child, prefix + ("    " if last else "│   "))
    walk(tree, "")
    lines.append("```")
    return "\n".join(lines)


def strip_volatile(text):
    """Drop the baseline commit/date header line so --check only compares real content."""
    return re.sub(r"^> .*Baseline commit.*$", "", text, flags=re.MULTILINE)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true",
                    help="verify outputs are up to date; exit 1 if not")
    args = ap.parse_args()

    files = tracked_files()
    commit = baseline_commit()
    date = datetime.date.today().isoformat()
    outputs = {
        os.path.join(REPO_ROOT, "docs/project_tree.md"): render_tree(files, commit, date),
        os.path.join(REPO_ROOT, "docs/en/file_list.md"): render_file_list(files, "en", commit, date),
        os.path.join(REPO_ROOT, "docs/zh-CN/file_list.md"): render_file_list(files, "zh-CN", commit, date),
    }
    for path, content in outputs.items():
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if args.check:
            with open(path, encoding="utf-8") as fh:
                if strip_volatile(fh.read()) != strip_volatile(content + "\n"):
                    print(f"STALE: {os.path.relpath(path, REPO_ROOT)} (rerun generate_docs.py)")
                    sys.exit(1)
            print(f"OK: {os.path.relpath(path, REPO_ROOT)}")
        else:
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(content + "\n")
            print(f"wrote {os.path.relpath(path, REPO_ROOT)}")


if __name__ == "__main__":
    main()
