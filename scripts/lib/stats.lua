ConchBlessing.stats = {}
-- Define local flag to avoid linter warning when REPENTANCE_PLUS is not globally defined
local REPENTANCE_PLUS = rawget(_G, "REPENTANCE_PLUS")

-- base stats
ConchBlessing.stats.BASE_STATS = {
    damage = 3.5,           -- base damage
    tears = 7,              -- base shots per second (MaxFireDelay)
    speed = 1.0,            -- base speed
    range = 6.5,            -- base range
    luck = 0,               -- base luck
    shotSpeed = 1.0         -- base shot speed
}

-- Unified Multiplier Management System
ConchBlessing.stats.unifiedMultipliers = {}

-- Initialize unified multiplier system for a player
function ConchBlessing.stats.unifiedMultipliers:InitPlayer(player)
    if not player then return end
    
    local playerID = player:GetPlayerType()
    if not self[playerID] then
        self[playerID] = {
            itemMultipliers = {},    -- Individual item multipliers by item ID (per stat)
            itemAdditions = {},      -- Individual item additions by item ID (per stat)
            statMultipliers = {},    -- Current multipliers/additions state per stat
            lastUpdateFrame = 0,     -- Last frame when multipliers were updated
            sequenceCounter = 0,     -- Counter for tracking item update order (shared by mult/add)
            pendingCache = {}        -- Deferred cache flags to apply on next update
        }
        ConchBlessing.printDebug(string.format("Unified Multipliers: Initialized for player %d", playerID))
    end
end

-- Helper: convert an addition to an equivalent multiplier for display purposes
local function _toEquivalentMultiplierFromAddition(player, statType, addition)
    if not player or type(addition) ~= "number" then return 1.0 end
    if statType == "Damage" then
        local base = player.Damage
        if base == 0 then return 1.0 end
        return (base + addition) / base
    elseif statType == "Tears" then
        -- Tears uses SPS; convert via MaxFireDelay
        local baseFD = player.MaxFireDelay
        local baseSPS = 30 / (baseFD + 1)
        if baseSPS <= 0 then return 1.0 end
        return (baseSPS + addition) / baseSPS
    elseif statType == "Speed" then
        local base = player.MoveSpeed
        if base == 0 then return 1.0 end
        return (base + addition) / base
    elseif statType == "Range" then
        local base = player.TearRange
        if base == 0 then return 1.0 end
        return (base + addition) / base
    elseif statType == "ShotSpeed" then
        local base = player.ShotSpeed
        if base == 0 then return 1.0 end
        return (base + addition) / base
    elseif statType == "Luck" then
        -- Luck can be zero frequently; treat as display-only (no multiplier impact)
        return 1.0
    end
    return 1.0
end

-- Add or update multiplier for a specific item and stat
function ConchBlessing.stats.unifiedMultipliers:SetItemMultiplier(player, itemID, statType, multiplier, description)
    if not player or not itemID or not statType or not multiplier then
        ConchBlessing.printError("SetItemMultiplier: Invalid parameters")
        return
    end
    
    self:InitPlayer(player)
    local playerID = player:GetPlayerType()
    local currentFrame = Game():GetFrameCount()
    self[playerID].lastSetFrame = self[playerID].lastSetFrame or {}
    local key = tostring(itemID) .. ":" .. tostring(statType)
    
    -- Skip duplicate SetItemMultiplier calls within the same frame for the same item+stat
    if self[playerID].lastSetFrame[key] == currentFrame then
        ConchBlessing.printDebug(string.format("SetItemMultiplier skipped (same frame) for %s", key))
        return
    end
    
    ConchBlessing.printDebug(string.format("SetItemMultiplier: Player %d, Item %s, Stat %s, Value %.2fx", 
        playerID, tostring(itemID), statType, multiplier))
    
    -- Initialize item data structure
    if not self[playerID].itemMultipliers[itemID] then
        self[playerID].itemMultipliers[itemID] = {}
        ConchBlessing.printDebug(string.format("  Created new item entry for item %s", tostring(itemID)))
    end
    
    -- Only advance sequence if this is a new entry or the multiplier value actually changed
    local existing = self[playerID].itemMultipliers[itemID][statType]
    local willAdvanceSequence = true
    if existing and type(existing.value) == "number" and existing.value == multiplier then
        willAdvanceSequence = false
    end
    
    if willAdvanceSequence then
        self[playerID].sequenceCounter = self[playerID].sequenceCounter + 1
    end
    local currentSequence = self[playerID].sequenceCounter
    
    if willAdvanceSequence then
        ConchBlessing.printDebug(string.format("  Advancing sequence to %d for %s", currentSequence, key))
    else
        ConchBlessing.printDebug(string.format("  Sequence unchanged (%d) for %s (same value)", currentSequence, key))
    end
    
    self[playerID].itemMultipliers[itemID][statType] = {
        value = multiplier,
        description = description or (existing and existing.description) or "Unknown",
        sequence = currentSequence,
        lastType = "multiplier"
    }
    
    ConchBlessing.printDebug(string.format("  Stored: Item %s %s = %.2fx (Sequence: %d)", tostring(itemID), statType, multiplier, self[playerID].sequenceCounter))
    
    -- Show current item multipliers for this item
    ConchBlessing.printDebug(string.format("  Current multipliers for item %s:", tostring(itemID)))
    for stat, data in pairs(self[playerID].itemMultipliers[itemID]) do
        ConchBlessing.printDebug(string.format("    %s: %.2fx (%s)", stat, data.value, data.description))
    end
    
    -- Recalculate total multipliers for this stat
    self:RecalculateStatMultiplier(player, statType)
    
    -- Mark this item+stat as updated this frame (to avoid multiple increments across cache flags)
    self[playerID].lastSetFrame[key] = currentFrame
end

-- Add or update addition entry for a specific item and stat
function ConchBlessing.stats.unifiedMultipliers:SetItemAddition(player, itemID, statType, addition, description)
    if not player or not itemID or not statType or type(addition) ~= "number" then
        ConchBlessing.printError("SetItemAddition: Invalid parameters")
        return
    end

    self:InitPlayer(player)
    local playerID = player:GetPlayerType()
    local currentFrame = Game():GetFrameCount()
    self[playerID].lastSetFrameAdd = self[playerID].lastSetFrameAdd or {}
    local key = tostring(itemID) .. ":" .. tostring(statType)

    -- Skip duplicate SetItemAddition calls within the same frame for the same item+stat
    if self[playerID].lastSetFrameAdd[key] == currentFrame then
        ConchBlessing.printDebug(string.format("SetItemAddition skipped (same frame) for %s", key))
        return
    end

    ConchBlessing.printDebug(string.format("SetItemAddition: Player %d, Item %s, Stat %s, Value %+0.2f", 
        playerID, tostring(itemID), statType, addition))

    -- Initialize item data structure for additions
    if not self[playerID].itemAdditions[itemID] then
        self[playerID].itemAdditions[itemID] = {}
        ConchBlessing.printDebug(string.format("  Created new addition entry for item %s", tostring(itemID)))
    end

    local existing = self[playerID].itemAdditions[itemID][statType]
    self[playerID].sequenceCounter = self[playerID].sequenceCounter + 1
    local currentSequence = self[playerID].sequenceCounter

    local eqMult = _toEquivalentMultiplierFromAddition(player, statType, addition)

    self[playerID].itemAdditions[itemID][statType] = {
        lastDelta = addition,                                 -- last delta to display with '+'
        cumulative = (existing and existing.cumulative or 0) + addition, -- cumulative for this item if needed
        description = description or (existing and existing.description) or "Unknown",
        sequence = currentSequence,
        lastType = "addition",
        eqMult = eqMult
    }

    ConchBlessing.printDebug(string.format("  Stored Addition: Item %s %s = %+0.2f (Cumulative: %+0.2f, Sequence: %d)", 
        tostring(itemID), statType, addition, self[playerID].itemAdditions[itemID][statType].cumulative, currentSequence))

    -- Recalculate (for display + cache queueing)
    self:RecalculateStatMultiplier(player, statType)

    -- Mark this item+stat as updated this frame
    self[playerID].lastSetFrameAdd[key] = currentFrame
