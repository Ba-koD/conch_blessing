local M = {}
ConchBlessing.arglasses = M
local View = require("scripts.lib.conch_answer_view")
local ID = Isaac.GetItemIdByName("AR Glasses")
local OWNER = "ConchBlessing AR Glasses"
local kinds = { "positive", "negative", "neutral" }
local selected, wasPressed, boundAPI, token = 0, false, nil, nil

function M.hasOwner()
    if ID <= 0 then return false end
    for i = 0, Game():GetNumPlayers()-1 do
        local p = Isaac.GetPlayer(i)
        if p and p:HasCollectible(ID) then return true end
    end
    return false
end

local function api()
    local p = rawget(_G, "MagicConch")
    if not M.hasOwner() then return nil, "NO_OWNER" end
    if not p or not p.Config or not p.Config.enabled then return nil, "DISABLED" end
    local a = p.API
    if not a or type(a.IsReady) ~= "function" or type(a.PreviewResult) ~= "function"
        or type(a.ReserveNextResult) ~= "function" or type(a.GetNextResultReservation) ~= "function"
        or type(a.ClearNextResultReservation) ~= "function" then
        View.warn("CHOICE_API_UNAVAILABLE", "update Magic Conch for the next-result reservation API")
        return nil, "API_UNAVAILABLE"
    end
    local ok, ready = pcall(a.IsReady)
    if not ok or not ready then return nil, "API_NOT_READY" end
    return a
end

local function pressed()
    return Input and type(Input.IsButtonPressed) == "function"
        and Input.IsButtonPressed(Keyboard.KEY_C, 0) == true
end

function M.cancel()
    if boundAPI then
        local ok, err = pcall(boundAPI.ClearNextResultReservation, OWNER)
        if not ok then View.warn("CHOICE_CLEAR_FAILED", err) end
    end
    boundAPI, token = nil, nil
end

function M.reset()
    M.cancel()
    selected, wasPressed = 0, pressed()
end

local function validOwner()
    return ConchBlessing.arglasses == M and M.hasOwner()
end

local function reserve(index)
    local a, reason = api()
    if not a then return false, reason end
    if boundAPI and boundAPI ~= a then M.cancel() end
    local ok, accepted, result = pcall(a.ReserveNextResult, OWNER, {type=kinds[index]}, validOwner)
    if not ok or accepted ~= true then
        View.warn("CHOICE_RESERVE_FAILED", ok and result or accepted)
        return false, ok and result or "API_FAILED"
    end
    selected, boundAPI, token = index, a, result
    return true
end

function M.cycle()
    -- No activation here. The provider applies this to its next successful
    -- ordinary activation, including its OWN hotkey and third-party API calls.
    return reserve(selected % #kinds + 1)
end

function M.getSelection()
    local a, reason = api()
    if not a then return nil, reason end
    if a ~= boundAPI or not token then return nil end
    local ok, reserved = pcall(a.GetNextResultReservation, OWNER)
    if not ok then View.warn("CHOICE_READ_FAILED", reserved); return nil end
    if not reserved or reserved.token ~= token then return nil end
    local previewOK, result = pcall(a.PreviewResult, 0)
    if not previewOK or type(result) ~= "table" or result.type ~= kinds[selected] or result.forced ~= true then
        View.warn("CHOICE_PREVIEW_FAILED", previewOK and "reservation/preview mismatch" or result)
        return nil
    end
    local usage = View.usage(a, result)
    return {type=result.type, text=result.text, id=result.id, useNumber=usage and usage+1 or result.useNumber}
end

function M.isOpen() return M.getSelection() ~= nil end

function M.onUpdate()
    -- Like Magic Conch, track IsButtonPressed's rising edge. Also polled from
    -- render so a short C tap between 30 Hz game updates is not lost.
    local down = pressed()
    local rising = down and not wasPressed
    wasPressed = down
    if not M.hasOwner() then M.reset(); return end
    local p = rawget(_G, "MagicConch")
    if not p or not p.Config or not p.Config.enabled then M.reset(); return end
    if Game():IsPaused() then return end
    if rising then M.cycle() end
end

function M.onRender()
    M.onUpdate()
    if not M.hasOwner() then return end
    local ok, err = pcall(function()
        local prediction = M.getSelection()
        if not prediction then
            if ConchBlessing.realeyes and ConchBlessing.realeyes.hasOwner() then return end
            View.render({{text=View.text("ui.ar_glasses.open"), icon="ar_glasses"}})
            return
        end
        local label = View.text("ui.conch_mode.flags." .. prediction.type)
        View.render({{text=View.text("ui.ar_glasses.title", label), kind=prediction.type, icon="ar_glasses"}})
    end)
    if not ok then View.warn("CHOICE_RENDER_FAILED", err) end
end

function M.onUnload(_, mod)
    if mod == ConchBlessing or mod == ConchBlessing.originalMod then M.reset() end
end

return M
