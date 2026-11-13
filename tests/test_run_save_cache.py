"""scripts/lib/run_save_cache.lua: SaveManager's run tables kept for one game
frame and dropped whenever SaveManager may replace them."""
import pathlib
import unittest

from lupa.lua53 import LuaRuntime

ROOT = pathlib.Path(__file__).resolve().parents[1]


class RunSaveCacheTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().source = (ROOT / 'scripts/lib/run_save_cache.lua').read_text(encoding='utf-8')
        self.lua.execute(r'''
            frame=1; loadedData=true; asks=0
            runs={}; globalRun={}
            ModCallbacks={MC_POST_PLAYER_INIT=1,MC_POST_GAME_STARTED=2,MC_PRE_GAME_EXIT=3,
                MC_POST_NEW_ROOM=4,MC_POST_NEW_LEVEL=5,MC_POST_ENTITY_REMOVE=6}
            EntityType={ENTITY_PLAYER=1}
            callbacks={}; saveCallbacks={}
            function Game() return {GetFrameCount=function() return frame end} end
            function GetPtrHash(p) return p.hash end
            SM={SaveCallbacks={POST_DATA_LOAD='load',PRE_GLOWING_HOURGLASS_RESET='pre',POST_GLOWING_HOURGLASS_RESET='post'},
                IsLoaded=function() return loadedData end,
                GetRunSave=function(p) asks=asks+1
                    if not p then return globalRun end
                    runs[p.seed]=runs[p.seed] or {}; return runs[p.seed] end,
                TryGetRunSave=function(p) asks=asks+1
                    if not p then return globalRun end
                    return runs[p.seed] end}
            mod={AddCallback=function(_,id,fn) saveCallbacks[id]=fn end}
            ConchBlessing={SaveManager=SM,originalMod=mod}
            function ConchBlessing:AddCallback(id,fn) callbacks[id]=fn end
            C=load(source,'run_save_cache')()
            function player(hash,seed,kind)
                return {hash=hash,seed=seed,kind=kind or 0,GetPlayerType=function(self) return self.kind end}
            end
        ''')

    def test_global_table_is_read_once_per_frame_and_dropped_on_replacement(self):
        self.lua.execute(r'''
            local first=C.global(); assert(first==globalRun and asks==1)
            assert(C.global()==first and C.global(true)==first and asks==1,'asked again in the same frame')
            frame=2; assert(C.global()==first and asks==2,'not asked again next frame')
            globalRun={}  -- SaveManager loads a save: a new table
            saveCallbacks.load(); assert(C.global()==globalRun and asks==3,'kept the replaced table')
            for _,id in ipairs({1,2,3,4,5}) do
                globalRun={}; callbacks[id](); assert(C.global()==globalRun,'callback '..id..' kept it')
            end
            globalRun={}; saveCallbacks.post(); assert(C.global()==globalRun,'hourglass restore kept it')
            loadedData=false; assert(C.global()==nil,'answered before SaveManager loaded')
        ''')

    def test_player_saves_follow_entity_and_character_and_never_cache_a_missing_save(self):
        self.lua.execute(r'''
            local a,b=player(1,'A'),player(2,'B')
            assert(C.player(a)==nil,'a missing save was made without create')
            local made=C.player(a,true); assert(made and runs.A==made,'create did not make the save')
            local n=asks; assert(C.player(a)==made and asks==n,'asked again in the same frame')
            assert(C.player(b,true)==runs.B and C.player(b)~=made,'players share a save')
            a.kind=5; runs.A={}; assert(C.player(a)==runs.A,'a character change kept the old save')
            runs.A={}; callbacks[6](nil,a); assert(C.player(a)==runs.A,'a removed player kept its save')
        ''')

    def test_without_a_frame_nothing_is_kept(self):
        self.lua.execute(r'''
            function Game() return {} end
            local a=player(1,'A'); C.player(a,true); C.global()
            local n=asks; C.player(a); C.global(); assert(asks==n+2,'kept without a frame to key on')
        ''')


if __name__ == '__main__':
    unittest.main()
