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
REPENTOGON={Real=true}
EntityType={ENTITY_FIREPLACE=33,ENTITY_SLOT=6}
EntityFlag={FLAG_FRIENDLY=1<<29}
DamageFlag={DAMAGE_RED_HEARTS=1<<5}
ModCallbacks={MC_ENTITY_TAKE_DMG=11}
CallbackPriority={LATE=100}
local V={}; V.__index=V
Vector=setmetatable({},{__call=function(_,x,y) return setmetatable({X=x,Y=y},V) end})
V.__add=function(a,b) return Vector(a.X+b.X,a.Y+b.Y) end
Vector.Zero=Vector(0,0)
drawn={}; paused=false; frame=0; showingIcons=false
function KColor(r,g,b,a) return {R=r,G=g,B=b,A=a} end
-- A sprite double with REPENTOGON's layer frame data: each layer {y, pivot, scale, height, visible}.
function layeredSprite(layers)
    local s={}
    function s:GetLayerCount() return #layers end
    function s:GetLayer(id)
        local l=layers[id+1]
        return {IsVisible=function() return l.layerVisible~=false end,
            GetSize=function() return Vector(1,l.layerScale or 1) end,GetPos=function() return Vector(0,l.shift or 0) end}
    end
    function s:GetLayerFrameData(id)
        local l=layers[id+1]
        return {GetPos=function() return Vector(0,l.y) end,GetPivot=function() return Vector(0,l.pivot) end,
            GetScale=function() return Vector(1,l.scale or 1) end,GetHeight=function() return l.height or 32 end,
            IsVisible=function() return l.visible~=false end}
    end
    return s
