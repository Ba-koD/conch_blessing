#!/usr/bin/env python3
"""Update Steam Workshop title and description localizations."""

import argparse
import json
import os
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from prepare_steam_workshop_upload import (
    APP_ID,
    DEFAULT_LANGUAGES,
    WORKSHOP_LOCALIZATIONS,
    parse_languages,
    read_metadata,
    read_workshop_description,
)

UPDATE_URL = "https://api.steampowered.com/IPublishedFileService/Update/v1/"
STEAM_WEB_API_LANGUAGE_IDS = {
    "english": 0,
    "koreana": 4,
}


def parse_args():
    parser = argparse.ArgumentParser(description="Update Steam Workshop localized title and description.")
    parser.add_argument("--repo-root", default=".", help="Repository root. Defaults to current directory.")
    parser.add_argument("--appid", default=APP_ID)
    parser.add_argument("--publishedfileid", default="")
    parser.add_argument(
        "--languages",
        default=",".join(DEFAULT_LANGUAGES),
        help="Comma-separated Steam API language codes for title/description updates.",
    )
    parser.add_argument("--dry-run", action="store_true", help="Validate payloads without calling Steam.")
    return parser.parse_args()


def build_payload(repo_root, appid, publishedfileid, language):
    if language not in STEAM_WEB_API_LANGUAGE_IDS:
        supported = ", ".join(sorted(STEAM_WEB_API_LANGUAGE_IDS))
        raise ValueError(f"Unsupported Steam Web API language: {language}. Supported: {supported}")

    localization = WORKSHOP_LOCALIZATIONS[language]
    return {
        "appid": int(appid),
        "publishedfileid": str(publishedfileid),
        "title": localization["title"],
        "file_description": read_workshop_description(repo_root, language),
        "language": STEAM_WEB_API_LANGUAGE_IDS[language],
    }


def post_update(api_key, payload):
    body = urllib.parse.urlencode(
        {
            "key": api_key,
            "format": "json",
            "input_json": json.dumps(payload, ensure_ascii=False),
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        UPDATE_URL,
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded; charset=utf-8"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            response_body = response.read().decode("utf-8")
    except urllib.error.HTTPError as error:
        error_body = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Steam localization update failed: HTTP {error.code}: {error_body}") from error

    if not response_body.strip():
        return {}

    result = json.loads(response_body)
    response = result.get("response", result)
    if response.get("result") not in (None, 1):
        raise RuntimeError(f"Steam localization update failed: {response_body}")

    return result


def main():
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    metadata = read_metadata(repo_root)
    publishedfileid = args.publishedfileid.strip() or metadata["publishedfileid"].strip()
    if not publishedfileid or publishedfileid == "0":
        raise ValueError("A publishedfileid is required.")

    languages = parse_languages(args.languages)
    payloads = [build_payload(repo_root, args.appid, publishedfileid, language) for language in languages]

    if args.dry_run:
        for payload in payloads:
            print(
                "Prepared Steam Workshop localization: "
                f"language={payload['language']} title={payload['title']!r}"
            )
        return

    api_key = os.environ.get("STEAM_WEB_API_KEY", "").strip()
    if not api_key:
        raise ValueError("STEAM_WEB_API_KEY is required to update Steam Workshop localizations.")

    for language, payload in zip(languages, payloads):
        post_update(api_key, payload)
        print(
            "Updated Steam Workshop localization: "
            f"{language} language={payload['language']} title={payload['title']!r}"
        )


if __name__ == "__main__":
    main()
