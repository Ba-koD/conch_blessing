local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- `conch_test kronos characters`: a fresh run as every selectable character,
-- with Kronos on characters that do not attack the ordinary way (Lilith's
-- Incubus, Tainted Lilith's Gello, the Forgotten's club, Tainted Forgotten's
-- thrown body, Azazel's charged beam, two bodies, ...) and with every kind of
-- absorbed ability, not only Brother Bobby's fire rate (user request
-- 2026-11-07): copies that fire the character's own weapon (Incubus, Twisted
-- Pair), a fixed laser (Bloodshot Eye), a damage aura (Succubus), a prism
-- (Angelic Prism), an item conversion (Robo-Baby -> Technology) and a stat
-- (Brother Bobby -> fire rate).
--
-- Each run measures, on a pinned target and by the source of every hit:
--   1. the character alone (the control);
--   2. the same pets held as ordinary familiars (what each real pet does for
--      this character);
--   3. Kronos holding them: every pet taken for +2, each absorbed ability hurts
--      the target wherever the real pet did, the conversion and the stat land;
--   4. Kronos lost: every pet comes back, the +2s and the conversion go.
-- A character whose own attack or a pet that does not reach the target in
-- this setup is a SKIP for that check, never a pass.
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")
local Provenance = require("scripts.lib.damage_provenance")
local M = { commands = {} }

local CHARACTERS = {
    { "isaac", 0 }, { "magdalene", 1 }, { "cain", 2 }, { "judas", 3 }, { "blue_baby", 4 }, { "eve", 5 },
    { "samson", 6 }, { "azazel", 7 }, { "lazarus", 8 }, { "eden", 9 }, { "the_lost", 10 }, { "lilith", 13 },
    { "keeper", 14 }, { "apollyon", 15 }, { "the_forgotten", 16 }, { "bethany", 18 }, { "jacob_esau", 19 },
    { "t_isaac", 21 }, { "t_magdalene", 22 }, { "t_cain", 23 }, { "t_judas", 24 }, { "t_blue_baby", 25 },
    { "t_eve", 26 }, { "t_samson", 27 }, { "t_azazel", 28 }, { "t_lazarus", 29 }, { "t_eden", 30 },
    { "t_the_lost", 31 }, { "t_lilith", 32 }, { "t_keeper", 33 }, { "t_apollyon", 34 }, { "t_the_forgotten", 35 },
    { "t_bethany", 36 }, { "t_jacob", 37 },
}
local TARGET_DISTANCE = 45 -- inside the Forgotten's club reach

-- The pets, each with the anchor Kronos keeps for its absorbed ability.
local function petList()
    local C, F = CollectibleType, FamiliarVariant
    return {
        { name = "Brother Bobby", item = C.COLLECTIBLE_BROTHER_BOBBY, variant = F.BROTHER_BOBBY },
        { name = "Incubus", item = C.COLLECTIBLE_INCUBUS, variant = F.INCUBUS, anchor = "__kronosIncubus" },
        { name = "Twisted Pair", item = C.COLLECTIBLE_TWISTED_PAIR, variant = F.TWISTED_BABY, anchor = "__kronosTwistedPair" },
        { name = "Bloodshot Eye", item = C.COLLECTIBLE_BLOODSHOT_EYE, variant = F.BLOODSHOT_EYE, anchor = "__kronosBloodshotEye" },
        { name = "Succubus", item = C.COLLECTIBLE_SUCCUBUS, variant = F.SUCCUBUS, anchor = "__kronosSuccubus" },
        { name = "Angelic Prism", item = C.COLLECTIBLE_ANGELIC_PRISM, variant = F.ANGELIC_PRISM, anchor = "__kronosAngelicPrism" },
        { name = "Robo-Baby", item = C.COLLECTIBLE_ROBO_BABY, variant = F.ROBO_BABY },
    }
end
local ANCHOR_KEYS = { "__kronosTwistedPair", "__kronosIncubus", "__kronosSuccubus", "__kronosCenser",
    "__kronosStarOfBethlehem", "__kronosBloodshotEye", "__kronosAngelicPrism", "__kronosMongoMinisaac" }

-- Bench-owned state: whether players shoot, the pinned target, and the hits.
local shooting = false
local pin = nil
local hits = nil -- { [category] = { hp, n } } while a window is open

