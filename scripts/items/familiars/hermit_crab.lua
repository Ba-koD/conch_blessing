local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 소라게 (Hermit Crab): the Magic Conch's positive answer to Mom's Purse.
--
-- A front-facing crab ambles around the room on its own, wherever its owner is
-- (user request 2026-11-09: it does not follow): it strolls to a random free
-- spot, rests, and strolls again. When its owner puts a trinket down, the
-- owner's nearest free crab hurries over to it and takes it on arrival; if the
-- trinket is gone first (picked back up), it goes back to strolling. While the
-- owner stands within two tiles of the trinket, or a Magic Conch upgrade is
-- changing it, the crab leaves it alone (user decision 2026-11-09: so a dropped
-- trinket can still be upgraded on the floor); it goes once the owner walks
-- away, and then carries the upgraded trinket. Like the
-- vanilla bums it passes over rocks and pits and stays inside the walls. It
-- holds one trinket in front;
-- with BFFS it raises each occupied claw and keeps an empty claw gathered.
-- While it holds a trinket, the owner has that trinket's effect: it is an
-- innate trinket of the owner (REPENTOGON's `AddInnateTrinket`, in this mod's
-- own group), neither carried nor smelted (user decision 2026-11-09). Measured
-- in game that day: it counts for HasTrinket and the trinket multiplier, a
-- golden copy counts twice, stat trinkets apply and hit triggers fire (a
-- Swallowed Penny drops its coin). The engine never takes an innate trinket
-- away, so a hit does not break a Perfection the crab holds; the user accepted
-- that the crab protects what it holds. Letting go removes exactly that copy.
--
-- Which trinkets: only the ones its own owner puts down. Measured in game on
-- 2026-11-09, a trinket a player drops is spawned with that player as its
-- `SpawnerEntity` from its first frame, while chests, rooms and shops spawn
-- theirs without a player. So the crab ignores every trinket the floor offers
-- and reacts only to its owner's own drops (the drop key, or a trinket pushed
-- out of a full hand by a new one). A crab with a free claw sets out before a
-- nearer one whose claws are full. Each trinket stays with the crab that took
-- it (the ledger keeps that crab's number beside it; user report 2026-11-10:
-- with three crabs, the third one's catch showed up in the second one's
-- claws). A crab's number is its place among its owner's crabs (1, 2, ...),
-- kept on the crab: the engine gives every crab of one owner the same InitSeed
-- (measured in game 2026-11-10), so a seed tells them apart no better than it
-- kept their strolls apart. A crab whose claws are full puts its own oldest trinket down where
-- the new one landed and takes the new one; a trinket the crab puts down is
-- spawned without a spawner, so it is never taken again.
--
-- Losing crabs (or BFFS) lets go of trinkets back on the floor: first those of
-- a crab that left, or beyond what a crab can hold now, then the newest. A
-- trinket whose crab is gone (or from a ledger that never named one) moves to a
-- crab with room and stays there. When Kronos (or Thurisaz) absorbs a crab, the trinkets it held are
-- smelted for good, and as long as the absorbed crabs have room left, every
-- trinket the owner gets in hand is smelted at once (user decision 2026-11-09:
-- "크로노스 흡수시 장신구를 얻자마자 흡수").
local Sound = require("scripts.lib.sound_volume")
local TrinketUtils = require("scripts.lib.trinket_utils")
local Visuals = require("scripts.items.familiars.hermit_crab_visuals")

ConchBlessing.hermitcrab = ConchBlessing.hermitcrab or {}
local M = ConchBlessing.hermitcrab

local ITEM_ID = Isaac.GetItemIdByName("Hermit Crab")
local SAVE_KEY = "hermitCrab"
local ANM2 = "gfx/hermit_crab.anm2"
local TRINKET_VARIANT = 350
local GROUP = "ConchBlessingHermitCrab" -- the innate group the crabs' trinkets live in

M.data = {
    perCrab = 1,
    bffsPerCrab = 2,
    takeVolume = 0.6,
    wanderSpeed = 1.5,  -- an amble
    fetchSpeed = 4,     -- hurrying to a trinket its owner put down
    reach = 14,         -- the claws close on a trinket this close
    margin = 30,        -- stroll spots keep this far from the walls
    pauseMin = 30,      -- updates it rests between strolls
    pauseMax = 105,
    stuckUpdates = 30,  -- no progress for this long: give up that way
    ownerNear = 80,     -- two tiles: the owner this close keeps the crab off the trinket
}

local started = false
local restorePending = false -- bring each owner's innate group in line with the ledger once
local queue = {}        -- trinkets an owner just put down: { ref = EntityPtr, owner = EntityPtr }
local claims = {}       -- those still on the floor, in drop order: { ref, owner, crab = hash, done }
local morphing = {}     -- [GetPtrHash(pickup)] = claims proven by their live reference before a Morph
local roomSerial = 0    -- walk targets belong to the room they were chosen in
local layout = {}       -- [GetPtrHash(crab)] = list of held trinket ids this crab draws
local sprites = { trinkets = {} }
local reported = {}

local evidence
local function resetEvidence()
    evidence = { taken = 0, putDown = 0, released = 0, kept = 0, smeltedAtOnce = 0, ignored = 0,
        fetchFrom = -1, fetchAt = -1, fetchCrab = -1, waitedNear = 0, waitedUpgrade = 0, vanished = 0 }
