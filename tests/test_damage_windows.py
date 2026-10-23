"""HP-window fixtures for the dragon and breath benches.

The engine double commits each hit's HP one update later (deferred HP) in
float32, as measured on 2026-10-23. These tests prove the benches' window
edges and isolation, not Isaac's damage itself.
"""
import unittest
import test_weapon_observer as weapon


class DamageWindows(unittest.TestCase):
    run_lua = weapon.WeaponObserverTests.run_lua

    def setUp(self):
        weapon.WeaponObserverTests.setUp(self)
        self.run_lua('''
            EntityType.ENTITY_FAMILIAR=3
            EntityCollisionClass={ENTCOLL_NONE=0,ENTCOLL_ALL=4}
            EntityFlag={FLAG_NO_TARGET=2,FLAG_NO_STATUS_EFFECTS=1}
            CollectibleType=CollectibleType or {}; CollectibleType.COLLECTIBLE_BFFS=247
            local V={}
            V.__index=V
            V.__add=function(a,b) return setmetatable({X=a.X+b.X,Y=a.Y+b.Y},V) end
            Vector=setmetatable({},{__call=function(_,x,y) return setmetatable({X=x,Y=y},V) end})
            Vector.Zero=Vector(0,0)
            Game=function() return {GetFrameCount=function() return frame end,
                GetRoom=function() return {GetCenterPos=function() return Vector(320,280) end} end} end
            function f32(x) return (string.unpack('f',string.pack('f',x))) end
            player.Type=1; player.Damage=3.5; player.MaxFireDelay=10; player.Position=Vector(0,0)
            player.HasCollectible=function() return false end
            targets={}
            H.target=function()
                local t=entity(100+#targets,18); t.EntityCollisionClass=4; t.HitPoints=100000
                t.Position=Vector(0,0); t.Velocity=Vector(0,0)
                targets[#targets+1]=t
                return t
            end
            H.targetReady=function(t) return t:Exists() end
            -- Runs a stage like the bench: acts and checks continue in one update,
            -- a wait ends it. The engine hits first in each update (entity phase).
            function runStage(stage,n,engine)
                local ops={}
                local plan={}
                function plan.act(fn) ops[#ops+1]={kind='act',fn=fn} end
                function plan.check(label,fn) ops[#ops+1]={kind='check',label=label,fn=fn} end
                function plan.waitUntil(fn,timeout,label) ops[#ops+1]={kind='until',fn=fn,n=timeout,label=label} end
                function plan.section() end
                function plan.note() end
                function plan.require() end
                stage(plan,7,n)
                local ctx,results,i,left={}, {}, 1
                for _=1,5000 do
                    frame=frame+1; engine()
                    while i<=#ops do
                        local op=ops[i]
                        if op.kind=='until' then
                            local done,why=op.fn(player,ctx)
                            left=(left or op.n)-1
                            if done then left=nil; i=i+1
                            elseif left<=0 then return results,op.label..': '..tostring(why) end
                            break
                        elseif op.kind=='act' then op.fn(player,ctx); i=i+1
                        else
                            local ok,pass,detail=pcall(op.fn,player,ctx)
                            results[op.label]={pass=ok and pass==true,detail=tostring(ok and detail or pass)}
                            i=i+1
                        end
                    end
                    if i>#ops then return results end
                end
                error('stage never finished')
            end
            pending={}
            -- Deferred, float32 HP: a hit dispatched in one update lands in HP the next.
            function hit(target,amount,source)
                amount=f32(amount)
                dispatch(41,target,amount,0,{Entity=source},0,nil)
                pending[#pending+1]={target=target,amount=amount}
            end
            function commit(scale)
                for _,p in ipairs(pending) do p.target.HitPoints=f32(p.target.HitPoints-p.amount*(scale or 1)) end
                pending={}
            end
        ''')

    def azure(self, scale=1, hit_intangible=False):
        self.lua.globals().lossScale = scale
        self.lua.globals().hitIntangible = hit_intangible
        self.run_lua('''
            C=require('scripts.dev.item_test_combat')
            ConchBlessing.ItemData.AZURE_DRAGON={entity={variant=778}}
            ConchBlessing.azureDragon={data={lightningDamageMultiplier=0.55},
                _test={strikeCooldownFor=function() return 55 end,partCountFor=function() return 1 end}}
            dragon=entity(50,3,player); dragon.Variant=778; dragon.Player=player
            dragon.ToFamiliar=function(self) return self end
            dragon.data.__ConchDragon={segments={}}
            for k=1,6 do dragon.data.__ConchDragon.segments[k]=Vector(k,k) end
            Isaac.FindByType=function(kind,variant) return kind==3 and variant==778 and {dragon} or {} end
            local age={}
            results,timedOut=runStage(C.AZURE_DRAGON.stage,1,function()
                commit(lossScale)
                for index,t in ipairs(targets) do
                    if t:Exists() and (t.EntityCollisionClass==4 or hitIntangible) then
                        -- Body contact every update, lightning every 55 per enemy.
                        hit(t,0.175,dragon)
                        age[t]=(age[t] or 0)+1
                        if age[t]%55==index then hit(t,1.925,dragon) end
                    end
                end
            end)
        ''')

    def test_azure_windows_match_settled_float32_hp_with_deferred_commits(self):
        self.azure()
        self.run_lua('''
            assert(timedOut==nil,timedOut)
            for _,label in ipairs({'every enemy the snout runs into is struck for 55% of the current damage',
                    'a dragon strikes the same enemy at most once every 5 / tears seconds',
                    'contact deals 5% of current damage every tick'}) do
                assert(results[label] and results[label].pass,label..': '..tostring(results[label] and results[label].detail))
            end
            assert(results['contact deals 5% of current damage every tick'].detail:find('contact hits=40',1,true))
            for _,t in ipairs(targets) do assert(not t:Exists(),'target leaked') end
        ''')

    def test_azure_hp_trimmed_after_the_applied_callback_is_caught(self):
        self.azure(scale=0.99)
        self.run_lua('''
            assert(timedOut==nil,timedOut)
            assert(not results['every enemy the snout runs into is struck for 55% of the current damage'].pass)
            assert(not results['contact deals 5% of current damage every tick'].pass)
        ''')

    def test_hits_on_intangible_targets_keep_the_window_from_closing(self):
        self.azure(hit_intangible=True)
        self.run_lua('''
            assert(timedOut and timedOut:find('no dragon hit in flight before the HP window',1,true),tostring(timedOut))
        ''')

    def weather(self, scale=1):
        self.lua.globals().lossScale = scale
        self.run_lua('''
            C=require('scripts.dev.item_test_combat')
            ConchBlessing.dragon={data={tearsDivisor=5,twisterMinCopies=2},_sky={bolts=0},_twisters={}}
            local updates=0
            results,timedOut=runStage(C.DRAGON.stage,1,function()
                commit(lossScale)
                local live=false
                for _,t in ipairs(targets) do live=live or t:Exists() and t.EntityCollisionClass==4 end
                if not live then return end
                updates=updates+1
                -- Two twisters stand on the third target; a bolt every 55 updates on the first.
                if targets[3] then hit(targets[3],0.175,player); hit(targets[3],0.175,player) end
                if updates%55==0 then ConchBlessing.dragon._sky.bolts=ConchBlessing.dragon._sky.bolts+1; hit(targets[1],3.5,player) end
            end)
        ''')

    def test_weather_window_waits_for_twister_ticks_in_flight(self):
        self.weather()
        self.run_lua('''
            assert(timedOut==nil,timedOut)
            local r=results['every bolt hits for 1x current damage and HP loss matches']
            assert(r and r.pass,tostring(r and r.detail))
        ''')

    def test_weather_hp_trimmed_after_the_applied_callback_is_caught(self):
        self.weather(scale=0.99)
        self.run_lua('''
            assert(not results['every bolt hits for 1x current damage and HP loss matches'].pass)
        ''')


