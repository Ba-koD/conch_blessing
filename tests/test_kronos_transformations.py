"""Transformation (set) progress of familiars Kronos and Thurisaz absorb.

Production Kronos Lua against a player double whose transformation counters
follow the engine rule measured in game on 2026-10-29
(`conch_test kronos transformation_engine`): a first pickup adds one per tag,
including duplicate copies; AddCollectible with FirstTimePickingUp false adds
none; RemoveCollectible takes one back per tag unless RemoveFromPlayerForm is
false, even from a copy that never counted; IncrementPlayerFormCounter moves the
counter; a counter of 3 or more is the transformation. The in-game
`conch_test kronos transformation_*` benches read the real counters.
"""
import unittest

import test_kronos_regressions as regressions


class KronosTransformationTests(unittest.TestCase):
    def setUp(self):
        regressions.KronosPerPlayerLedgerTests.setUp(self)
        self.lua.execute(r"""
            DRY,GB,ALTAR=C.COLLECTIBLE_DRY_BABY,C.COLLECTIBLE_GB_BUG,C.COLLECTIBLE_SACRIFICIAL_ALTAR
            PlayerForm={PLAYERFORM_BABY=7,PLAYERFORM_LORD_OF_THE_FLIES=1}
            ItemConfig={TAG_BABY=1<<9,TAG_FLY=1<<6}
            BABY=PlayerForm.PLAYERFORM_BABY
            local tags={[BOBBY]=ItemConfig.TAG_BABY,[ANGEL]=ItemConfig.TAG_BABY,[ROBO]=ItemConfig.TAG_BABY,
                [DRY]=ItemConfig.TAG_BABY,[GB]=0,[TECH]=0}
            local familiarIds={[BOBBY]=true,[ANGEL]=true,[ROBO]=true,[DRY]=true,[GB]=true}
            Isaac.GetItemConfig=function()
                return {GetCollectible=function(_,id)
                    if familiarIds[id] or tags[id] then
                        return {ID=id,Type=familiarIds[id] and ItemType.ITEM_FAMILIAR or 0,
                            HasTags=function(_,tag) return (tags[id] or 0)&tag~=0 end}
                    end
                end}
            end
            K._familiarCollectibleIds=nil
            local forms={[BABY]=ItemConfig.TAG_BABY,[PlayerForm.PLAYERFORM_LORD_OF_THE_FLIES]=ItemConfig.TAG_FLY}
            function counting(p)
                p.forms={}
                local add,remove=p.AddCollectible,p.RemoveCollectible
                local function each(id,fn)
                    for form,tag in pairs(forms) do if (tags[id] or 0)&tag~=0 then fn(form) end end
                end
                function p:AddCollectible(id,charge,firstTime)
                    add(self,id)
                    if firstTime~=false then each(id,function(f) self.forms[f]=(self.forms[f] or 0)+1 end) end
                end
                function p:RemoveCollectible(id,ignore,slot,fromForm)
                    local had=self:GetCollectibleNum(id)
                    remove(self,id)
                    if had>0 and fromForm~=false then
                        each(id,function(f) self.forms[f]=math.max(0,(self.forms[f] or 0)-1) end)
                    end
                end
                function p:GetPlayerFormCounter(f) return self.forms[f] or 0 end
                function p:IncrementPlayerFormCounter(f,n) self.forms[f]=math.max(0,(self.forms[f] or 0)+n) end
                function p:HasPlayerForm(f) return (self.forms[f] or 0)>=3 end
                return p
            end
            counting(player); counting(two)
            function baby(p) return (p or player):GetPlayerFormCounter(BABY) end
            -- A real pickup: first time, so it counts.
            function pickUp(id,p) (p or player):AddCollectible(id,0,true) end
            function settle(p) for _=1,3 do update(p or player) end end
        """)

    def test_absorbing_keeps_progress_picked_up_before_kronos(self):
        self.lua.execute("""
            player.inventory[9999]=nil
            pickUp(BOBBY); assert(baby()==1)
            player.inventory[9999]=1; settle()
            assert(player:GetCollectibleNum(BOBBY)==0 and K._getAbsorbedCount(player,BOBBY)==1)
            assert(baby()==1,'absorbing Bobby took its Conjoined progress')
            player:RemoveCollectible(9999); settle()
            assert(player:GetCollectibleNum(BOBBY)==1)
            assert(baby()==1,'the returned Bobby counted twice or not at all: '..baby())
        """)

    def test_absorbing_keeps_progress_picked_up_after_kronos(self):
        self.lua.execute("""
            pickUp(BOBBY); settle()
            assert(K._getAbsorbedCount(player,BOBBY)==1 and baby()==1)
            player:RemoveCollectible(9999); settle()
            assert(player:GetCollectibleNum(BOBBY)==1 and baby()==1)
        """)

    def test_absorbed_familiars_add_to_existing_progress_and_complete_at_three(self):
        self.lua.execute("""
            pickUp(BOBBY); pickUp(ANGEL); settle()
            assert(baby()==2 and not player:HasPlayerForm(BABY))
            pickUp(DRY); settle()
            assert(K._getAbsorbedCount(player,DRY)==1)
            assert(baby()==3 and player:HasPlayerForm(BABY),'the third absorbed baby lost Conjoined')
            player:RemoveCollectible(9999); settle()
            assert(baby()==3 and player:HasPlayerForm(BABY),'release changed the completed set')
            -- Picking Kronos up again absorbs the returned copies without touching the count.
            player.inventory[9999]=1; settle()
            assert(K._getAbsorbedCount(player,BOBBY)==1 and baby()==3)
        """)

    def test_duplicate_copies_count_as_the_engine_counts_them(self):
        self.lua.execute("""
            pickUp(BOBBY); pickUp(BOBBY); settle()
            assert(K._getAbsorbedCount(player,BOBBY)==2 and baby()==2)
            player:RemoveCollectible(9999); settle()
            assert(player:GetCollectibleNum(BOBBY)==2 and baby()==2)
        """)

    def test_gb_bug_hands_back_without_counting_twice(self):
        self.lua.execute("""
            pickUp(BOBBY); pickUp(ANGEL); settle()
            assert(K._releaseRandomHalf(player)==1)
            assert(player:GetCollectibleNum(BOBBY)+player:GetCollectibleNum(ANGEL)==1)
            assert(baby()==2,'GB Bug release changed the count: '..baby())
            settle(); assert(baby()==2)
        """)

    def test_temporary_absorption_adds_no_progress(self):
        self.lua.execute("""
            pickUp(BOBBY); settle()
            useBox()
            assert(baby()==1,'Box of Friends added progress')
            -- A Monster Manual familiar is a temporary effect, never a collectible.
            local rs=ledger(player)
            rs.tempFloor={serial=0,counts={['fam_'..ANGEL]=1},grants={}}
            K.onNewLevel(); settle()
            assert(baby()==1,'a temporary familiar moved the count: '..baby())
        """)

    def test_a_used_up_absorbed_familiar_gives_its_count_back(self):
        self.lua.execute("""
            pickUp(ROBO); settle()
            assert(player:GetCollectibleNum(TECH)==1 and baby()==1)
            player:RemoveCollectible(TECH); settle()
            assert(K._getAbsorbedCount(player,ROBO)==0,'losing Technology used up Robo-Baby')
            assert(baby()==0,'the used-up Robo-Baby kept its count')
        """)

    def test_without_the_counter_api_a_used_up_familiar_keeps_its_count(self):
        self.lua.execute("""
            player.IncrementPlayerFormCounter=nil
            pickUp(ROBO); settle()
            player:RemoveCollectible(TECH); settle()
            assert(K._getAbsorbedCount(player,ROBO)==0 and baby()==1)
        """)

    def test_altar_sacrifice_of_absorbed_familiars_gives_their_count_back(self):
        self.lua.execute("""
            Game().GetItemPool=function() return {GetCollectible=function() return 1 end} end
            player.Position=setmetatable({X=0,Y=0},{__add=function(a) return a end})
            pickUp(BOBBY); pickUp(DRY); settle()
            assert(baby()==2)
            local rng={RandomInt=function() return 0 end,Next=function() return 7 end}
            callbacks[ModCallbacks.MC_PRE_USE_ITEM][ALTAR](nil,ALTAR,rng,player)
            callbacks[ModCallbacks.MC_USE_ITEM][ALTAR](nil,ALTAR,rng,player)
            assert(K._getAbsorbedCount(player,BOBBY)+K._getAbsorbedCount(player,DRY)==0)
            assert(#spawned==2,'one devil item per sacrifice')
            assert(baby()==0,'sacrificed absorbed familiars kept their count: '..baby())
        """)

    def test_withdraw_never_takes_more_than_the_counter_holds(self):
        self.lua.execute("""
            pickUp(BOBBY); settle()
            player.forms[BABY]=0
            player:RemoveCollectible(9999); settle()
            assert(player:GetCollectibleNum(BOBBY)==1 and baby()==0)
        """)

    def test_a_familiar_in_two_sets_keeps_and_gives_back_both(self):
        self.lua.execute("""
            FLY=PlayerForm.PLAYERFORM_LORD_OF_THE_FLIES
            -- Dry Baby stands in for a familiar the runtime tags put in two sets.
            local config=Isaac.GetItemConfig
            Isaac.GetItemConfig=function()
                local inner=config()
                return {GetCollectible=function(self,id)
                    local item=inner:GetCollectible(id)
                    if item and id==DRY then
                        item.HasTags=function(_,tag) return tag==ItemConfig.TAG_BABY or tag==ItemConfig.TAG_FLY end
                    end
                    return item
                end}
            end
            local add,remove=player.AddCollectible,player.RemoveCollectible
            function player:AddCollectible(id,charge,firstTime)
                add(self,id,charge,firstTime)
                if id==DRY and firstTime~=false then self.forms[FLY]=(self.forms[FLY] or 0)+1 end
            end
            function player:RemoveCollectible(id,ignore,slot,fromForm)
                local had=self:GetCollectibleNum(id)
                remove(self,id,ignore,slot,fromForm)
                if id==DRY and had>0 and fromForm~=false then self.forms[FLY]=math.max(0,(self.forms[FLY] or 0)-1) end
            end
            local function fly() return player:GetPlayerFormCounter(FLY) end
            pickUp(DRY); assert(baby()==1 and fly()==1)
            settle()
            assert(K._getAbsorbedCount(player,DRY)==1 and baby()==1 and fly()==1,'absorbing lost a set')
            player:RemoveCollectible(9999); settle()
            assert(player:GetCollectibleNum(DRY)==1 and baby()==1 and fly()==1,'release counted a set twice')
            player.inventory[9999]=1; settle()
            assert(K._getAbsorbedCount(player,DRY)==1 and baby()==1 and fly()==1)
            Game().GetItemPool=function() return {GetCollectible=function() return 1 end} end
            player.Position=setmetatable({X=0,Y=0},{__add=function(a) return a end})
            local rng={RandomInt=function() return 0 end,Next=function() return 7 end}
            callbacks[ModCallbacks.MC_PRE_USE_ITEM][ALTAR](nil,ALTAR,rng,player)
            callbacks[ModCallbacks.MC_USE_ITEM][ALTAR](nil,ALTAR,rng,player)
            assert(baby()==0 and fly()==0,'a sacrifice left a set behind: baby='..baby()..' fly='..fly())
        """)

    def test_each_players_progress_is_their_own(self):
        self.lua.execute("""
            pickUp(BOBBY); pickUp(ANGEL,two); settle(); settle(two)
            assert(baby()==1 and baby(two)==1)
            player:RemoveCollectible(9999); settle(); settle(two)
            assert(baby()==1 and baby(two)==1)
        """)


class ThurisazTransformationTests(unittest.TestCase):
    def setUp(self):
        import test_thurisaz
        test_thurisaz.ThurisazTests.setUp(self)
        self.lua.execute(r"""
            PlayerForm={PLAYERFORM_BABY=7}
            ItemConfig={TAG_BABY=1<<9}
            removedWith={}
            local remove=player.RemoveCollectible
            function player:RemoveCollectible(id,ignore,slot,fromForm)
                removedWith[#removedWith+1]={id=id,fromForm=fromForm}
                remove(self,id)
            end
        """)

    def test_devouring_an_owned_familiar_keeps_its_progress(self):
        self.lua.execute("""
            dropKronos()
            local bobby=owned('BROTHER_BOBBY')
            assert(K.devourWithRune(player,1,first)==1)
            assert(player:GetCollectibleNum(bobby)==0)
            assert(#removedWith==1 and removedWith[1].id==bobby and removedWith[1].fromForm==false,
                'Thurisaz removed Bobby with RemoveFromPlayerForm on')
        """)


if __name__ == "__main__":
    unittest.main()
