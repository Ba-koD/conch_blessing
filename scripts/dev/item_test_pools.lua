-- Real engine rerolls/copies/morphs. Read-only pool observations are independent
-- of each item's implementation; no production callback is called by a test.
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")
local capture

if ModCallbacks.MC_POST_GET_COLLECTIBLE then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_GET_COLLECTIBLE, function(_, id, requested, decrease, seed)
        if not capture then return end
        local pool = Game():GetItemPool()
        capture[#capture+1] = {id=id, requested=requested, actual=pool:GetLastPool(), seed=seed, decrease=decrease}
        -- Never return a replacement or consume a pool entry in this observer.
    end)
end

local function pedestals()
    local out = {}
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, -1)) do
        out[#out+1] = entity:ToPickup()
    end
    return out
end

local function observe(ctx)
    capture = {}; ctx.draws = capture
    if not ctx.poolCleanup then
        ctx.poolCleanup=true; ctx.cleanupFns=ctx.cleanupFns or {}
        ctx.cleanupFns[#ctx.cleanupFns+1]=function() capture=nil end
    end
end

local function poolCapability(plan)
    plan.require("read-only pool provenance capabilities",function()
        local pool=Game():GetItemPool()
        return (ModCallbacks.MC_POST_GET_COLLECTIBLE~=nil
            and type(pool.GetLastPool)=="function"
            and type(pool.GetCollectiblesFromPool)=="function") or nil,
            "POST_GET_COLLECTIBLE, GetLastPool and GetCollectiblesFromPool required"
    end)
end

local function snapshotPool(poolType)
    local ids={}
    for _,entry in ipairs(Game():GetItemPool():GetCollectiblesFromPool(poolType)) do
        assert(type(entry.itemID)=="number","incompatible pool-entry schema")
        if entry.isUnlocked~=false and entry.weight>entry.removeOn then ids[entry.itemID]=true end
    end
    assert(next(ids),"expected pool has no eligible entries")
    return ids
end

local function poolResult(ctx, expected)
    local seen, detail={},{}
    for _,draw in ipairs(ctx.draws) do
        if draw.actual==expected then seen[draw.id]=true end
        detail[#detail+1]=string.format("%s@%s",draw.id,draw.actual)
    end
    local stock=pedestals()
    if #stock~=ctx.stockCount then return false,"pedestal count changed: "..#stock.." expected="..ctx.stockCount end
    for _,pickup in ipairs(stock) do
        if not seen[pickup.SubType] or not ctx.allowed[pickup.SubType] then
            return false,string.format("item=%s expectedPool=%s; draws=[%s]",pickup.SubType,expected,table.concat(detail,","))
        end
    end
    return true,string.format("%d pedestals; expectedPool=%s actualDraws=[%s]",#stock,expected,table.concat(detail,","))
end

local function visitTreasure(plan, before)
    plan.act(function(player,ctx)
        ctx.originGrid=Game():GetLevel():GetCurrentRoomIndex()
        local rooms=Game():GetLevel():GetRooms()
        for i=0,rooms.Size-1 do
            local desc=rooms:Get(i)
            if desc.Data and desc.Data.Type==RoomType.ROOM_TREASURE then
                ctx.treasureGrid,ctx.treasureIndex=desc.SafeGridIndex,desc.ListIndex
                if before then before(player,ctx) end
                Game():StartRoomTransition(desc.SafeGridIndex,Direction.NO_DIRECTION,RoomTransitionAnim.FADE,player)
                return
            end
        end
        error("test floor has no native treasure room")
    end)
    plan.waitUntil(function(_,ctx) return Game():GetLevel():GetCurrentRoomDesc().ListIndex==ctx.treasureIndex end,180,"native treasure entry")
    plan.wait(4)
    plan.require("native treasure stock exists",function(_,ctx)
        ctx.stockCount=#pedestals()
        return ctx.stockCount>0,"pedestals="..ctx.stockCount
    end)
end

local function signature()
    local rows={}
    for _,p in ipairs(pedestals()) do
        local ids={p.SubType}
        if type(p.GetCollectibleCycle)=="function" then
            for _,id in ipairs(p:GetCollectibleCycle()) do ids[#ids+1]=id end
        end
        table.sort(ids)
        rows[#rows+1]=table.concat(ids,",").."@"..p.Price..":"..p.OptionsPickupIndex
    end
    table.sort(rows); return table.concat(rows,"|")
end

local function revisit(plan)
    plan.act(function(player,ctx)
        ctx.stockSignature=signature()
        Game():StartRoomTransition(ctx.originGrid,Direction.NO_DIRECTION,RoomTransitionAnim.FADE,player)
    end)
    plan.waitUntil(function(_,ctx) return Game():GetLevel():GetCurrentRoomIndex()==ctx.originGrid end,180,"leave stock room")
    plan.act(function(player,ctx) Game():StartRoomTransition(ctx.treasureGrid,Direction.NO_DIRECTION,RoomTransitionAnim.FADE,player) end)
    plan.waitUntil(function(_,ctx) return Game():GetLevel():GetCurrentRoomDesc().ListIndex==ctx.treasureIndex end,180,"revisit stock room")
    plan.wait(4)
    plan.check("revisit preserves item/cycle identities, prices and option groups",function(_,ctx)
        local actual=signature(); return actual==ctx.stockSignature,"actual="..actual.." expected="..ctx.stockSignature
    end)
end

local function deals(plan,label)
    plan.check(label.." coin prices remain owned",function()
        for _,p in ipairs(pedestals()) do
            local c=Isaac.GetItemConfig():GetCollectible(p.SubType)
            local price=c and c.ShopPrice and c.ShopPrice>0 and math.floor(c.ShopPrice) or 15
            if p.Price~=price or p.ShopItemId~=-1 or p.AutoUpdatePrice then
                return false,string.format("item=%s price=%s expected=%s shop=%s auto=%s",p.SubType,p.Price,price,p.ShopItemId,tostring(p.AutoUpdatePrice))
            end
        end
        return true,"individual item price; ShopItemId=-1; AutoUpdatePrice=false"
    end)
end

S.add("ANGELS_CROWN","dice_pool",{conditions=true},function(plan,id)
    poolCapability(plan)
    plan.act(function(player) player:AddTrinket(id,false) end)
    visitTreasure(plan,function(_,ctx) ctx.allowed=snapshotPool(ItemPoolType.POOL_ANGEL); observe(ctx) end)
    plan.check("initial conversion actually draws from Angel pool",function(_,ctx) return poolResult(ctx,ItemPoolType.POOL_ANGEL) end)
    deals(plan,"conversion")
    for roll=1,4 do
        plan.section("ANGELS_CROWN / reroll "..roll)
        plan.act(function(player,ctx)
            if roll==4 then assert(player:TryRemoveTrinket(id),"remove crown") end
            ctx.allowed=snapshotPool(ItemPoolType.POOL_ANGEL); observe(ctx)
            player:UseActiveItem(roll==3 and CollectibleType.COLLECTIBLE_D100 or CollectibleType.COLLECTIBLE_D6,UseFlag.USE_NOANIM,-1)
        end)
        plan.wait(4)
        plan.check("reroll "..roll.." uses Angel pool (including D100 and owner loss)",function(_,ctx) return poolResult(ctx,ItemPoolType.POOL_ANGEL) end)
        deals(plan,"reroll "..roll)
    end
    revisit(plan)
end)

S.add("INF_D6","dice_pool",{conditions=true},function(plan,id)
    poolCapability(plan)
    visitTreasure(plan)
    plan.act(function(player) player:AddCollectible(id,0,false) end)
    for roll=1,3 do
        plan.act(function(player,ctx)
            ctx.allowed=snapshotPool(ItemPoolType.POOL_TREASURE); observe(ctx); H.use(player,id)
        end)
        plan.wait(3)
        plan.check("activation "..roll.." produces real Treasure pool stock",function(player,ctx)
            if player:GetActiveItem(ActiveSlot.SLOT_PRIMARY)~=id then return false,"infinite active consumed" end
            return poolResult(ctx,ItemPoolType.POOL_TREASURE)
        end)
    end
    plan.act(function(player,ctx)
        player:RemoveCollectible(id,true,ActiveSlot.SLOT_PRIMARY)
        ctx.allowed=snapshotPool(ItemPoolType.POOL_TREASURE); observe(ctx)
        player:UseActiveItem(CollectibleType.COLLECTIBLE_D6,UseFlag.USE_NOANIM,-1)
    end)
    plan.wait(3)
    plan.check("removed infinite D6 leaves vanilla reroll working",function(_,ctx) return poolResult(ctx,ItemPoolType.POOL_TREASURE) end)
    revisit(plan)
end)

local function cycleCapability(plan)
    plan.require("collectible cycle capability",function()
        local p=pedestals()[1]
        return (p and type(p.GetCollectibleCycle)=="function") or nil,"REPENTOGON cycle inspection required"
    end)
end

local function cycleCount(plan,label,count)
    plan.check(label,function()
        for _,p in ipairs(pedestals()) do
            if #p:GetCollectibleCycle()~=count then
                return false,string.format("item=%s cycle=%s expected=%s",p.SubType,#p:GetCollectibleCycle(),count)
            end
        end
        return #pedestals()>0,"each pedestal has exactly "..count.." alternate choice(s)"
    end)
end

S.add("SEVERED_OATH","dice_copy_split",{conditions=true},function(plan,id)
    poolCapability(plan)
    plan.act(function(player,ctx) H.suppressRandomGoldenPedestals(ctx); player:AddCollectible(id,0,false) end)
    visitTreasure(plan)
    cycleCapability(plan)
    cycleCount(plan,"new stock gains one alternate",1)
    for roll=1,3 do
        plan.act(function(player) player:UseActiveItem(roll==3 and CollectibleType.COLLECTIBLE_D100 or CollectibleType.COLLECTIBLE_D6,UseFlag.USE_NOANIM,-1) end)
        plan.wait(4)
        plan.require("dice preserve the held active",function(player) return player:GetActiveItem(ActiveSlot.SLOT_PRIMARY)==id,"Severed Oath still held after reroll "..roll end)
        cycleCount(plan,"repeated D6/D100 keeps exactly one alternate: "..roll,1)
    end
    plan.act(function(player,ctx)
        ctx.beforeCopy=#pedestals()
        player:UseActiveItem(CollectibleType.COLLECTIBLE_DIPLOPIA,UseFlag.USE_NOANIM,-1)
    end)
    plan.wait(4)
    plan.check("Diplopia copies each pedestal exactly once",function(_,ctx) return H.expect(#pedestals(),2*ctx.beforeCopy) end)
    cycleCount(plan,"copied stock does not accumulate extra cycles",1)
    plan.act(function(_,ctx)
        ctx.morphed=pedestals()[1]
        ctx.morphed:Morph(EntityType.ENTITY_PICKUP,PickupVariant.PICKUP_COLLECTIBLE,CollectibleType.COLLECTIBLE_SAD_ONION,true,true,true)
    end)
    plan.wait(4)
    cycleCount(plan,"explicit pedestal morph stays bounded to one alternate",1)
    revisit(plan)
    plan.act(function(player,ctx)
        ctx.expectedSplit={}; ctx.expectedSplitCount=0
        ctx.splitSources=#pedestals()
        for _,p in ipairs(pedestals()) do
            p.OptionsPickupIndex=777
            local ids={[p.SubType]=true}
            for _,cid in ipairs(p:GetCollectibleCycle()) do ids[cid]=true end
            for cid in pairs(ids) do ctx.expectedSplit[cid]=(ctx.expectedSplit[cid] or 0)+1; ctx.expectedSplitCount=ctx.expectedSplitCount+1 end
        end
        observe(ctx); H.use(player,id)
    end)
    plan.wait(4)
    plan.check("split materializes the exact existing choices without new pool draws",function(_,ctx)
        local actual={}
        for _,p in ipairs(pedestals()) do actual[p.SubType]=(actual[p.SubType] or 0)+1 end
        if #pedestals()~=ctx.expectedSplitCount or #ctx.draws~=0 then
            return false,string.format("pedestals=%d expected=%d; new draws=%d expected=0",#pedestals(),ctx.expectedSplitCount,#ctx.draws)
        end
        for cid,n in pairs(ctx.expectedSplit) do if actual[cid]~=n then return false,"split item count differs: "..cid end end
        return true,"exact choice multiset; zero new pool selections"
    end)
    cycleCount(plan,"split products remain independent",0)
    plan.check("linked source choices split into two parallel option groups",function(_,ctx)
        local groups={}
        for _,p in ipairs(pedestals()) do
            if p.OptionsPickupIndex==0 then return false,"lost source choice linkage" end
            groups[p.OptionsPickupIndex]=(groups[p.OptionsPickupIndex] or 0)+1
        end
        local n=0
        for _,count in pairs(groups) do
            n=n+1
            if count~=ctx.splitSources then return false,"option group size="..count.." expected="..ctx.splitSources end
        end
        return H.expect(n,2)
    end)
    plan.act(function(player) H.use(player,id) end)
    plan.wait(3)
    plan.check("second use cannot duplicate already split items",function(_,ctx) return H.expect(#pedestals(),ctx.expectedSplitCount) end)
    plan.act(function(player)
        for _,p in ipairs(pedestals()) do p:Remove() end
        player:RemoveCollectible(id,true,ActiveSlot.SLOT_PRIMARY)
        H.pickup(player,CollectibleType.COLLECTIBLE_BREAKFAST)
    end)
    plan.wait(3)
    cycleCount(plan,"new unowned pedestal receives no extra choice",0)
    plan.act(function(player)
        player:AddCollectible(id,0,false)
        player:UseActiveItem(CollectibleType.COLLECTIBLE_D6,UseFlag.USE_NOANIM,-1)
    end)
    plan.wait(4)
    cycleCount(plan,"reacquisition followed by D6 creates one new alternate",1)
end)

local function cycleSnapshot(p)
    local counts = {[p.SubType]=1}
    local total = 1
    for _, id in ipairs(p:GetCollectibleCycle()) do counts[id]=(counts[id] or 0)+1; total=total+1 end
    return {counts=counts,total=total}
end

local function addedChoices(ctx, extra)
    local stock = pedestals()
    if #stock~=1 then return false,"expected one pedestal, actual="..#stock end
    local after=cycleSnapshot(stock[1])
    if after.total~=ctx.beforeCycle.total+extra then
        return false,string.format("choices=%d expected=%d (existing=%d + bonus=%d)",
            after.total,ctx.beforeCycle.total+extra,ctx.beforeCycle.total,extra)
    end
    for id,n in pairs(ctx.beforeCycle.counts) do
        if (after.counts[id] or 0)<n then return false,"lost pre-existing cycle member "..id end
    end
    return true,string.format("existing=%d; added=%d; all existing members retained",ctx.beforeCycle.total,extra)
end

local function reenterTreasure(plan)
    plan.act(function(player,ctx) Game():StartRoomTransition(ctx.originGrid,Direction.NO_DIRECTION,RoomTransitionAnim.FADE,player) end)
    plan.waitUntil(function(_,ctx) return Game():GetLevel():GetCurrentRoomIndex()==ctx.originGrid end,180,"leave stock room")
    plan.act(function(player,ctx) Game():StartRoomTransition(ctx.treasureGrid,Direction.NO_DIRECTION,RoomTransitionAnim.FADE,player) end)
    plan.waitUntil(function(_,ctx) return Game():GetLevel():GetCurrentRoomDesc().ListIndex==ctx.treasureIndex end,180,"re-enter held-item room")
    plan.wait(4)
end

S.add("SEVERED_OATH","cycle_stacking",{conditions=true,synergies=true},function(plan,id)
    plan.act(function(_,ctx) H.suppressRandomGoldenPedestals(ctx) end)
    visitTreasure(plan)
    cycleCapability(plan)
    local crown,binge,birthright=CollectibleType.COLLECTIBLE_GLITCHED_CROWN,CollectibleType.COLLECTIBLE_BINGE_EATER,CollectibleType.COLLECTIBLE_BIRTHRIGHT
    for _,case in ipairs({{name="Glitched Crown",items={crown},tail=4},
        {name="Binge Eater",items={binge},tail=1},
        {name="Glitched Crown + Binge Eater",items={crown,binge}},
        -- Isaac Birthright cycles between two options (one alternate), as
        -- described by the installed EID and observed before Oath is held.
        {name="Isaac Birthright",items={birthright},tail=1}}) do
        plan.section("SEVERED_OATH / "..case.name)
        plan.act(function(player)
            for _,p in ipairs(pedestals()) do p:Remove() end
            for _,item in ipairs({id,crown,binge,birthright}) do
                while player:HasCollectible(item) do player:RemoveCollectible(item,true) end
            end
            for _,item in ipairs(case.items) do player:AddCollectible(item,0,false) end
        end)
        plan.wait(4) -- settle removal of the previous native cycle modifiers
        plan.act(function(player)
            H.pickup(player,CollectibleType.COLLECTIBLE_BREAKFAST)
        end)
        plan.wait(4)
        plan.require(case.name.." native baseline before Severed Oath",function(player,ctx)
            local p=pedestals()[1]; ctx.beforeCycle=cycleSnapshot(p)
            local tail=ctx.beforeCycle.total-1
            local valid=not player:HasCollectible(id)
                and (case.tail==nil and tail>=4 or tail==case.tail)
            return valid,"native alternate count="..tail.."; player type="..player:GetPlayerType()
        end)
        plan.act(function(player) player:AddCollectible(id,0,false) end)
        reenterTreasure(plan)
        plan.check(case.name.." existing room gains exactly +1 on entry",function(_,ctx) return addedChoices(ctx,1) end)
        revisit(plan)
        plan.act(function(player) player:UseActiveItem(CollectibleType.COLLECTIBLE_D6,UseFlag.USE_NOANIM,-1) end)
        plan.wait(4)
        plan.check(case.name.." D6 preserves total cycle size",function(_,ctx)
            return H.expect(#pedestals()[1]:GetCollectibleCycle()+1,ctx.beforeCycle.total+1)
        end)
        plan.act(function(player) player:RemoveCollectible(id,true,ActiveSlot.SLOT_PRIMARY) end)
        revisit(plan)
    end
end)

S.add("SEVERED_OATH","golden_cycle",{conditions=true,synergies=true},function(plan,id)
    plan.require("Golden Items held-active query, upgrade and downgrade APIs",function(_,ctx)
        ctx.goldProvider=Epiphany and type(Epiphany.HasGoldenItem)=="function" and Epiphany or GoldenItems
        local provider=ctx.goldProvider
        return (provider and type(provider.HasGoldenItem)=="function"
            and type(provider.SetGoldenItem)=="function" and type(provider.ExaustGoldenItem)=="function") or nil,
            "optional Golden Items/Epiphany held-active provider required"
    end)
    plan.act(function(_,ctx) H.suppressRandomGoldenPedestals(ctx) end)
    visitTreasure(plan)
    cycleCapability(plan)
    plan.act(function(player,ctx)
        local provider=ctx.goldProvider
        local wasGolden=provider:HasGoldenItem(id,player,ActiveSlot.SLOT_PRIMARY)==true
        ctx.cleanupFns=ctx.cleanupFns or {}
        ctx.cleanupFns[#ctx.cleanupFns+1]=function()
            if wasGolden then provider:SetGoldenItem(id,player,ActiveSlot.SLOT_PRIMARY)
            else provider:ExaustGoldenItem(id,player,ActiveSlot.SLOT_PRIMARY) end
        end
    end)
    for _,native in ipairs({false,true}) do
        plan.section("SEVERED_OATH / golden held active"..(native and " + Glitched Crown" or ""))
        plan.act(function(player,ctx)
            for _,p in ipairs(pedestals()) do p:Remove() end
            if player:HasCollectible(id) then player:RemoveCollectible(id,true,ActiveSlot.SLOT_PRIMARY) end
            ctx.goldProvider:ExaustGoldenItem(id,player,ActiveSlot.SLOT_PRIMARY)
            if native then player:AddCollectible(CollectibleType.COLLECTIBLE_GLITCHED_CROWN,0,false) end
        end)
        plan.wait(4)
        plan.act(function(player) H.pickup(player,CollectibleType.COLLECTIBLE_BREAKFAST) end)
        plan.wait(4)
        plan.require("native choices before holding the active",function(_,ctx)
            ctx.beforeCycle=cycleSnapshot(pedestals()[1])
            return H.expect(ctx.beforeCycle.total,native and 5 or 1)
        end)
        plan.act(function(player) player:AddCollectible(id,0,false) end)
        reenterTreasure(plan)
        plan.check("normal held active gives +1 regardless of target gold",function(_,ctx) return addedChoices(ctx,1) end)
        plan.act(function(player,ctx) ctx.goldProvider:SetGoldenItem(id,player,ActiveSlot.SLOT_PRIMARY) end)
        plan.wait(4)
        plan.require("provider confirms held Severed Oath upgrade",function(player,ctx)
            return ctx.goldProvider:HasGoldenItem(id,player,ActiveSlot.SLOT_PRIMARY)==true,
                "golden state must belong to the held active"
        end)
        plan.check("golden held active increases committed bonus to +2 once",function(_,ctx) return addedChoices(ctx,2) end)
        revisit(plan)
        plan.act(function(player) player:UseActiveItem(CollectibleType.COLLECTIBLE_D6,UseFlag.USE_NOANIM,-1) end)
        plan.wait(4)
        plan.check("D6 keeps +2 from held-active golden state",function()
            return H.expect(#pedestals()[1]:GetCollectibleCycle()+1,(native and 5 or 1)+2)
        end)
        plan.act(function(player,ctx)
            ctx.goldProvider:ExaustGoldenItem(id,player,ActiveSlot.SLOT_PRIMARY)
        end)
        plan.wait(3)
        plan.check("downgrade preserves already committed choices",function()
            return H.expect(#pedestals()[1]:GetCollectibleCycle()+1,(native and 5 or 1)+2)
        end)
        plan.act(function(player)
            for _,p in ipairs(pedestals()) do p:Remove() end
            H.pickup(player,CollectibleType.COLLECTIBLE_BREAKFAST)
        end)
        plan.wait(4)
        plan.check("new stock after downgrade receives only +1",function()
            return H.expect(#pedestals()[1]:GetCollectibleCycle()+1,(native and 5 or 1)+1)
        end)
        plan.act(function(player)
            player:RemoveCollectible(id,true,ActiveSlot.SLOT_PRIMARY)
            for _,p in ipairs(pedestals()) do p:Remove() end
            H.pickup(player,CollectibleType.COLLECTIBLE_BREAKFAST)
        end)
        plan.wait(4)
        plan.check("removal stops bonuses for new stock",function()
            return H.expect(#pedestals()[1]:GetCollectibleCycle()+1,native and 5 or 1)
        end)
        plan.act(function(player) player:AddCollectible(id,0,false) end)
        reenterTreasure(plan)
        plan.check("normal reacquisition gains +1 without stale gold",function()
            return H.expect(#pedestals()[1]:GetCollectibleCycle()+1,(native and 5 or 1)+1)
        end)
        plan.act(function(player,ctx)
            ctx.goldProvider:SetGoldenItem(id,player,ActiveSlot.SLOT_PRIMARY)
        end)
        plan.wait(3)
        plan.act(function(player,ctx)
            ctx.goldenSplitChoices=cycleSnapshot(pedestals()[1]).counts
            player:UseActiveItem(id,UseFlag.USE_NOANIM,ActiveSlot.SLOT_PRIMARY)
        end)
        plan.wait(4)
        plan.check("golden active use splits choices without duplicating split products",function(_,ctx)
            local actual,expectedCount={},0
            for _,p in ipairs(pedestals()) do
                actual[p.SubType]=(actual[p.SubType] or 0)+1
                if #p:GetCollectibleCycle()~=0 then return false,"split product regrew choices" end
            end
            -- A split materializes each distinct choice once, even if a foreign
            -- cycle contains duplicates. The original cycle is never deduplicated.
            for item in pairs(ctx.goldenSplitChoices) do
                expectedCount=expectedCount+1
                if actual[item]~=1 then return false,"split item "..item.." count="..tostring(actual[item]) end
            end
            return H.expect(#pedestals(),expectedCount)
        end)
        plan.act(function(player,ctx)
            ctx.goldProvider:ExaustGoldenItem(id,player,ActiveSlot.SLOT_PRIMARY)
            player:RemoveCollectible(id,true,ActiveSlot.SLOT_PRIMARY)
        end)
        revisit(plan)
    end
end)

S.add("ATROPOS","dice_options",{conditions=true},function(plan,id)
    visitTreasure(plan)
    plan.act(function(player,ctx)
        for _,p in ipairs(pedestals()) do p:Remove() end
        ctx.options={H.pickup(player,CollectibleType.COLLECTIBLE_BREAKFAST),H.pickup(player,CollectibleType.COLLECTIBLE_DINNER)}
        for i,p in ipairs(ctx.options) do p.Position=p.Position+Vector(0,60*(i-1)); p.OptionsPickupIndex=777 end
        player:AddTrinket(id,false)
    end)
    plan.wait(4)
    for roll=1,3 do
        plan.act(function(player)
            player:UseActiveItem(roll==2 and CollectibleType.COLLECTIBLE_D100 or CollectibleType.COLLECTIBLE_D6,UseFlag.USE_NOANIM,-1)
        end)
        plan.wait(4)
        plan.check("D6/D100 preserves all choices while owned: "..roll,function()
            for _,p in ipairs(pedestals()) do if p.OptionsPickupIndex~=0 then return false,"unexpected linked group="..p.OptionsPickupIndex end end
            return H.expect(#pedestals(),2)
        end)
    end
    plan.act(function(player) assert(player:TryRemoveTrinket(id),"remove Atropos") end)
    plan.wait(3)
    plan.check("owner loss after rerolls restores original choice group",function()
        for _,p in ipairs(pedestals()) do if p.OptionsPickupIndex~=777 then return false,"actual="..p.OptionsPickupIndex.." expected=777" end end
        return true,"both pedestals restored to original option 777"
    end)
    revisit(plan)
    plan.act(function(player) player:AddTrinket(id,false); player:UseActiveItem(CollectibleType.COLLECTIBLE_DIPLOPIA,UseFlag.USE_NOANIM,-1) end)
    plan.wait(4)
    plan.check("reacquisition and Diplopia keep all four choices independent",function()
        for _,p in ipairs(pedestals()) do if p.OptionsPickupIndex~=0 then return false,"linked copy" end end
        return H.expect(#pedestals(),4)
    end)
    plan.act(function()
        pedestals()[1]:Morph(EntityType.ENTITY_PICKUP,PickupVariant.PICKUP_COLLECTIBLE,CollectibleType.COLLECTIBLE_SAD_ONION,true,true,true)
    end)
    plan.wait(3)
    plan.check("morph retains independent options",function()
        for _,p in ipairs(pedestals()) do if p.OptionsPickupIndex~=0 then return false,"morphed option linked" end end
        return true,"all option groups remain zero"
    end)
end)

return S