class BreathIsolation(unittest.TestCase):
    run_lua = weapon.WeaponObserverTests.run_lua

    def setUp(self):
        weapon.WeaponObserverTests.setUp(self)

    def test_foreign_hit_evidence_names_its_source_and_flags(self):
        self.run_lua('''
            local attack=entity(2,1000,player); attack.Variant=52; attack.SubType=0; attack.FrameCount=4
            attack.ToEffect=function(self) return self end
            local target=entity(3,21); local ctx={attack=attack,target=target}
            H.captureDamage(ctx,true)
            dispatch(41,target,1.05,0,{Entity=attack},0,nil)
            local burner=entity(4,1); burner.Variant=0; burner.SubType=0
            dispatch(41,target,0.525,8,{Entity=burner},0,nil)
            local evidence=H.damageEvidence(ctx)
            assert(ctx.hitCapture.foreignHits==1)
            assert(evidence:find('foreign1 amount=0.525 source=1:0:0 flags=8',1,true),evidence)
            dispatch(41,target,0.5,0,{},0,nil)
            assert(H.damageEvidence(ctx):find('foreign2 amount=0.5 source=none',1,true))
        ''')

    def test_status_free_sample_makes_only_its_own_target_status_immune(self):
        self.run_lua('''
            EntityFlag={FLAG_NO_TARGET=2,FLAG_NO_STATUS_EFFECTS=1}
            EntityCollisionClass={ENTCOLL_ALL=4}
            Vector=setmetatable({}, {__call=function() return setmetatable({},
                {__add=function(a) return a end}) end})
            player.Position=Vector()
            local made={}
            H.target=function()
                local t=entity(30+#made,18); t.flags=0
                t.ClearEntityFlags=function(self,f) self.flags=self.flags & ~f end
                t.AddEntityFlags=function(self,f) self.flags=self.flags | f end
                made[#made+1]=t
                return t
            end
            for _,statusFree in ipairs({true,false}) do
                local acts={}
                local plan=setmetatable({act=function(fn) acts[#acts+1]=fn end},
                    {__index=function() return function() end end})
                H.sampleAttackDamage(plan,function() return 1.05 end,function() return entity(9,1000,player) end,
                    {statusFree=statusFree})
                acts[1](player,{})
                assert((made[#made].flags & 1 ~= 0)==statusFree,'status immunity follows the option')
            end
        ''')

    def test_fire_breath_sample_is_status_free_and_ice_breath_keeps_its_freeze(self):
        self.run_lua('''
            local seen={}
            H.sampleAttackDamage=function(_,_,_,options) seen[#seen+1]=options end
            C=require('scripts.dev.item_test_combat')
            ModCallbacks.MC_POST_TRIGGER_WEAPON_FIRED=6
            local plan=setmetatable({},{__index=function() return function() end end})
            C.FIRE_BREATH.stage(plan,7,1)
            assert(seen[1].statusFree==true and not seen[1].blueFlame)
            C.ICE_BREATH.stage(plan,7,1)
            assert(not seen[2].statusFree and seen[2].blueFlame==true)
        ''')


if __name__ == '__main__':
    unittest.main()
