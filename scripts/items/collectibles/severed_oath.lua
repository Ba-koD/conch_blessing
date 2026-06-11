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
    for _, itemId in pairs(cycle) do
        addUniqueItem(ids, seen, itemId)
    end

    addUniqueItem(ids, seen, pickup.SubType)
    return ids
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

local function applyPickupState(pickup, state)
    if not pickup or not state then
        return
    end

    pickup.OptionsPickupIndex = 0
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

local function spawnSplitPickup(itemId, pos, state, player)
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
    applyPickupState(pickup, state)
    pickup:GetData().__conchBlessingSeveredOathSplit = true
    return pickup
end

local function splitPickup(pickup, player)
    local cycleItems = getCycleItems(pickup)
    if #cycleItems <= 1 then
        return 0
    end

    local room = Game():GetRoom()
    local basePos = pickup.Position
    local state = savePickupState(pickup)
    local count = #cycleItems

    pickup:Remove()

    for index, itemId in ipairs(cycleItems) do
        local pos = getSplitPosition(room, basePos, index, count)
        spawnSplitPickup(itemId, pos, state, player)
    end

    local effectVariant = EffectVariant.SCYTHE_BREAK or EffectVariant.POOF_1
    Isaac.Spawn(EntityType.ENTITY_EFFECT, effectVariant, 0, basePos, Vector.Zero, player)
    return count
end

local function splitRoomCycles(player)
    local splitCount = 0
    local spawnedCount = 0

    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type == EntityType.ENTITY_PICKUP
            and entity.Variant == PickupVariant.PICKUP_COLLECTIBLE then
            local pickup = entity:ToPickup()
            if pickup and pickup:Exists() then
                local count = splitPickup(pickup, player)
                if count > 0 then
                    splitCount = splitCount + 1
                    spawnedCount = spawnedCount + count
                end
            end
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
