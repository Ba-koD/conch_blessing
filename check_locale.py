#!/usr/bin/env python3
"""Check the locale files in scripts/locale against each other and the item registry.

Run from anywhere:  python check_locale.py
Prints every problem and exits 1 if there is one. It checks that
  * every language in Locale.LANGUAGES (scripts/locale/init.lua) has a pure-data
    file, and every file is listed
  * en.lua names every ConchBlessing.ItemData item with the same name its id field
    looks up (generate_xml.py writes that English name into items.xml), and no
    language has an entry for an item that does not exist
  * every other language mirrors English line for line: the same fields, the same
    number of EID lines, the same synergy lines and the same specials
  * each synergy entry in ItemData names an English line, and each English line is used
  * icon tokens resolve: {c:}, {t:} and {card:} names exist in the game's enums.lua
    (checked when the mod sits in the game's mods folder), {own:KEY} is an ItemData key
  * %TOKEN% values in item text are registered in ConchBlessing.EIDDynamicTokens
  * ui strings mirror English (ui.mcm is English-only), use only %s and %% as
    format directives, and take as many %s arguments as English does
  * every character Cronus's absorption captions can show has a glyph in
    scripts/items/collectibles/cronus_caption_glyphs.lua (generate_caption_glyphs.py)
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ROOT)
import lua_data  # noqa: E402

LOCALE_DIR = os.path.join(ROOT, "scripts", "locale")
INIT_PATH = os.path.join(LOCALE_DIR, "init.lua")
ITEMS_PATH = os.path.join(ROOT, "scripts", "conch_blessing_items.lua")
SCRIPTS_DIR = os.path.join(ROOT, "scripts")
ENUMS_PATH = os.path.normpath(os.path.join(ROOT, "..", "..", "resources", "scripts", "enums.lua"))
FALLBACK = "en"
ENGLISH_ONLY = ("ui.mcm",)
ITEM_FIELDS = ("name", "description", "eid", "synergies", "specials")
ICON = re.compile(r"\{(\w+):([^{}]+)\}")
DYNAMIC = re.compile(r"%([A-Z_]+)%")
ENUM_TABLES = {"c": ("CollectibleType", "COLLECTIBLE_"), "t": ("TrinketType", "TRINKET_"), "card": ("Card", "CARD_")}
CAPTION_GLYPHS_PATH = os.path.join(ROOT, "scripts", "items", "collectibles", "cronus_caption_glyphs.lua")
# Characters LanaPixel lacks that the caption draws as another glyph (CAPTION.FALLBACK in cronus.lua).
CAPTION_FALLBACK = {"\u2212"}

errors = []


def error(message):
    errors.append(message)


# ---- the item registry, read as tokens ----

def matching(toks, i):
    pairs = {"{": "}", "[": "]", "(": ")"}
    depth = 0
    for j in range(i, len(toks)):
        kind, text, _ = toks[j]
        if kind == "op" and text in pairs:
            depth += 1
        elif kind == "op" and text in pairs.values():
            depth -= 1
            if depth == 0:
                return j
    raise lua_data.LuaDataError("line %d: unclosed %s" % (toks[i][2], toks[i][1]))


def table_entries(toks, i):
    """Entries of the table constructor opened at toks[i]: (key, value_start, value_end).
    key is a name, ("expr", start, end) for [key] = ..., or None for a positional value."""
    end = matching(toks, i)
    entries, i = [], i + 1
    while i < end:
        if toks[i][1] in (",", ";"):
            i += 1
            continue
        if toks[i][0] == "name" and toks[i + 1][1] == "=":
            key, i = toks[i][1], i + 2
        elif toks[i][1] == "[":
            j = matching(toks, i)
            key, i = ("expr", i + 1, j - 1), j + 2
        else:
            key = None
        start = i
        while i < end and not (toks[i][1] in (",", ";")):
            i = matching(toks, i) + 1 if toks[i][1] in ("{", "[", "(") else i + 1
        entries.append((key, start, i - 1))
    return entries


def read_registry():
    """ItemData key -> {"type": str, "xml_name": str or None, "synergies": [(line key, source line)]}."""
    with open(ITEMS_PATH, encoding="utf-8") as handle:
        toks = lua_data.scan(handle.read())
    texts = [t[1] for t in toks]
    start = next((i for i in range(len(toks)) if texts[i:i + 5] == ["ConchBlessing", ".", "ItemData", "=", "{"]), None)
    if start is None:
        sys.exit("check_locale: ConchBlessing.ItemData = { not found in " + ITEMS_PATH)
    registry = {}
    for key, a, _ in table_entries(toks, start + 4):
        if not isinstance(key, str) or toks[a][1] != "{":
            continue
        info = {"type": None, "xml_name": None, "synergies": []}
        for field, fa, fb in table_entries(toks, a):
            if field == "type" and fa == fb and toks[fa][0] == "string":
                info["type"] = lua_data.loads(toks[fa][1])
            elif field == "id" and [t[1] for t in toks[fa:fa + 4]] in (
                    ["Isaac", ".", "GetItemIdByName", "("], ["Isaac", ".", "GetTrinketIdByName", "("]) \
                    and toks[fa + 4][0] == "string":
                info["xml_name"] = (lua_data.loads(toks[fa + 4][1]), toks[fa][2])
            elif field == "synergies" and toks[fa][1] == "{":
                for _, va, vb in table_entries(toks, fa):
                    if va == vb and toks[va][0] == "string":
                        info["synergies"].append((lua_data.loads(toks[va][1]), toks[va][2]))
                    else:
                        error("conch_blessing_items.lua:%d: %s: a synergy value must be the name of its "
                              "line in the locale files" % (toks[va][2], key))
        registry[key] = info
    return registry


# ---- reference data ----

def read_enums():
    if not os.path.exists(ENUMS_PATH):
        print("note: %s not found; {c:}, {t:} and {card:} names were not checked" % ENUMS_PATH)
        return None
    with open(ENUMS_PATH, encoding="utf-8", errors="replace") as handle:
        src = handle.read()
    names = {}
    for kind, (table, prefix) in ENUM_TABLES.items():
        found = set()
        block = re.search(r"^%s\s*=\s*\{(.*?)^\}" % table, src, re.S | re.M)
        if block:
            found.update(re.findall(r"\b%s(\w+)\s*=" % prefix, block.group(1)))
        found.update(re.findall(r"^%s\.%s(\w+)\s*=" % (table, prefix), src, re.M))
        names[kind] = found
    return names


def read_dynamic_tokens():
    tokens = set()
    for dirpath, _, files in os.walk(SCRIPTS_DIR):
        for name in files:
            if name.endswith(".lua"):
                with open(os.path.join(dirpath, name), encoding="utf-8", errors="replace") as handle:
                    src = handle.read()
                tokens.update(re.findall(r"EIDDynamicTokens\.([A-Z_]+)\s*=[^=]", src))
                tokens.update(re.findall(r"EIDDynamicTokens\[\"([A-Z_]+)\"\]\s*=[^=]", src))
    return tokens


def read_caption_glyphs():
    if not os.path.exists(CAPTION_GLYPHS_PATH):
        return None
    with open(CAPTION_GLYPHS_PATH, encoding="utf-8") as handle:
        return {int(code) for code in re.findall(r"^\s*\[(\d+)\] = \{", handle.read(), re.M)}


def caption_sources(table):
    """The strings Cronus's absorption caption can draw: its synergy lines and ui.cronus.transfer_*."""
    cronus = table.get("items", {}).get("CRONUS", {})
    yield from strings(cronus.get("synergies", {}) if isinstance(cronus, dict) else {}, "items.CRONUS.synergies")
    for path, text in strings(table.get("ui", {}).get("cronus", {}), "ui.cronus"):
        if path.startswith("ui.cronus.transfer_"):
            yield path, text


