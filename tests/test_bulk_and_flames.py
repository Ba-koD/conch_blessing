"""Regression fixtures for bulk return and the test harness; no engine/FPS claims."""
from pathlib import Path
import unittest

from lupa.lua53 import LuaRuntime
import test_item_bench as runner_tests
import test_kronos_room_effects as kronos_tests

ROOT = Path(__file__).resolve().parents[1]


class BulkReturnTests(unittest.TestCase):
    setUp = kronos_tests.KronosRoomEffectsTests.setUp

    def enable_visuals(self):
        self.lua.execute('''
            K._queueTransferEffect=originalTransferQueue
            spriteLoads=0
            function Sprite()
                return {Load=function() end,ReplaceSpritesheet=function() end,
                    LoadGraphics=function() spriteLoads=spriteLoads+1 end,
                    SetFrame=function() end,IsLoaded=function() return true end}
            end
            function Font() return {Load=function() end,IsLoaded=function() return true end} end
            Isaac.GetItemConfig=function() return {GetCollectible=function(_,id) return {GfxFileName='item'..id..'.png'} end} end
            Game().GetFrameCount=function() return 10 end
            package.loaded['scripts.conch_blessing_config']={GetCurrentLanguage=function() return 'en' end}
            ConchBlessing.Locale={textIn=function() return 'Return' end}
            function player:Exists() return true end
        ''')

    def test_ten_thousand_copies_use_one_grid_and_bounded_sprite_and_grain_work(self):
        self.enable_visuals()
        self.lua.execute('''
            for _=1,10000 do K._queueTransferEffect(player,123,true) end
            local g=K._test.transferGroups()[1]
            assert(g.copies==10000 and g.icons==1 and g.iconGrains==16)
            assert(spriteLoads==2,'same item reloaded its spritesheet per copy') -- icon + caption atlas
            for id=124,148 do K._queueTransferEffect(player,id,true) end
            g=K._test.transferGroups()[1]
            assert(#K._test.transferGroups()==1 and g.icons==12 and g.copies==10025)
            assert(spriteLoads==13 and g.iconGrains==192,'return work grew beyond the visual budget')
            local other={hash=2}; K._queueTransferEffect(other,150,true)
            K._beginReleaseVisuals(player)
            assert(#K._test.transferGroups()==1 and K._test.transferGroups()[1].hash==2,'another player lost its effects')
            K._clearRoomVisuals(); assert(#K._test.transferGroups()==0)
        ''')

    def test_bulk_inventory_grants_temporary_sources_and_save_are_exact(self):
        self.enable_visuals()
        self.lua.execute('''
            local bobby=absorb('BROTHER_BOBBY',1000)
            local robo=absorb('ROBO_BABY',1000)
            local tech=CollectibleType.COLLECTIBLE_TECHNOLOGY
            local rs=run.kronos
            rs.itemGrants['fam_'..robo]=1000
            rs.itemGrantTotals['fam_'..robo]=1000
            rs.itemGrantBaselines['item_'..tech]=3
            player.inventory[tech]=1003
            rs.tempPermanent={['fam_'..bobby]=300}
            rs.tempFloor={serial=rs.floorSerial or 0,counts={['fam_'..robo]=400}}
            rs.prettyFlies=3
            function player:AddPrettyFly() self.flies=(self.flies or 0)+1 end
            local writes=0
            ConchBlessing.SaveManager.Save=function() writes=writes+1; savedRun=copy(run) end
            player:RemoveCollectible(9999)
            assert(K._revertAll(player))
            assert(player.inventory[bobby]==1000 and player.inventory[robo]==1000)
            assert(player.inventory[tech]==3 and effects[bobby]==300 and effects[robo]==400 and player.flies==3)
            assert(damageBonus()==0 and writes==1)
            assert(next(savedRun.kronos.absorbed)==nil and next(savedRun.kronos.itemGrants)==nil)
            local g=K._test.transferGroups()[1]
            assert(#K._test.transferGroups()==1 and g.copies==2703 and g.icons==3)
            assert(spriteLoads==4,'a returned copy loaded its own sprite')
            assert(not K._revertAll(player))
            assert(writes==1 and player.inventory[bobby]==1000 and effects[bobby]==300,'second cleanup duplicated inventory')
        ''')

    def test_release_queue_expires_without_more_inventory_work(self):
        self.enable_visuals()
        self.lua.execute('''
            function SFXManager() return {Play=function() end} end
            K._queueTransferEffect(player,123,true,nil,10000)
            local before=spriteLoads
            for _=1,K._test.TRANSFER_TOTAL do K.onPostUpdate() end
            assert(#K._test.transferGroups()==0 and spriteLoads==before)
            assert(next(player.inventory)==9999,'cosmetics changed inventory')
        ''')


