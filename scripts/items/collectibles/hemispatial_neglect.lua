local M = {}
ConchBlessing.hemispatialneglect = M
local ID = Isaac.GetItemIdByName("Hemispatial Neglect")
local visual = require("scripts.items.collectibles.hemispatial_neglect_visual")
M.onPrePlayerRender = visual.onPrePlayerRender
M.resetVisual = visual.reset
M.onUnload = visual.onUnload
local definition = require("scripts.entities.definitions").NEGLECT_TEAR
local BLOCKED = "__ConchBlessingNeglectTear"
local variant
if type(Isaac.GetEntityTypeByName) == "function" and type(Isaac.GetEntityVariantByName) == "function" then
    local ok, entityType, value = pcall(function()
        return Isaac.GetEntityTypeByName(definition.name), Isaac.GetEntityVariantByName(definition.name)
    end)
    if ok and entityType == definition.id and type(value) == "number" and value > 0 then variant = value end
end
local warned = false

function M.canRestrictTears()
    local rg = rawget(_G, "REPENTOGON")
    return variant ~= nil and type(rg) == "table" and rg.Real == true
        and ModCallbacks and type(ModCallbacks.MC_EVALUATE_TEAR_HIT_PARAMS) == "number"
        and type(ModCallbacks.MC_PRE_TEAR_UPDATE) == "number" or false
end

-- Carry the engine's per-result eye decision through an owned tear variant.
-- No last-eye/frame/position guess, custom flag bit, or player fire-delay write.
-- Restrict the ordinary tear weapon only; non-tear weapons must be untouched.
function M.onTearParams(_, player, params, weaponType, _, eye, source)
    if ID <= 0 or not player:HasCollectible(ID) or not M.canRestrictTears()
        or weaponType ~= WeaponType.WEAPON_TEARS or eye ~= 1 then return end
    if source then
        local owner = source:ToPlayer()
        if not owner or GetPtrHash(owner) ~= GetPtrHash(player) then return end
    end
    params.TearVariant = variant
    params.TearDamage = 0
    params.TearFlags = TearFlags.TEAR_NORMAL
    params.TearColor = Color(1, 1, 1, 0)
end

function M.isBlockedTear(tear)
    if not tear or tear.Type ~= definition.id then return false end
    return (variant ~= nil and tear.Variant == variant) or tear:GetData()[BLOCKED] == true
end

local function silence(tear)
    tear:GetData()[BLOCKED] = true
    tear.Visible = false
    tear.CollisionDamage = 0
    tear.TearFlags = TearFlags.TEAR_NORMAL
    tear.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    tear.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
    if type(tear.SetInitSound) == "function" then tear:SetInitSound(SoundEffect.SOUND_NULL) end
end

function M.onTearInit(_, tear)
    if M.isBlockedTear(tear) then
        -- Init precedes the engine's remaining tear setup. Do not remove an
        -- entity mid-construction; post-fire/pre-update finalizes suppression.
        silence(tear)
    end
end

function M.onFireTear(_, tear)
    if not M.isBlockedTear(tear) then return end
    silence(tear)
    -- Remove, never Die: no native impact/splash/split death effects.
    tear:Remove()
end

function M.onPreTearUpdate(_, tear)
    if not M.isBlockedTear(tear) then return end
    M.onFireTear(nil, tear)
    return true
end

function M.onTearCollision(_, tear)
    if not M.isBlockedTear(tear) then return end
    M.onFireTear(nil, tear)
    return true
end

function M.onSplitTear(_, tear, source)
    if not M.isBlockedTear(source) then return end
    silence(tear)
    tear:Remove()
end

function M.onPlayerUpdate(_, player)
    visual.onPlayerUpdate(nil, player)
    if ID <= 0 then return end
    if player:HasCollectible(ID) and not M.canRestrictTears() and not warned then
        warned = true
        ConchBlessing.printError("Hemispatial Neglect: right-tear suppression unavailable; requires REPENTOGON tear-params/pre-update callbacks and a full restart after entities2.xml changes.")
    end
    local um = ConchBlessing.stats and ConchBlessing.stats.unifiedMultipliers
    if not um then return end
    local state = ConchBlessing.getUnifiedMultiplierState(player, um)
    local row = state and state.itemMultipliers and state.itemMultipliers[ID]
    local entry = row and row.Damage
    local count = player:GetCollectibleNum(ID)
    local target = count > 0 and 2 ^ count or nil
    if target and (not entry or entry.value ~= target) then
        um:SetItemMultiplier(player, ID, "Damage", target, "Hemispatial Neglect")
    elseif not target and entry then um:RemoveItemMultiplier(player, ID, "Damage")
    else return end
    if um.QueueCacheUpdate then um:QueueCacheUpdate(player, "Damage") end
    if um.SaveToSaveManager then um:SaveToSaveManager(player) end
end

return M
