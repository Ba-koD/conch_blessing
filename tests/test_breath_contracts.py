"""Description/boundary contracts for shipped breath callbacks and weapon tracking.

Lupa provider doubles check Lua dispatch and parameters, not engine HP delivery,
weapon callback frequency, native candle damage decay, or real save/Continue.
"""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class BreathContracts(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(r"""
            local v={}; local mt={__index=v}
            Vector=setmetatable({}, {__call=function(_,x,y) return setmetatable({X=x,Y=y},mt) end})
            mt.__add=function(a,b) return Vector(a.X+b.X,a.Y+b.Y) end
            mt.__sub=function(a,b) return Vector(a.X-b.X,a.Y-b.Y) end
            mt.__mul=function(a,b) if type(a)=='number' then a,b=b,a end return Vector(a.X*b,a.Y*b) end
            function v:Length() return math.sqrt(self.X*self.X+self.Y*self.Y) end
            function v:Normalized() local n=self:Length();return n>0 and self*(1/n) or Vector(0,0) end
            function v:Resized(n) return self:Normalized()*n end
            function v:Distance(other) return (self-other):Length() end
            Vector.Zero=Vector(0,0)
            function Color(r,g,b,a,ro,go,bo) return {R=r,G=g,B=b,A=a} end
            function EntityRef(e) return {Entity=e} end
            EntityType={ENTITY_PLAYER=1,ENTITY_TEAR=2,ENTITY_FAMILIAR=3,ENTITY_EFFECT=1000}
            EntityGridCollisionClass={GRIDCOLL_NONE=0}; EntityFlag={FLAG_ICE=64}
            EffectVariant={RED_CANDLE_FLAME=52,BLUE_FLAME=10}; SoundEffect={SOUND_FLAMETHROWER_END=1}
            GridEntityType={GRID_TNT=12,GRID_FIREPLACE=13,GRID_POOP=14}
            spawned={};targets={};sounds=0;frame=0;roll=.5; roomEnabled=false
            math.random=function(a,b) if a then return a end return roll end
            function SFXManager() return {Play=function() sounds=sounds+1 end} end
            function makeEntity(t,pos,velocity,owner)
                local e={Type=t,Position=pos or Vector(0,0),Velocity=velocity or Vector(0,0),
                    SpawnerEntity=owner,Data={},removed=false,colors={}}
                function e:GetData() return self.Data end
                function e:ToPlayer() return nil end
                function e:ToNPC() return nil end
                function e:ToEffect() if self.Type==1000 and not spawnFailure then return self end end
                function e:SetTimeout(n) self.Timeout=n end
                function e:Remove() self.removed=true end
                function e:Exists() return not self.removed end
                function e:SetColor(c) self.colors[#self.colors+1]=c end
                function e:GetSprite() if spriteMissing then return nil end return {Load=function(_,path) e.loadedSprite=path end,
                    Play=function(_,anim) e.animation=anim end} end
                return e
            end
            function makePlayer()
                local p=makeEntity(1,Vector(100,100));p.inventory={[1]=1,[2]=1}
                p.Luck=14;p.MaxFireDelay=10;p.Damage=10;p.ShotSpeed=1;p.TearRange=260
                p.input=Vector(1,0)
                function p:ToPlayer() return self end
                function p:HasCollectible(id) return self:GetCollectibleNum(id)>0 end
                function p:GetCollectibleNum(id) return self.inventory[id] or 0 end
                function p:GetShootingInput() return self.input end
                return p
            end
            p=makePlayer();q=makePlayer()
            Isaac={GetItemIdByName=function(name) return name=='Fire Breath' and 1 or 2 end,
                GetRoomEntities=function() return targets end,GetPlayer=function() return p end,
                Spawn=function(t,variant,sub,pos,velocity,owner)
                    local e=makeEntity(t,pos,velocity,owner);e.Variant=variant
                    spawned[#spawned+1]=e;return e
                end,
                Explode=function() explosions=(explosions or 0)+1 end}
            gridCalls={};gridMap={};gridSize=0
            room={GetGridWidth=function() return 3 end,GetGridSize=function() return gridSize end,
                GetGridIndex=function() return 4 end,GetGridPosition=function() return Vector(110,100) end,
                GetGridEntity=function(_,i) return gridMap[i] end,
                DestroyGrid=function(_,i,tnt) gridCalls[#gridCalls+1]={i=i,tnt=tnt};if destroyThrows then error('unsupported') end end,
                RemoveGridEntity=function(_,i) gridMap[i]=nil;removedGrid=i end}
            function Game() return {GetFrameCount=function() return frame end,
                GetRoom=function() return roomEnabled and room or nil end} end
            function target(distance,vulnerable)
                local n=makeEntity(100,Vector(110+distance,100));n.damage={};n.status={};n.flags=0
                function n:ToNPC() return self end
                function n:IsVulnerableEnemy() return vulnerable~=false end
                function n:TakeDamage(amount,flags,source) self.damage[#self.damage+1]={amount=amount,source=source.Entity} end
                function n:AddBurn(source,time,amount) self.status[#self.status+1]={kind='burn',source=source.Entity,time=time,amount=amount} end
                function n:AddFreeze(source,time) self.status[#self.status+1]={kind='freeze',source=source.Entity,time=time} end
                function n:AddEntityFlags(flags) self.flags=self.flags|flags end
                return n
            end
            ConchBlessing={}
            W=require('scripts.lib.weapon_attack_tracker')
            Fire=require('scripts.items.collectibles.fire_breath')
            Ice=require('scripts.items.collectibles.ice_breath')
            specs={{module=Fire,id=1,key='__ConchFireBreath',coef=.3,chance='burnChance',time=120,kind='burn'},
                   {module=Ice,id=2,key='__ConchIceBreath',coef=.2,chance='freezeChance',time=60,kind='freeze'}}
            function reset(spec)
                p=makePlayer();q=makePlayer();spawned={};targets={};sounds=0;roll=.5;spawnFailure=false;spriteMissing=false
                spec.module.data.projectileMode='tear_flame'
            end
            function trigger(spec,owner,amount,dir,weapon)
                spec.module.onWeaponFired(nil,dir or Vector(1,0),amount or 1,owner or p,weapon)
            end
            function almost(a,b) assert(math.abs(a-b)<.000001,tostring(a)..' ~= '..tostring(b)) end
        """)

    def test_luck_changes_attack_interval_at_before_boundary_and_repetition(self):
        self.lua.execute(r"""
            for _,s in ipairs(specs) do
                for _,row in ipairs({{-5,20},{0,15},{13,2},{14,1},{15,1},{20,1}}) do
                    reset(s);p.Luck=row[1]
                    for i=1,row[2]-1 do trigger(s);assert(#spawned==0) end
                    trigger(s);assert(#spawned==2 and p.Data[s.key].attackCount==0)
                    for i=1,row[2]-1 do trigger(s);assert(#spawned==2) end
                    trigger(s);assert(#spawned==4)
                end
            end
        """)

    def test_fire_rate_count_boundaries_do_not_multiply_the_attack_counter(self):
        self.lua.execute(r"""
            for _,s in ipairs(specs) do
                for _,row in ipairs({{100,1},{29,1},{14,2},{9,3},{1,15},{.5,20},{0,30},{-1,30},{-10,30}}) do
                    reset(s);p.MaxFireDelay=row[1];trigger(s,p,50)
                    assert(#spawned==row[2],tostring(row[1])..': '..#spawned)
                    assert(sounds==1 and p.Data[s.key].attackCount==0)
                end
                reset(s);p.MaxFireDelay=nil;trigger(s);assert(#spawned==2)
            end
        """)

    def test_copies_scale_each_flame_damage_and_partial_final_removal_reset_counter(self):
        self.lua.execute(r"""
            for _,s in ipairs(specs) do
                reset(s)
                for _,copies in ipairs({1,3,2,1}) do
                    p.inventory[s.id]=copies;spawned={};trigger(s)
                    assert(#spawned==2);for _,e in ipairs(spawned) do almost(e.CollisionDamage,10*s.coef*copies) end
                end
                p.Luck=0;trigger(s);trigger(s);assert(p.Data[s.key].attackCount==2)
                p.inventory[s.id]=0;s.module.onPlayerUpdate(nil,p);trigger(s)
                assert(p.Data[s.key].attackCount==0)
                p.inventory[s.id]=1;spawned={}
                for _=1,14 do trigger(s);assert(#spawned==0) end
                trigger(s);assert(#spawned==2)
            end
        """)

    def test_damage_speed_and_range_inputs_increase_then_decrease_independently(self):
        self.lua.execute(r"""
            for _,s in ipairs(specs) do
                reset(s)
                for _,damage in ipairs({3.5,20,1}) do
                    spawned={};p.Damage=damage;trigger(s);almost(spawned[1].CollisionDamage,damage*s.coef)
                end
                for _,row in ipairs({{.1,.7},{1,1},{10,1.6},{.5,.7}}) do
                    spawned={};p.ShotSpeed=row[1];trigger(s);almost(spawned[1].Velocity:Length(),15*row[2])
                end
                -- Default flames intentionally delegate lifetime/range to the native effect.
                for _,range in ipairs({0,80,260,900,40}) do
                    spawned={};p.TearRange=range;trigger(s)
                    assert(spawned[1].Data[s.key].lifeLeft==nil and spawned[1].Timeout==30)
                end
                s.module.data.projectileMode='entity_effect';p.ShotSpeed=1
                for _,row in ipairs({{0,80},{80,80},{260,260},{900,900},{40,80}}) do
                    spawned={};p.TearRange=row[1];trigger(s);local d=spawned[1].Data[s.key]
                    assert(d.maxDistance==row[2] and d.maxLife==math.ceil(row[2]/10)+30)
                end
            end
        """)

    def test_stat_change_mid_counter_uses_current_luck_without_double_burst(self):
        self.lua.execute(r"""
            for _,s in ipairs(specs) do
                reset(s);p.Luck=0;for _=1,5 do trigger(s) end;assert(#spawned==0)
                p.Luck=14;trigger(s);assert(#spawned==2 and p.Data[s.key].attackCount==0)
                p.Luck=0;for _=1,14 do trigger(s);assert(#spawned==2) end
                trigger(s);assert(#spawned==4)
            end
        """)

    def test_direct_player_ownership_coop_and_emitted_effects_never_recurse(self):
        self.lua.execute(r"""
            for _,s in ipairs(specs) do
                reset(s);p.Luck=13;q.Luck=13
                s.module.onWeaponFired(nil,Vector(1,0),100,nil,nil)
                s.module.onWeaponFired(nil,Vector(1,0),100,{},nil)
                local familiar=makeEntity(3,Vector.Zero,Vector.Zero,p);familiar.Player=p
                trigger(s,familiar);assert(#spawned==0 and p.Data[s.key]==nil)
                trigger(s,p,100);trigger(s,q,100);assert(#spawned==0)
                trigger(s,p);assert(#spawned==2 and q.Data[s.key].attackCount==1)
                local emitted=spawned[1];trigger(s,emitted,100)
                assert(#spawned==2 and p.Data[s.key].attackCount==0)
                trigger(s,q);assert(#spawned==4)
            end
        """)

    def test_missing_direction_does_not_count_and_weapon_or_input_fallback_normalizes(self):
        self.lua.execute(r"""
            for _,s in ipairs(specs) do
                reset(s);p.input=Vector.Zero
                s.module.onWeaponFired(nil,nil,1,p,nil);assert(p.Data[s.key]==nil and #spawned==0)
                s.module.onWeaponFired(nil,Vector.Zero,1,p,{GetDirection=function() return Vector(0,7) end})
                almost(spawned[1].Velocity.X,0);assert(spawned[1].Velocity.Y>0)
                spawned={};p.input=Vector(-7,0);s.module.onWeaponFired(nil,nil,1,p,nil)
                assert(spawned[1].Velocity.X<0);almost(spawned[1].Velocity.Y,0)
                spawned={};s.module.onWeaponFired(nil,Vector(0,-2),1,p,{GetDirection=function() error('wrong fallback') end})
                assert(spawned[1].Velocity.Y<0)
            end
        """)

    def test_spawn_failure_optional_sprite_and_unknown_mode_are_safe(self):
        self.lua.execute(r"""
            for _,s in ipairs(specs) do
                reset(s);spawnFailure=true;trigger(s);assert(sounds==1 and spawned[1].Data[s.key]==nil)
                spawnFailure=false;s.module.data.projectileMode='unknown';spawned={};trigger(s)
                assert(spawned[1].Data[s.key].projectileMode=='entity_flame')
                s.module.data.projectileMode='entity_effect';spawned={};trigger(s)
                assert(spawned[1].loadedSprite=='gfx/effects/flame.anm2' and spawned[1].animation=='Idle')
                spawned={};spriteMissing=true;trigger(s)
                assert(#spawned==2 and spawned[1].Data[s.key] and spawned[1].loadedSprite==nil)
            end
        """)

    def test_effect_and_tear_callbacks_ignore_nil_unrelated_and_non_enemy_inputs(self):
        self.lua.execute(r"""
            for _,s in ipairs(specs) do
                reset(s);local unrelated=makeEntity(1000)
                s.module.onPlayerUpdate(nil,nil);s.module.onEffectUpdate(nil,nil);s.module.onTearUpdate(nil,nil)
                s.module.onEffectUpdate(nil,unrelated);s.module.onTearUpdate(nil,unrelated)
                assert(s.module.onTearCollision(nil,nil,unrelated)==nil)
                assert(s.module.onTearCollision(nil,unrelated,nil)==nil)
                trigger(s);local flame=spawned[1];local ally=target(0,false);local object=makeEntity(6)
                s.module.onTearCollision(nil,flame,object);s.module.onTearCollision(nil,flame,ally)
                assert(#ally.status==0 and #unrelated.colors==0 and not unrelated.removed)
            end
        """)

    def test_status_probabilities_use_strict_boundary_source_and_duration(self):
        self.lua.execute(r"""
            for _,s in ipairs(specs) do
                for _,luck in ipairs({-5,0,1,13,20,100,200}) do
                    for _,atBoundary in ipairs({false,true}) do
                        reset(s);p.Luck=luck
                        for _=1,math.max(1,math.floor(15-luck)) do trigger(s) end
                        local flame=spawned[1]
                        local expected=math.min(1,math.max(0,luck*(s.id==1 and .05 or .01)))
                        -- Check both the helper boundary and its actual emitted snapshot.
                        local f=s.id==1 and s.module._test.getBurnChance or s.module._test.getFreezeChance
                        almost(f({Luck=luck}),expected);almost(f(nil),0)
                        almost(flame.Data[s.key][s.chance],expected)
                        roll=atBoundary and expected or math.max(0,expected-.00001)
                        local npc=target(0);s.module.onTearCollision(nil,flame,npc)
                        local hit=expected>0 and not atBoundary
                        assert(#npc.status==(hit and 1 or 0))
                        assert(#npc.damage==0,'collision callback must not duplicate native damage')
                        if hit then
                            assert(npc.status[1].kind==s.kind and npc.status[1].source==p and npc.status[1].time==s.time)
                            if s.id==1 then almost(npc.status[1].amount,flame.CollisionDamage*.5) else assert(npc.flags==64) end
                        end
                    end
                end
            end
        """)

    def test_effect_damage_dispatch_is_mode_specific_bounded_and_cannot_trigger_more_bursts(self):
        self.lua.execute(r"""
            for _,s in ipairs(specs) do
                for _,mode in ipairs({'tear_flame','entity_flame','entity_effect'}) do
                    reset(s);s.module.data.projectileMode=mode;p.Luck=100;trigger(s);local flame=spawned[1]
                    local near=target(29.9);local edge=target(30);local ally=target(0,false)
                    targets={near,edge,ally,makeEntity(6)};roll=0
                    s.module.onEffectUpdate(nil,flame)
                    assert(#near.damage==(mode=='entity_effect' and 1 or 0))
                    assert(#near.status==1 and #edge.status==0 and #edge.damage==0 and #ally.status==0)
                    if mode=='entity_effect' then almost(near.damage[1].amount,10*s.coef);assert(near.damage[1].source==flame) end
                    assert(#spawned==2 and p.Data[s.key].attackCount==0)
                end
            end
        """)

    def test_custom_motion_lifetime_range_clamp_drag_fade_and_scale_boundaries(self):
        self.lua.execute(r"""
            for _,s in ipairs(specs) do
                reset(s);s.module.data.projectileMode='entity_effect';p.TearRange=80;trigger(s)
                local flame=spawned[1];local d=flame.Data[s.key]
                flame.Position=d.origin+d.travelDir*40;s.module.onEffectUpdate(nil,flame)
                almost(flame.SpriteScale.X,.775);assert(flame.Velocity:Length()<d.initialSpeed)
                flame.Position=d.origin+d.travelDir*90;s.module.onEffectUpdate(nil,flame)
                assert(d.reachedRange);almost(flame.Position:Distance(d.origin),80);almost(flame.SpriteScale.X,1)
                local speed=flame.Velocity:Length();s.module.onEffectUpdate(nil,flame)
                almost(flame.Velocity:Length(),speed*.88)
                flame.Velocity=Vector(.01,0);s.module.onEffectUpdate(nil,flame);almost(flame.Velocity:Length(),0)
                d.lifeLeft=2;s.module.onEffectUpdate(nil,flame);assert(not flame.removed and d.lifeLeft==1)
                assert(flame.colors[#flame.colors].A>=.2 and flame.colors[#flame.colors].A<=1)
                s.module.onEffectUpdate(nil,flame);assert(flame.removed)
                -- Legacy tagged tear motion also has bounded expiry; no emitted weapon recursion.
                trigger(s);local tear=spawned[#spawned];tear.Type=2;local td=tear.Data[s.key]
                tear.Position=td.origin+td.travelDir*40;s.module.onTearUpdate(nil,tear);almost(tear.Scale,.775)
                td.lifeLeft=1;s.module.onTearUpdate(nil,tear);assert(tear.removed)
            end
        """)

    def test_projectiles_keep_their_spawn_snapshot_after_owner_stats_or_item_change(self):
        self.lua.execute(r"""
            for _,s in ipairs(specs) do
                reset(s);p.Luck=100;s.module.data.projectileMode='entity_effect';trigger(s)
                local flame=spawned[1];local d=flame.Data[s.key];local original=d.baseDamage
                p.Damage=100;p.Luck=0;p.inventory[s.id]=0;s.module.onPlayerUpdate(nil,p)
                targets={target(0)};roll=0;s.module.onEffectUpdate(nil,flame)
                almost(targets[1].damage[1].amount,original);assert(#targets[1].status==1)
                assert(p.Data[s.key].attackCount==0 and #spawned==2)
            end
        """)

    def test_optional_stats_status_flag_and_legacy_partial_effect_data(self):
        self.lua.execute(r"""
            for _,s in ipairs(specs) do
                reset(s);s.module.data.projectileMode='entity_effect'
                p.Damage=nil;p.ShotSpeed=nil;p.TearRange=nil;p.MaxFireDelay=nil
                trigger(s);local flame=spawned[1];local d=flame.Data[s.key]
                almost(flame.CollisionDamage,s.coef);assert(d.maxDistance==260 and #spawned==2)
                d.source=nil;d[s.chance]=1;d.origin=nil;d.maxDistance=nil;d.maxLife=0
                d.startScale=nil;d.endScale=nil;EntityFlag=nil;targets={target(0)};roll=0
                s.module.onEffectUpdate(nil,flame)
                assert(targets[1].status[1].source==flame and targets[1].damage[1].source==flame)
                assert(targets[1].flags==0 and not flame.removed)
                EntityFlag={FLAG_ICE=64}
                spawned={};p.Damage=0;trigger(s);almost(spawned[1].CollisionDamage,0)
            end
        """)

    def test_missing_room_grid_apis_or_failed_destruction_do_not_break_projectile_update(self):
        self.lua.execute(r"""
            for _,s in ipairs(specs) do
                reset(s);roomEnabled=true;gridSize=0;trigger(s);local flame=spawned[1]
                s.module.onEffectUpdate(nil,flame);assert(not flame.removed)
                gridSize=9;gridMap={[4]={GetType=function() return 14 end}}
                local destroy,remove=room.DestroyGrid,room.RemoveGridEntity
                room.DestroyGrid=nil;room.RemoveGridEntity=nil
                s.module.onEffectUpdate(nil,flame);assert(gridMap[4] and not flame.removed)
                room.DestroyGrid=function() error('unavailable') end
                room.RemoveGridEntity=function() error('unavailable') end
                s.module.onEffectUpdate(nil,flame);assert(gridMap[4] and not flame.removed)
                room.DestroyGrid=destroy;room.RemoveGridEntity=remove;roomEnabled=false;gridSize=0
            end
        """)

    def test_grid_targets_filter_tnt_fallback_and_repeat_cooldown(self):
        self.lua.execute(r"""
            for _,s in ipairs(specs) do
                reset(s);roomEnabled=true;gridSize=9;frame=0;gridMap={};gridCalls={};destroyThrows=false
                trigger(s);local flame=spawned[1]
                gridMap[3]={GetType=function() return 1 end}
                gridMap[4]={GetType=function() return 14 end}
                s.module.onEffectUpdate(nil,flame);assert(#gridCalls==1 and gridCalls[1].i==4)
                frame=2;s.module.onEffectUpdate(nil,flame);assert(#gridCalls==1)
                frame=3;s.module.onEffectUpdate(nil,flame);assert(#gridCalls==2)
                gridMap[4]={GetType=function() return 12 end};frame=6;explosions=0;removedGrid=nil
                s.module.onEffectUpdate(nil,flame);assert(explosions==1 and removedGrid==4 and gridMap[3])
                frame=9;gridMap[4]={GetType=function() return 13 end};destroyThrows=true;removedGrid=nil
                s.module.onEffectUpdate(nil,flame);assert(removedGrid==4)
                roomEnabled=false;gridSize=0;destroyThrows=false
            end
        """)

    def test_tracker_bad_states_fractional_thresholds_custom_keys_and_reset(self):
        self.lua.execute(r"""
            for _,bad in ipairs({false,0,'bad'}) do local hit,n=W.advance(bad,2);assert(not hit and n==0);W.reset(bad) end
            local hit,n=W.advance(nil,2);assert(not hit and n==0);W.reset(nil)
            local state={attackCount=-2,other=99}
            hit,n=W.advance(state,2.9);assert(not hit and n==1)
            hit,n=W.advance(state,'2');assert(hit and n==0 and state.other==99)
            hit,n=W.advance(state,0);assert(hit and n==0)
            state.alt='3.9';hit,n=W.advance(state,5,'alt');assert(not hit and n==4)
            W.reset(state,'alt');assert(state.alt==0 and state.other==99)
            state.attackCount='corrupt';hit,n=W.advance(state,2);assert(not hit and n==1)
        """)

    def test_native_flame_damage_snapshot_survives_engine_decay_and_owner_changes(self):
        self.lua.execute(r"""
            for _,s in ipairs(specs) do
                reset(s);p.inventory[s.id]=2;trigger(s);local flame=spawned[1]
                local expected=10*s.coef*2
                p.Damage=99;p.inventory[s.id]=0
                for _,decayed in ipairs({expected*.9,expected*.2,0}) do
                    flame.CollisionDamage=decayed;s.module.onEffectUpdate(nil,flame)
                    almost(flame.CollisionDamage,expected)
                end
                local unrelated=makeEntity(1000);unrelated.CollisionDamage=123
                s.module.onEffectUpdate(nil,unrelated);almost(unrelated.CollisionDamage,123)
            end
        """)

    def test_status_requires_accepted_damage_with_provider_and_ignores_proximity_or_cancellation(self):
        self.lua.execute(r"""
            REPENTOGON={Real=true};ModCallbacks={MC_POST_ENTITY_TAKE_DMG=1006}
            for _,s in ipairs(specs) do
                reset(s);p.Luck=100;roll=0;trigger(s);local flame=spawned[1]
                local npc=target(0);targets={npc}
                s.module.onEffectUpdate(nil,flame);s.module.onTearCollision(nil,flame,npc)
                assert(#npc.status==0,'proximity or attempted collision rerolled an on-hit status')
                s.module.onPostEntityTakeDamage(nil,npc,0,0,EntityRef(flame),0)
                -- Players hold this same namespace for their attack counter.
                -- A player-sourced hit/burn tick is never the physical flame.
                p.Data[s.key].baseDamage=99;p.Data[s.key][s.chance]=1
                s.module.onPostEntityTakeDamage(nil,npc,2,0,EntityRef(p),0)
                s.module.onPostEntityTakeDamage(nil,npc,2,0,EntityRef(makeEntity(1000)),0)
                assert(#npc.status==0,'zero/rejected or unrelated hit applied status')
                s.module.onPostEntityTakeDamage(nil,npc,2,0,EntityRef(p),0,EntityRef(flame))
                assert(#npc.status==1 and npc.status[1].time==s.time and npc.status[1].source==p)
                s.module.onEffectUpdate(nil,flame);s.module.onTearCollision(nil,flame,npc)
                assert(#npc.status==1,'status duration extended without another accepted hit')
                s.module.onPostEntityTakeDamage(nil,npc,2,0,EntityRef(flame),0)
                assert(#npc.status==2,'a later real damage tick must remain eligible')
            end
        """)

    def test_ice_native_hit_corrects_decay_without_rehitting_or_erasing_earlier_scaling(self):
        self.lua.execute(r"""
            REPENTOGON={Real=true};ModCallbacks={MC_POST_ENTITY_TAKE_DMG=1006}
            local s=specs[2];reset(s);trigger(s);local flame=spawned[1]
            local npc=target(0);local expected=flame.Data[s.key].baseDamage
            p.Damage=99;p.inventory[s.id]=0
            for _,factor in ipairs({.9,.2,1}) do
                flame.CollisionDamage=expected*factor
                local result=Ice.onEntityTakeDamage(nil,npc,flame.CollisionDamage*2,0,EntityRef(flame),0)
                if factor==1 then assert(result==nil) else almost(result.Damage,expected*2) end
                assert(#npc.damage==0 and #npc.status==0,'attempted damage must not cause a second hit or status')
            end
            flame.CollisionDamage=expected*.9
            assert(Ice.onEntityTakeDamage(nil,npc,0,0,EntityRef(flame),0)==nil)
            assert(Ice.onEntityTakeDamage(nil,p,1,0,EntityRef(flame),0)==nil)
            flame.Data[s.key].projectileMode='entity_effect'
            assert(Ice.onEntityTakeDamage(nil,npc,1,0,EntityRef(flame),0)==nil)
            flame.Data[s.key].projectileMode='entity_flame'
            REPENTOGON=nil
            assert(Ice.onEntityTakeDamage(nil,npc,1,0,EntityRef(flame),0)==nil)
        """)

if __name__=='__main__': unittest.main()
