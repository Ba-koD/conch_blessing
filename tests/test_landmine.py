"""지뢰 (Landmine) through its shipped Lua, for the tear that sows mines (user
design 2026-11-25): +40 range, x0.33 damage, -0.2 tears and attacks locked to
tears; every tear the holder fires carries 3 mines, one more for every 5 luck
with no cap, flings them to either side as it flies (passing over ground that
already holds one) and spills the rest where it stops; a mine landing on an
enemy goes off at once, the rest lie until an enemy or a player steps on them,
and a player is never hurt. A blast is twice the holder's damage. These are
Lua regressions with doubles, not proof of engine behaviour
(`cb test landmine`).
"""
from pathlib import Path
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
function reloadLandmine()
    cache["scripts.items.collectibles.landmine"]=nil
    M=ConchBlessingRequire("scripts.items.collectibles.landmine")
    T=M._test
end
local V={}; V.__index=V
V.__add=function(a,b) return Vector(a.X+b.X,a.Y+b.Y) end
V.__sub=function(a,b) return Vector(a.X-b.X,a.Y-b.Y) end
V.__mul=function(a,k) return Vector(a.X*k,a.Y*k) end
function V:Distance(o) return math.sqrt((self.X-o.X)^2+(self.Y-o.Y)^2) end
function V:Length() return math.sqrt(self.X^2+self.Y^2) end
Vector=setmetatable({},{__call=function(_,x,y) return setmetatable({X=x,Y=y},V) end})
Vector.Zero=Vector(0,0)
function Color(...) return {...} end
ModCallbacks={}
CacheFlag={CACHE_DAMAGE=1,CACHE_FIREDELAY=2,CACHE_SHOTSPEED=4,CACHE_RANGE=8,CACHE_LUCK=1024,CACHE_WEAPON=32}
WeaponType={WEAPON_TEARS=1,WEAPON_BRIMSTONE=2,WEAPON_LASER=3,WEAPON_KNIFE=4,WEAPON_BOMBS=5,WEAPON_ROCKETS=6,
    WEAPON_MONSTROS_LUNGS=7,WEAPON_LUDOVICO_TECHNIQUE=8,WEAPON_TECH_X=9,WEAPON_BONE=10,WEAPON_NOTCHED_AXE=11,
    WEAPON_URN_OF_SOULS=12,WEAPON_SPIRIT_SWORD=13,WEAPON_FETUS=14,WEAPON_UMBILICAL_WHIP=15}
