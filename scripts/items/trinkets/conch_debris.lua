local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 소라 잔해 (Conch Debris): what is left when a Magic Conch evolution fails
-- (user design 2026-11-15).
--
-- With the Magic Conch's Delete Mode on, an answer still evolves every pickup
-- that has a result for it; an evolvable pickup with no result for the answer
-- (a failed evolution) is deleted as before and one Conch Debris lies where it
-- stood, free whatever the pickup cost (scripts/conch_blessing_upgrade.lua
-- calls M.dropAt). Pickups that cannot evolve at all go as they always did,
-- with no debris, and the debris itself is never deleted by an answer.
--
-- Touching it smelts it at once (REPENTOGON's AddSmeltedTrinket) instead of
-- putting it in the hand, so it never pushes a held trinket out. Three
-- smelted copies (a golden copy counts as one) are removed and one Conch
-- Ticket appears beside that player. A copy that reaches the hand some other
-- way (bought, given by console, a helper's own pickup) is smelted on the
-- next update. The smelted copies are the whole state: nothing is saved.
-- Without REPENTOGON's smelt API no debris drops (its EID says it is required).
local Sound = require("scripts.lib.sound_volume")
local TrinketUtils = ConchBlessing.TrinketUtils or require("scripts.lib.trinket_utils")

ConchBlessing.conchdebris = ConchBlessing.conchdebris or {}
local M = ConchBlessing.conchdebris

M.NEEDED = 3 -- smelted copies that become one Conch Ticket

local evidence = { dropped = 0, touched = 0, fromHand = 0, tickets = 0 }
local seen = {} -- GetPtrHash(player) -> last trinket multiplier, to notice smelts made elsewhere
local reported = {}

local function reportOnce(key, message)
    if reported[key] then return end
    reported[key] = true
    ConchBlessing.printError("[Conch Debris] " .. message)
end

local function debrisId()
    local data = ConchBlessing.ItemData and ConchBlessing.ItemData.CONCH_DEBRIS
    local id = data and data.id
    return type(id) == "number" and id > 0 and id or nil
end

local function isDebris(raw)
    local id = debrisId()
    if not id or type(raw) ~= "number" or raw <= 0 then return false end
    return (TrinketUtils.baseIdOf(raw)) == id
end
M.isDebris = isDebris

local function canSmelt(player)
    return player ~= nil and type(player.AddSmeltedTrinket) == "function"
        and type(player.TryRemoveSmeltedTrinket) == "function"
        and type(player.GetSmeltedTrinkets) == "function"
end

-- REPENTOGON's smelt API, checked on a live player: without it no debris drops.
local smeltReady = false
function M.available()
    if smeltReady then return true end
    if not debrisId() then return false end
    local player = Isaac.GetPlayer(0)
    smeltReady = canSmelt(player)
    return smeltReady
end

local function alive(player)
    if not player or not player:Exists() or player:IsDead() then return false end
    return not (type(player.IsCoopGhost) == "function" and player:IsCoopGhost())
end

-- A failed evolution's pickup was deleted at `position`: one free debris lies
-- there. Its seed comes from the deleted pickup's, so no gameplay RNG is spent
-- and SaveManager never mistakes it for a copy of that pickup.
function M.dropAt(position, sourceSeed)
    if not M.available() then return nil end
    local id = debrisId()
    local rng = RNG()
    rng:SetSeed(math.max(1, math.floor(tonumber(sourceSeed) or 1)), 35)
    local seed = rng:Next()
    if seed == 0 then seed = 1 end
    local entity = Game():Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TRINKET,
        Vector(position.X, position.Y), Vector.Zero, nil, id, seed)
    local pickup = entity and entity:ToPickup()
    if not pickup then
        reportOnce("spawn", "the debris did not spawn")
        return nil
    end
    evidence.dropped = evidence.dropped + 1
    return pickup
end

-- Smelted debris copies, normal and golden alike.
local function smeltedCount(player)
    local normal, golden = TrinketUtils.getSmeltedCounts(player, debrisId())
    if not normal then return 0, 0, 0 end
    return normal + golden, normal, golden
end
M.smeltedCount = smeltedCount

local function spawnTicket(player)
    local pockets = ConchBlessing.PocketData
    local ticket = pockets and pockets.CONCH_TICKET
    local card = ticket and ticket.id
    if type(card) ~= "number" or card <= 0 then
        reportOnce("ticket", "the Conch Ticket card is not registered")
        return false
    end
    -- One tile from Isaac toward the room's middle, so it is seen before it is taken.
    local room = Game():GetRoom()
    local toward = room:GetCenterPos() - player.Position
    toward = toward:Length() > 1 and toward:Resized(40) or Vector(0, 40)
    local position = room:FindFreePickupSpawnPosition(player.Position + toward, 0, true)
    Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD, card, position, Vector.Zero, player)
    Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.POOF01, 0, position, Vector.Zero, nil)
    SFXManager():Play(SoundEffect.SOUND_THUMBSUP, Sound.volume(0.8))
    evidence.tickets = evidence.tickets + 1
    return true
