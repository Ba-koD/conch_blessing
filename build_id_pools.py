#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Build ID Pools from IsaacDocs

Fetches the enums table and outputs an ID-first pool array for use in script.js.

Examples:
  # Default: build ALL (collectibles, trinkets, pills, cards) to files under tools/output/
  python3 tools/build_id_pools.py

  # Specific type to stdout (old behavior):
  python3 tools/build_id_pools.py --type collectibles --format json --stdout
  python3 tools/build_id_pools.py --type trinkets --format js --var TRINKET_ID_POOL --stdout

Docs referenced:
  - CollectibleType: https://wofsauge.github.io/IsaacDocs/rep/enums/CollectibleType.html
  - TrinketType:     https://wofsauge.github.io/IsaacDocs/rep/enums/TrinketType.html
"""

import argparse
import json
import re
import sys
import os
from typing import List, Tuple

try:
    import requests
    from bs4 import BeautifulSoup
except Exception as e:
    print("This script requires 'requests' and 'beautifulsoup4'. Install via:\n  pip install requests beautifulsoup4", file=sys.stderr)
    raise


URLS = {
    "collectibles": "https://wofsauge.github.io/IsaacDocs/rep/enums/CollectibleType.html",
    "trinkets": "https://wofsauge.github.io/IsaacDocs/rep/enums/TrinketType.html",
    "pills": "https://wofsauge.github.io/IsaacDocs/rep/enums/PillEffect.html",
    "cards": "https://wofsauge.github.io/IsaacDocs/rep/enums/Card.html",
}


def fetch_html(url: str) -> str:
    r = requests.get(url, timeout=30)
    r.raise_for_status()
    return r.text


def parse_enums_table(html: str, prefix_to_strip: str) -> List[Tuple[int, str]]:
    soup = BeautifulSoup(html, "html.parser")
    result: List[Tuple[int, str]] = []

    # The docs render a table: DLC | Value | Enumerator | Comment
    for tr in soup.select("table tbody tr"):
        tds = tr.find_all("td")
        if len(tds) < 3:
            continue
        value_txt = tds[1].get_text(strip=True)
        enum_txt = tds[2].get_text(strip=True)
        if not value_txt or not value_txt.isdigit():
            continue
        value = int(value_txt)
        # Strip enum prefix: e.g., COLLECTIBLE_*, TRINKET_*
        enum_clean = re.sub(rf"^{re.escape(prefix_to_strip)}_", "", enum_txt)
        if enum_clean:
            result.append((value, enum_clean))

    # Sort by ID ascending for stable diffs
    result.sort(key=lambda x: x[0])
    return result


def to_json_array(pairs: List[Tuple[int, str]]) -> str:
    # Emit one pair per line: [ID, "NAME"],
    lines = ["["]
    for idx, (id_, name) in enumerate(pairs):
        name_json = json.dumps(name, ensure_ascii=False)
        comma = "," if idx < len(pairs) - 1 else ""
        lines.append(f"  [{id_}, {name_json}]{comma}")
    lines.append("]")
    return "\n".join(lines)


def to_js_array(pairs: List[Tuple[int, str]], var_name: str) -> str:
    lines = [f"const {var_name} = ["]
    for id_, name in pairs:
        # Ensure proper escaping and double quotes for the name
        name_js = json.dumps(name, ensure_ascii=False)
        lines.append(f"  [{id_}, {name_js}],")
    lines.append("];")
    return "\n".join(lines)


def ensure_dir(path: str) -> None:
    if not os.path.isdir(path):
        os.makedirs(path, exist_ok=True)


def build_pairs(kind: str) -> List[Tuple[int, str]]:
    url = URLS[kind]
    prefix_map = {
        "collectibles": "COLLECTIBLE",
        "trinkets": "TRINKET",
        "pills": "PILLEFFECT",
        "cards": "CARD",
    }
    html = fetch_html(url)
    pairs = parse_enums_table(html, prefix_map[kind])
    return pairs


def build_one(kind: str, out_format: str, var_name_override: str | None = None) -> str:
    default_var_map = {
        "collectibles": "COLLECTIBLE_ID_POOL",
        "trinkets": "TRINKET_ID_POOL",
        "pills": "PILL_ID_POOL",
        "cards": "CARD_ID_POOL",
    }

    pairs = build_pairs(kind)

    if out_format == "json":
        return to_json_array(pairs)
    else:
        var_name = var_name_override or default_var_map[kind]
        return to_js_array(pairs, var_name)


def default_out_filename(kind: str, out_format: str) -> str:
    name_map = {
        "collectibles": "collectible_pool",
        "trinkets": "trinket_pool",
        "pills": "pill_pool",
        "cards": "card_pool",
    }
    base = name_map[kind]
    ext = "js" if out_format == "js" else "json"
    return f"{base}.{ext}"


def main() -> None:
    ap = argparse.ArgumentParser(description="Build ID pools from IsaacDocs enums table")
    ap.add_argument("--type", choices=["collectibles", "trinkets", "pills", "cards"], nargs="*", help="Which enum(s) to fetch. Default: all")
    ap.add_argument("--format", choices=["json", "js"], default="json", help="Output format (default: json)")
    ap.add_argument("--var", dest="var_name", default=None, help="JS variable name when --format js; applies only if single --type is used")
    ap.add_argument("--out-dir", default="tools/output", help="Directory to write split outputs (when --write-split)")
    ap.add_argument("--stdout", action="store_true", help="Print to stdout instead of writing files (only valid with single --type)")
    ap.add_argument("--itemmap-out", default="itemmap.js", help="Path to write bundled itemmap.js (default: itemmap.js at project root)")
    ap.add_argument("--no-itemmap", action="store_true", help="Do not generate bundled itemmap.js")
    ap.add_argument("--write-split", action="store_true", help="Also write per-type outputs under --out-dir (disabled by default)")
    args = ap.parse_args()

    kinds = args.type or ["collectibles", "trinkets", "pills", "cards"]

    # stdout mode only makes sense for single type
    if args.stdout and len(kinds) != 1:
        print("--stdout requires exactly one --type", file=sys.stderr)
        sys.exit(2)

    # Split outputs only when explicitly requested
    if args.stdout:
        # stdout mode (single type only)
        kind = kinds[0]
        content = build_one(kind, args.format, args.var_name)
        print(content)
    elif args.write_split:
        ensure_dir(args.out_dir)
        for kind in kinds:
            content = build_one(kind, args.format)
            out_path = os.path.join(args.out_dir, default_out_filename(kind, args.format))
            with open(out_path, "w", encoding="utf-8") as f:
                f.write(content)
            print(f"Wrote {kind} -> {out_path}")

    # Build bundled itemmap.js when not stdout (default)
    if not args.stdout and not args.no_itemmap:
        # Always include all four kinds in the bundle for completeness
        kinds_all = ["collectibles", "trinkets", "pills", "cards"]
        default_var_map = {
            "collectibles": "COLLECTIBLE_ID_POOL",
            "trinkets": "TRINKET_ID_POOL",
            "pills": "PILL_ID_POOL",
            "cards": "CARD_ID_POOL",
        }

        def to_js_window_array(pairs: List[Tuple[int, str]], var_name: str) -> str:
            lines = [f"window.{var_name} = ["]
            for id_, name in pairs:
                name_js = json.dumps(name, ensure_ascii=False)
                lines.append(f"  [{id_}, {name_js}],")
            lines.append("];\n")
            return "\n".join(lines)

        bundle_lines = [
            "// Auto-generated by build_id_pools.py",
            "// Item ID pools for display (loaded by script.js)",
            "",
        ]
        for k in kinds_all:
            try:
                pairs = build_pairs(k)
                var_name = default_var_map[k]
                bundle_lines.append(to_js_window_array(pairs, var_name))
            except Exception as e:
                # Emit empty pool on failure, but continue
                bundle_lines.append(f"window.{default_var_map[k]} = [];\n")

        itemmap_content = "\n".join(bundle_lines)
        with open(args.itemmap_out, "w", encoding="utf-8") as f:
            f.write(itemmap_content)
        print(f"Wrote bundled pools -> {args.itemmap_out}")


if __name__ == "__main__":
    main()

