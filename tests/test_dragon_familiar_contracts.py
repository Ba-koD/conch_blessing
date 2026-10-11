"""Dragon familiar's shipped Lua with engine doubles; real HP and art remain in-game.

Expected values come from the item's design: contact 5% of damage per tick per
enemy, lightning on every enemy the snout runs into for 5x damage (once
every five seconds each, one dragon per copy), 5x more on bosses, BFFS
doubling, no flight or spectral tears, and cosmetic sparks along the body.
Motion contracts: the head turns smoothly and keeps up, the body stays on the
head's trail without bunching, and turns roll down the body.
"""
from pathlib import Path
import unittest

from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class DragonFamiliarContracts(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().repo = ROOT.as_posix()
        self.lua.execute(r'''
            package.path=repo..'/?.lua;'..package.path
            package=nil
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
            renderFrame=0; frame=0; entities={}; scans=0; sounds={}; shakes=0; logs={}; errors={}; checks={}
            CacheFlag={CACHE_FAMILIARS=1,CACHE_FLYING=2,CACHE_TEARFLAG=4}
            TearFlags={TEAR_SPECTRAL=8}
            EntityFlag={FLAG_FRIENDLY=1}
            EntityCollisionClass={ENTCOLL_NONE=0,ENTCOLL_ALL=4}
            EntityGridCollisionClass={GRIDCOLL_NONE=0}
            EntityType={ENTITY_FAMILIAR=3}
            CollectibleType={COLLECTIBLE_BFFS=247}
            function EntityRef(e) return {Entity=e} end
            function GetPtrHash(e) return tostring(e) end
            Color=function(r,g,b,a) return {R=r,G=g,B=b,A=a} end
            function EntityPtr(e) return setmetatable({},{__index=function(_,k) if k=='Ref' and e:Exists() then return e end end}) end
            room={GetRenderMode=function() return renderMode end}
            game={GetFrameCount=function() return frame end,ShakeScreen=function() shakes=shakes+1 end,
                GetRoom=function() return room end}
            function Game() return game end
            function SFXManager() return {Play=function(_,id,v) sounds[#sounds+1]={id=id,volume=v} end} end
            spriteLog={}
            Sprite=setmetatable({},{__call=function()
                local s={}
                function s:Load(path) if failArt then error('missing '..path) end self.path=path end
                function s:IsLoaded() return true end
                function s:SetFrame(name,f) self.anim=name; self.frame=f end
                function s:Render(pos) spriteLog[#spriteLog+1]={anim=self.anim,frame=self.frame,flip=self.FlipY,rot=self.Rotation,pos=pos,scale=self.Scale} end
                return s
            end})
            Isaac={GetItemIdByName=function() return 600 end,
                GetFrameCount=function() return renderFrame end,
                GetRoomEntities=function() scans=scans+1; return entities end,
                FindByType=function(t,v) local out={} for _,e in ipairs(entities) do if e.Type==t and e.Variant==v then out[#out+1]=e end end return out end,
                WorldToScreen=function(p) return Vector(p.X,p.Y) end,
                GetItemConfig=function() return {GetCollectible=function(_,id) return {ID=id} end} end,
                GetSoundIdByName=function(name) return name=='Conch Upgrade Thunder Strike' and 901 or -1 end}
            ConchBlessing={ItemData={DRAGON={entity={variant=778}}},Config={debugMode=false},
                printDebug=function(t) logs[#logs+1]=t end,printError=function(t) errors[#errors+1]=t end}
            function makePlayer()
                local p={Position=Vector(300,200),Damage=10,InitSeed=1,items=0,temp=0,bffs=false,TearFlags=0,CanFly=false,alive=true}
                function p:Exists() return self.alive end
                function p:ToPlayer() return self end
                function p:GetCollectibleNum() return self.items end
                function p:HasCollectible(id) return id==247 and self.bffs end
                function p:GetEffects() return {GetCollectibleEffectNum=function() return p.temp end} end
                function p:GetCollectibleRNG() return {} end
                function p:CheckFamiliar(variant,count,rng,config) checks[#checks+1]={variant=variant,count=count,config=config} end
                return p
            end
            function makeFamiliar(player)
                local f={Type=3,Variant=778,Position=Vector(player.Position.X+60,player.Position.Y),Velocity=Vector(0,0),
                    Player=player,InitSeed=4242,data={},sprite={}}
                function f:GetData() return self.data end
                function f:GetSprite() local s=self.sprite; function s:Play(n) s.anim=n end return s end
                function f:ToFamiliar() return self end
                function f:Exists() return true end
                function f:ToNPC() return nil end
                return f
            end
            function enemy(x,y,opts)
                opts=opts or {}
                local e={Type=10,Variant=0,Position=Vector(x,y),Size=opts.size or 10,InitSeed=opts.seed or (x*1000+y),
                    hits={},alive=true,boss=opts.boss,friendly=opts.friendly,vulnerable=opts.vulnerable~=false}
                function e:ToNPC() return self end
                function e:Exists() return self.alive end
                function e:IsVulnerableEnemy() return self.vulnerable end
                function e:IsActiveEnemy() return true end
                function e:IsDead() return self.dead==true end
                function e:HasEntityFlags(f) return f==1 and self.friendly==true end
                function e:IsBoss() return self.boss==true end
                function e:TakeDamage(amount,flags,source) self.hits[#self.hits+1]={amount=amount,frame=frame,source=source.Entity} end
                entities[#entities+1]=e
                return e
            end
            function tick(f)
                frame=frame+1; renderFrame=renderFrame+2
                f.Position=f.Position+f.Velocity
                D.onFamiliarUpdate(nil,f)
                D.onUpdate()
            end
            require('scripts.items.collectibles.dragon'); D=ConchBlessing.dragon; T=D._test
            function near(a,b,eps) assert(math.abs(a-b)<=(eps or 1e-9), tostring(a)..' ~= '..tostring(b)) end
        ''')

    def run_lua(self, code):
        self.lua.execute(code)

    def test_damage_rules_follow_the_design(self):
        self.run_lua('''
            near(T.contactDamage(10,false),0.5); near(T.contactDamage(3.5,false),0.175)
            near(T.contactDamage(10,true),1.0)
            near(T.lightningDamage(10,false,false),50); near(T.lightningDamage(10,true,false),250)
            near(T.lightningDamage(10,false,true),100); near(T.lightningDamage(10,true,true),500)
        ''')

    def test_orbit_breathes_and_changes_speed_like_a_creature(self):
        self.run_lua('''
            local s={p1=0.3,p2=1.7,p3=2.2,p4=4.1}
            local minS,maxS,minR,maxR=1e9,-1e9,1e9,-1e9
            for t=1,2000 do
                local sp,r=T.orbitShape(s,t)
                minS=math.min(minS,sp); maxS=math.max(maxS,sp); minR=math.min(minR,r); maxR=math.max(maxR,r)
            end
            local base=D.data.angularSpeed
            assert(maxS-minS>base*0.8, 'speed varies a lot: '..minS..'..'..maxS)
            assert(minS>0, 'never turns backwards')
            assert(maxR-minR>30 and minR>=74-31-1e-9 and maxR<=74+31+1e-9, minR..'..'..maxR)
            local a1,b1=T.orbitShape(s,123); local a2,b2=T.orbitShape(s,123); near(a1,a2); near(b1,b2)
        ''')

    def test_contact_hits_each_touching_enemy_once_per_tick(self):
        self.run_lua('''
            local p=makePlayer(); p.items=1; p.Damage=10; local f=makeFamiliar(p); D.onFamiliarInit(nil,f)
            tick(f)
            local s=f.data.__ConchDragon
            local close=enemy(0,0); local far=enemy(9999,9999)
            local ally=enemy(0,0,{friendly=true}); local immune=enemy(0,0,{vulnerable=false})
            local dead=enemy(0,0); dead.dead=true
            D.data.lightningInterval=100000; s.cooldown=100000
            for i=1,10 do
                -- Pin the enemies onto the body so several segments touch them at once.
                close.Position=s.segments[3]; ally.Position=s.segments[3]; immune.Position=s.segments[3]; dead.Position=s.segments[3]
                tick(f)
            end
            assert(#close.hits==10, 'once per tick: '..#close.hits)
            for _,h in ipairs(close.hits) do near(h.amount,0.5); assert(h.source==f) end
            assert(#far.hits==0 and #ally.hits==0 and #immune.hits==0 and #dead.hits==0)
            p.bffs=true; close.Position=s.segments[1]; local n=#close.hits; tick(f)
            local found=false
            for i=n+1,#close.hits do if math.abs(close.hits[i].amount-1.0)<1e-9 then found=true end end
            assert(found, 'BFFS doubles contact')
        ''')

    def test_one_room_scan_per_update_for_every_dragon(self):
        self.run_lua('''
            local p=makePlayer(); p.items=2; local a,b=makeFamiliar(p),makeFamiliar(p)
            D.onFamiliarInit(nil,a); D.onFamiliarInit(nil,b); enemy(0,0)
            scans=0; frame=frame+1; D.onFamiliarUpdate(nil,a); D.onFamiliarUpdate(nil,b)
            assert(scans==1, 'scans='..scans)
        ''')

    def test_snout_running_into_an_enemy_calls_lightning_once_a_second(self):
        self.run_lua('''
            local p=makePlayer(); p.items=1; p.Damage=10; local f=makeFamiliar(p); D.onFamiliarInit(nil,f)
            for i=1,60 do tick(f) end
            local e=enemy(0,0,{size=10}); local boss=enemy(0,0,{size=10,boss=true})
            local function bolts(target)
                local out={}
                for _,h in ipairs(target.hits) do if h.amount>=20 then out[#out+1]=h end end
                return out
            end
            for i=1,600 do
                e.Position=p.Position+Vector(-150,-40); boss.Position=p.Position+Vector(160,50)
                tick(f)
            end
            local a,b=bolts(e),bolts(boss)
            assert(#a>=2 and #b>=2, 'the dragon keeps running into both: '..#a..','..#b)
            for _,h in ipairs(a) do near(h.amount,50); assert(h.source==f) end
            for _,h in ipairs(b) do near(h.amount,250) end
            for _,list in ipairs({a,b}) do
                for i=2,#list do assert(list[i].frame-list[i-1].frame>=D.data.strikeCooldown, 'once a second per enemy') end
            end
            assert(#sounds>=4 and sounds[1].id==901 and shakes>=4, 'thunder and a shake with each bolt')
        ''')

    def test_no_lightning_without_the_snout_touching(self):
        self.run_lua('''
            local p=makePlayer(); p.items=1; p.Damage=10; local f=makeFamiliar(p); D.onFamiliarInit(nil,f)
            local s=f.data.__ConchDragon
            for i=1,60 do tick(f) end
            local e=enemy(0,0,{size=10})
            for i=1,60 do e.Position=s.segments[6]; tick(f) end   -- held against the body, away from the head
            for _,h in ipairs(e.hits) do assert(h.amount<1, 'only body contact: '..h.amount) end
            assert(#e.hits>0 and #D._strikes==0)
        ''')

    def test_familiar_count_and_owned_flags(self):
        self.run_lua('''
            local p=makePlayer()
            p.items=2; p.temp=1; D.onEvaluateCache(nil,p,CacheFlag.CACHE_FAMILIARS)
            assert(checks[1].variant==778 and checks[1].count==3 and checks[1].config.ID==600, 'one dragon per copy and effect')
            p.items=0; p.temp=0; D.onEvaluateCache(nil,p,CacheFlag.CACHE_FAMILIARS)
            assert(checks[2].count==0, 'the last dragon is removed')
            p.items=1; D.onEvaluateCache(nil,p,CacheFlag.CACHE_FLYING); D.onEvaluateCache(nil,p,CacheFlag.CACHE_TEARFLAG)
            assert(not p.CanFly and p.TearFlags==0, 'Dragon grants no flight or spectral tears')
            local q=makePlayer(); q.items=0; q.temp=1
            D.onEvaluateCache(nil,q,CacheFlag.CACHE_FAMILIARS); assert(checks[#checks].count==1, 'a temporary dragon appears')
        ''')

    def test_missing_art_reports_once_and_never_breaks(self):
        self.run_lua('''
            failArt=true
            local p=makePlayer(); p.items=1; local a,b=makeFamiliar(p),makeFamiliar(p)
            D.onFamiliarInit(nil,a); D.onFamiliarInit(nil,b); tick(a); tick(b)
            D.onFamiliarRender(nil,a,Vector(0,0)); D.onFamiliarRender(nil,b,Vector(0,0)); D.onFamiliarRender(nil,a,Vector(0,0))
            assert(#errors==1, 'one report: '..#errors)
            D._strikes={{position=Vector(0,0),age=0}}; D.onRender(); D.onRender()
            assert(#errors==2, 'lightning art failure reported once too')
        ''')

    def test_debug_lines_only_with_debug_mode(self):
        self.run_lua('''
            local p=makePlayer(); p.items=1; p.Damage=10; local f=makeFamiliar(p); D.onFamiliarInit(nil,f)
            local s=f.data.__ConchDragon
            local e=enemy(0,0)
            local function snout() return s.segments[1]+Vector(math.cos(s.dir),math.sin(s.dir))*(D.data.headReach+s.speed) end
            e.Position=snout(); tick(f)
            assert(#logs==0)
            ConchBlessing.Config.debugMode=true; s.struck={}
            e.Position=snout(); tick(f)
            local text=table.concat(logs,'\\n')
            assert(text:find('[Dragon] strike 10.0 boss=false damage=50.00',1,true), text)
        ''')

    def test_several_dragons_go_for_different_enemies(self):
        self.run_lua('''
            local p=makePlayer(); p.items=2
            local a,b=makeFamiliar(p),makeFamiliar(p); b.InitSeed=777; b.Position=Vector(p.Position.X-60,p.Position.Y)
            D.onFamiliarInit(nil,a); D.onFamiliarInit(nil,b)
            for i=1,40 do frame=frame+1; D.onFamiliarUpdate(nil,a); D.onFamiliarUpdate(nil,b) end
            local e1=enemy(0,0,{size=10}); local e2=enemy(0,0,{size=10})
            local sa,sb=a.data.__ConchDragon,b.data.__ConchDragon
            local apart=0
            for i=1,30 do
                e1.Position=p.Position+Vector(300,0); e2.Position=p.Position+Vector(310,40)
                frame=frame+1; D.onFamiliarUpdate(nil,a); D.onFamiliarUpdate(nil,b)
                if sa.prey and sb.prey and sa.prey~=sb.prey then apart=apart+1 end
            end
            assert(apart>=25, 'two dragons take one enemy each: '..apart)
            -- A lone enemy draws both.
            e2.alive=false
            for i=1,30 do
                e1.Position=p.Position+Vector(300,0)
                frame=frame+1; D.onFamiliarUpdate(nil,a); D.onFamiliarUpdate(nil,b)
            end
            assert(sa.prey==GetPtrHash(e1) or sa.passing, 'dragon a hunts the lone enemy')
            assert(sb.prey==GetPtrHash(e1) or sb.passing, 'dragon b hunts the lone enemy')
        ''')

    def test_extra_dragons_keep_the_snout_lightning(self):
        self.run_lua('''
            local p=makePlayer(); p.items=3; p.Damage=10; local f=makeFamiliar(p); D.onFamiliarInit(nil,f)
            for i=1,60 do tick(f) end
            local e=enemy(0,0,{size=10})
            for i=1,500 do e.Position=p.Position+Vector(-150,-40); tick(f) end
            local bolts=0
            for _,h in ipairs(e.hits) do if h.amount>=20 then bolts=bolts+1; near(h.amount,50) end end
            assert(bolts>=2, 'three Dragons still strike lightning: '..bolts)
        ''')

    def test_sparks_crackle_now_and_then_and_hurt_nothing(self):
        self.run_lua('''
            local d=D.data
            local p=makePlayer(); p.items=1; local f=makeFamiliar(p); D.onFamiliarInit(nil,f)
            local s=f.data.__ConchDragon
            local born,last,gaps,seen={},nil,{},{}
            for t=1,600 do
                local before={}
                for _,sp in ipairs(s.sparks) do before[sp]=true end
                tick(f)
                for _,sp in ipairs(s.sparks) do
                    if not before[sp] and not seen[sp] then
                        seen[sp]=true; born[#born+1]=sp
                        if last then gaps[#gaps+1]=t-last end
                        last=t
                    end
                end
                assert(#s.sparks<=2, 'only a spark or two at a time: '..#s.sparks)
                for _,sp in ipairs(s.sparks) do
                    assert(sp.age<d.sparkFrames*d.sparkFrameTicks, 'spent sparks are dropped')
                    assert(sp.part>=1 and sp.part<=#d.parts and math.abs(sp.side)<=d.sparkSpread)
                    assert(sp.angle>=0 and sp.angle<360)
                end
            end
            assert(#born>=40 and #born<=100, 'a spark every 6-14 updates: '..#born)
            for _,g in ipairs(gaps) do assert(g>=d.sparkGap[1] and g<=d.sparkGap[2], 'gap '..g) end
            local parts={}
            for _,sp in ipairs(born) do parts[sp.part]=true end
            local n=0; for _ in pairs(parts) do n=n+1 end
            assert(n>=10, 'sparks land all along the body: '..n)
            assert(#sounds==0 and shakes==0, 'sparks make no sound and shake nothing')
            -- The same seed crackles the same way; another seed differs.
            local function sequence(seed)
                local st={sparks={},sparkWait=1,sparkSeed=seed}
                local out={}
                for i=1,200 do
                    T.updateSparks(st)
                    local sp=st.sparks[#st.sparks]
                    if sp and sp.age==0 then out[#out+1]=sp.part..':'..math.floor(sp.angle) end
                end
                return table.concat(out,',')
            end
            assert(sequence(77)==sequence(77) and sequence(77)~=sequence(78))
            local seed,r=T.cosmeticRoll(1); assert(r>=0 and r<1 and seed~=1)
        ''')

    def test_sparks_draw_on_top_of_their_part_and_clear_with_the_room(self):
        self.run_lua('''
            local p=makePlayer(); p.items=1; local f=makeFamiliar(p); D.onFamiliarInit(nil,f)
            entities[#entities+1]=f
            for i=1,30 do tick(f) end
            local s=f.data.__ConchDragon
            s.renders=2
            s.sparks={{part=5,angle=90,side=0,age=3}}
            spriteLog={}; D.onFamiliarRender(nil,f,Vector(0,0))
            local last=spriteLog[#spriteLog]
            assert(last.anim=='Spark' and last.frame==1 and last.rot==90, 'the spark is drawn last')
            local lift=T.partLift(5,s.t)
            near(last.pos.X,s.segments[5].X,1e-6); near(last.pos.Y,s.segments[5].Y-lift,1e-6)
            near(last.scale.X,T.partTaper(5))
            s.sparks={{part=5,angle=0,side=4,age=0}}
            spriteLog={}; D.onFamiliarRender(nil,f,Vector(0,0))
            local off=spriteLog[#spriteLog].pos-(s.segments[5]-Vector(0,lift))
            near(off:Length(),4*T.partTaper(5),1e-6)
            D.onNewRoom(); assert(#s.sparks==0, 'a new room starts without sparks')
        ''')

    def test_trail_records_the_heads_path_and_lays_parts_on_it(self):
        self.run_lua('''
            local total=0; for _,g in ipairs(D.data.spacing) do total=total+g end
            -- An L-shaped trail, newest point first.
            local trail={Vector(0,0),Vector(-20,0),Vector(-20,-60)}
            local pos=T.sampleTrail(trail,10,0); near(pos.X,-10); near(pos.Y,0)
            pos=T.sampleTrail(trail,35,0); near(pos.X,-20); near(pos.Y,-15)
            pos=T.sampleTrail(trail,100,0); near(pos.X,-20); near(pos.Y,-80)   -- straight on past the end
            local positions,angles=T.layOut(trail,0)
            assert(#positions==#D.data.parts and #D.data.parts==14, 'a long fourteen-part dragon')
            local offset=0
            for i=1,#positions do
                if i>1 then offset=offset+D.data.spacing[i-1] end
                local want=T.sampleTrail(trail,offset,0)
                near(positions[i].X,want.X,1e-9); near(positions[i].Y,want.Y,1e-9)
            end
            near(angles[1],0)                                      -- the head faces its heading
            near(angles[4],math.pi/2,1e-6)                         -- the body faces along the trail
            -- Small moves slide the newest point; points past the body's length drop off.
            local tr={Vector(0,0),Vector(-5,0)}
            T.pushTrail(tr,Vector(0.2,0)); assert(#tr==2 and tr[1].X==0.2, 'a tiny move slides the newest point')
            for x=1,300 do T.pushTrail(tr,Vector(x,0)) end
            local length=0; for i=2,#tr do length=length+tr[i]:Distance(tr[i-1]) end
            assert(length<=total+4+1.01 and length>=total, 'the trail keeps just the body length: '..length)
            -- The body thins toward the tail.
            assert(T.partTaper(1)==1 and T.partTaper(#D.data.parts)<0.7 and T.partTaper(7)<1 and T.partTaper(7)>T.partTaper(12))
        ''')

    def test_familiar_orbits_the_player_without_a_fixed_circle(self):
        self.run_lua('''
            local p=makePlayer(); p.items=1; local f=makeFamiliar(p)
            D.onFamiliarInit(nil,f)
            assert(f.EntityCollisionClass==0 and f.GridCollisionClass==0 and f.sprite.anim=='Hidden')
            local s=f.data.__ConchDragon
            local speeds,dists={},{}
            for i=1,1500 do
                tick(f)
                assert(f.Position.X==s.head.X and f.Position.Y==s.head.Y, 'the entity follows the head')
                if i>150 then speeds[#speeds+1]=s.speed; dists[#dists+1]=f.Position:Distance(p.Position) end
            end
            local minS,maxS=math.min(table.unpack(speeds)),math.max(table.unpack(speeds))
            assert(maxS>minS*1.5, 'swims at changing speeds: '..minS..'..'..maxS)
            local minD,maxD=math.min(table.unpack(dists)),math.max(table.unpack(dists))
            assert(minD>20 and maxD<130 and maxD-minD>20, 'circles near the player without crossing it: '..minD..'..'..maxD)
        ''')

    def test_head_direction_never_jumps(self):
        self.run_lua('''
            local p=makePlayer(); p.items=1; local f=makeFamiliar(p); D.onFamiliarInit(nil,f)
            local s=f.data.__ConchDragon
            local prey=enemy(0,0,{size=10})
            prey.alive=false
            local lastDir,lastVel=s.dir,s.turnVel
            for i=1,1500 do
                -- Idle, then a running player, then an enemy that teleports about.
                if i>400 and i<700 then p.Position=p.Position+Vector(((i//60)%2==0) and 5 or -5,0) end
                if i>=800 then prey.alive=true; if i%90==0 then prey.Position=p.Position+Vector(((i//90)%2==0) and 150 or -150,60) end end
                tick(f)
                local turn=((s.dir-lastDir)+math.pi)%(2*math.pi)-math.pi
                assert(math.abs(turn)<=D.data.hurryTurnRate+1e-9, 'turn per update: '..turn)
                assert(math.abs(s.turnVel-lastVel)<=D.data.turnAccel*2.5+1e-9, 'turning eases in and out: '..(s.turnVel-lastVel))
                lastDir,lastVel=s.dir,s.turnVel
            end
        ''')

    def test_dragon_keeps_up_with_a_running_player(self):
        self.run_lua('''
            local p=makePlayer(); p.items=1; local f=makeFamiliar(p); D.onFamiliarInit(nil,f)
            local maxD=0
            for i=1,900 do
                p.Position=p.Position+Vector(((i//150)%2==0) and 5 or -5,0)
                local before=f.Position
                tick(f)
                assert(f.Position:Distance(before)<=D.data.maxSpeed+1e-6, 'no teleport while following')
                if i>60 then maxD=math.max(maxD,f.Position:Distance(p.Position)) end
            end
            assert(maxD<170, 'keeps up: '..maxD)
        ''')

    def test_body_stays_on_the_heads_trail_and_never_bunches(self):
        self.run_lua('''
            local p=makePlayer(); p.items=1; local f=makeFamiliar(p); D.onFamiliarInit(nil,f)
            local s=f.data.__ConchDragon
            local n=#D.data.parts
            for i=1,1200 do
                p.Position=p.Position+Vector(((i//200)%3==1) and 4 or 0,0)
                tick(f)
                local offset=0
                for k=1,n do
                    if k>1 then offset=offset+D.data.spacing[k-1] end
                    local want=T.sampleTrail(s.trail,offset,s.dir)
                    near(s.segments[k].X,want.X,1e-9); near(s.segments[k].Y,want.Y,1e-9)
                    if k>1 then
                        local chord=s.segments[k]:Distance(s.segments[k-1])
                        assert(chord<=D.data.spacing[k-1]+1e-6 and chord>=D.data.spacing[k-1]*0.5, 'part gap '..chord)
                    end
                end
            end
        ''')

    def test_room_entry_puts_the_dragon_on_its_player(self):
        self.run_lua('''
            local p=makePlayer(); p.items=1; local f=makeFamiliar(p); D.onFamiliarInit(nil,f)
            entities[#entities+1]=f
            for i=1,60 do tick(f) end
            p.Position=Vector(120,380)                 -- the player enters at a door elsewhere
            D.onNewRoom()
            local s=f.data.__ConchDragon
            near(f.Position.X,120); near(f.Position.Y,380)
            near(s.segments[1].X,120); near(s.segments[1].Y,380)
            tick(f)
            assert(f.Position:Distance(p.Position)<D.data.maxSpeed, 'starts from the player, no dash across the room')
        ''')

    def test_dragon_hunts_any_enemy_at_once_in_a_weaving_line(self):
        self.run_lua('''
            local p=makePlayer(); p.items=1; local f=makeFamiliar(p); D.onFamiliarInit(nil,f)
            D.data.contactRadius=-10; D.data.lightningInterval=100000
            local s=f.data.__ConchDragon; s.cooldown=100000
            for i=1,60 do tick(f) end
            local prey=enemy(0,0,{size=10}); prey.Position=p.Position+Vector(260,90)   -- far across the room
            tick(f)
            assert(s.prey==GetPtrHash(prey), 'goes for an enemy as soon as it appears')
            local offsets,ranThrough={},false
            for i=1,300 do
                local before=s.passing
                tick(f)
                if not before and s.passing then ranThrough=true; break end
                local bearing=math.atan(prey.Position.Y-f.Position.Y,prey.Position.X-f.Position.X)
                offsets[#offsets+1]=((s.dir-bearing)+math.pi)%(2*math.pi)-math.pi
            end
            assert(ranThrough, 'reaches it and runs through')
            local lo,hi=math.min(table.unpack(offsets)),math.max(table.unpack(offsets))
            assert(lo<-0.2 and hi>0.2, 'weaves to both sides of the bearing: '..lo..'..'..hi)
            -- A fly-by: straight on through for passTicks, not coiling round the enemy.
            local dir=s.dir
            for i=1,D.data.passTicks-1 do tick(f) end
            assert(math.abs(((s.dir-dir)+math.pi)%(2*math.pi)-math.pi)<0.25, 'keeps on straight through')
            prey.alive=false
            for i=1,3 do tick(f) end
            assert(s.prey==nil, 'back to circling the player when the enemies are gone')
        ''')

    def test_hunt_is_a_fast_dash_and_a_plain_turn_onto_each_new_target(self):
        self.run_lua('''
            local p=makePlayer(); p.items=1; local f=makeFamiliar(p); D.onFamiliarInit(nil,f)
            D.data.contactRadius=-10; D.data.lightningInterval=100000
            local s=f.data.__ConchDragon; s.cooldown=100000
            for i=1,60 do tick(f) end
            local a,b=enemy(0,0,{size=10}),enemy(0,0,{size=10})
            local function pin() a.Position=p.Position+Vector(-180,-40); b.Position=p.Position+Vector(190,50) end
            pin()
            local top,turns,passEnd=0,{},nil
            for i=1,600 do
                pin()
                local before=s.passing
                tick(f)
                top=math.max(top,s.speed)
                if before and not s.passing then passEnd=i end
                if passEnd and s.prey then
                    local target=s.prey==GetPtrHash(a) and a or b
                    local bearing=math.atan(target.Position.Y-f.Position.Y,target.Position.X-f.Position.X)
                    if math.abs(((s.dir-bearing)+math.pi)%(2*math.pi)-math.pi)<0.5 then
                        turns[#turns+1]=i-passEnd; passEnd=nil
                    end
                end
            end
            assert(top>=D.data.chaseSpeed*0.9, 'dashes at the hunt speed: '..top)
            assert(#turns>=3, 'several passes: '..#turns)
            for _,ticks in ipairs(turns) do assert(ticks<=20, 'turns onto the new target in '..ticks..' updates') end
        ''')

    def test_big_room_hunt_is_not_pulled_back_and_draws_where_the_dragon_is(self):
        self.run_lua('''
            local p=makePlayer(); p.items=1; local f=makeFamiliar(p); D.onFamiliarInit(nil,f)
            D.data.contactRadius=-10; D.data.lightningInterval=100000
            local s=f.data.__ConchDragon; s.cooldown=100000
            for i=1,60 do tick(f) end
            local far=enemy(0,0,{size=10}); far.Position=p.Position+Vector(620,260)   -- across a 2x2 room
            local reached,maxAway=false,0
            for i=1,300 do
                local before=s.passing
                tick(f)
                maxAway=math.max(maxAway,f.Position:Distance(p.Position))
                if not before and s.passing then reached=true; break end
            end
            assert(reached and maxAway>500, 'hunts across the room without snapping back: '..maxAway)
            -- A real teleport of the player still brings the dragon along.
            far.alive=false
            p.Position=p.Position+Vector(0,300); tick(f)
            assert(f.Position:Distance(p.Position)<D.data.maxSpeed+1, 'follows a teleport')
            -- In a scrolling room the render offset carries the camera scroll:
            -- parts must land on their world positions, not be shifted twice.
            local scroll=Vector(-210,-130)
            Isaac.WorldToRenderPosition=function(at) return at-scroll end
            spriteLog={}; s.renders=1; s.sparks={}
            D.onFamiliarRender(nil,f,scroll)
            local head=spriteLog[#spriteLog]
            local want=s.previous[1]+(s.segments[1]-s.previous[1])*0.5
            near(head.pos.X,want.X,1e-9)
            assert(math.abs(head.pos.Y-(want.Y-T.partLift(1,s.t-0.5)))<1e-9, 'drawn on the dragon, scroll counted once')
            Isaac.WorldToRenderPosition=nil
        ''')

    def test_head_points_where_it_goes_and_the_body_never_kinks(self):
        self.run_lua('''
            local p=makePlayer(); p.items=1; local f=makeFamiliar(p); D.onFamiliarInit(nil,f)
            D.data.contactRadius=-10
            local s=f.data.__ConchDragon; s.cooldown=100000
            local a,b=enemy(0,0,{size=10}),enemy(0,0,{size=10})
            local worst=0
            for i=1,1200 do
                a.Position=p.Position+Vector(-170,-50); b.Position=p.Position+Vector(180,60)
                if i>600 then a.alive=false; b.alive=false end
                if i>800 and i<1000 then p.Position=p.Position+Vector(((i//50)%2==0) and 5 or -5,0) end
                tick(f)
                near(s.angles[1],s.dir,1e-12)                     -- the head faces its direction of travel
                for k=2,#s.angles-1 do
                    local bend=math.abs(((s.angles[k]-s.angles[k+1])+math.pi)%(2*math.pi)-math.pi)
                    worst=math.max(worst,bend)
                end
                local neck=math.abs(((s.angles[1]-s.angles[2])+math.pi)%(2*math.pi)-math.pi)
                worst=math.max(worst,neck)
            end
            assert(worst<=math.rad(30), 'no joint bends sharply: '..math.deg(worst))
        ''')

    def test_dragon_spreads_its_passes_over_every_enemy(self):
        self.run_lua('''
            local p=makePlayer(); p.items=1; local f=makeFamiliar(p); D.onFamiliarInit(nil,f)
            D.data.contactRadius=-10; D.data.lightningInterval=100000
            local s=f.data.__ConchDragon; s.cooldown=100000
            local list={enemy(0,0,{size=10}),enemy(0,0,{size=10}),enemy(0,0,{size=10})}
            local spots={Vector(-160,-60),Vector(170,-40),Vector(20,110)}
            local passes={0,0,0}
            for i=1,1800 do
                for k,e in ipairs(list) do e.Position=p.Position+spots[k] end
                local before=s.passing
                tick(f)
                if not before and s.passing then
                    for k,e in ipairs(list) do if s.passed[GetPtrHash(e)]==s.t then passes[k]=passes[k]+1 end end
                end
            end
            local lo,hi=math.min(table.unpack(passes)),math.max(table.unpack(passes))
            assert(lo>=2 and hi-lo<=1, 'every enemy gets its turn: '..table.concat(passes,','))
            -- The next prey is the enemy passed least recently.
            s.passing=nil; s.prey=nil
            s.passed[GetPtrHash(list[1])]=s.t-10; s.passed[GetPtrHash(list[2])]=s.t-50; s.passed[GetPtrHash(list[3])]=s.t-30
            tick(f)
            assert(s.prey==GetPtrHash(list[2]), 'goes for the enemy it hit longest ago')
        ''')

    def test_every_part_follows_one_orientation_rule(self):
        self.run_lua('''
            -- Facing: past vertical by the band, else unchanged (no flicker going straight up or down).
            local th=D.data.flipThreshold
            assert(T.facesLeft(math.pi,false)==true and T.facesLeft(0,true)==false)
            assert(T.facesLeft(math.pi/2+0.05,false)==false and T.facesLeft(math.pi/2-0.05,true)==true, 'the band keeps the facing')
            -- Drawing: the engine mirrors after rotating, so a mirrored part takes the negated angle.
            local sprite={}
            T.orient(sprite,math.rad(150),true); assert(sprite.FlipY==true and math.abs(sprite.Rotation+150)<1e-9)
            T.orient(sprite,math.rad(30),false); assert(sprite.FlipY==false and math.abs(sprite.Rotation-30)<1e-9)
            local p=makePlayer(); p.items=1; local f=makeFamiliar(p); D.onFamiliarInit(nil,f)
            local s=f.data.__ConchDragon
            local turned={}
            for i=1,900 do
                local was={}
                for k=1,#s.flips do was[k]=s.flips[k] end
                tick(f)
                for k=1,#s.flips do
                    if was[k]~=nil and was[k]~=s.flips[k] then
                        turned[k]=true
                        assert(math.abs(math.cos(s.angles[k]))>=th-1e-9, 'a part turns round only past the band')
                    end
                end
                s.renders=0; s.sparks={}
                spriteLog={}; D.onFamiliarRender(nil,f,Vector(0,0))
                -- Shadows first, then parts tail to head (a legs layer before its body part).
                local k=#s.segments+1
                for _,e in ipairs(spriteLog) do
                    if e.anim=='Shadow' then
                        assert(not e.flip and e.rot==0, 'shadows lie flat')
                    else
                        if e.anim~='Legs' then k=k-1 end
                        local part=e.anim=='Legs' and k-1 or k
                        local deg=math.deg(s.prevAngles[part])
                        assert(e.flip==s.flips[part], 'part '..part..' uses its own facing')
                        assert(math.abs(e.rot-(e.flip and -deg or deg))<1e-9, 'part '..part..' uses the one rule')
                        assert(e.scale.X==e.scale.Y, 'never squashed')
                    end
                end
            end
            assert(turned[1] and turned[#s.segments], 'the head and the tail both turn round over a lap')
        ''')

    def test_far_player_teleport_snaps_the_whole_dragon(self):
        self.run_lua('''
            local p=makePlayer(); p.items=1; local f=makeFamiliar(p); D.onFamiliarInit(nil,f)
            tick(f); p.Position=Vector(2000,2000); tick(f)
            local s=f.data.__ConchDragon
            assert(f.Position:Distance(p.Position)<20)
            local offset=0
            for i=1,#D.data.parts do
                if i>1 then offset=offset+D.data.spacing[i-1] end
                assert(math.abs(s.segments[i]:Distance(p.Position)-offset)<20, 'laid straight behind the head')
            end
        ''')

    def test_strike_visuals_age_out_and_rooms_reset(self):
        self.run_lua('''
            assert(T.strikeLength()==11)
            assert(T.strikeFrame(0)==0 and T.strikeFrame(1)==0 and T.strikeFrame(2)==1 and T.strikeFrame(10)==4 and T.strikeFrame(11)==nil)
            D._strikes={{position=Vector(0,0),age=0}}
            for i=1,10 do D.onUpdate() end
            assert(#D._strikes==1); D.onUpdate(); assert(#D._strikes==0)
            local p=makePlayer(); p.items=1; local f=makeFamiliar(p); D.onFamiliarInit(nil,f)
            entities[#entities+1]=f
            for i=1,40 do tick(f) end
            local s=f.data.__ConchDragon; s.struck={[1]=5}
            D._strikes={{position=Vector(0,0),age=0}}
            D.onNewRoom()
            assert(#D._strikes==0 and next(s.struck)==nil)
            -- On the player, with the body laid out straight behind the head.
            near(s.segments[1].X,p.Position.X); near(s.segments[1].Y,p.Position.Y)
            for i=2,#D.data.parts do
                near(s.segments[i]:Distance(s.segments[i-1]),D.data.spacing[i-1],1e-6)
                near(s.previous[i].X,s.segments[i].X)
            end
        ''')

    def test_render_draws_shadows_then_the_body_tail_first_with_legs_underneath(self):
        self.run_lua('''
            local p=makePlayer(); p.items=1; local f=makeFamiliar(p); D.onFamiliarInit(nil,f)
            for i=1,60 do tick(f) end
            local s=f.data.__ConchDragon
            local function noSparks() s.sparks={} end
            noSparks(); spriteLog={}; D.onFamiliarRender(nil,f,Vector(0,0))
            local shadows,order=0,{}
            for _,e in ipairs(spriteLog) do
                if e.anim=='Shadow' then shadows=shadows+1; assert(#order==0, 'shadows first') else order[#order+1]=e.anim end
            end
            assert(shadows==8, 'every other part casts a shadow: '..shadows)
            local want={'Tail','Body','Body','Body','Body','Legs','Body','Body','Body','Body','Body','Body','Legs','Body','Body','Head'}
            assert(table.concat(order,',')==table.concat(want,','), table.concat(order,','))
            -- The body floats above its shadow and thins toward the tail.
            local tail,head=spriteLog[9],spriteLog[#spriteLog]
            assert(tail.scale.X<head.scale.X)
            near(T.partLift(1,0),D.data.flyHeight+D.data.liftWave*math.sin(-D.data.liftStep),1e-9)
            -- The first render after an update shows the last pose, the second is halfway.
            for i=1,#s.segments do s.previous[i]=Vector(0,0); s.segments[i]=Vector(10,20); s.prevAngles[i]=0; s.angles[i]=1; s.flips[i]=false end
            s.renders=0
            noSparks(); spriteLog={}; D.onFamiliarRender(nil,f,Vector(0,0))
            near(spriteLog[#spriteLog].pos.X,0,1e-9)
            spriteLog={}; D.onFamiliarRender(nil,f,Vector(0,0))
            local h=spriteLog[#spriteLog]
            near(h.pos.X,5,1e-9); assert(math.abs(h.rot-math.deg(0.5))<1e-9)
            -- Legs stroke and the tail flutters over time; the plain body holds one frame.
            local seen={}
            for t=0,40 do seen[T.partFrame(3,t)]=true; assert(T.partFrame(2,t)==0) end
            assert(seen[0] and seen[1] and seen[2] and seen[3], 'four leg poses')
            assert(T.partFrame(3,0)~=T.partFrame(9,0), 'the front and hind legs move out of step')
            assert(T.partFrame(14,0)~=T.partFrame(14,D.data.tailFrameTicks), 'tail flutters')
            p.bffs=true; noSparks(); spriteLog={}; D.onFamiliarRender(nil,f,Vector(0,0))
            near(spriteLog[#spriteLog].scale.X,1.25)
            renderMode=1; RenderMode={RENDER_WATER_REFLECT=1}
            spriteLog={}; D.onFamiliarRender(nil,f,Vector(0,0)); assert(#spriteLog==0, 'skips the water reflection pass')
        ''')

    def test_registry_entry_is_a_familiar_without_a_self_synergy(self):
        source = (ROOT / 'scripts/conch_blessing_items.lua').read_text(encoding='utf-8')
        block = source[source.index('    DRAGON = {'):]
        block = block[:block.index('\n    },\n')]
        self.assertIn('type = "familiar"', block)
        self.assertIn('variant = 778', block)
        self.assertIn('cache = "familiars"', block)
        self.assertNotIn('synergies', block)
        self.assertNotIn('weaponFired', block)
        xml = (ROOT / 'content/items.xml').read_text(encoding='utf-8')
        self.assertIn('<familiar id="6" name="Dragon"', xml)
        self.assertIn('cache="familiars"', xml)
        entities = (ROOT / 'content/entities2.xml').read_text(encoding='utf-8')
        self.assertIn('name="Dragon" id="3" variant="778" anm2path="dragon.anm2"', entities)


if __name__ == '__main__':
    unittest.main()
