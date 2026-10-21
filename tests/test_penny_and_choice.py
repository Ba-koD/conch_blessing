"""Production functions: eligibility, reward recursion and DC choice commit order.

Provider doubles exercise errors and boundaries. The Penny's Continue and Glowing
Hourglass cases stand the run save in for the disk; they are not engine tests.
"""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class PennyTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            ItemType={ITEM_ACTIVE=2}; CollectibleType={NUM_COLLECTIBLES=10}
            ModCallbacks={MC_POST_ADD_COLLECTIBLE=1}; CallbackPriority={EARLY=-100}; stage=1
            configs={[1]={Type=1},[2]={Type=2},[3]={Type=3},[4]={Type=1},[999]={Type=1},[10001]={Type=2}}
            players={}; sounds=0; handlers={}
            Isaac={GetItemIdByName=function() return 999 end,
                GetItemConfig=function() return {GetCollectible=function(_,id) return configs[id] end} end,
                GetPlayer=function(i) return players[i+1] end}
            function Game() return {GetLevel=function() return {GetStage=function() return stage end,GetStageType=function() return 0 end} end,
                GetNumPlayers=function() return #players end} end
            function SFXManager() return {Play=function() sounds=sounds+1 end} end
            SoundEffect={SOUND_POWERUP1=1}
            DamageFlag={DAMAGE_NO_PENALTIES=1<<28}; RoomType={ROOM_SACRIFICE=13}
            ConchBlessingRequire=function(name)
                if name=='scripts.lib.player_hits' then return load(hitsSource,'player_hits')() end
                assert(name=='scripts.lib.sound_volume','unexpected require '..tostring(name))
                return {volume=function(v) return v end}
            end
            -- The run save stands in for the disk: it outlives GetData and a module reload.
            runs={}
            local SaveManager={}
            function SaveManager.GetRunSave(p) runs[p.key]=runs[p.key] or {}; return runs[p.key] end
            function SaveManager.TryGetRunSave(p) return runs[p.key] end
            ConchBlessing={printDebug=function() end,printError=function(e) error(e) end,
                ItemData={PENNY={id=999},EXTERNAL_ACTIVE={id=10001}},SaveManager=SaveManager}
            -- Callbacks run in priority order like the engine's; ties keep registration order.
            function ConchBlessing:AddPriorityCallback(id,priority,fn)
                handlers[#handlers+1]={priority=priority,fn=fn,order=#handlers}
                table.sort(handlers,function(a,b)
                    if a.priority~=b.priority then return a.priority<b.priority end
                    return a.order<b.order end)
            end
            function ConchBlessing:AddCallback() end
            function otherMod(fn) ConchBlessing:AddPriorityCallback(1,0,fn) end
            function makePlayer()
                local p={inventory={},data={},key='P'..(#players+1)}
                function p:GetData() return self.data end
                function p:ToPlayer() return self end
                function p:GetCollectibleNum(id) return self.inventory[id] or 0 end
                function p:HasCollectible(id) return self:GetCollectibleNum(id)>0 end
                function p:AddCollectible(id,_,first)
                    self.inventory[id]=self:GetCollectibleNum(id)+1
                    if ModCallbacks.MC_POST_ADD_COLLECTIBLE then
                        for _,h in ipairs(handlers) do h.fn(nil,id,0,first,0,0,self) end
                    end
                end
                function p:RemoveCollectible(id) self.inventory[id]=math.max(0,self:GetCollectibleNum(id)-1) end
                players[#players+1]=p; return p
            end
            function slots(p) local s=M._test.state(p); return s and s.slots or {} end
            function loadPenny() load(source, "two_faced_penny")(); M=ConchBlessing.twofacedpenny end
            -- Continue: a new process, empty entity data, the saved run save.
            function continue()
                handlers={}
                for _,q in ipairs(players) do q.data={} end
                loadPenny(); M.onGameStarted(nil,true)
            end
            p=makePlayer()
        ''')
        self.lua.globals().source = (ROOT/'scripts/items/collectibles/two_faced_penny.lua').read_text(encoding='utf-8')
        self.lua.globals().hitsSource = (ROOT/'scripts/lib/player_hits.lua').read_text(encoding='utf-8')
        self.load()

    def load(self):
        self.lua.execute('handlers={}; loadPenny(); M.onGameStarted(nil,false)')

    def test_post_add_runs_before_default_priority_callbacks(self):
        self.lua.execute('''
            assert(#handlers==1 and handlers[1].priority==CallbackPriority.EARLY)
            otherMod(function() end); assert(handlers[1].fn==M.onPostAddCollectible)
        ''')

    def test_actives_and_invalid_ids_never_consume_a_pending_reward(self):
        self.lua.execute('''
            p:AddCollectible(999,0,true)
            for _,id in ipairs({2,10001,77777}) do p:AddCollectible(id,0,true); assert(p:GetCollectibleNum(id)==1) end
            assert(slots(p)[1].itemId==nil)
            p:AddCollectible(1,0,true); assert(p:GetCollectibleNum(1)==2)
            p:AddCollectible(1,0,true); assert(p:GetCollectibleNum(1)==3,'reward recursively repeated')
        ''')

    def test_fallback_scan_also_ignores_actives_and_accepts_familiars(self):
        self.lua.execute('ModCallbacks={}')
        self.load()
        self.lua.execute('''
            p:AddCollectible(999,0,true); M.onPlayerUpdate(nil,p)
            p:AddCollectible(2,0,true); p:AddCollectible(10001,0,true); M.onPlayerUpdate(nil,p)
            assert(slots(p)[1].itemId==nil)
            p:AddCollectible(3,0,true); M.onPlayerUpdate(nil,p); M.onPlayerUpdate(nil,p)
            assert(p:GetCollectibleNum(3)==2 and p:GetCollectibleNum(2)==1)
        ''')

    def test_fallback_floor_payout_is_not_claimed_by_a_newer_open_coin(self):
        self.lua.execute('ModCallbacks={}')
        self.load()
        self.lua.execute('''
            p:AddCollectible(999,0,true); M.onPlayerUpdate(nil,p)
            p:AddCollectible(1,0,true); M.onPlayerUpdate(nil,p); assert(p:GetCollectibleNum(1)==2)
            p:AddCollectible(999,0,true); M.onPlayerUpdate(nil,p)
            stage=2; M.onNewFloor(); M.onPlayerUpdate(nil,p); M.onPlayerUpdate(nil,p)
            assert(p:GetCollectibleNum(1)==3 and slots(p)[2].itemId==nil,'payout taken by the second coin')
        ''')

    def test_stack_partial_loss_and_new_copy_claim_only_their_own_slots(self):
        self.lua.execute('''
            p:AddCollectible(999,0,true); p:AddCollectible(999,0,true)
            p:AddCollectible(1,0,true); assert(p:GetCollectibleNum(1)==3)
            p:RemoveCollectible(999); M.onPlayerUpdate(nil,p)
            assert(#slots(p)==1)
            p:AddCollectible(999,0,true); p:AddCollectible(2,0,true); p:AddCollectible(3,0,true)
            assert(p:GetCollectibleNum(3)==2 and p:GetCollectibleNum(1)==3)
            p:RemoveCollectible(999); p:RemoveCollectible(999); M.onPlayerUpdate(nil,p)
            p:AddCollectible(1,0,true); assert(p:GetCollectibleNum(1)==4)
            assert(#slots(p)==0)
        ''')

    def test_floor_reward_is_once_per_boundary_damage_cancels_and_owners_are_separate(self):
        self.lua.execute('''
            q=makePlayer(); M.onPlayerUpdate(nil,q)
            p:AddCollectible(999,0,true); q:AddCollectible(999,0,true)
            p:AddCollectible(1,0,true); q:AddCollectible(3,0,true)
            M.onDamage(nil,p,1,0); stage=2; M.onNewFloor(); M.onNewFloor()
            assert(p:GetCollectibleNum(1)==2 and q:GetCollectibleNum(3)==3)
            M.onDamage(nil,p,1,DamageFlag.DAMAGE_NO_PENALTIES); stage=3; M.onNewFloor()
            assert(p:GetCollectibleNum(1)==3 and q:GetCollectibleNum(3)==4)
        ''')

    def test_a_later_coins_reservation_does_not_clear_an_earlier_coins_hit(self):
        self.lua.execute('''
            p:AddCollectible(999,0,true); p:AddCollectible(1,0,true)
            M.onDamage(nil,p,1,0)
            p:AddCollectible(999,0,true); p:AddCollectible(4,0,true); assert(p:GetCollectibleNum(4)==2)
            stage=2; M.onNewFloor()
            assert(p:GetCollectibleNum(1)==2,'hit floor paid the first coin')
            assert(p:GetCollectibleNum(4)==3,'a coin counts its floor from its own reservation')
            stage=3; M.onNewFloor(); assert(p:GetCollectibleNum(1)==3 and p:GetCollectibleNum(4)==4)
        ''')

    def test_another_mods_grant_during_the_pickup_does_not_take_the_coin(self):
        self.lua.execute('''
            otherMod(function(_,id,_,_,_,_,player) if id==1 and not granted then granted=true; player:AddCollectible(4,0,true) end end)
            p:AddCollectible(999,0,true); p:AddCollectible(1,0,true)
            assert(p:GetCollectibleNum(1)==2 and p:GetCollectibleNum(4)==1)
            stage=2; M.onNewFloor(); assert(p:GetCollectibleNum(1)==3 and p:GetCollectibleNum(4)==1)
        ''')

    def test_payout_answered_by_another_mod_stays_unclaimed_for_a_new_coin(self):
        self.lua.execute('''
            otherMod(function(_,id,_,_,_,_,player) if id==1 and p:GetCollectibleNum(1)==3 then player:AddCollectible(4,0,true) end end)
            p:AddCollectible(999,0,true); p:AddCollectible(1,0,true); p:AddCollectible(999,0,true)
            stage=2; M.onNewFloor()
            assert(p:GetCollectibleNum(1)==3 and p:GetCollectibleNum(4)==1 and slots(p)[2].itemId==nil)
        ''')

    def test_continue_keeps_each_coins_item_and_hit(self):
        self.lua.execute('''
            p:AddCollectible(999,0,true); p:AddCollectible(1,0,true)
            continue()
            p:AddCollectible(3,0,true); assert(p:GetCollectibleNum(3)==1,'continue reopened the coin')
            stage=2; M.onNewFloor(); assert(p:GetCollectibleNum(1)==3 and p:GetCollectibleNum(3)==1)
            M.onDamage(nil,p,1,0); continue()
            stage=3; M.onNewFloor(); assert(p:GetCollectibleNum(1)==3,'continue forgot the hit')
        ''')

    def test_level_callbacks_before_game_start_never_pay_a_stale_run(self):
        self.lua.execute('''
            p:AddCollectible(999,0,true); p:AddCollectible(1,0,true)
            handlers={}; p.data={}; loadPenny()
            stage=5; M.onNewFloor(); M.onPlayerUpdate(nil,p)
            assert(p:GetCollectibleNum(1)==2,'paid before game start')
            M.onGameStarted(nil,false); p:AddCollectible(3,0,true)
            assert(p:GetCollectibleNum(3)==2,'a new run starts with an open coin')
            M.onPreGameExit(); stage=6; M.onNewFloor(); assert(p:GetCollectibleNum(3)==2)
        ''')

    def test_glowing_hourglass_rewind_pays_each_floor_once(self):
        self.lua.execute('''
            local function copy(t) local c={} for k,v in pairs(t) do c[k]=type(v)=='table' and copy(v) or v end return c end
            p:AddCollectible(999,0,true); p:AddCollectible(1,0,true)
            local savedRuns, savedInventory = copy(runs), copy(p.inventory)
            stage=2; M.onNewFloor(); assert(p:GetCollectibleNum(1)==3)
            runs, p.inventory, stage = savedRuns, savedInventory, 1
            M.onNewFloor(); assert(p:GetCollectibleNum(1)==2,'paid on the way back')
            stage=2; M.onNewFloor(); assert(p:GetCollectibleNum(1)==3)
        ''')

    def test_old_active_reservation_never_pays_and_becomes_available(self):
        self.lua.execute('''
            p:AddCollectible(999,0,true)
            slots(p)[1]={itemId=2}
            stage=2; M.onNewFloor(); assert(p:GetCollectibleNum(2)==0)
            M.onPlayerUpdate(nil,p); p:AddCollectible(1,0,true)
            assert(p:GetCollectibleNum(1)==2)
        ''')

    def test_non_acquisition_inventory_restore_does_not_claim(self):
        self.lua.execute('''
            p:AddCollectible(999,0,true); p:AddCollectible(1,0,false)
            assert(p:GetCollectibleNum(1)==1 and slots(p)[1].itemId==nil)
        ''')


class AtroposChoiceTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            M={}; PHASE_PREPARED='prepared'; PHASE_CLOSING='closing'; PHASE_CANCELLED='cancelled'
            DC_DIMENSION=2; PickupVariant={PICKUP_COLLECTIBLE=100}
            state={runtimeTransactionToken='one'}; context={key='room1'}
            events={}; savesOK=true; saveCalls=0; removed=0; nativeSave={rooms={}}
            transaction={token='one',phase='prepared',roomKey='room1',playerIndex=1,
                collectibleId=10,pickupInitSeed=123,pickupHash=456,extendedCallbacks=true,collisionWindowOpen=true}
            nativeSave.transaction=transaction
            function saveNow()
                saveCalls=saveCalls+1; events[#events+1]='save'
                return savesOK and saveCalls~=failSaveCall
            end
            function getState() return state end
            function getCurrentDimension() return 2 end
            function isAppraisalGalleryRoom() return appraisal==true end
            function getMatchingPreparedTransaction(player)
                if player==owner and transaction.phase=='prepared' and transaction.collisionWindowOpen then
                    return nativeSave,transaction,context
                end
            end
            owner={QueuedItem={Item={ID=10}},IsItemQueueEmpty=function() error('must not wait for animation') end}
            function owner:ToPlayer() return self end
            pickup={Variant=100,InitSeed=123,hash=456}
            function GetPtrHash(p) return p.hash end
            function removeRoomCollectibles()
                assert(nativeSave.rooms.room1.completed,'removed before room commit')
                events[#events+1]='remove'; removed=removed+1; return 5
            end
            function clearCancelledTransaction() error('unexpected cancellation') end
            isc={getPlayerFromIndex=function() return owner end}
            ConchBlessing={printError=function() end,printDebug=function() end}
        ''')
        source=(ROOT/'scripts/items/trinkets/atropos.lua').read_text(encoding='utf-8')
        transaction_functions=source[source.index('local function closeTransaction('):source.index('local function getMatchingPreparedTransaction(')]
        collision=source[source.index('function M.onPostPickupCollision('):source.index('function M.onPostUpdate(')]
        self.lua.execute(transaction_functions+collision+'\nresolve=resolvePreparedTransaction; accepted=hasAcceptedQueuedChoice')

    def test_accepted_pickup_clears_room_in_same_collision_while_animation_is_active(self):
        self.lua.execute('''
            M.onPostPickupCollision(nil,pickup,owner)
            assert(removed==1 and nativeSave.transaction==nil)
            assert(table.concat(events,',')=='save,save,remove,save')
            assert(nativeSave.rooms.room1.selectedId==10 and nativeSave.rooms.room1.committed)
            assert(owner.QueuedItem.Item.ID==10,'selected reward queue was modified')
        ''')

    def test_cancelled_foreign_ambiguous_and_other_room_collisions_do_not_remove(self):
        for setup in ('owner.QueuedItem.Item=nil', 'owner.QueuedItem.Item.ID=11',
                      'pickup.hash=999', 'pickup.InitSeed=99', 'transaction.preAddAmbiguous=true',
                      'transaction.postAddCount=2', 'transaction.evidenceSaveFailed=true', 'appraisal=true'):
            with self.subTest(setup=setup):
                self.setUp()
                self.lua.execute(setup+'; M.onPostPickupCollision(nil,pickup,owner); assert(removed==0)')

    def test_failed_pre_removal_save_blocks_deletion_and_closing_journal_retries(self):
        self.lua.execute('''
            failSaveCall=2; M.onPostPickupCollision(nil,pickup,owner)
            assert(removed==0 and nativeSave.transaction.phase=='closing')
            failSaveCall=nil; resolve(nativeSave,context)
            assert(removed==1 and nativeSave.transaction==nil)
        ''')

    def test_queue_transform_accepts_only_exact_post_add_result(self):
        self.lua.execute('''
            transaction.preAddCount=1; transaction.preAddObservedId=10
            transaction.postAddCount=1; transaction.postAddObservedId=20
            owner.QueuedItem.Item.ID=20
            M.onPostPickupCollision(nil,pickup,owner)
            assert(removed==1 and nativeSave.rooms.room1.selectedId==20)
        ''')


if __name__ == '__main__':
    unittest.main()
