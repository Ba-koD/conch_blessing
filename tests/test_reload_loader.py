"""main.lua's loader keeps `luamod conch_blessing` working (offline doubles only).

The game's require keeps a module for the whole session, so a reload would rerun
main.lua against cached modules and leave the mod without callbacks. Every file
of this mod loads through ConchBlessingRequire instead: include reruns the file,
and the cache lasts one load. A real reload is checked in game through the
runtime queue (AGENTS.md, Verification).
"""
import re
import unittest
from pathlib import Path

from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
HEADER = 'local require = ConchBlessingRequire or require -- reloadable loader, see main.lua'
# Vendored or retired files keep their own loading: isaacscript-common bundles a
# private require, save_manager only loads the game's json, and the retired
# custom-placement backend never runs.
EXEMPT = {'scripts/lib/isaacscript-common.lua', 'scripts/lib/save_manager.lua',
          'scripts/rooms/native_gallery_rooms.lua'}
CALLS_REQUIRE = re.compile(r'(^|[^\w.:])require\s*\(', re.M)


def runtime_files():
    for path in sorted((ROOT / 'scripts').rglob('*.lua')):
        rel = path.relative_to(ROOT).as_posix()
        if rel not in EXEMPT:
            yield rel, path.read_text(encoding='utf-8-sig')


class ReloadLoaderTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            files={}; runs={}; gameLoads={}
            -- The game's include: syntax and runtime errors raise, but a
            -- missing file returns the search's "no file" list.
            function include(path)
                runs[path]=(runs[path] or 0)+1
                local source=files[path]
                if not source then return string.char(10, 9).. "no file 'mods/conch_blessing/"..path..".lua'" end
                return assert(load(source, path))()
            end
            -- The game's require: one instance per session.
            local cache={}
            require=function(name)
                gameLoads[#gameLoads+1]=name
                cache[name]=cache[name] or {name=name}
                return cache[name]
            end
            function reload()
                ConchBlessingRequire=nil
                files['scripts/conch_blessing_core']=coreSource
                assert(load(mainSource, 'main.lua'))()
            end
        ''')
        main = (ROOT / 'main.lua').read_text(encoding='utf-8-sig')
        self.lua.globals().mainSource = main
        self.lua.globals().coreSource = '''
            local require = ConchBlessingRequire or require
            Shared = require("scripts.lib.shared")
            SharedSlash = require("scripts/lib/shared")
            Json = require("json")
            Core = (Core or 0) + 1
        '''
        self.lua.execute('''
            files['scripts/lib/shared']='return {made={}}'
        ''')

    def test_every_load_runs_each_module_once_and_a_reload_runs_it_again(self):
        self.lua.execute('''
            reload()
            local first=Shared
            assert(Core==1 and runs['scripts/conch_blessing_core']==1 and runs['scripts/lib/shared']==1)
            assert(Shared==SharedSlash, 'one instance per load whichever separator names it')
            reload()
            assert(Core==2 and runs['scripts/conch_blessing_core']==2 and runs['scripts/lib/shared']==2)
            assert(Shared~=first, 'a reload builds a fresh module')
        ''')

    def test_modules_that_are_not_this_mods_come_from_the_game(self):
        self.lua.execute('''
            reload()
            assert(Json.name=='json' and gameLoads[#gameLoads]=='json' and runs['json']==nil)
        ''')

    def test_nil_return_errors_and_self_requiring_modules_behave_like_require(self):
        self.lua.execute('''
            reload()
            files['scripts/lib/plain']='Plain=(Plain or 0)+1'
            assert(ConchBlessingRequire('scripts.lib.plain')==true and ConchBlessingRequire('scripts.lib.plain')==true)
            assert(Plain==1, 'a module returning nothing still loads once')
            files['scripts/lib/broken']='error("boom")'
            local ok,err=pcall(ConchBlessingRequire,'scripts.lib.broken')
            assert(not ok and tostring(err):find('boom'))
            files['scripts/lib/broken']='return 7'
            assert(ConchBlessingRequire('scripts.lib.broken')==7, 'a failed load can be retried')
            files['scripts/lib/loop']='return ConchBlessingRequire("scripts.lib.loop")'
            ok,err=pcall(ConchBlessingRequire,'scripts.lib.loop')
            assert(not ok and tostring(err):find('requires itself'))
            ok,err=pcall(ConchBlessingRequire,'scripts.lib.missing')
            assert(not ok and tostring(err):find("module 'scripts.lib.missing' not found",1,true), tostring(err))
            assert(tostring(err):find('no file',1,true))
            files['scripts/lib/missing']='return 9'
            assert(ConchBlessingRequire('scripts.lib.missing')==9, 'a missing module is not cached')
            files['scripts/lib/text']='return "plain text"'
            assert(ConchBlessingRequire('scripts.lib.text')=='plain text', 'an ordinary string value still loads')
        ''')

    def test_every_runtime_file_that_requires_uses_the_reloadable_loader(self):
        missing = [rel for rel, source in runtime_files()
                   if CALLS_REQUIRE.search(source) and source.splitlines()[0] != HEADER]
        self.assertEqual(missing, [], 'add the loader header as the first line')
        main = (ROOT / 'main.lua').read_text(encoding='utf-8-sig')
        self.assertNotRegex(main, r'(^|[^\w.:])require\s*\(\s*"scripts', 'main.lua loads the core through the loader')


if __name__ == '__main__':
    unittest.main()
