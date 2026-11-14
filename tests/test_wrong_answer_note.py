"""오답노트 (Wrong Answer Note): production Lua with engine doubles.

Each hit writes down the kind of enemy that dealt it; the holder's attacks deal
+50% (x trinket multiplier) to that kind, and a floor passed without a hit adds
+25% (x multiplier) against every enemy. These doubles cannot show the engine's
damage pipeline or drawing; `cb test wrong_answer_note` covers those in game.
"""
from pathlib import Path
import re
import unittest
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]

HARNESS = r"""
package=nil
REPENTOGON={}
EntityType={ENTITY_FIREPLACE=33,ENTITY_SLOT=6}
EntityFlag={FLAG_FRIENDLY=1<<29}
DamageFlag={DAMAGE_RED_HEARTS=1<<5}
ModCallbacks={MC_ENTITY_TAKE_DMG=11}
CallbackPriority={LATE=100}
local V={}; V.__index=V
Vector=setmetatable({},{__call=function(_,x,y) return setmetatable({X=x,Y=y},V) end})
V.__add=function(a,b) return Vector(a.X+b.X,a.Y+b.Y) end
Vector.Zero=Vector(0,0)
drawn={}; paused=false
function KColor(r,g,b,a) return {R=r,G=g,B=b,A=a} end
function Font()
    local f={}
    function f:Load() end
    function f:IsLoaded() return true end
    function f:GetStringWidth(s) return #s*4 end
    function f:DrawStringScaled(text,x,y,sx,sy,color) drawn[#drawn+1]={text=text,color=color} end
    return f
end
local nextHash=0
function GetPtrHash(e) return e.hash end
function EntityPtr(e) return {Ref=e} end
function entity(fields)
    nextHash=nextHash+1
    local e={hash=nextHash,data={},exists=true,Position=Vector(0,0),PositionOffset=Vector(0,0),Size=10,
        SpriteScale=Vector(1,1),flags=0}
    for k,v in pairs(fields or {}) do e[k]=v end
    function e:Exists() return self.exists end
    function e:ToNPC() return self.isNpc and self or nil end
    function e:ToPlayer() return self.isPlayer and self or nil end
    function e:HasEntityFlags(f) return self.flags&f~=0 end
    function e:IsEnemy() return self.enemy~=false end
    function e:IsDead() return self.dead==true end
    return e
end
function newPlayer(mult)
    local p=entity({isPlayer=true,mult=mult or 1,save={}})
    function p:IsCoopGhost() return false end
    return p
end
function newNpc(t,v,fields) local n=entity(fields or {}); n.isNpc=true; n.Type=t; n.Variant=v or 0; return n end
function shot(spawner) return entity({Type=9,Variant=0,SpawnerEntity=spawner}) end
function ref(e) return {Entity=e,Type=e and e.Type or 0,Variant=e and e.Variant or 0} end
players={}; roomEntities={}
local game={GetNumPlayers=function() return #players end,IsPaused=function() return paused end}
Game=function() return game end
Isaac={GetPlayer=function(i) return players[i+1] end,GetRoomEntities=function() return roomEntities end,
    WorldToScreen=function(p) return p end,GetTrinketIdByName=function() return 700 end}
saveCallbacks={}; hitHandlers={}
ConchBlessing={printError=function() end,printDebug=function() end,
    AddCallback=function() end,AddPriorityCallback=function(_,id,prio,fn) lateDamage=fn end,
    ItemData={WRONG_ANSWER_NOTE={id=700}},
    originalMod={__SAVEMANAGER_UNIQUE_KEY='test',AddCallback=function(_,id,fn) saveCallbacks[id]=fn end},
    minuschain={noHit=function(p) return not p.hitThisFloor end}}
local SaveManager={GetRunSave=function(p) return p.save end,
    SaveCallbacks={PRE_FLOOR_DATA_RESET='PRE_FLOOR',POST_DATA_LOAD='POST_LOAD'}}
ConchBlessing.SaveManager=SaveManager
local Hits={register=function(key,fn) hitHandlers[key]=fn end,
    counts=function(flags) return (flags or 0)&DamageFlag.DAMAGE_RED_HEARTS==0 end,
    watchFloor=function() end,markBroken=function() end,recover=function() end}
local Provenance={getSourceEntity=function(source,extra) return (extra and extra.Entity) or (source and source.Entity) end,
    getPlayerOwner=function(e)
        for _=1,12 do
            if not e then return nil end
            if e.isPlayer then return e end
            e=e.SpawnerEntity or e.Parent
        end
    end}
local stubs={
    ['scripts.lib.player_hits']=Hits,
    ['scripts.lib.trinket_utils']={getMultiplier=function(p,id) assert(id==700); return p.mult end},
    ['scripts.lib.damage_provenance']=Provenance,
    ['scripts.lib.enemy_utils']=dofile(root..'/scripts/lib/enemy_utils.lua'),
    ['scripts.lib.save_manager']=SaveManager,
}
require=function(name) return assert(stubs[name],'unexpected require '..name) end
M=dofile(root..'/scripts/items/trinkets/wrong_answer_note.lua')
T=M._test
function hit(p,source,flags) return hitHandlers.WRONG_ANSWER_NOTE(nil,p,1,flags or 0,source,30) end
function damage(target,attacker,amount)
    local r=lateDamage(nil,target,amount or 10,0,ref(attacker),0)
    return r and r.Damage or amount or 10
end
"""


class WrongAnswerNoteTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(HARNESS)

    def run_lua(self, script):
        self.lua.execute(script)

    def test_a_hit_writes_down_the_enemy_behind_it(self):
        self.run_lua(r'''
            local p=newPlayer(1); players={p}; M.onGameStarted()
            local gaper=newNpc(10,0)
            assert(hit(p,ref(gaper))==true and p.save.wrongAnswerNote.kinds['10.0']==1, 'contact')
            local shooter=newNpc(27,1)
            assert(hit(p,ref(shot(shooter)))==true and p.save.wrongAnswerNote.kinds['27.1']==1, 'its projectile')
            -- the shooter died as the shot landed: the reference still names it
            assert(hit(p,{Type=9,Variant=0,SpawnerType=27,SpawnerVariant=1})==true
                and p.save.wrongAnswerNote.kinds['27.1']==2, 'a dead spawner')
        ''')

    def test_hits_with_no_enemy_behind_them_write_nothing(self):
        self.run_lua(r'''
            local p=newPlayer(1); players={p}; M.onGameStarted()
            assert(hit(p,ref(entity({Type=4,SpawnerEntity=p})))==nil, 'own bomb')
            assert(hit(p,ref(newNpc(33,0)))==nil, 'a fireplace is furniture')
            assert(hit(p,{Type=1000,Variant=0,SpawnerType=33,SpawnerVariant=0})==nil, 'fire from a gone fireplace')
            assert(hit(p,{Type=0,Variant=0})==nil, 'spikes')
            assert(hit(p,ref(newNpc(10,0,{flags=EntityFlag.FLAG_FRIENDLY})))==nil, 'a friendly one')
            assert(next(p.save.wrongAnswerNote and p.save.wrongAnswerNote.kinds or {})==nil)
        ''')

    def test_only_a_holder_counts_real_hits_after_game_start(self):
        self.run_lua(r'''
            local p=newPlayer(1); players={p}
            assert(hit(p,ref(newNpc(10,0)))==nil and p.save.wrongAnswerNote==nil, 'before game start')
            M.onGameStarted()
            p.mult=0
            assert(hit(p,ref(newNpc(10,0)))==nil, 'not holding')
            p.mult=1
            assert(hit(p,ref(newNpc(10,0)),DamageFlag.DAMAGE_RED_HEARTS)==nil, 'self-damage')
            assert(next(p.save.wrongAnswerNote and p.save.wrongAnswerNote.kinds or {})==nil)
        ''')

    def test_the_holders_attacks_hit_noted_kinds_harder(self):
        self.run_lua(r'''
            local p=newPlayer(1); local other=newPlayer(1); players={p,other}; M.onGameStarted()
            local gaper, fly=newNpc(10,0), newNpc(18,0)
            hit(p,ref(gaper))
            assert(damage(newNpc(10,0),p)==15, 'noted kind +50%')
            assert(damage(newNpc(10,1),p)==10, 'another variant')
            assert(damage(fly,p)==10, 'another kind')
            assert(damage(newNpc(10,0),entity({Type=2,SpawnerEntity=p}))==15, 'its tear')
            assert(damage(newNpc(10,0),other)==10, 'another player wrote nothing')
            hit(p,ref(gaper))
            assert(damage(newNpc(10,0),p)==20, 'a second hit stacks')
        ''')

    def test_the_trinket_multiplier_scales_both_steps(self):
        self.run_lua(r'''
            local p=newPlayer(2); players={p}; M.onGameStarted()
            hit(p,ref(newNpc(10,0)))
            assert(damage(newNpc(10,0),p)==20, 'golden or Mom\'s Box: +100%')
            p.mult=3
            assert(damage(newNpc(10,0),p)==25, 'both: +150%')
            p.mult=0
            assert(damage(newNpc(10,0),p)==10, 'dropped: nothing, though the note is kept')
            assert(p.save.wrongAnswerNote.kinds['10.0']==1)
        ''')

    def test_a_clean_floor_adds_against_every_enemy(self):
        self.run_lua(r'''
            local p=newPlayer(1); local q=newPlayer(1); players={p,q}; M.onGameStarted()
            q.hitThisFloor=true
            saveCallbacks.PRE_FLOOR(); M.onNewLevel()
            assert(p.save.wrongAnswerNote.floors==1 and (q.save.wrongAnswerNote or {}).floors~=1)
            assert(damage(newNpc(18,0),p)==12.5, 'any enemy +25%')
            hit(p,ref(newNpc(10,0)))
            assert(damage(newNpc(10,0),p)==17.5, 'both bonuses add')
            local gold=false
            for _,m in ipairs(T.markers()) do if m.hash==p.hash and m.text=='+25%' then gold=true end end
            assert(gold, 'a gold +25% over the holder')
            p.mult=0; saveCallbacks.PRE_FLOOR(); M.onNewLevel()
            assert(p.save.wrongAnswerNote.floors==1, 'not holding at floor end')
        ''')

    def test_markers_pop_over_noted_kinds_and_fade(self):
        self.run_lua(r'''
            local p=newPlayer(1); players={p}; M.onGameStarted()
            hit(p,ref(newNpc(10,0)))
            local gaper, fly=newNpc(10,0), newNpc(18,0)
            M.onNpcInit(nil,gaper); M.onNpcInit(nil,fly)
            local list=T.markers()
            assert(#list==1 and list[1].hash==gaper.hash and list[1].text=='+50%')
            M.onRender()
            assert(drawn[1].text=='+50%' and drawn[1].color.R==1)
            paused=true; for _=1,200 do M.onRender() end
            assert(#T.markers()==1, 'frozen while paused')
            paused=false; for _=1,200 do M.onRender() end
            assert(#T.markers()==0, 'gone after its moment')
            M.onNpcInit(nil,newNpc(10,0)); M.onNewRoom()
            assert(#T.markers()==0, 'a new room clears them')
        ''')

    def test_a_new_hit_updates_the_markers_of_that_kind_in_the_room(self):
        self.run_lua(r'''
            local p=newPlayer(1); players={p}; M.onGameStarted()
            local a=newNpc(10,0); roomEntities={a, newNpc(18,0)}
            hit(p,ref(newNpc(10,0)))
            hit(p,ref(newNpc(10,0)))
            local list=T.markers()
            assert(#list==1 and list[1].hash==a.hash and list[1].text=='+100%')
        ''')

    def test_a_luamod_reload_mid_run_starts_it(self):
        self.run_lua(r'''
            local p=newPlayer(1); players={p}
            saveCallbacks.POST_LOAD(nil,{},false)
            assert(not T.started())
            saveCallbacks.POST_LOAD(nil,{},true)
            assert(T.started() and hit(p,ref(newNpc(10,0)))==true)
        ''')

    def test_registry_locale_and_upgrade_slot(self):
        items = (ROOT / 'scripts/conch_blessing_items.lua').read_text(encoding='utf-8')
        start = items.index('WRONG_ANSWER_NOTE = {')
        row = items[start:items.index('\n    },', start)]
        for needle in ('type = "trinket"', 'TRINKET_PERFECTION', 'flag = "neutral"', 'stackable = true',
                       'specials = { normal = { 100, 50 }, moms_box = { 100, 50 }, both = { 150, 75 } }'):
            self.assertIn(needle, row)
        # the Magic Conch's other Perfection answers keep their slots
        flags = re.findall(r'TRINKET_PERFECTION, type = "trinket" \},\s*flag = "(\w+)"', items)
        self.assertEqual(sorted(flags), ['negative', 'neutral', 'positive'])
        xml = (ROOT / 'content/items.xml').read_text(encoding='utf-8')
        self.assertIn('name="Wrong Answer Note" gfx="wrong_answer_note.png"', xml)
        self.assertTrue((ROOT / 'resources/gfx/items/trinkets/wrong_answer_note.png').exists())
        catalog = (ROOT / 'scripts/upgrade_visual_catalog.lua').read_text(encoding='utf-8')
        self.assertIn('{ key = "WRONG_ANSWER_NOTE" }', catalog)
        kr = (ROOT / 'scripts/locale/kr.lua').read_text(encoding='utf-8')
        entry = kr[kr.index('WRONG_ANSWER_NOTE = {'):]
        self.assertLess(entry.index('50%'), entry.index('25%'), 'golden numbers swap in text order')


if __name__ == '__main__':
    unittest.main()