end
function Font()
    local f={}
    function f:Load() end
    function f:IsLoaded() return true end
    function f:GetStringWidth(s) return #s*4 end
    function f:DrawStringScaled(text,x,y,sx,sy,color) drawn[#drawn+1]={text=text,color=color,y=y} end
    return f
end
local nextHash=0
function GetPtrHash(e) return e.hash end
function EntityPtr(e) return {Ref=e} end
function entity(fields)
    nextHash=nextHash+1
    local e={hash=nextHash,data={},exists=true,Position=Vector(100,200),PositionOffset=Vector(0,0),Size=10,
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
local game={GetNumPlayers=function() return #players end,IsPaused=function() return paused end,
    GetFrameCount=function() return frame end}
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
    watchFloor=function() end,markBroken=function() end,recover=function() end,
    iconsShowing=function() return showingIcons end}
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
    ['scripts.lib.run_save_cache']={player=function(p) return p.save end},
}
require=function(name) return assert(stubs[name],'unexpected require '..name) end
M=dofile(root..'/scripts/items/trinkets/wrong_answer_note.lua')
T=M._test
function hit(p,source,flags) return hitHandlers.WRONG_ANSWER_NOTE(nil,p,1,flags or 0,source,30) end
function render(n) for _=1,n or 1 do frame=frame+1; drawn={}; M.onRender() end end
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
            assert(hit(p,ref(gaper))==true and p.save.wrongAnswerNote.kinds['10.0']==0.5, 'contact')
            local shooter=newNpc(27,1)
            assert(hit(p,ref(shot(shooter)))==true and p.save.wrongAnswerNote.kinds['27.1']==0.5, 'its projectile')
            -- the shooter died as the shot landed: the reference still names it
            assert(hit(p,{Type=9,Variant=0,SpawnerType=27,SpawnerVariant=1})==true
                and p.save.wrongAnswerNote.kinds['27.1']==1, 'a dead spawner')
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

    def test_each_step_keeps_the_worth_of_its_moment(self):
        self.run_lua(r'''
            local p=newPlayer(1); players={p}; M.onGameStarted()
            hit(p,ref(newNpc(10,0)))
            assert(damage(newNpc(10,0),p)==15, 'one copy: +50%')
            p.mult=2
            assert(damage(newNpc(10,0),p)==15, 'made golden later: the earlier hit stays +50%')
            hit(p,ref(newNpc(10,0)))
            assert(damage(newNpc(10,0),p)==25, 'a hit while golden adds +100%')
            p.mult=3; hit(p,ref(newNpc(10,0)))
            assert(damage(newNpc(10,0),p)==40, 'golden and Mom box: +150%')
            p.mult=1
            assert(damage(newNpc(10,0),p)==40, 'losing the golden copy shrinks nothing')
            p.mult=0
            assert(damage(newNpc(10,0),p)==10, 'dropped: nothing, though the note is kept')
            assert(p.save.wrongAnswerNote.kinds['10.0']==3)
        ''')

    def test_a_clean_floor_adds_against_every_enemy(self):
        self.run_lua(r'''
            local p=newPlayer(1); local q=newPlayer(1); players={p,q}; M.onGameStarted()
            q.hitThisFloor=true
            saveCallbacks.PRE_FLOOR(); M.onNewLevel()
            assert(p.save.wrongAnswerNote.floors==1 and p.save.wrongAnswerNote.all==0.25
                and (q.save.wrongAnswerNote or {}).floors~=1)
            assert(damage(newNpc(18,0),p)==12.5, 'any enemy +25%')
            hit(p,ref(newNpc(10,0)))
            assert(damage(newNpc(10,0),p)==17.5, 'both bonuses add')
            assert(T.shownText(p)=='+25%' and T.shownText(q)==nil, 'a gold +25% over the holder only')
            -- the multiplier at the floor's end sets that floor's worth
            p.hitThisFloor=false; p.mult=2; saveCallbacks.PRE_FLOOR(); p.mult=1; M.onNewLevel()
            assert(p.save.wrongAnswerNote.floors==2 and p.save.wrongAnswerNote.all==0.75, 'a golden floor: +50%')
            p.mult=0; saveCallbacks.PRE_FLOOR(); M.onNewLevel()
            assert(p.save.wrongAnswerNote.floors==2, 'not holding at floor end')
        ''')

    def test_markers_stay_over_noted_kinds(self):
        self.run_lua(r'''
            local p=newPlayer(1); players={p}; M.onGameStarted()
            hit(p,ref(newNpc(10,0)))
            local gaper, fly=newNpc(10,0), newNpc(18,0)
            M.onNpcInit(nil,gaper); M.onNpcInit(nil,fly)
            assert(T.shownText(gaper)=='+50%' and T.shownText(fly)==nil)
            render()
            assert(#drawn==1 and drawn[1].text=='+50%' and drawn[1].color.R==1 and drawn[1].color.G<0.5)
            local popped=drawn[1].y
            render(300)
            assert(#drawn==1 and drawn[1].text=='+50%' and drawn[1].color.A==1, 'still there, settled')
            assert(drawn[1].y>popped, 'it dropped into place')
            paused=true; render(5); paused=false
            assert(#drawn==1, 'drawn while paused')
            p.mult=0; render()
            assert(#drawn==0, 'nobody holds a note')
            p.mult=1; gaper.dead=true; render()
            assert(#drawn==0 and T.tracked()[gaper.hash]==nil, 'a dead enemy drops its marker')
            -- a new room tracks what is in it
            local inRoom=newNpc(10,0); roomEntities={inRoom}
            M.onNewRoom(); render()
            assert(#drawn==1 and T.shownText(inRoom)=='+50%' and T.tracked()[fly.hash]==nil)
            inRoom.flags=EntityFlag.FLAG_FRIENDLY; render()
            assert(#drawn==0, 'a friendly one shows nothing')
        ''')

    def test_a_new_hit_grows_the_markers_of_that_kind(self):
        self.run_lua(r'''
            local p=newPlayer(1); players={p}; M.onGameStarted()
            local a=newNpc(10,0); roomEntities={a, newNpc(18,0)}; M.onNewRoom()
            hit(p,ref(newNpc(10,0)))
            render(20)
            hit(p,ref(newNpc(10,0)))
            assert(T.shownText(a)=='+100%')
            render()
            assert(#drawn==1 and drawn[1].text=='+100%' and drawn[1].color.A<1, 'it pops in again')
        ''')

    def test_the_gold_number_stays_and_makes_room_for_hit_icons(self):
        self.run_lua(r'''
            local p=newPlayer(1); players={p}; M.onGameStarted()
            saveCallbacks.PRE_FLOOR(); M.onNewLevel()
            render(30)
            assert(#drawn==1 and drawn[1].text=='+25%' and drawn[1].color.B<0.5, 'gold over the holder')
            local y=drawn[1].y
            showingIcons=true; render(30)
            assert(drawn[1].y==y-14, 'moved up over the hit icons')
            showingIcons=false; render(30)
            assert(drawn[1].y==y, 'back down')
        ''')

    def test_an_older_note_keeps_what_it_showed(self):
        self.run_lua(r'''
            local p=newPlayer(2); players={p}; M.onGameStarted()
            p.save.wrongAnswerNote={kinds={['10.0']=2}, floors=1}
            assert(damage(newNpc(10,0),p)==35, 'two hits and a floor at golden: +200% and +50%')
            local note=p.save.wrongAnswerNote
            assert(note.v==2 and note.kinds['10.0']==2 and note.all==0.5 and note.floors==1)
            local q=newPlayer(0); players={p,q}
            q.save.wrongAnswerNote={kinds={['10.0']=1}, floors=0}
            M.ledger(q)
            assert(q.save.wrongAnswerNote.kinds['10.0']==0.5, 'not holding: one copy worth')
        ''')

    def test_a_monsters_number_sits_over_its_drawn_top(self):
        self.run_lua(r'''
            local p=newPlayer(1); players={p}; M.onGameStarted()
            -- Hush: size 100, its face reaching 96 px above its position
            local hush=newNpc(407,0,{Size=100,Position=Vector(240,140)})
            hush.sprite=layeredSprite({{y=0,pivot=96,height=160},{y=-62,pivot=24},{y=-71,pivot=16},
                {y=32,pivot=16},{y=-200,pivot=0,visible=false},{y=-300,pivot=0,layerVisible=false}})
            function hush:GetSprite() return self.sprite end
            assert(T.spriteTop(hush)==96, 'the highest visible layer: '..tostring(T.spriteTop(hush)))
            p.save.wrongAnswerNote={kinds={['407.0']=0.5},floors=0,all=0,v=2}
            M.onNpcInit(nil,hush); render(20)
            assert(#drawn==1 and drawn[1].y==140-96-2-9, 'just over the face, not 162 px up: '..drawn[1].y)
            -- the sprite grows: the number eases up, it does not jump
            hush.sprite=layeredSprite({{y=0,pivot=120}}); render()
            local y=drawn[1].y
            assert(y<140-96-2-9 and y>140-120-2-9, 'eased: '..y)
            render(40)
            assert(math.abs(drawn[1].y-(140-120-2-9))<0.01, 'settled on the new top')
        ''')

    def test_numbers_stay_on_the_screen(self):
        self.run_lua(r'''
            local p=newPlayer(1); players={p}; M.onGameStarted()
            Isaac.GetScreenWidth=function() return 480 end; Isaac.GetScreenHeight=function() return 270 end
            p.save.wrongAnswerNote={kinds={['407.0']=0.5},floors=0,all=0,v=2}
            local high=newNpc(407,0,{Position=Vector(470,30)})
            function high:GetSprite() return layeredSprite({{y=0,pivot=96}}) end
            M.onNpcInit(nil,high); render(20)
            local x,y=drawn[1].y and T.tracked()[high.hash].x, drawn[1].y
            assert(y==4, 'kept under the top edge: '..y)
            assert(x+#drawn[1].text*4<=476, 'kept inside the right edge: '..x)
            -- without frame data the size rule still places it
            local plain=newNpc(407,0,{Size=10,Position=Vector(200,200)})
            M.onNpcInit(nil,plain); render(20)
            local found=false
            for _,d in ipairs(drawn) do if d.y==200-45 then found=true end end
            assert(found, 'the size rule for a monster without frame data')
        ''')

    def test_huge_totals_stay_exact_through_a_save(self):
        self.run_lua(r'''
            local stubbed=require
            require=function(name) return ({math=math,string=string,table=table})[name] or stubbed(name) end
            local json=dofile(root..'/../../resources/scripts/json.lua')
            require=stubbed
            local p=newPlayer(3); players={p}; M.onGameStarted()
            local gaper=newNpc(10,0)
            for _=1,1000 do assert(hit(p,ref(gaper))==true) end
            for _=1,40 do saveCallbacks.PRE_FLOOR(); M.onNewLevel() end
            local note=p.save.wrongAnswerNote
            assert(note.kinds['10.0']==1500 and note.all==30 and note.floors==40,
                string.format('%s %s %s', note.kinds['10.0'], note.all, note.floors))
            -- what SaveManager writes and reads back (the game's own json)
            p.save=json.decode(json.encode(p.save))
            assert(damage(newNpc(10,0),p)==10*(1+1500+30), 'damage after the round trip: '..damage(newNpc(10,0),p))
            assert(damage(newNpc(18,0),p)==10*31)
            M.onNpcInit(nil,newNpc(10,0)); render(20)
            assert(T.shownText(gaper)==nil and #drawn==2, 'the new gaper and the holder')
            local texts={}
            for _,d in ipairs(drawn) do texts[d.text]=true end
            assert(texts['+150000%'] and texts['+3000%'], 'whole numbers, no exponent')
            -- one more hit after the round trip keeps adding exactly
            hit(p,ref(gaper))
            assert(p.save.wrongAnswerNote.kinds['10.0']==1501.5)
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