def read_languages():
    with open(INIT_PATH, encoding="utf-8") as handle:
        listed = re.search(r"Locale\.LANGUAGES\s*=\s*(\{[^}]*\})", handle.read())
    if not listed:
        sys.exit("check_locale: Locale.LANGUAGES not found in " + INIT_PATH)
    languages = lua_data.loads(listed.group(1))
    files = sorted(f[:-4] for f in os.listdir(LOCALE_DIR) if f.endswith(".lua") and f != "init.lua")
    for lang in sorted(set(files) - set(languages)):
        error("scripts/locale/%s.lua is not listed in Locale.LANGUAGES, so it never loads" % lang)
    if FALLBACK not in languages:
        error("Locale.LANGUAGES must include %s, the fallback language" % FALLBACK)
    tables = {}
    for lang in languages:
        path = os.path.join(LOCALE_DIR, lang + ".lua")
        try:
            tables[lang] = lua_data.load(path)
        except (OSError, lua_data.LuaDataError) as exc:
            error("%s.lua: %s" % (lang, exc))
    return tables


# ---- helpers ----

def strings(value, path):
    if isinstance(value, str):
        yield path, value
    elif isinstance(value, list):
        for i, inner in enumerate(value, 1):
            yield from strings(inner, "%s[%d]" % (path, i))
    elif isinstance(value, dict):
        for key, inner in value.items():
            yield from strings(inner, "%s.%s" % (path, key))


