local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 전우치 (Jeon Woo-chi), the Magic Conch's positive answer to The Wiz (user
-- design 2026-11-13): the righteous thief of 『전우치전』.
--
-- The moment a player picks up a copy, he takes, among that player's
-- transformations not yet complete, one with the most progress at random, and
-- steals as many of its items as it still needs (its threshold minus the
-- counter), chosen at random, leaving each on a free pedestal near the player
-- (the choosing section). Every copy does this at the moment it is picked up;
-- two copies picked up in the same update each steal on their own, one after
-- the other. With every transformation complete he steals nothing.
--
-- At each spot a 전우치 effect plays his arrival (docs/previews/jeonwoochi/
-- author.py owns its frames): a streak of light, the landing, the fan, the
-- 부적 and a "펑" of smoke; the pedestal appears at the animation's Item event,
-- under the smoke. Each theft is a record in the room's save until its
-- pedestal stands, so leaving the room or the game during the show places it
-- on the next entry. Reading transformation progress needs REPENTOGON.
local definitions = require("scripts.entities.definitions")
local Forms = require("scripts.lib.player_forms")
local Sound = require("scripts.lib.sound_volume")

ConchBlessing.jeonwoochi = ConchBlessing.jeonwoochi or {}
local M = ConchBlessing.jeonwoochi

M.data = {
    distance = 80,       -- how far from the player the spots are looked for (two tiles)
    nearest = 52,        -- no spot closer to the player than this
    gap = 56,            -- spots keep this far from one another
    stagger = 10,        -- updates between one arrival and the next
    -- Each 전우치 lands and fans himself (`Steal` frames 9-16, looped) until
    -- every one of the theft is down; then, after a short pause, all of them
    -- snap the fan shut together and go on as one: the 부적, the 결인, the
    -- flash, the throw and the 펑 (user design 2026-11-13).
    hold = { from = 9, to = 16, pause = 10 },
}
-- Cues a group plays once however many 전우치 vanish together.
local GROUP_CUES = { Throw = true, Pop = true }
-- The module draws the `Steal` frames itself, one an update, because the show
-- waits and loops: the engine's Sprite:SetFrame(name, frame) stops the
-- animation and IsFinished then reports it done (measured 2026-11-13: the
-- pedestals stood 12 updates after each arrival). So the events are read
-- from this table, the frames the anm2's Triggers name (tests compare them).
local EVENTS = { Land = 2, Snap = 18, Charm = 19, Flash = 26, Throw = 29, Pop = 34, Item = 38 }
local LAST = 63 -- the last frame of `Steal`

local SAVE_KEY = "jeonWoochi"
local DATA_KEY = "__ConchBlessingJeonWoochi"
local ANIM, IDLE = "Steal", "Wait"
local RNG_SHIFT = 35
-- Spot directions around the player, in degrees (0 = right, 90 = down): in
-- front of him first, then to the sides, then behind.
local ANGLES = { 60, 120, 0, 180, 30, 150, 90, 240, 300, 210, 330, 270 }
-- Sounds at the animation's events: (sound, volume, pitch). He comes and goes
-- the way Isaac teleports: measured with `cb test jeon_woochi
-- teleport_sound` (2026-11-13), Teleport!, Teleport 2.0 and Telepills all
-- play HELL_PORTAL2 as Isaac leaves and HELL_PORTAL1 as he arrives, then
-- SUMMON_POOF. Streak has no anm2 event: it plays when the show starts.
local CUES = {
    Streak = { "SOUND_HELL_PORTAL2", 0.7, 1.0 },
    Land = { "SOUND_HELL_PORTAL1", 0.7, 1.0 },
    Snap = { "SOUND_PAPER_OUT", 0.8, 1.35 },
    Charm = { "SOUND_PAPER_IN", 0.6, 1.1 },
    Throw = { "SOUND_FIRE_BURN", 0.45, 1.2 },
    Pop = { "SOUND_SUMMON_POOF", 0.9, 1.0 },
}

local started = false
local warned = false

local function itemId()
    local row = ConchBlessing.ItemData and ConchBlessing.ItemData.JEON_WOOCHI
    return row and row.id or -1
end

local function effectVariant()
    local entry = definitions.JEON_WOOCHI
    local ok, entityType, variant = pcall(function()
        return Isaac.GetEntityTypeByName(entry.name), Isaac.GetEntityVariantByName(entry.name)
    end)
    if ok and entityType == entry.id and type(variant) == "number" and variant > 0 then return variant end
    if itemId() > 0 then
        ConchBlessing.printError("Jeon Woo-chi: the effect '" .. entry.name
            .. "' is not registered; restart the game after entities2.xml changes")
    end
    return -1
