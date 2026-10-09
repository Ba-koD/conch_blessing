"""Atropos shipped callbacks with provider doubles; no engine/Continue claim."""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]

class AtroposReturnTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(r'''
            function Vector(x,y)
                return {X=x,Y=y,DistanceSquared=function(a,b) return (a.X-b.X)^2+(a.Y-b.Y)^2 end}
            end
            dimension=0; roomIndex=84; previousIndex=84; transitionMode=0; hasAtropos=true
            doors={}; savedDoor=nil; spawnCount=0; open=nil; saveOK=true; errors={}; events={}
            function descriptor(i,d,sub)
                return {ListIndex=i+100*d,GridIndex=i,SafeGridIndex=i,SpawnSeed=1000+i,
                    DecorationSeed=2000+i,AwardSeed=3000+i,Data={Type=1,Variant=i,Subtype=sub},
                    GetDimension=function() return d end}
            end
            origin=descriptor(84,0,0); entrance=descriptor(80,2,33); stock=descriptor(81,2,34)
            player={HasTrinket=function() return hasAtropos end,IsItemQueueEmpty=function() return true end}
            room={GetDoor=function() return nativeDoor end}
            level={GetDimension=function() return dimension end,GetStage=function() return 1 end,
                GetStageType=function() return 0 end,GetCurrentRoomIndex=function() return roomIndex end,
                GetCurrentRoomDesc=function() if dimension==0 then return origin end return roomIndex==80 and entrance or stock end,
                GetPreviousRoomIndex=function() return previousIndex end,
                GetRoomByIdx=function(_,i,d)
                    if d==0 and i==84 then return origin end
                    if d==2 and i==80 then return entrance end
                    if d==2 and i==81 then return stock end
                    return {Data=nil}
                end}
            game={GetLevel=function() return level end,GetRoom=function() return room end,
                GetNumPlayers=function() return 1 end,GetPlayer=function() return player end,
                GetSeeds=function() return {GetStartSeed=function() return 123 end} end,
                StartRoomTransition=function(_,idx,dir,anim,p,dim)
                    events[#events+1]='transition'; transitionCalls=(transitionCalls or 0)+1
                    assert(idx==84 and dim==0); if transitionFails then error('failed transition') end
                    transitionMode=1
                end}
            function Game() return game end
            function GetPtrHash(p) return p end
            RoomTransition={GetTransitionMode=function() return transitionMode end}
            DoorSlot={LEFT0=0,RIGHT0=2}; Direction={NO_DIRECTION=-1}; RoomTransitionAnim={FADE=1}
            REPENTOGON={Real=true}; CollectibleType={COLLECTIBLE_DEATH_CERTIFICATE=628}
            ModCallbacks={}; PickupVariant={PICKUP_COLLECTIBLE=100}; EntityType={ENTITY_PICKUP=5}
            Isaac={FindByType=function() return {} end,GetRoomEntities=function() return {} end,
                Spawn=function() error('Atropos must not grant cards') end}
            runSave={}; saveCallbacks={}
            ConchBlessing={ItemData={ATROPOS={id=1}},printDebug=function() end,
                printError=function(msg) errors[#errors+1]=msg end,
                originalMod={AddCallback=function(_,id,fn) saveCallbacks[id]=fn end}}
            ConchBlessing.SaveManager={IsLoaded=function() return true end,
                GetRunSave=function() return runSave end,TryGetRunSave=function() return runSave end,
                SaveCallbacks={POST_DATA_SAVE=90},Save=function()
                    events[#events+1]='save'; if saveOK then saveCallbacks[90]() end
                end}
            function makeDoor(name,data)
                local door={Position=Vector(40,280),Exists=function() return not effectMissing end,
                    Remove=function() effectMissing=true end}
                local grid={GridIndex=1,PersistData={DoorDataName=name,Slot=0,Data=data},Data={DoorEntity=door},
                    Remove=function() doors={};savedDoor=nil end}
                savedDoor=grid;doors={grid}; return grid
            end
            StageAPI={Loaded=true,InOrTransitioningToExtraRoom=function() return extraRoom==true end,
                GetCustomDoorDataAtSlot=function() return savedDoor end,
                GetCustomDoors=function() return doors end,SpawnCustomDoor=function() end,
                SetDoorOpen=function(value) open=value end,
                CustomDoor=setmetatable({}, {__call=function() end})}
            package.loaded['scripts.lib.isaacscript-common']={
                getRoomsOfDimension=function() return {entrance,stock} end,
                getPlayerIndex=function(_,p) if p==player then return 1 end end,
                getPlayerFromIndex=function(_,i) if i==1 then return player end end}
            package.loaded['scripts.rooms.native_return_door']={
                leftWall=function() return 1,Vector(40,280) end,
                spawn=function(_,_,name,data)
                    spawnCount=spawnCount+1; effectMissing=false;makeDoor(name,data)
                    return 1,Vector(40,280),0
                end}
            package.loaded['scripts.rooms.gallery_exit_door']={ANM2='door',register=function() end}
        ''')
        source=(ROOT/'scripts/items/trinkets/atropos.lua').read_text(encoding='utf-8')
        # Export local entry points without replacing their shipped implementation.
        before,after=source.rsplit('return M',1)
        self.lua.execute(before+'M.test={sync=syncReturnDoor,enter=beginNativeSession,restore=ensureContinuedNativeSession,'
                         'use=tryReturnThroughDoor,enable=enableSessionReturnDoor}; return M'+after)
        self.lua.execute('M=ConchBlessing.atropos; M.onGameStarted(nil,false)')

    def enter(self, canonical=True):
        if canonical:
            self.lua.execute('M.onPreUseDeathCertificate(nil,628,nil,player)')
        self.lua.execute('dimension=2;roomIndex=80;M.onPostNewRoom(); saved=runSave.atroposNativeDeathCertificate')

    def test_canonical_entry_always_creates_one_reachable_open_door_and_no_card(self):
        self.enter()
        self.lua.execute('''
            assert(spawnCount==1 and open and saved.returnDoorEnabled and saved.origin.roomIndex==84)
            M.test.sync(); M.test.sync(); assert(spawnCount==1)
        ''')

    def test_custom_entry_uses_only_exact_previously_observed_native_room(self):
        self.enter(canonical=False)
        self.lua.execute('assert(open and saved.origin.roomIndex==84)')
        for setup in ('previousIndex=83', 'extraRoom=true;M.onPostNewRoom()', 'origin.SpawnSeed=999'):
            with self.subTest(setup=setup):
                self.setUp(); self.lua.execute(setup); self.enter(canonical=False)
                self.lua.execute('assert(saved.origin==nil and open==false and #errors>0)')

    def test_late_acquisition_latches_door_through_removal_revisit_and_continue(self):
        self.lua.execute('hasAtropos=false')
        self.enter()
        self.lua.execute('''
            assert(spawnCount==0)
            roomIndex=81; M.onPostNewRoom(); hasAtropos=true; M.onPostUpdate()
            assert(saved.returnDoorEnabled and spawnCount==0)
            hasAtropos=false; roomIndex=80; M.onPostNewRoom(); assert(open and spawnCount==1)
            M.onGameStarted(nil,true); assert(open and saved.returnDoorEnabled and spawnCount==1)
            M.test.use(savedDoor.PersistData); assert(transitionCalls==1)
        ''')

    def test_drop_before_picking_anything_does_not_remove_escape_door(self):
        self.enter()
        self.lua.execute('hasAtropos=false; M.test.sync();assert(open and spawnCount==1);M.test.use(savedDoor.PersistData);assert(transitionCalls==1)')

    def test_return_intent_is_saved_before_transition_and_double_callback_is_latched(self):
        self.enter()
        self.lua.execute('''
            events={};M.test.use(savedDoor.PersistData);M.test.use(savedDoor.PersistData)
            assert(table.concat(events,',')=='save,transition' and transitionCalls==1)
        ''')

    def test_pending_choice_unsaved_return_and_failed_transition_do_not_teleport_or_lose_origin(self):
        self.enter()
        self.lua.execute('''
            saved.transaction={}; M.test.sync(); assert(open==false)
            M.test.use(savedDoor.PersistData);assert(transitionCalls==nil)
            saved.transaction=nil;saveOK=false;M.test.use(savedDoor.PersistData)
            assert(transitionCalls==nil and saved.returnIntent==nil)
            saveOK=true;transitionFails=true;M.test.use(savedDoor.PersistData)
            assert(transitionCalls==1 and saved.returnIntent==nil and saved.origin.roomIndex==84)
            transitionFails=false;M.test.sync();assert(open);M.test.use(savedDoor.PersistData);assert(transitionCalls==2)
        ''')

    def test_removed_door_entity_is_rebuilt_but_foreign_doors_and_appraisal_are_untouched(self):
        self.enter()
        self.lua.execute('''
            effectMissing=true; M.test.sync();assert(spawnCount==2 and open)
            savedDoor.PersistData.DoorDataName='foreign';M.test.sync();assert(spawnCount==2)
            ConchBlessing.GalleryManager={isCurrentGalleryRoom=function() return true end}
            M.test.sync();assert(spawnCount==2 and savedDoor.PersistData.DoorDataName=='foreign')
        ''')

    def test_session_map_mismatch_and_missing_capabilities_are_never_silent_success(self):
        self.enter()
        self.lua.execute('''
            StageAPI.SetDoorOpen=nil; M.test.sync();assert(#errors>0)
            saved.mapFingerprint='foreign';M.onGameStarted(nil,true)
            assert(M._state.nativeSessionReady==false)
        ''')

    def test_old_fool_ledger_only_migrates_door_ownership_without_granting_cards(self):
        self.lua.execute('hasAtropos=false')
        self.enter()
        self.lua.execute('saved.foolSpawned=true;M.onGameStarted(nil,true);assert(open and saved.returnDoorEnabled)')

    def test_activation_save_failure_retries_without_a_permanent_unsaved_latch(self):
        self.lua.execute('hasAtropos=false')
        self.enter()
        self.lua.execute('''
            hasAtropos=true;saveOK=false;M.test.sync()
            assert(not saved.returnDoorEnabled and spawnCount==0 and #errors>0)
            saveOK=true;M.test.sync();assert(saved.returnDoorEnabled and spawnCount==1 and open)
        ''')

    def test_legacy_missing_entrance_is_saved_before_rebinding_and_never_guesses_origin(self):
        self.enter()
        self.lua.execute('''
            doors={};savedDoor=nil;saved.entrance=nil;saved.origin=nil
            saveOK=false;M.test.sync();assert(saved.entrance==nil and spawnCount==1)
            saveOK=true;M.test.sync();assert(saved.entrance and spawnCount==2 and open==false)
            M.test.use(savedDoor.PersistData);assert(transitionCalls==nil)
        ''')

    def test_leaving_dc_retires_door_ownership_and_a_new_visit_does_not_inherit_it(self):
        self.enter()
        self.lua.execute('''
            dimension=0;roomIndex=84;M.onPostNewRoom();assert(not saved.active and not saved.returnDoorEnabled)
            doors={};savedDoor=nil;hasAtropos=false;M.onPreUseDeathCertificate(nil,628,nil,player)
            dimension=2;roomIndex=80;M.onPostNewRoom()
            assert(saved.active and saved.sequence==2 and not saved.returnDoorEnabled and spawnCount==1)
        ''')

    def test_stale_owned_door_is_replaced_and_bad_callback_identity_never_teleports(self):
        self.enter()
        self.lua.execute('''
            local stale=savedDoor.PersistData
            stale.Data.sessionId='old';M.test.sync();assert(spawnCount==2)
            M.test.use(stale);assert(transitionCalls==nil)
            roomIndex=81;M.test.use(savedDoor.PersistData);assert(transitionCalls==nil)
            roomIndex=80;origin.SpawnSeed=999;M.test.use(savedDoor.PersistData);assert(transitionCalls==nil)
        ''')

if __name__=='__main__': unittest.main()
