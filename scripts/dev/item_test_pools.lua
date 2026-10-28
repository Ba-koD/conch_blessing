local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
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

-- The Oath's own grant record for a pedestal (its seed-keyed pickup save).
local function oathGrants(p)
    local saves=ConchBlessing.SaveManager
    local ok,save=pcall(saves.TryGetNoRerollPickupSave,p)
    local state=ok and type(save)=="table" and save.severedOath or nil
    local items={}
    if type(state)=="table" and type(state.bonusItems)=="table" then
        for _,cid in ipairs(state.bonusItems) do items[#items+1]=cid end
    end
    return items
end

-- A grant whose paid draw differed from its preview, still waiting to swap
-- the queued preview ID for the paid one (no further draw).
local function oathPending(p)
    local ok,save=pcall(ConchBlessing.SaveManager.TryGetNoRerollPickupSave,p)
    local state=ok and type(save)=="table" and save.severedOath or nil
    local swap=type(state)=="table" and state.pendingSwap or nil
    return type(swap)=="table" and {from=swap.from,to=swap.to,slot=swap.slot} or nil
end

local function circleHas(p,cid)
    if p.SubType==cid then return true end
    for _,other in ipairs(p:GetCollectibleCycle()) do if other==cid then return true end end
    return false
end

-- Every pedestal's seed and the room, right before a dice roll.
local function markRoll(ctx)
    ctx.rollSeeds,ctx.rollSeedList={},{}
    ctx.rollRoom=Game():GetLevel():GetCurrentRoomDesc().ListIndex
    for _,p in ipairs(pedestals()) do
        ctx.rollSeeds[p.InitSeed]=true; ctx.rollSeedList[#ctx.rollSeedList+1]=tostring(p.InitSeed)
    end
end

-- A dice reroll that changes a pedestal's InitSeed makes a new pedestal, so a
-- held Oath grants it again at once, in the same room: one choice, or two
-- while the held Oath is golden (user rule 2026-10-18).
local function rerollRegrant(plan,label,grants)
    grants=grants or 1
    plan.waitUntil(function(_,ctx)
        for _,p in ipairs(pedestals()) do
            if ctx.rollSeeds[p.InitSeed] or #oathGrants(p)~=grants then
                return false,string.format("item=%s seed=%s granted=%d",p.SubType,p.InitSeed,#oathGrants(p))
            end
        end
        return #pedestals()>0,"no pedestal"
    end,60,"rerolled pedestals settle: "..label)
    plan.note("reroll seeds "..label,function(_,ctx)
        local seeds={}
        for _,p in ipairs(pedestals()) do seeds[#seeds+1]=tostring(p.InitSeed) end
        return "before "..table.concat(ctx.rollSeedList,",").." -> after "..table.concat(seeds,",")
    end)
    plan.check("a new-seed pedestal gets its own Oath choice"..(grants>1 and "s" or "").." again: "..label,function(_,ctx)
        local granted={}
        for _,p in ipairs(pedestals()) do
            local items=oathGrants(p)
            local shown=#items==grants
            for _,cid in ipairs(items) do shown=shown and circleHas(p,cid) end
            if not shown then
                return false,string.format("seed=%s item=%s granted=[%s] want %d; cycle=[%s]",p.InitSeed,p.SubType,
                    table.concat(items,","),grants,table.concat(p:GetCollectibleCycle(),","))
            end
            granted[#granted+1]=p.SubType.."+"..table.concat(items,"+")
        end
        return Game():GetLevel():GetCurrentRoomDesc().ListIndex==ctx.rollRoom,
            "granted in the same room: "..table.concat(granted," ")
    end)
end

S.add("SEVERED_OATH","dice_copy_split",{conditions=true},function(plan,id)
    poolCapability(plan)
    plan.act(function(player,ctx) H.suppressRandomGoldenPedestals(ctx); player:AddCollectible(id,0,false) end)
    visitTreasure(plan)
    cycleCapability(plan)
    cycleCount(plan,"new stock gains one alternate",1)
    for roll=1,3 do
        plan.act(function(player,ctx)
            markRoll(ctx)
            player:UseActiveItem(roll==3 and CollectibleType.COLLECTIBLE_D100 or CollectibleType.COLLECTIBLE_D6,UseFlag.USE_NOANIM,-1)
        end)
        plan.wait(4)
        plan.require("dice preserve the held active",function(player) return player:GetActiveItem(ActiveSlot.SLOT_PRIMARY)==id,"Severed Oath still held after reroll "..roll end)
        rerollRegrant(plan,(roll==3 and "D100 " or "D6 ")..roll)
        cycleCount(plan,"repeated D6/D100 keeps exactly one alternate: "..roll,1)
    end
    plan.act(function(player,ctx)
        ctx.beforeCopy=#pedestals()
        ctx.copySources={}
        for _,p in ipairs(pedestals()) do
            ctx.copySources[GetPtrHash(p)]={tail=#p:GetCollectibleCycle(),seed=p.InitSeed}
        end
        player:UseActiveItem(CollectibleType.COLLECTIBLE_DIPLOPIA,UseFlag.USE_NOANIM,-1)
    end)
    plan.wait(4)
    plan.check("Diplopia copies each pedestal exactly once",function(_,ctx) return H.expect(#pedestals(),2*ctx.beforeCopy) end)
    -- Native Diplopia copies the shown item, not the source's queue. Like
    -- Birthright, the copy is a new pedestal and gets one Oath choice of its own.
    plan.check("each Diplopia copy gains one choice of its own while each source keeps its choice",function(_,ctx)
        local sources,copies,seeds=0,0,{}
        for _,p in ipairs(pedestals()) do
            local source=ctx.copySources[GetPtrHash(p)]
            local tail=#p:GetCollectibleCycle()
            if source then
                sources=sources+1
                if tail~=source.tail then return false,string.format("source item=%s cycle=%d was %d",p.SubType,tail,source.tail) end
            else
                copies=copies+1
                seeds[#seeds+1]=tostring(p.InitSeed)
                if tail~=1 then return false,string.format("copy item=%s has %d choice(s), expected 1",p.SubType,tail) end
            end
        end
        return sources==ctx.beforeCopy and copies==ctx.beforeCopy,
            string.format("%d sources kept their choice; %d copies have one each (seeds %s)",sources,copies,table.concat(seeds,","))
    end)
    plan.act(function(_,ctx)
        ctx.morphed=pedestals()[1]
        ctx.morphSeed=ctx.morphed.InitSeed
        local grants=oathGrants(ctx.morphed)
        ctx.morphGrants=table.concat(grants,",")
        -- A pending swap may still settle afterwards: the same slot then holds
        -- the paid ID instead of the preview, without another draw.
        local pending=oathPending(ctx.morphed)
        if pending and grants[pending.slot]==pending.from then grants[pending.slot]=pending.to end
        ctx.morphSettled=table.concat(grants,",")
        ctx.morphPending=pending and (pending.from.."->"..pending.to) or "none"
        ctx.morphTail=#ctx.morphed:GetCollectibleCycle()
        observe(ctx)
        ctx.morphed:Morph(EntityType.ENTITY_PICKUP,PickupVariant.PICKUP_COLLECTIBLE,CollectibleType.COLLECTIBLE_SAD_ONION,true,true,true)
    end)
    plan.wait(4)
    plan.check("a seed-keeping Morph is not a reroll: no new Oath choice",function(_,ctx)
        local p=ctx.morphed
        if not p:Exists() then return false,"morphed pedestal disappeared" end
        local grants,tail=table.concat(oathGrants(p),","),#p:GetCollectibleCycle()
        local paid=0
        for _,draw in ipairs(ctx.draws or {}) do if draw.decrease then paid=paid+1 end end
        return p.InitSeed==ctx.morphSeed and (grants==ctx.morphGrants or grants==ctx.morphSettled)
            and tail<=ctx.morphTail and paid==0,
            string.format("seed kept=%s; Oath grants [%s]->[%s] (pending %s); alternates %d->%d; new paid draws=%d",
                tostring(p.InitSeed==ctx.morphSeed),ctx.morphGrants,grants,ctx.morphPending,ctx.morphTail,tail,paid)
    end)
    -- Reroll every pedestal so each has its own choice again before the split.
    plan.act(function(player,ctx)
        markRoll(ctx)
        player:UseActiveItem(CollectibleType.COLLECTIBLE_D6,UseFlag.USE_NOANIM,-1)
    end)
    plan.wait(4)
    rerollRegrant(plan,"D6 on copies and the morphed pedestal")
    cycleCount(plan,"every rerolled pedestal has one alternate before the split",1)
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
    plan.act(function(player,ctx)
        player:AddCollectible(id,0,false)
        markRoll(ctx)
        player:UseActiveItem(CollectibleType.COLLECTIBLE_D6,UseFlag.USE_NOANIM,-1)
    end)
    plan.wait(4)
    rerollRegrant(plan,"D6 after reacquisition")
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

-- A rotating pedestal turns through a native Morph, which expires its
-- EntityPtr (measured in game 2026-10-17) while it keeps its pointer hash and
-- seed. A same-seed copy has its own hash, so the two never mix.
local function fixtureRef(p) return {ptr=EntityPtr(p),hash=GetPtrHash(p),seed=p.InitSeed} end
local function liveFixture(ref)
    local p=ref.ptr.Ref
    if p then return p:ToPickup() end
    for _,q in ipairs(pedestals()) do
        if GetPtrHash(q)==ref.hash and q.InitSeed==ref.seed then return q end
    end
end

S.add("SEVERED_OATH","cycle_ownership",{conditions=true},function(plan,id)
    poolCapability(plan)
    plan.act(function(_,ctx) H.suppressRandomGoldenPedestals(ctx) end)
    visitTreasure(plan)
    cycleCapability(plan)
    plan.act(function(player,ctx)
        for _,p in ipairs(pedestals()) do p:Remove() end
        player:AddCollectible(id,0,false)
        observe(ctx)
        -- Created while the Oath is held, so it is eligible; its queue is
        -- filled before its first update, when the bonus would be added.
        local p=H.pickup(player,CollectibleType.COLLECTIBLE_SAD_ONION)
        p:RemoveCollectibleCycle()
        for _=1,8 do assert(p:AddCollectibleCycle(CollectibleType.COLLECTIBLE_BREAKFAST)) end
    end)
    plan.wait(4)
    revisit(plan)
    plan.check("full native queue consumes no pool selections",function(_,ctx)
        return #ctx.draws==0 and #pedestals()[1]:GetCollectibleCycle()==8,"draws="..#ctx.draws
    end)
    plan.act(function(_,ctx)
        local p=pedestals()[1]
        p:RemoveCollectibleCycle()
        assert(p:AddCollectibleCycle(CollectibleType.COLLECTIBLE_BREAKFAST))
        assert(p:AddCollectibleCycle(CollectibleType.COLLECTIBLE_BREAKFAST))
        ctx.beforeCycle=cycleSnapshot(p)
        observe(ctx)
    end)
    plan.wait(4)
    plan.require("freed capacity awards one choice and preserves native duplicates",function(_,ctx)
        local ok,detail=addedChoices(ctx,1)
        if not ok then return ok,detail end
        for item,n in pairs(cycleSnapshot(pedestals()[1]).counts) do
            if n>(ctx.beforeCycle.counts[item] or 0) then ctx.ownedChoice=item end
        end
        return ctx.ownedChoice~=nil,detail
    end)
    plan.act(function(player,ctx)
        local p=pedestals()[1]
        ctx.copySource=EntityPtr(p); ctx.copySourceHash=GetPtrHash(p); ctx.copySourceSeed=p.InitSeed
        ctx.copySourceCycle=cycleSnapshot(p); ctx.copyHead=p.SubType
        player:UseActiveItem(CollectibleType.COLLECTIBLE_DIPLOPIA,UseFlag.USE_NOANIM,-1)
    end)
    plan.wait(4)
    plan.require("native copy shows the displayed choice plus its own while source keeps its queue",function(_,ctx)
        local stock=pedestals()
        if #stock~=2 then return false,"pedestals="..#stock end
        if not ctx.copySource.Ref then return false,"original source disappeared" end
        local source,copy
        for _,p in ipairs(stock) do
            if GetPtrHash(p)==ctx.copySourceHash and p.InitSeed==ctx.copySourceSeed then source=p
            else copy=p end
        end
        if not source or not copy then return false,"source/copy identity missing" end
        local a,b=cycleSnapshot(source),cycleSnapshot(copy)
        if a.total~=ctx.copySourceCycle.total then return false,"source choice count changed" end
        for item,n in pairs(ctx.copySourceCycle.counts) do
            if a.counts[item]~=n then return false,"source lost item "..item end
        end
        -- Native Diplopia copies the displayed item, not the source's cycle tail;
        -- the copy is a new pedestal and gets one Oath choice of its own.
        if b.total~=2 or (b.counts[ctx.copyHead] or 0)<1 then return false,"copy lacks the displayed choice plus one of its own" end
        ctx.changed=fixtureRef(source); ctx.untouched=fixtureRef(copy); ctx.untouchedCycle=b
        return true,"source choices="..a.total.."; independent copy choices=2"
    end)
    plan.act(function(_,ctx)
        local p=assert(liveFixture(ctx.changed),"source disappeared")
        local tail=p:GetCollectibleCycle()
        local replacement=CollectibleType.COLLECTIBLE_SAD_ONION
        if replacement==ctx.ownedChoice then replacement=CollectibleType.COLLECTIBLE_INNER_EYE end
        local head=p.SubType==ctx.ownedChoice and replacement or p.SubType
        for i,item in ipairs(tail) do if item==ctx.ownedChoice then tail[i]=replacement end end
        ctx.expectedChanged={counts={},total=1+#tail}
        ctx.expectedChanged.counts[head]=1
        for _,item in ipairs(tail) do ctx.expectedChanged.counts[item]=(ctx.expectedChanged.counts[item] or 0)+1 end
        local seed=p.InitSeed
        p:Morph(EntityType.ENTITY_PICKUP,PickupVariant.PICKUP_COLLECTIBLE,head,true,true,true)
        assert(p.InitSeed==seed,"keep-seed Morph changed seed")
        p:RemoveCollectibleCycle()
        for _,item in ipairs(tail) do assert(p:AddCollectibleCycle(item)) end
        ctx.changed=fixtureRef(p)
        observe(ctx)
    end)
    plan.wait(10)
    plan.check("foreign same-seed rewrite neither revives old choice nor changes sibling",function(_,ctx)
        for _,case in ipairs({{ctx.changed,ctx.expectedChanged},{ctx.untouched,ctx.untouchedCycle}}) do
            local p=liveFixture(case[1])
            if not p then return false,"fixture disappeared" end
            local actual,expected=cycleSnapshot(p),case[2]
            if actual.total~=expected.total then return false,"unexpected extra choice" end
            for item,n in pairs(expected.counts) do
                if actual.counts[item]~=n then return false,"changed occurrence count for "..item end
            end
        end
        return #ctx.draws==0,"no regeneration, sibling mutation or new draws; draws="..#ctx.draws
    end)
    revisit(plan)
    plan.act(function(player,ctx)
        player:UseCard(Card.CARD_SOUL_ISAAC,UseFlag.USE_NOANIM | UseFlag.USE_NOANNOUNCER)
        ctx.soulSignature=signature() -- The same native operation used by AstroItems.
    end)
    plan.wait(10)
    plan.check("native Soul of Isaac additions remain authoritative",function(_,ctx)
        return signature()==ctx.soulSignature,"native additions preserved through ordinary updates"
    end)
    revisit(plan)
end)

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
        -- Like Birthright: a pedestal seen before the Oath keeps its choices.
        plan.check(case.name.." seen pedestal gains nothing on entry",function(_,ctx) return addedChoices(ctx,0) end)
        plan.act(function(player)
            for _,p in ipairs(pedestals()) do p:Remove() end
            H.pickup(player,CollectibleType.COLLECTIBLE_BREAKFAST)
        end)
        plan.wait(4)
        plan.check(case.name.." a pedestal created while held gains exactly +1 over the native choices",function(_,ctx)
            local p=pedestals()[1]
            local grants=oathGrants(p)
            if #grants~=1 then return false,"Oath grants="..#grants end
            for _,cid in ipairs(grants) do
                if not circleHas(p,cid) then return false,"granted "..cid.." is not in the circle" end
            end
            return H.expect(cycleSnapshot(p).total,ctx.beforeCycle.total+1)
        end)
        revisit(plan)
        plan.act(function(player,ctx) markRoll(ctx); player:UseActiveItem(CollectibleType.COLLECTIBLE_D6,UseFlag.USE_NOANIM,-1) end)
        plan.wait(4)
        rerollRegrant(plan,case.name.." D6")
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
        plan.check("seen stock gains nothing on entry",function(_,ctx) return addedChoices(ctx,0) end)
        plan.act(function(player)
            for _,p in ipairs(pedestals()) do p:Remove() end
            H.pickup(player,CollectibleType.COLLECTIBLE_BREAKFAST)
        end)
        plan.wait(4)
        plan.require("normal held active gives a new pedestal +1 regardless of target gold",function(_,ctx)
            ctx.beforeCycle=cycleSnapshot(pedestals()[1])
            return H.expect(ctx.beforeCycle.total,(native and 5 or 1)+1)
        end)
        plan.act(function(player,ctx) ctx.goldProvider:SetGoldenItem(id,player,ActiveSlot.SLOT_PRIMARY) end)
        plan.wait(4)
        plan.require("provider confirms held Severed Oath upgrade",function(player,ctx)
            return ctx.goldProvider:HasGoldenItem(id,player,ActiveSlot.SLOT_PRIMARY)==true,
                "golden state must belong to the held active"
        end)
        plan.check("golden held active increases committed bonus to +2 once",function(_,ctx) return addedChoices(ctx,1) end)
        revisit(plan)
        plan.act(function(player,ctx) markRoll(ctx); player:UseActiveItem(CollectibleType.COLLECTIBLE_D6,UseFlag.USE_NOANIM,-1) end)
        plan.wait(4)
        rerollRegrant(plan,"golden D6"..(native and " + Glitched Crown" or ""),2)
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
        plan.check("stock made while unowned stays as it was after reacquisition",function()
            return H.expect(#pedestals()[1]:GetCollectibleCycle()+1,native and 5 or 1)
        end)
        plan.act(function(player)
            for _,p in ipairs(pedestals()) do p:Remove() end
            H.pickup(player,CollectibleType.COLLECTIBLE_BREAKFAST)
        end)
        plan.wait(4)
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
