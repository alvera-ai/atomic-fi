#!/usr/bin/env python3
"""
port_platform_skill.py — copy markdown skills from the platform repo to this
repo, applying module/path substitutions.

Usage:
    # Dry-run — print planned diffs, exit 1 if any file would change:
    python scripts/port_platform_skill.py

    # Apply:
    python scripts/port_platform_skill.py --apply

One-time-ish: this script records which files were ported and what
substitutions were applied, so future re-ports (or pulling in new skills
from the platform) are reviewable.
"""
from __future__ import annotations

import argparse
import difflib
import sys
from pathlib import Path

SRC_ROOT = Path(
    "/Users/himangshuhazarika/work/alvera-ai/platform/.claude/commands"
)
DEST_ROOT = Path(__file__).resolve().parent.parent / ".claude" / "commands"

# (src_rel, dest_rel) — listed out so the port is explicit/reviewable.
FILES = [
    ("dev/create-rest-api.md", "dev/create-rest-api.md"),
    ("dev/create-ast-refactor-task.md", "dev/create-ast-refactor-task.md"),
    ("dev/setup-worktree.md", "dev/setup-worktree.md"),
    ("qa/quality-checks.md", "qa/quality-checks.md"),
    ("qa/fix-failing-tests.md", "qa/fix-failing-tests.md"),
    ("qa/review.md", "qa/review.md"),
    ("qa/increase-test-coverage.md", "qa/increase-test-coverage.md"),
]

# Order matters: longer matches first so e.g. "lib/platform_api/" is rewritten
# before "lib/platform/" would match the same prefix.
SUBSTITUTIONS: list[tuple[str, str]] = [
    ("lib/platform_api/", "lib/payment_compliance_platform_api/"),
    ("lib/platform_web/", "lib/payment_compliance_platform_web/"),
    ("lib/platform/", "lib/payment_compliance_platform/"),
    ("test/platform_api/", "test/payment_compliance_platform_api/"),
    ("test/platform_web/", "test/payment_compliance_platform_web/"),
    ("test/platform/", "test/payment_compliance_platform/"),
    ("PlatformApi", "PaymentCompliancePlatformApi"),
    ("PlatformWeb", "PaymentCompliancePlatformWeb"),
    # Dot-suffixed so we only rewrite module refs like `Platform.Foo`, not
    # prose sentences mentioning "platform".
    ("Platform.", "PaymentCompliancePlatform."),
]


def rewrite(text: str) -> str:
    out = text
    for needle, repl in SUBSTITUTIONS:
        out = out.replace(needle, repl)
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--apply", action="store_true", help="Write changes; default is dry-run."
    )
    args = parser.parse_args()

    changed: list[Path] = []
    for src_rel, dest_rel in FILES:
        src = SRC_ROOT / src_rel
        dest = DEST_ROOT / dest_rel

        if not src.exists():
            print(f"ERROR: source missing: {src}", file=sys.stderr)
            return 2

        original = src.read_text()
        rewritten = rewrite(original)

        existing = dest.read_text() if dest.exists() else ""
        if existing == rewritten:
            print(f"unchanged: {dest_rel}")
            continue

        changed.append(dest)
        print(f"\n=== {dest_rel} ===")
        diff = difflib.unified_diff(
            existing.splitlines(keepends=True),
            rewritten.splitlines(keepends=True),
            fromfile=str(dest),
            tofile=f"{src} (rewritten)",
            n=2,
        )
        sys.stdout.writelines(diff)

        if args.apply:
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(rewritten)

    print(f"\n{'applied' if args.apply else 'would change'}: {len(changed)} file(s)")
    return 0 if args.apply or not changed else 1


if __name__ == "__main__":
    sys.exit(main())
