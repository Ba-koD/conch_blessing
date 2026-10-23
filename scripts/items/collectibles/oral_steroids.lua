local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
ConchBlessing.oralsteroids = {}

local ORAL_STEROIDS_ID = Isaac.GetItemIdByName("Oral Steroids")

-- SaveManager integration
local SaveManager = require("scripts.lib.save_manager")

-- STATS: Item stat modifiers (Dark Rock style)
ConchBlessing.oralsteroids.STATS = {
    MIN_MULTIPLIER = 0.8,        -- Minimum random multiplier value
    MAX_MULTIPLIER = 1.5,        -- Maximum random multiplier value
    -- Floor for the APPLIED total multiplier, as a fraction of the minimum
    -- single roll. 0.5 means the total can never drop below half of it.
    MIN_TOTAL_MULTIPLIER_FACTOR = 0.5,
}

ConchBlessing.oralsteroids.data = {
    speedDecrease = 0
}

-- Copy count each player was last reconciled at. Keyed by the player entity
-- (GetPtrHash) and rebuilt every session; the rolls themselves live in that
-- player's own run save, which SaveManager keys by the collectible RNG seed, so
-- two players of one character, Esau or a character change keep their own rolls.
ConchBlessing.oralsteroids._lastItemCount = {}

-- Before game start a callback can still see the previous run's save table, so
-- nothing is rolled or trimmed until onGameStarted has reconciled every player.
-- A luamod reload in the middle of a run never sees game start, so it opens at once.
ConchBlessing.oralsteroids._runReady = type(Isaac.IsInGame) == "function" and Isaac.IsInGame() == true

-- One roll per copy, in pickup order. Without `create`, a player that never
-- had a roll gets no empty list in its save.
local function getRolls(player, create)
    local save = SaveManager.GetRunSave(player)
    if type(save) ~= "table" then return nil end
    if type(save.oralSteroids) ~= "table" then
        if create == false then return nil end
        save.oralSteroids = {}
    end
    return save.oralSteroids
end

local function rebuildOralUnified(player, stored)
    local um = ConchBlessing.stats.unifiedMultipliers
    um:RemoveItemAddition(player, ORAL_STEROIDS_ID, "Tears")
    um:RemoveItemAddition(player, ORAL_STEROIDS_ID, "Damage")
    um:RemoveItemAddition(player, ORAL_STEROIDS_ID, "Range")
    um:RemoveItemAddition(player, ORAL_STEROIDS_ID, "Luck")
    stored = stored or {}
    for i = 1, #stored do
        local m = stored[i]
        um:SetItemAdditiveMultiplier(player, ORAL_STEROIDS_ID, "Tears", m.tears or 1.0, "Oral Steroids #" .. i)
        um:SetItemAdditiveMultiplier(player, ORAL_STEROIDS_ID, "Damage", m.damage or 1.0, "Oral Steroids #" .. i)
        um:SetItemAdditiveMultiplier(player, ORAL_STEROIDS_ID, "Range", m.range or 1.0, "Oral Steroids #" .. i)
        um:SetItemAdditiveMultiplier(player, ORAL_STEROIDS_ID, "Luck", m.luck or 1.0, "Oral Steroids #" .. i)
    end
    -- StatsAPI applies 1 + sum(roll - 1) and clamps only at zero, so without this
    -- a run of bad rolls can drive a stat multiplier to 0. Lift the accumulated
    -- total back to the floor with one corrective entry.
    local cfg = ConchBlessing.oralsteroids.STATS
    local floorValue = (cfg.MIN_MULTIPLIER or 0) * (cfg.MIN_TOTAL_MULTIPLIER_FACTOR or 0)
    for _, pair in ipairs({ { "Tears", "tears" }, { "Damage", "damage" }, { "Range", "range" }, { "Luck", "luck" } }) do
        local statName, field = pair[1], pair[2]
        local total = 1.0
        for i = 1, #stored do
            total = total + ((stored[i][field] or 1.0) - 1.0)
        end
        if total < floorValue then
            um:SetItemAdditiveMultiplier(player, ORAL_STEROIDS_ID, statName,
                1.0 + (floorValue - total), "Oral Steroids floor")
            ConchBlessing.printDebug(string.format(
                "Oral Steroids: %s total %.3f floored to %.3f", statName, total, floorValue))
        end
    end
    um:SaveToSaveManager(player)
