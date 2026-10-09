"""Offline contract regressions; these do not replace a real Isaac run."""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime
import test_item_bench as runner_tests

ROOT = Path(__file__).resolve().parents[1]


class RunnerInfrastructureTests(unittest.TestCase):
    setUp = runner_tests.BenchTests.setUp
    run_lua = runner_tests.BenchTests.run_lua

    def test_every_result_reaches_log_with_debug_off_and_on(self):
        self.run_lua('''
            local snapshots={}
            ConchBlessing.printDebug=function() error('test output routed through debug logger') end
            for _,debug in ipairs({false,true}) do
                ConchBlessing_Config={debugMode=debug}
                ConchBlessing.Config={debugMode=debug}
                local disk={}; logs={}
                Isaac.DebugString=function(s) disk[#disk+1]=s end
                local name=debug and 'enabled' or 'disabled'
                bench.register({command=name,tag='ItemTest:LOG',build=function(p)
                    p.section('log contract')
                    p.check('success',function() return true,'actual=2 expected=2' end)
                    p.check('failure',function() return false,'actual=1 expected=2' end)
                    p.check('optional',function() return nil,'unavailable API' end)
                end})
                bench.start(name,false); drain()
                local text=table.concat(disk,'\n')
                for _,token in ipairs({'START','PASS success','FAIL failure','SKIP optional','END: 1 PASS, 1 FAIL, 1 SKIP'}) do
                    assert(text:find(token,1,true),token..' missing from log')
                    assert(output():find(token,1,true),token..' missing from console')
                end
                snapshots[#snapshots+1]=text:gsub(name,'test')
            end
            assert(snapshots[1]==snapshots[2],'debug toggle changed test evidence')
        '''.replace("'\n'", "'\\n'"))

    def test_only_proven_compatible_baselines_skip_restarts(self):
        self.run_lua('''
            for _,mode in ipairs({'safe','no_proof','failure','cleanup_error','different_group'}) do
                restarts={}; logs={}
                local first=mode..'_first'; local second=mode..'_second'
                bench.register({command=first,reuseGroup='stats',cleanup=function()
                    if mode=='cleanup_error' then error('cleanup rejected') end
                end,build=function(p)
                    p.act(function(_,ctx) ctx.canReuse=mode~='no_proof' end)
                    p.check('baseline',function() return mode~='failure' end)
                end})
                bench.register({command=second,reuseGroup=mode=='different_group' and 'permanent' or 'stats',
                    build=function(p) p.check('next',function() return true end) end})
                bench.startSuite(mode,{first,second}); drain()
                assert(#restarts==(mode=='safe' and 2 or 3),mode..' wrong reset count '..#restarts)
                assert(output():find(second..' END',1,true),'missing second END')
                assert(output():find('== '..mode..' END',1,true),'missing whole suite END')
            end
        ''')

    def test_clock_releases_after_action_error_stop_and_cleanup_error(self):
        self.run_lua('''
            frame=10; Game=function() return {GetFrameCount=function() return frame end} end
            H=require('scripts.dev.item_test_support'); Clock=require('scripts.lib.timer_clock')
            for _,mode in ipairs({'action_error','stop','cleanup_error'}) do
                local ctxSaved
                bench.register({command=mode,cleanup=H.cleanup,build=function(p)
                    p.act(function(_,ctx)
                        ctxSaved=ctx; H.beginClock(ctx); H.clockAt(ctx,10000)
                        ctx.cleanupFns={function() if mode=='cleanup_error' then error('fixture cleanup error') end end}
                        if mode=='action_error' then error('fixture action error') end
                    end)
                    p.wait(10)
                end})
                bench.start(mode,false); tick()
                if mode~='action_error' then bench.stop() end
                drain(); assert(Clock.now()==frame,mode..' leaked virtual time')
                assert(not pcall(Clock.advance,ctxSaved,11000),'lease survived cleanup')
            end
        ''')

    def test_rng_probe_also_logs_with_debug_off(self):
        self.run_lua('''
            local disk={}; ConchBlessing.Config={debugMode=false}
            ConchBlessing.printDebug=function() error('RNG result used gated debug logger') end
            Isaac.DebugString=function(s) disk[#disk+1]=s end
            require('scripts.dev.rng_probe').injectableDeath()
            assert(table.concat(disk):find('SKIPPED (module/real death-roll helper not loaded)',1,true))
        ''')

    def test_pool_oracle_rejects_valid_item_from_wrong_source(self):
        self.run_lua('''
            EntityType={ENTITY_PICKUP=5}; PickupVariant={PICKUP_COLLECTIBLE=100}; ItemPoolType={POOL_ANGEL=15}
            ConchBlessing.ItemData.ANGELS_CROWN={id=8}
            require('scripts.dev.item_test_pools')
            local checks={}
            local plan=setmetatable({check=function(name,fn) checks[name]=fn end},
                {__index=function() return function() end end})
            bench.get('conch_test angels_crown dice_pool').build(plan)
            local pickup={SubType=7}; pickup.ToPickup=function() return pickup end
            Isaac.FindByType=function() return {pickup} end
            local ctx={stockCount=1,allowed={[7]=true},draws={{id=7,actual=1}}}
            local check=checks['initial conversion actually draws from Angel pool']
            assert(not check(nil,ctx),'nonzero pool member alone must not pass')
            ctx.draws[1].actual=15; assert(check(nil,ctx))
            ctx.allowed={}; assert(not check(nil,ctx),'foreign item must fail')
            ctx.allowed={[7]=true}; ctx.draws={}; assert(not check(nil,ctx),'missing actual draw evidence must fail')
        ''')

    def test_rng_arguments_reject_invalid_values_before_sampling(self):
        self.run_lua('''
            local probe=require('scripts.dev.rng_probe'); local calls={}; player.Luck=7
            for _,name in ipairs({'statRolls','stacking','voidDagger','flatChances','timeMoney',
                'aMinus','angelsCrown','kronos','liveEye','injectableDeath'}) do
                probe[name]=function(...) calls[#calls+1]={name,...} end
            end
            for _,arg in ipairs({'0','-1','0.5','10 20','garbage','luck','luck nope','luck 2 luck 3','1e999'}) do
                probe.run(arg); assert(#calls==0,'invalid input sampled: '..arg)
            end
            probe.run('20 luck -2')
            assert(#calls==10 and calls[1][2]==20 and calls[4][2]==-2)
        ''')

    def test_isolation_rejects_inventory_stats_queue_and_floor_state_leaks(self):
        self.run_lua('''
            EntityType={ENTITY_PLAYER=1,ENTITY_EFFECT=1000}; ItemType={ITEM_ACTIVE=3}
            local itemCount=0; local queueEmpty=true
            player={Damage=3.5,MaxFireDelay=9,TearRange=260,Luck=0,MoveSpeed=1,ShotSpeed=1,
                CanFly=false,TearFlags=0,ControllerIndex=0}
            for _,name in ipairs({'GetTrinket','GetActiveItem','GetActiveCharge','GetBatteryCharge','GetNumCoins',
                'GetNumBombs','GetNumKeys','GetSoulHearts','GetBlackHearts'}) do player[name]=function() return 0 end end
            player.GetHearts=function() return 6 end; player.GetMaxHearts=player.GetHearts
            player.GetCollectibleNum=function() return itemCount end
            player.IsItemQueueEmpty=function() return queueEmpty end
            GetPtrHash=function() return 123 end
            player.IsDead=function() return false end
            player.GetEffects=function() return {GetEffectsList=function() return {Size=0} end} end
            Isaac.GetItemConfig=function() return {GetCollectibles=function() return {Size=2} end} end
            Game=function() return {GetRoom=function() return {IsClear=function() return true end} end,
                GetLevel=function() return {GetStage=function() return 1 end,
                GetCurrentRoomDesc=function() return {ListIndex=0} end,GetDimension=function() return 0 end} end} end
            ConchBlessing._minusNoHit={[0]=true}
            ConchBlessing.getUnifiedMultiplierState=function() return {} end
            local isolation=require('scripts.dev.test_isolation'); local ctx={}; local verify
            isolation.begin({act=function(fn) fn(player,ctx) end,wait=function() end})
            isolation.finish({section=function() end,act=function() end,wait=function() end,
                waitUntil=function() end,
                check=function(_,fn) verify=fn end},'CEIL',1)
            assert(verify(player,ctx))
            itemCount=1; assert(not verify(player,ctx)); itemCount=0
            player.Damage=4; assert(not verify(player,ctx)); player.Damage=3.5
            queueEmpty=false; assert(not verify(player,ctx)); queueEmpty=true
            ConchBlessing._minusNoHit[0]=false; assert(not verify(player,ctx))
        ''')


class ProductionContractTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root=ROOT.as_posix()
        self.lua.execute("package.path=root..'/?.lua;'..package.path")

    def test_timer_clock_rebases_remaining_time_and_releases_before_save(self):
        self.lua.execute('''
            frame=100; events={}; callbacks={}
            Game=function() return {GetFrameCount=function() return frame end} end
            ModCallbacks={MC_PRE_GAME_EXIT=1,MC_POST_GAME_STARTED=2,MC_PRE_MOD_UNLOAD=3}
            ConchBlessing={printError=function(e) error(e) end}
            function ConchBlessing:AddPriorityCallback(id,priority,fn)
                callbacks[id]={priority=priority,fn=fn}
            end
            Clock=require('scripts.lib.timer_clock')
            assert(Clock.now()==100)
            local owner={}; local deadline=1900
            Clock.onRebase('deadline',function(delta) deadline=deadline+delta end)
            Clock.begin(owner); frame=140; assert(Clock.now()==100)
            Clock.advance(owner,1899); assert(deadline-Clock.now()==1)
            assert(not pcall(Clock.advance,{},2000))
            assert(not pcall(Clock.advance,owner,1800))
            assert(not pcall(Clock.begin,{}))
            Clock.release({}); assert(Clock.now()==1899)
            assert(callbacks[1].priority<0,'release must precede ordinary exit save callbacks')
            callbacks[1].fn(); assert(Clock.now()==140 and deadline==141)
            local savedRemaining=deadline-Clock.now(); assert(savedRemaining==1)
            Clock.begin(owner); Clock.advance(owner,5000)
            callbacks[3].fn(nil,{}); assert(Clock.now()==5000,'foreign unload must not revoke lease')
            callbacks[3].fn(nil,ConchBlessing); assert(Clock.now()==frame)
            Clock.begin(owner); Clock.advance(owner,10000); frame=0
            callbacks[2].fn(); assert(Clock.now()==0)
        ''')

    def test_live_timer_callbacks_use_accelerated_boundaries_without_extra_growth(self):
        self.lua.execute('''
            frame=100; save={}; callbacks={}
            ModCallbacks={}; CacheFlag={CACHE_DAMAGE=1}; EntityType={}
            player={held=true}; function player:GetPlayerType() return 0 end
            function player:HasTrinket() return self.held end
            function player:ToPlayer() return self end
            function player:AddCacheFlags() end
            function player:EvaluateItems() end
            game={GetFrameCount=function() return frame end,GetNumPlayers=function() return 1 end,
                GetPlayer=function() return player end}
            Game=function() return game end
            Isaac={GetPlayer=function() return player end}
            ConchBlessing={ItemData={TIME_POWER={id=7}},printDebug=function() end,
                SaveManager={GetRunSave=function() return save end,Save=function() end},
                DamageUtils={isSelfInflictedDamage=function() return false end},
                TrinketUtils={getTrinketCounts=function() return 1,0,false end}}
            require('scripts.items.trinkets.time_power')
            local item=ConchBlessing.timepowertrinket
            item.onGameStarted(nil,false)
            local owner={}; Clock=require('scripts.lib.timer_clock'); Clock.begin(owner)
            item.onUpdate(); local state=item.state.perPlayer['0']; local earned=state.damageBonus
            item.onEntityTakeDamage(nil,player,1,0,nil,30)
            Clock.advance(owner,1899); item.onUpdate(); assert(state.damageBonus==earned)
            Clock.advance(owner,1900); item.onUpdate()
            assert(math.abs(state.damageBonus-earned-0.006/30)<1e-10)
            Clock.advance(owner,1901); item.onUpdate()
            assert(math.abs(state.damageBonus-earned-2*0.006/30)<1e-10)
            item.onEntityTakeDamage(nil,player,1,0,nil,30)
            Clock.advance(owner,2001); frame=120; Clock.release(owner)
            assert(state.pausedUntilFrame-frame==1700,'remaining pause changed during release')
            item.onUpdate(); local before=state.damageBonus
            player.held=false; item.onUpdate()
            assert(state.damageBonus==0 and state.permanentBonus==before)
            frame=10000; item.onUpdate(); assert(state.permanentBonus==before)
        ''')

    def test_return_door_geometry_uses_reachable_wall_and_refuses_foreign_slots(self):
        self.lua.execute('''
            local mt={}; mt.__index=mt
            Vector=function(x,y) return setmetatable({X=x,Y=y},mt) end
            mt.__add=function(a,b) return Vector(a.X+b.X,a.Y+b.Y) end
            mt.__sub=function(a,b) return Vector(a.X-b.X,a.Y-b.Y) end
            DoorSlot={LEFT0=0,RIGHT0=2}; RoomTransitionAnim={FADE=1}
            M=require('scripts.rooms.native_return_door')
            room={left=40,GetCenterPos=function() return Vector(320,0) end,
                GetClampedPosition=function(self) return Vector(self.left,0) end,
                GetGridIndex=function(_,p) return p.X end,GetGridPosition=function(_,i) return Vector(i,0) end,
                IsPositionInRoom=function(self,p) return p.X>self.left and p.X<600 end,
                GetDoorSlotPosition=function() return Vector(20,0) end,
                GetDoor=function(self) return self.occupied end}
            local calls={}; local foreign
            Stage={GetCustomDoorDataAtSlot=function() return foreign end,
                GetCustomGrids=function() return {} end,
                SpawnCustomDoor=function(...) calls[#calls+1]={...} end,
                CustomDoorGrid={Spawn=function(_,index,_,_,data) calls[#calls+1]={index,data} end}}
            local index=M.spawn(Stage,room,'owned',{session=42})
            assert(index==20 and calls[1][1]==0,'ordinary room uses native slot')
            room.left=200; index=M.spawn(Stage,room,'owned',{session=42})
            assert(index==180 and calls[2][1]==180 and calls[2][2].Data.session==42)
            assert(room:IsPositionInRoom(Vector(index+40,0)))
            foreign={}; assert(not pcall(M.spawn,Stage,room,'owned',{})); foreign=nil
            room.occupied={}; assert(not pcall(M.spawn,Stage,room,'owned',{})); room.occupied=nil
            Stage.GetCustomGrids=function() return {{foreign=true}} end
            assert(not pcall(M.spawn,Stage,room,'owned',{}))
            assert(#calls==2,'foreign door/grid was overwritten')
        ''')

    def flame_fixture(self):
        self.lua.execute('''
            CacheFlag={CACHE_DAMAGE=1,CACHE_FIREDELAY=2}; LevelCurse={DARKNESS=1,LOST=2,NUM_CURSES=4}
            EntityType={ENTITY_EFFECT=1000}; Vector={Zero={}}
            curses=0; saves={}; players={}; writes=0
            level={GetCurses=function() return curses end,RemoveCurses=function(_,mask) curses=curses&(~mask) end}
            game={GetLevel=function() return level end,GetNumPlayers=function() return #players end}
            Game=function() return game end
            Isaac={GetItemIdByName=function() return 7 end,GetPlayer=function(i) return players[i+1] end,
                Spawn=function() return nil end}
            ConchBlessing={printDebug=function() end,stats={
                damage={applyAddition=function(p,x) p.Damage=p.Damage+x end},
                tears={applyAddition=function(p,x) p.Tears=p.Tears+x end}}}
            package.loaded['scripts.lib.save_manager']={
                GetRunSave=function(p) saves[p]=saves[p] or {}; return saves[p] end,
                Save=function() writes=writes+1 end}
            require('scripts.items.collectibles.eternal_flame'); flame=ConchBlessing.eternalflame
            function newPlayer(copies)
                local p={copies=copies,hearts=0,Position={}}
                function p:GetCollectibleNum() return self.copies end
                function p:HasCollectible() return self.copies>0 end
                function p:AddCacheFlags() end
                function p:AddEternalHearts(n) self.hearts=self.hearts+n end
                function p:EvaluateItems()
                    self.Damage,self.Tears=3.5,3
                    flame.onEvaluateCache(nil,self,1); flame.onEvaluateCache(nil,self,2)
                end
                players[#players+1]=p; return p
            end
            function updates(n) for _=1,n do flame.onUpdate() end end
        ''')

    def test_flame_earns_at_removal_and_never_rescales_or_revokes(self):
        self.flame_fixture()
        self.lua.execute('''
            local p=newPlayer(1); flame.onGameStarted()
            curses=1; updates(5); p.copies=2; updates(30)
            assert(curses==0 and p.Damage==9.5 and p.Tears==5)
            for _,n in ipairs({1,0,4,0}) do p.copies=n; p:EvaluateItems(); assert(p.Damage==9.5 and p.Tears==5) end
            p.copies=1; curses=3; updates(32)
            assert(p.Damage==15.5 and p.Tears==7 and saves[p].eternalFlame.earnedUnits==4)
            p.copies=0; flame.onGameStarted(); assert(p.Damage==15.5 and p.hearts==1)
            curses=1; updates(40); assert(curses==1 and saves[p].eternalFlame.earnedUnits==4)
            saves[p]={}; flame.onGameStarted(); assert(p.Damage==3.5,'reward leaked into a fresh run')
        ''')

    def test_flame_coop_partial_removal_and_legacy_migration(self):
        self.flame_fixture()
        self.lua.execute('''
            local a=newPlayer(0); local b=newPlayer(3)
            saves[a]={eternalFlame={curseCount=2,itemCount=2}}
            flame.onGameStarted(); assert(a.Damage==15.5 and a.hearts==0)
            level.RemoveCurses=function() curses=curses&2 end
            curses=3; updates(32)
            assert(curses==2 and b.Damage==12.5,'only actually removed curse should earn reward')
            assert(saves[b].eternalFlame.earnedUnits==3)
            updates(40); assert(saves[b].eternalFlame.earnedUnits==3,'failed removal granted a reward')
            a.copies=5; a:EvaluateItems(); assert(a.Damage==15.5,'legacy reward rescaled')
        ''')

    def test_all_swords_evolve_and_existing_tyrfing_earnings_survive(self):
        self.lua.execute('''
            players={}; saves={}; callbacks={}; EID=nil; Vector={Zero={}}
            EntityType={ENTITY_EFFECT=1000}; EffectVariant={POOF01=1}; SoundEffect={SOUND_POWERUP_SPEWER=1}
            SFXManager=function() return {Play=function() end} end
            Isaac={GetItemIdByName=function(name) return name=='Tyrfing' and 8 or 7 end,Spawn=function() end}
            Game=function() return {GetNumPlayers=function() return #players end,GetPlayer=function(_,i) return players[i+1] end} end
            ConchBlessing={printDebug=function() end}
            package.loaded['scripts.lib.save_manager']={GetRunSave=function(p) return saves[p] end,Save=function() end}
            package.loaded['scripts.lib.enemy_utils']={isMonsterKind=function(npc) return npc.monster end}
            require('scripts.items.collectibles.sealed_demon_sword')
            for i,copies in ipairs({3,2}) do
                local p={swords=copies,tyrfing=1}
                function p:HasCollectible() return self.swords>0 end
                function p:GetCollectibleNum() return self.swords end
                function p:RemoveCollectible() self.swords=self.swords-1 end
                function p:AddCollectible(id) assert(id==8); self.tyrfing=self.tyrfing+1 end
                players[i]=p; saves[p]={sealedDemonSword={killCount=298},tyrfing={accumulatedDamage=9}}
            end
            local die=ConchBlessing.sealeddemonsword.onNPCDeath
            die(nil,{monster=false}); assert(saves[players[1]].sealedDemonSword.killCount==298)
            die(nil,{monster=true}); assert(players[1].swords==3 and players[1].tyrfing==1)
            players[1].swords=0; die(nil,{monster=true})
            assert(saves[players[1]].sealedDemonSword.killCount==299)
            assert(players[2].swords==0 and players[2].tyrfing==3)
            players[1].swords=3; die(nil,{monster=true})
            assert(players[1].swords==0 and players[1].tyrfing==4)
            for _,p in ipairs(players) do assert(saves[p].tyrfing.accumulatedDamage==9 and saves[p].sealedDemonSword==nil) end
        ''')

    def test_changed_production_lua_syntax(self):
        check=self.lua.eval('function(s,n) local f,e=load(s,n); return f~=nil,e end')
        names=['lib/timer_clock','rooms/native_return_door','rooms/native_gallery_manager',
               'items/trinkets/atropos','items/trinkets/time_power','items/trinkets/time_tear',
               'items/trinkets/time_luck','items/familiars/time_money',
               'items/collectibles/eternal_flame','items/collectibles/sealed_demon_sword']
        for name in names:
            p=ROOT/'scripts'/(name+'.lua')
            ok,error=check(p.read_text(encoding='utf-8-sig'),str(p))
            self.assertTrue(ok,error)


if __name__=='__main__':
    unittest.main()
