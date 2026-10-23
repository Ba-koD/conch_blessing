"""Production lifecycle callbacks under controlled providers; no engine claims."""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class UtilityBeltTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            -- The run save stands in for the disk and is keyed by the player's seed,
            -- which outlives GetData and the session's pointer hashes.
            runs={}
            ConchBlessing={printDebug=function() end,SaveManager={
                GetRunSave=function(p) runs[p.seed]=runs[p.seed] or {}; return runs[p.seed] end,
                TryGetRunSave=function(p) return runs[p.seed] end}}
            Isaac={GetItemIdByName=function() return 900 end}
            ActiveSlot={SLOT_PRIMARY=0,SLOT_POCKET=2}; SoundEffect={SOUND_POWERUP_SPEWER=1}
            CollectibleType={COLLECTIBLE_BOOK_OF_BELIAL_PASSIVE=59,COLLECTIBLE_BOOK_OF_VIRTUES=60,
                COLLECTIBLE_D_INFINITY=61,COLLECTIBLE_BLANK_CARD=62,COLLECTIBLE_PLACEBO=63,
                COLLECTIBLE_CLEAR_RUNE=64,COLLECTIBLE_GLOWING_HOUR_GLASS=65,COLLECTIBLE_JAR_OF_WISPS=66}
            function GetPtrHash(p) return p.hash end
            function SFXManager() return {Play=function() end} end
            package.loaded['scripts.lib.isaacscript-common']={setActiveItem=function(_,p,id,slot,charge)
                p.slots[slot]=id; p.charges[slot]=charge; p.battery[slot]=0; p.moves=p.moves+1
            end}
            function makePlayer(hash)
                local p={hash=hash,seed=hash,data={},slots={},charges={},battery={},belt=0,moves=0}
                function p:GetData() return self.data end
                function p:HasCollectible(id) return id==900 and self.belt>0 end
                function p:GetActiveItem(slot) return self.slots[slot] or 0 end
                function p:GetActiveCharge(slot) return self.charges[slot] or 0 end
                function p:GetBatteryCharge(slot) return self.battery[slot] or 0 end
                return p
            end
            p=makePlayer(1)
        ''')
        self.lua.globals().beltSource = (ROOT/'scripts/items/collectibles/utility_belt.lua').read_text(encoding='utf-8')
        self.lua.execute('''
            function dofile_belt() load(beltSource,'utility_belt')(); M=ConchBlessing.utilitybelt end
            dofile_belt(); function update(p) M.onPlayerUpdate(nil,p) end
        ''')

    def test_transfer_preserves_charge_and_existing_pocket(self):
        self.lua.execute('''
            p.slots[0]=12; p.charges[0]=4; p.battery[0]=6; p.belt=1; update(p)
            assert(p:GetActiveItem(0)==0 and p:GetActiveItem(2)==12 and p:GetActiveCharge(2)==10)
            p.belt=2; update(p); update(p); assert(p.moves==2,'stack repeated the transfer')
            p.belt=0; update(p); assert(p:GetActiveItem(2)==12,'item loss stole an earned pocket active')
            p.slots[0]=13; p.belt=1; update(p)
            assert(p:GetActiveItem(0)==13 and p:GetActiveItem(2)==12 and p.moves==2)
        ''')

    def test_pending_is_per_owner_and_final_loss_cancels_it(self):
        self.lua.execute('''
            q=makePlayer(2); p.belt=1; q.belt=1; update(p); update(q)
            assert(M._pendingPlayers[1] and M._pendingPlayers[2])
            p.belt=0; update(p); assert(not M._pendingPlayers[1] and M._pendingPlayers[2])
            p.slots[0]=12; update(p); assert(p:GetActiveItem(2)==0)
            q.slots[0]=13; update(q); assert(q:GetActiveItem(2)==13 and not M._pendingPlayers[2])
            p.belt=1; update(p); assert(p:GetActiveItem(2)==12)
            M.onPlayerUpdate(nil,nil) -- absent player is a supported non-event
        ''')

    def test_continue_keeps_the_belt_marks_and_moves_nothing_already_settled(self):
        # Continue: a new process, empty entity data and new pointer hashes, the saved run save.
        self.lua.execute('''
            function continue(...)
                for _,q in ipairs({...}) do q.data={}; q.hash=q.hash+100 end
                dofile_belt(); M.onGameStarted(nil,true)
            end
            p.slots[0]=12; p.belt=1; update(p); assert(p:GetActiveItem(2)==12 and p.moves==2) -- one transfer: two slot writes
            p.slots[2]=nil; p.slots[0]=13; update(p)
            assert(p:GetActiveItem(0)==13 and p:GetActiveItem(2)==0,'a settled belt moved a later active')
            q=makePlayer(2); q.belt=1; update(q); assert(M._pendingPlayers[2])
            continue(p,q)
            update(p); update(p)
            assert(p:GetActiveItem(0)==13 and p:GetActiveItem(2)==0 and p.moves==2,'Continue read the belt as just picked up')
            update(q); assert(M._pendingPlayers[q.hash],'Continue lost the owed transfer')
            q.slots[0]=14; update(q); assert(q:GetActiveItem(2)==14 and not M._pendingPlayers[q.hash])
            p.belt=0; update(p); continue(p); p.slots[0]=15; p.belt=1; update(p)
            assert(p:GetActiveItem(2)==15,'reacquisition after a loss is a new pickup')
        ''')

    def test_missing_run_save_never_guesses_a_first_pickup(self):
        self.lua.execute('''
            local get=ConchBlessing.SaveManager.GetRunSave
            ConchBlessing.SaveManager.GetRunSave=function() return nil end
            p.slots[0]=12; p.belt=1; update(p); update(p); assert(p.moves==0)
            ConchBlessing.SaveManager.GetRunSave=get; update(p); assert(p.moves==2 and p:GetActiveItem(2)==12)
        ''')

    def test_every_excluded_active_in_both_orders_then_valid_active(self):
        self.lua.execute('''
            for _,id in pairs(CollectibleType) do
                for _,beltFirst in ipairs({false,true}) do
                    local p=makePlayer(id)
                    if beltFirst then p.belt=1; update(p); p.slots[0]=id
                    else p.slots[0]=id; update(p); p.belt=1 end
                    update(p); update(p)
                    assert(p:GetActiveItem(0)==id and p:GetActiveItem(2)==0 and p.moves==0)
                    p.belt=0; update(p); assert(not M._pendingPlayers[id])
                    p.slots[0]=12; p.belt=1; update(p)
                    assert(p:GetActiveItem(0)==0 and p:GetActiveItem(2)==12)
                end
            end
        ''')


class MinusCacheTests(unittest.TestCase):
    def test_normal_golden_box_partial_final_loss_and_reacquisition_refresh_once(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().root = ROOT.as_posix()
        lua.execute('''
            package.path=root..'/?.lua;'..package.path
            ModCallbacks={MC_EVALUATE_CACHE=1,MC_POST_PEFFECT_UPDATE=2}
            CacheFlag={CACHE_LUCK=1,CACHE_FIREDELAY=2,CACHE_DAMAGE=4}
            callbacks={}; Isaac={GetTrinketIdByName=function(n) return n=='B -' and 10 or 11 end}
            ConchBlessing={printDebug=function() end,originalMod={AddCallback=function(_,id,fn)
                callbacks[id]=callbacks[id] or {}; table.insert(callbacks[id],fn)
            end},stats={}}
            for _,entry in ipairs({{'luck','Luck'},{'tears','Tears'},{'damage','Damage'}}) do
                local field=entry[2]; ConchBlessing.stats[entry[1]]={applyAddition=function(p,v) p[field]=p[field]+v end}
            end
            function makePlayer()
                local p={data={},counts={},evaluations=0}
                function p:GetData() return self.data end
                function p:GetTrinketMultiplier(id) return self.counts[id] or 0 end
                function p:AddCacheFlags(flags) assert(flags==7) end
                function p:EvaluateItems()
                    self.evaluations=self.evaluations+1; self.Luck=0; self.Tears=2.73; self.Damage=3.5
                    for _,flag in ipairs({1,2,4}) do for _,fn in ipairs(callbacks[1]) do fn(nil,self,flag) end end
                end
                return p
            end
            function update(p) for _,fn in ipairs(callbacks[2]) do fn(nil,p) end end
            require('scripts.items.trinkets.b_minus'); require('scripts.items.trinkets.c_minus')
            local p,q=makePlayer(),makePlayer()
            for _,id in ipairs({10,11}) do
                for _,count in ipairs({1,2,3,2,1,0,1,0}) do
                    local before=p.evaluations; p.counts[id]=count; update(p)
                    assert(p.evaluations==before+1,'count transition did not refresh exactly once')
                    local tears=id==10 and 3 or 2
                    assert(math.abs(p.Tears-(2.73+count*tears))<1e-9,'stale tears on count='..count)
                    assert(p.Luck==count*(id==10 and 3 or 4))
                    assert(p.Damage==3.5+(id==10 and 3*count or 0))
                    update(p); assert(p.evaluations==before+1,'unchanged count reevaluated every frame')
                    update(q); assert(q.evaluations==0,'another player was modified')
                end
            end
        ''')


class LuaCompilationTests(unittest.TestCase):
    def test_all_runtime_lua_sources_compile_without_running_gameplay(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        compile_source = lua.eval('function(s,n) local f,e=load(s,n); return f~=nil,e end')
        paths = [ROOT/'main.lua', *sorted((ROOT/'scripts').rglob('*.lua'))]
        for path in paths:
            with self.subTest(path=path.relative_to(ROOT).as_posix()):
                ok, error = compile_source(path.read_text(encoding='utf-8-sig'), str(path))
                self.assertTrue(ok, error)


if __name__ == '__main__':
    unittest.main()
