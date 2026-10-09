"""Test-fixture causal evidence only; does not simulate Isaac laser damage."""
import unittest
import test_item_bench as runner_tests


class WeaponObserverTests(unittest.TestCase):
    run_lua = runner_tests.BenchTests.run_lua

    def setUp(self):
        runner_tests.BenchTests.setUp(self)
        self.run_lua('''
            ModCallbacks.MC_POST_LASER_INIT=40
            ModCallbacks.MC_POST_ENTITY_TAKE_DMG=41
            EntityType={ENTITY_PLAYER=1,ENTITY_TEAR=2,ENTITY_LASER=7}
            frame=12; entities={}
            Game=function() return {GetFrameCount=function() return frame end} end
            GetPtrHash=function(e) return e.hash end
            function entity(hash,kind,owner)
                local e={hash=hash,Type=kind,owner=owner,alive=true,data={},CollisionDamage=3.5}
                function e:GetData() return self.data end
                function e:Exists() return self.alive end
                function e:Remove() self.alive=false end
                return e
            end
            player.hash=1
            Isaac.GetRoomEntities=function() return entities end
            package.loaded['scripts.lib.damage_provenance']={
                getDirectPlayerOwner=function(e) return e.owner end,
                getPlayerOwner=function(e) return e.owner or e.familiarOwner end,
                getSourceEntity=function(source,extra) return extra and extra.Entity or source and source.Entity end,
            }
            H=require('scripts.dev.item_test_support')
        ''')

    def test_laser_isolation_keeps_one_real_beam_without_touching_other_owners(self):
        self.run_lua('''
            local ctx={}; H.shoot(player,'$lasers',ctx,1)
            ctx.shots.isolateLasers=true
            local first=entity(2,7,player)
            local second=entity(3,7,player)
            local other=entity(4,7,{hash=90})
            dispatch(40,first); dispatch(40,first); dispatch(40,second); dispatch(40,other)
            assert(first.alive and not second.alive and other.alive)
            assert(first.CollisionDamage==3.5 and ctx.shots.count==1)
            assert(ctx.shots.entities[1]==first)
            H.stopShooting()
            local after=entity(5,7,player); dispatch(40,after)
            assert(after.alive,'observer interfered after cleanup')
        ''')

    def test_only_new_observed_attack_and_exact_target_establish_hit_time(self):
        self.run_lua('''
            local old=entity(2,2,player); entities={old}
            local ctx={}; H.shoot(player,'$tears',ctx,1);ctx.shots.targetHash=30
            dispatch(41,{hash=30},3.5,0,{Entity=old},0,nil)
            assert(ctx.shots.hitFrame==nil,'pre-existing attack accepted as new evidence')
            local fresh=entity(3,2,player);entities={old,fresh};dispatch(ModCallbacks.MC_POST_UPDATE)
            assert(ctx.shots.count==1 and ctx.shots.entities[1]==fresh)
            assert(ctx.shots.samples[1].entityType==2,'emitted type was not snapshotted before collision removal')
            dispatch(41,{hash=31},3.5,0,{Entity=fresh},0,nil)
            dispatch(41,{hash=30},0,0,{Entity=fresh},0,nil)
            assert(ctx.shots.hitFrame==nil,'unrelated or zero damage accepted')
            dispatch(41,{hash=30},3.5,0,{Entity=player},0,{Entity=fresh})
            assert(ctx.shots.hitFrame==12,'actual attack in ExtraSource ignored')
            assert(ctx.shots.directDamage==3.5 and ctx.shots.directHits==1)
            frame=20;dispatch(41,{hash=30},3.5,0,{Entity=fresh},0,nil)
            assert(ctx.shots.hitFrame==12,'repeat hit changed first-hit timestamp')
            assert(ctx.shots.directDamage==7 and ctx.shots.directHits==2,'direct damage evidence lost')
        ''')

    def test_familiar_tears_remain_visible_except_in_direct_weapon_fixture(self):
        self.run_lua('''
            local familiarTear=entity(2,2,nil);familiarTear.familiarOwner=player
            local ctx={};H.shoot(player,'$tears',ctx,1)
            entities={familiarTear};dispatch(ModCallbacks.MC_POST_UPDATE)
            assert(ctx.shots.count==1,'Kronos familiar attack was filtered out')
            entities={};H.shoot(player,'$tears',ctx,1);ctx.shots.directOnly=true
            entities={familiarTear};dispatch(ModCallbacks.MC_POST_UPDATE)
            assert(ctx.shots.count==0,'familiar damage substituted for direct player fire')
        ''')


if __name__ == '__main__':
    unittest.main()
