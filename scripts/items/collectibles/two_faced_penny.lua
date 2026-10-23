local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
local game = Game()
local Hits = require("scripts.lib.player_hits")
local Sound = require("scripts.lib.sound_volume")

ConchBlessing.twofacedpenny = {}

local M = ConchBlessing.twofacedpenny
local TWO_FACED_PENNY_ID = Isaac.GetItemIdByName("Two Faced Penny")
local HAS_POST_ADD_COLLECTIBLE = ModCallbacks and ModCallbacks.MC_POST_ADD_COLLECTIBLE ~= nil
local SAVE_KEY = "twoFacedPenny"

-- The first MC_POST_NEW_LEVEL of a run fires before MC_POST_GAME_STARTED, while
-- SaveManager can still expose the previous run's table. A luamod reload in the
-- middle of a run never sees game start, so it opens at once.
M._runReady = type(Isaac.IsInGame) == "function" and Isaac.IsInGame() == true

local collectibleScanIds = nil

local function getFloorKey()
    local level = game:GetLevel()
    local stage = level:GetStage()
    local stageType = level:GetStageType()
    return tostring(stage) .. ":" .. tostring(stageType)
end

-- Each coin's slot (its reserved item, and whether the player was hit on this
-- floor since the item was reserved) and the floor those flags belong to live
-- in the run save, so Continue and Glowing Hourglass bring them back together
-- with the inventory. Before, they lived in GetData: Continue reopened every
-- slot, and the next item then took the coin and its floor payouts.
local function getState(player, create)
    local SaveManager = ConchBlessing.SaveManager
    if not SaveManager then return nil end
    local save = create and SaveManager.GetRunSave(player) or SaveManager.TryGetRunSave(player)
    if type(save) ~= "table" then return nil end
    local state = save[SAVE_KEY]
    if type(state) ~= "table" then
        if not create then return nil end
        state = {}
        save[SAVE_KEY] = state
    end
    if type(state.slots) ~= "table" then state.slots = {} end
    return state
end

-- Pickup bookkeeping the engine rebuilds every session stays runtime-only.
local function getRuntime(player)
    local data = player:GetData()
    local runtime = data.__twofacedpenny
    if type(runtime) ~= "table" then
        runtime = {}
        data.__twofacedpenny = runtime
    end
    runtime.granting = tonumber(runtime.granting) or 0
    return runtime
end

local function isValidCollectibleId(itemId)
    return type(itemId) == "number" and itemId > 0
end

local function isRewardCollectible(itemId)
    if not isValidCollectibleId(itemId) or itemId == TWO_FACED_PENNY_ID then return false end
    local config = Isaac.GetItemConfig():GetCollectible(itemId)
    return config ~= nil and config.Type ~= ItemType.ITEM_ACTIVE
end

local function getPennyCount(player)
    if not player or not isValidCollectibleId(TWO_FACED_PENNY_ID) then
        return 0
    end

    local ok, count = pcall(function()
        return player:GetCollectibleNum(TWO_FACED_PENNY_ID, true)
    end)
    if ok and type(count) == "number" then
        return count
    end
    return 0
end

local function addScanId(ids, seen, itemId)
    itemId = tonumber(itemId)
    if not isValidCollectibleId(itemId) or seen[itemId] then
        return
    end

    seen[itemId] = true
    table.insert(ids, itemId)
end

local function getCollectibleScanIds()
    if collectibleScanIds then
        return collectibleScanIds
    end

    local ids = {}
    local seen = {}
    local maxId = CollectibleType.NUM_COLLECTIBLES or 0
    for itemId = 1, math.max(0, maxId - 1) do
        addScanId(ids, seen, itemId)
    end

    for _, itemData in pairs(ConchBlessing.ItemData or {}) do
        addScanId(ids, seen, itemData and itemData.id)
    end

    table.sort(ids)
    collectibleScanIds = ids
    return collectibleScanIds
end

local function buildCollectibleCounts(player)
    local counts = {}
    for _, itemId in ipairs(getCollectibleScanIds()) do
        local ok, count = pcall(function()
            return player:GetCollectibleNum(itemId, true)
        end)
        if ok and type(count) == "number" then
            counts[itemId] = count
        end
    end
    return counts