end
resetEvidence()

local cachedVariant
local function variant()
    if cachedVariant then return cachedVariant end
    local v = Isaac.GetEntityVariantByName("Hermit Crab")
    if v and v >= 0 then cachedVariant = v end
    return cachedVariant
end

local function goldenFlag()
    return TrinketType and TrinketType.TRINKET_GOLDEN_FLAG or 32768
end

local function reportOnce(key, message)
    if reported[key] then return end
    reported[key] = true
    ConchBlessing.printError("[Hermit Crab] " .. message)
end

local function canHold(player)
    return type(player.AddInnateTrinket) == "function" and type(player.RemoveInnateTrinket) == "function"
        and type(player.GetInnateTrinketCount) == "function"
end

-- Kronos keeps what absorbed crabs held, and smelts the next ones, for good.
local function canSmelt(player)
    return type(player.AddSmeltedTrinket) == "function" and type(player.TryRemoveSmeltedTrinket) == "function"
end

-- Innate copies of exactly this trinket in the crabs' group (golden apart).
local function innate(player, id)
    return player:GetInnateTrinketCount(id, GROUP)
end

local function alive(player)
    if not player or not player:Exists() or player:IsDead() then return false end
    return not (type(player.IsCoopGhost) == "function" and player:IsCoopGhost())
end

local function ledger(player)
    local sm = ConchBlessing.SaveManager
    local save = sm and sm.GetRunSave(player)
    if not save then return nil end
    local data = save[SAVE_KEY]
    if type(data) ~= "table" then
        data = { held = {}, kept = 0, innate = true }
        save[SAVE_KEY] = data
    end
    data.held = type(data.held) == "table" and data.held or {}
    -- the number of the crab holding each one (0: not known yet, as in an
    -- older ledger); it draws that trinket
    data.crabs = type(data.crabs) == "table" and data.crabs or {}
    for i = 1, #data.held do data.crabs[i] = tonumber(data.crabs[i]) or 0 end
    while #data.crabs > #data.held do data.crabs[#data.crabs] = nil end
    data.kept = tonumber(data.kept) or 0
    return data
end

local function addHeld(data, id, slot)
    local i = #data.held + 1
    data.held[i], data.crabs[i] = id, slot or 0
end

local function removeHeld(data, i)
    local id = table.remove(data.held, i)
    table.remove(data.crabs, i)
    return id
end

local function perCrab(player)
    return player:HasCollectible(CollectibleType.COLLECTIBLE_BFFS) and M.data.bffsPerCrab or M.data.perCrab
end

--- How many trinkets this player's crabs can hold now (owned copies only).
function M.capacity(player)
    if ITEM_ID <= 0 then return 0 end
    return player:GetCollectibleNum(ITEM_ID) * perCrab(player)
end

--- How many trinkets absorbed crabs (Kronos, Thurisaz) may smelt for good.
function M.keptAllowance(player)
    local kronos = ConchBlessing.kronos
    local count = kronos and type(kronos._getEffectCount) == "function" and kronos._getEffectCount(player, ITEM_ID) or 0
    return math.max(0, count) * perCrab(player)
end

-- Players found without a crab ledger (no crab this run): their run save is
-- not read every update. Owning a crab, or a kept crab's room through Kronos,
-- makes them active at once; a new room or game start looks again.
local noLedger = {}