end

-- Every three smelted copies become one Conch Ticket.
local function settle(player)
    local id = debrisId()
    if not id or not canSmelt(player) then return end
    local total = smeltedCount(player)
    while total >= M.NEEDED do
        for _ = 1, M.NEEDED do
            local _, normal = smeltedCount(player)
            player:TryRemoveSmeltedTrinket(normal > 0 and id or (id | TrinketUtils.GOLDEN_FLAG))
        end
        local left = smeltedCount(player)
        if left ~= total - M.NEEDED then
            reportOnce("remove", string.format("removing three smelted copies left %d of %d", left, total))
            return
        end
        if not spawnTicket(player) then return end
        total = left
    end
end
M.settle = settle

local function absorb(player, raw)
    player:AddSmeltedTrinket(raw, false)
    SFXManager():Play(SoundEffect.SOUND_VAMP_GULP, Sound.volume(0.8))
    local show = ConchBlessing.EID and ConchBlessing.EID.showItemText
    if type(show) == "function" then show(ConchBlessing.ItemData.CONCH_DEBRIS) end
    settle(player)
    seen[GetPtrHash(player)] = player:GetTrinketMultiplier(debrisId())
end

-- Touching a free debris smelts it. A helper player (Parent set: Strawman,
-- 자's lookalikes) is left to the engine's own pickup rules, and so is a debris
-- for sale; whatever reaches a hand is smelted on the next update.
function M.onPrePickupCollision(_, pickup, collider)
    if pickup.Variant ~= PickupVariant.PICKUP_TRINKET or not isDebris(pickup.SubType) then return nil end
    local player = collider and collider:ToPlayer()
    if not player or player.Parent ~= nil or not alive(player) or not canSmelt(player) then return nil end
    if pickup.Wait > 0 or pickup.Price ~= 0 or pickup:IsShopItem() then return nil end
    if type(player.CanPickupItem) == "function" and not player:CanPickupItem() then return nil end
    local raw = pickup.SubType
    pickup:Remove()
    evidence.touched = evidence.touched + 1
    absorb(player, raw)
    return true
end

function M.onPEffectUpdate(_, player)
    local id = debrisId()
    if not id then return end
    for slot = 0, 1 do
        local raw = player:GetTrinket(slot)
        if isDebris(raw) and canSmelt(player) and alive(player) and player:TryRemoveTrinket(raw) then
            evidence.fromHand = evidence.fromHand + 1
            absorb(player, raw)
        end
    end
    -- A smelt made elsewhere (an absorbed Hermit Crab smelting what reaches the
    -- hand, a console command) still adds up: settle whenever the count changes.
    local multiplier = player:GetTrinketMultiplier(id)
    local hash = GetPtrHash(player)
    if seen[hash] ~= multiplier then
        seen[hash] = multiplier
        if multiplier > 0 then settle(player) end
    end
end

function M.onGameStarted()
    seen = {}
    for index = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if player then settle(player) end
    end
end

function M.onGameExit()
    seen = {}
end

M._test = {
    evidence = function() return evidence end,
    resetEvidence = function() evidence = { dropped = 0, touched = 0, fromHand = 0, tickets = 0 } end,
}

return M
