"""The Workshop package holds only what the mod runs (user request 2026-11-10).

The packager leaves out the dev tooling (scripts/dev), modules nothing loads and
art kept for later, and strips the test hooks (`X._test = {...}`) and the lines
marked dev-only from every Lua file it stages (.github/scripts/release_lua.py).
These tests stage a real package and check what is in it."""
from pathlib import Path
import importlib.util
import re
import sys
import tempfile
import unittest
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / '.github/scripts'


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


sys.path.insert(0, str(SCRIPTS))
Release = load('release_lua', SCRIPTS / 'release_lua.py')


LONG_OPEN = re.compile(r'\[(=*)\[')
SPECIAL = re.compile(r'--|\[=*\[|["\']')


def without_comments(source):
    """Lua source with its comments removed (strings kept)."""
    out, i, n = [], 0, len(source)
    while i < n:
        m = SPECIAL.search(source, i)
        if not m:
            out.append(source[i:])
            break
        out.append(source[i:m.start()])
        i = m.start()
        if source.startswith('--', i):
            long = LONG_OPEN.match(source, i + 2)
            if long:
                i = source.index(']' + long.group(1) + ']', long.end()) + len(long.group(1)) + 2
            else:
                end = source.find('\n', i)
                i = n if end < 0 else end
            continue
        long = LONG_OPEN.match(source, i)
        if long:
            end = source.index(']' + long.group(1) + ']', long.end()) + len(long.group(1)) + 2
            out.append(source[i:end])
            i = end
            continue
        c, j = source[i], i + 1
        while source[j] != c:
            j += 2 if source[j] == '\\' else 1
        out.append(source[i:j + 1])
        i = j + 1
    return ''.join(out)


class StripTests(unittest.TestCase):
    def test_hook_tables_and_marked_lines_go_and_everything_else_stays(self):
        source = '\r\n'.join([
            'local M = {}',
            'local a = "}" .. [[ { ]] -- { in a comment',
            '',
            '-- Test hooks for the bench.',
            'M._test = {',
            '    s = "}{", long = [==[ } ]==], -- }',
            '    f = function() return { 1 } end,',
            '}',
            '-- An ordinary comment.',
            'M.live = true',
            'local dev = 1 -- dev-only',
            '-- dev-only:begin',
            'error("never shipped")',
            '-- dev-only:end',
            'return M',
            ''])
        released = Release.strip_dev_lua(source)
        self.assertEqual(released, '\r\n'.join([
            'local M = {}', 'local a = "}" .. [[ { ]] -- { in a comment', '',
            '-- An ordinary comment.', 'M.live = true', 'return M', '']))

    def test_unbalanced_markers_fail_loudly(self):
        for broken in ('-- dev-only:begin\nx = 1\n', '-- dev-only:end\n',
                       '-- dev-only:begin\n-- dev-only:begin\n-- dev-only:end\n'):
            with self.assertRaises(ValueError):
                Release.strip_dev_lua(broken)


class WorkshopPackageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        packager = load('packager', SCRIPTS / 'prepare_steam_workshop_upload.py')
        cls.content = packager.prepare_content(ROOT, Path(cls.tmp.name), 'conch_blessing')
        cls.lua_files = sorted(cls.content.rglob('*.lua'))

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def source(self, path):
        return path.read_bytes().decode('utf-8-sig')

    def test_dev_tooling_unused_modules_and_spare_art_are_left_out(self):
        for gone in ('scripts/dev', 'scripts/items/collectibles/magic_mold.lua',
                     'scripts/items/collectibles/notused', 'scripts/lib/damage_utils.lua',
                     'scripts/lib/weapon_fire.lua', 'scripts/rooms/native_gallery_rooms.lua',
                     'resources/gfx/items/collectibles/notused', 'resources/gfx/effects/notused'):
            self.assertFalse((self.content / gone).exists(), gone)
        for kept in ('main.lua', 'metadata.xml', 'scripts/conch_blessing_core.lua',
                     'scripts/items/familiars/hermit_crab.lua', 'scripts/lib/save_manager.lua',
                     'content/items.xml', 'resources/gfx/hermit_crab.anm2'):
            self.assertTrue((self.content / kept).exists(), kept)

    def test_every_staged_lua_file_compiles(self):
        lua = LuaRuntime()
        check = lua.eval('function(s, n) local f, e = load(s, n) return e end')
        errors = [(str(p.relative_to(self.content)), check(self.source(p), str(p))) for p in self.lua_files]
        self.assertEqual([e for e in errors if e[1]], [])

    def test_no_test_hooks_or_dev_code_are_shipped(self):
        offenders = []
        for path in self.lua_files:
            text = self.source(path)
            code = without_comments(text)
            name = str(path.relative_to(self.content))
            if re.search(r'\._test\s*=', code):
                offenders.append((name, '_test table'))
            if 'dev-only' in text:
                offenders.append((name, 'dev-only marker'))
            for word in ('scripts.dev', 'scripts/dev', 'ConchBlessingOptionalRequire', 'DevOrigins',
                         'ConchBlessingLoadingModule', '__CBQ__'):
                if word in code and not name.endswith('save_manager.lua'):
                    offenders.append((name, word))
        self.assertEqual(offenders, [])

    def test_the_repository_keeps_its_hooks_and_dev_lines(self):
        core = (ROOT / 'scripts/conch_blessing_core.lua').read_text(encoding='utf-8-sig')
        self.assertIn('ConchBlessingOptionalRequire("scripts.dev.init")', core)
        self.assertIn('M._test = {', (ROOT / 'scripts/items/familiars/hermit_crab.lua').read_text(encoding='utf-8'))
        self.assertNotIn('__CBQ__', core, 'the save-file command queue lives in scripts/dev')

    def test_every_staged_lua_file_is_loaded_by_the_mod(self):
        files = {p.relative_to(self.content).with_suffix('').as_posix() for p in self.lua_files}
        named = re.compile(r'''(?:(?i:require)|include)\s*\(?\s*["']([^"']+)["']'''
                           r'''|pcall\(\s*require\s*,\s*["']([^"']+)["']'''
                           r'''|\b(?:script|path)\s*=\s*["'](scripts[./][^"']+)["']''')
        seen, stack = set(), ['main']
        while stack:
            module = stack.pop()
            if module in seen or module not in files:
                continue
            seen.add(module)
            code = without_comments(self.source(self.content / (module + '.lua')))
            for groups in named.findall(code):
                stack.append(next(g for g in groups if g).replace('.', '/'))
            if module == 'scripts/locale/init':  # loads scripts.locale.<lang> by name
                stack.extend(f for f in files if f.startswith('scripts/locale/'))
        self.assertEqual(sorted(files - seen), [], 'staged Lua files nothing loads')

    def test_optional_require_returns_nil_only_for_that_missing_module(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        main = (ROOT / 'main.lua').read_text(encoding='utf-8-sig')
        start = main.index('local gameRequire = require')
        stop = main.index('ConchBlessingRequire("scripts.conch_blessing_core")')
        files = {'scripts/present': 'return {ok=true}',
                 'scripts/broken': 'error("boom")',
                 'scripts/needs': 'return ConchBlessingRequire("scripts.gone")'}
        lua.globals().files = lua.table_from(files)
        lua.execute(r"""
            package=nil
            include=function(path)
                local src=files[path]
                if not src then return "no file '" .. path .. ".lua'" end
                return assert(load(src))()
            end
        """)
        lua.execute(main[start:stop])
        self.assertTrue(lua.eval('ConchBlessingOptionalRequire("scripts.present").ok'))
        self.assertIsNone(lua.eval('ConchBlessingOptionalRequire("scripts.dev.init")'))
        for name in ('scripts.broken', 'scripts.needs'):
            ok, err = lua.eval(f'pcall(ConchBlessingOptionalRequire, "{name}")')
            self.assertFalse(ok, f'{name}: a real error is raised, not hidden')
            self.assertTrue(err, name)


if __name__ == '__main__':
    unittest.main()
