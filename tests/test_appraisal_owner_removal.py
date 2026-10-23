"""Native Appraisal return when the visit owner leaves the run mid-visit.

Production native_gallery_manager.lua runs against engine/provider doubles. A
co-op player can drop out and a mid-run extra player can be removed, so the
owner may be gone while others still stand in the Death Certificate rooms.
These checks do not prove the engine transition itself or a real Continue.
"""
from pathlib import Path
import unittest

from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class AppraisalOwnerRemovalTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(r'''
            dimension=2; roomIndex=80; transitionMode=0; saveOK=true
            errors={}; transitions={}; smelts=0
            function descriptor(i,d,sub)
                return {ListIndex=i+100*d,GridIndex=i,SafeGridIndex=i,SpawnSeed=1000+i,
                    Data={Type=1,Variant=i,Subtype=sub},GetDimension=function() return d end}
            end
            origin=descriptor(84,0,0); entrance=descriptor(80,2,33)
            local function makePlayer(index)
                local p={index=index,ControllerIndex=0,removed=false}
                function p:Exists() return not self.removed end
                function p:IsDead() return false end
                function p:ToPlayer() return self end
                function p:IsItemQueueEmpty() return true end
                function p:SmeltTrinket() smelts=smelts+1 end
                return p
            end
            owner=makePlayer(1); friend=makePlayer(2)
            players={owner,friend}
            function removePlayer(p)
                p.removed=true
                for i,q in ipairs(players) do if q==p then table.remove(players,i) break end end
            end
            level={GetDimension=function() return dimension end,GetStage=function() return 1 end,
                GetStageType=function() return 0 end,GetDungeonPlacementSeed=function() return 55 end,
                GetCurrentRoomIndex=function() return roomIndex end,
                GetCurrentRoomDesc=function() if dimension==0 then return origin end return entrance end,
                GetRoomByIdx=function(_,i,d)
                    if d==0 and i==84 then return origin end
                    if d==2 and i==80 then return entrance end
                    return nil
                end}
            game={GetLevel=function() return level end,
                GetRoom=function() return {GetDoor=function() return nil end} end,
                GetNumPlayers=function() return #players end,
                GetPlayer=function(_,i) return players[i+1] end,
                StartRoomTransition=function(_,target,dir,anim,player,dim)
                    transitions[#transitions+1]={target=target,player=player,dimension=dim}
                    transitionMode=1
                end}
            function Game() return game end
            function GetPtrHash(x) return x end
            RoomTransition={GetTransitionMode=function() return transitionMode end}
            Direction={NO_DIRECTION=-1}; RoomTransitionAnim={FADE=1}; DoorSlot={LEFT0=0}
            PickupVariant={PICKUP_COLLECTIBLE=100,PICKUP_TRINKET=350}
            CollectibleType={COLLECTIBLE_DEATH_CERTIFICATE=628,COLLECTIBLE_GLOWING_HOUR_GLASS=422}
            ModCallbacks=setmetatable({}, {__index=function(_,k) return k end})
            runSave={}; saveCallbacks={}
            ConchBlessing={NativeGalleryManager={},ItemData={},Config={debugMode=false},
                GalleryManager={isBackendActive=function() return true end},
                printDebug=function() end,printError=function(m) errors[#errors+1]=m end,
                originalMod={AddCallback=function(_,id,fn) saveCallbacks[id]=fn end}}
            function ConchBlessing:AddCallback() end
            function ConchBlessing:AddPriorityCallback() end
            function ConchBlessing:AddCallbackCustom() end
            ConchBlessing.SaveManager={IsLoaded=function() return true end,
                GetRunSave=function() return runSave end,TryGetRunSave=function() return runSave end,
                SaveCallbacks={POST_DATA_SAVE=90},
                Save=function() if saveOK then saveCallbacks[90]() end end}
            package.loaded['scripts.rooms.native_return_door']={leftWall=function() return nil end}
            package.loaded['scripts.rooms.death_certificate_gallery_rooms']={}
            package.loaded['scripts.rooms.gallery_exit_door']={ANM2='door',register=function() end}
            package.loaded['scripts.lib.isaacscript-common']={ModCallbackCustom={POST_ITEM_PICKUP=1},
                getPlayerIndex=function(_,p) return p.index end,
                getPlayerFromIndex=function(_,i)
                    for _,p in ipairs(players) do if p.index==i then return p end end
                end}
            package=nil -- production code must not see the host's package table
        ''')
        source = (ROOT / 'scripts/rooms/native_gallery_manager.lua').read_text(encoding='utf-8')
        # Export local entry points without replacing their shipped implementation.
        before, after = source.rsplit('return M', 1)
        chunk = before + ('M.test={transition=transitionToOrigin,doorExit=requestReturnDoorExit};'
                          'return M') + after
        self.lua.globals().nativeSource = chunk
        self.lua.execute(r'''
            M=assert(load(nativeSource,'native_gallery_manager.lua'))()
            M._runLifecycleReady=true
            session={version=11,mode='appraisal_trinkets_death_certificate',token='t1',
                visitId='t1:visit:1',floor={stage=1,stageType=0,placementSeed=55},
                phase='browsing',entryCommitted=true,ownerPlayerIndex=1,visitRewardCount=0,
                origin={dimension=0,roomIndex=84,safeGridIndex=84,gridIndex=84,listIndex=84,
                    spawnSeed=1084,roomType=1,roomVariant=84,roomSubType=0,stage=1,stageType=0},
                entryJournal={coinsBefore=20,coinsApplied=true}}
            runSave.appraisalGallerySession=session
            function arriveAtOrigin() transitionMode=0; dimension=0; roomIndex=84 end
        ''')

    def test_return_door_is_led_by_a_remaining_player_when_the_owner_left(self):
        self.lua.execute(r'''
            removePlayer(owner)
            assert(M.test.doorExit(session)==true, 'the return door still works')
            assert(#transitions==1 and transitions[1].player==friend, 'the remaining player leads it')
            assert(transitions[1].target==84 and transitions[1].dimension==0, 'to the exact saved origin')
            assert(session.phase=='returning' and session.origin.roomIndex==84)
            assert(M.test.doorExit(session)==true and #transitions==1, 'the issued return is latched')
            arriveAtOrigin(); M.onPostNewRoom()
            assert(session.phase=='completed' and session.origin==nil and #errors==0)
        ''')

    def test_owner_still_leads_while_present(self):
        self.lua.execute(r'''
            M.test.doorExit(session)
            assert(#transitions==1 and transitions[1].player==owner)
        ''')

    def test_auto_return_does_not_stall_without_the_owner(self):
        self.lua.execute(r'''
            session.phase='return_ready'; session.returnReason='choice_complete'
            removePlayer(owner)
            M.onUpdate()
            assert(#transitions==1 and transitions[1].player==friend and session.phase=='returning')
            arriveAtOrigin(); M.onUpdate()
            assert(session.phase=='completed')
        ''')

    def test_a_removed_entity_never_leads_and_nobody_left_issues_nothing(self):
        self.lua.execute(r'''
            removePlayer(owner); owner.removed=true
            friend.removed=true                       -- still listed for a frame, but gone
            assert(M.test.transition(session)==false and #transitions==0, 'no live player, no call')
            assert(session.returnIssuedFrom==nil and M._returnTransitionIssued.t1==nil,
                'nothing is armed for a call that was never made')
            friend.removed=false
            assert(M.test.transition(session)==true and transitions[1].player==friend)
        ''')

    def test_unresolved_reward_without_its_players_still_settles_fail_closed(self):
        self.lua.execute(r'''
            session.phase='pickup_animating'
            session.pendingChoice={phase='animating',playerIndex=1,token='c1',roomKey='r1',
                collisionCompleted=true,pickupConfirmed=true}
            removePlayer(owner)
            assert(M.test.doorExit(session)==true, 'the door works during an unresolved reward')
            assert(session.emergencyReturnRequested=='gallery_return_door')
            assert(#transitions==1 and transitions[1].player==friend)
            assert(session.pendingChoice and session.pendingChoice.phase=='animating',
                'the reward journal is preserved through the transition')
            arriveAtOrigin(); M.onPostNewRoom()
            assert(session.phase=='choice_failed' and session.pendingChoice.failureReason,
                'with its chooser gone the reward fails closed at the origin')
            M.onUpdate(); M.onUpdate()
            assert(session.phase=='completed' and session.pendingChoice==nil)
            assert(smelts==0 and #transitions==1, 'no reward was granted and no second transition issued')
        ''')

    def test_save_failure_before_the_call_keeps_the_owner_free_return_unissued(self):
        self.lua.execute(r'''
            removePlayer(owner); saveOK=false
            assert(M.test.transition(session)==false and #transitions==0)
            saveOK=true
            assert(M.test.transition(session)==true and transitions[1].player==friend)
        ''')


