ConchBlessing.appraisal = ConchBlessing.appraisal or {}
local M = ConchBlessing.appraisal

M.config = M.config or {
    costCoins = 30,
}

local function getManager()
    return ConchBlessing.GalleryManager
end

local function logBlockedUse(reason, cost, coins)
    if reason == "coins" then
        ConchBlessing.print(string.format(
            "[Appraisal] Not enough coins (%d/%d).",
            coins or 0,
            cost or M.config.costCoins
        ))
    elseif reason == "stageapi_missing" then
        ConchBlessing.print("[Appraisal] The Atropos synergy requires StageAPI.")
    elseif reason == "repentogon_missing"
        or reason == "repentogon_incompatible"
        or tostring(reason):find("REPENTOGON", 1, true)
    then
        ConchBlessing.printError("Appraisal requires a compatible REPENTOGON version.")
    elseif reason == "death_certificate" then
        ConchBlessing.print("[Appraisal] Cannot enter from the Death Certificate dimension.")
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

function M.onUseItem(_, _, _, player)
    local manager = getManager()
    if not manager or type(manager.startAppraisal) ~= "function" then
        logBlockedUse("repentogon_incompatible")
        return { Discharge = false, Remove = false, ShowAnim = false }
    end

    local started, reason, cost, coins = manager.startAppraisal(player, M.config.costCoins)
    if not started then
        logBlockedUse(reason, cost, coins)
        return { Discharge = false, Remove = false, ShowAnim = false }
    end
    -- Coin payment and the gallery session own this zero-charge active's use
    -- contract. The Death Certificate transition supplies the full animation.
    return { Discharge = false, Remove = false, ShowAnim = false }
end

return M
