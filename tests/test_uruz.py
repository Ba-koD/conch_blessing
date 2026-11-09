"""Uruz (Tyrfing's rune): production Lua with engine doubles.

Used in a room, every monster that dies there gives the user +0.05 damage for
good (each further use there adds the reward again); a new room ends it and
hits take nothing away. `conch_test uruz` covers real kills and stats in game.
"""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]

HARNESS = r"""
package=nil
EntityType={ENTITY_FIREPLACE=33}
EntityFlag={FLAG_FRIENDLY=1<<29}
CacheFlag={CACHE_DAMAGE=1}
ModCallbacks={MC_USE_CARD=5,MC_POST_NPC_DEATH=29,MC_EVALUATE_CACHE=8,MC_POST_NEW_ROOM=19,
    MC_POST_GAME_STARTED=15,MC_PRE_GAME_EXIT=17}
local nextHash=0
function GetPtrHash(e) return e.hash end
function EntityPtr(e) return setmetatable({},{__index=function(_,k) if k=='Ref' and e.exists then return e end end}) end
function entity(fields)
    nextHash=nextHash+1
    local e={hash=nextHash,exists=true,flags=0}
    for k,v in pairs(fields or {}) do e[k]=v end
    function e:Exists() return self.exists end
    function e:ToPlayer() return self.isPlayer and self or nil end
    function e:HasEntityFlags(f) return self.flags&f~=0 end
    function e:IsEnemy() return self.enemy~=false end
    function e:IsDead() return self.dead==true end
    return e
end
applied={}
function newPlayer()
    local p=entity({isPlayer=true,save={},evaluated=0})
    function p:IsCoopGhost() return false end
    function p:AddCacheFlags() end
    function p:EvaluateItems() self.evaluated=self.evaluated+1 end
    return p
end
function npc(t) return entity({Type=t or 10,Variant=0}) end
players={}
Game=function() return {GetNumPlayers=function() return #players end} end
Isaac={GetPlayer=function(i) return players[i+1] end}
callbacks={}; saveCallbacks={}; loaded=true
ConchBlessing={printError=function() end,printDebug=function() end,
    PocketData={URUZ={id=77}},
    stats={damage={applyAddition=function(p,amount) applied[p.hash]=amount end}},
    originalMod={__SAVEMANAGER_UNIQUE_KEY='test',AddCallback=function(_,id,fn) saveCallbacks[id]=fn end}}
function ConchBlessing:AddCallback(id,fn,param) callbacks[id]={fn=fn,param=param} end
ConchBlessing.SaveManager={GetRunSave=function(p) return p.save end,IsLoaded=function() return loaded end,
    SaveCallbacks={POST_DATA_LOAD='POST_LOAD'}}
local stubs={['scripts.lib.enemy_utils']=dofile(root..'/scripts/lib/enemy_utils.lua')}
require=function(name) return assert(stubs[name],'unexpected require '..name) end
M=dofile(root..'/scripts/items/cards/uruz.lua')
T=M._test
function use(p) M.onUseCard(nil,77,p) end
function die(n) M.onNpcDeath(nil,n or npc()) end
function damage(p) applied[p.hash]=nil; M.onEvaluateCache(nil,p,CacheFlag.CACHE_DAMAGE); return applied[p.hash] or 0 end
function near(a,b) return math.abs(a-b)<1e-9 end
"""


class UruzTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(HARNESS)

    def run_lua(self, script):
        self.lua.execute(script)

    def test_registers_its_card_callbacks(self):
        self.run_lua(r'''
            assert(callbacks[ModCallbacks.MC_USE_CARD].param==77)
            assert(callbacks[ModCallbacks.MC_EVALUATE_CACHE].param==CacheFlag.CACHE_DAMAGE)
            for _,id in ipairs({'MC_POST_NPC_DEATH','MC_POST_NEW_ROOM','MC_POST_GAME_STARTED','MC_PRE_GAME_EXIT'}) do
                assert(callbacks[ModCallbacks[id]], id)
            end
        ''')

    def test_each_monster_death_after_using_it_gives_005_for_good(self):
        self.run_lua(r'''
            local p=newPlayer(); players={p}; M.onGameStarted()
            die()
            assert(damage(p)==0, 'nothing before the rune')
            use(p); die(); die()
            assert(near(damage(p),0.10) and p.save.uruz.kills==2, tostring(damage(p)))
            M.onUseCard(nil,12,p); die()
            assert(near(damage(p),0.15), 'another card is not Uruz')
        ''')

    def test_a_second_use_in_the_room_doubles_the_reward(self):
        self.run_lua(r'''
            local p=newPlayer(); players={p}; M.onGameStarted()
            use(p); use(p)
            assert(M.uses(p)==2)
            die()
            assert(near(damage(p),0.10))
        ''')

    def test_a_new_room_ends_it_and_keeps_what_was_earned(self):
        self.run_lua(r'''
            local p=newPlayer(); players={p}; M.onGameStarted()
            use(p); die(); M.onNewRoom(); die()
            assert(M.uses(p)==0 and near(damage(p),0.05))
        ''')

    def test_only_monsters_count_and_only_acting_users_earn(self):
        self.run_lua(r'''
            local p=newPlayer(); local q=newPlayer(); players={p,q}; M.onGameStarted()
            use(p)
            die(npc(33)); die(entity({Type=10,Variant=0,flags=EntityFlag.FLAG_FRIENDLY}))
            assert(damage(p)==0, 'furniture and friends are no kills')
            die()
            assert(near(damage(p),0.05) and damage(q)==0, 'a co-op partner earns nothing')
            p.dead=true; die()
            assert(near(damage(p),0.05), 'a dead user earns nothing')
            p.dead=false; p.exists=false; die()
            assert(next(T.active())==nil, 'a removed user leaves the room\'s list')
        ''')

    def test_nothing_is_read_before_the_run_save_is_ready(self):
        self.run_lua(r'''
            local p=newPlayer(); players={p}
            p.save.uruz={damage=0.3,kills=6}
            assert(damage(p)==0, 'before game start')
            loaded=false; M.onGameStarted()
            assert(damage(p)==0, 'SaveManager not loaded yet')
            loaded=true; M.onGameStarted()
            assert(near(damage(p),0.3) and p.evaluated>0, 'Continue re-evaluates once readable')
        ''')

    def test_a_luamod_reload_mid_run_starts_it(self):
        self.run_lua(r'''
            local p=newPlayer(); players={p}
            saveCallbacks.POST_LOAD(nil,{},false)
            assert(not T.started())
            saveCallbacks.POST_LOAD(nil,{},true)
            assert(T.started())
            use(p); die()
            assert(near(damage(p),0.05))
        ''')


if __name__ == '__main__':
    unittest.main()