end

-- Add or update additive-multiplier entry for a specific item and stat
-- Accepts a multiplier value (e.g., 1.20) and stores display as +0.20 while using 1.20 for total display
function ConchBlessing.stats.unifiedMultipliers:SetItemAdditiveMultiplier(player, itemID, statType, multiplierValue, description)
    if not player or not itemID or not statType or type(multiplierValue) ~= "number" then
        ConchBlessing.printError("SetItemAdditiveMultiplier: Invalid parameters")
        return
    end

    self:InitPlayer(player)
    local playerID = player:GetPlayerType()
    local currentFrame = Game():GetFrameCount()
    self[playerID].lastSetFrameAddMul = self[playerID].lastSetFrameAddMul or {}
    local key = tostring(itemID) .. ":" .. tostring(statType)

    -- Allow updates in the same frame if the delta changed; skip only when identical
    if self[playerID].lastSetFrameAddMul[key] == currentFrame then
        local existing = self[playerID].itemAdditions[itemID] and self[playerID].itemAdditions[itemID][statType]
        local prevDelta = existing and existing.lastDelta or nil
        local newDelta = multiplierValue - 1.0
        if prevDelta and math.abs(prevDelta - newDelta) < 0.00001 then
            ConchBlessing.printDebug(string.format("SetItemAdditiveMultiplier skipped (same frame, same delta) for %s", key))
            return
        end
    end

    local delta = multiplierValue - 1.0
    ConchBlessing.printDebug(string.format("SetItemAdditiveMultiplier: Player %d, Item %s, Stat %s, Mult %.2fx (Delta %+0.2f)", 
        playerID, tostring(itemID), statType, multiplierValue, delta))

    -- Initialize item data structure for additions
    if not self[playerID].itemAdditions[itemID] then
        self[playerID].itemAdditions[itemID] = {}
        ConchBlessing.printDebug(string.format("  Created new additive-mult entry for item %s", tostring(itemID)))
    end

    local existing = self[playerID].itemAdditions[itemID][statType]
    self[playerID].sequenceCounter = self[playerID].sequenceCounter + 1
    local currentSequence = self[playerID].sequenceCounter

    -- Update existing entry rather than overwrite to preserve running cumulative per itemID
    local entry = self[playerID].itemAdditions[itemID][statType] or {}
    entry.lastDelta = delta
    entry.cumulative = (entry.cumulative or 0) + delta
    entry.description = description or entry.description or "Unknown"
    entry.sequence = currentSequence
    entry.lastType = "addition"
    entry.eqMult = multiplierValue
    self[playerID].itemAdditions[itemID][statType] = entry

    ConchBlessing.printDebug(string.format("  Stored Additive Mult: Item %s %s = x%.2f (Delta %+0.2f, Seq %d)", 
        tostring(itemID), statType, multiplierValue, delta, currentSequence))

    -- Recalculate (for display + cache queueing)
    self:RecalculateStatMultiplier(player, statType)

    -- Mark this item+stat as updated this frame
    self[playerID].lastSetFrameAddMul[key] = currentFrame
end

-- Remove multiplier for a specific item and stat
function ConchBlessing.stats.unifiedMultipliers:RemoveItemMultiplier(player, itemID, statType)
    if not player or not itemID or not statType then return end
    
    local playerID = player:GetPlayerType()
    if self[playerID] and self[playerID].itemMultipliers[itemID] then
        self[playerID].itemMultipliers[itemID][statType] = nil
        
        -- Remove empty item entry
        if not next(self[playerID].itemMultipliers[itemID]) then
            self[playerID].itemMultipliers[itemID] = nil
        end
        
        -- Recalculate total multipliers for this stat
        self:RecalculateStatMultiplier(player, statType)
        
        ConchBlessing.printDebug(string.format("Unified Multipliers: Removed Item %d %s", itemID, statType))
    end
end

-- Remove addition for a specific item and stat
function ConchBlessing.stats.unifiedMultipliers:RemoveItemAddition(player, itemID, statType)
    if not player or not itemID or not statType then return end

    local playerID = player:GetPlayerType()
    if self[playerID] and self[playerID].itemAdditions and self[playerID].itemAdditions[itemID] then
        self[playerID].itemAdditions[itemID][statType] = nil

        -- Remove empty item entry
        if not next(self[playerID].itemAdditions[itemID]) then
            self[playerID].itemAdditions[itemID] = nil
        end

        -- Recalculate
        self:RecalculateStatMultiplier(player, statType)

        ConchBlessing.printDebug(string.format("Unified Multipliers: Removed Addition Item %d %s", itemID, statType))
    end
end

-- Recalculate total multiplier for a specific stat
function ConchBlessing.stats.unifiedMultipliers:RecalculateStatMultiplier(player, statType)
    if not player or not statType then return end
    
    local playerID = player:GetPlayerType()
    if not self[playerID] then return end
    
    local totalMultiplierApply = 1.0   -- product of per-item (base + cumulative delta)
    local totalMultiplierDisplay = 1.0 -- same as apply, also used for HUD display
    local lastItemCurrentVal = 1.0   -- May be multiplier or addition delta
    local lastItemID = nil
    local lastDescription = ""
    local lastSequence = 0
    local lastType = "multiplier"    -- "multiplier" | "addition"
    
    ConchBlessing.printDebug(string.format("Recalculating %s for player %d:", statType, playerID))
    
    -- Build union of touched itemIDs (have base multiplier and/or additions)
    local touched = {}
    for itemID, itemData in pairs(self[playerID].itemMultipliers) do
        if itemData[statType] then touched[itemID] = true end
    end
    if self[playerID].itemAdditions then
        for itemID, itemData in pairs(self[playerID].itemAdditions) do
            if itemData[statType] then touched[itemID] = true end
        end
    end

    -- Aggregate per item: itemTotal = baseMultiplier + cumulativeDelta (default base=1, delta=0)
    for itemID, _ in pairs(touched) do
        local baseM, baseSeq, baseDesc = 1.0, 0, ""
        if self[playerID].itemMultipliers[itemID] and self[playerID].itemMultipliers[itemID][statType] then
            baseM = self[playerID].itemMultipliers[itemID][statType].value or 1.0
            baseSeq = self[playerID].itemMultipliers[itemID][statType].sequence or 0
            baseDesc = self[playerID].itemMultipliers[itemID][statType].description or ""
        end
        local addCum, addSeq, addLastDelta, addDesc = 0, 0, 0, ""
        if self[playerID].itemAdditions and self[playerID].itemAdditions[itemID] and self[playerID].itemAdditions[itemID][statType] then
            local ad = self[playerID].itemAdditions[itemID][statType]
            addCum = ad.cumulative or 0
            addSeq = ad.sequence or 0
            addLastDelta = ad.lastDelta or 0
            addDesc = ad.description or ""
        end
        local itemTotal = baseM + addCum
        totalMultiplierApply = totalMultiplierApply * itemTotal
        totalMultiplierDisplay = totalMultiplierDisplay * itemTotal

        -- Track latest change by sequence
        if addSeq >= baseSeq and addSeq > lastSequence then
            lastItemCurrentVal = addLastDelta
            lastItemID = itemID
            lastDescription = addDesc
            lastSequence = addSeq
            lastType = "addition"
            ConchBlessing.printDebug(string.format("  Item %s: base=%.2f, addCum=%+0.2f (last %+0.2f) => itemTotal=%.2f", tostring(itemID), baseM, addCum, addLastDelta, itemTotal))
        elseif baseSeq > lastSequence then
            lastItemCurrentVal = baseM
            lastItemID = itemID
            lastDescription = baseDesc
            lastSequence = baseSeq
            lastType = "multiplier"
            ConchBlessing.printDebug(string.format("  Item %s: base=%.2f, addCum=%+0.2f => itemTotal=%.2f", tostring(itemID), baseM, addCum, itemTotal))
        end
    end
    
    -- Store the calculated total
    if not self[playerID].statMultipliers then
        self[playerID].statMultipliers = {}
    end
    
    self[playerID].statMultipliers[statType] = {
        current = lastItemCurrentVal,    -- Last item's individual value (multiplier or addition)
        total = totalMultiplierDisplay,  -- Display total multiplier (includes additions as eq. mult)
        totalApply = totalMultiplierApply, -- Apply-only total multiplier (pure multipliers)
        lastItemID = lastItemID,         -- Last item that modified this stat
        description = lastDescription,   -- Description of the last item
        sequence = lastSequence,         -- Sequence number of the last item
        currentType = lastType           -- "multiplier" | "addition"
    }
    
    if lastType == "addition" then
        ConchBlessing.printDebug(string.format("Unified Multipliers: %s recalculated - Current: %+0.2f (from %s, seq: %d), Total: %.2fx (display), Apply: %.2fx", 
            statType, lastItemCurrentVal, tostring(lastItemID), lastSequence, totalMultiplierDisplay, totalMultiplierApply))
    else
        ConchBlessing.printDebug(string.format("Unified Multipliers: %s recalculated - Current: %.2fx (from %s, seq: %d), Total: %.2fx (display), Apply: %.2fx", 
            statType, lastItemCurrentVal, tostring(lastItemID), lastSequence, totalMultiplierDisplay, totalMultiplierApply))
    end
    
    -- Update the multiplier display system
    if ConchBlessing.stats.multiplierDisplay then
        ConchBlessing.stats.multiplierDisplay:UpdateFromUnifiedSystem(player, statType, lastItemCurrentVal, totalMultiplierDisplay, lastType)
    end
    
    -- Defer cache update to next frame to avoid re-entrant EvaluateCache loops
    if not self._isEvaluatingCache then
        self:QueueCacheUpdate(player, statType)
    end
