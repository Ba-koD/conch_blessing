local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 욥의 축복 (Job's Blessing), the Magic Conch's positive answer to Damocles
-- (user design 2026-11-18). Damocles hangs a sword over the riches it brings;
-- this one takes the sword away and keeps only the riches: everything its
-- holder acquires comes twice ("이전 모든 소유보다 갑절을 주신지라", Job 42:10).
-- Nothing else changes: no sword, no price paid twice, one copy or many alike.
--
-- The user's rules (2026-11-18), one semantic event each, never a list of
-- items or sources:
-- * Items: every collectible acquisition is one engine event, AddCollectible
--   with its FirstTime flag (REPENTOGON's MC_POST_ADD_COLLECTIBLE). A passive
--   or familiar that enters the inventory for the first time brings one more
--   copy, with its own pickup consumables, wherever it came from: a pedestal,
--   a shop or deal, or another effect handing over a new item (Golden Items'
--   golden pedestal, Two Faced Penny's payout). A Quarter therefore gives 50
--   cents: two Quarters, 25 each; the coins themselves are not doubled again.
--   Every item is two acquisitions with no exception (the user, 2026-11-19:
--   "아이템, 장신구 흡수는 그냥 예외없이 아이템 두개 획득"), quest items,
--   hidden items and this item included; only actives stay single (the user's
--   earlier decision). An item handed back or re-taken, or a reroll, is no
--   acquisition: the engine itself adds it with FirstTime false.
-- * Trinkets: every way a trinket is absorbed (smelted) is one engine event,
--   REPENTOGON's MC_POST_TRIGGER_TRINKET_ADDED, with the trinket landing in the
--   smelted inventory; that inventory then grows once more by the same amount
--   (Smelter, Gulp!, Marbles, a debris absorbed at a touch, another mod's
--   AddSmeltedTrinket). Measured 2026-11-19: the Smelter's event fires before
--   its smelted count rises and AddSmeltedTrinket's after, and every smelted
--   removal has its own event, so a gain is read at the event or on the next
--   update and removals (a Conch Debris trio turned into a ticket) never hide
--   one. A trinket that only goes to the hand is not absorbed and does not
--   double ("손에 갈 때 흡수가 아니라 흡수할 때 2배"); innate trinkets are not
--   smelted either.
-- * Pickups absorbed on touch (the engine plays their Collect animation, or
--   removes a bought one at once):
--   nothing is spawned or changed on the floor (the user, 2026-11-19: "소환,
--   생성 등등 전부 건들지말라고"); what the pickup added is added once more.
--   The holder's numbers are read as the engine's collision starts and after
--   it ends, and every number that rose rises by the same amount again: coins
--   (a nickel 5 more), keys, bombs, giga bombs, poop, active charge and luck
--   (a lucky penny). Hearts double through the healing rule below. A price
--   paid is a fall and stays as it is. Other mods' own pickups get no handling
--   of their own: the engine has no add callback for these numbers, and the
--   user does not want one made for them (2026-11-19). A sack's contents are new pickups on
--   the floor, so a sack is not repeated; each of its pickups doubles when
--   taken. Cards, runes and pills are kept to be used, not absorbed, and stay
--   single.
-- * Healing: every heart added to the holder is added twice, a pickup's or
--   anything else's (an active, a room reward, an item's own consumables).
--   Heart containers come with the item copies and broken hearts are a cost;
--   neither is healing. Health that does not fit is lost, as a double heart's
--   is. A heart addition the engine makes inside another one is part of that
--   one and doubles only through it (measured 2026-11-19: a black heart adds
--   its soul hearts through an inner add, and doubling both made it four
--   times); MC_POST_PLAYER_ADD_HEARTS closes each addition. Hearts an item
--   gives as it is added (Breakfast's) come with the item, like A Quarter's
--   coins: they double through the item's copy and are not doubled again
--   (an add opens at MC_PRE_ADD_COLLECTIBLE and closes at its POST).
--
-- The collectible copies wait until the holder's item queue has been empty
-- for a whole update, so another pickup transaction (Appraisal's exact trinket
-- evidence, Atropos's choice window) has closed before the copy arrives. Every
-- add while a copy is being given is ignored, so no copy, and no item another
-- mod turns it into, is ever doubled again.
--
-- A copy is not a new acquisition, and neither is another mod's answer to it.
-- Multiplier Get compares item counts every update and multiplies whatever
-- grew, our copy included; doubling its answer again fed the two without end
-- (measured 2026-11-19 with its x2: 242 copies of one item in 120 updates).
-- No engine event names the cause of a later add, so a first-time add of the
-- same item to the same player in the update a copy arrived or the next one
-- (M.reactionWindow) is taken as that answer and not doubled. The limitation:
-- a genuinely new pickup of that very item inside those two updates would not
-- double either; a pedestal's own hold-up alone lasts longer.
--
-- Needs REPENTOGON (every event used is a REPENTOGON callback). The only saved
-- state is the luck a doubled lucky penny gave, which stays like the penny's.
local M = {}
ConchBlessing.jobsblessing = M

local SAVE_KEY = "jobsBlessing"
local GOLDEN = TrinketType.TRINKET_GOLDEN_FLAG or 32768

-- Pickups that are not absorbed on touch: collectibles and trinkets have their
-- own events, and cards, runes and pills are kept to be used.
M.notAbsorbed = {
    [PickupVariant.PICKUP_COLLECTIBLE] = true,
    [PickupVariant.PICKUP_TRINKET] = true,
    [PickupVariant.PICKUP_TAROTCARD] = true,
    [PickupVariant.PICKUP_PILL] = true,
}
M.settleUpdates = 1 -- whole updates with an empty item queue before an item copy arrives
M.smeltSweep = 30   -- updates between full smelted-inventory checks (silent changes)
M.reactionWindow = 1 -- updates after a copy in which a first-time add of that item answers the copy

-- Kinds of health whose additions are healing (REPENTOGON AddHealthType).
local HEAL = 0
if type(AddHealthType) == "table" then
    for _, name in ipairs({ "RED", "SOUL", "BLACK", "ETERNAL", "GOLDEN", "BONE", "ROTTEN" }) do
        HEAL = HEAL | (AddHealthType[name] or 0)
    end
end
M.healTypes = HEAL

local function itemId()
    local row = ConchBlessing.ItemData and ConchBlessing.ItemData.JOBS_BLESSING
    return row and type(row.id) == "number" and row.id or -1
end

local function callbackId(name)
    local id = ModCallbacks and ModCallbacks[name]
    return type(id) == "number" and id or nil
end
local addCollectible = callbackId("MC_POST_ADD_COLLECTIBLE")
local preAddCollectible = callbackId("MC_PRE_ADD_COLLECTIBLE")
local trinketAdded = callbackId("MC_POST_TRIGGER_TRINKET_ADDED")
local trinketRemoved = callbackId("MC_POST_TRIGGER_TRINKET_REMOVED")
local prePickupCollision = callbackId("MC_PRE_PICKUP_COLLISION")
local pickupCollision = callbackId("MC_POST_PICKUP_COLLISION")
local addHearts = callbackId("MC_PRE_PLAYER_ADD_HEARTS")
local addedHearts = callbackId("MC_POST_PLAYER_ADD_HEARTS")
M.available = addCollectible ~= nil and pickupCollision ~= nil and prePickupCollision ~= nil

local pending = {}   -- [GetPtrHash(player)] = { list = { collectible ids }, empty = updates seen empty }
local smelted = {}   -- [GetPtrHash(player)] = { counts = { [id] = { n, g } }, dirty = { [id] = true }, gains, at }
local touching = {}  -- [GetPtrHash(player)] = the holder's numbers as the engine's pickup collision began
local giving = nil   -- GetPtrHash of the player a copy is being given to right now
local given = {}     -- [GetPtrHash(player)] = { [item id] = frame a copy last arrived }
local hearting = {}  -- [GetPtrHash(player)] = heart additions open right now (one inside another counts once)
local adding = {}    -- [GetPtrHash(player)] = collectible additions open right now (their hearts come with the item)
local reported = {}
local evidence
local function resetEvidence()
    evidence = { collectibles = 0, trinkets = 0, pickups = 0, heals = 0, queued = 0, ignored = 0, reactions = 0,
        luck = 0, itemHearts = 0, notFirst = 0, added = {} }
end
resetEvidence()

local function reportOnce(key, message)
    if reported[key] then return end
    reported[key] = true
    ConchBlessing.printError("Job's Blessing: " .. message)
end

-- ------------------------------------------------------------------ rules
local function alive(player)
    if not player or not player:Exists() or player:IsDead() then return false end
    return not (type(player.IsCoopGhost) == "function" and player:IsCoopGhost())
end

local function holds(player)
    local id = itemId()
    return id > 0 and alive(player) and player:GetCollectibleNum(id) > 0
end

-- Whether a collectible entering the inventory for the first time comes
-- twice: every one but an active, glitched items (negative IDs) included.
local function collectibleDoubles(id, config)
    if type(id) ~= "number" or id == 0 or not config then return false end
    return config.Type ~= ItemType.ITEM_ACTIVE
end

-- A pickup variant absorbed on touch (its numbers are added once more).
local function absorbedOnTouch(variant)
    return type(variant) == "number" and not M.notAbsorbed[variant]
end

-- The amount a heart addition becomes: healing doubles, nothing else does.
local function healAmount(amount, healthType)
    if type(amount) ~= "number" or amount <= 0 then return nil end
    if type(healthType) ~= "number" or healthType & HEAL == 0 or healthType & ~HEAL ~= 0 then return nil end
    return amount * 2
end

-- ------------------------------------------------------------------ pickup numbers
local function saveManager()
    local sm = ConchBlessing.SaveManager
    if type(sm) ~= "table" then return nil end
    if type(sm.IsLoaded) == "function" and not sm.IsLoaded() then return nil end
    return sm
end

-- The numbers a pickup can add, each with how to read it and add to it.
local function method(player, name) return type(player[name]) == "function" end
local NUMBERS = {
    { name = "coins", get = function(p) return p:GetNumCoins() end, add = function(p, n) p:AddCoins(n) end },
    { name = "keys", get = function(p) return p:GetNumKeys() end, add = function(p, n) p:AddKeys(n) end },
    { name = "bombs", get = function(p) return p:GetNumBombs() end, add = function(p, n) p:AddBombs(n) end },
    { name = "gigaBombs", has = function(p) return method(p, "GetNumGigaBombs") and method(p, "AddGigaBombs") end,
        get = function(p) return p:GetNumGigaBombs() end, add = function(p, n) p:AddGigaBombs(n) end },
    { name = "poop", has = function(p) return method(p, "GetPoopMana") and method(p, "AddPoopMana") end,
        get = function(p) return p:GetPoopMana() end, add = function(p, n) p:AddPoopMana(n) end },
}
M.numbers = NUMBERS
local SLOTS = { 0, 1, 2, 3 } -- primary, secondary, pocket, the pocket's second

local function maxCharge(player, slot, item)
    if method(player, "GetActiveMaxCharge") then return player:GetActiveMaxCharge(slot) end
    local config = Isaac.GetItemConfig():GetCollectible(item)
    return config and config.MaxCharges or 0
end

-- The holder's numbers right now.
local function readNumbers(player)
    local out = { luck = player.Luck, charge = {}, battery = {}, full = {}, takes = {} }
    for _, number in ipairs(NUMBERS) do
        if not number.has or number.has(player) then out[number.name] = number.get(player) end
    end
    for _, slot in ipairs(SLOTS) do
        local item = player:GetActiveItem(slot)
        if item > 0 then
            out.charge[slot] = player:GetActiveCharge(slot) + player:GetBatteryCharge(slot)
            out.battery[slot] = player:GetBatteryCharge(slot)
            out.full[slot] = player:GetActiveCharge(slot) >= maxCharge(player, slot, item)
            out.takes[slot] = method(player, "NeedsCharge") and player:NeedsCharge(slot) or false
        end
    end
    return out
end

-- What rose between `before` and `after` (falls, such as a price, are left out).
local function rises(before, after)
    local out = { charge = {} }
    for _, number in ipairs(NUMBERS) do
        local was, now = before[number.name], after[number.name]
        if was and now and now > was then out[number.name] = now - was end
    end
    for slot, now in pairs(after.charge) do
        local was = before.charge[slot]
        if was and now > was then
            -- The pickup could overcharge when it did, or when it filled the
            -- item to the top and the item still takes charge (The Battery).
            local overcharged = (after.battery[slot] or 0) > (before.battery[slot] or 0)
            local filled = after.full and after.full[slot] and after.takes and after.takes[slot]
            out.charge[slot] = { amount = now - was, overcharge = overcharged or filled or false }
        end
    end
    if after.luck > before.luck then out.luck = after.luck - before.luck end
    return out
end

local function runSave(player)
    local sm = saveManager()
    local save = sm and sm.GetRunSave(player)
    if type(save) ~= "table" then return nil end
    save[SAVE_KEY] = save[SAVE_KEY] or {}
    return save[SAVE_KEY]
end

-- Luck a doubled lucky penny gave: kept like the penny's own, held or not.
local function addLuck(player, amount)
    local save = runSave(player)
    if not save then
        reportOnce("luck", "the run save is not ready; a lucky penny's luck was not repeated")
        return
    end
    save.luck = (save.luck or 0) + amount
    evidence.luck = evidence.luck + amount
    player:AddCacheFlags(CacheFlag.CACHE_LUCK)
    player:EvaluateItems()
end

-- Add once more everything a pickup added.
local function repeatRises(player, gained)
    for _, number in ipairs(NUMBERS) do
        local amount = gained[number.name]
        if amount then
            number.add(player, amount)
            evidence.added[number.name] = (evidence.added[number.name] or 0) + amount
        end
    end
    for slot, row in pairs(gained.charge) do
        if method(player, "AddActiveCharge") then
            player:AddActiveCharge(row.amount, slot, true, row.overcharge, false)
        else
            player:SetActiveCharge(player:GetActiveCharge(slot) + player:GetBatteryCharge(slot) + row.amount, slot)
        end
        evidence.added.charge = (evidence.added.charge or 0) + row.amount
    end
    if gained.luck then addLuck(player, gained.luck) end
end

local function giveCollectible(player, id)
    local hash = GetPtrHash(player)
    giving = hash
    local ok, err = pcall(function() player:AddCollectible(id, 0, true) end)
    giving = nil
    given[hash] = given[hash] or {}
    given[hash][id] = Game():GetFrameCount()
    if ok then evidence.collectibles = evidence.collectibles + 1
    else ConchBlessing.printError("Job's Blessing: giving a copy of item " .. tostring(id) .. " failed: " .. tostring(err)) end
end

-- ------------------------------------------------------------------ smelted inventory
local function readSmelted(player)
    if type(player.GetSmeltedTrinkets) ~= "function" then return nil end
    local ok, list = pcall(function() return player:GetSmeltedTrinkets() end)
    if not ok or type(list) ~= "table" then return nil end
    local counts = {}
    for id, entry in pairs(list) do
        if type(id) == "number" and type(entry) == "table" then
            local normal = math.max(0, tonumber(entry.trinketAmount) or 0)
            local golden = math.max(0, tonumber(entry.goldenTrinketAmount) or 0)
            if normal > 0 or golden > 0 then counts[id] = { normal, golden } end
        end
    end
    return counts
end

-- Compare one trinket's smelted copies with the record: a rise is an
-- absorption to repeat, a fall only moves the record.
local function noteSmelted(entry, counts, id)
    local now = counts[id] or { 0, 0 }
    local was = entry.counts[id] or { 0, 0 }
    local normal, golden = now[1] - was[1], now[2] - was[2]
    entry.counts[id] = { now[1], now[2] }
    if normal > 0 or golden > 0 then
        entry.gains[#entry.gains + 1] = { id = id, normal = math.max(0, normal), golden = math.max(0, golden) }
        return true
    end
    return false
end

-- Absorb once more every absorption noted since the last update.
local function settleSmelted(player, entry)
    local counts = readSmelted(player)
    if not counts then
        reportOnce("smelted", "this REPENTOGON build cannot read smelted trinkets; trinkets stay single")
        return
    end
    if Game():GetFrameCount() - entry.at >= M.smeltSweep then
        entry.at = Game():GetFrameCount()
        local ids = {}
        for id in pairs(counts) do ids[id] = true end
        for id in pairs(entry.counts) do ids[id] = true end
        for id in pairs(ids) do noteSmelted(entry, counts, id) end
    else
        for id in pairs(entry.dirty) do noteSmelted(entry, counts, id) end
    end
    entry.dirty = {}
    if #entry.gains == 0 then return end
    local gains = entry.gains
    entry.gains = {}
    giving = GetPtrHash(player)
    local ok, err = pcall(function()
        for _, gain in ipairs(gains) do
            for _ = 1, gain.normal do player:AddSmeltedTrinket(gain.id, false) end
            for _ = 1, gain.golden do player:AddSmeltedTrinket(gain.id | GOLDEN, false) end
            evidence.trinkets = evidence.trinkets + gain.normal + gain.golden
        end
    end)
    giving = nil
    if not ok then ConchBlessing.printError("Job's Blessing: absorbing a trinket copy failed: " .. tostring(err)) end
    counts = readSmelted(player) or counts
    for _, gain in ipairs(gains) do
        local now = counts[gain.id] or { 0, 0 }
        entry.counts[gain.id] = { now[1], now[2] }
    end
end

-- A trinket event for a holder: an absorption seen now is noted at once; one
-- whose count has not risen yet (the Smelter's) is looked at next update.
local function trinketEvent(player, trinket, added)
    local entry = smelted[GetPtrHash(player)]
    if not entry or type(trinket) ~= "number" then return end
    local id = trinket & ~GOLDEN
    local counts = readSmelted(player)
    if not counts then return end
    local gained = noteSmelted(entry, counts, id)
    if added and not gained then entry.dirty[id] = true end
end

-- ------------------------------------------------------------------ callbacks
-- A collectible addition opens here (LATE, after any mod that would cancel it)
-- and closes in M.onAddCollectible (first of all): the hearts the item itself
-- gives in between come with the item.
function M.onPreAddCollectible(_, _id, _charge, _firstTime, _slot, _varData, player)
    if player then
        local hash = GetPtrHash(player)
        adding[hash] = (adding[hash] or 0) + 1
    end
    return nil
end

function M.onAddCollectibleOpened(_, _id, _charge, _firstTime, _slot, _varData, player)
    if not player then return end
    local hash = GetPtrHash(player)
    local open = (adding[hash] or 0) - 1
    adding[hash] = open > 0 and open or nil
end

function M.onAddCollectible(_, id, _charge, firstTime, _slot, _varData, player)
    if not player then return end
    if giving == GetPtrHash(player) then
        evidence.ignored = evidence.ignored + 1
        return
    end
    if not holds(player) then return end
    if firstTime ~= true then
        evidence.notFirst = evidence.notFirst + 1
        return
    end
    if not collectibleDoubles(id, Isaac.GetItemConfig():GetCollectible(id)) then return end
    local hash = GetPtrHash(player)
    local last = given[hash] and given[hash][id]
    if last and Game():GetFrameCount() - last <= M.reactionWindow then
        evidence.reactions = evidence.reactions + 1
        return
    end
    local entry = pending[hash]
    if not entry then
        entry = { list = {}, empty = 0 }
        pending[hash] = entry
    end
    entry.list[#entry.list + 1] = id
    entry.empty = 0
    evidence.queued = evidence.queued + 1
end

-- Every trinket entering a holder may be an absorption; every one leaving keeps
-- the smelted record in step, so a removal never hides a gain.
function M.onTrinketAdded(_, player, trinket)
    if player and giving ~= GetPtrHash(player) then trinketEvent(player, trinket, true) end
end

function M.onTrinketRemoved(_, player, trinket)
    if player and giving ~= GetPtrHash(player) then trinketEvent(player, trinket, false) end
end

-- Every heal doubles, a heart pickup's included; an addition the engine makes
-- inside another one is part of the outer one and is not doubled again, and
-- hearts an item gives as it is added come with the item and its copy.
function M.onAddHearts(_, player, amount, healthType)
    if not player then return nil end
    local hash = GetPtrHash(player)
    local open = hearting[hash] or 0
    hearting[hash] = open + 1
    if open > 0 or not holds(player) then return nil end
    if (adding[hash] or 0) > 0 or giving == hash then
        evidence.itemHearts = evidence.itemHearts + 1
        return nil
    end
    local doubled = healAmount(amount, healthType)
    if doubled then evidence.heals = evidence.heals + 1 end
    return doubled
end

function M.onAddedHearts(_, player)
    if not player then return end
    local hash = GetPtrHash(player)
    local open = (hearting[hash] or 0) - 1
    hearting[hash] = open > 0 and open or nil
end

-- The holder's numbers as the engine's collision begins (first of all
-- callbacks, so the whole collision is measured).
function M.onPrePickupCollision(_, pickup, collider)
    local player = collider and collider:ToPlayer()
    if not player then return nil end
    -- A snapshot left by a collision another mod cancelled never outlives the next one.
    touching[GetPtrHash(player)] = absorbedOnTouch(pickup.Variant) and holds(player) and readNumbers(player) or nil
    return nil
end

-- The engine has just taken `pickup` when its Collect animation started during
-- this collision, or when it was removed in it: a bought pickup goes at once,
-- with no Collect (measured 2026-11-19: a key for sale is dead and gone in its
-- POST collision, its key already added). A pickup only touched stays alive.
local function collectedNow(pickup)
    if pickup:GetSprite():GetAnimation() == "Collect" then return true end
    return pickup:IsDead() or not pickup:Exists()
end

function M.onPickupCollision(_, pickup, collider)
    local player = collider and collider:ToPlayer()
    if not player then return end
    local hash = GetPtrHash(player)
    local before = touching[hash]
    touching[hash] = nil
    if not before or not collectedNow(pickup) or not holds(player) then return end
    -- A lucky penny's luck has risen by now (measured 2026-11-19: 0 before
    -- the collision, 1 after it).
    evidence.pickups = evidence.pickups + 1
    repeatRises(player, rises(before, readNumbers(player)))
end

function M.onEvaluateCache(_, player, flag)
    if flag ~= CacheFlag.CACHE_LUCK then return end
    local save = runSave(player)
    if save and (save.luck or 0) ~= 0 then ConchBlessing.stats.luck.applyAddition(player, save.luck, nil) end
end

function M.onPlayerUpdate(_, player)
    local hash = GetPtrHash(player)
    touching[hash] = nil
    -- Absorbed trinkets: a baseline the moment the player holds the item, then
    -- every gain absorbed once more.
    if holds(player) then
        local entry = smelted[hash]
        if not entry then
            local counts = readSmelted(player)
            if counts then smelted[hash] = { counts = counts, dirty = {}, gains = {}, at = Game():GetFrameCount() } end
        elseif next(entry.dirty) or #entry.gains > 0 or Game():GetFrameCount() - entry.at >= M.smeltSweep then
            settleSmelted(player, entry)
        end
    else
        smelted[hash] = nil
    end
    -- Item copies, once the engine's own pickup transaction is over.
    local entry = pending[hash]
    if not entry then return end
    if not player:IsItemQueueEmpty() then
        entry.empty = 0
        return
    end
    entry.empty = entry.empty + 1
    if entry.empty <= M.settleUpdates then return end
    pending[hash] = nil
    for _, id in ipairs(entry.list) do giveCollectible(player, id) end
end

-- Nothing stays open across updates (an addition whose closing callback never came).
function M.onUpdate() touching, hearting, adding = {}, {}, {} end
function M.onNewRoom() touching = {} end
local function reset()
    pending, smelted, touching, given, hearting, adding, giving = {}, {}, {}, {}, {}, {}, nil
end
M.onGameStarted = reset
M.onGameExit = reset

-- Saved luck is applied as soon as the save is there (a Continue or a luamod
-- evaluates the cache before SaveManager has loaded), so it never turns up
-- later in the middle of a pickup and looks like that pickup's luck.
local function evaluateLuck()
    local game = Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local player = game:GetPlayer(i)
        if player then
            player:AddCacheFlags(CacheFlag.CACHE_LUCK)
            player:EvaluateItems()
        end
    end
end
M.onDataLoad = evaluateLuck

-- Glowing Hourglass puts the inventory and the run save back as they were:
-- the smelted record starts again from what is there now (a trinket the
-- rewind gives back is no new absorption), queued copies go with the items
-- they were for, and the saved luck is the rewound one.
function M.onHourglassReset()
    reset()
    evaluateLuck()
end

M._test = {
    collectibleDoubles = collectibleDoubles,
    absorbedOnTouch = absorbedOnTouch,
    healAmount = healAmount,
    noteSmelted = noteSmelted,
    readNumbers = readNumbers,
    rises = rises,
    holds = holds,
    readSmelted = readSmelted,
    pending = function() return pending end,
    smelted = function() return smelted end,
    adding = function() return adding end,
    touching = function() return touching end,
    evidence = function() return evidence end,
    resetEvidence = resetEvidence,
    saveKey = SAVE_KEY,
}

-- REPENTOGON's add, heart and collision events, which the ItemData registrar
-- does not map. LATE, so every other mod has finished first; the collision's
-- numbers are read first of all callbacks.
if M.available then
    local priority = rawget(_G, "CallbackPriority")
    local late = priority and priority.LATE or 100
    local first = priority and priority.IMPORTANT or -200
    ConchBlessing:AddPriorityCallback(addCollectible, late, M.onAddCollectible)
    -- An item's own hearts are told apart by the add they arrive inside.
    if preAddCollectible then
        ConchBlessing:AddPriorityCallback(preAddCollectible, late, M.onPreAddCollectible)
        ConchBlessing:AddPriorityCallback(addCollectible, first, M.onAddCollectibleOpened)
    end
    if trinketAdded then ConchBlessing:AddPriorityCallback(trinketAdded, late, M.onTrinketAdded) end
    if trinketRemoved then ConchBlessing:AddPriorityCallback(trinketRemoved, late, M.onTrinketRemoved) end
    ConchBlessing:AddPriorityCallback(prePickupCollision, first, M.onPrePickupCollision)
    ConchBlessing:AddPriorityCallback(pickupCollision, late, M.onPickupCollision)
    -- Doubling heals needs both ends of an addition to tell an inner one apart.
    if addHearts and addedHearts then
        ConchBlessing:AddPriorityCallback(addHearts, late, M.onAddHearts)
        ConchBlessing:AddPriorityCallback(addedHearts, late, M.onAddedHearts)
    end
    local sm, mod = ConchBlessing.SaveManager, ConchBlessing.originalMod
    local ids = type(sm) == "table" and sm.SaveCallbacks
    if mod and type(ids) == "table" then
        if ids.POST_DATA_LOAD then mod:AddCallback(ids.POST_DATA_LOAD, M.onDataLoad) end
        if ids.POST_GLOWING_HOURGLASS_RESET then mod:AddCallback(ids.POST_GLOWING_HOURGLASS_RESET, M.onHourglassReset) end
    end
else
    ConchBlessing.printDebug("Job's Blessing: REPENTOGON's add and pickup callbacks are missing; nothing doubles")
end

return M
