#!/usr/bin/env python3
"""Prepare a Steam Workshop upload folder and VDF for SteamCMD."""

import argparse
import shutil
import xml.etree.ElementTree as ET
from pathlib import Path

APP_ID = "250900"
INCLUDE_DIRS = ("content", "resources", "scripts")
INCLUDE_FILES = ("main.lua", "metadata.xml", "Thumbnial.png")
VISIBILITY = {
    "public": "0",
    "friends": "1",
    "private": "2",
}


def parse_args():
    parser = argparse.ArgumentParser(description="Prepare Steam Workshop upload files.")
    parser.add_argument("--repo-root", default=".", help="Repository root. Defaults to current directory.")
    parser.add_argument("--output-dir", default="dist/steam-workshop", help="Output directory.")
    parser.add_argument("--visibility", choices=sorted(VISIBILITY), default="public")
    parser.add_argument(
        "--changenote",
        default="",
        help=r"Steam Workshop changenote. Use \n for line breaks.",
    )
    return parser.parse_args()


def read_metadata(repo_root):
    metadata_path = repo_root / "metadata.xml"
    root = ET.parse(metadata_path).getroot()

    def text(name, default=""):
        value = root.findtext(name)
        return value if value is not None else default

    return {
        "title": text("name", "Conch's Blessing"),
        "directory": text("directory", "conch_blessing"),
        "publishedfileid": text("id", "0"),
        "description": text("description", ""),
        "version": text("version", ""),
    }


def copy_tree(src, dst):
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))


def prepare_content(repo_root, output_dir, directory_name):
    content_dir = output_dir / "content" / directory_name
    if content_dir.exists():
        shutil.rmtree(content_dir)
    content_dir.mkdir(parents=True, exist_ok=True)

    for dirname in INCLUDE_DIRS:
        copy_tree(repo_root / dirname, content_dir / dirname)

    for filename in INCLUDE_FILES:
        src = repo_root / filename
        if src.exists():
            shutil.copy2(src, content_dir / filename)

    return content_dir


def escape_vdf(value, preserve_newlines=False):
    text = str(value).replace("\\", "\\\\").replace('"', '\\"').replace("\t", "\\t")
    if preserve_newlines:
        return text.replace("\r\n", "\n").replace("\r", "\n")
    return text.replace("\r\n", " ").replace("\n", " ").replace("\r", " ")


def normalize_changenote(value):
    return value.replace("\\r\\n", "\n").replace("\\n", "\n").strip()


def write_vdf(output_dir, metadata, content_dir, preview_file, visibility, changenote):
    vdf_path = output_dir / "workshop_item.vdf"
    note = normalize_changenote(changenote) or f"Version {metadata['version']}".strip()

    fields = {
        "appid": APP_ID,
        "publishedfileid": metadata["publishedfileid"],
        "contentfolder": str(content_dir.resolve()),
        "previewfile": str(preview_file.resolve()),
        "visibility": VISIBILITY[visibility],
        "title": metadata["title"],
        "description": metadata["description"],
        "changenote": note,
    }

    lines = ['"workshopitem"', "{"]
    multiline_keys = {"description", "changenote"}
    for key, value in fields.items():
        lines.append(f'\t"{key}" "{escape_vdf(value, preserve_newlines=key in multiline_keys)}"')
    lines.append("}")
    vdf_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return vdf_path


def main():
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    output_dir = (repo_root / args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    metadata = read_metadata(repo_root)
    content_dir = prepare_content(repo_root, output_dir, metadata["directory"])
    preview_file = content_dir / "Thumbnial.png"
    if not preview_file.exists():
        raise FileNotFoundError("Preview file not found: Thumbnial.png")

    vdf_path = write_vdf(output_dir, metadata, content_dir, preview_file, args.visibility, args.changenote)

    print(f"Prepared Steam Workshop content: {content_dir}")
    print(f"Prepared Steam Workshop VDF: {vdf_path}")
    print(f"PublishedFileId: {metadata['publishedfileid']}")
    print(f"Visibility: {args.visibility}")


if __name__ == "__main__":
    main()