EntityType={ENTITY_PLAYER=1,ENTITY_TEAR=2,ENTITY_FAMILIAR=3,ENTITY_EFFECT=1000}
EffectVariant={BOMB_EXPLOSION=1,POOF01=15}
EntityPartition={ENEMY=8}
EntityFlag={FLAG_FRIENDLY=1<<29}
DamageFlag={DAMAGE_EXPLOSION=1<<2}
GridCollisionClass={COLLISION_NONE=0,COLLISION_PIT=1,COLLISION_SOLID=4}
SoundEffect={SOUND_BOOM=37}
played={}
function SFXManager() return {Play=function(_,id,volume) played[#played+1]={id=id,volume=volume} end} end
-- A seeded RNG double: a fixed cycle of fractions from the seed.
function RNG()
    local r={n=0,seed=1}
    function r:SetSeed(seed) self.seed=seed self.n=0 end
    function r:RandomFloat()
        self.n=self.n+1
        return ((self.seed*7919+self.n*104729)%1000)/1000
    end
    return r
end
errors={}; callbacks={}
-- StatsAPI's doubles: additions applied and the item multiplier table.
applied={}
multipliers={}
um={}
function um:SetItemMultiplier(p,id,stat,value) multipliers[p.hash]={id=id,stat=stat,value=value}; applied[#applied+1]="set "..value end
function um:RemoveItemMultiplier(p,id,stat) multipliers[p.hash]=nil; applied[#applied+1]="remove" end
function um:QueueCacheUpdate() end
function um:SaveToSaveManager() end
ConchBlessing={ItemData={},printError=function(m) errors[#errors+1]=m end,printDebug=function() end,
    stats={unifiedMultipliers=um,
        tears={applyAddition=function(p,a) p.tearsAdded=(p.tearsAdded or 0)+a end},
        range={applyAddition=function(p,a) p.rangeAdded=(p.rangeAdded or 0)+a end}},
    getUnifiedMultiplierState=function(p)
        local e=multipliers[p.hash]
        if not e then return {itemMultipliers={}} end
        return {itemMultipliers={[e.id]={Damage={value=e.value}}}}
    end}
function ConchBlessing:AddCallback(id,fn) callbacks[id]=fn end
function GetPtrHash(e) return e.hash end
function EntityPtr(e) return {Ref=e} end
function EntityRef(e) return {Entity=e} end
-- Static sprites record what they draw.
renders={}
function Sprite()
    local sp={}
    function sp:Load(path) self.path=path end
    function sp:SetFrame(anim,f) self.anim=anim; self.frame=f end
    function sp:Render(pos) renders[#renders+1]={anim=self.anim,frame=self.frame,pos=pos} end
    return sp
end

serial=0; entities={}; players={}; frame=0
local E={}; E.__index=E
function E:Exists() return not self.removed end
function E:Remove() self.removed=true end
function E:GetData() self.data=self.data or {} return self.data end
function E:ToPlayer() return self.Type==EntityType.ENTITY_PLAYER and self or nil end
function E:ToEffect() return self.Type==EntityType.ENTITY_EFFECT and self or nil end
function E:IsActiveEnemy() return self.enemy==true and not self.dead end
function E:IsVulnerableEnemy() return self.enemy==true and not self.invulnerable end
function E:HasEntityFlags(f) return ((self.flags or 0) & f)~=0 end
function E:IsDead() return self.dead==true end
function E:IsCoopGhost() return self.ghost==true end
function E:GetCollectibleNum(id) return id==LANDMINE and (self.copies or 0) or 0 end
function E:TakeDamage(amount,flags,source) self.hits=self.hits or {}; self.hits[#self.hits+1]={amount=amount,flags=flags,source=source} end
function E:AddCacheFlags(f) self.cacheFlags=(self.cacheFlags or 0)|f end
function E:EvaluateItems() self.evaluated=(self.evaluated or 0)+1 end
function E:EnableWeaponType(t,on) self.weapons=self.weapons or {}; self.weapons[#self.weapons+1]=t..(on and "+" or "-") end
function E:GetSprite()
    local entity=self
    self.sprite=self.sprite or {anim=nil,Play=function(s,name) s.anim=name end,IsFinished=function(s,name) return s.anim==name and entity.finished end}
    return self.sprite
end
function entity(fields)
    serial=serial+1
    local e=setmetatable(fields,E); e.hash=serial; e.FrameCount=e.FrameCount or 0; e.Velocity=e.Velocity or Vector.Zero
    e.PositionOffset=e.PositionOffset or Vector.Zero
    entities[#entities+1]=e
    return e
end
LANDMINE=700; MINE_VARIANT=7790
Isaac={
    GetItemIdByName=function(name) return name=="Landmine" and LANDMINE or -1 end,
    GetEntityTypeByName=function() return 1000 end,
    GetEntityVariantByName=function(name) return name=="Conch Blessing Landmine" and MINE_VARIANT or -1 end,
    GetPlayer=function(i) return players[i+1] end,
    WorldToRenderPosition=function(v) return Vector(v.X*0.65,v.Y*0.65) end,
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
-- A room 0..600 x 0..300 with one rock cell around (300,100) and a pit cell
-- around (300,250).
room={}
function room:IsPositionInRoom(p,m) return p.X>=m and p.X<=600-m and p.Y>=m and p.Y<=300-m end
function room:GetCenterPos() return Vector(300,150) end
function room:GetClampedPosition(p,m) return Vector(math.max(m,math.min(600-m,p.X)),math.max(m,math.min(300-m,p.Y))) end
function room:GetGridCollisionAtPos(p)
    if math.abs(p.X-300)<=20 and math.abs(p.Y-100)<=20 then return GridCollisionClass.COLLISION_SOLID end
    if math.abs(p.X-300)<=20 and math.abs(p.Y-250)<=20 then return GridCollisionClass.COLLISION_PIT end
    return GridCollisionClass.COLLISION_NONE
end
function Game() return {GetRoom=function() return room end,GetFrameCount=function() return frame end,
    GetNumPlayers=function() return #players end} end
reloadLandmine()
function player(copies)
    local p=entity({Type=EntityType.ENTITY_PLAYER,Variant=0,Position=Vector(20,150),copies=copies or 1,Damage=3.5,
        Luck=0,Size=10})
    players[#players+1]=p
    return p
end
-- A tear fired by `spawner` from (x,y) at velocity (vx,vy).
function tear(spawner,x,y,vx,vy,seed)
    local t=entity({Type=EntityType.ENTITY_TEAR,Variant=0,Position=Vector(x,y),Velocity=Vector(vx or 10,vy or 0),
        SpawnerEntity=spawner,InitSeed=seed or 12345,Height=-23.75})
    M.onFireTear(nil,t)
    return t
end
-- One update: every live tear moves by its velocity, then the module runs.
function update(n)
    for _=1,(n or 1) do
        frame=frame+1
        for _,e in ipairs(entities) do
            if e.Type==EntityType.ENTITY_TEAR and not e.removed then e.Position=e.Position+e.Velocity end
            if e.Type==EntityType.ENTITY_EFFECT then e.FrameCount=e.FrameCount+1 end
        end
        M.onUpdate()
    end
end
function enemy(x,y,size) return entity({Type=10,Variant=0,Position=Vector(x,y),Size=size or 10,enemy=true}) end
function liveMines() return #M.mines() end
-- The live effects of the mine's variant: the field.
function fieldEffects()
    local n=0
    for _,e in ipairs(entities) do
        if e.Type==EntityType.ENTITY_EFFECT and e.Variant==MINE_VARIANT and not e.removed then n=n+1 end
    end
    return n
end
function tileCount() local n=0 for _,list in pairs(T.tiles()) do n=n+#list end return n end
function explosions()
    local n=0
    for _,e in ipairs(entities) do
        if e.Type==EntityType.ENTITY_EFFECT and e.Variant==EffectVariant.BOMB_EXPLOSION then n=n+1 end
    end
    return n
end
function closest()
    local list,best=M.mines(),math.huge
    for a=1,#list do for b=a+1,#list do
        local dx,dy=list[a].x-list[b].x,list[a].y-list[b].y
        best=math.min(best,math.sqrt(dx*dx+dy*dy))
    end end
    return best
end
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

    def test_registry_callbacks_cache_and_eid(self):
        self.assertTrue(self.g.M.available)
        self.assertEqual(len(list(self.g.callbacks.keys())), 0)
        self.assertEqual(len(list(self.g.errors.values())), 0)
        registry = (ROOT / 'scripts/conch_blessing_items.lua').read_text(encoding='utf-8')
        row = registry[registry.index('    LANDMINE = {'):registry.index('    UNDERDOG = {')]
        self.assertIn('fireTear = "landmine.onFireTear"', row)
        self.assertIn('evaluateCache = "landmine.onEvaluateCache"', row)
        self.assertIn('postUpdate = "landmine.onUpdate"', row)
        self.assertIn('cache = "damage firedelay range weapon"', row)
        self.assertNotIn('weaponFiredOptional', row)
        self.assertNotIn('stackable', row)
        # The user's EID (2026-11-25), Korean verbatim with stat icons.
        kr = (ROOT / 'scripts/locale/kr.lua').read_text(encoding='utf-8')
        entry = kr[kr.index('LANDMINE = {'):kr.index('UNDERDOG = {')]
        for line in ('{{Range}} 고정 사거리 +40', '#{{Damage}} 공격력 배율 x0.33', '#{{Tears}} 연사 0.2 감소',
                     '#공격이 눈물로 고정되며 눈물이 지속적으로 지뢰를 뿌립니다',
                     '#{{Luck}} 행운 5마다 지뢰가 1개씩 늘어납니다(기본 3개)', '#지뢰는 내 공격력의 2배 피해를 줍니다',
                     '#{{Warning}} REPENTOGON 권장'):
            self.assertIn('"' + line + '"', entry)
        warnings = {
            'en': '#{{Warning}} REPENTOGON recommended',
            'urimal': '#{{Warning}} 덧붙임 도우미(REPENTOGON)를 쓰면 좋습니다',
        }
        for lang, warning in warnings.items():
            text = (ROOT / f'scripts/locale/{lang}.lua').read_text(encoding='utf-8')
            entry = text[text.index('LANDMINE = {'):text.index('UNDERDOG = {')]
            self.assertIn(warning, entry, lang)
            self.assertNotIn('feet', entry, lang)
            self.assertNotIn('발밑', entry, lang)

    def test_payload_grows_with_luck_without_a_cap(self):
        result = self.run_lua('return T.payload(0), T.payload(4), T.payload(5), T.payload(10), T.payload(26), '
                              'T.payload(-3), T.payload(100)')
        self.assertEqual(result, (3, 3, 4, 5, 8, 3, 23))

    def test_pure_rules(self):
        result = self.run_lua('''
            local vz=T.launchSpeed(-23.75,10,0.9)
            return T.mineDamage(3.5), T.mineDamage(-1), T.within(40,40,0), T.within(51,40,10),
                -23.75+vz*10+0.5*0.9*100
        ''')
        damage, negative, edge, outside, landing = result
        self.assertEqual((damage, negative, edge, outside), (7, 0, True, False))
        self.assertAlmostEqual(landing, 0, places=9)

    def test_a_tear_flings_its_three_mines_to_both_sides_as_it_flies(self):
        result = self.run_lua('''
            local p=player(); p.Damage=1.2
            local t=tear(p,20,150,10,0)
            local laid={}
            for i=1,24 do update(1); laid[i]=T.evidence().laid end
            local sides,worst,ahead={},0,true
            for _,r in ipairs(M.mines()) do
                local off=r.y-150
                sides[off<0 and "up" or "down"]=true
                worst=math.max(worst,math.abs(off))
            end
            return laid[3],laid[4],laid[11],laid[12],laid[20],T.evidence().laid,#T.carriers(),sides.up==true,
                sides.down==true,worst,M.mines()[1].damage,M.mines()[1].owner.Ref==p,closest()
        ''')
        (before, first, _, second, third, laid, carriers, up, down, worst, damage, owner, gap) = result
        # The first after one tile (40 units, the 4th update), then every two.
        self.assertEqual((before, first, second, third, laid, carriers), (0, 1, 2, 3, 3, 0))
        self.assertTrue(up and down)
        self.assertLessEqual(worst, 40)
        self.assertEqual((damage, owner), (1.2, True))
        self.assertGreaterEqual(gap, 26)

    def test_a_mine_flies_from_the_tear_and_lands_where_it_was_aimed(self):
        result = self.run_lua('''
            local p=player(); local t=tear(p,20,150,10,0)
            update(4)
            local r=M.mines()[1]
            local start,flying,lifts=r.px,r.flying,{}
            for i=1,10 do update(1); lifts[i]=r.z end
            return start, flying, lifts[1]<-23.75, lifts[9]<0, lifts[10], r.px==r.x and r.py==r.y,
                r.flying, r.idle==true, r.landed, T.evidence().landed
        ''')
        start, flying, rose, airborne, last, placed, still_flying, idle, landed, count = result
        self.assertEqual((start, flying), (60, True))
        self.assertTrue(rose and airborne)
        self.assertEqual((last, placed, still_flying, idle, landed, count), (0, True, False, False, True, 1))

    def test_ground_with_a_mine_is_passed_over(self):
        result = self.run_lua('''
            local p=player()
            -- A row of mines along the first tile and a half of the tear's way.
            for x=40,140,20 do for y=100,200,20 do T.lay(p,Vector(x,y),3) end end
            local before=#M.mines()
            local t=tear(p,20,150,10,0)
            update(30)
            local farthest=0
            for k=before+1,#M.mines() do farthest=math.max(farthest,M.mines()[k].x) end
            return #M.mines()-before, T.evidence().carried>0, farthest>160
        ''')
        self.assertEqual(result, (3, True, True))

    def test_a_stopped_tear_spills_the_rest_around_where_it_stopped(self):
        result = self.run_lua('''
            local p=player(); local t=tear(p,20,150,10,0)
            update(5)                   -- one flung
            t:Remove()                  -- it hit something at about x=70
            update(1)
            local far=0
            for k=2,#M.mines() do
                local r=M.mines()[k]
                if math.sqrt((r.x-80)^2+(r.y-150)^2)>40.5 then far=far+1 end
            end
            return T.evidence().flung, T.evidence().spilled, #M.mines(), #T.carriers(), far
        ''')
        self.assertEqual(result, (1, 2, 3, 0, 0))

    def test_a_spill_with_no_free_ground_piles_up_and_off_the_floor_is_lost(self):
        result = self.run_lua('''
            local p=player()
            for x=30,130,10 do for y=100,200,10 do T.lay(p,Vector(x,y),3) end end
            local t=tear(p,60,150,10,0); t:Remove(); update(1)
            local piled=T.evidence().piled
            -- Inside the rock: no floor anywhere it could spill.
            local before=T.evidence().laid
            room.GetGridCollisionAtPos=function() return GridCollisionClass.COLLISION_SOLID end
            local t2=tear(p,300,100,10,0); t2:Remove(); update(1)
            return piled, T.evidence().laid-before, T.evidence().lost
        ''')
        self.assertEqual(result, (3, 0, 3))

    def test_luck_adds_mines_to_every_tear(self):
        result = self.run_lua('''
            local p=player(); p.Luck=10
            tear(p,20,150,10,0)
            update(40)
            return T.evidence().laid
        ''')
        self.assertEqual(result, 5)

    def test_only_a_living_holders_tears_carry_mines(self):
        result = self.run_lua('''
            local other=player(0); tear(other,20,40,10,0)
            local dead=player(); dead.dead=true; tear(dead,20,150,10,0)
            local ghost=player(); ghost.ghost=true; tear(ghost,20,280,10,0)
            local holder=player()
            local familiar=entity({Type=EntityType.ENTITY_FAMILIAR,Variant=1,Position=Vector(80,80),Player=holder})
            tear(familiar,80,80,10,0)
            tear(nil,80,80,10,0)
            M.onFireTear(nil,nil)
            update(30)
            return #M.mines(), T.evidence().fired, #errors
        ''')
        self.assertEqual(result, (0, 0, 0))

    def test_a_mine_landing_on_an_enemy_goes_off_at_once(self):
        result = self.run_lua('''
            local p=player(); p.Damage=2
            local t=tear(p,20,150,10,0)
            update(4)
            local r=M.mines()[1]
            local victim=enemy(r.x,r.y,10)
            update(9)
            local early=r.dead==true
            update(1)
            return early, r.dead==true, T.evidence().landedOn, victim.hits and #victim.hits or 0,
                victim.hits and victim.hits[1].amount
        ''')
        self.assertEqual(result, (False, True, 1, 1, 4))

    def test_armed_mine_blasts_enemies_only_and_waits_unarmed(self):
        result = self.run_lua('''
            local p=player(); p.Position=Vector(500,250)
            local m=T.lay(p,Vector(100,150),3)
            local stepper=enemy(102,150,10)
            local near=enemy(140,150,10)        -- 40 away: inside 40 + its size
            local far=enemy(200,200,10)         -- outside
            local friend=enemy(110,160,10); friend.flags=EntityFlag.FLAG_FRIENDLY
            update(M.data.armFrames-1)
            local before=m.dead==true
            update(1)
            local function took(e) return e.hits and #e.hits or 0 end
            local hit=stepper.hits[1]
            return before, m.dead==true, took(stepper), took(near), took(far), took(friend),
                hit.amount, hit.flags, hit.source.Entity==p, took(p), #played, #M.mines(), tileCount(),
                T.blasting(), fieldEffects()
        ''')
        # The owner is the blast's source; the field goes with the last mine.
        self.assertEqual(result, (False, True, 1, 1, 0, 0, 6, 4, True, 0, 1, 0, 0, False, 0))

    def test_a_player_stepping_on_an_armed_mine_sets_it_off_unhurt(self):
        result = self.run_lua('''
            local p=player(); p.Position=Vector(500,250)
            local m=T.lay(p,Vector(100,150),3)
            local near=enemy(134,150,10)
            update(M.data.armFrames)
            local waited=m.dead==true
            p.Position=Vector(110,150)
            update(1)
            return waited, m.dead==true, T.evidence().byPlayer, near.hits and #near.hits or 0, p.hits==nil
        ''')
        self.assertEqual(result, (False, True, 1, 1, True))

    def test_a_dead_player_or_ghost_sets_nothing_off(self):
        result = self.run_lua('''
            local p=player(); p.dead=true; p.Position=Vector(100,150)
            local g=player(); g.ghost=true; g.Position=Vector(100,150)
            local m=T.lay(p,Vector(100,150),3)
            update(M.data.armFrames+2)
            return m.dead==true, T.evidence().byPlayer
        ''')
        self.assertEqual(result, (False, 0))

    def test_blast_sets_off_nearby_mines_a_moment_later(self):
        result = self.run_lua('''
            local p=player(); p.Position=Vector(500,280)
            T.lay(p,Vector(100,150),3); T.lay(p,Vector(130,150),3); T.lay(p,Vector(300,200),3)
            update(M.data.armFrames)
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

    def test_a_pile_goes_off_together_with_one_explosion_and_one_sound(self):
        result = self.run_lua('''
            local p=player(); p.Position=Vector(500,280)
            for _=1,4 do T.lay(p,Vector(100,150),3) end
            update(M.data.armFrames)
            local stepper=enemy(100,150,10)
            update(1)
            local function total(e) local n=0 for _,h in ipairs(e.hits or {}) do n=n+h.amount end return n end
            return T.evidence().exploded, total(stepper), explosions(), #played, #M.mines()
        ''')
        # Four mines of 2 x 3 each.
        self.assertEqual(result, (4, 24, 1, 1, 0))

    def test_stepping_looks_only_near_each_enemy(self):
        result = self.run_lua('''
            local p=player(); p.Position=Vector(590,290)
            for i=0,13 do for j=0,5 do T.lay(p,Vector(20+i*40,20+j*45),3) end end
            update(M.data.armFrames)
            enemy(260,200,10)
            findCalls=0
            update(1)
            return T.evidence().exploded, findCalls
        ''')
        # One mine under the enemy; one enemy query for stepping, one for the blast.
        self.assertEqual(result, (1, 2))

    def test_evaluate_cache_gives_the_stats_and_locks_the_tears(self):
        result = self.run_lua('''
            local p=player(2)
            M.onEvaluateCache(nil,p,CacheFlag.CACHE_FIREDELAY)
            M.onEvaluateCache(nil,p,CacheFlag.CACHE_RANGE)
            M.onEvaluateCache(nil,p,CacheFlag.CACHE_WEAPON)
            M.onEvaluateCache(nil,p,CacheFlag.CACHE_DAMAGE)
            local without=player(0)
            for _,f in pairs(CacheFlag) do M.onEvaluateCache(nil,without,f) end
            return p.tearsAdded, p.rangeAdded, table.concat(p.weapons,","), without.tearsAdded, without.rangeAdded,
                without.weapons
        ''')
        # Copies do not stack; the active items' own weapons (11, 12) stay.
        self.assertEqual(result, (-0.2, 1600, '2-,3-,4-,5-,6-,7-,8-,9-,10-,13-,14-,15-,1+', None, None, None))

    def test_the_damage_multiplier_follows_holding_the_item(self):
        result = self.run_lua('''
            local p=player(0)
            update(1)
            local none=multipliers[p.hash]
            p.copies=2; update(1)
            local held=multipliers[p.hash] and multipliers[p.hash].value
            local evaluated=p.evaluated
            update(5)
            local steady=#applied
            p.copies=0; update(1)
            return none==nil, held, evaluated, steady, multipliers[p.hash]==nil, p.evaluated, p.cacheFlags
        ''')
        # Set once on pickup, removed on loss; stats evaluated at each change.
        self.assertEqual(result, (True, 0.33, 1, 1, True, 2, 1 | 2 | 8 | 32))

    def test_a_stale_multiplier_is_removed_after_a_start(self):
        result = self.run_lua('''
            local p=player(0)
            multipliers[p.hash]={id=LANDMINE,stat="Damage",value=0.33}
            M.onGameStarted()
            update(1)
            return multipliers[p.hash]==nil
        ''')
        self.assertTrue(result)

    def test_land_hands_over_to_idle(self):
        result = self.run_lua('''
            local p=player(); p.Position=Vector(500,280); local m=T.lay(p,Vector(100,150),3)
            update(T.frames.Land-1)
            local early=m.idle==true
            update(1)
            return early, m.idle==true, m.idleAt==frame, m.armed==true
        ''')
        self.assertEqual(result, (False, True, True, True))

    def test_one_field_draws_every_mine_on_its_frame(self):
        result = self.run_lua('''
            local p=player(); p.Position=Vector(500,280)
            local lying=T.lay(p,Vector(100,150),3)      -- lands at once
            update(T.frames.Land+5)                     -- then 5 updates idle
            local landing=T.lay(p,Vector(200,150),3)
            update(2)
            local t=tear(p,20,150,10,0); update(4)      -- one flung, in the air
            local f=T.field()
            renders={}
            M.onFieldRender(nil,f,Vector(1,2))
            local drawn={}
            for _,r in ipairs(renders) do drawn[#drawn+1]=r.anim..r.frame end
            table.sort(drawn)
            local idlePos
            for _,r in ipairs(renders) do if r.anim=="Idle" then idlePos=r.pos end end
            local count=T.evidence().drawnMines
            local stray=Isaac.Spawn(EntityType.ENTITY_EFFECT,MINE_VARIANT,0,Vector(0,0),Vector.Zero,nil)
            local before=#renders
            M.onFieldRender(nil,stray,Vector(0,0))
            return fieldEffects(), f.DepthOffset<-10000, f.Color[4], table.concat(drawn," "),
                #renders-before, idlePos.X, idlePos.Y, count
        ''')
        fields, under, alpha, drawn, stray, x, y, count = result
        # The field plus the stray this test spawned; the lying mine is 11
        # updates into Idle, the landing one on Land frame 6, the flung one Fall.
        self.assertEqual((fields, under, alpha), (2, True, 0))
        self.assertEqual(drawn, 'Fall0 Idle11 Land6')
        self.assertEqual((stray, x, y, count), (0, 100 * 0.65 + 1, 150 * 0.65 + 2, 3))

    def test_new_room_forgets_mines_and_tears_and_unload_removes_them(self):
        result = self.run_lua('''
            local p=player(); local m=T.lay(p,Vector(100,150),3)
            local f=T.field()
            M.onModUnload()
            local removed=f.removed==true and T.field()==nil
            tear(p,20,150,10,0)
            local carried=#T.carriers()
            M.onNewRoom()
            return removed, carried, #M.mines(), #T.carriers(), tileCount()
        ''')
        self.assertEqual(result, (True, 1, 0, 0, 0))


if __name__ == '__main__':
    unittest.main()