class LegacyDetourLeaderTests(unittest.TestCase):
    """Continued version-9 sessions: Atropos's detour return and map teleport."""

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(r'''
            entered={}; errors={}
            local function makePlayer(index)
                local p={index=index,removed=false}
                function p:Exists() return not self.removed end
                function p:IsDead() return false end
                function p:ToPlayer() return self end
                return p
            end
            owner=makePlayer(1); friend=makePlayer(2); stranger={index=3}
            players={owner,friend}
            function removePlayer(p)
                p.removed=true
                for i,q in ipairs(players) do if q==p then table.remove(players,i) break end end
            end
            level={GetStage=function() return 1 end,GetStageType=function() return 0 end,
                GetDungeonPlacementSeed=function() return 55 end,GetDimension=function() return 2 end}
            game={GetLevel=function() return level end,GetNumPlayers=function() return #players end,
                GetPlayer=function(_,i) return players[i+1] end}
            function Game() return game end
            function GetPtrHash(x) return x end
            ModCallbacks=setmetatable({}, {__index=function(_,k) return k end})
            PickupVariant={PICKUP_COLLECTIBLE=100,PICKUP_TRINKET=350}
            CollectibleType={COLLECTIBLE_DEATH_CERTIFICATE=628,COLLECTIBLE_GLOWING_HOUR_GLASS=422}
            runSave={}; saveCallbacks={}
            ConchBlessing={ItemData={},Config={debugMode=false},
                printDebug=function() end,printError=function(m) errors[#errors+1]=m end,
                originalMod={AddCallback=function(_,id,fn) saveCallbacks[id]=fn end}}
            function ConchBlessing:AddCallback() end
            function ConchBlessing:AddPriorityCallback() end
            function ConchBlessing:AddCallbackCustom() end
            ConchBlessing.SaveManager={IsLoaded=function() return true end,
                GetRunSave=function() return runSave end,TryGetRunSave=function() return runSave end,
                SaveCallbacks={POST_DATA_SAVE=90},Save=function() saveCallbacks[90]() end}
            legacyRooms={MAP_DIMENSION=-7,
                rebind=function() return {} end,
                enterRoom=function(_,_,mapID,player) entered[#entered+1]=player; return true end}
            package.loaded['scripts.rooms.stageapi_gallery_rooms']=legacyRooms
            package.loaded['scripts.rooms.gallery_exit_door']={ANM2='door',register=function() end}
            package.loaded['scripts.lib.isaacscript-common']={ModCallbackCustom={POST_ITEM_PICKUP=1},
                getPlayerIndex=function(_,p) return p.index end,
                getPlayerFromIndex=function(_,i)
                    for _,p in ipairs(players) do if p.index==i then return p end end
                end}
            package=nil
        ''')
        source = (ROOT / 'scripts/rooms/legacy_stageapi_gallery_manager.lua').read_text(encoding='utf-8')
        self.lua.globals().legacySource = source
        self.lua.execute(r'''
            M=assert(load(legacySource,'legacy_stageapi_gallery_manager.lua'))()
            identity={version=1,kind='appraisal_stageapi',detourId='v:dc:1',token='t9',visitId='v',
                mapDimension=-7,mapID=1,roomID='r1',roomKey='e',graphSeed=7,playerIndex=1,
                underlyingDimension=0,baseRoomIndex=84,baseRoomVariant=3,baseRoomSpawnSeed=99,
                stage=1,stageType=0,floorPlacementSeed=55}
            local detour={}
            for k,v in pairs(identity) do detour[k]=v end
            detour.phase='active'; detour.dcSessionId='dc1'
            session={version=9,mode='appraisal_trinkets_stageapi',token='t9',visitId='v',seed=7,
                floor={stage=1,stageType=0,placementSeed=55},
                graph={entrance={key='e',mapID=1,roomID='r1',graphSeed=7},rooms={}},
                deathCertificateDetour=detour}
            runSave.appraisalGallerySession=session
            function returnAs(player) return M.returnDeathCertificateDetour(identity,'dc1',player) end
        ''')

    def test_detour_player_still_leads_while_present(self):
        self.lua.execute(r'''
            assert(not returnAs(friend), 'another player cannot take over while the detour player is here')
            assert(returnAs(owner)==true and entered[1]==owner)
        ''')

    def test_a_remaining_player_leads_once_the_detour_player_left(self):
        self.lua.execute(r'''
            removePlayer(owner)
            assert(not returnAs(nil) and not returnAs(stranger), 'a non-player never leads')
            assert(returnAs(friend)==true and entered[1]==friend)
            assert(session.deathCertificateDetour.phase=='reentering', 'the detour identity is unchanged')
        ''')

    def test_map_teleport_uses_the_callers_player_else_a_live_one_never_player_zero(self):
        self.lua.execute(r'''
            Isaac={GetFrameCount=function() frame=(frame or 0)+1; return frame end,
                GetPlayer=function() error('must not fall back to player 0') end}
            StageAPI={CurrentLevelMapRoomID=1}
            local stub=legacyRooms
            stub.isCurrentRoom=function() return true end
            stub.getCurrentManifest=function() return session.graph.entrance, {} end
            stub.rebind=function() return {byMapID={[1]=session.graph.entrance,[2]={}}} end
            stub.teleportWithinGallery=function(_,_,mapID,player) entered[#entered+1]=player; return true end
            session.deathCertificateDetour=nil; session.ownerPlayerIndex=1; session.graph.seed=7
            M._runLifecycleReady=true
            assert(M.teleportToGalleryRoom(7,2,friend)==true and entered[1]==friend, "the caller's player leads")
            assert(M.teleportToGalleryRoom(7,2,nil)==true and entered[2]==owner, 'no player named: the owner')
            removePlayer(owner)
            assert(M.teleportToGalleryRoom(7,2,nil)==true and entered[3]==friend, 'owner gone: a live player')
            removePlayer(friend)
            local ok,reason=M.teleportToGalleryRoom(7,2,nil)
            assert(not ok and reason=='no_live_player' and #entered==3)
        ''')

    def test_a_foreign_identity_is_refused_even_without_its_player(self):
        self.lua.execute(r'''
            removePlayer(owner)
            identity.roomID='r2'
            assert(not returnAs(friend) and #entered==0)
        ''')


class NoPlayerZeroFallbackTests(unittest.TestCase):
    """A callback whose player is missing is rejected, never answered for player 0."""

    def test_player_owned_flows_never_borrow_player_zero(self):
        for path in ('scripts/rooms/native_gallery_manager.lua',
                     'scripts/rooms/legacy_stageapi_gallery_manager.lua',
                     'scripts/rooms/stageapi_gallery_rooms.lua',
                     'scripts/items/trinkets/atropos.lua',
                     'scripts/items/collectibles/severed_oath.lua',
                     'scripts/items/cards/conch_ticket.lua'):
            with self.subTest(path=path):
                source = (ROOT / path).read_text(encoding='utf-8')
                self.assertNotIn('GetPlayer(0)', source)


if __name__ == '__main__':
    unittest.main()