end

local function showOralRemovalDisplay(player, removedEntry)
    if not removedEntry then return end
    local um = ConchBlessing.stats.unifiedMultipliers
    local statMap = {
        Damage = "damage",
        Tears = "tears",
        Range = "range",
        Luck = "luck"
    }
    for statType, key in pairs(statMap) do
        local mult = removedEntry[key]
        if type(mult) == "number" then
            local delta = mult - 1.0
            if math.abs(delta) > 0.00001 then
                local total = ConchBlessing.getUnifiedStatTotal(player, statType, 1.0, um)
                ConchBlessing.stats.multiplierDisplay:ForceDisplay(player, statType, -delta, total, "remove_mult")
            end
        end
    end
end

ConchBlessing.oralsteroids.removeLastStack = function(player, removeCount, applyCacheUpdate)
    if not player then return end
    local stored = getRolls(player)
    if not stored then return end
    local current = #stored
    local remove = tonumber(removeCount) or 1
    if remove <= 0 or current <= 0 then return end
    local target = math.max(0, current - remove)
    local removedEntry = stored[current]
    for i = current, target + 1, -1 do
        stored[i] = nil
    end
    SaveManager.Save()
    rebuildOralUnified(player, stored)
    ConchBlessing.oralsteroids._lastItemCount[GetPtrHash(player)] = target
    if applyCacheUpdate ~= false then
        player:AddCacheFlags(CacheFlag.CACHE_ALL)
        player:EvaluateItems()
    end
    showOralRemovalDisplay(player, removedEntry)
end

-- Rolls the copies that have none yet; earlier rolls never change.
local function rollMissing(player, stored, itemNum)
    local storedCount = #stored
    if itemNum <= storedCount then return false end
    -- One stat roll. Lives on the module so the probe measures this exact
    -- expression instead of a copy of it.
    local rollStat = ConchBlessing.oralsteroids.rollStat
    for i = storedCount + 1, itemNum do
        local newMultipliers = {
            tears = rollStat(),
            damage = rollStat(),
            range = rollStat(),
            luck = rollStat()
        }
        stored[i] = newMultipliers
        ConchBlessing.printDebug(string.format("Oral Steroids #%d: Tears=%.2fx Damage=%.2fx Range=%.2fx Luck=%.2fx",
            i, newMultipliers.tears, newMultipliers.damage, newMultipliers.range, newMultipliers.luck))
    end
    SaveManager.Save()
    rebuildOralUnified(player, stored)
    ConchBlessing.printDebug("Oral Steroids: Added " .. (itemNum - storedCount) .. " new multipliers")
    return true
end

