"""지뢰 (Landmine) through its shipped Lua, for the tear that sows mines (user
designs 2026-11-25 and 2026-11-27): +40 range, x0.33 damage, -0.2 tears and
attacks locked to tears (tear weapons stay); every tear of a living holder,
whatever made it, lays mines 3 times (+1 per 5 luck, no cap) every 0.2 s while
it lives, one mine at a time per copy held (alternating sides), passing over
ground that already holds one, refills them all 5 fire intervals after it
runs out and spills the rest where it stops; a mine landing on an enemy goes
off at once, the rest lie until an enemy or a player steps on them, and a
player is never hurt. A blast is the holder's damage, a fake explosion
that carries the holder's bomb flags (engine bomb damage at each enemy, the
flags' own effects, Bomber Boy's cross, Scatter Bombs, Ghost Bombs) and, with
the homing flag, lets lying mines creep toward enemies. These are Lua
regressions with doubles, not proof of engine behaviour (`cb test landmine`).
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
Color=setmetatable({},{__call=function(_,...) return {...} end})
ModCallbacks={}
CacheFlag={CACHE_DAMAGE=1,CACHE_FIREDELAY=2,CACHE_SHOTSPEED=4,CACHE_RANGE=8,CACHE_LUCK=1024,CACHE_WEAPON=32}
Color.Default={1,1,1,1}
WeaponType={WEAPON_TEARS=1,WEAPON_BRIMSTONE=2,WEAPON_LASER=3,WEAPON_KNIFE=4,WEAPON_BOMBS=5,WEAPON_ROCKETS=6,
    WEAPON_MONSTROS_LUNGS=7,WEAPON_LUDOVICO_TECHNIQUE=8,WEAPON_TECH_X=9,WEAPON_BONE=10,WEAPON_NOTCHED_AXE=11,
    WEAPON_URN_OF_SOULS=12,WEAPON_SPIRIT_SWORD=13,WEAPON_FETUS=14,WEAPON_UMBILICAL_WHIP=15}
EntityType={ENTITY_PLAYER=1,ENTITY_TEAR=2,ENTITY_FAMILIAR=3,ENTITY_BOMB=4,ENTITY_EFFECT=1000}
BombVariant={BOMB_NORMAL=0}
EffectVariant={BOMB_EXPLOSION=1,POOF01=15,HUNGRY_SOUL=186,PURGATORY=189}
LaserVariant={THICK_RED=1}
TearFlags={TEAR_HOMING=1<<2,TEAR_SCATTER_BOMB=1<<36,TEAR_CROSS_BOMB=1<<45,TEAR_GHOST_BOMB=1<<50,TEAR_BRIMSTONE_BOMB=1<<41,
    TEAR_BURN=1<<22,TEAR_POISON=1<<4,TEAR_SAD_BOMB=1<<35,TEAR_STICKY=1<<34,TEAR_BUTT_BOMB=1<<37,TEAR_SLOW=1<<3,
    TEAR_EGG=1<<23,TEAR_SPECTRAL=1<<0}
CollectibleType={COLLECTIBLE_NANCY_BOMBS=725}
EntityPartition={ENEMY=8}
EntityFlag={FLAG_FRIENDLY=1<<29}
DamageFlag={DAMAGE_EXPLOSION=1<<2}
GridCollisionClass={COLLISION_NONE=0,COLLISION_PIT=1,COLLISION_SOLID=4}
bombCalls={}; flagCalls={}
function bombs()
    local list={}
    for _,e in ipairs(entities) do if e.Type==EntityType.ENTITY_BOMB then list[#list+1]=e end end
    return list
end
SoundEffect={SOUND_BOOM=37}
played={}
function SFXManager() return {Play=function(_,id,volume) played[#played+1]={id=id,volume=volume} end} end
-- A seeded RNG double: a fixed cycle of fractions from the seed.
function RNG()
    local r={n=0,seed=1}
    function r:SetSeed(seed) self.seed=seed self.n=0 end
    function r:Next() self.n=self.n+1 return (self.seed*31+self.n*7)%100000 end
    function r:RandomInt(n) return math.floor(self:RandomFloat()*n) end
    function r:RandomFloat()
        self.n=self.n+1
        return ((self.seed*7919+self.n*104729)%1000)/1000
    end
    return r
end
errors={}; callbacks={}
-- StatsAPI's doubles: additions applied and the item multiplier table.
applied={}
multipliers={}   -- the Damage multiplier, by player
tearsMult={}     -- the Tears multiplier, by player
um={}
function um:SetItemMultiplier(p,id,stat,value)
    if stat=="Tears" then tearsMult[p.hash]=value else multipliers[p.hash]={id=id,stat=stat,value=value} end
    applied[#applied+1]="set "..stat.." "..value
end
function um:RemoveItemMultiplier(p,id,stat)
    if stat=="Tears" then tearsMult[p.hash]=nil else multipliers[p.hash]=nil end
    applied[#applied+1]="remove "..stat
end
function um:QueueCacheUpdate() end
function um:SaveToSaveManager() end
ConchBlessing={ItemData={},printError=function(m) errors[#errors+1]=m end,printDebug=function() end,
    stats={unifiedMultipliers=um,
        tears={applyAddition=function(p,a) p.tearsAdded=(p.tearsAdded or 0)+a end},
        range={applyAddition=function(p,a) p.rangeAdded=(p.rangeAdded or 0)+a end},
        shotSpeed={applyAddition=function(p,a) p.shotAdded=(p.shotAdded or 0)+a end}},
    getUnifiedMultiplierState=function(p)
        local e,t=multipliers[p.hash],tearsMult[p.hash]
        if not e and not t then return {itemMultipliers={}} end
        return {itemMultipliers={[LANDMINE]={Damage=e and {value=e.value} or nil,Tears=t and {value=t} or nil}}}
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
    function sp:SetFrame(anim,f) if not (missingAnims or {})[anim] then self.anim=anim end; self.frame=f end
    function sp:GetAnimation() return self.anim or "" end
    function sp:Render(pos) renders[#renders+1]={anim=self.anim,frame=self.frame,pos=pos,red=self.Color~=nil} end
    return sp
end

serial=0; entities={}; players={}; frame=0
local E={}; E.__index=E
function E:Exists() return not self.removed end
function E:Remove() self.removed=true end
function E:GetData() self.data=self.data or {} return self.data end
function E:ToPlayer() return self.Type==EntityType.ENTITY_PLAYER and self or nil end
function E:ToEffect() return self.Type==EntityType.ENTITY_EFFECT and self or nil end
function E:ToTear() return self.Type==EntityType.ENTITY_TEAR and self or nil end
function E:IsActiveEnemy() return self.enemy==true and not self.dead end
function E:IsVulnerableEnemy() return self.enemy==true and not self.invulnerable end
function E:HasEntityFlags(f) return ((self.flags or 0) & f)~=0 end
function E:IsDead() return self.dead==true end
function E:IsCoopGhost() return self.ghost==true end
function E:HasCollectible(id) return (self.items or {})[id]==true end
function E:GetBombFlags() return self.bombFlags or 0 end
function E:ToBomb() return self.Type==EntityType.ENTITY_BOMB and self or nil end
function E:SetExplosionCountdown(n) self.countdown=n end
function E:GetCollectibleNum(id) return id==LANDMINE and (self.copies or 0) or 0 end
function E:TakeDamage(amount,flags,source) self.hits=self.hits or {}; self.hits[#self.hits+1]={amount=amount,flags=flags,source=source} end
function E:AddCacheFlags(f) self.cacheFlags=(self.cacheFlags or 0)|f end
function E:EvaluateItems() self.evaluated=(self.evaluated or 0)+1 end
function E:EnableWeaponType(t,on) self.weapons=self.weapons or {}; self.weapons[#self.weapons+1]=t..(on and "+" or "-") end
function E:HasWeaponType(t) return (self.has or {})[t]==true end
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
    FindByType=function(t)
        local list={}
        for _,e in ipairs(entities) do if e.Type==t and not e.removed then list[#list+1]=e end end
        return list
    end,
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
-- The grid: 40-unit cells, 15 wide; the rock cell is index 2*15+7 (around 300,100).
function room:GetGridWidth() return 15 end
function room:GetGridIndex(p) return math.floor(p.Y/40)*15+math.floor(p.X/40) end
function room:GetGridEntity(i)
    if i==2*15+7 then return {CollisionClass=GridCollisionClass.COLLISION_SOLID,Position=Vector(300,100)} end
    if i==6*15+7 then return {CollisionClass=GridCollisionClass.COLLISION_PIT,Position=Vector(300,250)} end
    return nil
end
function room:GetGridCollisionAtPos(p)
    if math.abs(p.X-300)<=20 and math.abs(p.Y-100)<=20 then return GridCollisionClass.COLLISION_SOLID end
    if math.abs(p.X-300)<=20 and math.abs(p.Y-250)<=20 then return GridCollisionClass.COLLISION_PIT end
    return GridCollisionClass.COLLISION_NONE
end
engineBombs=false   -- whether Game() offers BombDamage and BombTearflagEffects
-- Lasers shot by angle: what was asked of each one.
lasers={}
EntityLaser={ShootAngle=function(variant,pos,angle,timeout,offset,source)
    local l=entity({Type=7,Variant=variant,Position=pos,Velocity=Vector.Zero,SpawnerEntity=source,
        angle=angle,Timeout=timeout,MaxDistance=0})
    lasers[#lasers+1]=l
    return l
end}
function Game()
    local g={GetRoom=function() return room end,GetFrameCount=function() return frame end,
        GetNumPlayers=function() return #players end,
        Spawn=function(_,t,v,pos,vel,spawner,s,seed)
            return entity({Type=t,Variant=v,SubType=s,Position=pos,Velocity=vel,SpawnerEntity=spawner,InitSeed=seed})
        end}
    if engineBombs then
        -- The engine's bomb damage hurts every enemy within radius + its size.
        g.BombDamage=function(_,pos,damage,radius,line,source,flags)
            bombCalls[#bombCalls+1]={pos=pos,damage=damage,radius=radius,flags=flags,source=source}
            for _,e in ipairs(entities) do
                if e.enemy and not e.removed and e.Position:Distance(pos)<=radius+(e.Size or 0) then
                    e:TakeDamage(damage,DamageFlag.DAMAGE_EXPLOSION,EntityRef(source))
                end
            end
        end
        g.BombTearflagEffects=function(_,pos,radius,flags,source)
            flagCalls[#flagCalls+1]={pos=pos,radius=radius,flags=flags,source=source}
        end
    end
    return g
end
reloadLandmine()
M.data.dudChance=0   -- the tests lay their own duds
function player(copies)
    local p=entity({Type=EntityType.ENTITY_PLAYER,Variant=0,Position=Vector(20,150),copies=copies or 1,Damage=3.5,
        Luck=0,Size=10,MaxFireDelay=10})
    players[#players+1]=p
    return p
end
-- A tear made by `spawner` at (x,y) moving at (vx,vy); the module takes it up
-- on the next update, as it does any tear in the room.
function tear(spawner,x,y,vx,vy,seed)
    return entity({Type=EntityType.ENTITY_TEAR,Variant=0,Position=Vector(x,y),Velocity=Vector(vx or 10,vy or 0),
        SpawnerEntity=spawner,InitSeed=seed or 12345,Height=-23.75})
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
        self.assertNotIn('fireTear', row)
        self.assertIn('"TECH_X", "SPIRIT_SWORD" }', row)
        for kept in ('MONSTROS_LUNG', 'LUDOVICO_TECHNIQUE', 'C_SECTION'):
            self.assertNotIn(kept, row)
        self.assertIn('evaluateCache = "landmine.onEvaluateCache"', row)
        self.assertIn('postUpdate = "landmine.onUpdate"', row)
        self.assertIn('cache = "damage firedelay shotspeed range weapon"', row)
        self.assertNotIn('weaponFiredOptional', row)
        self.assertIn('stackable = true', row)
        # The user's EID (2026-11-25), Korean verbatim with stat icons.
        kr = (ROOT / 'scripts/locale/kr.lua').read_text(encoding='utf-8')
        entry = kr[kr.index('LANDMINE = {'):kr.index('UNDERDOG = {')]
        for line in ('{{Range}} 고정 사거리 +40, {{Damage}} 공격력 x0.33, {{Tears}} 연사 x0.8, {{Shotspeed}} 탄속 -0.2',
                     '#공격이 눈물로 고정되고, 눈물마다 지뢰를 2번 뿌립니다({{Luck}} 행운 5마다 +1번)',
                     '#중첩할 때마다 한 번에 뿌리는 지뢰가 1개씩 늘어납니다',
                     '#{{Tears}} 지뢰를 뿌리기 시작하면 5 / 연사 초 뒤 다시 가득 채워집니다', '#지뢰 피해는 내 공격력과 같습니다',
                     '#지뢰의 10%는 녹슨 지뢰로 2배의 피해와 나에게 데미지를 줍니다',
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
        # 2 drops (user decision 2026-11-28) and one more for every 5 luck, one
        # mine a drop with one copy.
        self.assertEqual(result, (2, 2, 3, 4, 7, 2, 22))
        copies = self.run_lua('return T.payload(0,2), T.payload(5,3), T.payload(10,2), T.perDrop(0), T.perDrop(3)')
        # Copies raise the mines laid at once and the most a tear holds.
        self.assertEqual(copies, (4, 9, 8, 1, 3))

    def test_reload_waits_five_fire_intervals(self):
        result = self.run_lua('return T.reloadDelay(10), T.reloadDelay(1.5), T.reloadDelay(-5), T.reloadDelay(nil)')
        # 5 x (MaxFireDelay + 1) updates, at least one.
        self.assertEqual(result, (55, 12.5, 1, 55))

    def test_pure_rules(self):
        result = self.run_lua('''
            local vz=T.launchSpeed(-23.75,10,0.9)
            return T.mineDamage(3.5), T.mineDamage(-1), T.within(40,40,0), T.within(51,40,10),
                -23.75+vz*10+0.5*0.9*100
        ''')
        damage, negative, edge, outside, landing = result
        self.assertEqual((damage, negative, edge, outside), (3.5, 0, True, False))
        self.assertAlmostEqual(landing, 0, places=9)

    def test_a_tear_lays_its_two_mines_then_refills_after_five_fire_intervals(self):
        result = self.run_lua('''
            local p=player(); p.Damage=1.2
            local t=tear(p,20,150,6,0)
            local laid={}
            for i=1,80 do update(1); laid[i]=T.evidence().laid end
            local straddle,worst=true,0
            local list=M.mines()
            for k=1,#list-1 do
                local a,b=list[k].y-150,list[k+1].y-150
                if a*b>=0 then straddle=false end
                worst=math.max(worst,math.abs(a),math.abs(b))
            end
            return laid[2],laid[3],laid[8],laid[9],laid[15],laid[57],laid[58],laid[64],T.evidence().reloads,
                #T.carriers(),straddle,worst,list[1].damage,list[1].owner.Ref==p,closest()
        ''')
        (before, first, waiting, second, third, emptied, refilled, again, reloads, carriers, straddle, worst,
         damage, owner, gap) = result
        # One copy: a mine on the 3rd update (half of 6), then every 6, sides
        # alternating, two in all; 5 x (10 + 1) = 55 updates after the first
        # mine (the 58th update) it holds 2 again and lays on at once.
        self.assertEqual((before, first, waiting, second, third), (0, 1, 1, 2, 2))
        self.assertEqual((emptied, refilled, again, reloads, carriers), (2, 3, 4, 1, 1))
        self.assertTrue(straddle)
        self.assertLessEqual(worst, 40)
        self.assertEqual((damage, owner), (1.2, True))
        self.assertGreaterEqual(gap, 26)

    def test_the_refill_runs_from_the_first_mine(self):
        result = self.run_lua('''
            local p=player()
            local t=tear(p,20,150,4,0)
            local laid={}
            for i=1,60 do update(1); laid[i]=T.evidence().laid end
            return laid[57], laid[58], T.evidence().reloads
        ''')
        # The first mine on the 3rd update, so the stock is full again on the
        # 58th (55 later) and the next mine goes down then.
        self.assertEqual(result, (2, 3, 1))

    def test_copies_lay_more_mines_at_once_and_hold_more(self):
        result = self.run_lua('''
            local function run(copies)
                M.onNewRoom(); T.resetEvidence()
                for _,e in ipairs(entities) do if e.Type==EntityType.ENTITY_TEAR then e.removed=true end end
                players={}
                local p=player(copies)
                tear(p,20,150,6,0)
                local laid={}
                for i=1,20 do update(1); laid[i]=T.evidence().laid end
                local up,down=0,0
                for _,r in ipairs(M.mines()) do if r.y<150 then up=up+1 else down=down+1 end end
                return laid[3], laid[9], laid[15], laid[20], up, down
            end
            local a={run(2)}
            local b={run(3)}
            return a[1],a[2],a[3],a[4],a[5],a[6],b[1],b[2],b[3],b[4],b[5],b[6]
        ''')
        # Two copies: a pair at once, 4 in all, one of each pair to each side;
        # three copies: three at once (two to one side), 6 in all.
        self.assertEqual(result[:6], (2, 4, 4, 4, 2, 2))
        self.assertEqual(result[6:10], (3, 6, 6, 6))
        self.assertEqual(sum(result[10:]), 6)

    def test_every_tear_of_the_holders_lays_mines_and_no_other(self):
        result = self.run_lua('''
            local DP=ConchBlessingRequire("scripts.lib.damage_provenance")
            local p=player()
            local main=tear(p,40,60,0,0)
            local satellite=tear(main,200,60,0,0)          -- a tear another tear made
            local familiar=entity({Type=EntityType.ENTITY_FAMILIAR,Variant=1,Position=Vector(80,80),Player=p})
            tear(familiar,300,200,0,0)
            local hidden=tear(p,400,200,0,0); hidden.Visible=false
            local harmless=tear(p,500,200,0,0); harmless.CollisionDamage=0
            local fromMine=tear(p,500,60,0,0); DP.markTriggeredAttack(fromMine,"landmine")
            update(1)
            local taken={}
            for _,c in ipairs(T.carriers()) do taken[#taken+1]=c.ref.Ref==main and "main" or c.ref.Ref==satellite and "satellite" or "other" end
            table.sort(taken)
            update(1)
            return table.concat(taken,","), T.evidence().fired, T.tearOwner(satellite)==p, T.tearOwner(fromMine)==p
        ''')
        self.assertEqual(result, ('main,satellite', 2, True, True))

    def test_a_tear_standing_still_lays_its_pairs_where_it_is(self):
        result = self.run_lua('''
            local p=player(); p.Position=Vector(500,280)
            local t=tear(p,200,150,0,0)
            update(30)
            local near=true
            for _,r in ipairs(M.mines()) do if math.sqrt((r.x-200)^2+(r.y-150)^2)>60 then near=false end end
            return T.evidence().placed>=2, #M.mines()>=2, near, #T.carriers()
        ''')
        self.assertEqual(result, (True, True, True, 1))

    def test_losing_the_item_stops_the_refill(self):
        result = self.run_lua('''
            local p=player()
            local t=tear(p,20,150,6,0)
            update(16)
            local held=#T.carriers()
            p.copies=0
            update(1)
            local gone=#T.carriers()
            update(70)
            return held, gone, T.evidence().reloads, T.evidence().laid
        ''')
        self.assertEqual(result, (1, 0, 0, 2))

    def test_a_mine_flies_from_the_tear_and_lands_where_it_was_aimed(self):
        result = self.run_lua('''
            local p=player(); local t=tear(p,20,150,10,0)
            update(3)
            local r=M.mines()[1]
            local start,flying,lifts=r.px,r.flying,{}
            for i=1,10 do update(1); lifts[i]=r.z end
            return start, flying, lifts[1]<-23.75, lifts[9]<0, lifts[10], r.px==r.x and r.py==r.y,
                r.flying, r.idle==true, r.landed, T.evidence().landed
        ''')
        start, flying, rose, airborne, last, placed, still_flying, idle, landed, count = result
        self.assertEqual((start, flying), (50, True))
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
        self.assertEqual(result, (2, True, True))

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
        self.assertEqual(result, (1, 1, 2, 0, 0))

    def test_a_spill_with_no_free_ground_piles_up_and_off_the_floor_is_lost(self):
        result = self.run_lua('''
            local p=player()
            for x=30,130,10 do for y=100,200,10 do T.lay(p,Vector(x,y),3) end end
            local t=tear(p,60,150,10,0); update(1); t:Remove(); update(1)
            local piled=T.evidence().piled
            -- Inside the rock: no floor anywhere it could spill.
            local before=T.evidence().laid
            room.GetGridCollisionAtPos=function() return GridCollisionClass.COLLISION_SOLID end
            local t2=tear(p,300,100,10,0); update(1); t2:Remove(); update(1)
            return piled, T.evidence().laid-before, T.evidence().lost
        ''')
        self.assertEqual(result, (2, 0, 2))

    def test_luck_adds_mines_to_every_tear(self):
        result = self.run_lua('''
            local p=player(); p.Luck=10
            tear(p,20,150,10,0)
            update(40)
            return T.evidence().laid
        ''')
        self.assertEqual(result, 4)

    def test_only_a_living_holders_tears_carry_mines(self):
        result = self.run_lua('''
            local other=player(0); tear(other,20,40,10,0)
            local dead=player(); dead.dead=true; tear(dead,20,150,10,0)
            local ghost=player(); ghost.ghost=true; tear(ghost,20,280,10,0)
            local holder=player()
            local familiar=entity({Type=EntityType.ENTITY_FAMILIAR,Variant=1,Position=Vector(80,80),Player=holder})
            tear(familiar,80,80,10,0)
            tear(nil,80,80,10,0)
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
            update(8)
            local early=r.dead==true
            update(1)
            return early, r.dead==true, T.evidence().landedOn, victim.hits and #victim.hits or 0,
                victim.hits and victim.hits[1].amount
        ''')
        # the holder's 2 (user decision 2026-11-27)
        self.assertEqual(result, (False, True, 1, 1, 2))

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
        self.assertEqual(result, (False, True, 1, 1, 0, 0, 3, 4, True, 0, 1, 0, 0, False, 0))

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
        # Four mines of 3 each.
        self.assertEqual(result, (4, 12, 1, 1, 0))

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
        # Monstro's Lung (7), Ludovico (8) and C Section's fetuses (14) shoot tears and stay.
        # The tears are StatsAPI's x0.8 item multiplier, not an addition.
        self.assertEqual(result, (None, 1600, '2-,3-,4-,5-,6-,9-,10-,13-,15-,1+', None, None, None))

    def test_a_weapon_that_shoots_its_own_tears_gets_no_plain_tears_beside_it(self):
        result = self.run_lua('''
            local out={}
            for _,w in ipairs({WeaponType.WEAPON_LUDOVICO_TECHNIQUE,WeaponType.WEAPON_MONSTROS_LUNGS,WeaponType.WEAPON_FETUS}) do
                local p=player(1); p.has={[w]=true}
                M.onEvaluateCache(nil,p,CacheFlag.CACHE_WEAPON)
                out[#out+1]=table.concat(p.weapons,",")
            end
            return table.unpack(out)
        ''')
        # The other weapons go; the tears are not switched on beside Ludovico,
        # Monstro's Lung or C Section's fetuses.
        for weapons in result:
            self.assertEqual(weapons, '2-,3-,4-,5-,6-,9-,10-,13-,15-')

    def test_the_damage_multiplier_follows_holding_the_item(self):
        result = self.run_lua('''
            local p=player(0)
            update(1)
            local none=multipliers[p.hash]
            p.copies=2; update(1)
            local held=multipliers[p.hash] and multipliers[p.hash].value
            local tears=tearsMult[p.hash]
            local evaluated=p.evaluated
            update(5)
            local steady=#applied
            p.copies=0; update(1)
            return none==nil, held, tears, evaluated, steady, multipliers[p.hash]==nil, tearsMult[p.hash]==nil,
                p.evaluated, p.cacheFlags
        ''')
        # x0.33 damage and x0.8 tears, each set once on pickup and removed on
        # loss; stats evaluated at each change.
        self.assertEqual(result, (True, 0.33, 0.8, 1, 2, True, True, 2, 1 | 2 | 4 | 8 | 32))

    def test_nothing_is_evaluated_before_the_save_is_loaded(self):
        result = self.run_lua('''
            local loaded=false
            ConchBlessing.SaveManager={IsLoaded=function() return loaded end}
            local p=player(1)
            update(3)
            local early=p.evaluated
            loaded=true
            update(1)
            ConchBlessing.SaveManager=nil
            return early, p.evaluated, multipliers[p.hash] and multipliers[p.hash].value
        ''')
        # A reload in the middle of a run: the sync waits for the save, then runs.
        self.assertEqual(result, (None, 1, 0.33))

    def test_shot_speed_drops_by_a_fifth_once(self):
        result = self.run_lua('''
            local p=player(3)
            M.onEvaluateCache(nil,p,CacheFlag.CACHE_SHOTSPEED)
            local none=player(0)
            M.onEvaluateCache(nil,none,CacheFlag.CACHE_SHOTSPEED)
            return p.shotAdded, none.shotAdded
        ''')
        self.assertEqual(result, (-0.2, None))

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

    def test_the_numbers_the_user_set(self):
        result = self.run_lua('''
            reloadLandmine()
            local d=M.data
            local out={d.drops,d.tearsMultiplier,d.shotSpeed,d.synergyChance,d.dudChance,d.dudDamage,
                T.rolls(0.05,0.1),T.rolls(0.1,0.1),T.rolls(0.5,0.1),T.rolls(nil,0.1)}
            d.dudChance=0
            return table.unpack(out)
        ''')
        # User decisions 2026-11-28: 2 drops, x0.8 tears and -0.2 shot speed,
        # each bomb synergy on its tenth, one mine in ten a dud that goes off as
        # a real bomb for twice the damage.
        self.assertEqual(result, (2, 0.8, -0.2, 0.1, 0.1, 2, True, False, False, False))

    def test_only_one_mine_in_ten_carries_the_bomb_flags(self):
        result = self.run_lua('''
            engineBombs=true
            local p=player(); p.Position=Vector(500,280)
            p.bombFlags=TearFlags.TEAR_CROSS_BOMB|TearFlags.TEAR_HOMING
            local plain=T.lay(p,Vector(140,150),3); plain.bombRoll=0.5
            local victim=enemy(142,150,10)
            update(M.data.armFrames); update(1)
            local plainFlags, plainCross, plainHit=#flagCalls, T.evidence().crossed, victim.hits and #victim.hits or 0
            victim:Remove()
            local flagged=T.lay(p,Vector(400,150),3); flagged.bombRoll=0.05
            local second=enemy(402,150,10)
            update(M.data.armFrames); update(1)
            return plainFlags, plainCross, plainHit, #flagCalls, T.evidence().crossed>=4, T.evidence().flagged
        ''')
        # A roll above the 10%: a plain blast (the enemy still hit once, no flag
        # effects); below it: the bomb flags ride on it.
        self.assertEqual(result, (0, 0, 1, 1, True, 1))

    def test_each_bomb_synergy_owns_a_tenth_of_the_roll(self):
        result = self.run_lua('''
            local p=player()
            p.bombFlags=TearFlags.TEAR_BURN|TearFlags.TEAR_SCATTER_BOMB|TearFlags.TEAR_HOMING|TearFlags.TEAR_EGG
            local function on(roll) return T.mineFlags(p,{bombRoll=roll,seed=5}) end
            local function name(flag)
                if flag==nil then return "none" end
                for key,value in pairs(TearFlags) do if value==flag then return key end end
                return "other"
            end
            local slots={}
            for _,roll in ipairs({0,0.099,0.1,0.95,0.9999,1}) do slots[#slots+1]=tostring(T.slotOf(roll)) end
            slots[#slots+1]=tostring(T.slotOf(nil))
            local before=name(on(0.95))
            p.items={[CollectibleType.COLLECTIBLE_NANCY_BOMBS]=true}
            local nancy=name(on(0.95))
            return table.concat(slots," "), name(on(0.15)), name(on(0.45)), name(on(0.05)), before,
                nancy~="none" and nancy~="other" and nancy~="TEAR_HOMING", name(T.mineFlags(nil,{bombRoll=0.15}))
        ''')
        # Ten tenths in order; a held synergy rides on its own tenth only, one
        # not held gives nothing, Nancy Bombs' tenth gives one of the other nine.
        self.assertEqual(result, ('1 1 2 10 10 nil nil', 'TEAR_BURN', 'TEAR_SCATTER_BOMB', 'none', 'none', True, 'none'))

    def test_no_bomb_flags_means_no_synergy_on_any_tenth(self):
        result = self.run_lua('''
            local p=player()
            local any=false
            for i=0,99 do if T.mineFlags(p,{bombRoll=i/100,seed=3}) then any=true end end
            return any
        ''')
        self.assertFalse(result)

    def test_a_slot_carries_what_its_item_sets_beside_its_own_flag(self):
        result = self.run_lua('''
            local sticky=T.slotFlags(8,TearFlags.TEAR_STICKY|TearFlags.TEAR_EGG|TearFlags.TEAR_BURN)
            local eggOnly=T.slotFlags(8,TearFlags.TEAR_EGG)
            local all=T.slotFlags(7,nil)
            return sticky==(TearFlags.TEAR_STICKY|TearFlags.TEAR_EGG), eggOnly, all==(TearFlags.TEAR_GHOST_BOMB|TearFlags.TEAR_SPECTRAL)
        ''')
        # Sticky Bombs' tenth: its own flag and the egg (its slowing creep), not
        # the burn another item sets; without its own flag, nothing; Ghost
        # Bombs' tenth for Nancy: both of its flags.
        self.assertEqual(result, (True, None, True))

    def test_a_dud_is_decided_when_it_is_laid(self):
        result = self.run_lua('''
            local p=player(); p.Position=Vector(500,280)
            M.data.dudChance=1
            local all=T.lay(p,Vector(100,150),3)
            M.data.dudChance=0
            local none=T.lay(p,Vector(200,150),3)
            local forced=T.lay(p,Vector(300,150),3,nil,nil,{dud=true})
            local spared=T.lay(p,Vector(300,250),3,nil,nil,{dud=false})
            local a=T.lay(p,Vector(400,150),3,nil,nil,{seed=777})
            local b=T.lay(p,Vector(400,250),3,nil,nil,{seed=777})
            return all.dud, none.dud, forced.dud, spared.dud, a.bombRoll==b.bombRoll, a.seed, T.evidence().duds
        ''')
        self.assertEqual(result, (True, False, True, False, True, 777, 2))

    def test_a_dud_goes_off_as_a_real_bomb(self):
        result = self.run_lua('''
            engineBombs=true
            local p=player(); p.Position=Vector(500,250); p.Damage=3
            p.bombFlags=TearFlags.TEAR_CROSS_BOMB
            local dud=T.lay(p,Vector(100,150),3,nil,nil,{dud=true}); dud.bombRoll=0.5
            local near=enemy(134,150,10)
            update(M.data.armFrames)
            p.Position=Vector(110,150)
            update(1)
            local c=bombs()[1]
            return dud.dead==true, #bombs(), c and c.Position.X, c and c.ExplosionDamage, c and c.Flags==0,
                c and c.SpawnerEntity==p, c and c.countdown, #bombCalls, near.hits and #near.hits or 0,
                T.evidence().realBlasts, #flagCalls
        ''')
        # A real bomb of the holder's at the dud, exploding at once with twice
        # the mine's damage (user decision 2026-11-28) and no flags (its roll
        # missed); none of the mine's fake blast or flag parts.
        self.assertEqual(result, (True, 1, 100, 6, True, True, 0, 0, 0, 1, 0))

    def test_a_dud_carries_the_flags_when_its_roll_does(self):
        result = self.run_lua('''
            engineBombs=true
            local p=player(); p.Position=Vector(500,250)
            p.bombFlags=TearFlags.TEAR_CROSS_BOMB
            local dud=T.lay(p,Vector(100,150),3,nil,nil,{dud=true}); dud.bombRoll=0.05
            update(M.data.armFrames)
            enemy(100,150,10)
            update(1)
            return #bombs(), bombs()[1] and bombs()[1].Flags==TearFlags.TEAR_CROSS_BOMB
        ''')
        self.assertEqual(result, (1, True))

    def test_a_dud_an_enemy_or_a_blast_sets_off_is_a_real_bomb_too(self):
        result = self.run_lua('''
            engineBombs=true
            local p=player(); p.Position=Vector(500,250)
            local mine=T.lay(p,Vector(100,150),3,nil,nil,{dud=false})
            local dud=T.lay(p,Vector(130,150),3,nil,nil,{dud=true})
            update(M.data.armFrames)
            enemy(100,150,10)
            update(1)
            local afterMine=#bombs()
            update(M.data.chainDelay)
            return afterMine, mine.dead==true, dud.dead==true, #bombs()
        ''')
        # The plain mine's fake blast sets the dud off a moment later, as a real bomb.
        self.assertEqual(result, (0, True, True, 1))

    def test_without_the_real_bomb_a_dud_blasts_like_a_mine(self):
        result = self.run_lua('''
            EntityType.ENTITY_BOMB=nil
            local p=player(); p.Position=Vector(500,250)
            local dud=T.lay(p,Vector(100,150),3,nil,nil,{dud=true})
            local near=enemy(134,150,10)
            update(M.data.armFrames)
            enemy(100,150,10)
            update(1)
            return dud.dead==true, near.hits and #near.hits or 0, near.hits and near.hits[1].amount,
                T.evidence().realBlasts
        ''')
        self.assertEqual(result, (True, 1, 6, 0))

    def test_a_dud_has_its_own_frames(self):
        result = self.run_lua('''
            local p=player(); p.Position=Vector(500,280)
            T.lay(p,Vector(100,150),3,nil,nil,{dud=true})
            T.lay(p,Vector(200,150),3,nil,nil,{dud=false})
            update(T.frames.Land+2)
            renders={}
            M.onFieldRender(nil,T.field(),Vector(0,0))
            local names={}
            for _,r in ipairs(renders) do names[#names+1]=(r.pos.X<100 and "dud" or "plain")..":"..r.anim end
            table.sort(names)
            return table.concat(names," "), T.frames.DudIdle
        ''')
        self.assertEqual(result, ('dud:DudIdle plain:Idle', 8))

    def test_bomb_flags_ride_on_a_fake_explosion(self):
        result = self.run_lua('''
            engineBombs=true
            local p=player(); p.Position=Vector(500,280)
            p.bombFlags=TearFlags.TEAR_CROSS_BOMB|TearFlags.TEAR_GHOST_BOMB|TearFlags.TEAR_SCATTER_BOMB
            local m=T.lay(p,Vector(140,150),4); m.bombRoll=T.slotRoll("bomber_boy")
            local victim=enemy(142,150,10)
            local beside=enemy(300,135,10)          -- beside the rock: struck plainly, the rock stays
            local r=T.lay(p,Vector(300,150),4); r.bombRoll=T.slotRoll("bomber_boy")
            update(M.data.armFrames)
            update(1)
            local crossFlags=flagCalls[1] and flagCalls[1].flags==TearFlags.TEAR_CROSS_BOMB
            -- one mine on Ghost Bombs' tenth, one on Scatter Bombs'
            local g=T.lay(p,Vector(140,260),4); g.bombRoll=T.slotRoll("ghost_bombs")
            local s=T.lay(p,Vector(450,200),4); s.bombRoll=T.slotRoll("scatter_bombs")
            update(M.data.armFrames)
            enemy(140,260,10); enemy(450,200,10)
            update(1)
            local e=T.evidence()
            local ghosts=0
            for _,x in ipairs(entities) do if x.Type==EntityType.ENTITY_EFFECT and x.Variant==189 and x.SubType==1 then ghosts=ghosts+1 end end
            local queued=#T.scattered()
            update(M.data.scatterDelay)
            return #bombCalls>=1, bombCalls[1].radius, bombCalls[1].pos.X, #flagCalls>=1, flagCalls[1].pos.X,
                e.crossed>=4 and crossFlags, ghosts==1, queued>=1, T.evidence().scattered==queued and #T.scattered()==0,
                beside.hits and #beside.hits or 0, victim.hits and victim.hits[1].source.Entity==p
        ''')
        (damaged, radius, at, effects, effects_at, crossed, ghosts, queued, scattered, beside, source) = result
        # Engine bomb damage at the enemy's own spot with radius 1; the flags'
        # effects once at the mine; each mine carries only its tenth's flag:
        # the cross, a Purgatory soul (인's 창귀, 1000.189.1) and scatter blasts
        # from three mines.
        self.assertEqual((damaged, radius, at, effects, effects_at), (True, 1, 142, True, 140))
        self.assertEqual((crossed, ghosts, queued, scattered), (True, True, True, True))
        self.assertGreaterEqual(beside, 1)
        self.assertTrue(source)

    def test_brimstone_bombs_shoot_four_short_beams_of_our_own(self):
        # User decision 2026-11-27: four Brimstone beams as long as the blast
        # reaches, shot here from the mine; the engine's own beams across the
        # room are left out by dropping the flag from its flag effects.
        result = self.run_lua('''
            engineBombs=true
            local p=player(); p.Position=Vector(500,280); p.Damage=3
            p.bombFlags=TearFlags.TEAR_BRIMSTONE_BOMB|TearFlags.TEAR_HOMING
            local m=T.lay(p,Vector(140,150),3); m.bombRoll=T.slotRoll("brimstone_bombs")
            local victim=enemy(142,150,10)
            update(M.data.armFrames)
            update(1)
            local angles,lengths,damages,detached,at={}, {}, {}, true, true
            for _,l in ipairs(lasers) do
                angles[#angles+1]=l.angle; lengths[#lengths+1]=l.MaxDistance; damages[#damages+1]=l.CollisionDamage
                detached=detached and l.DisableFollowParent==true
                at=at and l.Position.X==m.spot.X and l.Position.Y==m.spot.Y and l.SpawnerEntity==p and l.Timeout==M.data.beamTime
            end
            local passed=flagCalls[1] and flagCalls[1].flags
            return #lasers, table.concat(angles," "), table.concat(lengths," "), table.concat(damages," "), detached, at,
                passed==0, T.evidence().beams
        ''')
        # Each hit a tenth of the mine's 3 (a beam hits about 14 times).
        self.assertEqual(result, (4, '0 90 180 270', '40 40 40 40', '0.3 0.3 0.3 0.3', True, True, True, 4))

    def test_the_ghost_is_handed_to_tigers_soul_handling_at_half_damage(self):
        # User decision 2026-11-27: the Purgatory soul's burst hits each enemy
        # once for half the mine's damage, through 인's own soul handling.
        result = self.run_lua('''
            engineBombs=true
            local handed={}
            ConchBlessing.tiger={adoptSoul=function(soul,owner,opts) handed[#handed+1]={soul=soul,owner=owner,opts=opts} return true end}
            local p=player(); p.Position=Vector(500,280)
            p.bombFlags=TearFlags.TEAR_GHOST_BOMB
            local m=T.lay(p,Vector(140,150),4); m.bombRoll=T.slotRoll("ghost_bombs")
            enemy(142,150,10)
            update(M.data.armFrames)
            update(1)
            ConchBlessing.tiger=nil
            local h=handed[1]
            return #handed, h.soul.Variant, h.soul.SubType, h.soul.SpawnerEntity==p, h.owner==p, h.opts.damage,
                h.opts.fear, h.opts.procKey
        ''')
        self.assertEqual(result, (1, 189, 1, True, True, 2, False, 'landmine'))

    def test_without_brimstone_bombs_no_beams_and_only_the_slots_flag_passes(self):
        result = self.run_lua('''
            engineBombs=true
            local p=player(); p.Position=Vector(500,280)
            p.bombFlags=TearFlags.TEAR_HOMING|TearFlags.TEAR_GHOST_BOMB
            local m=T.lay(p,Vector(140,150),3); m.bombRoll=T.slotRoll("ghost_bombs")
            enemy(142,150,10)
            update(M.data.armFrames)
            update(1)
            return #lasers, flagCalls[1].flags==TearFlags.TEAR_GHOST_BOMB, T.evidence().ghosts
        ''')
        self.assertEqual(result, (0, True, 1))

    def test_the_cross_and_scatter_blasts_set_off_mines_too(self):
        result = self.run_lua('''
            engineBombs=true
            local p=player(); p.Position=Vector(500,280)
            local function run(flags,key)
                M.onNewRoom(); T.resetEvidence()
                p.bombFlags=flags
                local a=T.lay(p,Vector(140,150),4); a.bombRoll=key and T.slotRoll(key) or 0.99
                local b=T.lay(p,Vector(215,150),4)      -- 75 away: past the mine's 40, inside the arm's
                update(M.data.armFrames)
                local victim=enemy(140,150,10)
                update(1)
                victim:Remove()
                local queued=T.scattered()[1]
                local c=queued and T.lay(p,Vector(queued.x,queued.y),4)
                update(M.data.scatterDelay+M.data.chainDelay+1)
                return b.dead==true, c and c.dead==true or false
            end
            local crossB=run(TearFlags.TEAR_CROSS_BOMB,"bomber_boy")
            local plainB=run(0)
            local _, scatterC=run(TearFlags.TEAR_SCATTER_BOMB,"scatter_bombs")
            return crossB, plainB, scatterC
        ''')
        # Bomber Boy's arm reaches the mine 75 away; without it nothing does;
        # a Scatter Bombs blast sets off the mine lying where it lands.
        self.assertEqual(result, (True, False, True))

    def test_a_blast_keeps_rocks_by_striking_near_them_plainly(self):
        result = self.run_lua('''
            engineBombs=true
            local near=T.gridNear(room,Vector(300,120),M.data.gridClear)
            local pit=T.gridNear(room,Vector(300,280),M.data.gridClear)
            local open=T.gridNear(room,Vector(100,150),M.data.gridClear)
            return near, pit, open, T.hasFlag(TearFlags.TEAR_HOMING|8,TearFlags.TEAR_HOMING), T.hasFlag(0,TearFlags.TEAR_HOMING),
                M.onPlayerDamage(nil,player())==nil
        ''')
        # A rock 20 away is close; a pit is no bomb target; open floor is clear;
        # outside a blast a player's damage goes through.
        self.assertEqual(result, (True, False, False, True, False, True))

    def test_homing_bombs_make_lying_mines_creep_to_the_nearest_enemy(self):
        result = self.run_lua('''
            local p=player(); p.Position=Vector(500,280); p.bombFlags=TearFlags.TEAR_HOMING
            local m=T.lay(p,Vector(100,150),3)
            update(M.data.armFrames)
            local target=enemy(200,150,10)
            local before=m.x
            update(20)
            local moved=m.x-before
            local key=m.key
            p.bombFlags=0
            local x=m.x
            update(5)
            return moved>17 and moved<19, key==math.floor(m.x/40)*4096+math.floor(m.y/40), m.legs==true, m.x==x,
                m.walking==false
        ''')
        # 0.9 units an update toward the enemy; filed where it is; it keeps its
        # legs and stops when the bombs no longer home.
        self.assertEqual(result, (True, True, True, True, True))

    def test_a_sheet_without_walk_draws_a_walking_mine_lying(self):
        result = self.run_lua('''
            missingAnims={Walk=true}
            reloadLandmine()
            local p=player(); p.Position=Vector(500,280); p.bombFlags=TearFlags.TEAR_HOMING
            local m=T.lay(p,Vector(100,150),3)
            update(M.data.armFrames)
            enemy(200,150,10)
            update(5)
            renders={}
            M.onFieldRender(nil,T.field(),Vector(0,0))
            missingAnims=nil
            return m.legs==true, #renders, renders[1] and renders[1].anim, #errors
        ''')
        # The reload kept the old sheet: the mine still shows (as a lying one) and
        # the missing animation is reported once.
        self.assertEqual(result, (True, 1, 'Idle', 1))

    def test_new_room_forgets_mines_and_tears_and_unload_removes_them(self):
        result = self.run_lua('''
            local p=player(); local m=T.lay(p,Vector(100,150),3)
            local f=T.field()
            M.onModUnload()
            local removed=f.removed==true and T.field()==nil
            tear(p,20,150,10,0)
            update(1)
            local carried=#T.carriers()
            M.onNewRoom()
            return removed, carried, #M.mines(), #T.carriers(), tileCount()
        ''')
        self.assertEqual(result, (True, 1, 0, 0, 0))


if __name__ == '__main__':
    unittest.main()
