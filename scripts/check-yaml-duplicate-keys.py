#!/usr/bin/env python3
"""Fail when YAML files contain duplicate mapping keys.

Helm templates are intentionally skipped because they are not YAML until rendered.
Vendored Gateway API CRDs are also skipped to keep the check focused on files
maintained directly in this repository.
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

import yaml

ROOT = Path(__file__).resolve().parents[1]
SKIP_PARTS = {
    ("apps", "core", "gateway-api-crds", "crd"),
    ("apps", "data", "dbt-analytics", "chart", "templates"),
}


class UniqueKeyLoader(yaml.SafeLoader):
    """PyYAML loader that rejects duplicate keys in mappings."""


def construct_mapping(loader: UniqueKeyLoader, node: yaml.MappingNode, deep: bool = False) -> dict[Any, Any]:
    # Expand YAML merge keys (`<<`) before checking duplicates so docker-compose
    # anchors keep working and explicit keys still override merged defaults.
    loader.flatten_mapping(node)

    mapping: dict[Any, Any] = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            mark = key_node.start_mark
            raise yaml.YAMLError(
                f"duplicate key {key!r} at {mark.name}:{mark.line + 1}:{mark.column + 1}"
            )
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


UniqueKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,
    construct_mapping,
)


def should_skip(path: Path) -> bool:
    rel = path.relative_to(ROOT)
    parts = rel.parts
    if ".git" in parts or ".terraform" in parts:
        return True
    return any(parts[: len(skip)] == skip for skip in SKIP_PARTS)


def iter_yaml_files() -> list[Path]:
    files: list[Path] = []
    for pattern in ("*.yaml", "*.yml"):
        files.extend(ROOT.rglob(pattern))
    return sorted(path for path in files if path.is_file() and not should_skip(path))


def main() -> int:
    errors: list[str] = []
    for path in iter_yaml_files():
        try:
            with path.open("r", encoding="utf-8") as handle:
                list(yaml.load_all(handle, Loader=UniqueKeyLoader))
        except Exception as exc:  # noqa: BLE001 - report every YAML/load failure consistently.
            errors.append(f"{path.relative_to(ROOT)}: {exc}")

    if errors:
        print("YAML duplicate-key check failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print(f"Checked {len(iter_yaml_files())} YAML files for duplicate keys")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