-- Brings one player's saved rolls in line with the copies it holds and
-- re-registers them. A Glowing Hourglass rewind restores the run save but not
-- StatsAPI, so with `clearStale` a player left with no rolls also has any
-- registration cleared. Returns true when a roll was added or removed or the
-- registration was rebuilt.
local function reconcile(player, clearStale)
    local itemNum = player:GetCollectibleNum(ORAL_STEROIDS_ID)
    local stored = getRolls(player, itemNum > 0)
    if not stored then
        ConchBlessing.oralsteroids._lastItemCount[GetPtrHash(player)] = itemNum
        if clearStale then
            rebuildOralUnified(player, nil)
            return true
        end
        return false
    end
    local changed = false
    if #stored > itemNum then
        ConchBlessing.oralsteroids.removeLastStack(player, #stored - itemNum, false)
        changed = true
    elseif #stored < itemNum then
        changed = rollMissing(player, stored, itemNum)
    elseif #stored > 0 or clearStale then
        rebuildOralUnified(player, stored)
        changed = clearStale == true
    end
    ConchBlessing.oralsteroids._lastItemCount[GetPtrHash(player)] = itemNum
    return changed
end

-- Every change in the copy count re-registers the saved rolls, so a rewind that
-- brings back or takes away a copy and its roll keeps StatsAPI in step.
ConchBlessing.oralsteroids.onPlayerUpdate = function(_, player)
    if not player or not ConchBlessing.oralsteroids._runReady then return end
    local itemNum = player:GetCollectibleNum(ORAL_STEROIDS_ID)
    if ConchBlessing.oralsteroids._lastItemCount[GetPtrHash(player)] == itemNum then return end
    if reconcile(player, true) then
        player:AddCacheFlags(CacheFlag.CACHE_ALL)
        player:EvaluateItems()
    end
end

ConchBlessing.oralsteroids.onEvaluateCache = function(_, player, cacheFlag)
    if not player or not ConchBlessing.oralsteroids._runReady then return end
    if not player:HasCollectible(ORAL_STEROIDS_ID) then return end
    local itemNum = player:GetCollectibleNum(ORAL_STEROIDS_ID)
    if itemNum <= 0 then return end
    local stored = getRolls(player)
    if not stored then return end

    if #stored > itemNum then
        ConchBlessing.oralsteroids.removeLastStack(player, #stored - itemNum, false)
    elseif itemNum > #stored then
        rollMissing(player, stored, itemNum)
    end

    if cacheFlag == CacheFlag.CACHE_DAMAGE and itemNum ~= ConchBlessing.oralsteroids._lastDebugItemNum then
        ConchBlessing.printDebug("Oral Steroids: stored rolls: " .. #stored .. " for " .. itemNum .. " copies")
        ConchBlessing.oralsteroids._lastDebugItemNum = itemNum
    end

    -- No direct stat application here; unified system will handle totals
    if cacheFlag == CacheFlag.CACHE_SPEED then
        local speedDecrease = ConchBlessing.oralsteroids.data.speedDecrease * itemNum
        ConchBlessing.stats.speed.applyAddition(player, -speedDecrease, ConchBlessing.oralsteroids.STATS.MIN_MULTIPLIER)
    end
end

-- Reconcile every player's rolls once SaveManager holds this run's table.
ConchBlessing.oralsteroids.onGameStarted = function(_)
    ConchBlessing.oralsteroids._lastItemCount = {}
    ConchBlessing.oralsteroids._runReady = true
    for i = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        if player and reconcile(player) then
            player:AddCacheFlags(CacheFlag.CACHE_ALL)
            player:EvaluateItems()
        end
    end
    ConchBlessing.printDebug("Oral Steroids: rolls reconciled for every player")
end

ConchBlessing.oralsteroids.onPreGameExit = function()
    ConchBlessing.oralsteroids._runReady = false
end

-- Register PRE_DATA_SAVE sanitizer for this item's run data only
do
    local sm = SaveManager
    local mod = ConchBlessing and ConchBlessing.originalMod
    if sm and mod and mod.__SAVEMANAGER_UNIQUE_KEY and sm.SaveCallbacks then
        local callbackKey = sm.SaveCallbacks.PRE_DATA_SAVE
        mod:AddCallback(callbackKey, function(_, saveData)
            if saveData and saveData.game and saveData.game.run then
                for _, playerRun in pairs(saveData.game.run) do
                    local arr = playerRun and playerRun.oralSteroids
                    if type(arr) == "table" then
                        -- Compact sparse array entries
                        local compacted = {}
                        local count = 0
                        for i = 1, #arr do
                            local v = arr[i]
                            if v ~= nil then
                                count = count + 1
                                compacted[count] = v
                            end
                        end
                        playerRun.oralSteroids = compacted
                    end
                end
            end
            if ConchBlessing and ConchBlessing.Config and ConchBlessing.Config.debugMode then
                ConchBlessing.printDebug("[OralSteroids] PRE_DATA_SAVE sanitized oralSteroids array")
            end
        end)
    end
end

-- Single stat multiplier roll: uniform over [MIN_MULTIPLIER, MAX_MULTIPLIER) truncated to 2 decimals,
-- so the mean is (min + max - 0.01) / 2, not (min + max) / 2.
function ConchBlessing.oralsteroids.rollStat()
    local r = math.random()
    local cfg = ConchBlessing.oralsteroids.STATS
    local span = cfg.MAX_MULTIPLIER - cfg.MIN_MULTIPLIER
    local value = math.floor((r * span + cfg.MIN_MULTIPLIER) * 100) / 100
    ConchBlessing.printDebug("Oral Steroids rollStat r=" .. string.format("%.6f", r) .. ", value=" .. string.format("%.2f", value))
    return value
end
