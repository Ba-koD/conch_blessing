"""Magic Conch upgrades on rotating pedestals through the shipped transaction.

A rotating (REPENTOGON collectible cycle) pedestal evolves only the choice on
show when the answer comes (user decision 2026-10-29). While the upgrade plays
it holds that choice (user request 2026-11-07): its queue waits in the job and
the room's record, so the engine has nothing to turn to, and the commit puts
the queue back behind the evolved item. Leaving the room or the game before the
change keeps the answer: the next visit (or Continue) finds the pedestal evolved.
Offline doubles only: `cb test morph cycle` and `cb test morph return`
check the engine.
"""
import unittest

import test_morph_viewer as viewer_harness

MORPH_PRE, MORPH_POST = 1213, 1215


class RotatingPedestalUpgradeTests(unittest.TestCase):
    def setUp(self):
        harness = viewer_harness.MorphVisualTests
        harness.setUp(self)
        self.lua.execute(f'''
            ModCallbacks.MC_PRE_PICKUP_MORPH={MORPH_PRE}
            ModCallbacks.MC_POST_PICKUP_MORPH={MORPH_POST}
            -- SaveManager: one room save per room, written by Save().
            roomSaves={{}}; currentRoom='start'; saves=0; saveLoaded=true
            local function roomSave(create)
                if not roomSaves[currentRoom] and create then roomSaves[currentRoom]={{}} end
                return roomSaves[currentRoom]
            end
            ConchBlessing.SaveManager={{IsLoaded=function() return saveLoaded end,
                GetRoomSave=function(ent) assert(ent==nil) return roomSave(true) end,
                TryGetRoomSave=function(ent) assert(ent==nil) return roomSave(false) end,
                Save=function() saves=saves+1 end}}
        ''')
        harness.viewer(self)
        self.lua.execute(f'''
            debugLines={{}}
            ConchBlessing.printDebug=function(s) debugLines[#debugLines+1]=s end
            MagicConch.API.Config.deleteMode=false
            player={{ToPlayer=function(self) return self end}}
            origin=ConchBlessing.ItemData.DRAGON.origin.id
            target=ConchBlessing.ItemData.DRAGON.id
            function giveCycle(p, tail)
                p.cycle={{}}
                for i,id in ipairs(tail or {{}}) do p.cycle[i]=id end
                function p:GetCollectibleCycle() local t={{}} for i,v in ipairs(self.cycle) do t[i]=v end return t end
                function p:AddCollectibleCycle(id) if #self.cycle>=8 then return false end self.cycle[#self.cycle+1]=id return true end
                function p:RemoveCollectibleCycle() self.cycle={{}} end
                return p
            end
            -- A pedestal showing `head` with the queued tail `cycle`.
            function rotating(head, tail)
                local p=giveCycle(Isaac.Spawn(5,100,head,Vector(80,80),Vector(0,0),nil), tail)
                entities={{p}}
                return p
            end
            -- The engine's own turn: the next choice shows, the shown one joins
            -- the end of the queue. An empty queue has nothing to turn to.
            -- viaMorph re-initializes the pickup like a native Morph.
            function turn(p, viaMorph)
                if #p.cycle==0 then return false end
                local head=table.remove(p.cycle,1); p.cycle[#p.cycle+1]=p.SubType
                if not viaMorph then p.SubType=head; return true end
                assert(event({MORPH_PRE},p,5,100,head,true,true,true)==nil, 'observers never cancel')
                p.SubType=head; p.data={{}}; p.generation=p.generation+1
                event({MORPH_POST},p,5,100,head,true,true,true)
                return true
            end
            function circle(p)
                local ids={{p.SubType}}
                for _,id in ipairs(p.cycle or {{}}) do ids[#ids+1]=id end
                return ids
            end
            function same(a, b)
                if #a~=#b then return false end
                for i=1,#a do if a[i]~=b[i] then return false end end
                return true
            end
            function records()
                local r=ConchBlessing.upgrade._test.records()
                local n=0
                for _ in pairs(r or {{}}) do n=n+1 end
                return n, r
            end
            -- Leave the room: its pickups unload and another room loads.
            function leave(room)
                for _,e in ipairs(entities) do e.alive=false end
                entities={{}}; currentRoom=room or 'elsewhere'
                event(3)
            end
            -- Come back: the engine rebuilds the pedestal from its saved state.
            function comeBack(saved, subtype, tail, room)
                local q=Isaac.Spawn(5, saved.Variant, subtype or saved.SubType, Vector(saved.Position.X,saved.Position.Y), Vector(0,0), nil)
                q.InitSeed=saved.InitSeed; q.Price=saved.Price; q.ShopItemId=saved.ShopItemId
                if tail then giveCycle(q, tail) end
                entities={{q}}; currentRoom=room or 'start'
                event(3)
                return q
            end
            event(4) -- game start opens the record lifecycle
            for i=1,10 do event(1) end -- Magic Conch callback registration
        ''')

    def test_the_choice_on_show_is_held_until_it_evolves(self):
        for via_morph in (False, True):
            with self.subTest(via_morph=via_morph):
                self.lua.globals().viaMorph = via_morph
                self.lua.execute('''
                    p=rotating(origin,{77,88})
                    actualConchResult({type='positive'})
                    job=ConchBlessing._upgradeJobs[1]
                    assert(job and job.cyclePlan and #ConchBlessing._upgradeJobs==1, 'queued with its cycle')
                    assert(#p.cycle==0 and p.SubType==origin, 'the queue is held at once')
                    assert(ConchBlessing.upgrade.isCycleFrozen(p))
                    local n, r=records(); assert(n==1)
                    local _, record=next(r)
                    assert(record.shown==origin and same(record.tail,{77,88}) and record.seed==p.InitSeed)
                    local turned, shownBefore, atCommit=0, true, nil
                    for tick=1,220 do
                        if tick%20==0 and turn(p, viaMorph) then turned=turned+1 end
                        if not job.committed then
                            shownBefore=shownBefore and p.SubType==origin
                            assert(event(10,p,player)==true, 'locked until the change')
                        end
                        event(1)
                        if job.committed and not atCommit then atCommit=circle(p) end
                    end
                    assert(shownBefore, 'the pedestal kept showing the evolving choice')
                    assert(job.status=='complete' and job.committed and job.endReason=='complete', tostring(job.endReason))
                    -- The evolved item first, then the held queue in its order.
                    assert(same(atCommit, {target,77,88}), table.concat(atCommit,','))
                    assert(turned>=1, 'it turns again after the change')
                    assert(#morphs==1 and titles[1]==target and #errors==0)
                    assert(records()==0 and not ConchBlessing.upgrade.isCycleFrozen(p))
                    morphs={}; titles={}; ConchBlessing._upgradeJobs={}
                ''')

    def test_an_evolvable_choice_not_on_show_stays(self):
        self.lua.execute('''
            p=rotating(77,{origin,88})
            actualConchResult({type='positive'})
            assert(#ConchBlessing._upgradeJobs==0 and records()==0, 'only the choice on show decides')
            assert(same(circle(p), {77,origin,88}), 'nothing is held')
            for tick=1,220 do
                if tick%20==0 then turn(p, false) end
                event(1)
            end
            assert(#morphs==0 and #titles==0 and #errors==0)
        ''')

    def test_only_the_copy_on_show_evolves(self):
        self.lua.execute('''
            p=rotating(origin,{77,origin})
            actualConchResult({type='positive'})
            job=ConchBlessing._upgradeJobs[1]
            for tick=1,220 do event(1) end
            assert(job.committed and same(circle(p), {target,77,origin}), table.concat(circle(p),','))
            assert(#errors==0)
        ''')

    def test_choices_added_while_held_follow_the_queue(self):
        self.lua.execute('''
            p=rotating(origin,{77,88})
            actualConchResult({type='positive'})
            job=ConchBlessing._upgradeJobs[1]
            for tick=1,10 do event(1) end
            assert(p:AddCollectibleCycle(99), 'another mod appends a choice')
            for tick=1,220 do event(1) end
            assert(job.committed and same(circle(p), {target,77,88,99}), table.concat(circle(p),','))
            assert(#errors==0)
        ''')

    def test_a_full_circle_keeps_its_capacity(self):
        self.lua.execute('''
            p=rotating(origin,{1,2,3,4,5,6,7,8})
            actualConchResult({type='positive'})
            job=ConchBlessing._upgradeJobs[1]
            for tick=1,220 do event(1) end
            assert(job.committed and same(circle(p), {target,1,2,3,4,5,6,7,8}), table.concat(circle(p),','))
        ''')

    def test_cancelling_gives_the_queue_back(self):
        self.lua.execute('''
            p=rotating(origin,{77,88})
            actualConchResult({type='positive'})
            job=ConchBlessing._upgradeJobs[1]
            for tick=1,10 do event(1) end
            ConchBlessing.upgrade.cancel(job)
            assert(job.status=='cancelled' and same(circle(p), {origin,77,88}), table.concat(circle(p),','))
            assert(records()==0 and #morphs==0 and event(10,p,player)==nil)
            for tick=1,220 do event(1) end
            assert(same(circle(p), {origin,77,88}) and #morphs==0)
        ''')

    def test_a_reroll_while_held_is_a_new_pedestal(self):
        self.lua.execute(f'''
            p=rotating(origin,{{77,88}})
            p.sprite.Color=Color(1,1,1,0.8); p.sprite.Color.original=true
            actualConchResult({{type='positive'}})
            job=ConchBlessing._upgradeJobs[1]
            for i=1,10 do event(1) end
            assert(not p.sprite:GetLayer(1):IsVisible(), 'presentation holds the item layer')
            event({MORPH_PRE},p,5,100,555,true,false,false)
            p.SubType=555; p.cycle={{}}; p.data={{}}; p.generation=p.generation+1
            event({MORPH_POST},p,5,100,555,true,false,false)
            event(1)
            assert(job.status=='cancelled' and job.endReason=='source-changed', tostring(job.endReason))
            -- The old queue belongs to the old pedestal; a reroll keeps its own.
            assert(same(circle(p), {{555}}) and records()==0 and #morphs==0)
            assert(p.sprite.Color.original and p.sprite:GetLayer(1):IsVisible(), 'pedestal restored')
            assert(event(10,p,player)==nil, 'no stale lock')
            for i=1,200 do event(1) end
            assert(#morphs==0 and #errors==0)
        ''')

    def test_a_reference_lost_without_proof_gives_the_queue_back_and_keeps_the_answer(self):
        self.lua.execute('''
            p=rotating(origin,{77,88})
            actualConchResult({type='positive'})
            job=ConchBlessing._upgradeJobs[1]
            for i=1,5 do event(1) end
            p.generation=p.generation+1 -- re-initialized without Morph callbacks
            event(1)
            assert(job.status=='cancelled' and job.endReason=='expired', tostring(job.endReason))
            assert(same(circle(p), {origin,77,88}), 'the very pedestal gets its queue back')
            assert(records()==1, 'the answer waits for the next visit')
            local logged=false
            for _,line in ipairs(debugLines) do logged=logged or line:find('Pickup reference expired',1,true)~=nil end
            assert(logged and #morphs==0)
            -- The next visit changes the choice where the circle has it then.
            local saved={Variant=100,SubType=88,Position=p.Position,InitSeed=p.InitSeed,Price=0,ShopItemId=-1}
            leave()
            local q=comeBack(saved, 88, {origin,77})
            assert(same(circle(q), {88,target,77}), table.concat(circle(q),','))
            assert(records()==0 and titles[1]==target and #errors==0)
        ''')

    def test_a_cancelled_native_morph_never_proves_a_recycled_address(self):
        self.lua.execute(f'''
            p=rotating(origin,{{77,88}})
            actualConchResult({{type='positive'}})
            job=ConchBlessing._upgradeJobs[1]
            for i=1,5 do event(1) end
            -- Another mod cancels this Morph after our PRE: POST never runs.
            event({MORPH_PRE},p,5,100,origin,true,true,true)
            p:Remove()
            local q=giveCycle(Isaac.Spawn(5,100,origin,p.Position,Vector(0,0),nil), {{}})
            q.pointerHash=p.pointerHash; q.InitSeed=p.InitSeed
            entities={{q}}
            event({MORPH_PRE},q,5,100,origin,true,true,true)
            assert(not ConchBlessing.upgrade.isAnimatingPickup(q), 'the earlier lease ends on this address')
            q.generation=q.generation+1
            event({MORPH_POST},q,5,100,origin,true,true,true)
            event(1)
            assert(job.status=='cancelled' and job.endReason=='expired', tostring(job.endReason))
            assert(event(10,q,player)==nil and next(q:GetData())==nil, 'the recycled pickup is not claimed')
            assert(#q.cycle==0, 'nothing is written onto an unproven pickup')
            for i=1,200 do event(1) end
            assert(#morphs==0 and q.SubType==origin)
        ''')

    def test_leaving_before_the_change_finds_it_evolved_on_return(self):
        self.lua.execute('''
            p=rotating(origin,{77,88})
            p.Price=15; p.ShopItemId=3; p.AutoUpdatePrice=false
            actualConchResult({type='positive'})
            job=ConchBlessing._upgradeJobs[1]
            for i=1,30 do event(1) end
            assert(not job.committed and #p.cycle==0)
            local saved={Variant=100,SubType=p.SubType,Position=p.Position,InitSeed=p.InitSeed,Price=15,ShopItemId=3}
            leave()
            assert(#ConchBlessing._upgradeJobs==0 and job.endReason=='room-change', tostring(job.endReason))
            assert(records()==0, 'another room has no records')
            for i=1,200 do event(1) end
            -- The engine saved the held pedestal: the shown choice and no queue.
            local q=comeBack(saved, origin, {})
            assert(same(circle(q), {target,77,88}), table.concat(circle(q),','))
            assert(q.Price==15 and q.ShopItemId==3 and q.AutoUpdatePrice==false, 'shop contract kept')
            assert(titles[1]==target and #titles==1 and records()==0 and #errors==0)
            assert(#ConchBlessing._upgradeJobs==0 and not ConchBlessing.upgrade.isAnimatingPickup(q), 'no presentation on return')
            for i=1,200 do event(1) end
            assert(#morphs==1 and #titles==1, 'it evolves once')
        ''')

    def test_a_plain_pedestal_left_before_the_change_evolves_on_return(self):
        self.lua.execute('''
            p=Isaac.Spawn(5,100,origin,Vector(120,80),Vector(0,0),nil)
            entities={p}
            actualConchResult({type='positive'})
            job=ConchBlessing._upgradeJobs[1]
            for i=1,20 do event(1) end
            local saved={Variant=100,SubType=origin,Position=p.Position,InitSeed=p.InitSeed,Price=0,ShopItemId=-1}
            leave()
            local q=comeBack(saved)
            assert(q.SubType==target and titles[1]==target and records()==0 and #errors==0)
        ''')

    def test_exit_and_continue_finish_the_upgrade_after_game_start(self):
        self.lua.execute('''
            p=rotating(origin,{77,88})
            actualConchResult({type='positive'})
            for i=1,20 do event(1) end
            local saved={Variant=100,SubType=origin,Position=p.Position,InitSeed=p.InitSeed,Price=0,ShopItemId=-1}
            event(5) -- exit to the menu
            assert(#ConchBlessing._upgradeJobs==0 and records()==1)
            for _,e in ipairs(entities) do e.alive=false end
            -- Continue: the room loads before the game start is seen.
            local q=comeBack(saved, origin, {})
            assert(q.SubType==origin and records()==1, 'no record is read before this run starts')
            event(4)
            assert(same(circle(q), {target,77,88}), table.concat(circle(q),','))
            assert(records()==0 and titles[1]==target and #errors==0)
        ''')

    def test_a_room_saved_before_the_hold_changes_the_choice_in_place(self):
        self.lua.execute('''
            p=rotating(origin,{77,88})
            actualConchResult({type='positive'})
            local saved={Variant=100,SubType=77,Position=p.Position,InitSeed=p.InitSeed,Price=0,ShopItemId=-1}
            leave()
            -- A crash: the game kept the room as it was before the answer.
            local q=comeBack(saved, 77, {88,origin})
            assert(same(circle(q), {77,88,target}), table.concat(circle(q),','))
            assert(records()==0 and #errors==0)
        ''')

    def test_a_changed_pedestal_drops_its_record(self):
        self.lua.execute('''
            p=rotating(origin,{77,88})
            actualConchResult({type='positive'})
            local saved={Variant=100,SubType=555,Position=p.Position,InitSeed=p.InitSeed,Price=0,ShopItemId=-1}
            leave()
            local q=comeBack(saved, 555, {})
            assert(same(circle(q), {555}) and records()==0 and #titles==0 and #morphs==0)
            -- Another pedestal at another place is not the recorded one.
            p=rotating(origin,{77})
            actualConchResult({type='positive'})
            saved={Variant=100,SubType=origin,Position=Vector(300,200),InitSeed=p.InitSeed,Price=0,ShopItemId=-1}
            leave()
            q=comeBack(saved, origin, {})
            assert(same(circle(q), {origin}) and records()==0 and #titles==0)
        ''')

    def test_unload_finishes_the_upgrade_at_once(self):
        self.lua.execute('''
            p=rotating(origin,{77,88})
            actualConchResult({type='positive'})
            for i=1,20 do event(1) end
            event(13, ConchBlessing)
            assert(same(circle(p), {target,77,88}), table.concat(circle(p),','))
            assert(#ConchBlessing._upgradeJobs==0 and records()==0 and titles[1]==target and #errors==0)
        ''')

    def test_a_hold_that_fails_queues_nothing(self):
        self.lua.execute('''
            p=rotating(origin,{77,88})
            function p:RemoveCollectibleCycle() error('refused') end
            actualConchResult({type='positive'})
            assert(#ConchBlessing._upgradeJobs==0 and records()==0)
            assert(same(circle(p), {origin,77,88}) and #errors==1, tostring(errors[1]))
        ''')

    def test_a_preview_keeps_no_record(self):
        self.lua.execute('''
            event(6,'conch_morph','void_dagger')
            for i=1,5 do event(1) end
            assert(#ConchBlessing._upgradeJobs==1 and ConchBlessing._upgradeJobs[1].preview)
            assert(records()==0)
        ''')


if __name__ == '__main__':
    unittest.main()
