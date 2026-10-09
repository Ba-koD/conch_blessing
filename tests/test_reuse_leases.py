"""Runner baseline reuse: execute production runner with deterministic engine doubles."""
import unittest
import test_item_bench as shared


class ReuseLeaseTests(unittest.TestCase):
    setUp = shared.BenchTests.setUp
    run_lua = shared.BenchTests.run_lua
    load_item_probe = shared.BenchTests.load_item_probe

    def test_compatible_commands_and_suite_use_one_initial_restart(self):
        self.run_lua("""
            local inventory=0
            for _,name in ipairs({'first','second','third'}) do
                bench.register({command=name,reuseGroup='kronos_reversible',build=function(p)
                    p.act(function() assert(inventory==0); inventory=1 end)
                    p.check('behavior',function() return true,'checked actual fixture' end)
                    p.act(function(_,ctx)
                        inventory=0; ctx.canReuse=true
                        ctx.verifyReuse=function() return inventory==0,'inventory changed' end
                    end)
                end})
            end
            bench.startSuite('suite',{'first','second'}); drain()
            assert(#restarts==1,'compatible suite restarted between members or after completion')
            bench.start('third',true); drain()
            assert(#restarts==1,'compatible independent command ignored the validated idle lease')
            assert(output():find('Baseline revalidated;',1,true))
            inventory=2
            Isaac.ExecuteCommand=function(cmd)
                restarts[#restarts+1]=cmd; pendingRestart=true; inventory=0
            end
            bench.start('first',true); drain()
            assert(#restarts==2,'changed inventory reused the stale lease')
            assert(output():find('retained baseline changed: inventory changed',1,true))
        """)

    def test_behavior_failure_does_not_force_restart_after_proven_cleanup(self):
        self.run_lua("""
            local dirty=false
            bench.register({command='failure',reuseGroup='kronos',build=function(p)
                p.act(function() dirty=true end)
                p.check('promised damage',function() return false,'actual=0 expected=2' end)
                p.act(function(_,ctx)
                    dirty=false; ctx.canReuse=true
                    ctx.verifyReuse=function() return not dirty end
                end)
            end})
            bench.register({command='next',reuseGroup='kronos',build=function(p)
                p.check('next starts clean',function() return not dirty end)
                p.act(function(_,ctx) ctx.canReuse=true; ctx.verifyReuse=function() return not dirty end end)
            end})
            bench.startSuite('suite',{'failure','next'}); drain()
            assert(#restarts==1,'independent behavior failure caused an unnecessary restart')
            assert(output():find('suite END: 1 PASS, 1 FAIL',1,true))
        """)

    def test_late_mutation_cleanup_exception_and_cancel_revoke_the_lease(self):
        self.run_lua("""
            local clean=true
            local execute=Isaac.ExecuteCommand
            Isaac.ExecuteCommand=function(cmd) clean=true; execute(cmd) end
            for _,mode in ipairs({'late_mutation','cleanup_error','cancel'}) do
                local first=mode..'_first'; local second=mode..'_second'
                bench.register({command=first,reuseGroup=mode,cleanup=function()
                    if mode=='late_mutation' then clean=false end
                    if mode=='cleanup_error' then error('cleanup failed') end
                end,build=function(p)
                    p.act(function(_,ctx)
                        ctx.canReuse=true; ctx.verifyReuse=function() return clean,'late effect remains' end
                    end)
                    if mode=='cancel' then p.wait(100) end
                end})
                bench.register({command=second,reuseGroup=mode,build=function(p)
                    p.check('next baseline',function() return clean end)
                    p.act(function(_,ctx) ctx.canReuse=true; ctx.verifyReuse=function() return clean end end)
                end})
                restarts={}
                bench.startSuite(mode,{first,second})
                if mode=='cancel' then tick(); tick(); bench.stop() end
                drain()
                assert(#restarts==2,mode..' failed to reset once before continuing/ending')
                if mode~='cancel' then assert(output():find(second..' END: 1 PASS, 0 FAIL',1,true)) end
            end
            assert(output():find('RESET reason: late effect remains',1,true))
            assert(output():find('RESET reason: cleanup raised an error',1,true))
        """)

    def test_actual_isolation_waits_for_returned_familiars_and_refuses_saved_effects(self):
        self.run_lua("""
            local inventory,returned={},false
            local saved={kronos={}}
            local game={GetFrameCount=function() return 10 end,GetRoom=function() return {IsClear=function() return true end} end,GetLevel=function() return {
                GetStage=function() return 1 end,GetCurrentRoomDesc=function() return {ListIndex=80} end,
                GetDimension=function() return 0 end} end}
            Game=function() return game end
            GetPtrHash=function() return 123 end
            ItemType={ITEM_ACTIVE=3}; EntityType={ENTITY_PLAYER=1,ENTITY_EFFECT=1000}
            local config={GetCollectibles=function() return {Size=30} end,
                GetCollectible=function() return {Type=1} end}
            Isaac.GetItemConfig=function() return config end
            player.Damage=3.5; player.MaxFireDelay=9; player.TearRange=260
            player.Luck=0; player.MoveSpeed=1; player.ShotSpeed=1; player.CanFly=false; player.TearFlags=0
            player.GetCollectibleNum=function(_,id) return inventory[id] or 0 end
            player.HasCollectible=function(_,id) return (inventory[id] or 0)>0 end
            player.AddCollectible=function(_,id) inventory[id]=(inventory[id] or 0)+1 end
            player.RemoveCollectible=function(_,id)
                inventory[id]=math.max(0,(inventory[id] or 0)-1)
                if id==10 then returned=true end
            end
            for _,method in ipairs({'GetTrinket','GetActiveItem','GetActiveCharge','GetBatteryCharge',
                'GetNumCoins','GetNumBombs','GetNumKeys','GetHearts','GetMaxHearts','GetSoulHearts','GetBlackHearts'}) do
                player[method]=function() return 0 end
            end
            CacheFlag={CACHE_ALL=1}
            for _,method in ipairs({'AddCoins','AddBombs','AddKeys','AddMaxHearts','AddHearts',
                'SetActiveCharge','AddCacheFlags','EvaluateItems'}) do
                player[method]=function() end
            end
            player.GetData=function() return {} end
            player.IsDead=function() return false end
            player.IsItemQueueEmpty=function() return true end
            player.GetEffects=function() return {GetEffectsList=function() return {Size=0} end} end
            ConchBlessing.SaveManager={GetRunSave=function() return saved end}
            ConchBlessing.getUnifiedMultiplierState=function() return {} end
            ConchBlessing.kronos={_getRoomTemporary=function() return {} end}
            local Isolation=require('scripts.dev.test_isolation')
            local H=require('scripts.dev.item_test_support')
            ConchBlessing:AddCallback(ModCallbacks.MC_POST_UPDATE,function()
                if returned then inventory[11]=(inventory[11] or 0)+2; returned=false end
            end)
            local leaveSaved
            bench.register({command='isolation',reuseGroup='kronos_reversible',cleanup=H.cleanup,build=function(p)
                Isolation.begin(p,true)
                p.act(function() inventory[10]=1; if leaveSaved then saved.kronos.milkSerial=3 end end)
                Isolation.finish(p,'KRONOS',10)
            end})
            bench.start('isolation',true); drain()
            assert(#restarts==1,'clean baseline was not retained')
            assert((inventory[10] or 0)==0 and (inventory[11] or 0)==0,'returned familiar escaped inventory cleanup')
            assert(output():find('isolation END: 2 PASS, 0 FAIL',1,true))
            leaveSaved=true; bench.start('isolation',true); drain()
            assert(#restarts==2,'orphan saved effect did not force isolation restart')
            assert(saved.kronos.milkSerial==3,'test erased production saved state to pretend cleanup succeeded')
            assert(output():find('Kronos saved effect remains: milkSerial',1,true))
        """)

    def test_kronos_and_belt_benches_share_a_compatibility_domain_with_reset_reasons(self):
        self.load_item_probe()
        self.run_lua("""
            for _,name in ipairs({'abilities','attacks','auras','barriers','lifecycle','gb_bug',
                'brother_bobby','guardian_angel','rotten_baby','succubus','censer','paschal_candle','relic','trinket_the_twins'}) do
                assert(bench.get('conch_test kronos '..name).reuseGroup=='kronos_reversible',name)
            end
            for _,name in ipairs({'lifecycle','excluded_actives','book_of_virtues','d_infinity'}) do
                assert(bench.get('conch_test utility_belt '..name).reuseGroup=='belt_reversible',name)
            end
            for _,name in ipairs({'manual_before','manual_after','lost_soul','sacrificial_altar','hallowed_ground','exclusions'}) do
                local def=bench.get('conch_test kronos '..name)
                assert(not def.reuseGroup and #def.resetReason>10,name..' missing actual isolation reason')
            end
            bench.register({command='conch_test kronos detail',build=function() end})
            local names=probe.suiteCommands({'KRONOS','UTILITY_BELT','MONEY_TEAR'})
            local closed,last={},nil
            for _,name in ipairs(names) do
                local group=bench.get(name).reuseGroup
                if group~=last then
                    if last then closed[last]=true end
                    assert(not group or not closed[group],'compatible group fragmented by suite order')
                    last=group
                end
            end
        """)


if __name__ == '__main__':
    unittest.main()
