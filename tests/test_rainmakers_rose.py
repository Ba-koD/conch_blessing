"""레인메이커의 장미 (Rose of the Rainmaker) through its shipped Lua: the user's
design (2026-11-27) is Depression's positive answer carrying over the rose of
the Rainmaker character mod: homing tears fall from the sky onto random spots
of the room at a third of the holder's tears, one per copy; a hit the holder
really takes brings down 25 at once; shot speed +0.2 once. Covers the rain's
pace and copies, each drop's fields, the downpour and what is not a hit, dead
holders, the shot speed and Live Eye leaving the rain unscored. These are Lua
regressions with doubles, not proof of engine behaviour (`cb test
rainmakers_rose`).
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
DamageFlag={DAMAGE_EXPLOSION=4,DAMAGE_RED_HEARTS=32,DAMAGE_SPIKES=128,DAMAGE_DEVIL=1024,DAMAGE_CURSED_DOOR=65536,
    DAMAGE_IV_BAG=262144,DAMAGE_FAKE=2097152,DAMAGE_NO_PENALTIES=268435456}
RoomType={ROOM_DEFAULT=1,ROOM_SACRIFICE=13}
ModCallbacks={}
CacheFlag={CACHE_DAMAGE=1,CACHE_SHOTSPEED=4}
TearFlags={TEAR_HOMING=4,TEAR_PIERCING=2}
WeaponType={WEAPON_TEARS=1,WEAPON_BRIMSTONE=2,WEAPON_LASER=3,WEAPON_KNIFE=4,WEAPON_BOMBS=5,WEAPON_ROCKETS=6,
    WEAPON_TECH_X=9,WEAPON_BONE=10,WEAPON_SPIRIT_SWORD=13,WEAPON_FETUS=14}
TearVariant={RAZOR=28,BONE=29,SWORD_BEAM=47,FETUS=50}
LaserVariant={THICK_RED=1,THIN_RED=2}
EffectVariant={BOMB_EXPLOSION=1}
EntityType={ENTITY_EFFECT=1000}
EntityPartition={ENEMY=8}
EntityFlag={FLAG_FRIENDLY=1}
DamageFlag_EXPLOSION=4
SoundEffect={SOUND_EXPLOSION_WEAK=42}
sounds={}
function SFXManager() return {Play=function(_,id,vol) sounds[#sounds+1]={id=id,vol=vol} end} end
function EntityPtr(e) return {Ref=e} end
function EntityRef(e) return {Entity=e} end
lasers={}
EntityLaser={ShootAngle=function(variant,from,angle,timeout,offset,source)
    local l={variant=variant,from=from,angle=angle,timeout=timeout,source=source,data={}}
    function l:SetMaxDistance(d) self.max=d end
    function l:GetData() return self.data end
    lasers[#lasers+1]=l
    return l
end}
spawned={}
enemies={}
ROSE=33
function Color(...) return {...} end
function Vector(x,y) return {X=x,Y=y} end
function GetPtrHash(e) return e.hash end
added={}
twisters={}
ConchBlessing={stats={shotSpeed={applyAddition=function(player,amount) added[#added+1]={player=player,amount=amount} end}},
    dragon={raiseTwister=function(player,pos,color) twisters[#twisters+1]={player=player,pos=pos,color=color}; return true end}}
DRAGON=44
Isaac={GetItemIdByName=function(name) return name=='Rose of the Rainmaker' and ROSE or name=='Dragon' and DRAGON or -1 end,
    Spawn=function(t,v,s,pos) local e={type=t,variant=v,pos=pos}; spawned[#spawned+1]=e; return e end,
    FindInRadius=function() return enemies end}
function enemy(x,y,friendly)
    local e={Position={X=x,Y=y},Size=10,friendly=friendly,hits={}}
    function e.Position:Distance(o) return math.sqrt((self.X-o.X)^2+(self.Y-o.Y)^2) end
    function e:IsVulnerableEnemy() return true end
    function e:HasEntityFlags() return self.friendly end
    function e:TakeDamage(amount,flags,source) self.hits[#self.hits+1]={amount=amount,flags=flags,source=source} end
    enemies[#enemies+1]=e
    return e
end
spot=0
room={}
function room:GetRandomPosition(margin) spot=spot+1; return {X=spot,Y=margin} end
function room:GetType() return RoomType.ROOM_DEFAULT end
function room:GetTopLeftPos() return {X=60,Y=140} end
players={}
function Game() return {GetRoom=function() return room end,GetNumPlayers=function() return #players end,
    GetPlayer=function(_,i) return players[i+1] end,GetFrameCount=function() return 0 end} end
fired={}
local nextHash=0
function player(copies, maxFireDelay)
    nextHash=nextHash+1
    local p={copies=copies or 1,MaxFireDelay=maxFireDelay or 10,dead=false,ghost=false,hash=nextHash}
    function p:GetCollectibleNum(id) return id==ROSE and self.copies or id==DRAGON and (self.dragons or 0) or 0 end
    function p:IsDead() return self.dead end
    function p:IsCoopGhost() return self.ghost end
    function p:ToPlayer() return self end
    function p:Exists() return true end
    function p:HasWeaponType(w) return self.weapons ~= nil and self.weapons[w] == true end
    function p:FireTechXLaser(pos,vel,radius,source,mult)
        local l={ring=true,pos=pos,radius=radius,source=source,data={}}
        function l:GetData() return self.data end
        lasers[#lasers+1]=l
        return l
    end
    function p:FireTear(pos,vel,canBeEye,noTractor,streak)
        local t={owner=self,Position=pos,Velocity=vel,args={canBeEye,noTractor,streak},flags=0,data={},
            CollisionDamage=3.5,Visible=true,gone=false}
        function t:AddTearFlags(f) self.flags=self.flags|f end
        function t:ChangeVariant(v) self.Variant=v end
        function t:Exists() return not self.gone end
        function t:IsDead() return false end
        function t:SetColor(c,duration,priority) self.color=c; self.colorArgs={duration,priority} end
        function t:GetData() return self.data end
        fired[#fired+1]=t
        return t
    end
    players[#players+1]=p
    return p
end
Hits=ConchBlessingRequire('scripts.lib.player_hits')
M=ConchBlessingRequire('scripts.items.collectibles.rainmakers_rose')
T=M._test
function run(n) for _=1,n do M.onUpdate() end end
function count(p)
    local c=0
    for _,t in ipairs(fired) do if t.owner==p then c=c+1 end end
    return c
end
function hit(p,flags) return Hits.handlers.RAINMAKERS_ROSE(nil,p,1,flags or 0,nil,30) end
'''


class RainmakersRoseTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().loadsource = source
        self.lua.execute(SETUP)

    def run_lua(self, code):
        return self.lua.execute(code)

    def test_a_drop_comes_every_three_shots_of_fire_delay(self):
        # Isaac's MaxFireDelay 10 is 30 / 11 shots a second: a drop every 33 updates.
        self.assertEqual(self.run_lua('return T.interval(10)'), 33)
        self.assertEqual(self.run_lua('return T.interval(5)'), 18)
        # A fire rate past one shot an update rains more than once an update.
        self.assertAlmostEqual(self.run_lua('return T.interval(-0.75)'), 0.75)

    def test_isaac_with_one_rose_gets_a_third_of_his_tears_as_rain(self):
        self.assertEqual(self.run_lua('local p=player(1,10); run(330); return count(p)'), 10)
        self.assertEqual(self.run_lua('local p=player(1,10); run(32); return count(p)'), 0)
        self.assertEqual(self.run_lua('local p=player(1,10); run(33); return count(p)'), 1)

    def test_every_copy_adds_one_drop_to_each_fall(self):
        self.assertEqual(self.run_lua('local p=player(2,10); run(330); return count(p)'), 20)
        self.assertEqual(self.run_lua('local p=player(3,10); run(33); return count(p)'), 3)

    def test_a_fast_fire_rate_brings_more_than_one_drop_an_update(self):
        # tears 120 a second: MaxFireDelay -0.75, a drop every 0.75 updates.
        self.assertEqual(self.run_lua('local p=player(1,-0.75); run(30); return count(p)'), 40)

    def test_each_drop_is_a_homing_tear_of_the_holder_falling_onto_a_random_spot(self):
        result = self.run_lua('''
            local p=player(1,10); run(33)
            local t=fired[1]
            return t.Position.X, t.Position.Y, t.Velocity.X, t.Velocity.Y,
                tostring(t.args[1])..tostring(t.args[2])..tostring(t.args[3]),
                t.Height, t.FallingSpeed, t.FallingAcceleration, t.flags & TearFlags.TEAR_HOMING,
                table.concat(t.color, ','), t.data[M.MARK], t.data[M.UNAIMED]
        ''')
        self.assertEqual(result, (1, 16, 0, 0, 'falsetruefalse', -500, 20, 2, 4, '0.8,0.8,1,0.5,0,0,0', True, True))

    def test_the_storm_of_jin_doubles_the_rain(self):
        # 진 held by anyone living: every fall brings twice the drops.
        self.assertEqual(self.run_lua('players={}; local p=player(1,10); p.dragons=1; run(330); return count(p)'), 20)
        self.assertEqual(self.run_lua(
            'players={}; local p=player(2,10); local q=player(0,10); q.dragons=1; run(33); return count(p)'), 4)
        # A dead 진 holder brings no storm, and the downpour stays 25.
        self.assertEqual(self.run_lua(
            'players={}; local p=player(1,10); local q=player(0,10); q.dragons=1; q.dead=true; run(33); return count(p)'), 1)
        self.assertEqual(self.run_lua('players={}; local p=player(1,10); p.dragons=1; hit(p); return count(p)'), 25)

    def test_brimstone_rain_raises_a_red_twister_where_its_carrier_lands(self):
        out = self.run_lua('''
            players={}; local p=player(1,10); p.weapons={[WeaponType.WEAPON_BRIMSTONE]=true}
            run(33)
            local t=fired[#fired]
            local carrier=tostring(t.Visible)..":"..t.CollisionDamage..":"..tostring(t.TearFlags)..":"..#T.carriers()
            t.Position={X=100,Y=200}; run(1)
            t.gone=true; run(1)
            local w=twisters[#twisters]
            return carrier.."|"..tostring(w.player==p)..":"..w.pos.X..","..w.pos.Y..":"..table.concat(w.color,",")
                ..":"..#lasers..":"..#T.carriers()..":"..T.evidence.brimstone
        ''')
        self.assertEqual(out, 'false:0:4:1|true:100,200:1,0.25,0.25,1,0.4,0,0:0:0:1')

    def test_technology_strikes_a_thin_beam_and_tech_x_leaves_a_ring(self):
        out = self.run_lua('''
            players={}; local p=player(1,10); p.weapons={[WeaponType.WEAPON_LASER]=true}
            run(33); fired[#fired].Position={X=100,Y=400}; run(1); fired[#fired].gone=true; run(1)
            local l=lasers[#lasers]
            local q=player(1,10); p.copies=0; q.weapons={[WeaponType.WEAPON_TECH_X]=true}
            run(33); fired[#fired].gone=true; run(1)
            local r=lasers[#lasers]
            return l.variant..":"..l.timeout..":"..l.from.Y..":"..l.max.."|"..tostring(r.ring)..":"..r.radius..":"
                ..r.Timeout..":"..r.CollisionDamage
        ''')
        # The Technology beam starts 80 above the room's top wall (y 140) and
        # reaches all the way down to where its drop landed (y 400).
        self.assertEqual(out, '2:2:60:340|true:24:12:3.5')

    def test_fetus_blasts_hurt_enemies_in_reach_and_nobody_else(self):
        out = self.run_lua('''
            players={}; enemies={}
            local p=player(1,10); p.weapons={[WeaponType.WEAPON_BOMBS]=true}
            local near, far, friend = enemy(100,200), enemy(100,300), enemy(100,205,true)
            run(33); local t=fired[#fired]; t.Position={X=100,Y=210}; run(1); t.gone=true; run(1)
            return #near.hits..":"..near.hits[1].amount..":"..near.hits[1].flags..":"..tostring(near.hits[1].source.Entity==p)
                ..":"..#far.hits..":"..#friend.hits..":"..spawned[#spawned].variant..":"..#sounds..":"..T.evidence.bomb
        ''')
        self.assertEqual(out, '1:3.5:4:true:0:0:1:1:1')

    def test_epic_fetus_wins_over_brimstone_and_blasts_wider(self):
        out = self.run_lua('''
            players={}; enemies={}
            local p=player(1,10)
            p.weapons={[WeaponType.WEAPON_ROCKETS]=true,[WeaponType.WEAPON_BRIMSTONE]=true}
            local e=enemy(100,260)
            run(33); local t=fired[#fired]; t.Position={X=100,Y=200}; run(1); t.gone=true; run(1)
            return T.formOf(p).strike..":"..#e.hits..":"..#lasers..":"..T.evidence.rocket
        ''')
        self.assertEqual(out, 'rocket:1:0:1')

    def test_blades_sword_beams_bones_and_fetuses_fall_as_tears(self):
        out = self.run_lua('''
            players={}
            local out={}
            for _,w in ipairs({"WEAPON_KNIFE","WEAPON_SPIRIT_SWORD","WEAPON_BONE","WEAPON_FETUS"}) do
                players={}; local p=player(1,10); p.weapons={[WeaponType[w]]=true}
                run(33); local t=fired[#fired]
                out[#out+1]=t.Variant..":"..(t.flags & TearFlags.TEAR_PIERCING)..":"..t.CollisionDamage..":"..tostring(t.Visible)
            end
            return table.concat(out," ")..":"..#T.carriers()
        ''')
        self.assertEqual(out, '28:2:3.5:true 47:0:3.5:true 29:0:3.5:true 50:0:3.5:true:0')

    def test_a_new_room_drops_the_carriers_of_the_room_left(self):
        out = self.run_lua('''
            players={}; local p=player(1,10); p.weapons={[WeaponType.WEAPON_BRIMSTONE]=true}
            run(33); local before=#T.carriers()
            M.reset(); fired[#fired].gone=true; run(1)
            return before..":"..#T.carriers()..":"..#lasers
        ''')
        self.assertEqual(out, '1:0:0')

    def test_the_downpour_takes_the_weapon_form_too(self):
        self.assertEqual(self.run_lua(
            'players={}; local p=player(1,10); p.weapons={[WeaponType.WEAPON_BRIMSTONE]=true}; hit(p);'
            ' return #T.carriers()'), 25)

    def test_no_rose_no_rain(self):
        self.assertEqual(self.run_lua('local p=player(0,10); run(330); return count(p)'), 0)

    def test_dead_players_and_coop_ghosts_bring_no_rain(self):
        self.assertEqual(self.run_lua('local p=player(1,10); p.dead=true; run(330); return count(p)'), 0)
        self.assertEqual(self.run_lua('local p=player(1,10); p.ghost=true; run(330); return count(p)'), 0)

    def test_a_new_room_starts_the_rain_from_nothing(self):
        self.assertEqual(self.run_lua('local p=player(1,10); run(32); M.reset(); run(32); return count(p)'), 0)

    def test_a_hit_brings_down_25_drops_whatever_the_copies(self):
        self.assertEqual(self.run_lua('local p=player(1,10); local r=hit(p); return tostring(r)..":"..count(p)'),
                         'true:25')
        self.assertEqual(self.run_lua('local p=player(3,10); hit(p); return count(p)'), 25)
        self.assertEqual(self.run_lua('T.resetEvidence(); local p=player(1,10); hit(p); return T.evidence.downpour'), 25)

    def test_self_damage_and_sacrifice_spikes_bring_no_downpour(self):
        for flag in ('DAMAGE_RED_HEARTS', 'DAMAGE_IV_BAG', 'DAMAGE_NO_PENALTIES', 'DAMAGE_DEVIL', 'DAMAGE_FAKE'):
            self.assertEqual(self.run_lua(
                'local p=player(1,10); local r=hit(p,DamageFlag.%s); return tostring(r)..":"..count(p)' % flag),
                'nil:0', flag)

    def test_without_the_rose_or_alive_a_hit_brings_nothing(self):
        self.assertEqual(self.run_lua('local p=player(0,10); local r=hit(p); return tostring(r)..":"..count(p)'),
                         'nil:0')
        self.assertEqual(self.run_lua('local p=player(1,10); p.dead=true; hit(p); return count(p)'), 0)

    def test_shot_speed_rises_by_0_2_once(self):
        out = self.run_lua('''
            local one, three, none = player(1), player(3), player(0)
            for _,p in ipairs({one,three,none}) do
                M.onEvaluateCache(nil,p,CacheFlag.CACHE_SHOTSPEED)
                M.onEvaluateCache(nil,p,CacheFlag.CACHE_DAMAGE)
            end
            local out={}
            for _,a in ipairs(added) do out[#out+1]=string.format('%d:%.1f',a.player.copies,a.amount) end
            return table.concat(out,' ')
        ''')
        self.assertEqual(out, '1:0.2 3:0.2')

    def test_live_eye_leaves_unaimed_tears_unscored(self):
        text = (ROOT / 'scripts/items/collectibles/live_eye.lua').read_text(encoding='utf-8')
        collision = text[text.index('onTearCollision = function'):text.index('onTearRemoved = function')]
        removed = text[text.index('onTearRemoved = function'):]
        self.assertIn('__ConchBlessingUnaimed', collision)
        self.assertIn('not data.__ConchBlessingUnaimed', removed[:removed.index('handleMiss(player)')])
        self.assertEqual(self.run_lua('return M.UNAIMED'), '__ConchBlessingUnaimed')


if __name__ == '__main__':
    unittest.main()