local function players()
    local list, game = {}, Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        if player then list[#list + 1] = player end
    end
    return list
end

local function putDown(id, position)
    local room = Game():GetRoom()
    local at = room:FindFreePickupSpawnPosition(position, 0, true)
    local pickup = Isaac.Spawn(EntityType.ENTITY_PICKUP, TRINKET_VARIANT, id, at, Vector.Zero, nil)
    if pickup then pickup:GetData().__ConchBlessingCrabPutDown = true end
    return pickup
end

-- Smelted copies of exactly this trinket (golden ones counted apart): only for
-- Kronos's keep and the one-time move of an older smelt-based ledger.
local function smelted(player, id)
    local golden = id & goldenFlag() ~= 0
    local normal, gold = TrinketUtils.getSmeltedCounts(player, id & ~goldenFlag())
    if normal == nil then return nil end
    return golden and gold or normal
end

-- Let go of one held trinket: drop its innate copy and put it on the floor.
-- The group's count, not the call's return value, tells whether it went.
local function release(player, id, position)
    local before = innate(player, id)
    player:RemoveInnateTrinket(id, 1, GROUP)
    if innate(player, id) >= before then
        reportOnce("release" .. tostring(id), "could not let go of trinket " .. tostring(id) .. "; its effect stays")
        return false
    end
    putDown(id, position or player.Position)
    evidence.released = evidence.released + 1
    return true
end

--- The crab (by its number) takes a trinket its owner put down.
local function take(player, data, pickup, slot)
    local id = pickup.SubType
    if id <= 0 then return end
    local capacity = M.capacity(player)
    if capacity <= 0 then return end
    -- hold it first: if the engine refuses, the trinket stays on the floor
    local before = innate(player, id)
    player:AddInnateTrinket(id, 1, GROUP, -1, false)
    if innate(player, id) <= before then
        reportOnce("hold" .. tostring(id), "could not hold trinket " .. tostring(id) .. "; it stays on the floor")
        return
    end
    local where = pickup.Position
    pickup:Remove()
    Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.POOF01, 0, where, Vector.Zero, nil)
    slot = slot or 0
    local own = {}
    for i, crab in ipairs(data.crabs) do
        if crab == slot and slot ~= 0 then own[#own + 1] = i end
    end
    addHeld(data, id, slot)
    evidence.taken = evidence.taken + 1
    -- its own claws were full: its own oldest goes down where the new one landed
    if #own >= perCrab(player) then
        if release(player, removeHeld(data, own[1]), where) then evidence.putDown = evidence.putDown + 1 end
    end
    -- still more than every claw together (a crab Box of Friends lent): the oldest
    while #data.held > capacity do
        if release(player, removeHeld(data, 1), where) then evidence.putDown = evidence.putDown + 1 end
    end
    SFXManager():Play(SoundEffect.SOUND_SCAMPER, Sound.volume(M.data.takeVolume), 0, false, 1.2)
end

-- The innate group mirrors the ledger. During play the engine never takes an
-- innate trinket away, but if anything does (another mod), it leaves the claws
-- as well and nothing goes on the floor; no trinket is named here. Extra copies
-- in the group (the crabs' own) go.
local function syncGroup(data, player)
    local counts, order = {}, {}
    for _, id in ipairs(data.held) do
        if not counts[id] then order[#order + 1] = id end
        counts[id] = (counts[id] or 0) + 1
    end
    for _, id in ipairs(order) do
        local actual, n = innate(player, id), counts[id]
        if actual > n then player:RemoveInnateTrinket(id, actual - n, GROUP) end
        local excess = n - actual
        for i = #data.held, 1, -1 do
            if excess <= 0 then break end
            if data.held[i] == id then
                removeHeld(data, i) -- the newest copy of it
                excess = excess - 1
                evidence.vanished = evidence.vanished + 1
            end
        end
    end
end

-- Once after game start (Continue included) or a luamod reload: the ledger is
-- the truth, so the group gets back whatever is missing (should REPENTOGON not
-- have kept it) and loses what is not in the ledger's counts. A ledger from
-- the earlier smelt-based crab is moved over once: its smelted copies go and
-- come back as innate ones.
local function restoreGroup(data, player)
    if data.innate ~= true then
        if #data.held > 0 and canSmelt(player) then
            for _, id in ipairs(data.held) do
                if (smelted(player, id) or 0) > 0 then player:TryRemoveSmeltedTrinket(id) end
            end
        end
        data.innate = true
    end
    local counts, order = {}, {}
    for _, id in ipairs(data.held) do
        if not counts[id] then order[#order + 1] = id end
        counts[id] = (counts[id] or 0) + 1
    end
    for _, id in ipairs(order) do
        local missing = counts[id] - innate(player, id)
        if missing > 0 then player:AddInnateTrinket(id, missing, GROUP, -1, false) end
    end
end

-- Which trinket goes when there are fewer claws: the newest of those whose crab
-- left (`live` holds the numbers of the owner's crabs still in the room) or
-- that a crab now holds beyond its claws (BFFS lost), else the newest.
local function letGoIndex(data, per, live)
    if live then
        local count, spare = {}, nil
        for i = 1, #data.held do
            local slot = data.crabs[i]
            count[slot] = (count[slot] or 0) + 1
            if not live[slot] or count[slot] > per then spare = i end
        end
        if spare then return spare end
    end
    return #data.held
end

-- Fewer claws than trinkets: absorbed crabs keep theirs, smelted for good,
-- while their allowance lasts; the rest go back on the floor.
local function reconcile(player, data, live)
    local capacity = M.capacity(player)
    while #data.held > capacity do
        local id = removeHeld(data, letGoIndex(data, perCrab(player), live))
        if data.kept < M.keptAllowance(player) and canSmelt(player) then
            player:RemoveInnateTrinket(id, 1, GROUP)
            player:AddSmeltedTrinket(id, false)
            data.kept = data.kept + 1
            evidence.kept = evidence.kept + 1
        else
            release(player, id, player.Position)
        end
    end
end

-- Absorbed crabs with room left smelt any trinket in hand at once.
local function smeltInHand(player, data)
    local allowance = M.keptAllowance(player)
    if data.kept >= allowance then return end
    for slot = 0, 1 do
        if data.kept >= allowance then return end
        local id = player:GetTrinket(slot)
        if id and id > 0 and player:TryRemoveTrinket(id) then
            player:AddSmeltedTrinket(id, false)
            data.kept = data.kept + 1
            evidence.smeltedAtOnce = evidence.smeltedAtOnce + 1
        end
    end
end

local SLOT_KEY = "__ConchBlessingHermitCrabSlot"

-- The crab's number among its owner's crabs: the lowest one no other crab of
-- that owner has, kept on the crab (GetData follows a familiar from room to
-- room). Crabs made again by a Continue are numbered again from 1, so each
-- held trinket goes back to a crab of the same number.
local function crabSlot(familiar)
    local data = familiar:GetData()
    if data[SLOT_KEY] then return data[SLOT_KEY] end
    local owner = familiar.Player
    if not owner then return nil end
    local used, hash = {}, GetPtrHash(owner)
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, familiar.Variant)) do
        local other = entity:ToFamiliar()
        local slot = other and other:Exists() and other.Player and GetPtrHash(other.Player) == hash
            and other:GetData()[SLOT_KEY]
        if slot then used[slot] = true end
    end
    local slot = 1
    while used[slot] do slot = slot + 1 end
    data[SLOT_KEY] = slot
    return slot
end

-- Every live crab in the room, by owner, in number order.
local function crabGroups()
    local groups = {}
    local v = variant()
    if not v then return groups end
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, v)) do
        local crab = entity:ToFamiliar()
        local owner = crab and crab:Exists() and crab.Player
        if owner then
            crabSlot(crab) -- numbered in the room's order, before any sorting
            local key = GetPtrHash(owner)
            groups[key] = groups[key] or { owner = owner, crabs = {} }
            table.insert(groups[key].crabs, crab)
        end
    end
    for _, group in pairs(groups) do
        table.sort(group.crabs, function(a, b) return (crabSlot(a) or 0) < (crabSlot(b) or 0) end)
    end
    return groups
end

-- Walking: runtime only, kept on the crab under a key no other mod uses. The
-- crab rolls its strolls on its own RNG seeded from its InitSeed and its
-- number (the crabs of one owner share an InitSeed and would stroll alike), never on
-- gameplay RNG, and forgets its goal on every new room.
local WALK_KEY = "__ConchBlessingHermitCrabWalk"

local function rest(rng)
    return M.data.pauseMin + rng:RandomInt(M.data.pauseMax - M.data.pauseMin + 1)
end

local function walkState(familiar)
    local data = familiar:GetData()
    local state = data[WALK_KEY]
    local slot = crabSlot(familiar) or 0
    if not state then
        state = { rng = RNG(), pause = 0 }
        data[WALK_KEY] = state
    end
    if state.slot ~= slot then -- seeded again once the crab has its number
        state.slot = slot
        state.rng:SetSeed(math.max(1, ((familiar.InitSeed or 1) + slot * 0x9E3779B1) % 0x100000000), 35)
    end
    if state.serial ~= roomSerial then
        state.serial = roomSerial
        state.target, state.detour, state.claim, state.best, state.stuck, state.planned = nil, nil, nil, nil, 0, nil
        state.pause = 15 + state.rng:RandomInt(31)
    end
    return state
end

local NO_GRID = GridCollisionClass and GridCollisionClass.COLLISION_NONE or 0
-- what stops a crab that keeps to the walls: walls, not rocks or pits
local WALL_GRIDS = {
    [GridCollisionClass and GridCollisionClass.COLLISION_WALL or 4] = true,
    [GridCollisionClass and GridCollisionClass.COLLISION_WALL_EXCEPT_PLAYER or 5] = true,
}

-- Whether a straight walk from a to b stays inside the walls (sampled every
-- 10 units, a quarter of a grid cell).
local function clearLine(a, b)
    local room = Game():GetRoom()
    local delta = b - a
    local steps = math.max(1, math.ceil(delta:Length() / 10))
    for i = 1, steps do
        local pos = a + delta * (i / steps)
        if not room:IsPositionInRoom(pos, 0) or WALL_GRIDS[room:GetGridCollisionAtPos(pos)] then return false end
    end
    return true
end

-- A random free spot inside the walls (L-shaped rooms included), or nil.
local function randomSpot(rng)
    local room = Game():GetRoom()
    local tl, br = room:GetTopLeftPos(), room:GetBottomRightPos()
    local margin = M.data.margin
    local w, h = math.max(0, br.X - tl.X - 2 * margin), math.max(0, br.Y - tl.Y - 2 * margin)
    for _ = 1, 8 do
        local spot = Vector(tl.X + margin + rng:RandomFloat() * w, tl.Y + margin + rng:RandomFloat() * h)
        if room:IsPositionInRoom(spot, 0) and room:GetGridCollisionAtPos(spot) == NO_GRID then return spot end
    end
    return nil
end

-- A stroll goal it can walk to in a straight line.
local function strollSpot(rng, from)
    for _ = 1, 8 do
        local spot = randomSpot(rng)
        if spot and clearLine(from, spot) then return spot end
    end
    return nil
end

-- A spot from which both legs, there and on to the goal, are straight walks:
-- of a couple dozen random free spots, the one making the shortest way whose
-- legs are clear (lines are checked shortest first, so most plans check few).
-- Only planned when the straight way is blocked.
local function waypoint(rng, from, to)
    local spots = {}
    for _ = 1, 24 do
        local spot = randomSpot(rng)
        if spot then spots[#spots + 1] = { spot = spot, length = (spot - from):Length() + (to - spot):Length() } end
    end
    table.sort(spots, function(a, b) return a.length < b.length end)
    for _, candidate in ipairs(spots) do
        if clearLine(from, candidate.spot) and clearLine(candidate.spot, to) then return candidate.spot end
    end
    return nil
end

-- Steer toward a goal. Returns the distance and whether it made no progress
-- for a while (a wall corner between it and the goal).
local function walkTo(familiar, state, goal, speed)
    local delta = goal - familiar.Position
    local dist = delta:Length()
    local desired = dist > 1 and delta * (math.min(speed, dist) / dist) or Vector.Zero
    familiar.Velocity = familiar.Velocity * 0.7 + desired * 0.3
    if not state.best or dist < state.best - 0.5 then
        state.best, state.stuck = dist, 0
    else
        state.stuck = state.stuck + 1
    end
    return dist, state.stuck >= M.data.stuckUpdates
end

local function settle(familiar)
    local v = familiar.Velocity * 0.7
    familiar.Velocity = v:Length() < 0.05 and Vector.Zero or v
end

local function wander(familiar, state)
    if state.pause > 0 then
        state.pause = state.pause - 1
        settle(familiar)
        return
    end
    if not state.target then
        state.target, state.best, state.stuck = strollSpot(state.rng, familiar.Position), nil, 0
        if not state.target then
            state.pause = M.data.pauseMin
            settle(familiar)
            return
        end
    end
    local dist, stuck = walkTo(familiar, state, state.target, M.data.wanderSpeed)
    if dist < 4 or stuck then
        state.target = nil
        state.pause = rest(state.rng)
    end
end

-- Whether the crab must leave this trinket alone for now: its owner stands
-- within two tiles of it (they may want it, for a Magic Conch answer say), or
-- a Magic Conch upgrade is changing it.
local function waiting(claim, pickup)
    local owner = claim.owner.Ref and claim.owner.Ref:ToPlayer()
    if owner and (owner.Position - pickup.Position):Length() <= M.data.ownerNear then return "near" end
    local upgrade = ConchBlessing.upgrade
    if upgrade and type(upgrade.isAnimatingPickup) == "function" and upgrade.isAnimatingPickup(pickup) then
        return "upgrade"
    end
    return nil
end

local function countWait(why)
    if why == "near" then
        evidence.waitedNear = evidence.waitedNear + 1
    else
        evidence.waitedUpgrade = evidence.waitedUpgrade + 1
    end
end

-- The claimed trinket is in reach: stop, take it, rest.
local function arrive(familiar, state, claim, pickup)
    state.claim, state.detour, state.target, state.best, state.stuck, state.planned = nil, nil, nil, nil, 0, nil
    state.pause = rest(state.rng)
    claim.done = true
    familiar.Velocity = Vector.Zero
    local owner = claim.owner.Ref and claim.owner.Ref:ToPlayer()
    if not (started and owner and alive(owner) and canHold(owner) and M.capacity(owner) > 0) then return end
    local data = ledger(owner)
    if not data then return end
    evidence.fetchFrom = claim.from or -1
    evidence.fetchAt = (pickup.Position - familiar.Position):Length()
    evidence.fetchCrab = GetPtrHash(familiar)
    take(owner, data, pickup, crabSlot(familiar))
end

local function fetch(familiar, state, claim, pickup)
    -- its owner came back to it, or it is being upgraded: stop and wait there
    local why = waiting(claim, pickup)
    if why then
        countWait(why)
        settle(familiar)
        state.best, state.stuck = nil, 0
        return
    end
    if state.detour then
        local dist, stuck = walkTo(familiar, state, state.detour, M.data.fetchSpeed)
        if dist < 6 or stuck then state.detour, state.best, state.stuck, state.planned = nil, nil, 0, nil end
        return
    end
    if (pickup.Position - familiar.Position):Length() <= M.data.reach then
        return arrive(familiar, state, claim, pickup)
    end
    -- a wall corner in the way (an L-shaped room): go round by a waypoint,
    -- checked once per leg and again whenever it stops making progress
    if not state.planned then
        state.planned = true
        if not clearLine(familiar.Position, pickup.Position) then
            state.detour = waypoint(state.rng, familiar.Position, pickup.Position)
            if state.detour then state.best, state.stuck = nil, 0; return end
        end
    end
    local _, stuck = walkTo(familiar, state, pickup.Position, M.data.fetchSpeed)
    if stuck then
        state.detour = waypoint(state.rng, familiar.Position, pickup.Position) or randomSpot(state.rng)
        state.best, state.stuck = nil, 0
    end
end

-- Hand each dropped trinket to its owner's nearest crab that has nothing to
-- fetch, one with a free claw before one whose claws are full (that one would
-- have to put its own down); forget the ones that are gone or whose owner can
-- no longer hold them. Free claws are read from this update's layout.
local function assignClaims(groups)
    local holder = {}
    for _, group in pairs(groups) do
        for _, crab in ipairs(group.crabs) do
            local claim = walkState(crab).claim
            if claim then holder[claim] = GetPtrHash(crab) end
        end
    end
    local kept = {}
    for _, claim in ipairs(claims) do
        local pickup = claim.ref.Ref and claim.ref.Ref:ToPickup()
        local owner = claim.owner.Ref and claim.owner.Ref:ToPlayer()
        if not claim.done and pickup and pickup:Exists() and owner and alive(owner) and M.capacity(owner) > 0 then
            kept[#kept + 1] = claim
            claim.crab = holder[claim]
            -- nobody sets out while the owner stands by it or it is being upgraded
            local why = not claim.crab and waiting(claim, pickup)
            if why then countWait(why) end
            local group = not claim.crab and not why and groups[GetPtrHash(owner)]
            if group then
                local per = perCrab(owner)
                local best, bestDist, bestRoom
                for _, crab in ipairs(group.crabs) do
                    if not walkState(crab).claim then
                        local d = (crab.Position - pickup.Position):Length()
                        local list = layout[GetPtrHash(crab)]
                        local room = not list or #list < per
                        if not best or (room and not bestRoom) or (room == bestRoom and d < bestDist) then
                            best, bestDist, bestRoom = crab, d, room
                        end
                    end
                end
                if best then
                    local state = walkState(best)
                    state.claim, state.detour, state.best, state.stuck, state.planned = claim, nil, nil, 0, nil
                    claim.crab, claim.from = GetPtrHash(best), bestDist
                end
            end
        else
            claim.done = true
        end
    end
    claims = kept
end

local function claimedAlready(pickup)
    local hash = GetPtrHash(pickup)
    for _, claim in ipairs(claims) do
        local other = not claim.done and claim.ref.Ref
        if other and other:Exists() and GetPtrHash(other) == hash then return true end
    end
    return false
end

-- The trinkets each crab draws: each on the crab that took it; one whose crab
-- is gone (or never named) goes to the first crab with room, which keeps it.
local function relayout(groups)
    layout = {}
    for _, group in pairs(groups) do
        local data = ledger(group.owner)
        local per = perCrab(group.owner)
        local lists, bySlot = {}, {}
        for i, crab in ipairs(group.crabs) do
            lists[i] = {}
            layout[GetPtrHash(crab)] = lists[i]
            local slot = crabSlot(crab)
            if slot then bySlot[slot] = bySlot[slot] or lists[i] end
        end
        if data then
            local placed = {}
            for i, id in ipairs(data.held) do
                local list = bySlot[data.crabs[i]]
                if list and #list < per then
                    list[#list + 1] = id
                    placed[i] = true
                end
            end
            for i, id in ipairs(data.held) do
                if not placed[i] then
                    for k, crab in ipairs(group.crabs) do
                        local list = lists[k]
                        if #list < per then
                            list[#list + 1] = id
                            data.crabs[i] = crabSlot(crab) or 0
                            break
                        end
                    end
                end
            end
        end
    end
end

-- The numbers of the owner's crabs in the room, or nil when none is.
local function liveSlots(groups, player)
    local group = groups[GetPtrHash(player)]
    if not group or #group.crabs == 0 then return nil end
    local live = {}
    for _, crab in ipairs(group.crabs) do
        local slot = crabSlot(crab)
        if slot then live[slot] = true end
    end
    return live
end

-- MC_POST_PICKUP_INIT: remember trinkets a crab owner puts down.
function M.onPickupInit(_, pickup)
    if pickup.Variant ~= TRINKET_VARIANT or ITEM_ID <= 0 then return end
    local spawner = pickup.SpawnerEntity
    local owner = spawner and spawner:ToPlayer()
    if not owner or owner:GetCollectibleNum(ITEM_ID) <= 0 then return end
    if pickup:GetData().__ConchBlessingCrabPutDown then return end
    queue[#queue + 1] = { ref = EntityPtr(pickup), owner = EntityPtr(owner) }
end

function M.onUpdate()
    if not started then return end
    local pending = queue
    queue = {}
    for _, entry in ipairs(pending) do
        local pickup = entry.ref.Ref and entry.ref.Ref:ToPickup()
        local owner = entry.owner.Ref and entry.owner.Ref:ToPlayer()
        if pickup and pickup:Exists() and owner and alive(owner) then
            if not canHold(owner) then
                reportOnce("api", "REPENTOGON's innate trinket API is missing; the crab cannot hold trinkets")
                evidence.ignored = evidence.ignored + 1
            elseif not claimedAlready(pickup) then
                -- a crab walks over and takes it on arrival
                claims[#claims + 1] = { ref = entry.ref, owner = entry.owner }
            end
        end
    end
    local groups = crabGroups()
    local sm = ConchBlessing.SaveManager
    for _, player in ipairs(players()) do
        -- only players who have or had a crab, or whose absorbed crabs still have room
        local key = GetPtrHash(player)
        local active = player:GetCollectibleNum(ITEM_ID) > 0 or M.keptAllowance(player) > 0
        if active then
            noLedger[key] = nil
        elseif not noLedger[key] then
            local save = sm and sm.GetRunSave(player)
            active = save and type(save[SAVE_KEY]) == "table"
            if save and not active then noLedger[key] = true end
        end
        local data = active and ledger(player) or nil
        if data and canHold(player) then
            if restorePending then restoreGroup(data, player) end
            if #data.held > 0 then
                syncGroup(data, player)
                reconcile(player, data, liveSlots(groups, player))
            end
            if alive(player) and canSmelt(player) then smeltInHand(player, data) end
        end
    end
    restorePending = false
    relayout(groups)
    assignClaims(groups)
end

function M.onNewRoom()
    noLedger = {}
    roomSerial = roomSerial + 1
    queue, claims, morphing = {}, {}, {}
end

-- A Morph (a Magic Conch upgrade turning the trinket into its upgrade) can
-- expire the claim's EntityPtr although the pickup stays the same entity. As
-- the upgrade module does, the claim is proven by its live reference at
-- REPENTOGON's MC_PRE_PICKUP_MORPH and handed that very pickup at
-- MC_POST_PICKUP_MORPH; it is never recovered by searching seeds or positions.
function M.onPrePickupMorph(_, pickup)
    if #claims == 0 or not pickup then return end
    local hash = GetPtrHash(pickup)
    local proven = {}
    for _, claim in ipairs(claims) do
        local ref = not claim.done and claim.ref.Ref
        if ref and ref:Exists() and GetPtrHash(ref) == hash then proven[#proven + 1] = claim end
    end
    morphing[hash] = #proven > 0 and proven or nil
end

function M.onPostPickupMorph(_, pickup)
    local hash = pickup and GetPtrHash(pickup)
    local proven = hash and morphing[hash]
    if not proven then return end
    morphing[hash] = nil
    for _, claim in ipairs(proven) do
        if pickup.Variant == TRINKET_VARIANT then
            claim.ref = EntityPtr(pickup) -- the same trinket, upgraded
        else
            claim.done = true -- no longer a trinket
        end
    end
end

function M.onEvaluateCache(_, player, flag)
    if flag ~= CacheFlag.CACHE_FAMILIARS or ITEM_ID <= 0 then return end
    local v = variant()
    if not v then return end
    local count = player:GetCollectibleNum(ITEM_ID) + player:GetEffects():GetCollectibleEffectNum(ITEM_ID)
    local cfg = Isaac.GetItemConfig():GetCollectible(ITEM_ID)
    player:CheckFamiliar(v, count, player:GetCollectibleRNG(ITEM_ID), cfg)
end

local VISUAL_KEY = "__ConchBlessingHermitCrabVisual"
local DRAWN_KEY = "__ConchBlessingHermitCrabDrawnScale"

local function updatePresentation(familiar)
    local owner = familiar.Player
    local bffs = owner and owner:HasCollectible(CollectibleType.COLLECTIBLE_BFFS)
    local held = layout[GetPtrHash(familiar)] or {}
    local pose = bffs and (#held >= 2 and "BffsTwo" or #held == 1 and "BffsOne" or "BffsEmpty")
        or (#held > 0 and "NormalOne" or "NormalEmpty")
    local velocity = familiar.Velocity
    local moving = velocity and velocity.X * velocity.X + velocity.Y * velocity.Y > 0.04
    local animation = pose .. (moving and "Walk" or "Idle")
    local sprite = familiar:GetSprite()
    if sprite:GetAnimation() ~= animation then sprite:Play(animation, true) end
    sprite.FlipX = false -- front art for every movement direction
    -- BFFS growth is drawn into its separate 48px frames, not multiplied again.
    if familiar.SpriteScale.X ~= 1 or familiar.SpriteScale.Y ~= 1 then
        familiar.SpriteScale = Vector(1, 1)
    end
    -- relayout replaces its lists. Freeze this update's list so a late pickup
    -- cannot give the already-rendered body a different pair of held items.
    familiar:GetData()[VISUAL_KEY] = { pose = pose, animation = animation, moving = moving, held = held }
end

local WALLS = EntityGridCollisionClass and EntityGridCollisionClass.GRIDCOLL_WALLS

-- Not a follower: it keeps to the room's walls but passes over rocks and pits.
local function keepToWalls(familiar)
    if WALLS and familiar.GridCollisionClass ~= WALLS then familiar.GridCollisionClass = WALLS end
end

function M.onFamiliarInit(_, familiar)
    keepToWalls(familiar)
    walkState(familiar)
    updatePresentation(familiar)
end

function M.onFamiliarUpdate(_, familiar)
    keepToWalls(familiar)
    local state = walkState(familiar)
    local claim = state.claim
    local pickup = claim and not claim.done and claim.ref.Ref and claim.ref.Ref:ToPickup()
    if pickup and pickup:Exists() then
        fetch(familiar, state, claim, pickup)
    else
        if claim then state.claim, state.detour, state.best, state.stuck, state.planned = nil, nil, nil, 0, nil end
        wander(familiar, state)
    end
    updatePresentation(familiar)
end

local function isReflectionPass()
    local room = Game():GetRoom()
    return RenderMode and type(room.GetRenderMode) == "function"
        and room:GetRenderMode() == RenderMode.RENDER_WATER_REFLECT
end

local function overlay()
    if not sprites.claws then
        sprites.claws = Sprite()
        sprites.claws:Load(ANM2, true)
    end
    return sprites.claws
end

local function trinketSprite(id)
    local base = id & ~goldenFlag()
    local cached = sprites.trinkets[id]
    if cached then return cached end
    local cfg = Isaac.GetItemConfig():GetTrinket(base)
    if not cfg then return nil end
    local sprite = Sprite()
    sprite:Load(ANM2, false)
    sprite:ReplaceSpritesheet(0, cfg.GfxFileName)
    sprite:LoadGraphics()
    sprite:Play("Trinket", true)
    -- The icon's opaque bounds, measured offline by generate_hermit_crab_assets.py
    -- (Sprite:GetTexel reads alpha 0 in game). Another mod's trinket gets the
    -- typical vanilla box.
    local name = tostring(cfg.GfxFileName or ""):match("([^/\\]+)$")
    local measured = name and Visuals.trinketBounds and Visuals.trinketBounds[name:lower()]
        or Visuals.defaultBounds or { 16, 0, 32 }
    local bounds = { center = measured[1], top = measured[2], bottom = measured[3] }
    if id ~= base then sprite.Color = Color(1, 1, 1, 1, 0.18, 0.12, 0) end -- a golden glint
    local entry = { sprite = sprite, bounds = bounds }
    sprites.trinkets[id] = entry
    return entry
end

-- BFFS: after the familiar's own update the engine scales a BFFS familiar by
-- 1.25 again (measured in game 2026-11-09: SpriteScale read 1.25 at
-- MC_POST_UPDATE although the familiar update had set 1). The larger BFFS
-- frames already hold that growth, so it is undone right before the body is
-- drawn (REPENTOGON's MC_PRE_FAMILIAR_RENDER; the item needs REPENTOGON anyway).
function M.onPreFamiliarRender(_, familiar)
    local scale = familiar.SpriteScale
    if scale.X ~= 1 or scale.Y ~= 1 then familiar.SpriteScale = Vector(1, 1) end
end

-- Held trinkets, then the claws over them.
function M.onFamiliarRender(_, familiar, offset)
    local v = variant()
    if familiar.Variant ~= v or isReflectionPass() then return end
    local state = familiar:GetData()[VISUAL_KEY]
    if not state or familiar.Visible == false then return end
    local held = state.held
    local scale = familiar.SpriteScale.X
    familiar:GetData()[DRAWN_KEY] = scale -- the update replaces the visual state
    local feet = familiar.Position + familiar.PositionOffset
    local base = Isaac.WorldToRenderPosition and (Isaac.WorldToRenderPosition(feet) + (offset or Vector.Zero))
        or Isaac.WorldToScreen(feet)
    local body = familiar:GetSprite()
    local timelineFrame = state.moving and body:GetFrame() or 0
    local step = math.floor(timelineFrame / Visuals.frameDelay) % Visuals.stepCount + 1
    local slots = Visuals.poses[state.pose].frames[step]
    for i, id in ipairs(held) do
        local entry = trinketSprite(id)
        local slot = slots[i]
        if entry and slot then
            local sprite, bounds = entry.sprite, entry.bounds
            local bottom = slot.bottom
            if slot.minTop then
                bottom = math.max(bottom, slot.minTop + (bounds.bottom - bounds.top) * slot.scale)
            end
            sprite.Scale = Vector(slot.scale * scale, slot.scale * scale)
            if ConchBlessing.AprilFools then ConchBlessing.AprilFools.Apply(sprite) end
            sprite:Render(base + Vector(slot.x - bounds.center * slot.scale,
                bottom - bounds.bottom * slot.scale) * scale)
        end
    end
    local claws = overlay()
    claws:SetFrame("Grip" .. state.animation, timelineFrame)
    claws.Scale = Vector(scale, scale)
    claws.Color = familiar.Color
    if ConchBlessing.AprilFools then ConchBlessing.AprilFools.Apply(claws) end
    claws:Render(base)
end

-- Run saves are read only after the game has started (they still hold the last
-- run before that). A luamod reload in the middle of a run never sees game
-- start; SaveManager reloads this run's data a little later and says so
-- (POST_DATA_LOAD with isLuamod), and the crab starts then.
function M.onGameStarted()
    started = true
    restorePending = true
    roomSerial = roomSerial + 1
    noLedger = {}
    queue, claims, layout, morphing = {}, {}, {}, {}
    sprites = { trinkets = {} }
end

function M.onGameExit()
    started = false
    roomSerial = roomSerial + 1
    queue, claims, layout, morphing = {}, {}, {}, {}
    sprites = { trinkets = {} }
end

M._test = {
    started = function() return started end,
    trinketBounds = function(id) local entry = trinketSprite(id); return entry and entry.bounds end,
    evidence = function() return evidence end,
    resetEvidence = resetEvidence,
    ledger = ledger,
    queue = function() return queue end,
    claims = function() return claims end,
    walkState = walkState,
    slot = crabSlot,
    layout = function() return layout end,
    itemId = function() return ITEM_ID end,
    variant = variant,
    release = release,
    group = GROUP,
    drawnScale = function(familiar) return familiar:GetData()[DRAWN_KEY] end,
}

-- The familiar render and the pickup init need no item filter of their own.
if ModCallbacks and ModCallbacks.MC_POST_PICKUP_INIT then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_PICKUP_INIT, M.onPickupInit, TRINKET_VARIANT)
end
do
    local sm = ConchBlessing.SaveManager or SaveManager
    local mod = ConchBlessing.originalMod
    if sm and mod and mod.__SAVEMANAGER_UNIQUE_KEY and sm.SaveCallbacks and sm.SaveCallbacks.POST_DATA_LOAD then
        mod:AddCallback(sm.SaveCallbacks.POST_DATA_LOAD, function(_, _, isLuamod)
            if isLuamod then M.onGameStarted() end
        end)
    end
end
if ModCallbacks and type(ModCallbacks.MC_PRE_PICKUP_MORPH) == "number"
    and type(ModCallbacks.MC_POST_PICKUP_MORPH) == "number" then
    ConchBlessing:AddCallback(ModCallbacks.MC_PRE_PICKUP_MORPH, M.onPrePickupMorph)
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_PICKUP_MORPH, M.onPostPickupMorph)
end
if ModCallbacks and type(ModCallbacks.MC_PRE_FAMILIAR_RENDER) == "number" and variant() then
    ConchBlessing:AddCallback(ModCallbacks.MC_PRE_FAMILIAR_RENDER, M.onPreFamiliarRender, variant())
end

return M