end

local function refreshCounts(player, runtime)
    runtime.lastCollectibleCounts = buildCollectibleCounts(player)
end

local function recordCollectibleCount(player, runtime, itemId)
    if not isValidCollectibleId(itemId) or not runtime.lastCollectibleCounts then
        return
    end

    local ok, count = pcall(function()
        return player:GetCollectibleNum(itemId, true)
    end)
    if ok and type(count) == "number" then
        runtime.lastCollectibleCounts[itemId] = count
    end
end

local function detectNewCollectibles(player, runtime)
    if not runtime.lastCollectibleCounts then
        refreshCounts(player, runtime)
        return {}
    end

    local changes = {}
    local counts = runtime.lastCollectibleCounts
    for _, itemId in ipairs(getCollectibleScanIds()) do
        local ok, current = pcall(function()
            return player:GetCollectibleNum(itemId, true)
        end)
        if ok and type(current) == "number" then
            local previous = counts[itemId] or 0
            if current > previous and itemId ~= TWO_FACED_PENNY_ID then
                table.insert(changes, {
                    itemId = itemId,
                    delta = current - previous,
                })
            end
            counts[itemId] = current
        end
    end

    return changes
end

-- One slot per coin owned. A lost coin takes the newest slot with it; a coin
-- gained opens a slot for the next item.
local function syncPennySlots(player, state)
    local pennyCount = getPennyCount(player)
    -- Reopen reservations made for an active by older code. Never remove an
    -- already granted item, and never pay that invalid reservation on a new floor.
    for _, slot in ipairs(state.slots) do
        if slot.itemId and not isRewardCollectible(slot.itemId) then
            slot.itemId, slot.hit = nil, false
        end
    end
    while #state.slots < pennyCount do
        table.insert(state.slots, { itemId = nil, hit = false })
    end
    while #state.slots > pennyCount do
        table.remove(state.slots)
    end
    return pennyCount
end

-- The coin's own copies are not acquisitions: while one is being added, every
-- add it causes is ignored, including another mod's answer to it.
local function grantItem(player, itemId, runtime)
    runtime.granting = (runtime.granting or 0) + 1
    local ok, err = pcall(function() player:AddCollectible(itemId, 0, true) end)
    runtime.granting = runtime.granting - 1
    recordCollectibleCount(player, runtime, itemId)
    if not ok then
        ConchBlessing.printError("[Two Faced Penny] Could not grant collectible " .. tostring(itemId) .. ": " .. tostring(err))
    end
    return ok
end

local function claimNextCollectible(player, state, runtime, itemId)
    local claimed = 0
    for _, slot in ipairs(state.slots) do
        if not slot.itemId then
            -- A coin's clean floor counts from the moment it has an item.
            slot.itemId, slot.hit = itemId, false
            claimed = claimed + 1
        end
    end
    if claimed <= 0 then
        return false
    end

    for _ = 1, claimed do
        grantItem(player, itemId, runtime)
    end
    ConchBlessing.printDebug(string.format(
        "[Two Faced Penny] Claimed collectible %d for %d slot(s).", itemId, claimed))
    return true
end

local function processObservedCollectible(player, runtime, itemId)
    if not isRewardCollectible(itemId) then
        return false
    end

    local state = getState(player, true)
    if not state or syncPennySlots(player, state) <= 0 then
        return false
    end
    return claimNextCollectible(player, state, runtime, itemId)
end

-- Registered below at EARLY priority, so the coin takes the item the player
-- picked up before default-priority callbacks of other mods can answer that
-- pickup with a grant of their own.
function M.onPostAddCollectible(_, itemId, _charge, firstTime, _slot, _varData, player)
    if not player or not isValidCollectibleId(itemId) or not isValidCollectibleId(TWO_FACED_PENNY_ID) then
        return
    end

    local runtime = getRuntime(player)
    if runtime.granting > 0 or not M._runReady then
        recordCollectibleCount(player, runtime, itemId)
        return
    end

    if itemId == TWO_FACED_PENNY_ID then
        local state = getState(player, true)
        if state then
            syncPennySlots(player, state)
            if state.floorKey == nil then state.floorKey = getFloorKey() end
        end
        recordCollectibleCount(player, runtime, itemId)
        return
    end

    if firstTime == true then
        processObservedCollectible(player, runtime, itemId)
    end
    recordCollectibleCount(player, runtime, itemId)
