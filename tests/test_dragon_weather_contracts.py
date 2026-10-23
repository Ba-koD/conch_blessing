"""진 (Dragon) weather's shipped Lua with engine doubles; real HP, sound and art remain in-game.

Expected values come from the item's design: rain and a dimmed room while held;
while enemies are present tears stat / 5 x copies held bolts a second, on their
own (tears 5 with one copy: once a second), each landing close to a random enemy
and hitting enemies within about 1.5 tiles for 1x damage; a quiet small thunder per bolt with a
full thunderclap at most every five seconds and a quiet distant rumble; with two
or more copies a bolt has a 5% chance to rise as a twister instead (at most 5 at
once) that stays 5 seconds, pulls enemies in and hits what it touches for 5% of
the holder's damage every tick.
"""
from pathlib import Path
import re
import unittest

from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class DragonWeatherContracts(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().repo = ROOT.as_posix()
        self.lua.execute(r'''
            package.path=repo..'/?.lua;'..package.path
            local V={}
            V.__index=V
            function Vector(x,y) return setmetatable({X=x,Y=y},V) end
            V.__add=function(a,b) return Vector(a.X+b.X,a.Y+b.Y) end
            V.__sub=function(a,b) return Vector(a.X-b.X,a.Y-b.Y) end
            V.__mul=function(a,b) if type(a)=='number' then a,b=b,a end return Vector(a.X*b,a.Y*b) end
            function V:Length() return math.sqrt(self.X*self.X+self.Y*self.Y) end
            function V:Resized(l) local n=self:Length(); return n>0 and Vector(self.X/n*l,self.Y/n*l) or Vector(0,0) end
            function V:Distance(o) return (self-o):Length() end
            function V:DistanceSquared(o) local d=self-o; return d.X*d.X+d.Y*d.Y end
            DamageProvenanceCalls={}
            package.loaded['scripts.lib.damage_provenance']={withTriggeredSource=function(entity,key,_,origin,fn)
                DamageProvenanceCalls[#DamageProvenanceCalls+1]=key; return fn() end}
            package=nil
            frame=0; renderFrame=0; players={}; entities={}; sounds={}; darken={}; logs={}; errors={}; scans=0
            EntityFlag={FLAG_FRIENDLY=1}
            SoundEffect={SOUND_HUSH_CHARGE=425,SOUND_THUNDER=472}
            ModCallbacks={}
            function Color(r,g,b,a) return {R=r,G=g,B=b,A=a} end
            function EntityRef(e) return {Entity=e} end
            function EntityPtr(e) return setmetatable({},{__index=function(_,k) if k=='Ref' and e.alive~=false then return e end end}) end
            function GetPtrHash(e) return tostring(e) end
            room={GetTopLeftPos=function() return Vector(60,140) end,GetBottomRightPos=function() return Vector(580,420) end,
                GetCenterPos=function() return Vector(320,280) end,
                IsPositionInRoom=function(_,pos) return not inVoid or not inVoid(pos) end}
            game={GetFrameCount=function() return frame end,GetNumPlayers=function() return #players end,
                GetRoom=function() return room end,Darken=function(_,v,t) darken[#darken+1]={v=v,t=t} end}
            function Game() return game end
            playing={}; stopped={}
            local sfx={}
            function sfx:Play(id,v,delay,loop,pitch) sounds[#sounds+1]={id=id,volume=v,pitch=pitch,loop=loop}; if loop then playing[id]=true end end
            function sfx:IsPlaying(id) return playing[id]==true end
            function sfx:Stop(id) playing[id]=nil; stopped[#stopped+1]=id end
            function SFXManager() return sfx end
            RAIN=904
            -- Only the one-shot cues, without the rain loop.
            function cues() local list={} for _,s in ipairs(sounds) do if s.id~=RAIN then list[#list+1]=s end end return list end
            spriteLog={}
            Sprite=setmetatable({},{__call=function()
                local s={}
                function s:Load(path) if failArt then error('missing '..path) end self.path=path end
                function s:IsLoaded() return true end
                function s:SetFrame(name,f) self.anim=name; self.frame=f end
                function s:Render(pos) spriteLog[#spriteLog+1]={path=self.path,anim=self.anim,frame=self.frame,pos=pos,scale=self.Scale,color=self.Color,rot=self.Rotation} end
                return s
            end})
            Isaac={GetItemIdByName=function() return 600 end,
                GetFrameCount=function() return renderFrame end,
                GetPlayer=function(i) return players[i+1] end,
                GetRoomEntities=function() scans=scans+1; return entities end,
                WorldToScreen=function(p) return Vector(p.X,p.Y) end,
                GetScreenWidth=function() return 480 end,GetScreenHeight=function() return 270 end,
                GetSoundIdByName=function(name) return ({['Conch Dragon Thunder']=901,['Conch Dragon Bolt']=902,['Conch Dragon Rain']=904})[name] or -1 end}
            ConchBlessing={Config={debugMode=false},printDebug=function(t) logs[#logs+1]=t end,printError=function(t) errors[#errors+1]=t end}
            -- A seeded stand-in for the collectible RNG: a fixed list of floats, then a plain LCG.
            function makeRng(list)
                local r={i=0,seed=7}
                function r:RandomFloat()
                    self.i=self.i+1
                    if list and list[self.i] then return list[self.i] end
                    self.seed=(self.seed*1103515245+12345)%2147483648; return self.seed/2147483648
                end
                function r:RandomInt(n) return math.floor(self:RandomFloat()*n) end
                return r
            end
            function makePlayer(opts)
                opts=opts or {}
                -- Luck 10 by default: every strike catches its enemy unless a test sets it.
                local p={Position=Vector(320,280),Damage=opts.damage or 10,MaxFireDelay=opts.delay or 10,items=opts.items or 1,
                    Luck=opts.luck or 10,
                    TearFlags=opts.flags or 0,alive=true,rng=makeRng(opts.rolls)}
                function p:GetCollectibleNum() return self.items end
                function p:GetCollectibleRNG() return self.rng end
                function p:ToPlayer() return self end
                function p:Exists() return self.alive end
                function p:GetData() self.data=self.data or {}; return self.data end
                players[#players+1]=p
                return p
            end
            function enemy(x,y,opts)
                opts=opts or {}
                local e={Position=Vector(x,y),Velocity=Vector(0,0),Size=opts.size or 10,hits={},alive=true,boss=opts.boss}
                function e:ToNPC() return self end
                function e:Exists() return self.alive end
                function e:IsVulnerableEnemy() return true end
                function e:IsActiveEnemy() return true end
                function e:IsDead() return false end
                function e:HasEntityFlags() return false end
                function e:IsBoss() return self.boss==true end
                function e:TakeDamage(amount,flags,source) self.hits[#self.hits+1]={amount=amount,source=source.Entity,frame=frame} end
                entities[#entities+1]=e
                return e
            end
            function tick() frame=frame+1; renderFrame=renderFrame+2; D.onUpdate() end
            require('scripts.items.collectibles.dragon'); D=ConchBlessing.dragon; T=D._test
            function near(a,b,eps) assert(math.abs(a-b)<=(eps or 1e-9), tostring(a)..' ~= '..tostring(b)) end
        ''')

    def run_lua(self, code):
        self.lua.execute(code)

    def test_bolts_follow_the_tears_stat_and_copies_add_linearly(self):
        self.run_lua('''
            near(T.shotsPerSecond(10),30/11); near(T.shotsPerSecond(-5),30)
            near(T.boltsPerUpdate(4,1),(30/5)/5/30, 1e-12)          -- tears 6: 1.2 a second
            near(T.boltsPerUpdate(5,1),1/30, 1e-12)                 -- tears 5: once a second
            near(T.boltsPerUpdate(10,3),3*T.boltsPerUpdate(10,1), 1e-12)
            near(T.boltsPerUpdate(10,0),0)
            ConchBlessing.Config.debugMode=true
            local function strikesOver(items,delay,updates)
                players={}; entities={}; logs={}; D.onNewRoom()
                makePlayer({items=items,delay=delay}); enemy(320,280)
                for i=1,updates do tick() end
                local n=0
                -- A strike is a bolt or, with two copies, sometimes a twister.
                for _,l in ipairs(logs) do if l:find('[Dragon] bolt',1,true) or l:find('[Dragon] twister rises',1,true) then n=n+1 end end
                return n
            end
            assert(strikesOver(1,5,300)==10, 'tears 5, one copy: once a second')
            assert(strikesOver(2,5,300)==20, 'two copies, twice a second')
            assert(strikesOver(1,10,330)==6, 'tears 2.73: one every 1.83 s')
            assert(strikesOver(1,2,300)==20, 'tears 10: twice a second')
        ''')

    def test_no_bolts_without_enemies_and_none_banked(self):
        self.run_lua('''
            ConchBlessing.Config.debugMode=true
            local p=makePlayer({delay=0})
            for i=1,300 do tick() end
            for _,l in ipairs(logs) do assert(not l:find('bolt',1,true), 'no bolts in a cleared room') end
            assert(D._charge[GetPtrHash(p)]==0, 'nothing is banked for the next fight')
            enemy(320,280); tick()
            local n=0 for _,l in ipairs(logs) do if l:find('[Dragon] bolt',1,true) then n=n+1 end end
            assert(n<=1, 'the first update of a fight does not release a backlog: '..n)
        ''')

    def test_bolt_hits_enemies_within_reach_for_full_damage(self):
        self.run_lua('''
            -- Rolls: the first enemy, angle 0, distance 0, a hit, then a bolt.
            -- Tears 30: a bolt every five updates.
            local p=makePlayer({damage=7,delay=0,rolls={0,0,0,0,0.9, 0,0,0,0,0.9, 0,0,0,0,0.9}})
            local anchor=enemy(320,280)
            local inside=enemy(320+65,280,{size=10}); local edge=enemy(320,280+70,{size=10}); local out=enemy(320+75,280,{size=10})
            for i=1,15 do tick() end
            assert(#anchor.hits>=1 and #inside.hits>=1 and #edge.hits>=1 and #out.hits==0, 'reach is 60 plus the enemy size')
            near(anchor.hits[1].amount,7); assert(anchor.hits[1].source==p, 'the holder is the damage source')
            assert(DamageProvenanceCalls[1]=='dragon_bolt', 'bolts carry their own proc key')
            assert(#D._bolts>=1 and #D._scorches>=1, 'the bolt is drawn and leaves a burn')
        ''')

    def test_rare_bolts_play_louder_and_a_busy_storm_stays_at_the_usual_level(self):
        self.run_lua('''
            local full=D.data.boltVolume*10^(D.data.boltRareBoostDb/20)
            near(T.boltVolumeForGap(D.data.boltRareGap),full,1e-9); near(T.boltVolumeForGap(1000),full,1e-9)
            near(T.boltVolumeForGap(D.data.boltBusyGap),D.data.boltVolume,1e-9); near(T.boltVolumeForGap(1),D.data.boltVolume,1e-9)
            local mid=math.sqrt(D.data.boltRareGap*D.data.boltBusyGap)
            near(T.boltVolumeForGap(mid),D.data.boltVolume*10^(D.data.boltRareBoostDb/40),1e-9)
            assert(T.boltVolumeForGap(30)>T.boltVolumeForGap(20), 'rarer is louder')
            -- Base stats (tears 2.73): a strike about every 55 updates, most of the boost.
            local p=makePlayer({delay=10,rolls={}}); enemy(320,280)
            for i=1,400 do tick() end
            local last
            for _,s in ipairs(sounds) do if s.id==902 then last=s.volume end end
            assert(last and last>D.data.boltVolume*10^(4/20) and last<=full+1e-9, 'a rare bolt is boosted: '..tostring(last))
        ''')

    def test_a_busy_storm_plays_bolts_at_the_usual_level(self):
        self.run_lua('''
            -- Tears 30 with two copies: twelve strikes a second.
            local p=makePlayer({delay=0,items=2}); enemy(320,280)
            for i=1,120 do tick() end
            local last
            for _,s in ipairs(sounds) do if s.id==902 then last=s.volume end end
            near(last,D.data.boltVolume,1e-6)
        ''')

    def test_luck_sets_how_often_a_strike_catches_its_enemy(self):
        self.run_lua('''
            -- 50% at luck 0, 5 points more per luck, between 10% and 100% (always from luck 10).
            near(T.boltHitChance(0),0.5); near(T.boltHitChance(1),0.55); near(T.boltHitChance(5),0.75)
            near(T.boltHitChance(9),0.95); near(T.boltHitChance(10),1); near(T.boltHitChance(25),1)
            near(T.boltHitChance(-5),0.25); near(T.boltHitChance(-8),0.1); near(T.boltHitChance(-30),0.1)
            near(T.boltHitChance(nil),0.5)
            -- A miss lands past the bolt's reach from its enemy, never on it.
            for i=0,20 do
                for _,r in ipairs({0,0.5,1}) do
                    local d=T.missSpot(Vector(300,300),i/20,r,13):Distance(Vector(300,300))
                    assert(d>D.data.boltRadius+13 and d<=D.data.boltRadius+13+4+D.data.boltMissReach+1e-6, 'miss at '..d)
                end
            end
        ''')

    def test_at_luck_zero_a_high_hit_roll_misses_and_a_low_one_hits(self):
        self.run_lua('''
            -- Rolls: the enemy, angle 0, distance 0, the hit roll, a bolt; a strike every five updates.
            local p=makePlayer({delay=0,luck=0,rolls={0,0,0,0.6,0.9, 0,0,0,0.3,0.9}})
            local target=enemy(320,280,{size=13}); local beside=enemy(320+60+13+4,280,{size=10})
            for i=1,5 do tick() end
            assert(#target.hits==0, 'a 0.6 roll at luck 0 (50%) misses its enemy')
            assert(#beside.hits==1, 'but catches the enemy standing where it lands')
            for i=1,5 do tick() end
            assert(#target.hits==1, 'a 0.3 roll hits')
        ''')

    def test_a_miss_turns_away_from_a_wall(self):
        self.run_lua('''
            local p=makePlayer({delay=0,luck=0,rolls={0,0,0,0.6,0.9}})
            local target=enemy(320,280,{size=13})
            -- Everything to the right is outside the room: the miss swings to the left.
            inVoid=function(pos) return pos.X>330 end
            ConchBlessing.Config.debugMode=true
            for i=1,5 do tick() end
            local x
            for _,l in ipairs(logs) do x=x or tonumber(l:match('%[Dragon%] bolt at (%-?%d+),')) end
            assert(x and x<320-60-13 and #target.hits==0, 'landed at '..tostring(x))
        ''')

    def test_bolts_land_close_to_a_random_enemy(self):
        self.run_lua('''
            for i=0,20 do
                local s=T.scatter(Vector(100,100),i/20,1)
                near(s:Distance(Vector(100,100)),D.data.boltScatter,1e-9)
            end
            assert(T.scatter(Vector(5,5),0.3,0).X==5, 'a zero roll lands on the enemy')
            assert(D.data.boltScatter<D.data.boltRadius, 'so the chosen enemy is always caught')
            ConchBlessing.Config.debugMode=true
            local p=makePlayer({delay=0}); local a=enemy(100,200); local b=enemy(500,380)
            for i=1,120 do tick() end
            local bolts=0
            for _,l in ipairs(logs) do
                local x,y=l:match('%[Dragon%] bolt at (%-?%d+),(%-?%d+)')
                if x then
                    bolts=bolts+1
                    local spot=Vector(tonumber(x),tonumber(y))
                    assert(spot:Distance(a.Position)<=D.data.boltScatter+1 or spot:Distance(b.Position)<=D.data.boltScatter+1, l)
                    assert(l:find('hit=1',1,true), 'every bolt catches its enemy: '..l)
                end
            end
            assert(bolts>20 and #a.hits>0 and #b.hits>0, 'both enemies are struck over time')
            -- Near a wall the spot falls back onto the enemy itself.
            inVoid=function() return true end
            logs={}
            for i=1,30 do tick() end
            local s=0
            for _,l in ipairs(logs) do if l:find('[Dragon] bolt at 100,200',1,true) or l:find('[Dragon] bolt at 500,380',1,true) then s=s+1 end end
            assert(s>0, 'out-of-room spots land on the enemy')
            inVoid=nil
        ''')

    def test_quiet_bolts_with_a_thunderclap_and_flash_at_most_every_five_seconds(self):
        self.run_lua('''
            ConchBlessing.Config.debugMode=true
            local p=makePlayer({delay=0}); enemy(320,280)
            local flashes=0
            for i=1,300 do tick(); if D._sky.flash==D.data.flashTicks then flashes=flashes+1 end end
            local bolts,claps,cracks,lastClap=0,0,0,nil
            for _,l in ipairs(logs) do if l:find('[Dragon] bolt',1,true) then bolts=bolts+1 end end
            for _,s in ipairs(sounds) do
                if s.id==901 then claps=claps+1; near(s.volume,D.data.thunderVolume) end
                if s.id==902 then cracks=cracks+1; assert(s.volume>=D.data.boltVolume-1e-9 and s.volume<=T.boltVolumeForGap(1e9)+1e-9); assert(s.pitch>=0.9 and s.pitch<=1.1) end
            end
            assert(bolts>50 and claps+cracks==bolts, 'every bolt makes a sound: bolts='..bolts..' claps='..claps..' cracks='..cracks)
            assert(claps==2, 'ten seconds hold two thunderclaps at most: '..claps)
            assert(flashes==claps, 'each thunderclap lights the room')
            near(T.veilAlpha(0),D.data.overcast); assert(T.veilAlpha(D.data.flashTicks)<D.data.overcast*0.3)
        ''')

    def test_twister_needs_two_copies_and_a_free_slot(self):
        self.run_lua('''
            assert(D.data.twisterChance==0.05 and D.data.twisterLimit==5 and D.data.twisterMinCopies==2)
            assert(T.rollStrikeKind(0.0,1,0)=='bolt', 'one copy never raises a twister')
            assert(T.rollStrikeKind(0.049,2,0)=='twister' and T.rollStrikeKind(0.05,2,0)=='bolt')
            assert(T.rollStrikeKind(0.0,3,4)=='twister' and T.rollStrikeKind(0.0,3,5)=='bolt', 'at most five at once')
        ''')

    def test_twister_stays_pulls_and_hurts_five_percent_a_tick(self):
        self.run_lua('''
            -- Rolls: the first enemy (at the centre), angle and distance 0, then 0 for the kind: a twister.
            local p=makePlayer({items=2,damage=10,delay=10,rolls={0,0,0,0,0}})
            local anchor=enemy(320,280,{size=10}); local near1=enemy(320+20,280,{size=10})
            local pulled=enemy(320+100,280,{size=10}); local boss=enemy(320-100,280,{size=10,boss=true})
            local far=enemy(320,280+200,{size=10})
            for i=1,40 do tick(); if #D._twisters>0 then break end end
            assert(#D._twisters==1, 'a twister rose')
            local tw=D._twisters[1]; assert(tw.position.X==320 and tw.position.Y==280)
            pulled.Velocity=Vector(0,0); boss.Velocity=Vector(0,0); far.Velocity=Vector(0,0)
            local before=#near1.hits
            D._charge={}; p.items=2; p.MaxFireDelay=1e9   -- no further strikes during the measurement
            tick()
            assert(pulled.Velocity.X<0 and boss.Velocity.X>0, 'pulled toward the middle')
            assert(math.abs(boss.Velocity.X)<math.abs(pulled.Velocity.X), 'a boss feels less of the pull')
            assert(far.Velocity.X==0 and far.Velocity.Y==0, 'nothing past the pull radius')
            near(near1.hits[#near1.hits].amount,0.5); assert(#near1.hits==before+1, 'one hit per tick')
            assert(DamageProvenanceCalls[#DamageProvenanceCalls]=='dragon_twister')
            -- It stays for five seconds, then fades harmlessly and is gone.
            local hitsAt=#near1.hits
            for i=1,200 do tick() end
            assert(#D._twisters==0, 'gone after its life')
            local touching=#near1.hits-hitsAt
            assert(touching<=D.data.twisterTicks, 'hurts only while standing: '..touching)
            local name,f=T.twisterFrame({age=0}); assert(name=='Start' and f==0)
            name,f=T.twisterFrame({age=40}); assert(name=='Loop')
            name,f=T.twisterFrame({age=152}); assert(name=='End' and f==2)
        ''')

    def test_twister_fades_when_its_owner_is_gone(self):
        self.run_lua('''
            local p=makePlayer({items=2,rolls={0,0,0,0,0}}); local e=enemy(330,280)
            for i=1,40 do tick(); if #D._twisters>0 then break end end
            assert(#D._twisters==1)
            p.alive=false; p.MaxFireDelay=1e9
            local hits=#e.hits; tick()
            assert(#e.hits==hits, 'no owner, no damage')
        ''')

    def test_dark_veil_and_rain_are_drawn_under_the_hud_while_held(self):
        self.run_lua('''
            local p=makePlayer()
            local function drawn(path) local n=0 for _,e in ipairs(spriteLog) do if e.path==path then n=n+1 end end return n end
            -- With REPENTOGON's room hook: a dark veil over the room, then the rain on top.
            ModCallbacks.MC_POST_ROOM_RENDER_ENTITIES=1044
            tick(); assert(#darken==0, 'the veil replaces the engine darkening')
            spriteLog={}; D.onRoomRender()
            local veil=spriteLog[1]
            assert(veil.path=='gfx/effects/conch_upgrade_pixel.anm2' and veil.scale.X==480 and veil.scale.Y==270, 'covers the screen')
            near(veil.color.A,D.data.overcast); assert(veil.color.A<0.5, 'dim, not pitch dark')
            assert(drawn('gfx/effects/conch_upgrade_pixel.anm2')+drawn('gfx/1000.133_water ripple.anm2')==1+D.data.rainDrops)
            spriteLog={}; D.onRender(); assert(#spriteLog==0, 'with the room hook the plain render pass draws nothing')
            p.items=0; spriteLog={}; D.onRoomRender(); assert(#spriteLog==0, 'no veil or rain once it is gone')
            -- Without the hook: the engine darkens the room and the rain draws in the plain pass, no veil over the HUD.
            ModCallbacks.MC_POST_ROOM_RENDER_ENTITIES=nil
            p.items=1; tick(); assert(#darken==1 and darken[1].v==D.data.overcast)
            p.items=0; tick(); assert(#darken==1, 'clouds lift when nobody holds it')
            p.items=1; spriteLog={}; D.onRender()
            assert(drawn('gfx/effects/conch_upgrade_pixel.anm2')+drawn('gfx/1000.133_water ripple.anm2')==D.data.rainDrops)
        ''')

    def test_rain_falls_along_its_own_slant_onto_its_ripple(self):
        self.run_lua('''
            ModCallbacks.MC_POST_ROOM_RENDER_ENTITIES=1044
            local p=makePlayer(); tick()
            local slant=math.rad(D.data.rainSlant)
            for drop=1,3 do
                local tops,spot={},nil
                for f=1,240 do
                    renderFrame=renderFrame+1
                    spriteLog={}; D.onRoomRender()
                    local e=spriteLog[1+drop]          -- after the veil, the drops in order
                    if e.path=='gfx/effects/conch_upgrade_pixel.anm2' then tops[#tops+1]=e
                    elseif not spot then spot=e.pos end
                end
                assert(spot and #tops>10, 'drop '..drop..' fell and landed')
                for _,t in ipairs(tops) do
                    near(t.rot,D.data.rainSlant)
                    -- The streak's lower end lies on the slanted line down to its ripple, above it.
                    local headX,headY=t.pos.X-math.sin(slant)*8,t.pos.Y+math.cos(slant)*8
                    near((headX-spot.X)*math.cos(slant)+(headY-spot.Y)*math.sin(slant),0,1e-6)
                    assert(headY<=spot.Y+1e-6 and headX>=spot.X-1e-6, 'falls from the upper right')
                end
            end
        ''')

    def test_scorch_marks_fade_and_bolts_play_every_frame(self):
        self.run_lua('''
            ModCallbacks.MC_POST_ROOM_RENDER_ENTITIES=1044
            local p=makePlayer({delay=0}); enemy(320,280)
            for i=1,5 do tick() end
            assert(#D._bolts==1 and #D._scorches==1)
            spriteLog={}; D.onRoomRender()
            local order={}
            for _,e in ipairs(spriteLog) do if e.anim=='Scorch' or (e.anim or ''):find('^Strike') then order[#order+1]=e.anim end end
            assert(order[1]=='Scorch' and order[#order]:find('^Strike'), 'burns lie under the bolt')
            assert(T.strikeLength()==14 and T.strikeFrame(0)==0 and T.strikeFrame(1)==1 and T.strikeFrame(13)==6 and T.strikeFrame(14)==nil)
            p.items=0
            for i=1,D.data.scorchTicks do tick() end
            assert(#D._scorches==0 and #D._bolts==0, 'burns fade out')
        ''')

    def test_bolts_come_in_four_shapes_either_way_round_and_sizes(self):
        self.run_lua('''
            local shapes,flips,small,large={},{},false,false
            for i=1,200 do
                local shape,flip,scale=T.boltLook(i)
                assert(shape>=1 and shape<=D.data.boltShapes and scale>=D.data.boltScale[1] and scale<=D.data.boltScale[2])
                shapes[shape]=true; flips[flip]=true
                small=small or scale<0.9; large=large or scale>1.05
                local again,_,_=T.boltLook(i); assert(again==shape, 'the same bolt always looks the same')
            end
            assert(shapes[1] and shapes[2] and shapes[3] and shapes[4] and flips[true] and flips[false] and small and large)
            ModCallbacks.MC_POST_ROOM_RENDER_ENTITIES=1044
            local p=makePlayer({delay=0}); enemy(320,280)
            local seen={}
            for i=1,120 do
                tick()
                spriteLog={}; D.onRoomRender()
                for _,e in ipairs(spriteLog) do if (e.anim or ''):find('^Strike') then seen[e.anim]=true end end
            end
            assert(seen.Strike and seen.Strike2 and seen.Strike3 and seen.Strike4, 'all four shapes are drawn')
        ''')

    def test_a_twister_roars_with_its_own_wind_and_winds_never_pile_up(self):
        self.run_lua('''
            GetSound=Isaac.GetSoundIdByName
            Isaac.GetSoundIdByName=function(name) if name=='Conch Dragon Twister' then return 903 end return GetSound(name) end
            -- Fast tears, so twisters rise faster than the gap between winds.
            local p=makePlayer({items=2,delay=0,rolls={0,0,0,0,0}}); enemy(320,280)
            local winds, joined = {}, false
            for i=1,240 do
                local before=#sounds; tick()
                for k=before+1,#sounds do
                    local s=sounds[k]
                    assert(s.id~=425, 'no Hush sound')
                    if s.id==903 then winds[#winds+1]=i; near(s.volume,D.data.twisterVolume) end
                end
                if #winds==1 and #D._twisters>1 then joined=true end
            end
            assert(#winds>=2, 'a wind roars as the first twister rises, and again later: '..#winds)
            assert(joined, 'twisters rising within the gap join the wind already blowing')
            for k=2,#winds do assert(winds[k]-winds[k-1]>=D.data.twisterWindGap, 'winds start at least the gap apart') end
            local strong=T.pullToward(Vector(0,0),Vector(100,0),false)
            assert(strong:Length()>=4, 'a strong pull: '..strong:Length())
        ''')

    def test_a_dead_or_ghost_holder_calls_down_nothing_but_keeps_the_weather(self):
        self.run_lua('''
            local dead=makePlayer({delay=0}); local ghost=makePlayer({delay=0}); local alive=makePlayer({delay=0,damage=3})
            function dead:IsDead() return true end
            function ghost:IsDead() return false end
            function ghost:IsCoopGhost() return true end
            local e=enemy(320,280)
            for i=1,30 do tick() end
            assert(#e.hits>0, 'the living holder still strikes')
            for _,h in ipairs(e.hits) do assert(h.source==alive, 'a bolt credited to a dead or ghost holder') end
            assert(D._charge[GetPtrHash(dead)]==0 and D._charge[GetPtrHash(ghost)]==0, 'nothing is banked while dead')
            alive.items=0; local hits=#e.hits
            for i=1,30 do tick() end
            assert(#e.hits==hits, 'dead and ghost holders strike nothing')
            assert(playing[RAIN], 'the rain keeps falling while they hold it')
            -- A twister whose owner dies fades out without hurting anything.
            D._twisters={{position=Vector(320,280),age=0,player=EntityPtr(dead)}}
            tick(); assert(#e.hits==hits and D._twisters[1].age>=D.data.twisterTicks)
            -- Revived: it calls down lightning again.
            function dead:IsDead() return false end
            for i=1,30 do tick() end
            assert(#e.hits>hits and e.hits[#e.hits].source==dead)
        ''')

    def test_the_rain_is_heard_while_anyone_holds_it(self):
        self.run_lua('''
            local p=makePlayer()
            for i=1,90 do tick() end
            local rains=0
            for _,s in ipairs(sounds) do
                if s.id==RAIN then rains=rains+1; assert(s.loop==true and s.volume==D.data.rainVolume) end
            end
            assert(rains==1 and playing[RAIN], 'one rain loop, started once: '..rains)
            D.onNewRoom(); for i=1,30 do tick() end
            assert(playing[RAIN] and #stopped==0, 'the rain carries on into the next room')
            p.items=0; tick()
            assert(not playing[RAIN] and stopped[1]==RAIN, 'it stops once nobody holds it')
            p.items=1; tick(); assert(playing[RAIN], 'and comes back with the item')
            D.onPreGameExit(); assert(not playing[RAIN], 'leaving the game stops it')
            p.items=1; tick(); D.onGameStarted(); assert(not playing[RAIN], 'a new game starts quiet')
        ''')

    def test_the_sound_settings_scale_the_storm_and_restart_the_rain(self):
        self.run_lua('''
            local function last(id)
                local volume
                for _,s in ipairs(sounds) do if s.id==id then volume=s.volume end end
                return volume
            end
            ConchBlessing.Config={soundVolume=5, rainVolume=10}
            local p=makePlayer({delay=0}); enemy(320,280)
            for i=1,60 do tick() end
            near(last(RAIN), D.data.rainVolume*0.5, 1e-9)
            assert(last(902) and last(902)<=T.boltVolumeForGap(1e9)*0.5+1e-9 and last(902)>=D.data.boltVolume*0.5-1e-9,
                'bolts at half: '..tostring(last(902)))
            -- A changed setting restarts the loop at its new level at once.
            ConchBlessing.Config.rainVolume=5; tick()
            near(last(RAIN), D.data.rainVolume*0.25, 1e-9); assert(playing[RAIN])
            -- Off: the rain stops and stays off; the bolts fall silent too.
            ConchBlessing.Config.soundVolume=0; tick()
            assert(not playing[RAIN], 'no rain at 0%')
            local rains=0
            for _,s in ipairs(sounds) do if s.id==RAIN then rains=rains+1 end end
            for i=1,30 do tick() end
            local again=0
            for _,s in ipairs(sounds) do if s.id==RAIN then again=again+1 end end
            assert(again==rains and not playing[RAIN], 'it does not restart while off')
            assert(last(902)==0, 'bolts play at 0')
            ConchBlessing.Config={}; tick()
            near(last(RAIN), D.data.rainVolume, 1e-9); assert(playing[RAIN], 'back at full with the defaults')
        ''')

    def test_a_quiet_distant_rumble_rolls_while_held(self):
        self.run_lua('''
            -- 3-8 s after entering, then every 12-20 s, with or without enemies.
            makePlayer()
            local at={}
            for i=1,1800 do tick(); if #cues()>#at then at[#at+1]=frame end end
            for _,s in ipairs(cues()) do assert(s.id==472 and s.volume==D.data.rumbleVolume and s.pitch<1) end
            local first=at[1]-(frame-1800)
            assert(first>=D.data.rumbleFirst[1] and first<=D.data.rumbleFirst[2], 'first rumble at '..first)
            for k=2,#at do local gap=at[k]-at[k-1]; assert(gap>=D.data.rumbleGap[1] and gap<=D.data.rumbleGap[2], 'gap '..gap) end
            assert(#at>=3 and #at<=5, 'rumbles in a minute: '..#at)
            players[1].items=0; sounds={}
            for i=1,900 do tick() end
            assert(#sounds==0 and not playing[RAIN], 'silent once nobody holds it')
            assert(T.rumbleWait({10,20},1)>=10 and T.rumbleWait({10,20},1)<=20 and T.rumbleWait({10,20},3)==T.rumbleWait({10,20},3))
        ''')

    def test_thunder_cues_are_loud_enough_to_hear(self):
        import importlib.util
        import math
        import re
        spec = importlib.util.spec_from_file_location('sound_levels', Path(__file__).with_name('test_upgrade_sound_levels.py'))
        levels = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(levels)
        try:
            levels.UpgradeSoundLevelTests.setUpClass()
        except unittest.SkipTest as skip:
            self.skipTest(str(skip))
        probe = levels.UpgradeSoundLevelTests()
        source = (ROOT / 'scripts/items/collectibles/dragon.lua').read_text(encoding='utf-8')
        cues = (('thunderVolume', 'Conch Dragon Thunder'), ('rumbleVolume', 'SOUND_THUNDER'))
        volume = lambda name: float(re.search(name + r'\s*=\s*([\d.]+)', source)[1])
        loudest = {}
        for name, sound in cues:
            self.assertLessEqual(volume(name), 1)
            for sample in probe.samples(sound):
                level = levels.loudest_db(sample) + 20 * math.log10(volume(name))
                loudest[name] = max(loudest.get(name, -99), level)
                self.assertGreaterEqual(level, levels.QUIETEST_DB, f'{name} on {sample.name}: {level:.1f} dB')
        # The user's levels (2026-10-13): bolt -5 dB, thunderclap -6 dB, twister
        # -6 dB, the rain loop -21 dB (lowered twice by 3 dB the same day).
        for name, sound, count, want in (('boltVolume', 'Conch Dragon Bolt', 5, -5.0),
                                         ('twisterVolume', 'Conch Dragon Twister', 2, -6.0),
                                         ('thunderVolume', 'Conch Dragon Thunder', 2, -6.0),
                                         ('rainVolume', 'Conch Dragon Rain', 1, -21.0)):
            takes = probe.samples(sound)
            self.assertEqual(len(takes), count, sound)
            for sample in takes:
                level = levels.loudest_db(sample) + 20 * math.log10(volume(name))
                self.assertAlmostEqual(level, want, delta=0.5, msg=f'{name} on {sample.name}: {level:.1f} dB')

    def test_rooms_reset_and_missing_art_reports_once(self):
        self.run_lua('''
            local p=makePlayer({delay=0}); enemy(320,280)
            for i=1,10 do tick() end
            assert(#D._bolts>0)
            D._twisters={{position=Vector(0,0),age=0}}
            D.onNewRoom(); assert(#D._bolts==0 and #D._twisters==0 and next(D._charge)==nil)
            failArt=true; spriteLog={}
            for i=1,3 do D.onRender() end
            assert(#errors==1 and errors[1]:find('art unavailable',1,true), table.concat(errors,';'))
        ''')

    def test_debug_lines_only_with_debug_mode(self):
        self.run_lua('''
            local p=makePlayer({delay=0}); enemy(320,280)
            for i=1,10 do tick() end
            assert(#logs==0)
            ConchBlessing.Config.debugMode=true
            for i=1,10 do tick() end
            assert(table.concat(logs,'\\n'):find('[Dragon] bolt at',1,true))
        ''')

    def test_registry_entry_is_a_weather_passive_with_the_twister_synergy(self):
        source = (ROOT / 'scripts/conch_blessing_items.lua').read_text(encoding='utf-8')
        block = source[source.index('    DRAGON = {'):]
        block = block[:block.index('\n    },\n')]
        self.assertIn('type = "passive"', block)
        self.assertIn('COLLECTIBLE_TAURUS', block)
        self.assertIn('name = "Dragon" }] = "dragon"', block)
        self.assertIn('postRoomRenderEntities = "dragon.onRoomRender"', block)
        self.assertNotIn('entity =', block)
        # 진 is numbered right after 자 and before the familiars; the unfinished
        # zodiac previews come after them (user order, 2026-10-24).
        xml = (ROOT / 'content/items.xml').read_text(encoding='utf-8')
        names = re.findall(r'<(passive|active|familiar|trinket) id="\d+" name="([^"]+)"', xml)
        start = [name for _, name in names].index('Dragon')
        self.assertEqual(names[start - 1], ('passive', 'Rat'))
        self.assertEqual(names[start + 1][0], 'familiar')
        mapping = (ROOT / 'scripts/callback_manager.lua').read_text(encoding='utf-8')
        self.assertIn('getRepentogonCallback("MC_POST_ROOM_RENDER_ENTITIES")', mapping)


if __name__ == '__main__':
    unittest.main()
