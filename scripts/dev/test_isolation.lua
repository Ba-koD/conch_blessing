-- Opt-in baseline verification for reversible stat cases and familiar batches.
-- Floor changes, consumed pools and permanent rewards still require fresh runs.
local H = require("scripts.dev.item_test_support")
local M = {}
local eligible = { MONEY_TEAR=true, ORAL_STEROIDS=true, CEIL=true, ROUND=true, FLOOR=true,
    F_MINUS=true, C_MINUS=true, B_MINUS=true, KRONOS=true, UTILITY_BELT=true }
function M.supports(key) return eligible[key] == true end
function M.group(key)
    if key=="KRONOS" then return "kronos_reversible" end
    if key=="UTILITY_BELT" then return "belt_reversible" end
    return "reversible_stats"
end
-- These cases deliberately mutate native state that removing Kronos cannot undo.
-- Every other familiar case is admitted through the same real cleanup contract.
local kronosSeparate = {
    conversions="conversion stress acquires vanilla health/transformations and pickup rewards",
    exclusions="excluded familiars include Dead Cat lives and Strawman player state",
    buddy_in_a_box="floor pick expiry changes the native floor",
    lil_delirium="floor pick expiry changes the native floor",
    mongo_baby="Minisaac refill crosses a native floor boundary",
    milk="Milk expiry crosses a native floor boundary",
    lost_soul="clean and hit floor rewards require fresh floor history",
    manual_before="Monster Manual expiry changes the floor and temporary-effect ledger",
    manual_after="Monster Manual expiry changes the floor and temporary-effect ledger",
    sacrificial_altar="Sacrificial Altar consumes the native devil item pool",
    hallowed_ground="Hallowed Ground creates a persistent native grid entity",
    box_of_friends="Box expiry visits native rooms and creates room-clear rewards",
}
function M.scenario(key,name)
    if key=="KRONOS" then return not kronosSeparate[name],kronosSeparate[name] end
    if key=="UTILITY_BELT" then return true end
    return (key=="F_MINUS" or key=="C_MINUS" or key=="B_MINUS") and name=="moms_box"
end
local function forms(player)
    local result={}
    if type(player.HasPlayerForm)=="function" then
        for name,id in pairs(PlayerForm or {}) do
            if type(id)=="number" and name:match("^PLAYERFORM_") then result[id]=player:HasPlayerForm(id) end
        end
    end
    return result
end
local function effects(player)
    local result={}
    local e=player:GetEffects()
    if type(e.GetEffectsList)~="function" then return nil end
    local list=e:GetEffectsList()
    for index=0,list.Size-1 do
        local entry=list:Get(index)
        local item=entry and entry.Item
        if item and entry.Count>0 then result[tostring(item.Type)..":"..tostring(item.ID)]=entry.Count end
    end
    return result
end

local function counts(player)
    local rows = {}
    for id=1,Isaac.GetItemConfig():GetCollectibles().Size-1 do
        local count=player:GetCollectibleNum(id,true)
        if count>0 then rows[id]=count end
    end
    return rows
end

local function equal(a,b)
    for key,value in pairs(a) do if b[key]~=value then return false end end
    for key,value in pairs(b) do if a[key]~=value then return false end end
    return true
end

local function empty(value)
    if value==nil then return true end
    if type(value)~="table" then return false end
    for _,v in pairs(value) do if not empty(v) then return false end end
    return true
end

local function gameplayEntities(includeEffects)
    local rows={}
    for _,entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type~=EntityType.ENTITY_PLAYER and (includeEffects or entity.Type~=EntityType.ENTITY_EFFECT) then
            rows[GetPtrHash(entity)]=entity
        end
    end
    return rows
end

local function entityEvidence(entity)
    local pickup=entity:ToPickup()
    local key=table.concat({entity.Type,entity.Variant,entity.SubType,entity.InitSeed},":")
    -- Room re-entry reconstructs native pickups. A process pointer is not their
    -- room identity; keep the seed and full pickup contract in the snapshot.
    if pickup then
        key=key..":"..tostring(pickup.OptionsPickupIndex)..":"..tostring(pickup.Price)
            ..":"..tostring(pickup.ShopItemId)
            ..":"..tostring(pickup.AutoUpdatePrice)
            ..":"..tostring(type(pickup.IsShopItem)=="function" and pickup:IsShopItem() or nil)
    end
    return {key=key,type=entity.Type,hash=GetPtrHash(entity),
        detail=key.." ptr="..tostring(GetPtrHash(entity)).." age="..tostring(entity.FrameCount)
            .." damage="..tostring(entity.CollisionDamage)}