end

-- Get current and total multipliers for a stat
function ConchBlessing.stats.unifiedMultipliers:GetMultipliers(player, statType)
    if not player or not statType then return 1.0, 1.0 end
    
    local playerID = player:GetPlayerType()
    if not self[playerID] or not self[playerID].statMultipliers[statType] then
        return 1.0, 1.0
    end
    
    local data = self[playerID].statMultipliers[statType]
    return data.current, data.total
end

-- Get all multipliers for a player
function ConchBlessing.stats.unifiedMultipliers:GetAllMultipliers(player)
    if not player then return {} end
    
    local playerID = player:GetPlayerType()
    if not self[playerID] or not self[playerID].statMultipliers then
        return {}
    end
    
    return self[playerID].statMultipliers
end

-- Reset all multipliers for a player (for new game)
function ConchBlessing.stats.unifiedMultipliers:ResetPlayer(player)
    if not player then return end
    
    local playerID = player:GetPlayerType()
    self[playerID] = nil
    
    ConchBlessing.printDebug(string.format("Unified Multipliers: Reset for player %d", playerID))
end

-- Save multipliers to SaveManager
function ConchBlessing.stats.unifiedMultipliers:SaveToSaveManager(player)
    if not player then return end
    
    local playerID = player:GetPlayerType()
    if not self[playerID] then return end
    
    local SaveManager = require("scripts.lib.save_manager")
    local playerSave = SaveManager.GetRunSave(player)
    
    if playerSave then
        -- Serialize itemMultipliers and itemAdditions with string keys to avoid sparse array warnings
        local function serializeItemKey(itemID)
            return "i_" .. tostring(itemID)
        end
        local serialItemMultipliers = {}
        if self[playerID].itemMultipliers then
            for itemID, perItem in pairs(self[playerID].itemMultipliers) do
                local key = serializeItemKey(itemID)
                serialItemMultipliers[key] = {}
                for statType, data in pairs(perItem) do
                    serialItemMultipliers[key][statType] = {
                        value = data.value,
                        description = data.description,
                        sequence = data.sequence,
                        lastType = data.lastType
                    }
                end
            end
        end

        local serialItemAdditions = {}
        if self[playerID].itemAdditions then
            for itemID, perItem in pairs(self[playerID].itemAdditions) do
                local key = serializeItemKey(itemID)
                serialItemAdditions[key] = {}
                for statType, data in pairs(perItem) do
                    serialItemAdditions[key][statType] = {
                        lastDelta = data.lastDelta,
                        cumulative = data.cumulative,
                        description = data.description,
                        sequence = data.sequence,
                        lastType = data.lastType
                    }
                end
            end
        end

        playerSave.unifiedMultipliers = {
            itemMultipliers = serialItemMultipliers,
            itemAdditions = serialItemAdditions,
            statMultipliers = self[playerID].statMultipliers
        }
        SaveManager.Save()
        ConchBlessing.printDebug(string.format("Unified Multipliers: Saved to SaveManager for player %d", playerID))
    end
end

-- Load multipliers from SaveManager
function ConchBlessing.stats.unifiedMultipliers:LoadFromSaveManager(player)
    if not player then return end
    
    local playerID = player:GetPlayerType()
    local SaveManager = require("scripts.lib.save_manager")
    local playerSave = SaveManager.GetRunSave(player)
    
    if playerSave and playerSave.unifiedMultipliers then
        self:InitPlayer(player)
        local function deserializeItemKey(key)
            local id = tostring(key)
            local num = id:match("^i_(%d+)$")
            return num and tonumber(num) or key
        end
        self[playerID].itemMultipliers = {}
        if playerSave.unifiedMultipliers.itemMultipliers then
            for key, perItem in pairs(playerSave.unifiedMultipliers.itemMultipliers) do
                local itemID = deserializeItemKey(key)
                self[playerID].itemMultipliers[itemID] = perItem
            end
        end
        self[playerID].itemAdditions = {}
        if playerSave.unifiedMultipliers.itemAdditions then
            for key, perItem in pairs(playerSave.unifiedMultipliers.itemAdditions) do
                local itemID = deserializeItemKey(key)
                self[playerID].itemAdditions[itemID] = perItem
            end
        end
        self[playerID].statMultipliers = playerSave.unifiedMultipliers.statMultipliers or {}
        
        ConchBlessing.printDebug(string.format("Unified Multipliers: Loaded from SaveManager for player %d", playerID))
        
        -- Recalculate all stat multipliers to ensure consistency
        for statType, _ in pairs(self[playerID].statMultipliers) do
            self:RecalculateStatMultiplier(player, statType)
        end
    end
end

-- Multiplier display system (inspired by milkshake mod)
ConchBlessing.stats.multiplierDisplay = {}

-- Use Isaac's default font (like milkshake mod)
local StatsFont = Font()
StatsFont:Load("font/luaminioutlined.fnt")
ConchBlessing.printDebug("Using Isaac default font for multiplier display")

