"""Verify shipped sprites against the final selection without duplicating PNGs."""
from pathlib import Path
import hashlib
import json
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def load_selection():
    return json.loads((HERE / "selection.json").read_text(encoding="utf-8"))


def original_bytes(selection, row):
    return subprocess.check_output(
        ["git", "show", f"{selection['original_revision']}:{row['source']}"], cwd=ROOT
    )


def verify(selection):
    for row in selection["items"]:
        current = (ROOT / row["source"]).read_bytes()
        if hashlib.sha256(current).hexdigest() != row["selected_sha256"]:
            raise ValueError(f"Runtime differs from approved selection: {row['key']}")
        if hashlib.sha256(original_bytes(selection, row)).hexdigest() != row["original_sha256"]:
            raise ValueError(f"Original revision differs from recorded baseline: {row['key']}")


if __name__ == "__main__":
    selection = load_selection()
    verify(selection)
    rows = selection["items"]
    changed = sum(row["selected_sha256"] != row["original_sha256"] for row in rows)
    print(f"{len(rows)} runtime sprites verified: {changed} updated, {len(rows) - changed} original.")
