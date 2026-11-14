local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- Dev-only command queue (not in the Workshop package). A line
-- `__CBQ__CMD|<console command>` (or `__CBQ__MSG|<text>`) appended to this mod's
-- save file (data/conch_blessing/save1.dat) runs during play: watch.sh queues
-- `luamod conch_blessing` this way, and benches are started with
-- `__CBQ__CMD|cb test ...` (AGENTS.md, Verification). Checking means reading
-- the whole save file from disk, every RUNTIME_POLL_INTERVAL render frames, so
-- it stays out of the released mod. SaveManager drops those lines when it
-- loads the file. After a queued `luamod`, the next run shows "Reloaded".
local mod = ConchBlessing.originalMod

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

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
    tryConsumePendingRuntimeNotice()
end)

return {}
