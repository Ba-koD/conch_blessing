"""지뢰 (Landmine) through its shipped Lua: every attack the holder makes drops
a mine at their feet, mines pile up where they stand, who drops none, the
missing cap, how mines fall, land and arm, the blast (twice the holder's
damage, enemies only), a pile going off together and the chain to nearby
mines. The user's design: an enemy stepping on a mine sets it off and it never
hurts the player (2026-11-15); every attack in a room with enemies drops a
mine at the feet, with no spacing and no cap, so mines may overlap
(2026-11-23). These are Lua regressions with doubles, not proof of engine
behaviour (`cb test landmine`).
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
function V:Normalized() local l=self:Length() return Vector(self.X/l,self.Y/l) end
Vector=setmetatable({},{__call=function(_,x,y) return setmetatable({X=x,Y=y},V) end})
Vector.Zero=Vector(0,0)
function Color(...) return {...} end
ModCallbacks={}
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
function E:IsCoopGhost() return self.ghost==true end
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
-- around (200,250); `roomEnemies` is how many enemies are alive in it.
room={}; roomEnemies=1
function room:IsPositionInRoom(p,m) return p.X>=m and p.X<=400-m and p.Y>=m and p.Y<=300-m end
function room:GetCenterPos() return Vector(200,150) end
function room:GetAliveEnemiesCount() return roomEnemies end
function room:GetGridCollisionAtPos(p)
    if math.abs(p.X-200)<=20 and math.abs(p.Y-100)<=20 then return GridCollisionClass.COLLISION_SOLID end
    if math.abs(p.X-200)<=20 and math.abs(p.Y-250)<=20 then return GridCollisionClass.COLLISION_PIT end
    return GridCollisionClass.COLLISION_NONE
end
function Game() return {GetRoom=function() return room end,GetFrameCount=function() return frame end,
    GetNumPlayers=function() return #players end} end
reloadLandmine()
function player(copies)
    local p=entity({Type=EntityType.ENTITY_PLAYER,Variant=0,Position=Vector(50,150),copies=copies or 1,Damage=3.5})
    players[#players+1]=p
    return p
end
-- One attack by `owner` (REPENTOGON's weapon trigger), the player standing at (x,y).
function attackAt(owner,x,y)
    frame=frame+1
    local p=owner and owner:ToPlayer()
    if p and x then p.Position=Vector(x,y) end
    M.onWeaponFired(nil,Vector(1,0),1,owner)
end
-- One tear fired by `spawner`, the player standing at (x,y) (the base fallback).
function tearAt(spawner,x,y)
    frame=frame+1
    local p=spawner and spawner:ToPlayer()
    if p and x then p.Position=Vector(x,y) end
    M.onFireTear(nil,entity({Type=EntityType.ENTITY_TEAR,Variant=0,Position=Vector(x or 0,y or 0),SpawnerEntity=spawner}))
end
function enemy(x,y,size) return entity({Type=10,Variant=0,Position=Vector(x,y),Size=size or 10,enemy=true}) end
function xs() local list={} for i,r in ipairs(M.mines()) do list[i]=r.x end return table.concat(list,",") end
function liveMines() local n=0 for _,r in ipairs(M.mines()) do if r.ref.Ref:Exists() then n=n+1 end end return n end
function age(frames) for _,r in ipairs(M.mines()) do r.ref.Ref.FrameCount=r.ref.Ref.FrameCount+frames end end
function update(n) for _=1,(n or 1) do frame=frame+1; M.onUpdate() end end
function tileCount() local n=0 for _,list in pairs(T.tiles()) do n=n+#list end return n end
function explosions()
    local n=0
    for _,e in ipairs(entities) do
        if e.Type==EntityType.ENTITY_EFFECT and e.Variant==EffectVariant.BOMB_EXPLOSION then n=n+1 end
    end
    return n
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

    def test_registers_the_attack_event_with_a_tear_fallback_through_item_data(self):
        self.assertTrue(self.g.M.available)
        self.assertEqual(len(list(self.g.callbacks.keys())), 0)
        self.assertEqual(len(list(self.g.errors.values())), 0)
        registry = (ROOT / 'scripts/conch_blessing_items.lua').read_text(encoding='utf-8')
        row = registry[registry.index('    LANDMINE = {'):registry.index('    UNDERDOG = {')]
        self.assertIn('weaponFiredOptional = "landmine.onWeaponFired"', row)
        self.assertIn('fireTear = "landmine.onFireTear"', row)
        self.assertNotIn('postPEffectUpdate', row)
        manager = (ROOT / 'scripts/callback_manager.lua').read_text(encoding='utf-8')
        mapping = manager[manager.index('    weaponFiredOptional = {'):]
        mapping = mapping[:mapping.index('},')]
        self.assertIn('MC_POST_TRIGGER_WEAPON_FIRED', mapping)
        self.assertIn('optional = true', mapping)
        warnings = {
            'en': '#{{Warning}} REPENTOGON recommended',
            'kr': '#{{Warning}} REPENTOGON 권장',
            'urimal': '#{{Warning}} 덧붙임 도우미(REPENTOGON)를 쓰면 좋습니다',
        }
        for lang, warning in warnings.items():
            text = (ROOT / f'scripts/locale/{lang}.lua').read_text(encoding='utf-8')
            entry = text[text.index('LANDMINE = {'):text.index('UNDERDOG = {')]
            self.assertIn(warning, entry, lang)
            self.assertNotIn('2칸', entry, lang)
            self.assertNotIn('tiles walked', entry, lang)
        # No spacing and no gap: every attack drops one.
        self.assertIsNone(self.g.M.data.spacing)
        self.assertIsNone(self.g.M.data.gap)
        self.assertFalse(self.g.T.weaponEvent())

    def test_every_attack_drops_a_mine_where_the_holder_stands(self):
        result = self.run_lua('''
            local p=player(); p.Damage=4.5
            for i=0,4 do attackAt(p,50+i*10,150) end
            local r=M.mines()[1]; local m=r.ref.Ref
            return xs(), m.Variant, m.Position.Y, r.damage, m.SpawnerEntity==p, m.sprite.anim, m.DepthOffset,
                m.PositionOffset.Y, T.evidence().laid
        ''')
        # Ten units apart: no spacing, no gap.
        self.assertEqual(result, ('50,60,70,80,90', 7790, 150, 4.5, True, 'Fall', -1000, -20, 5))

    def test_attacks_in_place_pile_mines_up(self):
        result = self.run_lua('''
            local p=player()
            for _=1,6 do attackAt(p,120,150) end
            return xs(), tileCount(), T.evidence().laid
        ''')
        self.assertEqual(result, ('120,120,120,120,120,120', 6, 6))

    def test_mine_falls_from_the_hands_and_arms_after_landing(self):
        result = self.run_lua('''
            local p=player(); attackAt(p,100,150)
            local r=M.mines()[1]; local m=r.ref.Ref
            local start, anim = m.PositionOffset.Y, m.sprite.anim
            local lifts={}
            local stepper=enemy(100,150,10)
            for i=1,6 do update(1); lifts[i]=m.PositionOffset.Y end
            local landedAnim, landed, armedOnLanding = m.sprite.anim, r.landed, r.armed
            m.FrameCount=m.FrameCount+M.data.armFrames-1; update(1)
            local early=m.removed==true
            m.FrameCount=m.FrameCount+1; update(1)
            return start, anim, table.concat(lifts,","), landedAnim, landed, armedOnLanding, early, m.removed==true,
                stepper.hits and #stepper.hits or 0, T.evidence().landed
        ''')
        # An enemy under a falling mine sets nothing off.
        self.assertEqual(result, (-20, 'Fall', '-18.5,-15.5,-11.0,-5.0,0,0', 'Land', True, None, False, True, 1, 1))

    def test_no_mine_in_a_room_without_enemies(self):
        result = self.run_lua('''
            local p=player(); roomEnemies=0
            for i=1,5 do attackAt(p,50+i*20,150) end
            local before=#M.mines()
            roomEnemies=1
            attackAt(p,300,150)
            return before, xs()
        ''')
        self.assertEqual(result, (0, '300'))

    def test_a_mine_holds_the_holders_damage_when_it_was_laid(self):
        result = self.run_lua('''
            local p=player(); p.Damage=3.5
            attackAt(p,50,150); attackAt(p,50,150)
            p.Damage=10
            attackAt(p,50,150)
            local list={}
            for i,r in ipairs(M.mines()) do list[i]=tostring(r.damage) end
            return table.concat(list,",")
        ''')
        self.assertEqual(result, '3.5,3.5,10')

    def test_only_a_living_holders_own_attacks_drop_mines(self):
        result = self.run_lua('''
            local other=player(0); attackAt(other,50,40)
            local dead=player(); dead.dead=true; attackAt(dead,50,150)
            local ghost=player(); ghost.ghost=true; attackAt(ghost,50,280)
            local holder=player()
            local familiar=entity({Type=EntityType.ENTITY_FAMILIAR,Variant=1,Position=Vector(80,80),Player=holder})
            attackAt(familiar)
            attackAt(nil)
            return #M.mines(), #errors
        ''')
        # A familiar's weapon is its own, even when its player holds Landmine.
        self.assertEqual(result, (0, 0))

    def test_losing_the_item_stops_the_mines_and_regaining_it_resumes(self):
        result = self.run_lua('''
            local p=player(); attackAt(p,50,150); attackAt(p,60,150)
            local before=xs()
            p.copies=0; attackAt(p,70,150); attackAt(p,80,150)
            local lost=xs()
            p.copies=1; attackAt(p,90,150)
            return before, lost, xs()
        ''')
        self.assertEqual(result, ('50,60', '50,60', '50,60,90'))

    def test_copies_do_not_multiply_the_mines(self):
        result = self.run_lua('''
            local p=player(3); attackAt(p,50,150)
            return #M.mines()
        ''')
        self.assertEqual(result, 1)

    def test_no_mine_over_a_rock_or_pit_or_off_the_floor(self):
        result = self.run_lua('''
            local p=player()
            attackAt(p,200,100)   -- the rock
            attackAt(p,200,250)   -- the pit
            attackAt(p,398,150)   -- past the floor margin
            attackAt(p,230,250)   -- floor beside the pit
            return xs(), T.evidence().blocked
        ''')
        self.assertEqual(result, ('230', 3))

    def test_no_cap_on_mines(self):
        result = self.run_lua('''
            local p=player(); local first
            for i=1,200 do
                attackAt(p,20+(i%10)*10,20+math.floor(i/10)*10)   -- clear of the rock and the pit
                first=first or M.mines()[1].ref.Ref
            end
            return #M.mines(), liveMines(), T.evidence().laid, first.removed==true
        ''')
        self.assertEqual(result, (200, 200, 200, False))

    def test_without_repentogon_each_tear_the_holder_fires_drops_a_mine(self):
        result = self.run_lua('''
            local p=player()
            tearAt(p,60,150); tearAt(p,60,150); tearAt(p,90,150)
            local holder=player()
            local familiar=entity({Type=EntityType.ENTITY_FAMILIAR,Variant=1,Position=Vector(80,80),Player=holder})
            tearAt(familiar,80,80)
            tearAt(nil,80,80)
            M.onFireTear(nil,nil)
            return T.weaponEvent(), xs()
        ''')
        self.assertEqual(result, (False, '60,60,90'))

    def test_with_repentogon_the_tears_lay_nothing(self):
        result = self.run_lua('''
            REPENTOGON={Real=true}
            ModCallbacks.MC_POST_TRIGGER_WEAPON_FIRED=1100
            reloadLandmine()
            local p=player()
            tearAt(p,60,150); tearAt(p,90,150)
            local tears=#M.mines()
            attackAt(p,120,150)
            return T.weaponEvent(), tears, xs()
        ''')
        # Only the attack counts, so a multishot attack drops one mine.
        self.assertEqual(result, (True, 0, '120'))

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

    def test_a_pile_goes_off_together_with_one_explosion(self):
        result = self.run_lua('''
            local p=player()
            for _=1,4 do attackAt(p,100,150) end
            update(6); age(M.data.armFrames)
            local stepper=enemy(100,150,10)
            local near=enemy(140,150,10)
            update(1)
            local function total(e) local n=0 for _,h in ipairs(e.hits or {}) do n=n+h.amount end return n end
            return T.evidence().exploded, #stepper.hits, total(stepper), total(near), explosions(),
                T.evidence().pictures, #played, #M.mines(), T.evidence().chained
        ''')
        # Four mines of 2 x 3.5 each: 28 to every enemy within reach.
        self.assertEqual(result, (4, 4, 28, 28, 1, 1, 1, 0, 0))

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

    def test_one_blast_sound_per_update_and_a_picture_per_spot(self):
        result = self.run_lua('''
            local p=player()
            for i=0,4 do T.lay(p,Vector(60+i*45,150),3) end
            age(M.data.armFrames)
            enemy(60,150,10); enemy(150,150,10); enemy(240,150,10)
            update(1)
            return T.evidence().exploded, #played, explosions()
        ''')
        self.assertEqual(result, (3, 1, 3))

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
            return #M.mines(), tileCount()
        ''')
        self.assertEqual(result, (1, 1))

    def test_new_room_forgets_mines_and_unload_removes_them(self):
        result = self.run_lua('''
            local p=player(); local m=T.lay(p,Vector(100,150),3)
            M.onModUnload()
            local removed=m.removed==true
            attackAt(p,120,150)
            local laid=#M.mines()
            M.onNewRoom()
            return removed, laid, #M.mines(), tileCount()
        ''')
        self.assertEqual(result, (True, 1, 0, 0))

    def test_pure_rules(self):
        result = self.run_lua('return T.mineDamage(3.5), T.mineDamage(-1), T.within(60,60,0), T.within(71,60,10)')
        self.assertEqual(result, (7, 0, True, False))


if __name__ == '__main__':
    unittest.main()
