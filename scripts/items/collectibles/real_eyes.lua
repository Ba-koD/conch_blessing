-- A read-only view of the provider's next unconsumed answer. Never persist a
-- prediction: the room, usage ledger, language or forced answer may change.
local M = {}
ConchBlessing.realeyes = M
local game = Game()
local ITEM_ID = Isaac.GetItemIdByName("Real Eyes")
local warned = {}
local View = require("scripts.lib.conch_answer_view")
local colors = { positive = { 0.65, 1, 0.78 }, neutral = { 0.9, 0.86, 0.7 }, negative = { 1, 0.58, 0.62 } }

local function warn(key, detail)
    if warned[key] then return end
    warned[key] = true
    ConchBlessing.printError("[RealEyes] " .. key .. ": " .. tostring(detail))
end

function M.hasOwner()
    if ITEM_ID <= 0 then return false end
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if player and player:HasCollectible(ITEM_ID) then return true end
    end
    return false
end

function M.getPrediction()
    if not M.hasOwner() then return nil, "NO_OWNER" end
    local provider = rawget(_G, "MagicConch")
    local api = provider and provider.API
    local config = provider and provider.Config
    if not config or not config.enabled then return nil, "DISABLED" end
    if not api or type(api.PreviewResult) ~= "function" or type(api.IsReady) ~= "function" then
        warn("PREVIEW_UNAVAILABLE", "Magic Conch.API.PreviewResult is required; update Magic Conch")
        return nil, "PREVIEW_UNAVAILABLE"
    end
    local readyOK, ready = pcall(api.IsReady)
    if not readyOK or not ready then return nil, "API_NOT_READY" end
    -- The provider samples with its current seed/room/usage/config without
    -- consuming an RNG stream or recording a use. Offset 0 is always next.
    local ok, result, reason = pcall(api.PreviewResult, 0)
    if not ok then
        warn("PREVIEW_FAILED", result)
        return nil, "PREVIEW_FAILED"
    end
    if result == nil then return nil, reason or "NO_RESPONSE" end
    if type(result) ~= "table" or not colors[result.type]
        or type(result.text) ~= "string" or result.text == "" then
        warn("INVALID_PREVIEW", "expected a text answer with positive/neutral/negative type")
        return nil, "INVALID_PREVIEW"
    end
    local usage = View.usage(api, result)
    return { id = result.id, text = result.text, type = result.type,
        usageCount = usage, useNumber = usage and usage + 1 or result.useNumber }
end

local function render()
    local ar = ConchBlessing.arglasses
    if ar and ar.isOpen() then return end
    local prediction = M.getPrediction()
    if not prediction then return end
    local kind = View.text("ui.conch_mode.flags." .. prediction.type)
    local text = prediction.useNumber and View.text("ui.real_eyes.numbered", prediction.useNumber, kind)
        or View.text("ui.real_eyes.prediction", kind)
    local rows = {{text=text, kind=prediction.type, icon="real_eyes"}}
    if ar and ar.hasOwner() then rows[#rows+1] = {text=View.text("ui.ar_glasses.open"), icon="ar_glasses"} end
    View.render(rows)
end

function M.onRender()
    local ok, err = pcall(render)
    if not ok then warn("RENDER_FAILED", err) end
end

return M
