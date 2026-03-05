local ConchBlessing_Config = require("scripts.conch_blessing_config")
local ConchBlessing_MCM = require("scripts.conch_blessing_mcm")
local isc = require("scripts.lib.isaacscript-common")
local SaveManager = require("scripts.lib.save_manager")

local mod = RegisterMod("Conch's Blessing", 1)
ConchBlessing = isc:upgradeMod(mod, {
    isc.ISCFeature.PLAYER_INVENTORY,
    isc.ISCFeature.ROOM_HISTORY,
    isc.ISCFeature.GRID_ENTITY_COLLISION_DETECTION,
})
-- ConchBlessing now contains the upgraded mod, but mod variable keeps the original RegisterMod reference
ConchBlessing.originalMod = mod

-- Debug: SaveManager initialization started
Isaac.ConsoleOutput("[Core] SaveManager initialization started\n")

-- Make SaveManager globally accessible
ConchBlessing.SaveManager = SaveManager
Isaac.ConsoleOutput("[Core] ConchBlessing.SaveManager set\n")

-- Initialize SaveManager with the original mod reference
Isaac.ConsoleOutput("[Core] SaveManager.Init() called\n")
SaveManager.Init(mod)
Isaac.ConsoleOutput("[Core] SaveManager.Init() completed\n")

-- Register SaveManager PRE_DATA_SAVE callback to clean EntityEffect objects
Isaac.ConsoleOutput("[Core] Registering SaveManager PRE_DATA_SAVE callback\n")
local callbackKey = mod.__SAVEMANAGER_UNIQUE_KEY .. SaveManager.SaveCallbacks.PRE_DATA_SAVE
mod:AddCallback(callbackKey, function(saveData)
    -- Clean dragon EntityEffect objects before saving
    if ConchBlessing.dragon and ConchBlessing.dragon.onPreDataSave then
        return ConchBlessing.dragon.onPreDataSave(saveData)
    end
    return saveData
end)
Isaac.ConsoleOutput("[Core] SaveManager PRE_DATA_SAVE callback registered\n")

-- Check SaveManager status
Isaac.ConsoleOutput("[Core] SaveManager.IsLoaded() = " .. tostring(SaveManager.IsLoaded()) .. "\n")
Isaac.ConsoleOutput("[Core] SaveManager.VERSION = " .. tostring(SaveManager.VERSION) .. "\n")

-- Initialize config after SaveManager is initialized
Isaac.ConsoleOutput("[Core] ConchBlessing_Config.Init() called\n")
ConchBlessing_Config.Init(ConchBlessing)
Isaac.ConsoleOutput("[Core] ConchBlessing_Config.Init() completed\n")

-- MCM setup
Isaac.ConsoleOutput("[Core] MCM.Setup() called\n")
ConchBlessing_MCM.Setup(ConchBlessing)
Isaac.ConsoleOutput("[Core] MCM.Setup() completed\n")

local RUNTIME_QUEUE_PREFIX = "__CBQ__"
local RUNTIME_POLL_INTERVAL = 10
local RUNTIME_TEXT_FADE_DELAY = 120
local RUNTIME_TEXT_FADE_STEP = 0.02
local RUNTIME_TEXT_SCALE = 1
local RUNTIME_TEXT_LEFT_PADDING = 18
local RUNTIME_TEXT_BOTTOM_PADDING = 18
local game = Game()
local RuntimeOverlay = {
    font = Font(),
    frameOfLastMsg = 0,
    messages = {},
    maxMessages = 10,
}
RuntimeOverlay.font:Load("font/pftempestasevencondensed.fnt")