-- Input constants for tab button detection
local ButtonAction = {
    ACTION_MAP = ButtonAction.ACTION_MAP  -- Tab/Map button (use Isaac's built-in constant)
}

-- Display settings (same as milkshake mod)
local MULTIPLIER_DISPLAY_DURATION = 150
local MULTIPLIER_MOVEMENT_DURATION = 10
local MULTIPLIER_FADING_DURATION = 40

-- Tab button display settings (like stats-plus mod)
local TAB_DISPLAY_DURATION = 10  -- How long to show when tab is pressed
local TAB_DISPLAY_FADE_DURATION = 20  -- Fade out duration

-- HUD positions for each stat (based on actual HUD layout)
local STAT_POSITIONS = {
    Speed = {x = 75, y = 87},       -- Speed (이동속도) - 맨 위
    Tears = {x = 75, y = 99},       -- Tears (연사)
    Damage = {x = 75, y = 111},     -- Damage (데미지)
    Range = {x = 75, y = 123},      -- Range (사거리)
    ShotSpeed = {x = 75, y = 135},  -- Shot Speed (사거리 밑)
    Luck = {x = 75, y = 147}        -- Luck (맨 아래)
}

if REPENTANCE_PLUS then
    STAT_POSITIONS.Speed.y = 90
    STAT_POSITIONS.Tears.y = 102
    STAT_POSITIONS.Damage.y = 114
    STAT_POSITIONS.Range.y = 126
    STAT_POSITIONS.ShotSpeed.y = 138
    STAT_POSITIONS.Luck.y = 150
end

-- Player multiplier data storage
ConchBlessing.stats.multiplierDisplay.playerData = {}

-- Initialize player data
function ConchBlessing.stats.multiplierDisplay:InitPlayer(player)
    local playerID = player:GetPlayerType()
    if not self.playerData[playerID] then
        ConchBlessing.printDebug(string.format("InitPlayer: Creating new player data for player ID %d", playerID))
        self.playerData[playerID] = {
            displayStartFrame = 0,        -- When to start displaying
            isDisplaying = false,
            tabDisplayStartFrame = 0,     -- When tab display started
            isTabDisplaying = false,      -- Whether tab display is active
            lastDebugState = nil,         -- For tracking debug state changes
            lastDisplayLogicState = nil,  -- For tracking display logic changes
            lastDisplayState = nil,       -- For tracking display state changes
            lastTabState = nil            -- For tracking tab button state changes
        }
    end
end

-- Update display from unified multiplier system
function ConchBlessing.stats.multiplierDisplay:UpdateFromUnifiedSystem(player, statType, currentValue, totalMult, currentType)
    if not player or not statType then return end
    
    self:InitPlayer(player)
    local playerID = player:GetPlayerType()
    
    -- Store the updated multiplier data
    if not self.playerData[playerID].unifiedData then
        self.playerData[playerID].unifiedData = {}
    end
    
    self.playerData[playerID].unifiedData[statType] = {
        current = currentValue,
        total = totalMult,
        currentType = currentType or "multiplier",
        timestamp = Game():GetFrameCount()
    }
    
    -- Start display
    self.playerData[playerID].displayStartFrame = Game():GetFrameCount()
    self.playerData[playerID].isDisplaying = true
    
    if currentType == "addition" then
        ConchBlessing.printDebug(string.format("Multiplier Display Updated: %s - Current: %+0.2f, Total: %.2fx (addition)", 
            statType, currentValue, totalMult))
    else
        ConchBlessing.printDebug(string.format("Multiplier Display Updated: %s - Current: %.2fx, Total: %.2fx", 
            statType, currentValue, totalMult))
    end
    
    -- Debug: Show current unified data state
    ConchBlessing.printDebug(string.format("  Current unified data for player %d:", playerID))
    for stat, data in pairs(self.playerData[playerID].unifiedData) do
        if data.currentType == "addition" then
            ConchBlessing.printDebug(string.format("    %s: Current=%+0.2f, Total=%.2fx", stat, data.current, data.total))
        else
            ConchBlessing.printDebug(string.format("    %s: Current=%.2fx, Total=%.2fx", stat, data.current, data.total))
        end
    end
end

-- Render a single multiplier stat (like milkshake mod)
local function RenderMultiplierStat(statType, currentValue, totalMult, currentType, pos, alpha)
    -- Type validation for multipliers
    if type(currentValue) ~= "number" or type(totalMult) ~= "number" then
        ConchBlessing.printError(string.format("RenderMultiplierStat: currentValue and totalMult must be numbers, got %s and %s", 
            type(currentValue), type(totalMult)))
        return
    end
    
    -- Format: Current/Total
    --  - multiplier: x1.20
    --  - addition: +1.20
    local currentText
    if currentType == "addition" then
        currentText = string.format("%+0.2f", currentValue)
    else
        currentText = string.format("x%.2f", currentValue)
    end
    local totalValue = string.format("/x%.2f", totalMult)
    
    pos = pos + (Options.HUDOffset * Vector(20, 12))
    pos = pos + Game().ScreenShakeOffset
    
    -- Current value color (green for positive, red for negative, white for neutral)
    local currentColor
    if currentType == "addition" then
        if currentValue > 0 then
            currentColor = KColor(0/255, 255/255, 0/255, alpha)
        elseif currentValue < 0 then
            currentColor = KColor(255/255, 0/255, 0/255, alpha)
        else
            currentColor = KColor(255/255, 255/255, 255/255, alpha)
        end
    else
        if currentValue > 1.0 then
            currentColor = KColor(0/255, 255/255, 0/255, alpha)
        elseif currentValue == 1.0 then
            currentColor = KColor(255/255, 255/255, 255/255, alpha)
        else
            currentColor = KColor(255/255, 0/255, 0/255, alpha)
        end
    end
    
    -- Total multiplier color (누적된 총 배수) - 파란색 계열로 구분
    local totalColor
    if totalMult > 1.0 then
        -- Blue for total multipliers above 1.0x
        totalColor = KColor(100/255, 150/255, 255/255, alpha)
    elseif totalMult == 1.0 then
        -- Light blue for exactly 1.0x
        totalColor = KColor(150/255, 200/255, 255/255, alpha)
    else
        -- Dark blue for total multipliers below 1.0x
        totalColor = KColor(50/255, 100/255, 200/255, alpha)
    end
    
    -- Render current multiplier first
    StatsFont:DrawString(
        currentText,         -- current value text
        pos.X,               -- X position
        pos.Y,               -- Y position
        currentColor,        -- current multiplier color
        0,                   -- alignment (0 = left)
        true                 -- center text
    )
    
    -- Calculate position for total multiplier (current text width + small gap)
    local currentTextWidth = StatsFont:GetStringWidth(currentText)
    local gap = 2  -- Small gap between current and total
    local totalX = pos.X + currentTextWidth + gap
    
    -- Render total multiplier
    StatsFont:DrawString(
        totalValue,          -- total multiplier text
        totalX,              -- X position (after current)
        pos.Y,               -- Y position (same as current)
        totalColor,          -- total multiplier color
        0,                   -- alignment (0 = left)
        true                 -- center text
    )
end

-- Render multiplier display for a player
function ConchBlessing.stats.multiplierDisplay:RenderPlayer(player)
    local playerID = player:GetPlayerType()
    
    if not self.playerData[playerID] then return end
    
    local data = self.playerData[playerID]
    
    -- Check if we have unified data to display
    if not data.unifiedData or not next(data.unifiedData) then
        return
    end
    
    -- Check if we should display
    local shouldDisplay = false
    local displayType = "none"
    local currentFrame = Game():GetFrameCount()
    
    -- Check tab button state (like stats-plus mod)
    local isTabPressed = Input.IsActionPressed(ButtonAction.ACTION_MAP, player.ControllerIndex or 0)
    
    if isTabPressed then
        -- Tab button is pressed, start tab display and override any existing display
        if not data.isTabDisplaying then
            data.isTabDisplaying = true
            data.tabDisplayStartFrame = currentFrame
        end
        shouldDisplay = true
        displayType = "tab"
    else
        -- Tab button not pressed, check if we should continue tab fade
        if data.isTabDisplaying then
            -- Tab display was active, check if we should continue showing
            local tabDuration = currentFrame - data.tabDisplayStartFrame
            local totalTabDuration = TAB_DISPLAY_DURATION + TAB_DISPLAY_FADE_DURATION
            
            if tabDuration < totalTabDuration then
                shouldDisplay = true
                displayType = "tab_fade"
            else
                data.isTabDisplaying = false
            end
        end
        
        -- Only check normal display if tab display is not active
        if not shouldDisplay and data.isDisplaying then
            local duration = currentFrame - data.displayStartFrame
            if duration < MULTIPLIER_DISPLAY_DURATION then
                shouldDisplay = true
                displayType = "normal"
            else
                data.isDisplaying = false
            end
        end
    end
    
    if not shouldDisplay then 
        return 
    end
    
    if not Options.FoundHUD then 
        return 
    end
    
    local alpha = 0.5
    
    -- Calculate alpha based on display type (like stats-plus mod)
    if displayType == "tab" then
        -- Tab display: full alpha while button is held
        alpha = 0.8
    elseif displayType == "tab_fade" then
        -- Tab fade: calculate fade out alpha and override normal display timing
        local tabDuration = currentFrame - data.tabDisplayStartFrame
        local fadeStart = TAB_DISPLAY_DURATION
        local fadeEnd = fadeStart + TAB_DISPLAY_FADE_DURATION
        
        if tabDuration <= fadeStart then
            -- Still in full display period
            alpha = 0.8
        elseif tabDuration <= fadeEnd then
            -- In fade out period
            local fadePercent = (fadeEnd - tabDuration) / TAB_DISPLAY_FADE_DURATION
            alpha = 0.8 * fadePercent
        else
            -- Fade out completed
            alpha = 0
        end
        
        -- Force normal display to end when tab fade starts
        if data.isDisplaying then
            data.isDisplaying = false
        end
    else
        -- Normal display: use existing animation logic
        local duration = currentFrame - data.displayStartFrame
        
        -- Animation effects (like milkshake mod)
        local animationOffset = 0
        if duration <= MULTIPLIER_MOVEMENT_DURATION then
            local percent = duration / MULTIPLIER_MOVEMENT_DURATION
            local movementPercent = math.sin((percent * math.pi) / 2) -- Simple easing
            
            animationOffset = 20 + (0 - 20) * movementPercent
            alpha = 0 + (0.5 - 0) * percent
        end
        
        if MULTIPLIER_DISPLAY_DURATION - duration <= MULTIPLIER_FADING_DURATION then
            local percent = (MULTIPLIER_DISPLAY_DURATION - duration) / MULTIPLIER_FADING_DURATION
            alpha = 0 + (0.5 - 0) * percent
        end
    end
    
    -- Multiplayer adjustments (like milkshake mod)
    local multiplayerOffset = 0
    if Game():GetNumPlayers() > 1 then
        if player:GetPlayerType() == PlayerType.PLAYER_ISAAC then
            multiplayerOffset = -4
        else
            multiplayerOffset = 4
        end
    end
    
    -- Challenge mode adjustments (like milkshake mod)
    local challengeOffset = 0
    if Game().Challenge == Challenge.CHALLENGE_NULL
    and Game().Difficulty == Difficulty.DIFFICULTY_NORMAL then
        challengeOffset = -15.5
    end
    
    -- Character-specific adjustments (like milkshake mod)
    local characterOffset = 0
    if player:GetPlayerType() == PlayerType.PLAYER_BETHANY then
        characterOffset = 10
    elseif player:GetPlayerType() == PlayerType.PLAYER_BETHANY_B then
        characterOffset = 10
    elseif player:GetPlayerType() == PlayerType.PLAYER_BLUEBABY_B then
        characterOffset = 10
    end
    
    if player:GetPlayerType() == PlayerType.PLAYER_JACOB or player:GetPlayerType() == PlayerType.PLAYER_ESAU then
        characterOffset = characterOffset + 16
    end
    
    -- Animation effects (like milkshake mod)
    local animationOffset = 0
    if displayType == "normal" then
        local duration = currentFrame - data.displayStartFrame
        if duration <= MULTIPLIER_MOVEMENT_DURATION then
            local percent = duration / MULTIPLIER_MOVEMENT_DURATION
            local movementPercent = math.sin((percent * math.pi) / 2) -- Simple easing
            
            animationOffset = 20 + (0 - 20) * movementPercent
        end
    elseif displayType == "tab" or displayType == "tab_fade" then
        -- Tab display: no animation offset, static position
        animationOffset = 0
    end
    
    -- Render each stat multiplier at their specific HUD positions
    local renderedCount = 0
    
    for statType, multiplierData in pairs(data.unifiedData) do
        local statPos = STAT_POSITIONS[statType]
        if statPos then
            local finalX = statPos.x - animationOffset
            local finalY = statPos.y + multiplayerOffset + challengeOffset + characterOffset
            local pos = Vector(finalX, finalY)
            
            RenderMultiplierStat(statType, multiplierData.current, multiplierData.total, multiplierData.currentType, pos, alpha)
            renderedCount = renderedCount + 1
        end
    end
end

-- Render all players' multiplier displays
function ConchBlessing.stats.multiplierDisplay:Render()
    local playerCount = 0
    local numPlayers = Game():GetNumPlayers()
    
    for i = 0, numPlayers - 1 do
        local player = Isaac.GetPlayer(i)
        if player then
            self:RenderPlayer(player)
            playerCount = playerCount + 1
        end
    end
    
    if playerCount > 0 and not self.lastProcessedCount then
        ConchBlessing.printDebug("Render() completed, processed " .. playerCount .. " players")
        self.lastProcessedCount = playerCount
    end
end

-- Initialize multiplier display system (called externally when ready)
function ConchBlessing.stats.multiplierDisplay:Initialize()
    if not self.initialized then
        self.initialized = true
        ConchBlessing.printDebug("Multiplier display system initialized!")
        
        -- Add render callback for multiplier display
        ConchBlessing.originalMod:AddCallback(ModCallbacks.MC_POST_RENDER, function()
            if ConchBlessing.stats and ConchBlessing.stats.multiplierDisplay then
                ConchBlessing.stats.multiplierDisplay:Render()
            end
        end)
        ConchBlessing.print("Render callback registered!")
    end
end

-- Reset all multiplier data for a new game
function ConchBlessing.stats.multiplierDisplay:ResetForNewGame()
    ConchBlessing.printDebug("Resetting multiplier display data for new game")
    self.playerData = {}
    self.lastProcessedCount = nil
    ConchBlessing.printDebug("Multiplier display data reset completed")
end

-- Force show multiplier display (for testing or external triggers)
function ConchBlessing.stats.multiplierDisplay:ForceShow(player, duration)
    if not player then return end
    
    self:InitPlayer(player)
    local playerID = player:GetPlayerType()
    
    self.playerData[playerID].displayStartFrame = Game():GetFrameCount()
    self.playerData[playerID].isDisplaying = true
    
    ConchBlessing.printDebug("Force showing multiplier display for " .. (duration or MULTIPLIER_DISPLAY_DURATION) .. " frames")
end

-- Legacy functions for backward compatibility (deprecated)
function ConchBlessing.stats.multiplierDisplay:ShowDetailedMultipliers(player, statType, currentMult, description, itemID, updateDisplayOnly)
    ConchBlessing.printDebug("ShowDetailedMultipliers is deprecated, use unifiedMultipliers:SetItemMultiplier instead")
    return false
end

function ConchBlessing.stats.multiplierDisplay:SetMultiplier(player, statType, currentMult, totalMult)
    ConchBlessing.printDebug("SetMultiplier is deprecated, use unifiedMultipliers:SetItemMultiplier instead")
    return false
end

function ConchBlessing.stats.multiplierDisplay:StoreMultiplierData(player, statType, currentMult, totalMult)
    ConchBlessing.printDebug("StoreMultiplierData is deprecated, use unifiedMultipliers:SetItemMultiplier instead")
    return false
end

function ConchBlessing.stats.multiplierDisplay:ShowMultipliers(player, statType, currentMult, totalMult)
    ConchBlessing.printDebug("ShowMultipliers is deprecated, use unifiedMultipliers:SetItemMultiplier instead")
    return false
end

-- damage related functions
ConchBlessing.stats.damage = {}

-- apply damage multiplier (includes poison damage)
function ConchBlessing.stats.damage.applyMultiplier(player, multiplier, minDamage, showDisplay)
    if not player then 
        ConchBlessing.printError("Player not found in ConchBlessing.stats.damage.applyMultiplier")
        return
    end
    
    local baseDamage = player.Damage
    local newDamage = baseDamage * multiplier
    
    -- apply minimum damage limit
    if minDamage then
        newDamage = math.max(minDamage, newDamage)
    end
    
    player.Damage = newDamage
    
    -- apply poison damage multiplier
    ConchBlessing.stats.damage.applyPoisonDamageMultiplier(player, multiplier)
    
    return newDamage
end

-- apply damage addition (includes poison damage)
function ConchBlessing.stats.damage.applyAddition(player, addition, minDamage)
    if not player then return end
    
    local baseDamage = player.Damage
    local newDamage = baseDamage + addition
    
    -- apply minimum damage limit
    if minDamage then
        newDamage = math.max(minDamage, newDamage)
    end
    
    player.Damage = newDamage
    
    -- apply poison damage addition
    ConchBlessing.stats.damage.applyPoisonDamageAddition(player, addition)
    
    return newDamage
end

-- apply poison damage multiplier
function ConchBlessing.stats.damage.applyPoisonDamageMultiplier(player, multiplier)
    if not player then return end
    
    -- check if poison damage API is supported
    if not ConchBlessing.stats.damage.supportsTearPoisonAPI(player) then
        return
    end
    
    local pdata = player:GetData()
    
    -- save base poison damage (only on first application)
    if not pdata.conch_stats_tpd_base then
        pdata.conch_stats_tpd_base = player:GetTearPoisonDamage()
    end
    
    -- reset to base value if multiplier is 1.0
    if multiplier == 1.0 then
        pdata.conch_stats_tpd_base = player:GetTearPoisonDamage()
    end
    
    local basePoisonDamage = pdata.conch_stats_tpd_base or 0
    local newPoisonDamage = basePoisonDamage * multiplier
    
    player:SetTearPoisonDamage(newPoisonDamage)
    pdata.conch_stats_tpd_lastMult = multiplier
    
    return newPoisonDamage
end

-- apply poison damage addition
function ConchBlessing.stats.damage.applyPoisonDamageAddition(player, addition)
    if not player then return end
    
    -- check if poison damage API is supported
    if not ConchBlessing.stats.damage.supportsTearPoisonAPI(player) then
        return
    end
    
    local pdata = player:GetData()
    
    -- save base poison damage (only on first application)
    if not pdata.conch_stats_tpd_base then
        pdata.conch_stats_tpd_base = player:GetTearPoisonDamage()
    end
    
    local basePoisonDamage = pdata.conch_stats_tpd_base or 0
    local newPoisonDamage = basePoisonDamage + addition
    
    player:SetTearPoisonDamage(newPoisonDamage)
    
    return newPoisonDamage
end

-- check if poison damage API is supported
function ConchBlessing.stats.damage.supportsTearPoisonAPI(player)
    return player and type(player.GetTearPoisonDamage) == "function" and type(player.SetTearPoisonDamage) == "function"
end

-- shot speed related functions
ConchBlessing.stats.tears = {}

-- speed related functions
ConchBlessing.stats.speed = {}

-- apply speed multiplier
function ConchBlessing.stats.speed.applyMultiplier(player, multiplier, minSpeed, showDisplay)
    if not player then return end
    
    local baseSpeed = player.MoveSpeed
    local newSpeed = baseSpeed * multiplier
    
    -- apply minimum speed limit
    if minSpeed then
        newSpeed = math.max(minSpeed, newSpeed)
    end
    
    player.MoveSpeed = newSpeed
    
    return newSpeed
end

-- apply speed addition
function ConchBlessing.stats.speed.applyAddition(player, addition, minSpeed)
    if not player then return end
    
    local baseSpeed = player.MoveSpeed
    local newSpeed = baseSpeed + addition
    
    -- apply minimum speed limit
    if minSpeed then
        newSpeed = math.max(minSpeed, newSpeed)
    end
    
    player.MoveSpeed = newSpeed
    
    return newSpeed
end

-- range related functions
ConchBlessing.stats.range = {}

-- apply range multiplier
function ConchBlessing.stats.range.applyMultiplier(player, multiplier, minRange, showDisplay)
    if not player then return end
    
    local baseRange = player.TearRange
    local newRange = baseRange * multiplier
    
    -- apply minimum range limit
    if minRange then
        newRange = math.max(minRange, newRange)
    end
    
    player.TearRange = newRange
    
    return newRange
end

-- apply range addition
function ConchBlessing.stats.range.applyAddition(player, addition, minRange)
    if not player then return end
    
    local baseRange = player.TearRange
    local newRange = baseRange + addition
    
    -- apply minimum range limit
    if minRange then
        newRange = math.max(minRange, newRange)
    end
    
    player.TearRange = newRange
    
    return newRange
end

-- luck related functions
ConchBlessing.stats.luck = {}

-- apply luck multiplier
function ConchBlessing.stats.luck.applyMultiplier(player, multiplier, minLuck, showDisplay)
    if not player then return end
    
    local baseLuck = player.Luck
    local newLuck = baseLuck
    
    -- If base luck is zero, keep it at zero regardless of multiplier or clamp
    if baseLuck == 0 then
        newLuck = 0
    else
        newLuck = baseLuck * multiplier
        -- apply minimum luck limit only when base is not zero
        if minLuck then
            newLuck = math.max(minLuck, newLuck)
        end
    end
    
    player.Luck = newLuck
    
    return newLuck
end

-- apply luck addition
function ConchBlessing.stats.luck.applyAddition(player, addition, minLuck)
    if not player then return end
    
    local baseLuck = player.Luck
    local newLuck = baseLuck + addition
    
    -- apply minimum luck limit
    if minLuck then
        newLuck = math.max(minLuck, newLuck)
    end
    
    player.Luck = newLuck
    
    return newLuck
end

-- shot speed related functions
ConchBlessing.stats.shotSpeed = {}

-- apply shot speed multiplier
function ConchBlessing.stats.shotSpeed.applyMultiplier(player, multiplier, minShotSpeed, showDisplay)
    if not player then return end
    
    local baseShotSpeed = player.ShotSpeed
    local newShotSpeed = baseShotSpeed * multiplier
    
    -- apply minimum shot speed limit
    if minShotSpeed then
        newShotSpeed = math.max(minShotSpeed, newShotSpeed)
    end
    
    player.ShotSpeed = newShotSpeed
    
    return newShotSpeed
end

-- apply shot speed addition
function ConchBlessing.stats.shotSpeed.applyAddition(player, addition, minShotSpeed)
    if not player then return end
    
    local baseShotSpeed = player.ShotSpeed
    local newShotSpeed = baseShotSpeed + addition
    
    -- apply minimum shot speed limit
    if minShotSpeed then
        newShotSpeed = math.max(minShotSpeed, newShotSpeed)
    end
    
    player.ShotSpeed = newShotSpeed
    
    return newShotSpeed
end

-- calculate MaxFireDelay based on SPS (Shots Per Second)
function ConchBlessing.stats.tears.calculateMaxFireDelay(baseFireDelay, multiplier, minFireDelay)
    if not baseFireDelay or not multiplier then return baseFireDelay end
    
    -- calculate SPS: SPS = 30 / (MaxFireDelay + 1)
    local baseSPS = 30 / (baseFireDelay + 1)
    local targetSPS = baseSPS * multiplier
    local newMaxFireDelay = math.max(0, (30 / targetSPS) - 1)
    
    -- apply minimum fire delay limit
    if minFireDelay then
        newMaxFireDelay = math.max(minFireDelay, newMaxFireDelay)
    end
    
    return newMaxFireDelay
end

-- apply fire delay multiplier (based on SPS)
function ConchBlessing.stats.tears.applyMultiplier(player, multiplier, minFireDelay, showDisplay)
    if not player then return end
    
    local baseFireDelay = player.MaxFireDelay
    local newFireDelay = ConchBlessing.stats.tears.calculateMaxFireDelay(baseFireDelay, multiplier, minFireDelay)
    
    player.MaxFireDelay = newFireDelay
    
    return newFireDelay
end

-- apply fire delay addition (based on SPS)
function ConchBlessing.stats.tears.applyAddition(player, addition, minFireDelay)
    if not player then return end
    
    local baseFireDelay = player.MaxFireDelay
    local baseSPS = 30 / (baseFireDelay + 1)
    local targetSPS = baseSPS + addition
    local newMaxFireDelay = math.max(0, (30 / targetSPS) - 1)
    
    -- apply minimum fire delay limit
    if minFireDelay then
        newMaxFireDelay = math.max(minFireDelay, newMaxFireDelay)
    end
    
    player.MaxFireDelay = newMaxFireDelay

    return newMaxFireDelay
end

-- unified stats apply functions
ConchBlessing.stats.unified = {}

-- apply multiplier to all stats
function ConchBlessing.stats.unified.applyMultiplierToAll(player, multiplier, minStats, showDisplay)
    if not player then return end
    
    minStats = minStats or ConchBlessing.stats.BASE_STATS
    
    -- damage
    ConchBlessing.stats.damage.applyMultiplier(player, multiplier, minStats.damage * 0.4, showDisplay)
    
    -- fire delay (based on SPS)
    ConchBlessing.stats.tears.applyMultiplier(player, multiplier, minStats.tears * 0.4, showDisplay)
    
    -- speed
    ConchBlessing.stats.speed.applyMultiplier(player, multiplier, minStats.speed * 0.4, showDisplay)
    
    -- range
    ConchBlessing.stats.range.applyMultiplier(player, multiplier, minStats.range * 0.4, showDisplay)
    
    -- luck
    ConchBlessing.stats.luck.applyMultiplier(player, multiplier, minStats.luck * 0.4, showDisplay)
    
    -- shot speed
    ConchBlessing.stats.shotSpeed.applyMultiplier(player, multiplier, minStats.shotSpeed * 0.4, showDisplay)

    return true
end

-- apply addition to all stats
function ConchBlessing.stats.unified.applyAdditionToAll(player, addition, minStats)
    if not player then return end
    
    minStats = minStats or ConchBlessing.stats.BASE_STATS
    
    -- damage
    ConchBlessing.stats.damage.applyAddition(player, addition, minStats.damage * 0.4)
    
    -- fire delay (based on SPS)
    ConchBlessing.stats.tears.applyAddition(player, addition, minStats.tears * 0.4)
    
    -- speed
    ConchBlessing.stats.speed.applyAddition(player, addition, minStats.speed * 0.4)
    
    -- range
    ConchBlessing.stats.range.applyAddition(player, addition, minStats.range * 0.4)
    
    -- luck
    ConchBlessing.stats.luck.applyAddition(player, addition, minStats.luck * 0.4)
    
    -- shot speed
    ConchBlessing.stats.shotSpeed.applyAddition(player, addition, minStats.shotSpeed * 0.4)
    
    return true
end

-- set stats cache flag and recalculate
function ConchBlessing.stats.unified.updateCache(player, cacheFlag)
    if not player then return end
    
    if cacheFlag then
        player:AddCacheFlags(cacheFlag)
    else
        player:AddCacheFlags(CacheFlag.CACHE_ALL)
    end
    
    player:EvaluateItems()
end

-- Convenience functions for all stats
ConchBlessing.stats.applyToAll = function(player, statType, multiplier, minValue, showDisplay)
    if not player or not statType then return false end
    
    if statType == "damage" then
        return ConchBlessing.stats.damage.applyMultiplier(player, multiplier, minValue, showDisplay)
    elseif statType == "tears" then
        return ConchBlessing.stats.tears.applyMultiplier(player, multiplier, minValue, showDisplay)
    elseif statType == "speed" then
        return ConchBlessing.stats.speed.applyMultiplier(player, multiplier, minValue, showDisplay)
    elseif statType == "range" then
        return ConchBlessing.stats.range.applyMultiplier(player, multiplier, minValue, showDisplay)
    elseif statType == "luck" then
        return ConchBlessing.stats.luck.applyMultiplier(player, multiplier, minValue, showDisplay)
    elseif statType == "shotSpeed" then
        return ConchBlessing.stats.shotSpeed.applyMultiplier(player, multiplier, minValue, showDisplay)
    end
    
    return false
end

ConchBlessing.stats.addToAll = function(player, statType, addition, minValue)
    if not player or not statType then return false end
    
    if statType == "damage" then
        return ConchBlessing.stats.damage.applyAddition(player, addition, minValue)
    elseif statType == "tears" then
        return ConchBlessing.stats.tears.applyAddition(player, addition, minValue)
    elseif statType == "speed" then
        return ConchBlessing.stats.speed.applyAddition(player, addition, minValue)
    elseif statType == "range" then
        return ConchBlessing.stats.range.applyAddition(player, addition, minValue)
    elseif statType == "luck" then
        return ConchBlessing.stats.luck.applyAddition(player, addition, minValue)
    elseif statType == "shotSpeed" then
        return ConchBlessing.stats.shotSpeed.applyAddition(player, addition, minValue)
    end
    
    return false
end

-- Get current stat values
ConchBlessing.stats.getCurrentStats = function(player)
    if not player then return {} end
    
    return {
        damage = player.Damage,
        tears = 30 / (player.MaxFireDelay + 1), -- Convert to SPS
        speed = player.MoveSpeed,
        range = player.TearRange,
        luck = player.Luck,
        shotSpeed = player.ShotSpeed
    }
end

-- Get base stats
ConchBlessing.stats.getBaseStats = function()
    return ConchBlessing.stats.BASE_STATS
end

-- Apply stat multiplier to actual player stat
function ConchBlessing.stats.unifiedMultipliers:ApplyStatMultiplier(player, statType, totalMultiplier)
    if not player or not statType or not totalMultiplier then return end
    
    ConchBlessing.printDebug(string.format("Applying %s multiplier %.2fx to player", statType, totalMultiplier))
    
    -- Store original values for comparison
    local originalValues = {
        Tears = player.MaxFireDelay,
        Damage = player.Damage,
        Range = player.TearRange,
        Luck = player.Luck,
        Speed = player.MoveSpeed,
        ShotSpeed = player.ShotSpeed
    }
    
    ConchBlessing.printDebug(string.format("Original values - Tears: %.2f, Damage: %.2f, Range: %.2f, Luck: %.2f, Speed: %.2f, ShotSpeed: %.2f", 
        originalValues.Tears, originalValues.Damage, originalValues.Range, originalValues.Luck, originalValues.Speed, originalValues.ShotSpeed))
    
    -- Apply the multiplier based on stat type
    if statType == "Tears" then
        ConchBlessing.stats.tears.applyMultiplier(player, totalMultiplier, 0.1, false)
    elseif statType == "Damage" then
        ConchBlessing.stats.damage.applyMultiplier(player, totalMultiplier, 0.1, false)
    elseif statType == "Range" then
        ConchBlessing.stats.range.applyMultiplier(player, totalMultiplier, 0.1, false)
    elseif statType == "Luck" then
        ConchBlessing.stats.luck.applyMultiplier(player, totalMultiplier, 0.1, false)
    elseif statType == "Speed" then
        ConchBlessing.stats.speed.applyMultiplier(player, totalMultiplier, 0.1, false)
    elseif statType == "ShotSpeed" then
        ConchBlessing.stats.shotSpeed.applyMultiplier(player, totalMultiplier, 0.1, false)
    end
    
    -- Force cache update to apply changes
    player:AddCacheFlags(CacheFlag.CACHE_ALL)
    player:EvaluateItems()
    
    -- Check if values actually changed
    local newValues = {
        Tears = player.MaxFireDelay,
        Damage = player.Damage,
        Range = player.TearRange,
        Luck = player.Luck,
        Speed = player.MoveSpeed,
        ShotSpeed = player.ShotSpeed
    }
    
    ConchBlessing.printDebug(string.format("New values - Tears: %.2f, Damage: %.2f, Range: %.2f, Luck: %.2f, Speed: %.2f, ShotSpeed: %.2f", 
        newValues.Tears, newValues.Damage, newValues.Range, newValues.Luck, newValues.Speed, newValues.ShotSpeed))
    
    -- Force immediate stat update if no change detected
    if newValues[statType] == originalValues[statType] then
        ConchBlessing.printDebug(string.format("WARNING: %s value did not change, forcing direct update", statType))
        
        -- Direct stat manipulation as fallback
        if statType == "Tears" then
            local baseSPS = 30 / (originalValues.Tears + 1)
            local targetSPS = baseSPS * totalMultiplier
            local newFireDelay = math.max(0, (30 / targetSPS) - 1)
            player.MaxFireDelay = newFireDelay
            ConchBlessing.printDebug(string.format("Direct update: MaxFireDelay %.2f -> %.2f", originalValues.Tears, newFireDelay))
        elseif statType == "Damage" then
            local newDamage = originalValues.Damage * totalMultiplier
            player.Damage = newDamage
            ConchBlessing.printDebug(string.format("Direct update: Damage %.2f -> %.2f", originalValues.Damage, newDamage))
        elseif statType == "Range" then
            local newRange = originalValues.Range * totalMultiplier
            player.TearRange = newRange
            ConchBlessing.printDebug(string.format("Direct update: Range %.2f -> %.2f", originalValues.Range, newRange))
        elseif statType == "Luck" then
            local newLuck = originalValues.Luck * totalMultiplier
            player.Luck = newLuck
            ConchBlessing.printDebug(string.format("Direct update: Luck %.2f -> %.2f", originalValues.Luck, newLuck))
        elseif statType == "Speed" then
            local newSpeed = originalValues.Speed * totalMultiplier
            player.MoveSpeed = newSpeed
            ConchBlessing.printDebug(string.format("Direct update: Speed %.2f -> %.2f", originalValues.Speed, newSpeed))
        elseif statType == "ShotSpeed" then
            local newShotSpeed = originalValues.ShotSpeed * totalMultiplier
            player.ShotSpeed = newShotSpeed
            ConchBlessing.printDebug(string.format("Direct update: ShotSpeed %.2f -> %.2f", originalValues.ShotSpeed, newShotSpeed))
        end
        
        -- Force another cache update
        player:AddCacheFlags(CacheFlag.CACHE_ALL)
        player:EvaluateItems()
    end
    
    ConchBlessing.printDebug(string.format("Applied %s multiplier %.2fx and updated cache", statType, totalMultiplier))
end

-- Centralized cache handler that applies unified total multipliers during MC_EVALUATE_CACHE
do
    local CACHE_FLAG_TO_STAT = {
        [CacheFlag.CACHE_DAMAGE] = "Damage",
        [CacheFlag.CACHE_FIREDELAY] = "Tears",
        [CacheFlag.CACHE_SPEED] = "Speed",
        [CacheFlag.CACHE_RANGE] = "Range",
        [CacheFlag.CACHE_LUCK] = "Luck",
        [CacheFlag.CACHE_SHOTSPEED] = "ShotSpeed"
    }

    function ConchBlessing.stats.unifiedMultipliers:OnEvaluateCache(player, cacheFlag)
        if not player or not cacheFlag then return end
        local statType = CACHE_FLAG_TO_STAT[cacheFlag]
        if not statType then return end
        self._isEvaluatingCache = true -- mark evaluating

        self:InitPlayer(player)
        local playerID = player:GetPlayerType()
        local total = 1.0
        if self[playerID]
            and self[playerID].statMultipliers
            and self[playerID].statMultipliers[statType]
            and type(self[playerID].statMultipliers[statType].totalApply) == "number" then
            total = self[playerID].statMultipliers[statType].totalApply
        end

        ConchBlessing.printDebug(string.format("[Unified] Evaluating %s cache: applying pure total %.2fx", statType, total))

        if statType == "Tears" then
            ConchBlessing.stats.tears.applyMultiplier(player, total, 0.1, false)
        elseif statType == "Damage" then
            ConchBlessing.stats.damage.applyMultiplier(player, total, 0.1, false)
        elseif statType == "Range" then
            ConchBlessing.stats.range.applyMultiplier(player, total, 0.1, false)
        elseif statType == "Luck" then
            ConchBlessing.stats.luck.applyMultiplier(player, total, 0.1, false)
        elseif statType == "Speed" then
            ConchBlessing.stats.speed.applyMultiplier(player, total, 0.1, false)
        elseif statType == "ShotSpeed" then
            ConchBlessing.stats.shotSpeed.applyMultiplier(player, total, 0.1, false)
        end
        self._isEvaluatingCache = false -- unmark evaluating
    end

    -- Register global MC_EVALUATE_CACHE to enforce unified multipliers during cache eval
    ConchBlessing.originalMod:AddCallback(ModCallbacks.MC_EVALUATE_CACHE, function(_, player, cacheFlag)
        if ConchBlessing.stats and ConchBlessing.stats.unifiedMultipliers and ConchBlessing.stats.unifiedMultipliers.OnEvaluateCache then
            ConchBlessing.stats.unifiedMultipliers:OnEvaluateCache(player, cacheFlag)
        end
    end)

    -- Map stat to cache flag (shared)
    local STAT_TO_CACHE_FLAG = {
        Damage = CacheFlag.CACHE_DAMAGE,
        Tears = CacheFlag.CACHE_FIREDELAY,
        Speed = CacheFlag.CACHE_SPEED,
        Range = CacheFlag.CACHE_RANGE,
        Luck = CacheFlag.CACHE_LUCK,
        ShotSpeed = CacheFlag.CACHE_SHOTSPEED
    }

    -- Queue a cache update for a specific stat to be processed next frame
    function ConchBlessing.stats.unifiedMultipliers:QueueCacheUpdate(player, statType)
        if not player or not statType then return end
        self:InitPlayer(player)
        local playerID = player:GetPlayerType()
        local flag = STAT_TO_CACHE_FLAG[statType] or CacheFlag.CACHE_ALL
        self[playerID].pendingCache[flag] = true
        self._hasPending = true
        ConchBlessing.printDebug(string.format("[Unified] Queued cache update for %s (flag %d)", statType, flag))
    end

    -- Flush all queued cache updates safely in POST_UPDATE
    ConchBlessing.originalMod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
        if not ConchBlessing.stats or not ConchBlessing.stats.unifiedMultipliers or not ConchBlessing.stats.unifiedMultipliers._hasPending then
            return
        end
        local um = ConchBlessing.stats.unifiedMultipliers
        local numPlayers = Game():GetNumPlayers()
        for i = 0, numPlayers - 1 do
            local player = Isaac.GetPlayer(i)
            if player then
                local playerID = player:GetPlayerType()
                if um[playerID] and um[playerID].pendingCache then
                    local combined = 0
                    for flag, pending in pairs(um[playerID].pendingCache) do
                        if pending then
                            combined = combined | flag
                        end
                    end
                    if combined ~= 0 then
                        player:AddCacheFlags(combined)
                        player:EvaluateItems()
                        um[playerID].pendingCache = {}
                    end
                end
            end
        end
        um._hasPending = false
    end)
end

ConchBlessing.printDebug("Enhanced Stats library with unified multiplier system loaded successfully!")