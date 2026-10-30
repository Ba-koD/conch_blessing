"""인 (Tiger): production Lua with engine doubles.

A kill by the holder (the enemy's last hit traced to them through
DamageProvenance, HP at or below 0) rolls 1/3 per copy, at most certain, and
raises the vanilla Purgatory soul where the enemy died. Its Ghost Bombs
explosion's own sourceless ticks are cancelled, and each enemy it reaches takes
one hit of 3x the holder's damage from the explosion, then fear for 3 seconds.
These doubles cannot show how the engine flies the soul or what its explosion
reaches; `conch_test tiger` covers those in game.
"""
from pathlib import Path
import re
import unittest
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]

HARNESS = r"""
package=nil
ModCallbacks={MC_ENTITY_TAKE_DMG=11,MC_POST_EFFECT_INIT=54,MC_POST_ENTITY_REMOVE=67}
CallbackPriority={EARLY=-100,LATE=100}
EntityType={ENTITY_PLAYER=1,ENTITY_EFFECT=1000,ENTITY_SHOPKEEPER=17,ENTITY_FIREPLACE=33}
EffectVariant={PURGATORY=189,ENEMY_GHOST=144}
EntityFlag={FLAG_FRIENDLY=1<<29}
TIGER=950
local V={}; V.__index=V
Vector=setmetatable({},{__call=function(_,x,y) return setmetatable({X=x,Y=y},V) end})
function V:Distance(o) return math.sqrt((self.X-o.X)^2+(self.Y-o.Y)^2) end
Vector.Zero=Vector(0,0)
local nextHash=0
function GetPtrHash(e) return e.hash end
function EntityPtr(e) return {Ref=e} end
function EntityRef(e) return {Entity=e} end
callbacks={}
local function entity(fields)
    nextHash=nextHash+1
    local e={hash=nextHash,data={},exists=true,dead=false,Position=Vector(0,0),Size=10,Type=10,Variant=0,SubType=0}
    for k,v in pairs(fields or {}) do e[k]=v end
    function e:GetData() return self.data end
    function e:Exists() return self.exists end
    function e:IsDead() return self.dead end
    function e:ToPlayer() return self.isPlayer and self or nil end
    function e:ToNPC() return self.isNPC and self or nil end
    function e:ToFamiliar() return nil end
    function e:ToEffect() return self.Type==EntityType.ENTITY_EFFECT and self or nil end
    return e
end
newEntity=entity
function newPlayer(copies,damage)
    local p=entity({isPlayer=true,Type=EntityType.ENTITY_PLAYER,Damage=damage or 3.5})
    p.copies=copies or 0
    p.rolls={}
    function p:GetCollectibleNum(id) return id==TIGER and self.copies or 0 end
    function p:IsCoopGhost() return false end
    function p:GetCollectibleRNG(id)
        assert(id==TIGER)
        return {RandomFloat=function() return table.remove(p.rolls,1) or 0.99 end,Next=function() return 7 end}
    end
    return p
end
hits={}; fears={}
function newNPC(hp,fields)
    local n=entity({isNPC=true,Type=10,HitPoints=hp or 10,flags=0})
    for k,v in pairs(fields or {}) do n[k]=v end
    function n:HasEntityFlags(f) return (self.flags & f)~=0 end
    function n:IsEnemy() return true end
    function n:TakeDamage(amount,flags,source,countdown)
        hits[#hits+1]={target=self,amount=amount,flags=flags,source=source and source.Entity}
        return true
    end
    function n:AddFear(source,duration) fears[#fears+1]={target=self,source=source.Entity,duration=duration} end
    return n
end
players={}
spawned={}
local game={}
function game:GetNumPlayers() return #players end
function game:Spawn(t,v,pos,vel,spawner,sub,seed)
    local e=entity({Type=t,Variant=v,SubType=sub,Position=pos,SpawnerEntity=spawner,seed=seed})
    spawned[#spawned+1]=e
    return e
end
Game=function() return game end
Isaac={GetItemIdByName=function(name) return name=='Tiger' and TIGER or -1 end,
    GetPlayer=function(i) return players[i+1] end}
errors={}
ConchBlessing={printError=function(e) errors[#errors+1]=e end,printDebug=function() end,
    AddCallback=function(_,id,fn,filter) callbacks[#callbacks+1]={id=id,fn=fn,filter=filter} end,
    AddPriorityCallback=function(_,id,priority,fn) callbacks[#callbacks+1]={id=id,fn=fn,priority=priority} end}
M=dofile(root..'/scripts/items/collectibles/tiger.lua')
T=M._test
function kill(npc,source,amount)
    M.onTakeDamageLate(nil,npc,amount or 30,0,EntityRef(source))
    npc.HitPoints=npc.HitPoints-(amount or 30)
    M.onEntityKill(nil,npc)
end
"""


class TigerTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        globals_ = self.lua.globals()
        globals_.root = ROOT.as_posix()
        self.lua.execute(r'''
            local root=root
            require=function(name)
                local path=root..'/'..name:gsub('%.','/')..'.lua'
                return dofile(path)
            end
        ''')
        self.lua.execute(HARNESS)

    def run_lua(self, script):
        self.lua.execute(script)

    def test_chance_is_a_third_per_copy_up_to_certain(self):
        self.run_lua(r'''
            local expected={[0]=0,[1]=1/3,[2]=2/3,[3]=1,[4]=1,[10]=1}
            for copies,chance in pairs(expected) do
                assert(math.abs(T.chanceFor(copies)-chance)<1e-12,'copies '..copies..' -> '..T.chanceFor(copies))
            end
            assert(T.chanceFor(-2)==0 and T.chanceFor(nil)==0 and T.chanceFor(2.7)==T.chanceFor(2))
            assert(T.chanceFor(3)==1,'three copies are exactly certain')
            assert(T.spawns(0.3333,1/3) and not T.spawns(1/3,1/3),'the roll is strictly below the chance')
            assert(T.spawns(0.999999,1) and not T.spawns(0,0))
            assert(T.blastDamage(3.5)==10.5 and T.blastDamage(nil)==0)
        ''')

    def test_a_holder_kill_raises_one_ghost_where_the_enemy_died(self):
        self.run_lua(r'''
            local p=newPlayer(3); players={p}
            local npc=newNPC(10); npc.Position=Vector(40,60)
            kill(npc,p)
            assert(#spawned==1,'one soul')
            local soul=spawned[1]
            assert(soul.Type==EntityType.ENTITY_EFFECT and soul.Variant==EffectVariant.PURGATORY and soul.SubType==1)
            assert(soul.Position.X==40 and soul.Position.Y==60 and soul.SpawnerEntity==p and soul.seed==7)
            local chain=soul.data.__ConchBlessingDamageProvenance.procChain
            assert(chain[T.procKey],'the soul carries the Tiger lineage')
            local e=T.evidence()
            assert(e.kills==1 and e.rolls==1 and e.spawned==1 and e.lastRoll.chance==1)
            assert(npc.data[T.hitKey]==nil,'one roll per death')
            M.onEntityKill(nil,npc)
            assert(#spawned==1,'a second kill report of the same death rolls nothing')
        ''')

    def test_the_roll_follows_each_holders_own_copies(self):
        self.run_lua(r'''
            local p=newPlayer(1); players={p}
            p.rolls={0.34,0.33}
            kill(newNPC(10),p); assert(#spawned==0,'0.34 is not below 1/3')
            kill(newNPC(10),p); assert(#spawned==1,'0.33 is')
            p.copies=2; p.rolls={0.66}
            kill(newNPC(10),p); assert(#spawned==2,'two copies: 2/3')
            local other=newPlayer(0); players={p,other}
            kill(newNPC(10),other); assert(#spawned==2 and T.evidence().rolls==3,'a non-holder in co-op never rolls')
        ''')

    def test_kills_that_are_not_the_holders_raise_nothing(self):
        self.run_lua(r'''
            local p=newPlayer(3); players={p}
            local enemy=newNPC(1000)
            kill(newNPC(10),enemy)                 -- another enemy's hit
            kill(newNPC(10),nil)                   -- no source
            local direct=newNPC(1000)              -- the holder hit it, then a direct Kill()
            M.onTakeDamageLate(nil,direct,5,0,EntityRef(p)); direct.HitPoints=995
            M.onEntityKill(nil,direct)
            local friendly=newNPC(10); friendly.flags=EntityFlag.FLAG_FRIENDLY
            kill(friendly,p)                       -- an ally is not an enemy
            local fire=newNPC(10); fire.Type=EntityType.ENTITY_FIREPLACE
            kill(fire,p)                           -- furniture is not a kill
            local dead=newPlayer(3); dead.dead=true; players={p,dead}
            kill(newNPC(10),dead)                  -- a dead holder does not act
            assert(#spawned==0 and T.evidence().rolls==0,'nothing rolled: '..#spawned)
            players={newPlayer(0)}
            local unrecorded=newNPC(10)
            M.onTakeDamageLate(nil,unrecorded,30,0,EntityRef(p))
            assert(unrecorded.data[T.hitKey]==nil,'without a holder no hit is recorded')
        ''')

    def test_the_last_hit_decides_the_kill(self):
        self.run_lua(r'''
            local p=newPlayer(3); players={p}
            local enemy=newNPC(1000)
            local npc=newNPC(10)
            M.onTakeDamageLate(nil,npc,5,0,EntityRef(p))
            kill(npc,enemy)
            assert(#spawned==0,'an enemy landed the last hit')
            local other=newNPC(10)
            M.onTakeDamageLate(nil,other,5,0,EntityRef(enemy))
            kill(other,p)
            assert(#spawned==1,'the holder landed the last hit')
            -- A tear the holder fired: ownership goes through the spawner.
            local tear=newEntity({Type=2,SpawnerEntity=p})
            kill(newNPC(10),tear)
            assert(#spawned==2,'a tear of the holder counts')
        ''')

    def test_the_explosion_hits_each_enemy_once_for_three_times_damage_and_fears_it(self):
        self.run_lua(r'''
            local p=newPlayer(3,3.5); players={p}
            local victim=newNPC(10); victim.Position=Vector(0,0)
            kill(victim,p)
            local soul=spawned[1]
            soul.Position=Vector(100,0)
            M.onUpdate()                                         -- it flies; we follow it
            M.onEntityRemove(nil,soul)                           -- it bursts...
            local blast=newEntity({Type=1000,Variant=EffectVariant.ENEMY_GHOST,SubType=1,
                Position=Vector(110,10),SpawnerEntity=p,CollisionDamage=7})
            M.onEffectInit(nil,blast)                            -- ...into its explosion
            assert(T.evidence().claimed==1,'the explosion is claimed')
            assert(blast.data.__ConchBlessingDamageProvenance.procChain[T.procKey])
            local a,b=newNPC(1000),newNPC(1000)
            a.Position,b.Position=Vector(120,0),Vector(150,40)
            -- The vanilla ticks: sourceless, flags 0, 2x damage. Each is cancelled.
            assert(M.onTakeDamageEarly(nil,a,7,0,EntityRef(nil))==false)
            assert(M.onTakeDamageEarly(nil,b,7,0,EntityRef(nil))==false)
            assert(M.onTakeDamageEarly(nil,a,7,0,EntityRef(nil))==false,'a later tick is cancelled too')
            -- LATE does not mistake a cancelled tick for a hit.
            a.data[T.hitKey]='kept'
            M.onTakeDamageLate(nil,a,7,0,EntityRef(nil))
            assert(a.data[T.hitKey]=='kept')
            M.onUpdate()
            assert(#hits==2,'one hit per enemy, got '..#hits)
            for _,hit in ipairs(hits) do
                assert(hit.amount==10.5 and hit.flags==0 and hit.source==blast,'3x damage from the explosion')
            end
            assert(#fears==2 and fears[1].duration==90 and fears[1].source==p,'three seconds of fear')
            M.onTakeDamageEarly(nil,a,7,0,EntityRef(nil)); M.onUpdate()
            assert(#hits==2,'the same enemy is never hit twice by one explosion')
            local e=T.evidence()
            assert(e.cancelled==4 and e.hits==2 and e.feared==2)
        ''')

    def test_only_its_own_ticks_are_cancelled(self):
        self.run_lua(r'''
            local p=newPlayer(3,3.5); players={p}
            kill(newNPC(10),p)
            local soul=spawned[1]
            M.onEntityRemove(nil,soul)
            local blast=newEntity({Type=1000,Variant=EffectVariant.ENEMY_GHOST,SubType=1,
                Position=Vector(0,0),SpawnerEntity=p,CollisionDamage=7})
            M.onEffectInit(nil,blast)
            local near,far=newNPC(1000),newNPC(1000)
            far.Position=Vector(400,0)
            assert(M.onTakeDamageEarly(nil,near,7,0,EntityRef(p))==nil,'a hit with a source')
            assert(M.onTakeDamageEarly(nil,near,7,4,EntityRef(nil))==nil,'a hit with flags')
            assert(M.onTakeDamageEarly(nil,near,5,0,EntityRef(nil))==nil,'another amount')
            assert(M.onTakeDamageEarly(nil,far,7,0,EntityRef(nil))==nil,'out of reach')
            assert(M.onTakeDamageEarly(nil,p,7,0,EntityRef(nil))==nil,'never the player')
            blast.exists=false
            assert(M.onTakeDamageEarly(nil,near,7,0,EntityRef(nil))==nil,'a finished explosion')
            M.onUpdate()
            assert(next(T.blasts())==nil,'the finished explosion is forgotten')
        ''')

    def test_an_explosion_is_claimed_only_by_the_owners_ghost_nearby(self):
        self.run_lua(r'''
            local p,q=newPlayer(3),newPlayer(0); players={p,q}
            kill(newNPC(10),p)
            local soul=spawned[1]
            M.onEntityRemove(nil,soul)
            local foreign=newEntity({Type=1000,Variant=EffectVariant.ENEMY_GHOST,SubType=1,Position=Vector(0,0),SpawnerEntity=q})
            M.onEffectInit(nil,foreign)
            local distant=newEntity({Type=1000,Variant=EffectVariant.ENEMY_GHOST,SubType=1,Position=Vector(500,0),SpawnerEntity=p})
            M.onEffectInit(nil,distant)
            local bomb=newEntity({Type=1000,Variant=EffectVariant.ENEMY_GHOST,SubType=0,Position=Vector(0,0),SpawnerEntity=p})
            M.onEffectInit(nil,bomb)
            assert(T.evidence().claimed==0,'another player, far away, or a flying ghost is not ours')
            M.onUpdate()
            assert(next(T.souls())==nil,'a burst ghost left unclaimed is forgotten after the update')
            local own=newEntity({Type=1000,Variant=EffectVariant.ENEMY_GHOST,SubType=1,Position=Vector(0,0),SpawnerEntity=p})
            M.onEffectInit(nil,own)
            assert(T.evidence().claimed==0,'nothing left to claim')
        ''')

    def test_a_ghost_kill_is_the_holders_and_raises_the_next(self):
        self.run_lua(r'''
            local p=newPlayer(3,3.5); players={p}
            kill(newNPC(10),p)
            M.onEntityRemove(nil,spawned[1])
            local blast=newEntity({Type=1000,Variant=EffectVariant.ENEMY_GHOST,SubType=1,
                Position=Vector(0,0),SpawnerEntity=p,CollisionDamage=7})
            M.onEffectInit(nil,blast)
            local second=newNPC(7)
            M.onTakeDamageEarly(nil,second,7,0,EntityRef(nil))
            M.onUpdate()
            assert(hits[1].source==blast)
            kill(second,blast,10.5)                -- the explosion's own hit kills it
            assert(#spawned==2 and spawned[2].SpawnerEntity==p,'the chain continues with the holder')
            assert(T.evidence().kills==2)
        ''')

    def test_reset_forgets_ghosts_and_explosions(self):
        self.run_lua(r'''
            local p=newPlayer(3); players={p}
            kill(newNPC(10),p)
            assert(next(T.souls())~=nil)
            M.reset()
            assert(next(T.souls())==nil and next(T.blasts())==nil)
        ''')

    def test_callbacks_and_priorities(self):
        self.run_lua(r'''
            local found={}
            for _,c in ipairs(callbacks) do
                found[#found+1]=tostring(c.id)..':'..tostring(c.priority or c.filter)
                if c.fn==M.onTakeDamageEarly then assert(c.priority==CallbackPriority.EARLY) end
                if c.fn==M.onTakeDamageLate then assert(c.priority==CallbackPriority.LATE) end
                if c.fn==M.onEffectInit then assert(c.filter==EffectVariant.ENEMY_GHOST) end
                if c.fn==M.onEntityRemove then assert(c.filter==EntityType.ENTITY_EFFECT) end
            end
            assert(#callbacks==4,table.concat(found,','))
        ''')

    def test_registry_eid_and_cap_follow_the_module(self):
        items = (ROOT / 'scripts/conch_blessing_items.lua').read_text(encoding='utf-8')
        block = items[items.index('    TIGER = {'):]
        block = block[:block.index('\n    },\n')]
        self.assertNotIn('WorkingNow', block)
        self.assertIn('id = Isaac.GetItemIdByName("Tiger")', block)
        self.assertIn('stackable = true', block)
        self.assertIn('stackCap = 3', block)
        self.assertNotIn('stackShared', block, 'each holder rolls with their own copies')
        self.assertIn('COLLECTIBLE_PISCES', block)
        self.assertIn('flag = "positive"', block)
        module = (ROOT / 'scripts/items/collectibles/tiger.lua').read_text(encoding='utf-8')
        self.assertIn('chancePerCopy = 1 / 3', module)
        self.assertIn('damageMultiplier = 3', module)
        self.assertIn('fearFrames = 90', module)
        # User-designated Korean copy (2026-10-31), translated line for line; no
        # REPENTOGON line because the item uses only the base API.
        kr = (ROOT / 'scripts/locale/kr.lua').read_text(encoding='utf-8')
        self.assertIn('"적을 죽이면 1/3 확률로 창귀가 생성됩니다."', kr)
        self.assertIn('"#창귀는 내 데미지의 3배로 적에게 날아가 폭발합니다."', kr)
        self.assertIn('"#창귀에 맞은 적은 3초간 공포에 걸립니다."', kr)
        for lang in ('en', 'kr', 'urimal'):
            text = (ROOT / f'scripts/locale/{lang}.lua').read_text(encoding='utf-8')
            entry = text[text.index('        TIGER = {'):]
            entry = entry[:entry.index('\n        },\n')]
            self.assertEqual(len(re.findall(r'^\s+"', entry, re.M)), 3, lang)
            self.assertNotIn('REPENTOGON', entry, lang)
            self.assertNotIn('(WIP)', entry, lang)
        for api in ('MC_POST_ENTITY_TAKE_DMG', 'REPENTOGON', 'GetFearCountdown'):
            self.assertNotIn(api, module.split('M._test')[0].replace('needs\n-- no REPENTOGON', ''), api)


if __name__ == '__main__':
    unittest.main()
