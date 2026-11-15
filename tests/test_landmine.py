"""지뢰 (Landmine) through its shipped Lua: which tear deaths lay a mine and
where, the ten-mine cap, arming, the blast (twice the tear's damage, enemies
only) and the chain to nearby mines. The user's design (2026-11-15): a tear
that falls or strikes a wall without hitting an enemy leaves a mine; an enemy
stepping on it sets it off; it never hurts the player. These are Lua
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
if NO_REPENTOGON then ModCallbacks={} end
EntityType={ENTITY_PLAYER=1,ENTITY_TEAR=2,ENTITY_FAMILIAR=3,ENTITY_EFFECT=1000}
EffectVariant={BOMB_EXPLOSION=1,POOF01=15}
EntityPartition={ENEMY=8}
EntityFlag={FLAG_FRIENDLY=1<<29}
DamageFlag={DAMAGE_EXPLOSION=1<<2}
GridCollisionClass={COLLISION_NONE=0,COLLISION_SOLID=4}
SoundEffect={SOUND_BOOM=37}
played={}
function SFXManager() return {Play=function(_,id,volume) played[#played+1]={id=id,volume=volume} end} end
errors={}; callbacks={}
ConchBlessing={ItemData={},printError=function(m) errors[#errors+1]=m end,printDebug=function() end}
function ConchBlessing:AddCallback(id,fn) callbacks[id]=fn end
function GetPtrHash(e) return e.hash end
function EntityPtr(e) return {Ref=e} end
function EntityRef(e) return {Entity=e} end

serial=0; entities={}
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
    Spawn=function(t,v,s,pos,vel,spawner)
        return entity({Type=t,Variant=v,SubType=s,Position=pos,Velocity=vel,SpawnerEntity=spawner})
    end,
    FindInRadius=function(pos,radius,partition)
        local list={}
        for _,e in ipairs(entities) do
            if not e.removed and e.enemy and e.Position:Distance(pos)<=radius then list[#list+1]=e end
        end
        return list
    end,
}
-- A room 0..400 x 0..300 with one rock cell around (200,100).
room={}
function room:IsPositionInRoom(p,m) return p.X>=m and p.X<=400-m and p.Y>=m and p.Y<=300-m end
function room:GetClampedPosition(p,m) return Vector(math.max(m,math.min(400-m,p.X)),math.max(m,math.min(300-m,p.Y))) end
function room:GetGridCollisionAtPos(p)
    if math.abs(p.X-200)<=20 and math.abs(p.Y-100)<=20 then return GridCollisionClass.COLLISION_SOLID end
    return GridCollisionClass.COLLISION_NONE
end
function Game() return {GetRoom=function() return room end,GetFrameCount=function() return 0 end} end
M=ConchBlessingRequire("scripts.items.collectibles.landmine")
T=M._test
function player(copies) return entity({Type=EntityType.ENTITY_PLAYER,Variant=0,Position=Vector(50,150),copies=copies or 1}) end
function tear(owner,x,y,vx,vy,damage)
    return entity({Type=EntityType.ENTITY_TEAR,Variant=0,Position=Vector(x,y),Velocity=Vector(vx or 10,vy or 0),
        SpawnerEntity=owner,CollisionDamage=damage or 3.5})
end
function die(t) callbacks[ModCallbacks.MC_POST_TEAR_DEATH](nil,t) end
function collide(t,with) callbacks[ModCallbacks.MC_POST_TEAR_COLLISION](nil,t,with,false) end
function enemy(x,y,size) return entity({Type=10,Variant=0,Position=Vector(x,y),Size=size or 10,enemy=true}) end
function liveMines() local n=0 for _,r in ipairs(M.mines()) do if r.ref.Ref:Exists() then n=n+1 end end return n end
function age(frames) for _,r in ipairs(M.mines()) do r.ref.Ref.FrameCount=r.ref.Ref.FrameCount+frames end end
function update(n) for _=1,(n or 1) do M.onUpdate() end end
'''


class LandmineTests(unittest.TestCase):
    def setUp(self, no_repentogon=False):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        g = self.lua.globals()
        g.loadsource = source
        g.NO_REPENTOGON = no_repentogon
        self.lua.execute(SETUP)
        self.g = g

    def run_lua(self, code):
        return self.lua.execute(code)

    def test_registers_repentogon_tear_callbacks(self):
        self.assertTrue(self.g.M.available)
        self.assertIsNotNone(self.g.callbacks[1033])
        self.assertIsNotNone(self.g.callbacks[1233])
        self.assertEqual(len(list(self.g.errors.values())), 0)

    def test_without_repentogon_registers_nothing(self):
        self.setUp(no_repentogon=True)
        self.assertFalse(self.g.M.available)
        self.assertEqual(len(list(self.g.callbacks.keys())), 0)

    def test_missed_tear_lays_a_mine_where_it_fell(self):
        result = self.run_lua('''
            local p=player(); local t=tear(p,120,150,10,0,4.5); die(t)
            local r=M.mines()[1]; local m=r.ref.Ref
            return #M.mines(), m.Variant, m.Position.X, m.Position.Y, r.damage, m.SpawnerEntity==p, m.sprite.anim, m.DepthOffset
        ''')
        self.assertEqual(result, (1, 7790, 120, 150, 4.5, True, 'Appear', -1000))

    def test_hit_tear_familiar_tear_and_non_holder_lay_nothing(self):
        result = self.run_lua('''
            local p=player()
            local hit=tear(p,120,150); collide(hit,enemy(125,150)); die(hit)
            local friendlyHit=tear(p,140,150); local f=enemy(145,150); f.flags=EntityFlag.FLAG_FRIENDLY; collide(friendlyHit,f); die(friendlyHit)
            local familiar=entity({Type=EntityType.ENTITY_FAMILIAR,Variant=1,Position=Vector(0,0)})
            familiar.SpawnerEntity=p; die(tear(familiar,160,150))
            local other=player(0); die(tear(other,180,150))
            return #M.mines(), T.evidence().hits, M.mines()[1].ref.Ref.Position.X
        ''')
        # Only the tear that touched a friendly enemy counts as a miss.
        self.assertEqual(result, (1, 1, 140))

    def test_tear_over_a_rock_steps_back_to_floor_and_walls_clamp_inside(self):
        result = self.run_lua('''
            local p=player()
            die(tear(p,200,100,10,0))         -- died on the rock, flying right
            die(tear(p,420,150,10,0))         -- struck the right wall
            local a,b=M.mines()[1].ref.Ref.Position,M.mines()[2].ref.Ref.Position
            return a.X, a.Y, b.X, b.Y
        ''')
        rock_x, rock_y, wall_x, wall_y = result
        self.assertLess(rock_x, 180)            # back out of the rock, toward where it came from
        self.assertGreaterEqual(rock_x, 160)    # within the 40-unit backtrack
        self.assertEqual(rock_y, 100)
        self.assertLessEqual(wall_x, 394)       # inside the floor margin
        self.assertEqual(wall_y, 150)

    def test_no_floor_within_reach_lays_nothing(self):
        result = self.run_lua('''
            local p=player()
            local free=room.GetGridCollisionAtPos
            room.GetGridCollisionAtPos=function() return GridCollisionClass.COLLISION_SOLID end
            die(tear(p,120,150,10,0))
            room.GetGridCollisionAtPos=free
            return #M.mines(), T.evidence().skipped
        ''')
        self.assertEqual(result, (0, 1))

    def test_eleventh_mine_removes_the_owners_oldest_only(self):
        result = self.run_lua('''
            local p, q = player(), player()
            local first=nil
            for i=1,10 do die(tear(p,20+i*10,250)) end
            first=M.mines()[1].ref.Ref
            die(tear(q,30,40))
            die(tear(p,300,250))
            local mine=0; local theirs=0
            for _,r in ipairs(M.mines()) do
                if r.owner.Ref==p then mine=mine+1 else theirs=theirs+1 end
            end
            return mine, theirs, first.removed==true, T.evidence().trimmed
        ''')
        self.assertEqual(result, (10, 1, True, 1))

    def test_unarmed_mine_waits_and_armed_mine_blasts_enemies_only(self):
        result = self.run_lua('''
            local p=player(); die(tear(p,100,150,10,0,3))
            local m=M.mines()[1].ref.Ref
            local stepper=enemy(102,150,10)
            local near=enemy(150,150,10)        -- 50 away: inside 60 + its size
            local far=enemy(200,200,10)         -- outside
            local friend=enemy(110,160,10); friend.flags=EntityFlag.FLAG_FRIENDLY
            update(1)
            local before=m.removed==true
            m.FrameCount=T and M.data.armFrames
            update(1)
            local function took(e) return e.hits and #e.hits or 0 end
            local hit=stepper.hits[1]
            return before, m.removed==true, took(stepper), took(near), took(far), took(friend),
                hit.amount, hit.flags, hit.source.Entity==m, took(p), #played
        ''')
        self.assertEqual(result, (False, True, 1, 1, 0, 0, 6, 4, True, 0, 1))

    def test_blast_sets_off_nearby_mines_a_moment_later(self):
        result = self.run_lua('''
            local p=player()
            die(tear(p,100,150)); die(tear(p,150,150)); die(tear(p,300,150))
            age(M.data.armFrames)
            local victim=enemy(100,150,10)
            update(1)
            local afterFirst=liveMines()
            victim:Remove()
            update(M.data.chainDelay)
            return afterFirst, liveMines(), T.evidence().chained, T.evidence().exploded
        ''')
        self.assertEqual(result, (2, 1, 1, 2))

    def test_appear_hands_over_to_idle(self):
        result = self.run_lua('''
            local p=player(); die(tear(p,100,150))
            local m=M.mines()[1].ref.Ref
            m:GetSprite(); m.finished=true
            update(1)
            return m.sprite.anim
        ''')
        self.assertEqual(result, 'Idle')

    def test_new_room_forgets_mines_and_unload_removes_them(self):
        result = self.run_lua('''
            local p=player(); die(tear(p,100,150)); local m=M.mines()[1].ref.Ref
            M.onModUnload()
            local removed=m.removed==true
            die(tear(p,120,150)); M.onNewRoom()
            return removed, #M.mines()
        ''')
        self.assertEqual(result, (True, 0))

    def test_pure_rules(self):
        result = self.run_lua('return T.mineDamage(3.5), T.mineDamage(-1), T.excess(9,10), T.excess(10,10), T.excess(12,10)')
        self.assertEqual(result, (7, 0, 0, 1, 3))


if __name__ == '__main__':
    unittest.main()