def shape_diff(english, other, path):
    """First place where other's structure differs from English's, or None."""
    if isinstance(english, dict):
        if not isinstance(other, dict):
            return "%s should be a table of named entries" % path
        missing = [k for k in english if k not in other]
        extra = [k for k in other if k not in english]
        if missing or extra:
            return "%s: %s" % (path, ", ".join(
                ["missing " + str(k) for k in missing] + ["not in English: " + str(k) for k in extra]))
        for key in english:
            found = shape_diff(english[key], other[key], "%s.%s" % (path, key))
            if found:
                return found
        return None
    if isinstance(english, list):
        if not isinstance(other, list):
            return "%s should be a list" % path
        if len(english) != len(other):
            return "%s has %d lines, English has %d" % (path, len(other), len(english))
        for i, (a, b) in enumerate(zip(english, other), 1):
            found = shape_diff(a, b, "%s[%d]" % (path, i))
            if found:
                return found
        return None
    if type(english) is not type(other):
        return "%s should be a %s like English" % (path, type(english).__name__)
    return None


def format_arguments(path, text):
    """Number of %s in a ui template; reports any other % directive."""
    count, i = 0, 0
    while True:
        i = text.find("%", i)
        if i < 0:
            return count
        directive = text[i + 1:i + 2]
        if directive == "s":
            count += 1
        elif directive != "%":
            error("%s: write a literal percent sign as %%%% (found %r)" % (path, text[i:i + 2]))
        i += 2


def english_only(path):
    return any(path == p or path.startswith(p + ".") for p in ENGLISH_ONLY)


# ---- checks ----

