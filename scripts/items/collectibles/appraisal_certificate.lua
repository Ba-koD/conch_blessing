ConchBlessing.appraisal = ConchBlessing.appraisal or {}
local M = ConchBlessing.appraisal

M.config = M.config or {
    costCoins = 30,
}

local function getManager()
    return ConchBlessing.GalleryManager
end

local function cancelUse()
    local repentogon = rawget(_G, "REPENTOGON")
    if type(repentogon) == "table" and repentogon.Real == true then
        return { Discharge = false }
    end
    return true
end

local function logBlockedUse(reason, cost, coins)
    if reason == "coins" then
        ConchBlessing.print(string.format(
            "[Appraisal] Not enough coins (%d/%d).",
            coins or 0,
            cost or M.config.costCoins
        ))
    elseif reason == "stageapi_missing" then
        ConchBlessing.printError("Appraisal requires a compatible StageAPI for its return door.")
    elseif reason == "repentogon_missing"
        or reason == "repentogon_incompatible"
        or tostring(reason):find("REPENTOGON", 1, true)
    then
        ConchBlessing.printError("Appraisal requires a compatible REPENTOGON version.")
    elseif reason == "stageapi_extra_room" then
        ConchBlessing.print("[Appraisal] Cannot enter from a StageAPI extra room.")
    elseif reason == "stageapi_origin_unknown" then
        ConchBlessing.printError("Appraisal could not verify its return origin through StageAPI.")
    elseif reason == "active" then
        ConchBlessing.print("[Appraisal] Its room session is already active.")
    elseif reason == "no_trinkets" then
        ConchBlessing.printError("No available trinkets were found for the gallery.")
    elseif reason then
        ConchBlessing.printError("Appraisal use was blocked: " .. tostring(reason))
    end
end

function M.onPreUseItem(_, _, _, player)
    local manager = getManager()
    if not manager or type(manager.startAppraisal) ~= "function" then
        logBlockedUse("repentogon_incompatible")
        return cancelUse()
    end

    local started, reason, cost, coins = manager.startAppraisal(player, M.config.costCoins)
    if not started then
        logBlockedUse(reason, cost, coins)
        return cancelUse()
    end
    -- Only an accepted transition reaches the engine's use/counter path.
end

function M.onUseItem(_, _, _, player)
    local manager = getManager()
    if manager and type(manager.confirmAppraisalUse) == "function" then
        manager.confirmAppraisalUse(player)
    end
    -- PRE_USE validates and journals; this real accepted-use callback confirms
    -- it. The next semantic update invokes DC after the outer use has unwound.
    return { Discharge = false, Remove = false, ShowAnim = false }
end

function M.onInputAction(_, entity, hook, action)
    local player = entity and entity:ToPlayer() or nil
    if not player or player:GetNumCoins() >= M.config.costCoins then return end
    local item = ConchBlessing.ItemData.APPRAISAL_CERTIFICATE.id
    local attemptsUse = action == ButtonAction.ACTION_ITEM
        and player:GetActiveItem(ActiveSlot.SLOT_PRIMARY) == item
        or action == ButtonAction.ACTION_PILLCARD
            and player:GetActiveItem(ActiveSlot.SLOT_POCKET) == item
    if not attemptsUse then return end
    -- Ignore the manual activation before the engine and other use listeners
    -- see it. PRE_USE remains the barrier for copies and programmatic uses.
    if hook == InputHook.GET_ACTION_VALUE then return 0.0 end
    if hook == InputHook.IS_ACTION_PRESSED or hook == InputHook.IS_ACTION_TRIGGERED then return false end
end

return M