class HarnessRegressionTests(unittest.TestCase):
    setUp = runner_tests.BenchTests.setUp
    run_lua = runner_tests.BenchTests.run_lua
    load_item_probe = runner_tests.BenchTests.load_item_probe

    def test_attack_isolation_never_removes_counter_bearing_player_or_familiar(self):
        self.run_lua('''
            EntityType={ENTITY_PLAYER=1,ENTITY_TEAR=2,ENTITY_LASER=7,ENTITY_BOMB=4,ENTITY_EFFECT=1000,ENTITY_FAMILIAR=3}
            function GetPtrHash(e) return e.hash end
            local entities={}
            local function entity(kind,data)
                local e={Type=kind,hash=#entities+1}
                function e:GetData() return data or {} end
                function e:Remove() self.removed=true end
                entities[#entities+1]=e; return e
            end
            local player=entity(1,{__ConchFireBreath={attackCount=14},__ConchIceBreath={attackCount=4}})
            local familiar=entity(3,{__ConchFireBreath={}})
            local keep=entity(1000,{__ConchFireBreath={}})
            local flame=entity(1000,{__ConchIceBreath={}})
            local tear=entity(2); local effect=entity(1000)
            Isaac.GetRoomEntities=function() return entities end
            local H=require('scripts.dev.item_test_support')
            H.isolateAttack(keep)
            assert(not player.removed and not familiar.removed and not keep.removed and not effect.removed)
            assert(flame.removed and tear.removed)
            H.isolateAttack(); assert(keep.removed and not player.removed)
        ''')

    def test_removed_or_missing_player_cannot_stall_render_only_runner(self):
        self.run_lua('''
            for _,missing in ipairs({false,true}) do
                logs={}; restarts={}; player={Exists=function() return false end,IsDead=function() return false end}
                bench.register({command=tostring(missing),build=function(p) p.wait(10000) end})
                bench.start(tostring(missing),false)
                if missing then player=nil end
                for _=1,121 do dispatch(ModCallbacks.MC_POST_RENDER) end
                assert(output():find('FAIL test player missing/removed',1,true))
                assert(#restarts==1,'no restart after a removed player')
                dispatch(ModCallbacks.MC_POST_GAME_STARTED,false)
                assert(not bench.isRunning())
            end
        ''')

    def test_bundles_cover_all_members_once_and_preserve_individual_commands(self):
        self.load_item_probe()
        self.run_lua('''
            local groups=require('scripts.dev.item_test_kronos_batches')
            local all=probe.scenarios.commands('KRONOS')
            local counts={}; for _,command in ipairs(all) do counts[command]=(counts[command] or 0)+1 end
            local total=0
            for name,members in pairs(groups.sequential) do groups[name]=members end
            groups.sequential=nil
            for name,members in pairs(groups) do
                assert(counts['conch_test kronos '..name]==1)
                for _,member in ipairs(members) do
                    local command='conch_test kronos '..member
                    assert(bench.get(command) and not counts[command],member..' duplicated or no longer callable')
                    total=total+1
                end
            end
            assert(total==110 and #groups.conversions==48 and #groups.barriers==22 and #groups.exclusions==10)
            local chance=0
            for _,name in ipairs(groups.barriers) do chance=chance+require('scripts.dev.kronos_synergy_cases')[name].block end
            assert(chance<1,'individual contribution checks would be hidden by the 100% cap')
        ''')

    def test_batch_timeout_reports_the_actual_unreturned_familiar(self):
        self.run_lua('''
            bench.register({command='return_timeout',build=function(p)
                p.waitUntil(function() return false,'robo_baby returned=3 expected=128' end,2,'exact return')
                p.act(function() error('dependent checks must not run') end)
            end})
            bench.start('return_timeout',false); drain()
            assert(output():find('robo_baby returned=3 expected=128',1,true))
            assert(not output():find('dependent checks must not run',1,true))
        ''')


class ExitSpriteTests(unittest.TestCase):
    def test_actual_atropos_registration_selects_exit_animation_and_scoped_skin(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().root = ROOT.as_posix()
        lua.execute('''
            package.path=root..'/?.lua;'..package.path
            ConchBlessing={printError=function(e) error(e) end}
            GalleryExitDoor=require('scripts.rooms.gallery_exit_door')
            M={}; RETURN_DOOR_NAME='ConchBlessingAtroposDeathCertificateReturn'
            RoomTransitionAnim={FADE=1}; tryReturnThroughDoor=function() end
            skins={}; StageAPI={UnregisterCallbacks=function(owner) assert(owner:find(RETURN_DOOR_NAME,1,true)) end}
            StageAPI.CustomDoor=setmetatable({}, {__call=function(_,name,anm2)
                assert(name==RETURN_DOOR_NAME); loadedAnm2=anm2
            end})
            StageAPI.AddCallback=function(_,event,_,fn,name) assert(name==RETURN_DOOR_NAME); skins[event]=fn end
        ''')
        source = (ROOT / 'scripts/items/trinkets/atropos.lua').read_text(encoding='utf-8')
        registration = source.split('local function registerReturnDoorType()', 1)[1].split('\nregisterReturnDoorType()', 1)[0]
        lua.execute('local function registerReturnDoorType()' + registration + '\nregisterReturnDoorType()')
        lua.execute('''
            assert(M._returnDoorRegistered and loadedAnm2=='gfx/grid/door_01x_ghostexit.anm2')
            local layers={}; local loads=0
            local sprite={ReplaceSpritesheet=function(_,layer,path) layers[layer]=path end,
                LoadGraphics=function() loads=loads+1 end,IsFinished=function(_,name) return name=='Opened' end,
                Play=function(_,name) assert(name=='Opened'); played=true end}
            local data={}
            skins.POST_SPAWN_CUSTOM_DOOR(nil,data,sprite)
            for i=0,5 do assert(layers[i]=='gfx/grid/door_01x_ghostexit_green.png') end
            assert(loads==1); skins.POST_CUSTOM_DOOR_UPDATE(nil,data,sprite); assert(played and loads==1)
            -- Existing normal door on hot reload updates once without moving it.
            sprite.Rotation=90; sprite.Offset={x=3}
            sprite.GetFilename=function() return 'gfx/grid/door_01_normaldoor.anm2' end
            sprite.Load=function(_,path) assert(path==loadedAnm2); replaced=true end
            skins.POST_CUSTOM_DOOR_UPDATE(nil,{},sprite)
            assert(replaced and loads==2 and sprite.Rotation==90 and sprite.Offset.x==3)
        ''')


if __name__ == '__main__':
    unittest.main()