def main():
    registry = read_registry()
    tables = read_languages()
    if FALLBACK not in tables:
        return finish(tables, registry)
    enums = read_enums()
    dynamic = read_dynamic_tokens()
    english = tables[FALLBACK]
    en_items = english.get("items", {})

    for key, info in registry.items():
        entry = en_items.get(key)
        if not isinstance(entry, dict) or not isinstance(entry.get("name"), str):
            error("en.lua: items.%s needs a name (it is also the items.xml name)" % key)
        elif info["xml_name"] and info["xml_name"][0] != entry["name"]:
            # generate_xml.py writes the English name into items.xml, and ItemData
            # resolves the item's ID by the name in its id field: they must agree.
            error("conch_blessing_items.lua:%d: %s looks up its ID by \"%s\" but en.lua names it \"%s\""
                  % (info["xml_name"][1], key, info["xml_name"][0], entry["name"]))

    for lang, table in tables.items():
        items = table.get("items", {})
        for key, entry in items.items():
            if key not in registry:
                error("%s.lua: items.%s is not an item in ConchBlessing.ItemData" % (lang, key))
            elif not isinstance(entry, dict):
                error("%s.lua: items.%s should be a table" % (lang, key))
            else:
                for field in entry:
                    if field not in ITEM_FIELDS:
                        error("%s.lua: items.%s.%s is not a text field (%s)" % (lang, key, field, ", ".join(ITEM_FIELDS)))
        if lang != FALLBACK:
            for key, en_entry in en_items.items():
                if key not in items:
                    error("%s.lua: items.%s is missing" % (lang, key))
                    continue
                found = shape_diff(en_entry, items[key], "items." + key)
                if found:
                    error("%s.lua: %s" % (lang, found))

    for key, info in registry.items():
        lines = en_items.get(key, {}).get("synergies", {}) if isinstance(en_items.get(key), dict) else {}
        used = set()
        for line_key, line_no in info["synergies"]:
            used.add(line_key)
            if line_key not in lines:
                error("conch_blessing_items.lua:%d: %s synergy line '%s' is not in en.lua" % (line_no, key, line_key))
        for line_key in lines:
            if line_key not in used:
                error("en.lua: items.%s.synergies.%s is not used by any synergy in ItemData" % (key, line_key))

    for lang, table in tables.items():
        for path, text in strings(table, ""):
            path = path.lstrip(".")
            for kind, name in ICON.findall(text):
                if kind == "own":
                    if name not in registry:
                        error("%s.lua: %s: {own:%s} is not an ItemData key" % (lang, path, name))
                elif kind in ENUM_TABLES:
                    if enums is not None and name not in enums[kind]:
                        table_name, prefix = ENUM_TABLES[kind]
                        error("%s.lua: %s: {%s:%s} - %s.%s%s does not exist" % (lang, path, kind, name, table_name, prefix, name))
                else:
                    error("%s.lua: %s: unknown icon token {%s:%s} (use c, t, card or own)" % (lang, path, kind, name))
            if path.startswith("items."):
                for name in DYNAMIC.findall(text):
                    if name not in dynamic:
                        error("%s.lua: %s: %%%s%% is not registered in ConchBlessing.EIDDynamicTokens" % (lang, path, name))

    en_ui = dict(strings(english.get("ui", {}), "ui"))
    en_arguments = {path: format_arguments("en.lua: " + path, text) for path, text in en_ui.items()}
    for lang, table in tables.items():
        if lang == FALLBACK:
            continue
        ui = dict(strings(table.get("ui", {}), "ui"))
        for path, text in ui.items():
            if english_only(path):
                error("%s.lua: %s is English-only (Mod Config Menu reads it in English); remove it" % (lang, path))
            elif path not in en_ui:
                error("%s.lua: %s is not in en.lua" % (lang, path))
            elif format_arguments("%s.lua: %s" % (lang, path), text) != en_arguments[path]:
                error("%s.lua: %s must take as many %%s arguments as English (%d)" % (lang, path, en_arguments[path]))
        for path in en_ui:
            if not english_only(path) and path not in ui:
                error("%s.lua: %s is missing" % (lang, path))

    glyphs = read_caption_glyphs()
    if glyphs is None:
        error("%s is missing; run python generate_caption_glyphs.py" % os.path.relpath(CAPTION_GLYPHS_PATH, ROOT))
    else:
        for lang, table in tables.items():
            for path, text in caption_sources(table):
                plain = re.sub(r"\{\{.*?\}\}", "", ICON.sub("", text))
                missing = sorted({ch for ch in plain if ch >= " " and ord(ch) not in glyphs and ch not in CAPTION_FALLBACK})
                if missing:
                    error("%s.lua: %s: Cronus captions have no glyph for %s; run python generate_caption_glyphs.py"
                          % (lang, path, " ".join("%s (U+%04X)" % (ch, ord(ch)) for ch in missing)))

    return finish(tables, registry)


def finish(tables, registry):
    for message in errors:
        print(message)
    if errors:
        print("check_locale: %d problem(s)" % len(errors))
        return 1
    lines = sum(len(info["synergies"]) for info in registry.values())
    print("check_locale: OK (%s; %d items, %d synergy lines)" % (", ".join(tables), len(registry), lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
