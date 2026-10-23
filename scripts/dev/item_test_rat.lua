local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 자 (Rat): the lifecycle contract and its isolated cases. Every case starts
-- from a clean run and checks real players: the fake's character, controller,
-- Parent, copied passives and health, its fall, the next floor's new fake,
-- and the engine's own revive and helper-pickup rules for it.
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")
local C = {}

local function rat() return ConchBlessing.rat end

local function requireApi(plan)
    plan.require("REPENTOGON co-player API available", function()
        local ok, detail = rat().supported()
        return ok or nil, detail
    end)
end

local function removeFakesOnCleanup(ctx)
    ctx.cleanupFns = ctx.cleanupFns or {}
    table.insert(ctx.cleanupFns, function() rat().removeAll("test cleanup") end)
end

local function helpers()
    local list = {}
    for i = 0, Game():GetNumPlayers() - 1 do
        local p = Game():GetPlayer(i)
        if p and p:Exists() and p.Parent ~= nil then list[#list + 1] = p end
    end
    return list
end

local function isActive(id)
    local config = Isaac.GetItemConfig():GetCollectible(id)
    return config ~= nil and config.Type == ItemType.ITEM_ACTIVE
end

-- The holder's passives a fake should carry: everything real and non-active but Rat.
local function passiveCounts(player)
    local counts = {}
    for id, n in pairs(player:GetCollectiblesList()) do
        id, n = tonumber(id), tonumber(n) or 0
        if id and n > 0 and id ~= ConchBlessing.ItemData.RAT.id and not isActive(id) then counts[id] = n end
    end
    return counts
end

local function sameCounts(actual, expected)
    for id, n in pairs(expected) do
        if (actual[id] or 0) ~= n then return false, string.format("collectible %d: %d, want %d", id, actual[id] or 0, n) end
    end
    for id, n in pairs(actual) do
        if not expected[id] then return false, string.format("extra collectible %d x%d", id, n) end
    end
    return true, "same passives"
end

local function shared(player) return { player:GetNumCoins(), player:GetNumBombs(), player:GetNumKeys() } end

-- Every kind of heart, and the Forgotten's Soul's on the sub-player.
local healthOf
function healthOf(p)
    local text = string.format("max %d red %d soul %d black %d bone %d golden %d eternal %d rotten %d broken %d",
        p:GetMaxHearts(), p:GetHearts(), p:GetSoulHearts(), p:GetBlackHearts(), p:GetBoneHearts(),
        p:GetGoldenHearts(), p:GetEternalHearts(), p:GetRottenHearts(), p:GetBrokenHearts())
    local sub = type(p.GetSubPlayer) == "function" and p:GetSubPlayer() or nil
    if sub and GetPtrHash(sub) ~= GetPtrHash(p) then text = text .. " | sub " .. healthOf(sub) end
    return text
end

-- Everything one fake must be: the holder's character and controller, Parent
-- set to the holder, the expected passives only, the holder's health and nothing else.
local function checkFake(holder, fake, expected)
    if fake:GetPlayerType() ~= holder:GetPlayerType() then return false, "type " .. fake:GetPlayerType() end
    if fake.ControllerIndex ~= holder.ControllerIndex then
        return false, string.format("controller %d, holder %d", fake.ControllerIndex, holder.ControllerIndex)
    end
    if not fake.Parent or GetPtrHash(fake.Parent) ~= GetPtrHash(holder) then return false, "Parent is not the holder" end
    local sm = ConchBlessing.SaveManager
    if sm.Utility.GetSaveIndex(fake) == sm.Utility.GetSaveIndex(holder) then return false, "fake shares the holder's save" end
    for _, slot in ipairs({ ActiveSlot.SLOT_PRIMARY, ActiveSlot.SLOT_SECONDARY, ActiveSlot.SLOT_POCKET }) do
        if fake:GetActiveItem(slot) > 0 then return false, "active " .. fake:GetActiveItem(slot) .. " in slot " .. slot end
    end
    if fake:GetTrinket(0) > 0 then return false, "trinket " .. fake:GetTrinket(0) end
    if fake:GetCollectibleNum(ConchBlessing.ItemData.RAT.id) > 0 then return false, "fake carries Rat" end
    local same, detail = sameCounts(passiveCounts(fake), expected)
    if not same then return false, detail end
    if healthOf(fake) ~= healthOf(holder) then
        return false, "health [" .. healthOf(fake) .. "], holder [" .. healthOf(holder) .. "]"
    end
    return true, "type, controller, Parent, passives and the holder's health"
end

-- count nil: any fake at all (a twin character brings more than one).
local function waitFakes(plan, count, label)
    plan.waitUntil(function(player)
        local n = #rat().fakesOf(player)
        return (count == nil and n > 0) or n == count, "fakes " .. n
    end, 180, label or ("holder has " .. tostring(count) .. " fake(s)"))
end

local function reenterRoom(plan)
    plan.act(function(player, ctx)
        ctx.roomsBefore = ctx.rooms
        Game():StartRoomTransition(Game():GetLevel():GetCurrentRoomIndex(), Direction.NO_DIRECTION,
            RoomTransitionAnim.FADE, player)
    end)
    plan.waitUntil(function(_, ctx) return ctx.rooms > ctx.roomsBefore end, 180, "room re-entered")
    plan.wait(20)
end

-- ------------------------------------------------------------------ lifecycle
C.RAT = {
    prepare = function(plan)
        requireApi(plan)
        plan.act(function(player, ctx)
            removeFakesOnCleanup(ctx)
            player:AddCollectible(CollectibleType.COLLECTIBLE_SAD_ONION, 0, false)
            player:AddCollectible(CollectibleType.COLLECTIBLE_BROTHER_BOBBY, 0, false)
            ctx.ratShared = shared(player)
        end)
    end,
    stage = function(plan, _, n)
        waitFakes(plan, n)
        plan.check("one fake per copy and nobody else joined", function(player)
            local fakes = #rat().fakesOf(player)
            return fakes == n and #helpers() == n and Game():GetNumPlayers() == 1 + n,
                string.format("fakes %d, helpers %d, players %d", fakes, #helpers(), Game():GetNumPlayers())
        end)
        if n > 0 then
            plan.check("every fake is the holder's character with its passives and health", function(player)
                local expected = passiveCounts(player)
                for i, fake in ipairs(rat().fakesOf(player)) do
                    local ok, detail = checkFake(player, fake, expected)
                    if not ok then return false, "fake " .. i .. ": " .. detail end
                end
                return true, n .. " fake(s) checked"
            end)
        end
        plan.check("transforming brought no coins, bombs or keys", function(player, ctx)
            local now = shared(player)
            return now[1] == ctx.ratShared[1] and now[2] == ctx.ratShared[2] and now[3] == ctx.ratShared[3],
                string.format("coins/bombs/keys %d/%d/%d, want %d/%d/%d", now[1], now[2], now[3],
                    ctx.ratShared[1], ctx.ratShared[2], ctx.ratShared[3])
        end)
        plan.check("item loss is not a fall", function(player) return H.expect(rat().fallen(player), 0) end)
    end,
}

-- ------------------------------------------------------------------ cases
local function setup(plan, extra)
    requireApi(plan)
    plan.act(function(player, ctx)
        removeFakesOnCleanup(ctx)
        player:AddCollectible(CollectibleType.COLLECTIBLE_SAD_ONION, 0, false)
        for _, id in ipairs(extra or {}) do player:AddCollectible(id, 0, false) end
        player:AddCollectible(ConchBlessing.ItemData.RAT.id, 0, false)
    end)
    waitFakes(plan, 1, "the rat transforms")
    plan.act(function(player, ctx) ctx.fake = rat().fakesOf(player)[1] end)
end

local function killFake(plan, label)
    plan.act(function(_, ctx)
        ctx.fakeHash = GetPtrHash(ctx.fake)
        ctx.fake:Kill()
    end)
    -- Only this fake has to go; another copy's fake may stay.
    plan.waitUntil(function(player, ctx)
        for i = 0, Game():GetNumPlayers() - 1 do
            local p = Game():GetPlayer(i)
            if p and p:Exists() and GetPtrHash(p) == ctx.fakeHash then return false, "fake still present" end
        end
        for _, fake in ipairs(rat().fakesOf(player)) do
            if GetPtrHash(fake) == ctx.fakeHash then return false, "still listed as a fake" end
        end
        return true
    end, 300, label or "the fake falls and is gone")
    plan.note("how the fallen fake left", function()
        local last = rat()._test.lastRemoval()
        return last and (last.by .. "/" .. last.reason) or "unknown"
    end)
end

S.add("RAT", "fall", {}, function(plan)
    setup(plan)
    plan.section("RAT / fall", "a puff of smoke, then a small grey rat with a fingernail in its mouth runs off, away from Isaac, and fades")
    killFake(plan)
    plan.check("a rat runs off where the fake fell", function()
        return #rat()._test.runners() >= 1, "fleeing rats " .. #rat()._test.runners()
    end)
    plan.check("the fall counts for this floor and leaves no ghost", function(player)
        return rat().fallen(player) == 1 and Game():GetNumPlayers() == 1 and not player:IsDead(),
            string.format("fallen %d, players %d", rat().fallen(player), Game():GetNumPlayers())
    end)
    reenterRoom(plan)
    plan.check("no new fake on the same floor", function(player) return H.expect(#rat().fakesOf(player), 0) end)
    S.newFloor(plan, 2)
    waitFakes(plan, 1, "the rat transforms again on the next floor")
    plan.check("the next floor's fake is fresh", function(player)
        local fake = rat().fakesOf(player)[1]
        local ok, detail = checkFake(player, fake, passiveCounts(player))
        return ok and rat().fallen(player) == 0, detail .. "; fallen " .. rat().fallen(player)
    end)
end)

S.add("RAT", "snapshot", {}, function(plan)
    setup(plan)
    plan.act(function(player, ctx)
        ctx.snapshot = passiveCounts(ctx.fake)
        ctx.fakeHash = GetPtrHash(ctx.fake)
        player:AddCollectible(CollectibleType.COLLECTIBLE_SPOON_BENDER, 0, false)
        player:RemoveCollectible(CollectibleType.COLLECTIBLE_SAD_ONION)
    end)
    plan.wait(30)
    plan.check("later gains and losses do not reach the fake", function(_, ctx)
        return sameCounts(passiveCounts(ctx.fake), ctx.snapshot)
    end)
    S.newFloor(plan, 2)
    plan.wait(30)
    plan.check("a surviving fake keeps its snapshot on the next floor", function(player, ctx)
        local fakes = rat().fakesOf(player)
        if #fakes ~= 1 or GetPtrHash(fakes[1]) ~= ctx.fakeHash then return false, "fake replaced: " .. #fakes end
        return sameCounts(passiveCounts(fakes[1]), ctx.snapshot)
    end)
end)

S.add("RAT", "revive", {}, function(plan)
    setup(plan, { CollectibleType.COLLECTIBLE_1UP })
    plan.check("the fake carries the holder's 1UP", function(_, ctx)
        return H.expect(ctx.fake:GetCollectibleNum(CollectibleType.COLLECTIBLE_1UP), 1)
    end)
    plan.act(function(_, ctx) ctx.fakeHash = GetPtrHash(ctx.fake); ctx.fake:Kill() end)
    plan.waitUntil(function(_, ctx)
        local fake = ctx.fake
        return fake:Exists() and not fake:IsDead() and fake:GetCollectibleNum(CollectibleType.COLLECTIBLE_1UP) == 0
    end, 300, "the engine revives the fake with its 1UP")
    plan.check("a revive is not a fall", function(player, ctx)
        local fakes = rat().fakesOf(player)
        return #fakes == 1 and GetPtrHash(fakes[1]) == ctx.fakeHash and rat().fallen(player) == 0,
            "fakes " .. #fakes .. ", fallen " .. rat().fallen(player)
    end)
    plan.wait(60)
    killFake(plan, "without a revive left the fake falls")
    plan.check("the second death is the fall", function(player) return H.expect(rat().fallen(player), 1) end)
end)

S.add("RAT", "holder_revive", {}, function(plan)
    setup(plan, { CollectibleType.COLLECTIBLE_1UP })
    plan.act(function(player, ctx)
        ctx.fakeHash = GetPtrHash(ctx.fake)
        ctx.expectedDeathFrames = 400
        player:Kill()
    end)
    plan.waitUntil(function(player)
        return not player:IsDead() and player:GetCollectibleNum(CollectibleType.COLLECTIBLE_1UP) == 0
    end, 400, "the holder revives with 1UP")
    plan.act(function(_, ctx) ctx.expectedDeathFrames = nil end)
    plan.wait(30)
    plan.check("a holder who revives keeps the fake", function(player, ctx)
        local fakes = rat().fakesOf(player)
        return #fakes == 1 and GetPtrHash(fakes[1]) == ctx.fakeHash and rat().fallen(player) == 0,
            "fakes " .. #fakes .. ", fallen " .. rat().fallen(player)
    end)
end)

S.add("RAT", "copy_changes", {}, function(plan)
    setup(plan)
    plan.act(function(player) player:AddCollectible(ConchBlessing.ItemData.RAT.id, 0, false) end)
    waitFakes(plan, 2, "a second copy brings a second fake")
    plan.act(function(player, ctx) ctx.fake = rat().fakesOf(player)[1]; ctx.keep = GetPtrHash(rat().fakesOf(player)[2]) end)
    killFake(plan, "one of two fakes falls")
    plan.wait(10)
    plan.check("the other fake stays", function(player, ctx)
        local fakes = rat().fakesOf(player)
        return #fakes == 1 and GetPtrHash(fakes[1]) == ctx.keep and rat().fallen(player) == 1,
            "fakes " .. #fakes .. ", fallen " .. rat().fallen(player)
    end)
    plan.act(function(player) player:RemoveCollectible(ConchBlessing.ItemData.RAT.id) end)
    plan.wait(10)
    plan.check("losing a copy takes the fallen place first", function(player, ctx)
        local fakes = rat().fakesOf(player)
        return #fakes == 1 and GetPtrHash(fakes[1]) == ctx.keep and rat().fallen(player) == 0,
            "fakes " .. #fakes .. ", fallen " .. rat().fallen(player)
    end)
    plan.act(function(player) player:AddCollectible(ConchBlessing.ItemData.RAT.id, 0, false) end)
    waitFakes(plan, 2, "a newly gained copy's rat transforms at once")
end)

-- What the engine lets a Parent helper pick up: cards, pills and trinkets stay
-- on the floor (Epiphany's First Page relies on the same rule). Hearts and
-- passive pedestals are recorded only.
S.add("RAT", "helper_pickups", {}, function(plan)
    setup(plan)
    plan.act(function(player, ctx)
        local room = Game():GetRoom()
        player.Position = room:GetCenterPos() + Vector(-120, 0)
        player.Velocity = Vector.Zero
        ctx.fake.Position = room:GetCenterPos() + Vector(120, 0)
        ctx.fake.Velocity = Vector.Zero
        local at = ctx.fake.Position
        ctx.floor = {}
        for _, row in ipairs({
            { "card", PickupVariant.PICKUP_TAROTCARD, Card.CARD_FOOL },
            { "pill", PickupVariant.PICKUP_PILL, PillColor.PILL_BLUE_BLUE },
            { "trinket", PickupVariant.PICKUP_TRINKET, TrinketType.TRINKET_SWALLOWED_PENNY },
            { "heart", PickupVariant.PICKUP_HEART, HeartSubType.HEART_SOUL },
        }) do
            local pickup = Isaac.Spawn(EntityType.ENTITY_PICKUP, row[2], row[3], at, Vector.Zero, nil)
            ctx.floor[row[1]] = pickup
            pickup:ToPickup().Wait = 0
        end
    end)
    plan.wait(45)
    plan.check("cards, pills and trinkets stay on the floor", function(_, ctx)
        for _, kind in ipairs({ "card", "pill", "trinket" }) do
            if not ctx.floor[kind]:Exists() then return false, kind .. " was taken" end
        end
        return ctx.fake:GetCard(0) == 0 and ctx.fake:GetPill(0) == 0 and ctx.fake:GetTrinket(0) == 0,
            "none in the fake's pockets"
    end)
    plan.note("soul heart touched by the fake", function(_, ctx)
        return ctx.floor.heart:Exists() and "left on the floor" or ("taken; fake soul hearts " .. ctx.fake:GetSoulHearts())
    end)
    plan.act(function(_, ctx)
        for _, pickup in pairs(ctx.floor) do if pickup:Exists() then pickup:Remove() end end
    end)
end)

-- ------------------------------------------------------------------ same character
-- `conch_test rat characters`: a fresh run as every selectable character, then
-- each fake against its original. Nobody's health is touched: the fake must
-- already have exactly the original's hearts, and the original's own health
-- must be what it was before the rat. Actives, trinkets and pocket items stay
-- out of the comparison because the design does not copy them. Everything
-- else must match.
local CHARACTERS = {
    { "isaac", 0 }, { "magdalene", 1 }, { "cain", 2 }, { "judas", 3 }, { "blue_baby", 4 }, { "eve", 5 },
    { "samson", 6 }, { "azazel", 7 }, { "lazarus", 8 }, { "eden", 9 }, { "the_lost", 10 }, { "lilith", 13 },
    { "keeper", 14 }, { "apollyon", 15 }, { "the_forgotten", 16 }, { "bethany", 18 }, { "jacob_esau", 19 },
    { "t_isaac", 21 }, { "t_magdalene", 22 }, { "t_cain", 23 }, { "t_judas", 24 }, { "t_blue_baby", 25 },
    { "t_eve", 26 }, { "t_samson", 27 }, { "t_azazel", 28 }, { "t_lazarus", 29 }, { "t_eden", 30 },
    { "t_the_lost", 31 }, { "t_lilith", 32 }, { "t_keeper", 33 }, { "t_apollyon", 34 }, { "t_the_forgotten", 35 },
    { "t_bethany", 36 }, { "t_jacob", 37 },
}
local STATS = { "Damage", "MaxFireDelay", "MoveSpeed", "TearRange", "ShotSpeed", "Luck" }
local EDEN = { "Damage", "FireDelay", "Luck", "Range", "ShotSpeed", "Speed" }

local function originals()
    local list = {}
    for i = 0, Game():GetNumPlayers() - 1 do
        local p = Game():GetPlayer(i)
        if p and p:Exists() and not rat().isFake(p) then list[#list + 1] = p end
    end
    return list
end

-- Each fake with the original of the same character (Jacob with Jacob, Esau with Esau).
local function pairsOf(holder)
    local result = {}
    for _, fake in ipairs(rat().fakesOf(holder)) do
        local match
        for _, p in ipairs(originals()) do
            if p:GetPlayerType() == fake:GetPlayerType() then match = p; break end
        end
        result[#result + 1] = { original = match, fake = fake }
    end
    return result
end

local function look(p)
    local sprite = p:GetSprite()
    local parts = { tostring(sprite:GetFilename()), "body " .. tostring(p:GetBodyColor()), "head " .. tostring(p:GetHeadColor()) }
    if type(sprite.GetLayerCount) == "function" and type(sprite.GetLayer) == "function" then
        for i = 0, sprite:GetLayerCount() - 1 do
            local layer = sprite:GetLayer(i)
            parts[#parts + 1] = i .. "=" .. tostring(layer and type(layer.GetSpritesheetPath) == "function" and layer:GetSpritesheetPath() or "?")
        end
    end
    return table.concat(parts, " | ")
end

-- Costumes the player wears, without those of actives and trinkets (never copied).
local function costumes(p)
    if type(p.GetCostumeSpriteDescs) ~= "function" then return nil end
    local ids = {}
    for _, desc in ipairs(p:GetCostumeSpriteDescs()) do
        local ok, config = pcall(desc.GetItemConfig, desc)
        if ok and config and config.Type ~= ItemType.ITEM_ACTIVE and config.Type ~= ItemType.ITEM_TRINKET then
            ids[#ids + 1] = tostring(config.Type) .. ":" .. tostring(config.ID)
        end
    end
    table.sort(ids)
    return table.concat(ids, ",")
end

local function familiars(p)
    local kinds = {}
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        local f = e:ToFamiliar()
        if f and f.Player and GetPtrHash(f.Player) == GetPtrHash(p) then kinds[#kinds + 1] = tostring(f.Variant) end
    end
    table.sort(kinds)
    return table.concat(kinds, ",")
end

local function weapons(p)
    local names = {}
    for name, id in pairs(WeaponType) do
        if type(id) == "number" and p:HasWeaponType(id) then names[#names + 1] = name end
    end
    table.sort(names)
    return table.concat(names, ",") .. (p.CanFly and " +flying" or "")
end

local function stats(p)
    local parts = {}
    for _, stat in ipairs(STATS) do parts[#parts + 1] = string.format("%s %.3f", stat, p[stat]) end
    for _, stat in ipairs(EDEN) do
        local get = p["GetEden" .. stat]
        if type(get) == "function" then parts[#parts + 1] = string.format("Eden%s %.3f", stat, get(p)) end
    end
    return table.concat(parts, ", ")
end

-- Temporary effects as type:id x count (collectible 1-4, trinket 2, null 0).
local function effectsOf(p)
    local list = p:GetEffects():GetEffectsList()
    local parts = {}
    for i = 0, list.Size - 1 do
        local e = list:Get(i)
        if e and e.Item then parts[#parts + 1] = tostring(e.Item.Type) .. ":" .. tostring(e.Item.ID) .. "x" .. tostring(e.Count) end
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

local function sub(p)
    local s = type(p.GetSubPlayer) == "function" and p:GetSubPlayer() or nil
    return s and ("sub-player " .. s:GetPlayerType()) or "no sub-player"
end

-- Compare one attribute for every pair; the detail names both sides on a mismatch.
local function compare(plan, label, read)
    plan.check(label, function(player, ctx)
        local pairs_ = ctx.pairs or {}
        if #pairs_ == 0 then return false, "no fake to compare" end
        local shown = {}
        for _, pair in ipairs(pairs_) do
            if not pair.original then return false, "no original for fake type " .. pair.fake:GetPlayerType() end
            local a, b = read(pair.original), read(pair.fake)
            if a == nil or b == nil then return nil, "API unavailable on this build" end
            if a ~= b then return false, "original [" .. a .. "] fake [" .. b .. "]" end
            shown[#shown + 1] = a
        end
        return true, table.concat(shown, " / ")
    end)
end

local function sameCharacter(plan, character)
    local name, playerType = character[1], character[2]
    plan.section("RAT / same character: " .. name)
    plan.waitUntil(function(player)
        return player:Exists() and player:GetPlayerType() == playerType and ConchBlessing.SaveManager.GetRunSave(player) ~= nil
    end, 120, "a fresh run as " .. name)
    requireApi(plan)
    plan.act(function(player, ctx)
        removeFakesOnCleanup(ctx)
        ctx.startPlayers = Game():GetNumPlayers()
        for _, id in ipairs({ CollectibleType.COLLECTIBLE_SAD_ONION, CollectibleType.COLLECTIBLE_BROTHER_BOBBY,
            CollectibleType.COLLECTIBLE_SPOON_BENDER, CollectibleType.COLLECTIBLE_CRICKETS_HEAD }) do
            player:AddCollectible(id, 0, false)
        end
    end)
    plan.wait(10)
    plan.act(function(player, ctx)
        ctx.before = {}
        for _, p in ipairs(originals()) do ctx.before[GetPtrHash(p)] = healthOf(p) end
        -- Record each step of making the fake (its items, effects and hearts).
        ctx.trace = {}
        ctx.cleanupFns = ctx.cleanupFns or {}
        table.insert(ctx.cleanupFns, function() rat()._test.setTrace(nil) end)
        rat()._test.setTrace(function(stage, body)
            local items = {}
            for id, n in pairs(body:GetCollectiblesList()) do
                if tonumber(n) and n > 0 then items[#items + 1] = id .. "x" .. n end
            end
            table.sort(items)
            ctx.trace[#ctx.trace + 1] = string.format("%s: items [%s] effects [%s] hearts %d/%d",
                stage, table.concat(items, ","), effectsOf(body), body:GetHearts(), body:GetMaxHearts())
        end)
        player:AddCollectible(ConchBlessing.ItemData.RAT.id, 0, false)
    end)
    waitFakes(plan, nil, "the rat transforms")
    plan.act(function() rat()._test.setTrace(nil) end)
    plan.note("making the fake", function(_, ctx) return table.concat(ctx.trace or {}, " | ") end)
    plan.note("fake right after the transformation", function(player)
        local parts = {}
        for _, fake in ipairs(rat().fakesOf(player)) do
            parts[#parts + 1] = "effects [" .. effectsOf(fake) .. "] health [" .. healthOf(fake) .. "] frame " .. fake.FrameCount
        end
        return table.concat(parts, " / ")
    end)
    plan.wait(20)
    plan.act(function(player, ctx) ctx.pairs = pairsOf(player) end)
    plan.check("the fake has exactly your health", function(_, ctx)
        if #ctx.pairs == 0 then return false, "no fake" end
        for _, pair in ipairs(ctx.pairs) do
            if not pair.original then return false, "no original" end
            local mine, theirs = healthOf(pair.original), healthOf(pair.fake)
            if mine ~= theirs then return false, "original [" .. mine .. "] fake [" .. theirs .. "]" end
        end
        return true, healthOf(ctx.pairs[1].original)
    end)
    plan.check("your health was left alone", function(_, ctx)
        for _, pair in ipairs(ctx.pairs) do
            local before = pair.original and ctx.before[GetPtrHash(pair.original)]
            if before and healthOf(pair.original) ~= before then
                return false, "before [" .. before .. "] now [" .. healthOf(pair.original) .. "]"
            end
        end
        return true, "unchanged"
    end)
    plan.note("temporary effects", function(_, ctx)
        local parts = {}
        for _, pair in ipairs(ctx.pairs) do
            parts[#parts + 1] = "original [" .. (pair.original and effectsOf(pair.original) or "?") .. "] fake [" .. effectsOf(pair.fake) .. "]"
        end
        return table.concat(parts, " / ")
    end)
    plan.note("players", function(player, ctx)
        return string.format("%d at start, %d now, %d fake(s); fakes are left out of the HUD and keep only passives by design",
            ctx.startPlayers, Game():GetNumPlayers(), #rat().fakesOf(player))
    end)
    plan.check("one fake per character of the holder's", function(player, ctx)
        local want = ctx.startPlayers
        return #ctx.pairs == want, "fakes " .. #ctx.pairs .. ", originals " .. want
    end)
    compare(plan, "same character", function(p) return p:GetPlayerType() .. " " .. tostring(p:GetName()) end)
    compare(plan, "same look", look)
    compare(plan, "same costumes", costumes)
    compare(plan, "same passives", function(p)
        local list = {}
        for id, n in pairs(passiveCounts(p)) do list[#list + 1] = id .. "x" .. n end
        table.sort(list)
        return table.concat(list, ",")
    end)
    compare(plan, "same familiars", familiars)
    compare(plan, "same stats", stats)
    compare(plan, "same weapon and flight", weapons)
    compare(plan, "same kind of health", function(p)
        return type(p.GetHealthType) == "function" and tostring(p:GetHealthType()) or nil
    end)
    compare(plan, "same sub-player", sub)
end

for _, character in ipairs(CHARACTERS) do
    local name = "same_" .. character[1]
    local command = "conch_test rat " .. name
    S.rows[#S.rows + 1] = { key = "RAT", name = name, command = command, groups = { characters = true },
        build = function(plan) sameCharacter(plan, character) end }
    require("scripts.dev.test_bench").register({ command = command, tag = "ItemTest:RAT",
        duration = "a fresh run as one character", restartCommand = "restart " .. character[2],
        finalRestartCommand = "restart 0",   -- end back on Isaac, as every other bench does
        resetReason = "every character needs its own fresh run", cleanup = H.cleanup,
        build = function(plan) sameCharacter(plan, character) end })
end

-- ------------------------------------------------------------------ perf
-- `conch_test rat perf` (by name only): how a run slows down as fakes are
-- added. With a typical loadout it holds 0, 1, 3 and 6 fakes in turn and logs,
-- for each, the average frame time, the room's entity count and this mod's
-- heaviest callback handlers (callback_profiler). Measurements, not checks.
local Profiler = require("scripts.dev.callback_profiler")
local frames = nil           -- render frame times while a window is open

ConchBlessing:AddCallback(ModCallbacks.MC_POST_RENDER, function()
    if not frames then return end
    local now = Isaac.GetTime()
    if frames.last then frames.sum, frames.n = frames.sum + (now - frames.last), frames.n + 1 end
    frames.last = now
end)

local function measure(plan, count)
    plan.act(function(player)
        local have = player:GetCollectibleNum(ConchBlessing.ItemData.RAT.id)
        for _ = have + 1, count do player:AddCollectible(ConchBlessing.ItemData.RAT.id, 0, false) end
    end)
    waitFakes(plan, count, count .. " fake(s)")
    plan.wait(30)
    plan.act(function(_, ctx)
        frames = { sum = 0, n = 0 }
        ctx.profiled = Profiler.start()
    end)
    plan.wait(150)
    plan.note(count .. " fake(s)", function(player, ctx)
        Profiler.stop()
        local top, total, clockName = Profiler.report(6)
        local window = frames
        frames = nil
        local parts = {}
        for _, row in ipairs(top) do parts[#parts + 1] = string.format("%s %.2fms/%d", row.label, row.ms, row.calls) end
        return string.format("%.2f ms per frame over %d frames, %d entities, %d players; this mod %.2f ms per update (%d handlers, %s); top: %s",
            window.n > 0 and window.sum / window.n or 0, window.n, #Isaac.GetRoomEntities(), Game():GetNumPlayers(),
            total / 150, ctx.profiled or 0, clockName, table.concat(parts, " | "))
    end)
end

S.add("RAT", "perf", {}, function(plan)
    requireApi(plan)
    plan.require("callback profiler available", function()
        return Profiler.available() or nil, "needs REPENTOGON's Isaac.GetCallbacks"
    end)
    plan.act(function(player, ctx)
        removeFakesOnCleanup(ctx)
        table.insert(ctx.cleanupFns, function() Profiler.stop(); frames = nil end)
        for _, id in ipairs({ CollectibleType.COLLECTIBLE_SAD_ONION, CollectibleType.COLLECTIBLE_BROTHER_BOBBY,
            CollectibleType.COLLECTIBLE_SISTER_MAGGY, CollectibleType.COLLECTIBLE_SPOON_BENDER,
            CollectibleType.COLLECTIBLE_CRICKETS_HEAD, CollectibleType.COLLECTIBLE_GUARDIAN_ANGEL }) do
            player:AddCollectible(id, 0, false)
        end
    end)
    plan.wait(30)
    for _, count in ipairs({ 0, 1, 3, 6 }) do measure(plan, count) end
end)
S.rows[#S.rows].manual = true

return C
