ConchBlessing.severedoath = ConchBlessing.severedoath or {}
local M = ConchBlessing.severedoath

local SEVERED_OATH_ID = Isaac.GetItemIdByName("Severed Oath")
local SPLIT_SPACING = 40
local MIN_PICKUP_WAIT = 20

M.data = M.data or {}

local function isValidCollectibleId(itemId)
    if type(itemId) ~= "number" or itemId <= 0 then
        return false
    end

    local config = Isaac.GetItemConfig()
    return config and config:GetCollectible(itemId) ~= nil
end

local function addUniqueItem(ids, seen, itemId)
    if not isValidCollectibleId(itemId) or seen[itemId] then
        return
    end

    seen[itemId] = true
    table.insert(ids, itemId)
end

local function getCycleItems(pickup)
    if not pickup or pickup.Variant ~= PickupVariant.PICKUP_COLLECTIBLE then
        return {}
    end

    if type(pickup.GetCollectibleCycle) ~= "function" then
        return {}
    end

    local ok, cycle = pcall(function()
        return pickup:GetCollectibleCycle()
    end)
    if not ok or type(cycle) ~= "table" then
        return {}
    end

    local ids = {}
    local seen = {}
    for _, itemId in ipairs(cycle) do
        addUniqueItem(ids, seen, itemId)
    end
    if #ids <= 0 then
        for _, itemId in pairs(cycle) do
            addUniqueItem(ids, seen, itemId)
        end
    end

    addUniqueItem(ids, seen, pickup.SubType)
    return ids
end

local function getPickupOptionsIndex(pickup)
    return math.max(0, tonumber(pickup and pickup.OptionsPickupIndex) or 0)
end

local function spawnCleaverSlashEffect(pos, player)
    if not pos then
        return
    end

    local variant = EffectVariant.CLEAVER_SLASH
        or EffectVariant.SCYTHE_BREAK
        or EffectVariant.POOF01
        or EffectVariant.POOF_1
        or 15
    Isaac.Spawn(EntityType.ENTITY_EFFECT, variant, 0, pos, Vector.Zero, player)
end

local function savePickupState(pickup)
    return {
        charge = pickup.Charge,
        price = pickup.Price,
        shopItemId = pickup.ShopItemId,
        timeout = pickup.Timeout,
        wait = pickup.Wait,
    }
end

local function applyPickupState(pickup, state, optionsPickupIndex)
    if not pickup or not state then
        return
    end

    pickup.OptionsPickupIndex = tonumber(optionsPickupIndex) or 0
    if state.price ~= nil then
        pickup.Price = state.price
    end
    if state.timeout ~= nil then
        pickup.Timeout = state.timeout
    end
    if state.charge ~= nil then
        pickup.Charge = state.charge
    end
    if pickup.AutoUpdatePrice ~= nil then
        pickup.AutoUpdatePrice = false
    end

    local wait = tonumber(state.wait) or 0
    pickup.Wait = math.max(wait, MIN_PICKUP_WAIT)

    local shopItemId = tonumber(state.shopItemId)
    if shopItemId and shopItemId < 0 then
        pickup.ShopItemId = shopItemId
    else
        pickup.ShopItemId = -1
    end

    pickup.Touched = false
end

local function getSplitPosition(room, basePos, index, count)
    local centeredIndex = index - ((count + 1) / 2)
    local target = basePos + Vector(centeredIndex * SPLIT_SPACING, 0)
    local ok, pos = pcall(function()
        return room:FindFreePickupSpawnPosition(target, 0, true)
    end)
    if ok and pos then
        return pos
    end
    return target
end

local function spawnSplitPickup(itemId, pos, state, player, optionsPickupIndex)
    local entity = Isaac.Spawn(
        EntityType.ENTITY_PICKUP,
        PickupVariant.PICKUP_COLLECTIBLE,
        itemId,
        pos,
        Vector.Zero,
        player
    )
    local pickup = entity and entity:ToPickup() or nil
    if not pickup then
        return nil
    end

    pcall(function()
        pickup:Morph(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, itemId, true, true, true)
    end)
    applyPickupState(pickup, state, optionsPickupIndex)
    pickup:GetData().__conchBlessingSeveredOathSplit = true
    return pickup
end

