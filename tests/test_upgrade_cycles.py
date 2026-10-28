"""Magic Conch upgrades on rotating pedestals through the shipped transaction.

A rotating (REPENTOGON collectible cycle) pedestal evolves only the choice on
show when the answer comes (user decision 2026-10-29), and keeps turning its
choices while the upgrade presentation plays. The engine may turn it in place or
through a native Morph, which expires the job's EntityPtr; both must still commit
that one choice wherever it has turned to. Offline doubles only:
`conch_test morph cycle` checks the engine.
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
        ''')
        harness.viewer(self)
        self.lua.execute(f'''
            debugLines={{}}
            ConchBlessing.printDebug=function(s) debugLines[#debugLines+1]=s end
            MagicConch.API.Config.deleteMode=false
            player={{ToPlayer=function(self) return self end}}
            origin=ConchBlessing.ItemData.DRAGON.origin.id
            target=ConchBlessing.ItemData.DRAGON.id
            -- A pedestal showing `head` with the queued tail `cycle`.
            function rotating(head, tail)
                local p=Isaac.Spawn(5,100,head,Vector(80,80),Vector(0,0),nil)
                p.cycle={{}}
                for i,id in ipairs(tail) do p.cycle[i]=id end
                function p:GetCollectibleCycle() local t={{}} for i,v in ipairs(self.cycle) do t[i]=v end return t end
                function p:AddCollectibleCycle(id) if #self.cycle>=8 then return false end self.cycle[#self.cycle+1]=id return true end
                function p:RemoveCollectibleCycle() self.cycle={{}} end
                entities={{p}}
                return p
            end
            -- The engine's own turn: the next choice shows, the shown one
            -- joins the end of the queue. viaMorph re-initializes the pickup
            -- like a native Morph (EntityPtr expires, GetData is replaced).
            function turn(p, viaMorph)
                local head=table.remove(p.cycle,1); p.cycle[#p.cycle+1]=p.SubType
                if not viaMorph then p.SubType=head; return end
                assert(event({MORPH_PRE},p,5,100,head,true,true,true)==nil, 'observers never cancel')
                p.SubType=head; p.data={{}}; p.generation=p.generation+1
                -- Init callbacks inside the Morph still see an animating pickup.
                insideMorph=ConchBlessing.upgrade.isAnimatingPickup(p)
                event({MORPH_POST},p,5,100,head,true,true,true)
            end
            function circle(p)
                local ids={{p.SubType}}
                for _,id in ipairs(p.cycle) do ids[#ids+1]=id end
                return ids
            end
            function sameCircle(a, b)
                if #a~=#b then return false end
                for offset=0,#a-1 do
                    local ok=true
                    for i=1,#a do if a[i]~=b[(i+offset-1)%#b+1] then ok=false break end end
                    if ok then return true end
                end
                return false
            end
            for i=1,10 do event(1) end -- Magic Conch callback registration
        ''')

    def run_rotating(self, via_morph):
        self.lua.globals().viaMorph = via_morph
        self.lua.execute('''
            p=rotating(origin,{77,88})
            actualConchResult({type='positive'})
            job=ConchBlessing._upgradeJobs[1]
            assert(job and job.cyclePlan and #ConchBlessing._upgradeJobs==1, 'rotating pedestal queued with its cycle')
            turns, lockedAfterTurn, cut = 0, true, nil
            for tick=1,220 do
                if tick%20==0 then
                    turn(p, viaMorph); turns=turns+1
                    if not job.committed then
                        lockedAfterTurn = lockedAfterTurn and event(10,p,player)==true
                        assert(not viaMorph or insideMorph, 'init callbacks inside a native Morph see the job')
                    end
                end
                event(1)
                local scene=job.templateState.morphScene
                if scene and scene.endReason and not cut then cut=scene.endReason end
            end
        ''')

    def test_turning_in_place_commits_the_choice_on_show(self):
        self.run_rotating(False)
        self.lua.execute('''
            assert(job.status=='complete' and job.committed and job.endReason=='complete', tostring(job.endReason))
            assert(#morphs==1 and turns>=5)
            assert(sameCircle(circle(p), {target,77,88}), table.concat(circle(p),','))
            assert(lockedAfterTurn and titles[1]==target and #errors==0)
        ''')

    def test_turning_through_native_morph_rebinds_and_commits(self):
        self.run_rotating(True)
        self.lua.execute('''
            assert(job.status=='complete' and job.committed and job.endReason=='complete', tostring(job.endReason))
            assert(#morphs==1 and turns>=5)
            assert(sameCircle(circle(p), {target,77,88}), table.concat(circle(p),','))
            -- The rebound job kept the pickup locked and its presentation alive.
            assert(lockedAfterTurn, 'collision lock survives the replaced GetData')
            assert(cut==nil or not cut:find('^before'), 'presentation cut before the change: '..tostring(cut))
            assert(titles[1]==target and #errors==0)
            local rebound=0
            for _,line in ipairs(debugLines) do if line:find('Native Morph rebound',1,true) then rebound=rebound+1 end end
            assert(rebound>=1)
        ''')

    def test_an_evolvable_choice_not_on_show_stays(self):
        self.lua.execute('''
            p=rotating(77,{origin,88})
            actualConchResult({type='positive'})
            assert(#ConchBlessing._upgradeJobs==0, 'only the choice on show decides')
            for tick=1,220 do
                if tick%20==0 then turn(p, false) end
                event(1)
            end
            assert(#morphs==0 and #titles==0 and #errors==0)
            assert(sameCircle(circle(p), {77,origin,88}), table.concat(circle(p),','))
        ''')

    def test_only_the_copy_on_show_evolves_and_turns_do_not_stop_it(self):
        for via_morph in (False, True):
            with self.subTest(via_morph=via_morph):
                self.lua.globals().viaMorph = via_morph
                self.lua.execute('''
                    p=rotating(origin,{77,origin})
                    actualConchResult({type='positive'})
                    job=ConchBlessing._upgradeJobs[1]
                    assert(job and #ConchBlessing._upgradeJobs==1)
                    local turned=0
                    for tick=1,220 do
                        if tick%20==0 then turn(p, viaMorph); if not job.committed then turned=turned+1 end end
                        event(1)
                    end
                    assert(turned>=2 and job.status=='complete' and job.committed, tostring(job.endReason))
                    assert(sameCircle(circle(p), {target,77,origin}), table.concat(circle(p),','))
                    assert(#errors==0)
                ''')

    def test_a_repeating_circle_changes_the_copy_on_show_at_the_commit(self):
        self.lua.execute('''
            p=rotating(origin,{77,origin,77})
            actualConchResult({type='positive'})
            job=ConchBlessing._upgradeJobs[1]
            -- Two turns bring the other copy of the evolving item on show.
            local committedShown
            for tick=1,220 do
                if tick==20 or tick==40 then turn(p, false) end
                local before=job.committed
                event(1)
                if job.committed and not before then committedShown=p.SubType end
            end
            assert(job.committed and committedShown==target, 'the copy on show changed: '..tostring(committedShown))
            assert(sameCircle(circle(p), {target,77,origin,77}), table.concat(circle(p),','))
        ''')

    def test_native_reroll_morph_cancels_and_restores_the_pedestal(self):
        self.lua.execute(f'''
            p=rotating(origin,{{77,88}})
            p.sprite.Color=Color(1,1,1,0.8); p.sprite.Color.original=true
            actualConchResult({{type='positive'}})
            job=ConchBlessing._upgradeJobs[1]
            for i=1,10 do event(1) end
            assert(not p.sprite:GetLayer(1):IsVisible(), 'presentation holds the item layer')
            -- A reroll: a native Morph to an unrelated item without the cycle.
            event({MORPH_PRE},p,5,100,555,true,true,false)
            p.SubType=555; p.cycle={{}}; p.data={{}}; p.generation=p.generation+1
            event({MORPH_POST},p,5,100,555,true,true,false)
            event(1)
            assert(job.status=='cancelled' and job.endReason=='source-changed', tostring(job.endReason))
            assert(#ConchBlessing._upgradeJobs==0 and #morphs==0 and p.SubType==555)
            assert(p.sprite.Color.original and p.sprite:GetLayer(1):IsVisible(), 'pedestal restored')
            assert(event(10,p,player)==nil, 'no stale lock')
            for i=1,200 do event(1) end
            assert(#morphs==0 and #errors==0)
        ''')

    def test_reference_lost_without_a_morph_callback_fails_closed_with_a_reason(self):
        self.lua.execute('''
            p=rotating(origin,{77,88})
            actualConchResult({type='positive'})
            job=ConchBlessing._upgradeJobs[1]
            for i=1,5 do event(1) end
            p.generation=p.generation+1 -- re-initialized without Morph callbacks
            event(1)
            assert(job.status=='cancelled' and job.endReason=='expired', tostring(job.endReason))
            local logged=false
            for _,line in ipairs(debugLines) do logged=logged or line:find('Pickup reference expired',1,true)~=nil end
            assert(logged and #morphs==0)
            for i=1,200 do event(1) end
            assert(#morphs==0 and p.SubType==origin)
        ''')

    def test_cancelled_native_morph_never_proves_a_recycled_address(self):
        self.lua.execute(f'''
            p=rotating(origin,{{77,88}})
            actualConchResult({{type='positive'}})
            job=ConchBlessing._upgradeJobs[1]
            for i=1,5 do event(1) end
            -- Another mod cancels this Morph after our PRE: POST never runs.
            event({MORPH_PRE},p,5,100,origin,true,true,true)
            p:Remove()
            local q=Isaac.Spawn(5,100,origin,p.Position,Vector(0,0),nil)
            q.pointerHash=p.pointerHash; q.InitSeed=p.InitSeed
            q.cycle={{77,88}}
            function q:GetCollectibleCycle() local t={{}} for i,v in ipairs(self.cycle) do t[i]=v end return t end
            entities={{q}}
            event({MORPH_PRE},q,5,100,origin,true,true,true)
            assert(not ConchBlessing.upgrade.isAnimatingPickup(q), 'the earlier lease ends on this address')
            q.generation=q.generation+1
            event({MORPH_POST},q,5,100,origin,true,true,true)
            event(1)
            assert(job.status=='cancelled' and job.endReason=='expired', tostring(job.endReason))
            assert(event(10,q,player)==nil and next(q:GetData())==nil, 'the recycled pickup is not claimed')
            for i=1,200 do event(1) end
            assert(#morphs==0 and q.SubType==origin)
        ''')


if __name__ == '__main__':
    unittest.main()
