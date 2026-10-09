"""Production SOFLAM + real damage provenance regressions; engine collision remains in-game."""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class SoflamContracts(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root=ROOT.as_posix()
        self.lua.execute(r"""
            package.path=root..'/?.lua;'..package.path
            ModCallbacks={MC_POST_TEAR_INIT=1,MC_POST_BOMB_INIT=2,MC_POST_LASER_INIT=3,
                MC_POST_ENTITY_TAKE_DMG=4,MC_POST_TRIGGER_WEAPON_FIRED=5,MC_POST_EFFECT_INIT=6}
            REPENTOGON={Real=true}; CacheFlag={CACHE_WEAPON=64}
            WeaponType={WEAPON_TEARS=1,WEAPON_LASER=2}; CollectibleType={COLLECTIBLE_MR_MEGA=106}
            EntityType={ENTITY_PLAYER=1,ENTITY_TEAR=2,ENTITY_LASER=7,ENTITY_BOMB=4,ENTITY_EFFECT=1000}
            EffectVariant={TARGET=30,ROCKET=31}; EntityFlag={FLAG_FRIENDLY=1}
            DamageFlag={DAMAGE_EXPLOSION=4}; SoundEffect={SOUND_BIRD_FLAP=1}; Color={Default={}}
            Vector=setmetatable({},{__call=function(_,x,y) return {X=x,Y=y} end}); Vector.Zero=Vector(0,0)
            serial=0; entities={}; bombs={}; explosions={}; callbacks={}; errors={}; room=5
            ConchBlessing={AddCallback=function(_,id,fn) callbacks[id]=fn end,
                printError=function(e) errors[#errors+1]=e end}
            function entity(kind,owner)
                serial=serial+1
                local e={kind=kind,Type=kind,InitSeed=serial,Index=serial,Position=Vector(100,100),
                    data={},removed=false,dead=false,SpawnerEntity=owner,vulnerable=true}
                function e:GetData() return self.data end
                function e:Exists() return not self.removed end
                function e:IsDead() return self.dead end
                function e:Remove() self.removed=true end
                function e:ToNPC() return self.kind==10 and self or nil end
                function e:ToPlayer() return self.kind==1 and self or nil end
                function e:ToFamiliar() return self.kind==3 and self or nil end
                function e:ToKnife() return self.kind==8 and self or nil end
                function e:ToTear() return self.kind==2 and self or nil end
                function e:ToEffect() return self.kind==1000 and self or nil end
                function e:ToBomb() return self.kind==4 and self or nil end
                function e:IsVulnerableEnemy() return self.vulnerable end
                function e:HasEntityFlags(flag) return flag==1 and self.friendly==true end
                function e:SetTimeout(value) self.Timeout=value end
                function e:GetSprite() return {IsFinished=function() return false end,GetFrame=function() return 0 end} end
                return e
            end
            function newPlayer()
                local p=entity(1); p.Luck=18; p.Damage=10; p.items={[77]=1}; p.roll=0.5; p.rolls=0; p.multishot=1
                p.weapon=2; p.enabled={}; p.cacheCount=0
                function p:HasCollectible(id) return (self.items[id] or 0)>0 end
                function p:GetCollectibleNum(id) return self.items[id] or 0 end
                function p:GetCollectibleRNG(id)
                    assert(id==77); return {RandomFloat=function() p.rolls=p.rolls+1; return p.roll end}
                end
                function p:GetWeaponType() return self.weapon end
                function p:GetMultiShotParams(weapon)
                    self.lastQueriedWeapon=weapon; return {GetNumTears=function() return p.multishot end}
                end
                function p:GetBombFlags() return 11 end
                function p:GetBombVariant(flags) assert(flags==11); return 9 end
                function p:EnableWeaponType(id,value) self.enabled[id]=value end
                function p:AddCacheFlags(flag) self.lastCache=flag end
                function p:EvaluateItems() self.cacheCount=self.cacheCount+1 end
                return p
            end
            player=newPlayer(); players={player}; npc=entity(10)
            game={GetNumPlayers=function() return #players end,
                GetLevel=function() return {GetCurrentRoomIndex=function() return room end} end,
                ShakeScreen=function() end,
                BombExplosionEffects=function(_,position,damage,flags,color,owner,scale)
                    explosions[#explosions+1]={position=position,damage=damage,flags=flags,owner=owner,scale=scale,
                        provenance=P.getSnapshot(owner)}
                    if duringExplosion then duringExplosion(owner) end
                end}
            Game=function() return game end
            SFXManager=function() return {Play=function() end} end
            Isaac={GetItemIdByName=function() return 77 end,GetPlayer=function(i) return players[i+1] end,
                Spawn=function(kind,variant,_,position,velocity,owner)
                    local mode=kind==4 and bombMode or visualMode
                    if mode=='throw' then error('spawn unavailable') end
                    if mode=='nil' then return nil end
                    local e=entity(kind,owner); e.Variant=variant; e.Position=Vector(position.X,position.Y)
                    entities[#entities+1]=e
                    if mode=='wrong_cast' then e.ToBomb=function() return nil end; e.ToEffect=function() return nil end end
                    if mode=='missing_cast' then e.ToBomb=false; e.ToEffect=false end
                    if kind==4 then
                        e.ExplosionDamage=100; e.RadiusMultiplier=1.2
                        if mode~='no_countdown' then e.SetExplosionCountdown=function(self,n) self.countdown=n end end
                        bombs[#bombs+1]=e
                    end
                    return e
                end}
            P=require('scripts.lib.damage_provenance')
            S=require('scripts.items.collectibles.soflam')
            function laser(owner) return entity(7,owner or player) end
            function hit(attack,target,source)
                S.onPostEntityTakeDamage(nil,target or npc,1,0,{Entity=source or player},0,{Entity=attack})
            end
            function updates(count) for _=1,count do S.onUpdate() end end
            function finish()
                for _=1,300 do if #S._pendingStrikes==0 then return end; S.onUpdate() end
                error('strike did not settle')
            end
            function near(a,b) assert(math.abs(a-b)<1e-9,tostring(a)..' ~= '..tostring(b)) end
        """)

    def run_lua(self,code):
        self.lua.execute(code)

    def test_chance_boundaries_negative_luck_and_failed_roll_consumes_attack(self):
        self.run_lua("""
            for _,row in ipairs({{-20,0},{-2,0},{-1,0.05},{0,0.1},{1,0.15},{17,0.95},{18,1},{99,1}}) do
                player.Luck=row[1]; near(S._test.getProcChance(player),row[2])
            end
            near(S._test.getProcChance(nil),0.1)
            player.Luck=-2; local a=laser(); hit(a)
            assert(player.rolls==0 and #S._pendingStrikes==0)
            player.Luck=18; hit(a); assert(player.rolls==0,'zero-chance attack rerolled after luck changed')
            player.Luck=0; player.roll=0.9; a=laser(); hit(a); hit(a)
            assert(player.rolls==1 and #S._pendingStrikes==0,'failed continuous laser hit rerolled')
            player.Luck=18; hit(a); assert(player.rolls==1,'same attack claimed more than once')
            hit(laser()); assert(player.rolls==2 and #S._pendingStrikes==1)
            player.roll=0.1; player.Luck=0; hit(laser()); assert(#S._pendingStrikes==2,'inclusive configured threshold drifted')
        """)

    def test_laser_extra_source_owner_lineage_and_recursive_proc_rejection(self):
        self.run_lua("""
            local other=newPlayer(); other.items[77]=0; players[2]=other
            local a=laser(other); hit(a,npc,other); assert(#S._pendingStrikes==0)
            a=laser(); hit(a); hit(a); assert(#S._pendingStrikes==1 and player.rolls==1)
            P.onWeaponFired(nil,0,1,player,{GetMainEntity=function() return a end})
            hit(a); assert(#S._pendingStrikes==1,'weapon callback reopened a live laser')
            local unrelated=laser(); P.markTriggeredAttack(unrelated,'void_dagger',nil,'other_proc')
            hit(unrelated); assert(#S._pendingStrikes==2,'another proc was incorrectly globally blocked')
            local inherited=P.getSnapshot(unrelated)
            local missile=entity(4,player); P.markTriggeredAttack(missile,'soflam',inherited,'soflam_missile')
            local child=entity(7,missile); hit(child)
            assert(#S._pendingStrikes==2,'SOFLAM descendant recursively proc-ed')
            local collapsed=entity(1000,player); P.markTriggeredAttack(collapsed,'soflam',nil,'collapsed')
            hit(laser(),npc,collapsed); assert(#S._pendingStrikes==2,'blocked Source hidden by clean ExtraSource')
            local familiar=entity(3); familiar.Player=player
            hit(entity(7,familiar)); assert(#S._pendingStrikes==3,'familiar laser ownership was lost')
            local cyclic=entity(7); cyclic.Parent=cyclic; cyclic.SpawnerEntity=cyclic
            hit(cyclic,npc,cyclic); assert(#S._pendingStrikes==3,'ownerless cyclic attack accepted')
            local foreign=laser(other); P.beginAttackInstance(foreign,player); hit(foreign,npc,other)
            assert(#S._pendingStrikes==4,'exact attack owner did not override stale source owner')
        """)

    def test_non_damage_friendly_invulnerable_and_missing_item_never_claim(self):
        self.run_lua("""
            local a=laser()
            for _,amount in ipairs({0,-1}) do S.onPostEntityTakeDamage(nil,npc,amount,0,{Entity=player},0,{Entity=a}) end
            npc.friendly=true; hit(a); npc.friendly=false
            npc.vulnerable=false; hit(a); npc.vulnerable=true
            npc.removed=true; hit(a); npc.removed=false
            player.items[77]=0; hit(a); player.items[77]=1
            hit(a); assert(player.rolls==1 and #S._pendingStrikes==1,'ineligible damage consumed a later legitimate roll')
        """)

    def test_current_laser_weapon_multishot_snapshot_and_capability_fallbacks(self):
        self.run_lua("""
            for _,row in ipairs({{0,1},{1,1},{2,2},{3.49,3},{3.5,4},{-2,1}}) do
                player.multishot=row[1]; near(S._test.getRocketCountFromMultishot(player),row[2])
                assert(player.lastQueriedWeapon==2,'multishot queried tear weapon instead of current laser')
            end
            player.multishot=3; hit(laser()); player.multishot=1
            assert(S._pendingStrikes[1].remainingRockets==3,'multishot count was not captured at accepted hit')
            finish(); assert(#bombs==3)
            player.GetMultiShotParams=function() error('old API') end
            assert(S._test.getRocketCountFromMultishot(player)==1)
            player.GetMultiShotParams=function() return {GetNumTears=function() return 'invalid' end} end
            assert(S._test.getRocketCountFromMultishot(player)==1)
            player.GetMultiShotParams=nil; assert(S._test.getRocketCountFromMultishot(player)==1)
            assert(S._test.getRocketCountFromMultishot(nil)==1)
        """)

    def test_missile_damage_tracks_live_damage_mega_stacks_and_radius_boundaries(self):
        self.run_lua("""
            for _,row in ipairs({{0,75},{140,75},{140.01,90},{175,90},{175.01,105}}) do
                near(S._test.getBombRadiusFromDamage(row[1]),row[2])
            end
            for count=0,2 do
                player.items[106]=count; player.Damage=10; hit(laser())
                player.Damage=70 -- live stat change while lock-on is pending
                finish(); local bomb=bombs[#bombs]
                near(bomb.ExplosionDamage,210*2^count)
                near(bomb.RadiusMultiplier,90*(count>0 and 1.5 or 1)/105)
                assert(bomb.Flags==11 and bomb.Variant==9 and bomb.IsFetus and bomb.countdown==0)
                local provenance=P.getSnapshot(bomb)
                assert(provenance.procChain.soflam and provenance.origin=='soflam_missile')
                assert(not P.isHitProcEligible(bomb,'soflam') and P.isHitProcEligible(bomb,'void_dagger'))
                local before=#S._pendingStrikes; hit(bomb); assert(#S._pendingStrikes==before)
            end
        """)

    def test_owner_loss_removed_dead_missing_and_room_change_cancel_visuals(self):
        self.run_lua("""
            for _,mode in ipairs({'loss','removed','dead','missing','room','callback','game_start'}) do
                hit(laser()); updates(45); local strike=S._pendingStrikes[1]
                assert(strike.phase=='rocket' and strike.rocketEffect:Exists())
                local effect=strike.rocketEffect; local previousBombs=#bombs
                if mode=='loss' then player.items[77]=0
                elseif mode=='removed' then player.removed=true
                elseif mode=='dead' then player.dead=true
                elseif mode=='missing' then players={}
                elseif mode=='room' then room=room+1
                elseif mode=='callback' then S.onNewRoom()
                else S.onGameStarted() end
                S.onUpdate(); assert(#S._pendingStrikes==0 and not effect:Exists(),mode..' leaked pending visuals')
                assert(#bombs==previousBombs,mode..' detonated after cancellation')
                player.items[77]=1; player.removed=false; player.dead=false; players={player}
            end
            for _,mode in ipairs({'dead','removed'}) do
                player[mode]=true; hit(laser()); assert(#S._pendingStrikes==0); player[mode]=false
            end
        """)

    def test_dead_or_reused_target_keeps_last_live_position_and_removed_rocket_detonates_once(self):
        self.run_lua("""
            hit(laser()); npc.Position=Vector(180,220); S.onUpdate()
            npc.dead=true; npc.Position=Vector(999,999); updates(44)
            local strike=S._pendingStrikes[1]; strike.rocketEffect:Remove()
            S.onUpdate(); assert(#bombs==1 and #S._pendingStrikes==0)
            assert(bombs[1].Position.X==180 and bombs[1].Position.Y==220,'dead target position was still tracked')
            updates(10); assert(#bombs==1,'removed visual caused repeated detonation')
            npc.dead=false; npc.Position=Vector(5,6); hit(laser()); npc.InitSeed=npc.InitSeed+1
            npc.Position=Vector(99,99); finish()
            assert(bombs[2].Position.X==5 and bombs[2].Position.Y==6,'recycled NPC pointer stole the target')
        """)

    def test_missing_visual_spawn_and_bomb_spawn_use_exact_once_scoped_fallback(self):
        self.run_lua("""
            player.Damage=70; player.items[106]=2
            for _,mode in ipairs({'nil','throw','wrong_cast','missing_cast'}) do
                visualMode=mode; bombMode=mode
                local before=#explosions; hit(laser()); finish()
                assert(#explosions==before+1,mode..' failed to detonate exactly once')
                local e=explosions[#explosions]
                near(e.damage,840); near(e.scale,112.5/105)
                assert(e.flags==11 and e.provenance.procChain.soflam)
                assert(P.get(player)==nil,'scoped fallback provenance leaked onto player')
            end
            assert(#errors>0,'real spawn exception was hidden')
            for _,e in ipairs(entities) do
                if e.kind==1000 then assert(not e:Exists(),'failed effect conversion left a visual behind') end
            end
        """)

    def test_missing_countdown_fallback_preserves_radius_lineage_and_cleans_on_error(self):
        self.run_lua("""
            bombMode='no_countdown'; player.items[106]=1; player.Damage=70
            local inherited=laser(); P.markTriggeredAttack(inherited,'void_dagger',nil,'other')
            hit(inherited); finish(); assert(#explosions==1 and not bombs[1]:Exists())
            near(explosions[1].damage,420); near(explosions[1].scale,135/105)
            assert(explosions[1].provenance.procChain.soflam and explosions[1].provenance.procChain.void_dagger)
            duringExplosion=function(owner)
                assert(not P.isHitProcEligible(owner,'soflam'))
                hit(laser(owner),npc,owner)
            end
            hit(laser()); finish(); assert(#explosions==2 and #S._pendingStrikes==0,'fallback recursively proc-ed')
            duringExplosion=function() error('engine explosion failed') end
            hit(laser()); updates(45)
            assert(not pcall(S.onUpdate))
            assert(P.get(player)==nil,'exception leaked scoped proc marker')
        """)

    def test_optional_bomb_apis_old_signatures_and_count_fallbacks_preserve_damage(self):
        self.run_lua("""
            player.Damage=10; player.items[106]=1
            player.GetCollectibleNum=function(_,id,onlyTrue)
                if onlyTrue~=nil then error('older count signature') end
                assert(id==106); return 2.9
            end
            player.GetBombFlags=function(_,withSynergies)
                if withSynergies~=nil then error('older flags signature') end
                return 19
            end
            player.GetBombVariant=function() error('variant unavailable') end
            hit(laser()); finish(); local b=bombs[#bombs]
            near(b.ExplosionDamage,120); assert(b.Flags==19 and b.Variant==0)
            player.GetCollectibleNum=function() error('enumeration unavailable') end
            player.GetBombFlags=nil; player.TearFlags=23
            hit(laser()); finish(); b=bombs[#bombs]
            near(b.ExplosionDamage,60); assert(b.Flags==23)
            player.GetCollectibleNum=function() return -9 end
            hit(laser()); finish(); near(bombs[#bombs].ExplosionDamage,30)
            player.GetCollectibleNum=function() return 'invalid' end
            player.items[106]=0; player.TearFlags=nil
            hit(laser()); finish(); b=bombs[#bombs]
            near(b.ExplosionDamage,30); assert(b.Flags==0)
        """)

    def test_multishot_weapon_query_failures_and_bitset_flags_are_guarded(self):
        self.run_lua("""
            player.GetWeaponType=function() error('weapon unavailable') end
            player.multishot=2
            assert(S._test.getRocketCountFromMultishot(player)==2 and player.lastQueriedWeapon==1)
            player.GetMultiShotParams=function() return {} end
            assert(S._test.getRocketCountFromMultishot(player)==1)
            player.GetMultiShotParams=function() return {GetNumTears=function() error('count unavailable') end} end
            assert(S._test.getRocketCountFromMultishot(player)==1)
            BitSet128=setmetatable({},{__call=function(_,lo,hi) return {lo=lo,hi=hi} end})
            player.GetBombVariant=function(_,flags) assert(flags.lo==11 and flags.hi==0); return 3 end
            hit(laser()); finish()
            assert(bombs[1].Flags.lo==11 and bombs[1].Flags.hi==0 and bombs[1].Variant==3)
        """)

    def test_weapon_cache_replaces_tears_and_restore_uses_engine_rebuild(self):
        self.run_lua("""
            S.onEvaluateCache(nil,player,CacheFlag.CACHE_WEAPON)
            assert(player.enabled[1]==false and player.enabled[2]==true)
            player.enabled={}; S.onEvaluateCache(nil,player,123); assert(next(player.enabled)==nil)
            player.items[77]=0; S.onEvaluateCache(nil,player,64); assert(next(player.enabled)==nil,'removal disabled foreign weapons')
            player.items[77]=1; REPENTOGON=nil; S.onEvaluateCache(nil,player,64); assert(next(player.enabled)==nil)
            REPENTOGON={Real=true}; player.EnableWeaponType=nil; S.onEvaluateCache(nil,player,64)
            S.onGameStarted(); assert(player.lastCache==64 and player.cacheCount==1)
        """)

    def test_base_collision_fallback_is_disabled_when_confirmed_damage_exists(self):
        self.run_lua("""
            local tear=entity(2,player)
            S.onTearCollision(nil,tear,npc,false)
            assert(#S._pendingStrikes==0,'REPENTOGON collision duplicated confirmed hit path')
            REPENTOGON=nil; S.onTearCollision(nil,tear,npc,false); S.onTearCollision(nil,tear,npc,false)
            assert(#S._pendingStrikes==1)
            local marked=entity(2,player); P.markTriggeredAttack(marked,'soflam',nil,'missile_child')
            S.onTearCollision(nil,marked,npc,false); assert(#S._pendingStrikes==1)
        """)


if __name__ == '__main__':
    unittest.main()
