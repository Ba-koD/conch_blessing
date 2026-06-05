#!/usr/bin/env python3
"""Prepare a Steam Workshop upload folder and VDF for SteamCMD."""

import argparse
import shutil
import xml.etree.ElementTree as ET
from pathlib import Path

APP_ID = "250900"
INCLUDE_DIRS = ("content", "resources", "scripts")
INCLUDE_FILES = ("main.lua", "metadata.xml", "Thumbnail.png")
DEFAULT_LANGUAGES = ("english", "koreana")
WORKSHOP_LOCALIZATIONS = {
    "english": {
        "title": "Conch's Blessing",
        "description": Path(".github/workshop/descriptions/english.txt"),
    },
    "koreana": {
        "title": "소라고둥의 축복 (Conch's Blessing)",
        "description": Path(".github/workshop/descriptions/koreana.txt"),
    },
}
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
        "--languages",
        default=",".join(DEFAULT_LANGUAGES),
        help="Comma-separated Steam API language codes for title/description updates.",
    )
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


def parse_languages(value):
    languages = [language.strip() for language in value.split(",") if language.strip()]
    if not languages:
        raise ValueError("At least one language must be specified.")

    unknown = [language for language in languages if language not in WORKSHOP_LOCALIZATIONS]
    if unknown:
        supported = ", ".join(sorted(WORKSHOP_LOCALIZATIONS))
        raise ValueError(f"Unsupported workshop language(s): {', '.join(unknown)}. Supported: {supported}")

    return languages


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


def read_workshop_description(repo_root, language):
    description_path = repo_root / WORKSHOP_LOCALIZATIONS[language]["description"]
    return description_path.read_text(encoding="utf-8").strip()


def write_vdf(vdf_path, fields):
    lines = ['"workshopitem"', "{"]
    multiline_keys = {"description", "changenote"}
    for key, value in fields.items():
        lines.append(f'\t"{key}" "{escape_vdf(value, preserve_newlines=key in multiline_keys)}"')
    lines.append("}")
    vdf_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return vdf_path


def build_vdf_fields(metadata, language, title, description, changenote):
    note = normalize_changenote(changenote) or f"Version {metadata['version']}".strip()
    return {
        "appid": APP_ID,
        "publishedfileid": metadata["publishedfileid"],
        "language": language,
        "title": title,
        "description": description,
        "changenote": note,
    }


def write_vdfs(output_dir, repo_root, metadata, content_dir, preview_file, visibility, changenote, languages):
    vdf_paths = []
    primary_language = languages[0]

    for language in languages:
        localization = WORKSHOP_LOCALIZATIONS[language]
        fields = build_vdf_fields(
            metadata,
            language,
            localization["title"],
            read_workshop_description(repo_root, language),
            changenote,
        )

        if language == primary_language:
            fields = {
                "appid": APP_ID,
                "publishedfileid": metadata["publishedfileid"],
                "contentfolder": str(content_dir.resolve()),
                "previewfile": str(preview_file.resolve()),
                "visibility": VISIBILITY[visibility],
                **{key: value for key, value in fields.items() if key not in {"appid", "publishedfileid"}},
            }

        vdf_paths.append(write_vdf(output_dir / f"workshop_item_{language}.vdf", fields))

    manifest_path = output_dir / "workshop_vdfs.txt"
    manifest_path.write_text("\n".join(str(path.name) for path in vdf_paths) + "\n", encoding="utf-8")
    return vdf_paths, manifest_path


def write_legacy_vdf(output_dir, metadata, content_dir, preview_file, visibility, changenote):
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

    return write_vdf(output_dir / "workshop_item.vdf", fields)


def main():
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    output_dir = (repo_root / args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    languages = parse_languages(args.languages)

    metadata = read_metadata(repo_root)
    content_dir = prepare_content(repo_root, output_dir, metadata["directory"])
    preview_file = content_dir / "Thumbnail.png"
    if not preview_file.exists():
        raise FileNotFoundError("Preview file not found: Thumbnail.png")

    write_legacy_vdf(output_dir, metadata, content_dir, preview_file, args.visibility, args.changenote)
    vdf_paths, manifest_path = write_vdfs(
        output_dir,
        repo_root,
        metadata,
        content_dir,
        preview_file,
        args.visibility,
        args.changenote,
        languages,
    )

    print(f"Prepared Steam Workshop content: {content_dir}")
    for vdf_path in vdf_paths:
        print(f"Prepared Steam Workshop VDF: {vdf_path}")
    print(f"Prepared Steam Workshop VDF manifest: {manifest_path}")
    print(f"Languages: {', '.join(languages)}")
    print(f"PublishedFileId: {metadata['publishedfileid']}")
    print(f"Visibility: {args.visibility}")


if __name__ == "__main__":
    main()