local function startsWith(text, prefix)
    return type(text) == "string" and string.sub(text, 1, #prefix) == prefix
end

local function showRuntimeNotice(message, kind)
    if type(message) ~= "string" or message == "" then
        return
    end

    RuntimeOverlay.frameOfLastMsg = Isaac.GetFrameCount()
    table.insert(RuntimeOverlay.messages, {
        text = message,
        kind = kind or "info",
    })
    if #RuntimeOverlay.messages > RuntimeOverlay.maxMessages then
        table.remove(RuntimeOverlay.messages, 1)
    end
end

local function renderRuntimeNotice()
    if #RuntimeOverlay.messages == 0 or RuntimeOverlay.frameOfLastMsg == 0 then
        return
    end

    if AwaitingTextInput then
        return
    end

    if game:IsPaused() then
        return
    end

    if ModConfigMenu ~= nil and ModConfigMenu.IsVisible then
        return
    end

    local elapsed = Isaac.GetFrameCount() - RuntimeOverlay.frameOfLastMsg
    local alpha = 1
    if elapsed > RUNTIME_TEXT_FADE_DELAY then
        alpha = 1 - (RUNTIME_TEXT_FADE_STEP * (elapsed - RUNTIME_TEXT_FADE_DELAY))
    end
    if alpha <= 0 then
        RuntimeOverlay.frameOfLastMsg = 0
        RuntimeOverlay.messages = {}
        return
    end

    local lineHeight = RuntimeOverlay.font:GetLineHeight() * RUNTIME_TEXT_SCALE
    local x = RUNTIME_TEXT_LEFT_PADDING
    local startY = Isaac.GetScreenHeight() - RUNTIME_TEXT_BOTTOM_PADDING - ((#RuntimeOverlay.messages - 1) * lineHeight)

    for i, entry in ipairs(RuntimeOverlay.messages) do
        local color = KColor(1, 1, 1, alpha)
        if entry.kind == "success" then
            color = KColor(0, 1, 0, alpha)
        elseif entry.kind == "error" then
            color = KColor(1, 0, 0, alpha)
        end

        RuntimeOverlay.font:DrawStringScaledUTF8(
            entry.text,
            x,
            startY + ((i - 1) * lineHeight),
            RUNTIME_TEXT_SCALE,
            RUNTIME_TEXT_SCALE,
            color,
            0,
            true
        )
    end
end

local function getRuntimeSettingsSave(create)
    if not ConchBlessing.SaveManager
        or type(ConchBlessing.SaveManager.IsLoaded) ~= "function"
        or not ConchBlessing.SaveManager.IsLoaded()
        or type(ConchBlessing.SaveManager.GetSettingsSave) ~= "function"
    then
        return nil, nil
    end

    local settingsSave = ConchBlessing.SaveManager.GetSettingsSave()
    if type(settingsSave) ~= "table" then
        return nil, nil
    end

    if create and type(settingsSave.runtimeQueue) ~= "table" then
        settingsSave.runtimeQueue = {}
    end

    local runtimeSave = settingsSave.runtimeQueue
    if type(runtimeSave) ~= "table" then
        return nil, settingsSave
    end
    return runtimeSave, settingsSave
end

local function setPendingRuntimeNotice(message)
    if type(message) ~= "string" or message == "" then
        return
    end

    local runtimeSave = getRuntimeSettingsSave(true)
    if type(runtimeSave) ~= "table" then
        return
    end

    runtimeSave.pendingNotice = message
    pcall(function()
        ConchBlessing.SaveManager.Save()
    end)
end

local function tryConsumePendingRuntimeNotice()
    if ConchBlessing._runtimePendingNoticeChecked then
        return
    end

    if not ConchBlessing.SaveManager
        or type(ConchBlessing.SaveManager.IsLoaded) ~= "function"
        or not ConchBlessing.SaveManager.IsLoaded()
    then
        return
    end

    ConchBlessing._runtimePendingNoticeChecked = true
    local runtimeSave, settingsSave = getRuntimeSettingsSave(false)
    if type(runtimeSave) ~= "table" then
        return
    end

    local pendingNotice = runtimeSave.pendingNotice
    if type(pendingNotice) ~= "string" or pendingNotice == "" then
        return
    end

    runtimeSave.pendingNotice = nil
    if next(runtimeSave) == nil and type(settingsSave) == "table" then
        settingsSave.runtimeQueue = nil
    end
    pcall(function()
        ConchBlessing.SaveManager.Save()
    end)

    showRuntimeNotice(pendingNotice, "success")
end

local function getRawModData()
    if not mod:HasData() then
        return ""
    end

    local ok, raw = pcall(function()
        return Isaac.LoadModData(mod)
    end)
    if ok and type(raw) == "string" then
        return raw
    end
    return ""
end

local function extractPersistentModData(raw)
    if type(raw) ~= "string" or raw == "" then
        return "{}"
    end

    local lines = {}
    for line in string.gmatch(raw, "[^\r\n]+") do
        if not startsWith(line, RUNTIME_QUEUE_PREFIX) then
            table.insert(lines, line)
        end
    end

    local cleaned = table.concat(lines, "\n")
    if cleaned == "" then
        return "{}"
    end
    return cleaned
end

local function consumeRuntimeQueue()
    local queue = {}
    local raw = getRawModData()
    if raw == "" then
        return queue
    end

    for line in string.gmatch(raw, "[^\r\n]+") do
        if startsWith(line, RUNTIME_QUEUE_PREFIX) then
            local payload = string.sub(line, #RUNTIME_QUEUE_PREFIX + 1)
            local sep = string.find(payload, "|", 1, true)
            if sep and sep > 1 then
                local kind = string.sub(payload, 1, sep - 1)
                local data = string.sub(payload, sep + 1)
                if kind == "CMD" and data ~= "" then
                    table.insert(queue, { type = "command", data = data })
                elseif kind == "MSG" and data ~= "" then
                    table.insert(queue, { type = "msg", data = data })
                end
            end
        end
    end

    if #queue > 0 then
        local saved = false
        if ConchBlessing.SaveManager
            and type(ConchBlessing.SaveManager.IsLoaded) == "function"
            and ConchBlessing.SaveManager.IsLoaded()
            and type(ConchBlessing.SaveManager.Save) == "function"
        then
            local ok = pcall(function()
                ConchBlessing.SaveManager.Save()
            end)
            saved = ok
        end

        if not saved then
            local cleaned = extractPersistentModData(raw)
            pcall(function()
                Isaac.SaveModData(mod, cleaned)
            end)
        end
    end

    return queue
end

-- Register callback for MCM config loading after game starts
Isaac.ConsoleOutput("[Core] Registering MC_POST_GAME_STARTED callback\n")
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isContinued)
    Isaac.ConsoleOutput("[Core] Game started, trying to load MCM config\n")
    
    -- Reset multiplier display data for new game
    if ConchBlessing.stats and ConchBlessing.stats.multiplierDisplay then
        Isaac.ConsoleOutput("[Core] Resetting multiplier display data\n")
        ConchBlessing.stats.multiplierDisplay:ResetForNewGame()
    end
    
    -- Reset unified multiplier system for new game
    if ConchBlessing.stats and ConchBlessing.stats.unifiedMultipliers then
        Isaac.ConsoleOutput("[Core] Resetting unified multiplier system\n")
        local um = ConchBlessing.stats.unifiedMultipliers
        local numPlayers = Game():GetNumPlayers()
        for i = 0, numPlayers - 1 do
            local player = Isaac.GetPlayer(i)
            if player then
                um:ResetPlayer(player)
            end
        end
        -- Clear any pending deferred cache updates
        um._hasPending = false
        for i = 0, (Game():GetNumPlayers() - 1) do
            local player = Isaac.GetPlayer(i)
            if player then
                local pid = player:GetPlayerType()
                if um[pid] then
                    um[pid].pendingCache = {}
                end
            end
        end
        -- Force a fresh cache rebuild to base values
        for i = 0, numPlayers - 1 do
            local player = Isaac.GetPlayer(i)
            if player then
                player:AddCacheFlags(CacheFlag.CACHE_ALL)
                player:EvaluateItems()
            end
        end
    end
    
    -- Reset all item tracking states for new game
    Isaac.ConsoleOutput("[Core] Resetting item tracking states\n")
    if ConchBlessing.oralsteroids and ConchBlessing.oralsteroids._lastItemCount then
        ConchBlessing.oralsteroids._lastItemCount = {}
        Isaac.ConsoleOutput("[Core] Reset oralsteroids._lastItemCount\n")
    end
    if ConchBlessing.injectablsteroids and ConchBlessing.injectablsteroids._lastUseCount then
        ConchBlessing.injectablsteroids._lastUseCount = {}
        Isaac.ConsoleOutput("[Core] Reset injectablsteroids._lastUseCount\n")
    end
    if ConchBlessing.powertraining and ConchBlessing.powertraining._lastUseCount then
        ConchBlessing.powertraining._lastUseCount = {}
        Isaac.ConsoleOutput("[Core] Reset powertraining._lastUseCount\n")
    end
    
    if ConchBlessing.SaveManager and ConchBlessing.SaveManager.IsLoaded() then
        Isaac.ConsoleOutput("[Core] SaveManager loaded, starting MCM config load\n")
        ConchBlessing_MCM.loadConfigFromSaveManager(ConchBlessing)
    else
        Isaac.ConsoleOutput("[Core] SaveManager not loaded, using default settings\n")
    end

    -- New run safeguard: if not continued, clear run-scoped saved multipliers to prevent carry-over
    if not isContinued and ConchBlessing.SaveManager then
        local player = Isaac.GetPlayer(0)
        if player then
            local SaveManager = ConchBlessing.SaveManager
            local playerSave = SaveManager.GetRunSave(player)
            if playerSave then
                playerSave.unifiedMultipliers = nil
                playerSave.oralSteroids = nil
                playerSave.injectableSteroids = nil
                playerSave.powerTraining = nil
                playerSave.dragon = nil
                -- Reset Time = Power trinket run-scoped data on new run (R key)
                playerSave.timePower = nil
                SaveManager.Save()
                Isaac.ConsoleOutput("[Core] Cleared run-scope saved multipliers for new run\n")
            end
        end
    end

    tryConsumePendingRuntimeNotice()
end)

mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    tryConsumePendingRuntimeNotice()

    local frame = Isaac.GetFrameCount()
    ConchBlessing._lastRuntimePollFrame = ConchBlessing._lastRuntimePollFrame or -RUNTIME_POLL_INTERVAL
    if (frame - ConchBlessing._lastRuntimePollFrame) < RUNTIME_POLL_INTERVAL then
        return
    end
    ConchBlessing._lastRuntimePollFrame = frame

    local queue = consumeRuntimeQueue()
    if #queue == 0 then
        return
    end

    for _, entry in ipairs(queue) do
        if entry.type == "msg" then
            Isaac.DebugString("[CB runtime] " .. entry.data)
            local kind = "info"
            if startsWith(entry.data, "Reloaded:") or startsWith(entry.data, "Reloaded mod:") then
                kind = "success"
            end
            showRuntimeNotice(entry.data, kind)
        elseif entry.type == "command" then
            Isaac.DebugString("[CB runtime] Executing command: " .. entry.data)
            if startsWith(entry.data, "luamod ") then
                local target = string.sub(entry.data, 8)
                local notice = "Reload complete"
                if target and target ~= "" then
                    notice = "Reloaded: " .. target
                end
                setPendingRuntimeNotice(notice)
            end
            Isaac.ExecuteCommand(entry.data)
        end
    end
end)

mod:AddCallback(ModCallbacks.MC_POST_RENDER, function()
    renderRuntimeNotice()
end)

-- sound IDs
ConchBlessing.Sounds = {
    -- add sound IDs here (e.g., 1 = "sfx/sfx_item_pickup.wav")
}

-- debug print functions
ConchBlessing.printDebug = function(text)
    if ConchBlessing.Config.debugMode then
        local frame = (Game and Game():GetFrameCount()) or -1
        Isaac.DebugString("[ConchBlessing][DEBUG][F:" .. tostring(frame) .. "] " .. tostring(text))
        Isaac.ConsoleOutput("[ConchBlessing][DEBUG][F:" .. tostring(frame) .. "] " .. tostring(text) .. "\n")
    end
end

ConchBlessing.printError = function(text)
    Isaac.ConsoleOutput("[ConchBlessing][ERROR] " .. tostring(text) .. "\n")
end

ConchBlessing.print = function(text)
    Isaac.ConsoleOutput("[ConchBlessing] " .. tostring(text) .. "\n")
end

-- Optional enum adapter for users referencing the @tboi namespace
do
    _G.tboi = _G.tboi or {}
    local ok, err = pcall(function()
        tboi.CollectibleType = tboi.CollectibleType or CollectibleType
        tboi.TrinketType = tboi.TrinketType or TrinketType
        tboi.ModCallbacks = tboi.ModCallbacks or ModCallbacks
        tboi.CacheFlag = tboi.CacheFlag or CacheFlag
        tboi.ItemType = tboi.ItemType or ItemType
        tboi.RoomType = tboi.RoomType or RoomType
    end)
    if ConchBlessing.Config and ConchBlessing.Config.debugMode then
        if ok then
            Isaac.ConsoleOutput("[Core] tboi enum adapter active\n")
        else
            Isaac.ConsoleOutput("[Core] tboi enum adapter error: " .. tostring(err) .. "\n")
        end
    end
end

-- Initialize HiddenItemManager
local HiddenItemManager = require("scripts.lib.hidden_item_manager")
HiddenItemManager:Init(mod)
ConchBlessing.HiddenItemManager = HiddenItemManager
ConchBlessing.print("HiddenItemManager initialized!")

-- load stats library first (before items and upgrade systems)
local statsSuccess, statsErr = pcall(function()
    require("scripts.lib.stats")
end)
if statsSuccess then
    ConchBlessing.print("Stats library loaded successfully!")
else
    ConchBlessing.printError("Stats library load failed: " .. tostring(statsErr))
end

-- load vanilla multipliers table (for bonus damage calculation with vanilla item multipliers)
local vanillaMultSuccess, vanillaMultErr = pcall(function()
    require("scripts.lib.vanilla_multipliers")
end)
if vanillaMultSuccess then
    ConchBlessing.print("Vanilla Multipliers table loaded successfully!")
else
    ConchBlessing.printError("Vanilla Multipliers table load failed: " .. tostring(vanillaMultErr))
end

-- load items and management
local itemsSuccess, itemsErr = pcall(function()
    require("scripts/conch_blessing_items")
end)
if not itemsSuccess then
    ConchBlessing.printError("Item system load failed: " .. tostring(itemsErr))
end

-- load upgrade system
local upgradeSuccess, upgradeErr = pcall(function()
    require("scripts/conch_blessing_upgrade")
end)
if not upgradeSuccess then
    ConchBlessing.printError("Upgrade system load failed: " .. tostring(upgradeErr))
end

-- Initialize stats system after everything is loaded
if ConchBlessing.stats and ConchBlessing.stats.multiplierDisplay then
    ConchBlessing.stats.multiplierDisplay:Initialize()
    ConchBlessing.print("Stats system initialized!")
else
    ConchBlessing.printError("Stats system not found during initialization!")
end

-- print message when mode is loaded
ConchBlessing.print("Conch's Blessing v" .. ConchBlessing.Config.Version .. " mode loaded!") 