end

function M.onPlayerUpdate(_, player)
    if not player or not isValidCollectibleId(TWO_FACED_PENNY_ID) or not M._runReady then
        return
    end

    local owned = player:HasCollectible(TWO_FACED_PENNY_ID)
    local state = getState(player, owned)
    local pennyCount = 0
    if state then
        pennyCount = syncPennySlots(player, state)
        if state.floorKey == nil then
            state.floorKey = getFloorKey()
        end
    end

    if not HAS_POST_ADD_COLLECTIBLE then
        if pennyCount > 0 then
            local runtime = getRuntime(player)
            for _, change in ipairs(detectNewCollectibles(player, runtime)) do
                processObservedCollectible(player, runtime, change.itemId)
            end
        else
            -- Without a coin there is nothing to claim, so drop the baseline: the
            -- first update with a coin takes a fresh one, and an item picked up
            -- before the coin is never claimed by it.
            local runtime = player:GetData().__twofacedpenny
            if type(runtime) == "table" then runtime.lastCollectibleCounts = nil end
        end
    end
end

function M.onDamage(_, entity, amount, flags, source, countdown)
    local player = entity:ToPlayer()
    if not player or not M._runReady or not player:HasCollectible(TWO_FACED_PENNY_ID) then
        return
    end
    if not Hits.counts(flags) then
        return
    end
    local state = getState(player, true)
    if not state then return end
    for _, slot in ipairs(state.slots) do
        slot.hit = true
    end
    return true
end
Hits.register("TWO_FACED_PENNY", M.onDamage)

function M.onNewFloor(_)
    if not M._runReady then return end
    local floorKey = getFloorKey()
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        local state = player and getState(player, false)
        if state then
            local paid = false
            if state.floorKey and state.floorKey ~= floorKey and player:HasCollectible(TWO_FACED_PENNY_ID) then
                syncPennySlots(player, state)
                local runtime = getRuntime(player)
                for _, slot in ipairs(state.slots) do
                    if not slot.hit and isRewardCollectible(slot.itemId) then
                        paid = grantItem(player, slot.itemId, runtime) or paid
                    end
                end
            end
            for _, slot in ipairs(state.slots) do
                slot.hit = false
            end
            state.floorKey = floorKey
            if paid then
                SFXManager():Play(SoundEffect.SOUND_POWERUP1, Sound.volume(1.0))
            end
        end
    end
end

function M.onGameStarted(_, isContinued)
    M._runReady = true
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        if player then
            player:GetData().__twofacedpenny = nil
            if not isContinued then
                local save = ConchBlessing.SaveManager and ConchBlessing.SaveManager.TryGetRunSave(player)
                if type(save) == "table" then save[SAVE_KEY] = nil end
            end
            -- A run saved before the slots moved into the run save has none, so
            -- its coins open fresh slots as they used to on every Continue.
            local state = getState(player, player:HasCollectible(TWO_FACED_PENNY_ID))
            if state then
                syncPennySlots(player, state)
                if state.floorKey == nil then state.floorKey = getFloorKey() end
            end
            refreshCounts(player, getRuntime(player))
        end
    end
end

function M.onPreGameExit()
    M._runReady = false
end

if HAS_POST_ADD_COLLECTIBLE then
    local priority = rawget(_G, "CallbackPriority")
    if type(ConchBlessing.AddPriorityCallback) == "function" then
        ConchBlessing:AddPriorityCallback(ModCallbacks.MC_POST_ADD_COLLECTIBLE,
            priority and priority.EARLY or -100, M.onPostAddCollectible)
    else
        ConchBlessing:AddCallback(ModCallbacks.MC_POST_ADD_COLLECTIBLE, M.onPostAddCollectible)
    end
end

M._test = {
    state = function(player) return getState(player, false) end,
}

return M
