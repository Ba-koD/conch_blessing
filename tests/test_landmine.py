"""지뢰 (Landmine) through its shipped Lua: where a flying tear drops its mines,
how they fall and land, which tears drop none, the one-tile rule and the
missing cap, arming, the blast (twice the tear's damage, enemies only) and the
chain to nearby mines. The user's design: an enemy stepping on a mine sets it
off and it never hurts the player (2026-11-15); every tear drops a trail of
mines as it flies, like Auri's Blue Eye, two at the default range, falling from
the tear, with no cap (2026-11-19). These are Lua regressions with doubles, not
proof of engine behaviour (`cb test landmine`).
"""
from pathlib import Path
import re
import unittest

from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def source(name):
    return (ROOT / (name.replace('.', '/') + '.lua')).read_text(encoding='utf-8')


SETUP = r'''
package=nil
local cache={}
function ConchBlessingRequire(name)
    if not cache[name] then cache[name]=load(loadsource(name),name)() end
    return cache[name]
end
local V={}; V.__index=V
V.__add=function(a,b) return Vector(a.X+b.X,a.Y+b.Y) end
V.__sub=function(a,b) return Vector(a.X-b.X,a.Y-b.Y) end
V.__mul=function(a,k) return Vector(a.X*k,a.Y*k) end
function V:Distance(o) return math.sqrt((self.X-o.X)^2+(self.Y-o.Y)^2) end
function V:Length() return math.sqrt(self.X^2+self.Y^2) end
function V:Normalized() local l=self:Length() return Vector(self.X/l,self.Y/l) end
Vector=setmetatable({},{__call=function(_,x,y) return setmetatable({X=x,Y=y},V) end})
Vector.Zero=Vector(0,0)
function Color(...) return {...} end
ModCallbacks={MC_POST_TEAR_DEATH=1033,MC_POST_TEAR_COLLISION=1233}
EntityType={ENTITY_PLAYER=1,ENTITY_TEAR=2,ENTITY_FAMILIAR=3,ENTITY_EFFECT=1000}
EffectVariant={BOMB_EXPLOSION=1,POOF01=15}
EntityPartition={ENEMY=8}
EntityFlag={FLAG_FRIENDLY=1<<29}
DamageFlag={DAMAGE_EXPLOSION=1<<2}
GridCollisionClass={COLLISION_NONE=0,COLLISION_PIT=1,COLLISION_SOLID=4}
SoundEffect={SOUND_BOOM=37}
played={}
function SFXManager() return {Play=function(_,id,volume) played[#played+1]={id=id,volume=volume} end} end
errors={}; callbacks={}
ConchBlessing={ItemData={},printError=function(m) errors[#errors+1]=m end,printDebug=function() end}
function ConchBlessing:AddCallback(id,fn) callbacks[id]=fn end
function GetPtrHash(e) return e.hash end
function EntityPtr(e) return {Ref=e} end
function EntityRef(e) return {Entity=e} end

serial=0; entities={}; players={}; frame=0
local E={}; E.__index=E
function E:Exists() return not self.removed end
function E:Remove() self.removed=true end
function E:GetData() self.data=self.data or {} return self.data end
function E:ToPlayer() return self.Type==EntityType.ENTITY_PLAYER and self or nil end
function E:ToEffect() return self.Type==EntityType.ENTITY_EFFECT and self or nil end
function E:IsEnemy() return self.enemy==true end
function E:IsActiveEnemy() return self.enemy==true and not self.dead end
function E:IsVulnerableEnemy() return self.enemy==true and not self.invulnerable end
function E:HasEntityFlags(f) return ((self.flags or 0) & f)~=0 end
function E:IsDead() return self.dead==true end
function E:GetCollectibleNum(id) return id==LANDMINE and (self.copies or 0) or 0 end
function E:TakeDamage(amount,flags,source) self.hits=self.hits or {}; self.hits[#self.hits+1]={amount=amount,flags=flags,source=source} end
function E:GetSprite()
    local entity=self
    self.sprite=self.sprite or {anim=nil,Play=function(s,name) s.anim=name end,IsFinished=function(s,name) return s.anim==name and entity.finished end}
    return self.sprite
end
function entity(fields)
    serial=serial+1
    local e=setmetatable(fields,E); e.hash=serial; e.FrameCount=e.FrameCount or 0; e.Velocity=e.Velocity or Vector.Zero
    entities[#entities+1]=e
    return e
end
LANDMINE=700; MINE_VARIANT=7790
Isaac={
    GetItemIdByName=function(name) return name=="Landmine" and LANDMINE or -1 end,
    GetEntityTypeByName=function() return 1000 end,
    GetEntityVariantByName=function(name) return name=="Conch Blessing Landmine" and MINE_VARIANT or -1 end,
    GetPlayer=function(i) return players[i+1] end,
    Spawn=function(t,v,s,pos,vel,spawner)
        return entity({Type=t,Variant=v,SubType=s,Position=pos,Velocity=vel,SpawnerEntity=spawner})
    end,
    FindInRadius=function(pos,radius,partition)
        findCalls=(findCalls or 0)+1
        local list={}
        for _,e in ipairs(entities) do
            if not e.removed and e.enemy and e.Position:Distance(pos)<=radius then list[#list+1]=e end
        end
        return list
    end,
}
-- A room 0..400 x 0..300 with one rock cell around (200,100) and a pit cell
-- around (200,250).
room={}
function room:IsPositionInRoom(p,m) return p.X>=m and p.X<=400-m and p.Y>=m and p.Y<=300-m end
function room:GetCenterPos() return Vector(200,150) end
function room:GetGridCollisionAtPos(p)
    if math.abs(p.X-200)<=20 and math.abs(p.Y-100)<=20 then return GridCollisionClass.COLLISION_SOLID end
    if math.abs(p.X-200)<=20 and math.abs(p.Y-250)<=20 then return GridCollisionClass.COLLISION_PIT end
    return GridCollisionClass.COLLISION_NONE
end
function Game() return {GetRoom=function() return room end,GetFrameCount=function() return frame end,
    GetNumPlayers=function() return #players end} end
M=ConchBlessingRequire("scripts.items.collectibles.landmine")
T=M._test
DP=ConchBlessingRequire("scripts.lib.damage_provenance")
function player(copies)
    local p=entity({Type=EntityType.ENTITY_PLAYER,Variant=0,Position=Vector(50,150),copies=copies or 1})
    players[#players+1]=p
    return p
end
function tear(owner,x,y,damage)
    return entity({Type=EntityType.ENTITY_TEAR,Variant=0,Position=Vector(x,y),SpawnerEntity=owner,CollisionDamage=damage or 3.5})
end
-- Moves the tear by (dx,dy) `steps` times, one update each, the way the engine
-- calls MC_POST_TEAR_UPDATE after every move.
function fly(t,dx,dy,steps)
    for _=1,steps do
        frame=frame+1
        t.Position=t.Position+Vector(dx,dy)
        M.onTearUpdate(nil,t)
    end
end
function enemy(x,y,size) return entity({Type=10,Variant=0,Position=Vector(x,y),Size=size or 10,enemy=true}) end
function xs() local list={} for i,r in ipairs(M.mines()) do list[i]=r.x end return table.concat(list,",") end
function liveMines() local n=0 for _,r in ipairs(M.mines()) do if r.ref.Ref:Exists() then n=n+1 end end return n end
function age(frames) for _,r in ipairs(M.mines()) do r.ref.Ref.FrameCount=r.ref.Ref.FrameCount+frames end end
function update(n) for _=1,(n or 1) do frame=frame+1; M.onUpdate() end end
function tileCount() local n=0 for _,list in pairs(T.tiles()) do n=n+#list end return n end
'''


class LandmineTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        g = self.lua.globals()
        g.loadsource = source
        self.lua.execute(SETUP)
        self.g = g

    def run_lua(self, code):
        return self.lua.execute(code)

    def test_uses_the_base_tear_update_through_item_data(self):
        # Base API only: no REPENTOGON tear callbacks and no direct registration.
        self.assertTrue(self.g.M.available)
        self.assertEqual(len(list(self.g.callbacks.keys())), 0)
        self.assertEqual(len(list(self.g.errors.values())), 0)
        registry = (ROOT / 'scripts/conch_blessing_items.lua').read_text(encoding='utf-8')
        row = registry[registry.index('    LANDMINE = {'):registry.index('    UNDERDOG = {')]
        self.assertIn('postTearUpdate = "landmine.onTearUpdate"', row)
        for lang in ('en', 'kr', 'urimal'):
            text = (ROOT / f'scripts/locale/{lang}.lua').read_text(encoding='utf-8')
            entry = text[text.index('LANDMINE = {'):text.index('UNDERDOG = {')]
            self.assertNotIn('REPENTOGON', entry, lang)
            self.assertNotRegex(entry, r'10', lang)

    def test_flying_tear_drops_a_mine_each_spacing_beneath_it(self):
        result = self.run_lua('''
            local p=player(); local t=tear(p,60,150,4.5); fly(t,10,0,25)
            local r=M.mines()[1]; local m=r.ref.Ref
            return xs(), m.Variant, m.Position.Y, r.damage, m.SpawnerEntity==p, m.sprite.anim, m.DepthOffset,
                T.evidence().trails
        ''')
        # Its first update (x=70) starts the count; a mine every 100 units after,
        # two over a default tear's flight. A tear with no height lands it at once.
        self.assertEqual(result, ('170,270', 7790, 150, 4.5, True, 'Land', -1000, 1))

    def test_dropped_mine_falls_from_the_tear_and_arms_after_landing(self):
        result = self.run_lua('''
            local p=player(); local t=tear(p,60,150,3); t.Height=-24; fly(t,10,0,11)
            local r=M.mines()[1]; local m=r.ref.Ref
            local start, anim = m.PositionOffset.Y, m.sprite.anim
            local lifts={}
            local stepper=enemy(170,150,10)
            for i=1,6 do update(1); lifts[i]=m.PositionOffset.Y end
            local landedAnim, landed, armedOnLanding = m.sprite.anim, r.landed, r.armed
            m.FrameCount=m.FrameCount+M.data.armFrames-1; update(1)
            local early=m.removed==true
            m.FrameCount=m.FrameCount+1; update(1)
            return start, anim, table.concat(lifts,","), landedAnim, landed, armedOnLanding, early, m.removed==true,
                stepper.hits and #stepper.hits or 0, T.evidence().landed
        ''')
        self.assertEqual(result, (-24, 'Fall', '-22.5,-19.5,-15.0,-9.0,-1.5,0', 'Land', True, None, False, True, 1, 1))

    def test_tear_that_hits_keeps_the_mines_it_laid(self):
        result = self.run_lua('''
            local p=player(); local t=tear(p,60,150); fly(t,10,0,15)
            t:Remove()   -- it hit something at x=210
            update(1)
            return xs()
        ''')
        self.assertEqual(result, '170')

    def test_familiar_tear_non_holder_and_own_lineage_lay_nothing(self):
        result = self.run_lua('''
            local p=player()
            local familiar=entity({Type=EntityType.ENTITY_FAMILIAR,Variant=1,Position=Vector(0,0)})
            familiar.SpawnerEntity=p
            fly(tear(familiar,60,40),10,0,20)
            local other=player(0); fly(tear(other,60,200),10,0,20)
            local looped=tear(p,60,280); DP.markTriggeredAttack(looped,"landmine",nil,"landmine"); fly(looped,10,0,20)
            return #M.mines()
        ''')
        self.assertEqual(result, 0)

    def test_nobody_holding_skips_every_tear_cheaply(self):
        result = self.run_lua('''
            local p=player(0); local t=tear(p,60,150); fly(t,10,0,20)
            return #M.mines(), t.data==nil
        ''')
        # The holder check comes before the tear's own data is touched.
        self.assertEqual(result, (0, True))

    def test_no_mine_over_a_rock_or_pit_the_next_free_floor_gets_it(self):
        result = self.run_lua('''
            local p=player()
            fly(tear(p,110,100),10,0,25)    -- due over the rock at x 180..220
            local rock=xs()
            M.onNewRoom()
            fly(tear(p,110,250),10,0,25)    -- due over the pit
            return rock, xs(), T.evidence().blocked
        ''')
        rock, pit, blocked = result
        self.assertEqual(rock, '230,330')
        self.assertEqual(pit, '230,330')
        self.assertEqual(blocked, 2)

    def test_no_mine_outside_the_floor_margin(self):
        result = self.run_lua('''
            local p=player(); fly(tear(p,250,150),10,0,20)   -- on past the right wall at 400
            return xs()
        ''')
        self.assertEqual(result, '360')

    def test_a_drop_point_with_a_mine_within_a_tile_counts_as_dropped(self):
        result = self.run_lua('''
            local p=player()
            fly(tear(p,60,150),10,0,22)
            local first=#M.mines()
            fly(tear(p,60,150),10,0,22)          -- the same line
            local same=#M.mines()
            fly(tear(p,75,150),10,0,22)          -- the same line, due 15 further on
            local shifted=#M.mines()
            fly(tear(p,60,180),10,0,22)          -- 30 away
            local close=#M.mines()
            fly(tear(p,60,195),10,0,22)          -- 45 away
            return first, same, shifted, close, #M.mines(), T.evidence().crowded
        ''')
        # A tear never fills in between the mines already on its line.
        self.assertEqual(result, (2, 2, 2, 2, 4, 6))

    def test_no_cap_on_mines(self):
        result = self.run_lua('''
            local p=player(); local first
            for row=0,4 do
                fly(tear(p,60,30+row*50),10,0,33)
                first=first or M.mines()[1].ref.Ref
            end
            return #M.mines(), liveMines(), T.evidence().laid, first.removed==true
        ''')
        # Five rows 50 apart, three mines each.
        self.assertEqual(result, (15, 15, 15, False))

    def test_owner_losing_the_item_stops_the_trail(self):
        result = self.run_lua('''
            local p=player(); local t=tear(p,60,150); fly(t,10,0,11)
            p.copies=0; players[2]=entity({Type=EntityType.ENTITY_PLAYER,Variant=0,Position=Vector(0,0),copies=1})
            fly(t,10,0,20)
            return xs()
        ''')
        self.assertEqual(result, '170')

    def test_dead_owner_lays_nothing(self):
        result = self.run_lua('''
            local p=player(); local t=tear(p,60,150); fly(t,10,0,1)
            p.dead=true; fly(t,10,0,20)
            return #M.mines()
        ''')
        self.assertEqual(result, 0)

    def test_unarmed_mine_waits_and_armed_mine_blasts_enemies_only(self):
        result = self.run_lua('''
            local p=player(); local m=T.lay(p,Vector(100,150),3,nil)
            local stepper=enemy(102,150,10)
            local near=enemy(150,150,10)        -- 50 away: inside 60 + its size
            local far=enemy(200,200,10)         -- outside
            local friend=enemy(110,160,10); friend.flags=EntityFlag.FLAG_FRIENDLY
            update(1)
            local before=m.removed==true
            m.FrameCount=M.data.armFrames
            update(1)
            local function took(e) return e.hits and #e.hits or 0 end
            local hit=stepper.hits[1]
            return before, m.removed==true, took(stepper), took(near), took(far), took(friend),
                hit.amount, hit.flags, hit.source.Entity==m, took(p), #played, #M.mines(), tileCount()
        ''')
        self.assertEqual(result, (False, True, 1, 1, 0, 0, 6, 4, True, 0, 1, 0, 0))

    def test_blast_sets_off_nearby_mines_a_moment_later(self):
        result = self.run_lua('''
            local p=player()
            T.lay(p,Vector(100,150),3); T.lay(p,Vector(150,150),3); T.lay(p,Vector(300,150),3)
            age(M.data.armFrames)
            local victim=enemy(100,150,10)
            update(1)
            local afterFirst=liveMines()
            victim:Remove()
            update(M.data.chainDelay - 1)
            local beforeFuse=liveMines()
            update(1)
            return afterFirst, beforeFuse, liveMines(), T.evidence().chained, T.evidence().exploded
        ''')
        self.assertEqual(result, (2, 2, 1, 1, 2))

    def test_one_blast_sound_per_update_however_many_go_off(self):
        result = self.run_lua('''
            local p=player()
            for i=0,4 do T.lay(p,Vector(60+i*45,150),3) end
            age(M.data.armFrames)
            enemy(60,150,10); enemy(150,150,10); enemy(240,150,10)
            update(1)
            return T.evidence().exploded, #played
        ''')
        self.assertEqual(result, (3, 1))

    def test_stepping_looks_only_near_each_enemy(self):
        result = self.run_lua('''
            local p=player()
            for i=0,9 do for j=0,5 do T.lay(p,Vector(20+i*40,20+j*45),3) end end
            age(M.data.armFrames)
            enemy(260,200,10)
            findCalls=0
            update(1)
            return #M.mines(), T.evidence().exploded, findCalls
        ''')
        # One mine under the enemy, its blast reaches neighbours for the chain;
        # one enemy query for stepping and one for the blast.
        count, exploded, finds = result
        self.assertEqual(exploded, 1)
        self.assertEqual(count, 59)
        self.assertEqual(finds, 2)

    def test_land_hands_over_to_idle(self):
        result = self.run_lua('''
            local p=player(); local m=T.lay(p,Vector(100,150),3)
            local anim=m.sprite.anim
            m.finished=true
            update(1)
            return anim, m.sprite.anim
        ''')
        self.assertEqual(result, ('Land', 'Idle'))

    def test_a_mine_removed_elsewhere_is_forgotten(self):
        result = self.run_lua('''
            local p=player(); local m=T.lay(p,Vector(100,150),3); T.lay(p,Vector(200,150),3)
            m:Remove()
            return #M.mines(), tileCount(), T.crowded(100,150)
        ''')
        self.assertEqual(result, (1, 1, False))

    def test_new_room_forgets_mines_and_unload_removes_them(self):
        result = self.run_lua('''
            local p=player(); local m=T.lay(p,Vector(100,150),3)
            M.onModUnload()
            local removed=m.removed==true
            T.lay(p,Vector(120,150),3); M.onNewRoom()
            return removed, #M.mines(), tileCount()
        ''')
        self.assertEqual(result, (True, 0, 0))

    def test_pure_rules(self):
        result = self.run_lua('return T.mineDamage(3.5), T.mineDamage(-1), T.within(60,60,0), T.within(71,60,10)')
        self.assertEqual(result, (7, 0, True, False))


if __name__ == '__main__':
    unittest.main()