end

local function snapshotEntities(includeEffects)
    local snapshot={}
    for hash,entity in pairs(gameplayEntities(includeEffects)) do snapshot[hash]=entityEvidence(entity) end
    return snapshot
end

local function matchEntities(base)
    local unmatched={}
    for hash,row in pairs(base.entities) do unmatched[hash]=row end
    local extra={}
    for _,entity in pairs(gameplayEntities(base.includeEffects)) do
        local evidence=entityEvidence(entity)
        local found
        for hash,row in pairs(unmatched) do
            if row.key==evidence.key then found=hash;break end
        end
        if found then unmatched[found]=nil else extra[#extra+1]=entity end
    end
    return unmatched,extra
end

function M.begin(plan, includeEffects)
    plan.wait(2) -- settle room-entry callbacks before taking the clean snapshot
    plan.act(function(player,ctx)
        local level=Game():GetLevel()
        ctx.canReuse=false
        ctx.isolation={counts=counts(player),stats=H.stats(player),hash=GetPtrHash(player),forms=forms(player),effects=effects(player),
            stage=level:GetStage(),room=level:GetCurrentRoomDesc().ListIndex,clear=Game():GetRoom():IsClear(),
            dimension=type(level.GetDimension)=="function" and level:GetDimension() or 0,
            entities=snapshotEntities(includeEffects),includeEffects=includeEffects,trinkets={},actives={},coins=player:GetNumCoins(),
            bombs=player:GetNumBombs(),keys=player:GetNumKeys(),hearts=player:GetHearts(),maxHearts=player:GetMaxHearts(),
            soulHearts=player:GetSoulHearts(),blackHearts=player:GetBlackHearts(),fly=player.CanFly,flags=player.TearFlags}
        ctx.isolation.minusNoHit = ConchBlessing._minusNoHit and ConchBlessing._minusNoHit[player.ControllerIndex or 0]
        for slot=0,1 do ctx.isolation.trinkets[slot]=player:GetTrinket(slot) end
        for slot=0,3 do
            ctx.isolation.actives[slot]={id=player:GetActiveItem(slot),charge=player:GetActiveCharge(slot),
                battery=player:GetBatteryCharge(slot)}
        end
    end)
end

function M.finish(plan,key,id,requireClean)
    plan.section(key .. " / restore shared-run baseline")
    plan.act(function(player,ctx)
        local base=ctx.isolation
        H.stopShooting()
        -- All gameplay assertions already ran. Restore only engine inventory
        -- and fixture resources; never erase item saves or provider contributions.
        -- Kronos removal returns absorbed inventory during ordinary updates. Let
        -- that happen BEFORE inventory restoration, or returned familiars leak
        -- past the first inventory scan and force a needless reset.
        if key=="KRONOS" then
            while player:HasCollectible(id) do player:RemoveCollectible(id) end
        end
    end)
    if key=="KRONOS" then
        plan.wait(4)
        plan.require("Kronos removes owned native anchors before fixture cleanup",function(player)
            local data=player:GetData()
            for _,key in ipairs({"__kronosTwistedPairs","__kronosIncubi","__kronosSuccubi","__kronosCensers",
                "__kronosStarsOfBethlehem","__kronosAngelicPrisms","__kronosBloodshotEyes"}) do
                for _,entity in ipairs(data[key] or {}) do
                    if entity and entity:Exists() then return false,"live owned anchor remains: "..key end
                end
            end
            return true,"ordinary removal callbacks cleared all owned anchor lists"
        end)
    end
    plan.act(function(player,ctx)
        local base=ctx.isolation
        for slot=0,1 do local tid=player:GetTrinket(slot); if tid>0 then player:TryRemoveTrinket(tid) end end
        for slot=0,3 do
            local aid=player:GetActiveItem(slot)
            if aid>0 then
                -- SetActiveCharge may ignore an empty pocket. Clear the fixture
                -- charge while its item is still present, before removing it.
                player:SetActiveCharge(0,slot)
                player:RemoveCollectible(aid,true,slot)
            end
        end
        for cid,count in pairs(counts(player)) do
            for _=(base.counts[cid] or 0)+1,count do player:RemoveCollectible(cid) end
        end
        for cid,wanted in pairs(base.counts) do
            if Isaac.GetItemConfig():GetCollectible(cid).Type~=ItemType.ITEM_ACTIVE then
                for _=player:GetCollectibleNum(cid,true)+1,wanted do player:AddCollectible(cid,0,false) end
            end
        end
        for slot=0,3 do
            local active=base.actives[slot]
            if active.id>0 then
                player:AddCollectible(active.id,active.charge,false,slot)
            end
            -- RemoveCollectible can leave charge on an empty pocket slot. That
            -- is fixture residue, not a Utility Belt gameplay failure.
            player:SetActiveCharge(active.charge+active.battery,slot)
            if (player:GetActiveCharge(slot)~=active.charge or player:GetBatteryCharge(slot)~=active.battery)
                and type(player.GetActiveItemDesc)=="function" then
                -- Some engines retain charge even on an already-empty slot.
                -- Use the guarded descriptor API for exact fixture restoration;
                -- the validation below still rejects an unsupported/no-op write.
                local ok,desc=pcall(player.GetActiveItemDesc,player,slot)
                if ok and desc and desc.Item==active.id then
                    pcall(function() desc.Charge=active.charge; desc.BatteryCharge=active.battery end)
                end
            end
        end
        -- AddTrinket inserts at slot zero, so restore the held pair in reverse.
        for slot=1,0,-1 do if base.trinkets[slot]>0 then player:AddTrinket(base.trinkets[slot],false) end end
        player:AddCoins(base.coins-player:GetNumCoins())
        player:AddBombs(base.bombs-player:GetNumBombs())
        player:AddKeys(base.keys-player:GetNumKeys())
        player:AddMaxHearts(base.maxHearts-player:GetMaxHearts(),false)
        player:AddHearts(base.hearts-player:GetHearts())
        -- The admitted fixtures do not create soul/black hearts. A mismatch is
        -- a failed isolation check, never repaired by changing heart types.
        local _,extra=matchEntities(base)
        for _,entity in ipairs(extra) do entity:Remove() end
        -- Gameplay removal checks have already completed. Refresh only after
        -- restoring the fixture's vanilla inventory (e.g. Sacred Heart).
        H.refresh(player)
    end)
    plan.wait(4) -- ordinary callbacks must withdraw effects and deferred caches
    local check = requireClean and plan.require or plan.check
    local function validate(player,ctx)
        local base=ctx.isolation
        if not player or GetPtrHash(player)~=base.hash then return false,"player identity changed" end
        if player:IsDead() then return false,"test player died" end
        if not equal(forms(player),base.forms) then return false,"permanent player transformation changed" end
        local currentEffects=effects(player)
        if not base.effects or not currentEffects then return false,"temporary-effect enumeration unavailable" end
        if not equal(currentEffects,base.effects) then return false,"native temporary effects differ" end
        local ok,detail=H.sameStats(player,base.stats)
        if not ok then return false,detail end
        if not equal(counts(player),base.counts) then return false,"inventory differs from baseline" end
        for slot=0,1 do if player:GetTrinket(slot)~=base.trinkets[slot] then return false,"held trinkets differ" end end
        for slot=0,3 do
            local a=base.actives[slot]
            if player:GetActiveItem(slot)~=a.id or player:GetActiveCharge(slot)~=a.charge
                or player:GetBatteryCharge(slot)~=a.battery then
                return false,string.format("active slot %d: item=%d/%d charge=%d/%d battery=%d/%d (actual/expected)",
                    slot,player:GetActiveItem(slot),a.id,player:GetActiveCharge(slot),a.charge,player:GetBatteryCharge(slot),a.battery)
            end
        end
        if player:GetNumCoins()~=base.coins or player:GetNumBombs()~=base.bombs or player:GetNumKeys()~=base.keys
            or player:GetHearts()~=base.hearts or player:GetMaxHearts()~=base.maxHearts
            or player:GetSoulHearts()~=base.soulHearts or player:GetBlackHearts()~=base.blackHearts
            or player.CanFly~=base.fly or player.TearFlags~=base.flags then return false,"resources or capabilities differ" end
        local level=Game():GetLevel()
        if level:GetStage()~=base.stage or level:GetCurrentRoomDesc().ListIndex~=base.room
            or (type(level.GetDimension)=="function" and level:GetDimension()~=base.dimension) then return false,"room changed" end
        local missing,extra=matchEntities(base)
        for _,row in pairs(missing) do
            -- A pre-existing cosmetic effect may expire naturally during a case.
            -- It is protected from cleanup, but need not survive the test.
            if row.type~=EntityType.ENTITY_EFFECT then
                return false,"baseline entity disappeared: "..row.detail
            end
        end
        if extra[1] then return false,"orphan gameplay entity: "..entityEvidence(extra[1]).detail end
        if Game():GetRoom():IsClear()~=base.clear then return false,"native room clear state changed" end
        if not player:IsItemQueueEmpty() then return false,"pickup queue still active" end
        local unified=ConchBlessing.getUnifiedMultiplierState(player)
        for _,group in ipairs({"itemAdditions","itemMultipliers","itemAdditiveMultipliers"}) do
            if not empty(unified and unified[group] and unified[group][id]) then return false,"orphan "..group end
        end
        if key=="ORAL_STEROIDS" then
            if not empty(H.save(player).oralSteroids) or not empty(ConchBlessing.oralsteroids.storedMultipliers) then
                return false,"stored steroid rolls remain"
            end
            for _,count in pairs(ConchBlessing.oralsteroids._lastItemCount or {}) do
                if count~=0 then return false,"steroid count tracking remains" end
            end
        end
        local noHit=ConchBlessing._minusNoHit and ConchBlessing._minusNoHit[player.ControllerIndex or 0]
        -- The admitted Kronos batches exercise hits but contain no floor rewards
        -- or Minus trinkets. Preserve that unrelated damage history, never reset it.
        if key~="KRONOS" and noHit~=base.minusNoHit then return false,"floor damage/evolution state changed" end
        if key=="MONEY_TEAR" then
            for _,ps in pairs(ConchBlessing.moneytear.state.perPlayer) do
                if ps.lastCoins~=nil or ps.lastCount~=nil then return false,"money-tear tracking remains" end
            end
        end
        if key=="KRONOS" then
            local saved=ConchBlessing.SaveManager.GetRunSave(nil).kronos or {}
            for _,field in ipairs({"absorbed","itemGrants","itemGrantTotals","itemGrantBaselines",
                "spared","floorPicks","tempFloor","tempPermanent","clearCounters","paschalHundredths","milkSerial",
                "lostSoulRewardPending","prettyFlies"}) do
                if not empty(saved[field]) then return false,"Kronos saved effect remains: "..field end
            end
            if (saved.totalAbsorbed or 0)~=0 then return false,"Kronos absorbed total remains" end
            local temporary=ConchBlessing.kronos._getRoomTemporary()
            if (temporary.double or 0)~=0 or not empty(temporary.counts) or not empty(temporary.twins)
                or not empty(temporary.mongoCopies) then return false,"Kronos room temporary effect remains" end
            local pending=ConchBlessing.kronos._test and ConchBlessing.kronos._test.pendingCounts
            if pending then
                for name,count in pairs(pending()) do
                    if count~=0 then return false,"Kronos pending callback remains: "..name end
                end
            end
        end
        if key=="UTILITY_BELT" and ConchBlessing.utilitybelt._pendingPlayers[GetPtrHash(player)] then
            return false,"pending belt transfer remains"
        end
        return true,"inventory, stats, resources, room, entities, saved effects and pending queue cleared"
    end
    -- Native removal visuals and deferred familiar cleanup can outlive the first
    -- four updates. Observe natural settling; never repeatedly delete a leak.
    plan.act(function(_,ctx) ctx.cleanupWait=0 end)
    plan.waitUntil(function(player,ctx)
        local ok,detail=validate(player,ctx)
        ctx.cleanupWait=ctx.cleanupWait+1
        ctx.cleanupDetail=detail
        return ok or ctx.cleanupWait>=120
    end,121,"baseline cleanup settles without erasing item state")
    check("baseline restored; safe to share next test",function(player,ctx)
        local ok,detail=validate(player,ctx)
        ctx.canReuse=ok
        ctx.reuseReason=not ok and detail or nil
        if ok then ctx.verifyReuse=function(p) return validate(p,ctx) end end
        return ok,detail
    end)
end

return M