ConchBlessing:AddCallback(ModCallbacks.MC_INPUT_ACTION, function(_, entity, hook, action)
    if not shooting or action ~= ButtonAction.ACTION_SHOOTRIGHT then return end
    if not (entity and entity:ToPlayer()) then return end
    if hook == InputHook.GET_ACTION_VALUE then return 1 end
    return true
end)

ConchBlessing:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    if not pin then return end
    local npc = pin.npc
    if npc and npc:Exists() then
        npc.Position = pin.pos
        npc.Velocity = Vector.Zero
    end
end)

local function anchorKey(familiar)
    local data = familiar:GetData()
    for _, key in ipairs(ANCHOR_KEYS) do
        if data[key] then return key end
    end
end

-- Who a hit came from: a Kronos anchor, a real pet, or a player (the
-- character's own weapon, Technology, an Angelic Prism split).
local function category(entity)
    for _ = 1, 5 do
        if not entity then break end
        local familiar = entity:ToFamiliar()
        if familiar then
            local key = anchorKey(familiar)
            return key and ("anchor:" .. key) or ("pet:" .. familiar.Variant)
        end
        if entity:ToPlayer() then return "player" end
        entity = entity.SpawnerEntity or entity.Parent
    end
    return "other"
end

local function onHit(entity, amount, source, extraSource)
    if not (hits and pin and pin.npc and GetPtrHash(entity) == GetPtrHash(pin.npc)) or amount <= 0 then return end
    local from = category(Provenance.getSourceEntity(source, extraSource))
    local row = hits[from] or { hp = 0, n = 0 }
    row.hp, row.n = row.hp + amount, row.n + 1
    hits[from] = row
end

-- Attacks fired during a window, by who fired them: tells "never fired" from
-- "fired and missed".
local fired = nil
local function onFired(entity)
    if not fired or not entity then return end
    local from = category(entity.SpawnerEntity or entity.Parent)
    fired[from] = (fired[from] or 0) + 1
end
for _, name in ipairs({ "MC_POST_TEAR_INIT", "MC_POST_LASER_INIT", "MC_POST_KNIFE_INIT" }) do
    if ModCallbacks[name] then ConchBlessing:AddCallback(ModCallbacks[name], function(_, entity) onFired(entity) end) end
end

if ModCallbacks.MC_POST_ENTITY_TAKE_DMG then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_ENTITY_TAKE_DMG, function(_, entity, amount, _, source, _, extraSource)
        onHit(entity, amount, source, extraSource)
    end)
end

-- How the target went, if it does (killed, or removed with its room): the
-- last hit it took and the frame, for the readiness checks' detail.
local function isTarget(entity)
    return pin and pin.npc and entity and GetPtrHash(entity) == GetPtrHash(pin.npc)
end
local function watch(callback, fn)
    if callback then ConchBlessing:AddCallback(callback, fn) end
end
watch(ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, entity, amount, flags, source)
    if not isTarget(entity) then return end
    local e = source and source.Entity
    pin.lastHit = string.format("%.1f from %s (%s) flags %s at frame %d", amount,
        e and string.format("%d.%d.%d", e.Type, e.Variant, e.SubType) or tostring(source and source.Type),
        e and e.SpawnerEntity and string.format("spawner %d.%d", e.SpawnerEntity.Type, e.SpawnerEntity.Variant) or "no spawner",
        tostring(flags), Game():GetFrameCount())