local function splitPickup(entry, player)
    local pickup = entry.pickup
    local cycleItems = entry.cycleItems
    local room = Game():GetRoom()
    local basePos = entry.basePos
    local state = entry.state
    local count = #cycleItems

    spawnCleaverSlashEffect(basePos, player)
    pickup:Remove()

    for index, itemId in ipairs(cycleItems) do
        local pos = getSplitPosition(room, basePos, index, count)
        local optionsPickupIndex = entry.splitOptions and entry.splitOptions[index] or 0
        spawnSplitPickup(itemId, pos, state, player, optionsPickupIndex)
    end

    return count
end

local function collectSplitEntries()
    local entries = {}
    local maxOptionsPickupIndex = 0

    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type == EntityType.ENTITY_PICKUP
            and entity.Variant == PickupVariant.PICKUP_COLLECTIBLE then
            local pickup = entity:ToPickup()
            if pickup and pickup:Exists() and not pickup:GetData().__conchBlessingSeveredOathSplit then
                local optionsPickupIndex = getPickupOptionsIndex(pickup)
                maxOptionsPickupIndex = math.max(maxOptionsPickupIndex, optionsPickupIndex)

                local cycleItems = getCycleItems(pickup)
                if #cycleItems > 1 then
                    table.insert(entries, {
                        pickup = pickup,
                        basePos = pickup.Position,
                        cycleItems = cycleItems,
                        optionsPickupIndex = optionsPickupIndex,
                        state = savePickupState(pickup),
                        splitOptions = {},
                    })
                end
            end
        end
    end

    return entries, maxOptionsPickupIndex
end

local function assignSplitOptions(entries, firstFreeOptionsPickupIndex)
    local optionGroups = {}
    for _, entry in ipairs(entries) do
        if entry.optionsPickupIndex > 0 then
            local key = entry.optionsPickupIndex
            optionGroups[key] = optionGroups[key] or {}
            table.insert(optionGroups[key], entry)
        end
    end

    local nextOptionsPickupIndex = firstFreeOptionsPickupIndex
    for _, group in pairs(optionGroups) do
        if #group > 1 then
            local maxCycleCount = 0
            for _, entry in ipairs(group) do
                maxCycleCount = math.max(maxCycleCount, #entry.cycleItems)
            end

            for cycleIndex = 1, maxCycleCount do
                local linkedCount = 0
                for _, entry in ipairs(group) do
                    if entry.cycleItems[cycleIndex] then
                        linkedCount = linkedCount + 1
                    end
                end

                if linkedCount > 1 then
                    for _, entry in ipairs(group) do
                        if entry.cycleItems[cycleIndex] then
                            entry.splitOptions[cycleIndex] = nextOptionsPickupIndex
                        end
                    end
                    nextOptionsPickupIndex = nextOptionsPickupIndex + 1
                end
            end
        end
    end
end

local function splitRoomCycles(player)
    local splitCount = 0
    local spawnedCount = 0
    local entries, maxOptionsPickupIndex = collectSplitEntries()
    assignSplitOptions(entries, maxOptionsPickupIndex + 1)

    for _, entry in ipairs(entries) do
        if entry.pickup and entry.pickup:Exists() then
            local count = splitPickup(entry, player)
            splitCount = splitCount + 1
            spawnedCount = spawnedCount + count
        end
    end

    return splitCount, spawnedCount
end

function M.onUseItem(_, collectibleId, rng, player, useFlags, activeSlot, varData)
    if collectibleId ~= SEVERED_OATH_ID then
        return
    end

    if not player or not player.Position then
        player = Isaac.GetPlayer(0)
    end

    local splitCount, spawnedCount = splitRoomCycles(player)
    if splitCount <= 0 then
        ConchBlessing.printDebug("[Severed Oath] No cycling collectible pickups found.")
        return { Discharge = false, Remove = false, ShowAnim = false }
    end

    SFXManager():Play(SoundEffect.SOUND_POWERUP_SPEWER, 1.0, 0, false, 1.0, 0)
    ConchBlessing.printDebug(string.format("[Severed Oath] Split %d cycling pickups into %d items.", splitCount, spawnedCount))
    return { Discharge = true, Remove = false, ShowAnim = true }
end

function M.onBeforeChange(upgradePos, pickup, _)
    return ConchBlessing.template.positive.onBeforeChange(upgradePos, pickup, M.data)
end

function M.onAfterChange(upgradePos, pickup, _)
    ConchBlessing.template.positive.onAfterChange(upgradePos, pickup, M.data)
end

function M.onUpdate()
    ConchBlessing.template.onUpdate(M.data)
end