end
local VARIANT = effectVariant()

-- REPENTOGON's transformation counter is what he reads.
local function capable(player)
    return type(player.GetPlayerFormCounter) == "function" and type(player.HasPlayerForm) == "function"
end

-- ------------------------------------------------------------------ choosing
--
-- Exactly the user's two rules (2026-11-13), nothing added. A set is a tagged
-- transformation (its collectibles) or one of Forms.SPECIAL (Adult and Stompy
-- also by pills, Necromancer one of each piece, Super Bum the three bums held
-- at once); the user asked for those too.
--  1. Among the player's transformations not yet complete, the ones with the
--     most progress, that is the least left to their threshold (threshold
--     minus counter); one of them entirely at random.
--  2. As many of its items as that leaves, entirely at random among its items.
-- A one-time pass over ItemConfig indexes every counting collectible (not
-- hidden, no quest item) by the transformations it counts toward, so a pickup
-- never walks the whole item list.

local index

-- The static index: each transformation's member collectibles, built on first use.
function M.index()
    if index then return index end
    local forms = Forms.list()
    local members = {}
    for i = 1, #forms do members[i] = {} end
    local config = Isaac.GetItemConfig()
    local collectibles = config and config:GetCollectibles()
    local last = collectibles and collectibles.Size - 1 or 0
    local quest = ItemConfig and ItemConfig.TAG_QUEST
    for id = 1, last do
        local item = config:GetCollectible(id)
        if item and not item.Hidden and type(item.HasTags) == "function" and not (quest and item:HasTags(quest)) then
            for i, f in ipairs(forms) do
                if item:HasTags(f.tag) then members[i][#members[i] + 1] = id end
            end
        end
    end
    local built = { forms = forms, members = members }
    if #forms > 0 then index = built end
    return built
end

-- Unlocks can change during a session, so availability is read per theft.
local function available(id, trinket)
    local config = Isaac.GetItemConfig()
    local item
    if trinket then item = config:GetTrinket(id) else item = config:GetCollectible(id) end
    if not item then return false end
    if type(item.IsAvailable) ~= "function" then return true end
    local ok, result = pcall(item.IsAvailable, item)
    return not ok or result ~= false
end

-- The pill color this run gives a pill effect, or nil when no pill has it.
local function pillColor(effect, player)
    local pool = Game():GetItemPool()
    for color = 1, 13 do
        local ok, found = pcall(pool.GetPillEffect, pool, color, player)
        if ok and found == effect then return color end
    end
    return nil
end

local function holds(player, piece)
    if piece.kind == "trinket" then return player:HasTrinket(piece.id) end
    return piece.kind == "collectible" and player:HasCollectible(piece.id, true)
end

-- A special set's progress and what can still fill it, from Forms.special:
-- (left, pieces) or nil when it is complete or nothing can fill it. A pill
-- is a piece only while this run's pills have its effect.
local function specialSet(player, set)
    local count, done
    if set.held then
        count = 0
        for _, piece in ipairs(set.supplies) do
            if holds(player, piece) then count = count + 1 end
        end
        done = count >= set.threshold
    else
        count, done = player:GetPlayerFormCounter(set.form), player:HasPlayerForm(set.form)
    end
    if done then return nil end
    local pieces = {}
    for _, piece in ipairs(set.supplies) do
        if piece.kind == "pill" then
            local color = pillColor(piece.id, player)
            if color then pieces[#pieces + 1] = { kind = "pill", id = color, effect = piece.id } end
        elseif available(piece.id, piece.kind == "trinket") and not (set.unique and holds(player, piece)) then
            pieces[#pieces + 1] = { kind = piece.kind, id = piece.id }
        end
    end
    local left = set.threshold - count
    if set.unique then left = math.min(left, #pieces) end
    if left <= 0 or #pieces == 0 then return nil end
    return left, pieces
end

-- Rule 1 on the unfinished transformations, each { left }: the ones with the
-- least left, and that number.
function M.closest(open)
    local least, list = math.huge, {}
    for _, o in ipairs(open) do
        if o.left < least then
            least, list = o.left, { o }
        elseif o.left == least then
            list[#list + 1] = o
        end
    end
    return list, least
end

-- Rule 2: `need` items of `set` at random, each item once while the set has
-- enough of them. rand(n) returns 1..n.
function M.chooseItems(set, need, rand)
    local picked, left = {}, {}
    for i, id in ipairs(set) do left[i] = id end
    while #picked < need and #left > 0 do picked[#picked + 1] = table.remove(left, rand(#left)) end
    while #picked < need and #set > 0 do picked[#picked + 1] = set[rand(#set)] end
    return picked
end

local function randomizer(rng)
    return function(n) return rng:RandomInt(n) + 1 end
end

-- The player's unfinished sets that something can still fill, each
-- { form, left, members }.
local function openSets(player)
    local idx = M.index()
    local open = {}
    for i, f in ipairs(idx.forms) do
        if not player:HasPlayerForm(f.form) then
            local left = Forms.threshold(f) - player:GetPlayerFormCounter(f.form)
            if left > 0 then
                local members = {}
                for _, id in ipairs(idx.members[i]) do
                    if available(id) then members[#members + 1] = { kind = "collectible", id = id } end
                end
                if #members > 0 then open[#open + 1] = { form = f, left = left, members = members } end
            end
        end
    end
    for _, set in ipairs(Forms.special()) do
        local left, pieces = specialSet(player, set)
        if left then open[#open + 1] = { form = set, left = left, members = pieces } end
    end
    return open
end

-- What a copy picked up by `player` steals: { form = key, left, items =
-- { { kind, id } } }, or nil when every set is complete. A piece is a
-- collectible, a trinket or a pill (by its color in this run).
function M.plan(player, rng)
    local open = openSets(player)
    if #open == 0 then return nil end
    local rand = randomizer(rng)
    local closest = M.closest(open)
    local target = closest[rand(#closest)]
    return { form = target.form.key, left = target.left, items = M.chooseItems(target.members, target.left, rand) }
end

-- How many items a copy picked up now would summon: whichever of the closest
-- sets he picks, it is what they have left, so EID can show it (user request
-- 2026-11-13); 0 with every set complete. EID asks every render frame, so the
-- answer is kept for the game frame.
local countCache = { frame = nil, key = nil, value = nil }
function M.summonCount(player)
    local frame = Game():GetFrameCount()
    local key = type(GetPtrHash) == "function" and GetPtrHash(player) or nil
    if key and countCache.key == key and countCache.frame == frame then return countCache.value end
    local open = openSets(player)
    local value = 0
    if #open > 0 then value = select(2, M.closest(open)) end
    countCache.frame, countCache.key, countCache.value = frame, key, value
    return value
end

-- ------------------------------------------------------------- the records

local function saveManager()
    local sm = ConchBlessing.SaveManager
    if type(sm) ~= "table" or type(sm.IsLoaded) ~= "function" then return nil end
    local ok, loaded = pcall(sm.IsLoaded)
    return ok and loaded == true and sm or nil
end

-- This room's thefts whose pedestal is not standing yet, keyed by name.
local function records(create)
    local sm = saveManager()
    if not sm then return nil end
    local getter = create and sm.GetRoomSave or sm.TryGetRoomSave
    if type(getter) ~= "function" then return nil end
    local ok, save = pcall(getter, nil, false)
    if not ok or type(save) ~= "table" then return nil end
    if create and type(save[SAVE_KEY]) ~= "table" then save[SAVE_KEY] = { serial = 0, pending = {} } end
    local entry = save[SAVE_KEY]
    if type(entry) ~= "table" then return nil end
    entry.pending = type(entry.pending) == "table" and entry.pending or {}
    return entry
end

local function flush()
    local sm = saveManager()
    if sm and type(sm.Save) == "function" then pcall(sm.Save) end
end

function M.pending()
    local entry = records(false)
    return entry and entry.pending or {}
end

-- ------------------------------------------------------------------ placing

local function occupied(spots, pos)
    for _, other in ipairs(spots) do
        if other:Distance(pos) < M.data.gap then return true end
    end
    for _, rec in pairs(M.pending()) do
        if Vector(rec.x, rec.y):Distance(pos) < M.data.gap then return true end
    end
    return false
end

-- Free spots for n pedestals around the player, apart from each other and
-- from thefts still on their way in this room.
function M.spots(player, n)
    local room = Game():GetRoom()
    local spots = {}
    for _, angle in ipairs(ANGLES) do
        if #spots >= n then break end
        local want = player.Position + Vector.FromAngle(angle) * M.data.distance
        local pos = room:FindFreePickupSpawnPosition(want, 0, true)
        if room:IsPositionInRoom(pos, 0) and pos:Distance(player.Position) >= M.data.nearest
            and not occupied(spots, pos) then
            spots[#spots + 1] = pos
        end
    end
    local step = 0
    while #spots < n do
        step = step + 1
        local pos = room:FindFreePickupSpawnPosition(player.Position, 40 * step, true)
        if step > 8 or not occupied(spots, pos) then spots[#spots + 1] = pos end
    end
    return spots
end

-- What a record places: a collectible (the default, for records saved
-- before pills and trinkets), a trinket or a pill of the recorded color.
local function variantOf(kind)
    if kind == "trinket" then return PickupVariant.PICKUP_TRINKET end
    if kind == "pill" then return PickupVariant.PICKUP_PILL end
    return PickupVariant.PICKUP_COLLECTIBLE
end

local function place(rec)
    local pickup = Game():Spawn(EntityType.ENTITY_PICKUP, variantOf(rec.kind), Vector(rec.x, rec.y), Vector.Zero, nil,
        rec.id, rec.seed)
    ConchBlessing.printDebug("[Jeon Woo-chi] placed %s %d at (%.0f, %.0f)", tostring(rec.kind or "collectible"),
        rec.id, rec.x, rec.y)
    return pickup
end

-- The pedestal of a theft stands: it leaves the room's records.
local function settle(key)
    local entry = records(false)
    if entry and entry.pending[key] then
        local rec = entry.pending[key]
        entry.pending[key] = nil
        flush()
        return rec
    end
    return nil
end

local function playCue(name)
    local cue = CUES[name]
    local id = cue and SoundEffect[cue[1]]
    if id then SFXManager():Play(id, Sound.volume(cue[2]), 0, false, cue[3]) end
end

local function spawnArrival(rec, key, wait, group)
    if VARIANT <= 0 then return nil end
    local effect = Isaac.Spawn(EntityType.ENTITY_EFFECT, VARIANT, 0, Vector(rec.x, rec.y), Vector.Zero, nil)
    effect = effect and effect:ToEffect()
    if not effect then return nil end
    -- drawn after a pedestal at the same height, so the smoke hides it
    effect.DepthOffset = 20
    -- the group is runtime only: the 전우치 of one theft, who vanish together
    local data = { key = key, rec = rec, wait = wait, group = group, frame = nil }
    effect:GetData()[DATA_KEY] = data
    local sprite = effect:GetSprite()
    sprite:Play(IDLE, true)
    if wait <= 0 then
        data.frame = 0
        sprite:SetFrame(ANIM, 0)
        playCue("Streak")
    end
    return effect
end

-- One theft for `player`: chooses, takes the items out of the pools, keeps a
-- record per item and sends 전우치 to each spot.
function M.steal(player)
    if not capable(player) then
        if not warned then
            warned = true
            ConchBlessing.printError("Jeon Woo-chi: REPENTOGON's transformation counter is missing")
        end
        return nil
    end
    local rng = player:GetCollectibleRNG(itemId())
    local theft = M.plan(player, rng)
    if not theft or #theft.items == 0 then return theft end
    local spots = M.spots(player, #theft.items)
    local entry = records(true)
    local group = { size = VARIANT > 0 and #theft.items or 0, landed = 0, release = nil, played = {} }
    for i, item in ipairs(theft.items) do
        local seed = rng:Next()
        local rec = { kind = item.kind, id = item.id, x = spots[i].X, y = spots[i].Y, seed = seed ~= 0 and seed or 1 }
        local key
        if entry then
            entry.serial = (tonumber(entry.serial) or 0) + 1
            key = "j" .. entry.serial
            entry.pending[key] = rec
        end
        spawnArrival(rec, key, (i - 1) * M.data.stagger, group)
    end
    flush()
    local names = {}
    for _, item in ipairs(theft.items) do names[#names + 1] = item.kind .. ":" .. item.id end
    ConchBlessing.printDebug("[Jeon Woo-chi] player %d steals for %s (%s left): %s", player.ControllerIndex,
        tostring(theft.form), tostring(theft.left), table.concat(names, ","))
    return theft
end

-- ---------------------------------------------------------------- callbacks

function M.onAddCollectible(_, collectible, _, firstTime, _, _, player)
    if collectible ~= itemId() or not firstTime or not player then return end
    M.steal(player)
end

function M.onEffectUpdate(_, effect)
    local data = effect:GetData()[DATA_KEY]
    if not data then
        effect:Remove()         -- a leftover without its theft (after a reload)
        return
    end
    local sprite = effect:GetSprite()
    if not data.frame then
        data.wait = data.wait - 1
        if data.wait <= 0 then
            data.frame = 0
            sprite:SetFrame(ANIM, 0)
            playCue("Streak")
        end
        return
    end
    local frame = data.frame + 1
    local group = data.group
    if group and not data.released then
        local now = Game():GetFrameCount()
        if frame >= M.data.hold.from and not data.landed then
            data.landed = true
            group.landed = group.landed + 1
            -- the last one down: after a short pause all go on from the same
            -- update, whatever order the effects update in
            if group.landed >= group.size then group.release = now + M.data.hold.pause end
        end
        if group.release and now >= group.release then
            data.released = true
            frame = M.data.hold.to + 1
        elseif frame > M.data.hold.to then
            frame = M.data.hold.from        -- fanning until then
        end
    end
    data.frame = frame
    sprite:SetFrame(ANIM, math.min(frame, LAST))
    for name, at in pairs(EVENTS) do
        if frame == at and CUES[name] and not (group and GROUP_CUES[name] and group.played[name]) then
            if group then group.played[name] = true end
            playCue(name)
        end
    end
    if not data.placed and frame >= EVENTS.Item then
        data.placed = true
        settle(data.key)
        place(data.rec)
    end
    if frame >= LAST then effect:Remove() end
end

-- Thefts left waiting in this room (the player left or quit during the show)
-- get their pedestals at once.
local function restore()
    local entry = records(false)
    if not entry then return end
    local keys = {}
    for key in pairs(entry.pending) do keys[#keys + 1] = key end
    if #keys == 0 then return end
    table.sort(keys)
    for _, key in ipairs(keys) do place(entry.pending[key]) end
    entry.pending = {}
    flush()
end

function M.onNewRoom()
    if started then restore() end
end

function M.onGameStarted()
    started = true
    restore()
end

function M.onGameExit()
    started = false
end

-- Before a reload or unload: every arrival on its way places its pedestal now.
function M.onModUnload(_, mod)
    if mod ~= nil and mod ~= ConchBlessing and mod ~= ConchBlessing.originalMod then return end
    if VARIANT <= 0 then return end
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_EFFECT, VARIANT)) do
        local data = entity:GetData()[DATA_KEY]
        if data and not data.placed then
            data.placed = true
            settle(data.key)
            place(data.rec)
        end
        entity:Remove()
    end
end

if type(ConchBlessing.AddCallback) == "function" and VARIANT > 0 then
    -- only his own effect, by variant
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE, M.onEffectUpdate, VARIANT)
end

-- After a `luamod` in the middle of a run there is no game start: the run is
-- going again once SaveManager reports its data loaded (POST_DATA_LOAD).
do
    local sm = ConchBlessing.SaveManager
    local mod = ConchBlessing.originalMod
    local callbacks = type(sm) == "table" and sm.SaveCallbacks
    if mod and callbacks and callbacks.POST_DATA_LOAD then
        mod:AddCallback(callbacks.POST_DATA_LOAD, function(_, _, isLuamod)
            if not isLuamod then return end
            started = true
            restore()
        end)
    end
end

-- EID: below his description, how many items he would summon now for the
-- player reading it (EID's own reader, the Item Reminder's player or the one
-- nearest the pedestal), above the REPENTOGON line.
local function describedPlayer(descObj)
    if type(EID) ~= "table" or type(EID.ClosestPlayerTo) ~= "function" then return nil end
    local ok, found = pcall(EID.ClosestPlayerTo, EID, descObj.Entity)
    return ok and found or nil
end

function M.describe(descObj)
    local player = describedPlayer(descObj)
    if not player or not capable(player) then return descObj end
    local ok, count = pcall(M.summonCount, player)
    if not ok or type(count) ~= "number" then return descObj end
    local line = ConchBlessing.Locale.text("ui.jeon_woochi.summon_count", tostring(count))
    local desc = descObj.Description or ""
    local at = desc:find("#{{Warning}}", 1, true)
    if at then
        descObj.Description = desc:sub(1, at - 1) .. line .. desc:sub(at)
    else
        descObj.Description = desc .. line
    end
    return descObj
end

if type(EID) == "table" and type(EID.addDescriptionModifier) == "function" then
    EID:addDescriptionModifier("ConchBlessing_JeonWoochiSummonCount", function(descObj)
        return descObj.ObjType == EntityType.ENTITY_PICKUP and descObj.ObjVariant == PickupVariant.PICKUP_COLLECTIBLE
            and descObj.ObjSubType == itemId() and itemId() > 0
    end, M.describe)
end

ConchBlessing.jeonwoochi._test = {
    variant = function() return VARIANT end,
    itemId = itemId,
    capable = capable,
    data = DATA_KEY,
}

return M
