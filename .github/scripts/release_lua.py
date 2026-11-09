"""The released (Workshop) copy of this mod's Lua: only what the mod runs.

prepare_steam_workshop_upload.py calls strip_dev_code on the staged package.
Removed from each file:

- every `X._test = { ... }` table: hooks only the dev benches and the offline
  tests read (no runtime code reads `_test`), with the comment right above it
  when that comment speaks of tests, probes, benches, hooks or exposure;
- every line ending in `-- dev-only`;
- every line from `-- dev-only:begin` to `-- dev-only:end`.

The repository keeps them; tests/test_workshop_package.py compiles the result.
"""
import re
from pathlib import Path

TEST_TABLE = re.compile(r"^[A-Za-z_][\w.]*\._test\s*=\s*\{")
DEV_HINT = re.compile(r"test|probe|bench|exposed|hook", re.I)
LONG_OPEN = re.compile(r"\[(=*)\[")
NEWLINE = "\n"


def _skip_long(text, i, match):
    close = "]" + match.group(1) + "]"
    return text.index(close, i + len(match.group(0))) + len(close)


def lua_block_end(text, start):
    """Index just past the brace closing the `{` at text[start], skipping Lua
    strings and comments."""
    depth, i, n = 0, start, len(text)
    while i < n:
        if text.startswith("--", i):
            long = LONG_OPEN.match(text, i + 2)
            if long:
                i = _skip_long(text, i + 2, long)
            else:
                end = text.find(NEWLINE, i)
                i = n if end < 0 else end + 1
            continue
        long = LONG_OPEN.match(text, i)
        if long:
            i = _skip_long(text, i, long)
            continue
        c = text[i]
        if c in ("'", '"'):
            i += 1
            while text[i] != c:
                i += 2 if text[i] == "\\" else 1
            i += 1
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise ValueError("unbalanced braces")


def strip_dev_lua(text):
    """The released copy of one Lua source (line endings kept as they were)."""
    lines = text.splitlines(keepends=True)
    out, i, skipping = [], 0, False
    while i < len(lines):
        line = lines[i]
        bare = line.strip()
        if bare == "-- dev-only:begin":
            if skipping:
                raise ValueError("nested -- dev-only:begin")
            skipping = True
        elif bare == "-- dev-only:end":
            if not skipping:
                raise ValueError("-- dev-only:end without a begin")
            skipping = False
        elif skipping or bare.endswith("-- dev-only"):
            pass
        elif TEST_TABLE.match(line):
            comment = len(out)
            while comment > 0 and out[comment - 1].lstrip().startswith("--"):
                comment -= 1
            if comment < len(out) and DEV_HINT.search("".join(out[comment:])):
                del out[comment:]
            rest = "".join(lines[i:])
            end = lua_block_end(rest, rest.index("{"))
            # the table and whatever follows it on its closing line
            i += rest[:end].count(NEWLINE) + 1
            continue
        else:
            out.append(line)
        i += 1
    if skipping:
        raise ValueError("-- dev-only:begin without an end")
    return "".join(out)


def strip_dev_code(content_dir):
    """Strip every staged Lua file in place; returns the paths it changed."""
    changed = []
    for path in sorted(Path(content_dir).rglob("*.lua")):
        text = path.read_bytes().decode("utf-8")
        released = strip_dev_lua(text)
        if released != text:
            path.write_bytes(released.encode("utf-8"))
            changed.append(path)
    return changed