end)
watch(ModCallbacks.MC_POST_ENTITY_KILL, function(_, entity)
    if not isTarget(entity) or pin.death then return end
    pin.death = string.format("killed at frame %d with hp %.0f; last hit %s", Game():GetFrameCount(), entity.HitPoints,
        tostring(pin.lastHit))
end)
watch(ModCallbacks.MC_POST_ENTITY_REMOVE, function(_, entity)
    if not isTarget(entity) or pin.death then return end
    local near = {}
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        if GetPtrHash(e) ~= GetPtrHash(entity) and e.Position:Distance(entity.Position) < 40 and e.Type ~= EntityType.ENTITY_EFFECT then
            near[#near + 1] = string.format("%d.%d.%d", e.Type, e.Variant, e.SubType)
        end
    end
    pin.death = string.format("removed at frame %d with hp %.0f, dead=%s; near [%s]; last hit %s", Game():GetFrameCount(),
        entity.HitPoints, tostring(entity:IsDead()), table.concat(near, ","), tostring(pin.lastHit))
end)

local function kronosId() return ConchBlessing.ItemData.KRONOS.id end

local function players()
    local list = {}
    for i = 0, Game():GetNumPlayers() - 1 do
        local p = Game():GetPlayer(i)
        if p and p:Exists() then list[#list + 1] = p end
    end
    return list
end

-- Visible pets of every player in the run, by variant.
local function pets()
    local mine = {}
    for _, p in ipairs(players()) do mine[GetPtrHash(p)] = true end
    local counts = {}
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local f = entity:ToFamiliar()
        if f and f:Exists() and f.Player and mine[GetPtrHash(f.Player)] and not anchorKey(f) then
            counts[f.Variant] = (counts[f.Variant] or 0) + 1
        end
    end
    return counts
end

local function anchors()
    local counts = {}
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local f = entity:ToFamiliar()
        local key = f and f:Exists() and anchorKey(f)
        if key then counts[key] = (counts[key] or 0) + 1 end
    end
    return counts
end

-- Hidden: the engine hides the entity, or its body sheet is the null image
-- (REPENTOGON's layer path). nil when neither can be read.
local function looksHidden(f)
    if f.Visible == false then return true end
    local sprite = f:GetSprite()
    local layer = type(sprite.GetLayer) == "function" and sprite:GetLayer(0)
    if layer and type(layer.GetSpritesheetPath) == "function" then
        local path = tostring(layer:GetSpritesheetPath() or "")
        return path:lower():find("null", 1, true) ~= nil
    end
    return nil
end

-- Every Kronos anchor: its kind, its owner, how far from the owner, hidden.
local function anchorRows()
    local rows = {}
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local f = entity:ToFamiliar()
        local key = f and f:Exists() and anchorKey(f)
        if key then
            local owner = f.Player
            rows[#rows + 1] = { key = key, owner = owner, hidden = looksHidden(f),
                distance = owner and owner.Position:Distance(f.Position) or -1,
                ownerType = owner and owner:GetPlayerType() or -1 }
        end
    end
    return rows
end

local function countText(counts)
    local rows = {}
    for key, n in pairs(counts) do rows[#rows + 1] = tostring(key) .. "x" .. n end
    table.sort(rows)
    return #rows > 0 and table.concat(rows, ",") or "none"
end

local function hitText(byFrom)
    local rows = {}
    for key, row in pairs(byFrom or {}) do rows[#rows + 1] = string.format("%s=%.1f/%d", key, row.hp, row.n) end
    table.sort(rows)
    return #rows > 0 and table.concat(rows, " ") or "no hits"
end

-- HP and hits from the given sources (all sources when none are given).
local function total(byFrom, sources)
    local hp, n = 0, 0
    for key, row in pairs(byFrom or {}) do
        if not sources or sources[key] then hp, n = hp + row.hp, n + row.n end
    end
    return hp, n
end

local function perHit(byFrom, sources)
    local hp, n = total(byFrom, sources)
    return n > 0 and hp / n or 0
end

local function hpFrom(byFrom, key) return byFrom and byFrom[key] and byFrom[key].hp or 0 end

-- Familiar collectibles the players hold, counted the way the engine counts
-- them (innate starting items included), minus Kronos's design blacklist.
local function heldFamiliarItems()
    local config, blacklist = Isaac.GetItemConfig(), ConchBlessing.kronos.data.blacklist or {}
    local count, rows = 0, {}
    local last = config:GetCollectibles().Size - 1
    for _, p in ipairs(players()) do
        for id = 1, last do
            local item = config:GetCollectible(id)
            local n = item and item.Type == ItemType.ITEM_FAMILIAR and not blacklist[id] and p:GetCollectibleNum(id, true) or 0
            if n > 0 then
                count = count + n
                rows[#rows + 1] = id .. "x" .. n
            end
        end
    end
    return count, table.concat(rows, ",")
end

local function kronosDamage()
    local sum = 0
    for _, p in ipairs(players()) do sum = sum + H.addition(p, "itemAdditions", kronosId(), "Damage") end
    return sum
end

-- Tainted Forgotten throws only a body the Soul is holding; each window logs
-- whether it does when the throw starts (REPENTOGON GetHeldEntity).
local READY_SLACK = 20
local function soulsAndBodies()
    local pairsFound = {}
    local soulType = PlayerType.PLAYER_THESOUL_B
    for _, p in ipairs(players()) do
        if soulType and p:GetPlayerType() == soulType then
            local body = type(p.GetOtherTwin) == "function" and p:GetOtherTwin() or nil
            if body then pairsFound[#pairsFound + 1] = { soul = p, body = body } end
        end
    end
    return pairsFound
end

local function holding(soul, body)
    if type(soul.GetHeldEntity) ~= "function" then return nil end
    local held = soul:GetHeldEntity()
    return held ~= nil and GetPtrHash(held) == GetPtrHash(body)
end

local function heldText()
    local rows = {}
    for _, pair in ipairs(soulsAndBodies()) do rows[#rows + 1] = "Soul holds its body=" .. tostring(holding(pair.soul, pair.body)) end
    return #rows > 0 and table.concat(rows, ", ") or nil
end

-- Shoot right at the pinned target in two bursts, letting go between them so
-- charged attacks (Azazel, the Forgotten's club, Tainted Forgotten) release.
local function attack(plan, field, label)
    -- Every body back at the start: a thrown Tainted Forgotten lies where it
    -- landed until the Soul picks it up again.
    plan.act(function(_, ctx)
        for _, p in ipairs(players()) do
            p.Position = ctx.home
            p.Velocity = Vector.Zero
        end
    end)
    plan.wait(20)
    -- Testable only from live state: the starting room, the target alive and
    -- pinned in place, every body at the start (user rule 2026-11-07).
    plan.require(label .. ": ready (room, target, bodies in place)", function(_, ctx)
        local problems = {}
        local room = Game():GetLevel():GetCurrentRoomIndex()
        if room ~= ctx.roomIndex then problems[#problems + 1] = string.format("room %d, not %d", room, ctx.roomIndex) end
        local t = ctx.target
        if not (t and t:Exists() and not t:IsDead()) then
            problems[#problems + 1] = "target " .. tostring(pin and pin.death or "gone")
        elseif t.Position:Distance(pin.pos) > READY_SLACK then
            problems[#problems + 1] = string.format("target %.0f from its place", t.Position:Distance(pin.pos))
        end
        for _, p in ipairs(players()) do
            local gap = p.Position:Distance(ctx.home)
            if gap > READY_SLACK then
                problems[#problems + 1] = string.format("type %d %.0f from the start", p:GetPlayerType(), gap)
            end
        end
        return #problems == 0, #problems == 0 and "in place" or table.concat(problems, "; ")
    end)
    plan.act(function(_, ctx)
        hits, fired = {}, {}
        ctx[field .. "Held"] = heldText()
        local t = ctx.target
        ctx[field .. "Target"] = t and string.format("target exists=%s dead=%s hp=%.0f coll=%s flags=%s pos=%.0f,%.0f vulnerable=%s%s; frame %d",
            tostring(t:Exists()), tostring(t:IsDead()), t.HitPoints, tostring(t.EntityCollisionClass),
            tostring(t:GetEntityFlags()), t.Position.X, t.Position.Y, tostring(t:IsVulnerableEnemy()),
            pin and pin.death and (" (" .. pin.death .. ")") or "", Game():GetFrameCount()) or "no target"
    end)
    for _ = 1, 2 do
        plan.act(function() shooting = true end)
        plan.wait(60)
        plan.act(function() shooting = false end)
        plan.wait(20)
    end
    plan.wait(10) -- the engine's HP buffer settles
    plan.act(function(_, ctx)
        ctx[field], hits = hits, nil
        ctx[field .. "Fired"], fired = fired, nil
        local rows = {}
        for _, p in ipairs(players()) do
            rows[#rows + 1] = string.format("type %d at %.0f,%.0f", p:GetPlayerType(), p.Position.X, p.Position.Y)
        end
        ctx[field .. "Players"] = table.concat(rows, "; ")
    end)
    plan.note(label .. ": HP the target lost, by source", function(_, ctx)
        local shots = {}
        for key, n in pairs(ctx[field .. "Fired"] or {}) do shots[#shots + 1] = key .. "x" .. n end
        table.sort(shots)
        return string.format("total %.1f (HP/hits): %s | fired %s | %s%s", total(ctx[field]), hitText(ctx[field]),
            #shots > 0 and table.concat(shots, ",") or "nothing", ctx[field .. "Players"],
            " | before: " .. tostring(ctx[field .. "Target"]) .. (ctx[field .. "Held"] and (", " .. ctx[field .. "Held"]) or ""))
    end)
    -- A window only counts in the starting room with its target: a body pushed
    -- through a door changes the room and takes the target with it, after which
    -- every attack hits nothing (Tainted Forgotten, 2026-11-07). That is a broken
    -- fixture, not a Kronos result, so it stops the case here.
    plan.require(label .. ": still in the starting room, with the target", function(_, ctx)
        local room = Game():GetLevel():GetCurrentRoomIndex()
        local t = ctx.target
        local alive = t ~= nil and t:Exists() and not t:IsDead()
        return room == ctx.roomIndex and alive, string.format("room %d (start %d); target %s", room, ctx.roomIndex,
            alive and "alive" or tostring(pin and pin.death or "gone"))
    end)
end

local function characterCase(plan, character)
    local name, playerType = character[1], character[2]
    plan.section("KRONOS / " .. name)
    plan.waitUntil(function(player)
        return player:Exists() and ConchBlessing.SaveManager.GetRunSave(player) ~= nil
    end, 60, "player and run save ready")
    plan.require("a fresh run as " .. name, function(player)
        return player:GetPlayerType() == playerType, "player type=" .. player:GetPlayerType()
    end)
    plan.require("hit sources (REPENTOGON MC_POST_ENTITY_TAKE_DMG)", function()
        return ModCallbacks.MC_POST_ENTITY_TAKE_DMG ~= nil or nil, "REPENTOGON required"
    end)
    plan.act(function(player, ctx)
        ctx.pets = petList()
        local room = Game():GetRoom()
        ctx.home = room:GetCenterPos() - Vector(60, 0)
        for _, p in ipairs(players()) do p.Position = ctx.home end
        -- Shut the doors (the room counts as uncleared while the target lives),
        -- so nothing knocked across the room can walk out through one.
        ctx.roomIndex = Game():GetLevel():GetCurrentRoomIndex()
        room:SetClear(false)
        for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
            local door = room:GetDoor(slot)
            if door then door:Close(true) end
        end
        local npc = H.target(player, true)
        ctx.target = npc
        pin = { npc = npc, pos = ctx.home + Vector(TARGET_DISTANCE, 0) }
        ctx.cleanupFns = ctx.cleanupFns or {}
        ctx.cleanupFns[#ctx.cleanupFns + 1] = function()
            shooting, pin, hits = false, nil, nil
            if npc:Exists() then npc:Remove() end
        end
    end)
    plan.waitUntil(function(_, ctx) return H.targetReady(ctx.target) end, 60, "the target is ready")
    plan.wait(15)
    attack(plan, "control", "the character alone")
    -- The character's own attack: whatever hurt the target with no test pet
    -- (its weapon, Lilith's Incubus, Tainted Lilith's Gello).
    plan.act(function(_, ctx)
        ctx.own = {}
        for key in pairs(ctx.control) do ctx.own[key] = true end
    end)

    plan.act(function(player, ctx)
        ctx.petsBefore = pets()
        for _, pet in ipairs(ctx.pets) do player:AddCollectible(pet.item, 0, false) end
    end)
    plan.wait(20)
    plan.act(function(player, ctx)
        ctx.petsHeld = pets()
        ctx.heldCount, ctx.heldText = heldFamiliarItems()
        ctx.fireDelayHeld = player.MaxFireDelay
        ctx.technologyBefore = player:GetCollectibleNum(CollectibleType.COLLECTIBLE_TECHNOLOGY, true)
    end)
    plan.note("pets before and with the test pets", function(_, ctx)
        return "innate " .. countText(ctx.petsBefore) .. " | held " .. countText(ctx.petsHeld)
            .. " | familiar items " .. ctx.heldText
    end)
    attack(plan, "real", "with the real pets")

    plan.act(function(player) player:AddCollectible(kronosId(), 0, false) end)
    plan.waitUntil(function(_, ctx)
        return kronosDamage() >= 2 * ctx.heldCount, "Kronos damage=" .. kronosDamage() .. " pets " .. countText(pets())
    end, 180, "Kronos takes the pets")
    plan.wait(20)
    plan.check("Kronos takes every familiar item held, each for +2 damage", function(_, ctx)
        return H.expect(kronosDamage(), 2 * ctx.heldCount)
    end)
    plan.check("every test pet is taken; innate pets stay", function(_, ctx)
        local now, wrong = pets(), {}
        for _, pet in ipairs(ctx.pets) do
            local left = (now[pet.variant] or 0) - (ctx.petsBefore[pet.variant] or 0)
            if left ~= 0 then wrong[#wrong + 1] = pet.name .. " " .. left end
        end
        return #wrong == 0, "pets " .. countText(now) .. " (innate " .. countText(ctx.petsBefore) .. ")"
            .. (#wrong > 0 and "; left " .. table.concat(wrong, ",") or "")
    end)
    plan.check("each absorbed ability has its anchor", function(_, ctx)
        local now, missing = anchors(), {}
        for _, pet in ipairs(ctx.pets) do
            if pet.anchor and (now[pet.anchor] or 0) < 1 then missing[#missing + 1] = pet.name end
        end
        return #missing == 0, "anchors " .. countText(now) .. (#missing > 0 and "; missing " .. table.concat(missing, ",") or "")
    end)
    plan.note("the invisible pets Kronos keeps: kind, owner, distance, hidden", function()
        local text = {}
        for _, row in ipairs(anchorRows()) do
            text[#text + 1] = string.format("%s owner=%d d=%.1f hidden=%s", row.key:gsub("__kronos", ""), row.ownerType,
                row.distance, tostring(row.hidden))
        end
        return #text > 0 and table.concat(text, "; ") or "none"
    end)
    plan.check("the invisible pets cannot be seen", function()
        local shown, unknown = {}, 0
        for _, row in ipairs(anchorRows()) do
            if row.hidden == false and row.key ~= "__kronosSuccubus" and row.key ~= "__kronosCenser"
                and row.key ~= "__kronosStarOfBethlehem" then
                shown[#shown + 1] = row.key
            elseif row.hidden == nil then
                unknown = unknown + 1
            end
        end
        if #shown == 0 and unknown > 0 then return nil, unknown .. " anchors could not be read" end
        return #shown == 0, #shown == 0 and "every body hidden (aura pets keep their aura)" or "visible: " .. table.concat(shown, ",")
    end)
    -- The Incubus sits on its owner; the Twisted Pair beside it, across the aim.
    plan.check("the invisible Incubus and Twisted Pair sit on a player of this run", function()
        local mine, wrong = {}, {}
        for _, p in ipairs(players()) do mine[GetPtrHash(p)] = true end
        for _, row in ipairs(anchorRows()) do
            if row.key == "__kronosIncubus" or row.key == "__kronosTwistedPair" then
                local reach = row.key == "__kronosIncubus" and 8 or 20
                if not (row.owner and mine[GetPtrHash(row.owner)]) or row.distance > reach then
                    wrong[#wrong + 1] = string.format("%s d=%.1f", row.key, row.distance)
                end
            end
        end
        return #wrong == 0, #wrong == 0 and "on their owner" or table.concat(wrong, ", ")
    end)
    plan.check("Robo-Baby becomes Technology", function(player, ctx)
        local n = player:GetCollectibleNum(CollectibleType.COLLECTIBLE_TECHNOLOGY, true)
        return n == ctx.technologyBefore + 1, "Technology " .. ctx.technologyBefore .. " -> " .. n
    end)
    plan.check("Brother Bobby's fire rate lands", function(player, ctx)
        return player.MaxFireDelay < ctx.fireDelayHeld,
            string.format("MaxFireDelay %.2f with the real pets, %.2f with Kronos", ctx.fireDelayHeld, player.MaxFireDelay)
    end)
    plan.check("the character keeps its body and form", function(player)
        local ok = player:GetPlayerType() == playerType and Game():GetNumPlayers() >= 1
        return ok, "type=" .. player:GetPlayerType() .. " players=" .. Game():GetNumPlayers()
    end)
    attack(plan, "kronos", "with Kronos")
    -- +2 damage per pet: each hit of the character's own attack lands harder.
    -- Per hit, because how many swings or throws land depends on charge speed.
    plan.check("with Kronos each hit of the character's own attack is stronger", function(_, ctx)
        local alone, with = perHit(ctx.control, ctx.own), perHit(ctx.kronos, ctx.own)
        if alone <= 0 then return nil, "the character's own attack did not reach the target in this setup" end
        if with <= 0 then return false, "the character's own attack no longer reached the target" end
        return with > alone, string.format("per hit with Kronos %.2f, alone %.2f", with, alone)
    end)
    -- Each absorbed attack hurts the target wherever the real pet did.
    for _, petName in ipairs({ "Incubus", "Twisted Pair", "Bloodshot Eye", "Succubus" }) do
        plan.check("the absorbed " .. petName .. " attacks like the real one", function(_, ctx)
            local pet
            for _, p in ipairs(ctx.pets) do if p.name == petName then pet = p end end
            local real = hpFrom(ctx.real, "pet:" .. tostring(pet.variant))
            local absorbed = hpFrom(ctx.kronos, "anchor:" .. pet.anchor)
            if real <= 0 then return nil, "the real " .. petName .. " did not hurt the target for this character" end
            return absorbed > 0, string.format("real %.1f, absorbed %.1f", real, absorbed)
        end)
    end

    plan.act(function(player) player:RemoveCollectible(kronosId()) end)
    plan.waitUntil(function(_, ctx)
        local now = pets()
        for variant, n in pairs(ctx.petsHeld) do
            if (now[variant] or 0) < n then return false, "pets " .. countText(now) end
        end
        return kronosDamage() == 0, "Kronos damage=" .. kronosDamage()
    end, 180, "losing Kronos gives the pets back")
    plan.wait(20)
    -- The test pets only: a character's own pets (Tainted Eve's clots) come and go.
    plan.check("every pet comes back, the +2s go, no anchor stays", function(_, ctx)
        local now, wrong = pets(), {}
        for _, pet in ipairs(ctx.pets) do
            if (now[pet.variant] or 0) ~= (ctx.petsHeld[pet.variant] or 0) then
                wrong[#wrong + 1] = pet.name .. " " .. (now[pet.variant] or 0) .. "/" .. (ctx.petsHeld[pet.variant] or 0)
            end
        end
        return #wrong == 0 and kronosDamage() == 0 and next(anchors()) == nil,
            "pets " .. countText(now) .. (#wrong > 0 and "; differ " .. table.concat(wrong, ",") or "")
            .. "; Kronos damage " .. kronosDamage() .. "; anchors " .. countText(anchors())
    end)
    plan.check("Technology goes with Robo-Baby's return", function(player, ctx)
        local n = player:GetCollectibleNum(CollectibleType.COLLECTIBLE_TECHNOLOGY, true)
        return n == ctx.technologyBefore, "Technology " .. n .. "; before Kronos " .. ctx.technologyBefore
    end)
    attack(plan, "after", "after losing Kronos")
    plan.check("after losing Kronos the attack still works", function(_, ctx)
        local alone, after = total(ctx.control, ctx.own), total(ctx.after, ctx.own)
        if alone <= 0 then return nil, "the character's own attack did not reach the target in this setup" end
        return after > 0, string.format("after %.1f, alone %.1f", after, alone)
    end)
    plan.act(function(_, ctx)
        shooting, pin, hits = false, nil, nil
        if ctx.target:Exists() then ctx.target:Remove() end
    end)
end
M._category = category

for _, character in ipairs(CHARACTERS) do
    local name = "character_" .. character[1]
    local command = "conch_test kronos " .. name
    S.rows[#S.rows + 1] = { key = "KRONOS", name = name, command = command, groups = { characters = true },
        build = function(plan) characterCase(plan, character) end }
    require("scripts.dev.test_bench").register({ command = command, tag = "ItemTest:KRONOS",
        duration = "a fresh run as one character", restartCommand = "restart " .. character[2],
        finalRestartCommand = "restart 0",
        resetReason = "every character needs its own fresh run", cleanup = function(ctx)
            shooting, pin, hits = false, nil, nil
            return H.cleanup(ctx)
        end,
        build = function(plan) characterCase(plan, character) end })
    M.commands[#M.commands + 1] = command
end

return M
