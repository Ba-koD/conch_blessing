local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- cb test gebo [CASE | list | give [N] | spawn]
-- Cereal's rune, used for real through EntityPlayer:UseCard. The user's design
-- (2026-11-25): the nearest pedestal within reach that may change is marked,
-- and its item turns into one of the items whose number uses the same digits
-- (Cereal's rule for what a number may make); a shop item keeps its price; an
-- item with no other arrangement, a quest item or one out of reach stays and
-- the rune is spent anyway. Every check reads the pedestals in the room.
-- Other mods' items count like any other (an install with items 811, 812 and
-- 821 lets 182 become 812 or 821 too), so the expected choices are the
-- vanilla ones plus whatever else the rule allows, each checked to be a real
-- rearrangement. A Morph expires the pedestal's EntityPtr (AGENTS.md), so a
-- pedestal is found again by its seed, which the change keeps.
local TestBench = require("scripts.dev.test_bench")
local H = require("scripts.dev.item_test_support")

local TAG = "GeboProbe"
local Probe = { cases = {}, order = {} }

local function out(line)
    Isaac.ConsoleOutput(tostring(line) .. "\n")
    Isaac.DebugString("[" .. TAG .. "] " .. tostring(line))
end

local function G() return ConchBlessing.gebo end
local function cardId() return ConchBlessing.PocketData and ConchBlessing.PocketData.GEBO.id or -1 end

local function useRune(plan)
    plan.act(function(player) player:UseCard(cardId(), UseFlag.USE_NOANIM | UseFlag.USE_NOANNOUNCER) end)
    plan.wait(3)
end

-- A pedestal of item `id` set `dy` below the player (extra fields set on it).
local function place(plan, name, id, dy, extra)
    plan.act(function(player, ctx)
        local room = Game():GetRoom()
        local pos = room:FindFreePickupSpawnPosition(player.Position + Vector(0, dy), 0, true)
        local pickup = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, id, pos, Vector.Zero, nil)
            :ToPickup()
        pickup.Wait = 90 -- nobody walks into it during the case
        for key, value in pairs(extra or {}) do pickup[key] = value end
        ctx[name] = { seed = pickup.InitSeed, pos = Vector(pickup.Position.X, pickup.Position.Y) }
    end)
    plan.wait(3)
end

local function ref(ctx, name)
    local mark = ctx[name]
    if not mark then return nil end
    local best, bestDistance = nil, 30
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE)) do
        local distance = entity.Position:Distance(mark.pos)
        if entity.InitSeed == mark.seed and distance <= bestDistance then best, bestDistance = entity:ToPickup(), distance end
    end
    return best
end

local function sortedDigits(n)
    local digits = {}
    for ch in tostring(n):gmatch("%d") do digits[#digits + 1] = ch end
    table.sort(digits)
    return table.concat(digits)
end

local function holdRune(plan)
    plan.act(function(player) player:AddCard(cardId()) end)
    plan.wait(2)
end

local function list(t)
    local text = {}
    for i, v in ipairs(t) do text[i] = tostring(v) end
    return table.concat(text, ",")
end

local function within(id, options)
    for _, n in ipairs(options) do if n == id then return true end end
    return false
end

local function case(name, title, build)
    local command = "cb test gebo " .. name
    Probe.cases[name] = command
    Probe.order[#Probe.order + 1] = name
    TestBench.register({
        command = command, tag = TAG, duration = "a few seconds", restartCommand = "restart 0", cleanup = H.cleanup,
        build = function(plan)
            plan.section("GEBO " .. name .. ": setup")
            plan.waitUntil(function(player)
                return player:Exists() and ConchBlessing.SaveManager.GetRunSave(player) ~= nil
            end, 60, "player and run save ready")
            plan.require("the rune is registered and its card ID resolves", function()
                return cardId() > 0 and G() and ConchBlessing.cereal and true or false, "card id " .. tostring(cardId())
            end)
            plan.act(function(player)
                assert(Game():GetNumPlayers() == 1 and player:GetPlayerType() == PlayerType.PLAYER_ISAAC,
                    "single-player Isaac test run required")
                player.Position = Game():GetRoom():GetCenterPos()
                G()._test.reset()
            end)
            plan.section("GEBO " .. name .. ": " .. title)
            build(plan)
        end,
    })
end

case("change", "the nearest pedestal turns into a rearrangement of its number", function(plan)
    holdRune(plan)
    place(plan, "pedestal", 182, 60)
    plan.check("182 may become 128, 218 and 281, and only rearrangements that are real items", function(_, ctx)
        local options = G().options(182)
        ctx.options = options
        local ok = within(128, options) and within(218, options) and within(281, options)
        for _, n in ipairs(options) do
            local config = Isaac.GetItemConfig():GetCollectible(n)
            if n == 182 or sortedDigits(string.format("%03d", n)) ~= sortedDigits("182") or not config
                or config.Hidden or config:HasTags(ItemConfig.TAG_QUEST) then ok = false end
        end
        return ok, list(options)
    end)
    plan.check("Brimstone 118 may become White Pony 181, which is in no pool", function()
        return within(181, G().options(CollectibleType.COLLECTIBLE_BRIMSTONE)),
            list(G().options(CollectibleType.COLLECTIBLE_BRIMSTONE))
    end)
    plan.check("no story piece comes out (Broken Shovel 550, 551, Mom's Shovel 552)", function()
        local seen = {}
        for _, from in ipairs({ 505, 55, 155, 515, 255, 525 }) do
            for _, n in ipairs(G().options(from)) do
                if n == 550 or n == 551 or n == 552 then seen[#seen + 1] = from .. "->" .. n end
            end
        end
        return #seen == 0, #seen == 0 and "none" or table.concat(seen, " ")
    end)
    plan.check("the pedestal in reach is marked", function(player, ctx)
        local target = G()._test.target(player)
        return target ~= nil and GetPtrHash(target) == GetPtrHash(ref(ctx, "pedestal")), "target " .. tostring(target and target.SubType)
    end)
    useRune(plan)
    plan.check("its item became one of them, on the same pedestal", function(_, ctx)
        local pedestal = ref(ctx, "pedestal")
        local id = pedestal and pedestal.SubType
        return id ~= nil and within(id, ctx.options or {}), "now " .. tostring(id)
    end)
end)

case("tag", "a short number is read as a three-digit tag: 25 is 025, 4 is 004", function(plan)
    holdRune(plan)
    plan.check("Breakfast 25 may become 52, 205, 250, 502 and 520", function()
        local options = G().options(CollectibleType.COLLECTIBLE_BREAKFAST)
        local ok = true
        for _, n in ipairs({ 52, 205, 250, 502, 520 }) do if not within(n, options) then ok = false end end
        return ok, list(options)
    end)
    plan.check("item 4 may become 40 and 400", function()
        local options = G().options(4)
        return within(40, options) and within(400, options), list(options)
    end)
    place(plan, "pedestal", CollectibleType.COLLECTIBLE_BREAKFAST, 60)
    useRune(plan)
    plan.check("Breakfast became one of them", function(_, ctx)
        local pedestal = ref(ctx, "pedestal")
        local id = pedestal and pedestal.SubType
        return id ~= nil and within(id, G().options(CollectibleType.COLLECTIBLE_BREAKFAST)), "now " .. tostring(id)
    end)
end)

case("shop", "a shop item changes and keeps its price", function(plan)
    holdRune(plan)
    place(plan, "pedestal", 182, 60, { Price = 15, AutoUpdatePrice = false })
    useRune(plan)
    plan.check("it changed and still costs 15", function(_, ctx)
        local pedestal = ref(ctx, "pedestal")
        local id = pedestal and pedestal.SubType
        return id and within(id, G().options(182)) and pedestal.Price == 15,
            string.format("now %s price %s", tostring(id), tostring(pedestal and pedestal.Price))
    end)
end)

case("stays", "no other arrangement, a quest item or one out of reach stays", function(plan)
    holdRune(plan)
    -- item 111 (The Bean): three of one digit have no other arrangement in any install
    place(plan, "single", 111, 50)
    place(plan, "quest", CollectibleType.COLLECTIBLE_KEY_PIECE_1, -50)
    place(plan, "far", 182, 200)
    plan.check("none of them is marked", function(player)
        local target = G()._test.target(player)
        return target == nil, "target " .. tostring(target and target.SubType)
    end)
    useRune(plan)
    plan.check("all three stay as they were", function(_, ctx)
        local a, b, c = ref(ctx, "single"), ref(ctx, "quest"), ref(ctx, "far")
        return a and a.SubType == 111 and b
            and b.SubType == CollectibleType.COLLECTIBLE_KEY_PIECE_1 and c and c.SubType == 182,
            string.format("%s %s %s", tostring(a and a.SubType), tostring(b and b.SubType), tostring(c and c.SubType))
    end)
end)

case("nearest", "only the nearest of two pedestals in reach changes", function(plan)
    holdRune(plan)
    place(plan, "near", 182, 40)
    place(plan, "other", 245, -70)
    useRune(plan)
    plan.check("the near one changed and the other did not", function(_, ctx)
        local near, other = ref(ctx, "near"), ref(ctx, "other")
        return near and within(near.SubType, G().options(182)) and other and other.SubType == 245,
            string.format("near %s other %s", tostring(near and near.SubType), tostring(other and other.SubType))
    end)
end)

case("eid", "a pedestal's description lists what it may become", function(plan)
    holdRune(plan)
    plan.check("182's line lists every item it may become, 128, 218 and 281 among them", function()
        local line = G().eidLine(182) or ""
        local ok = line:find("{{Card" .. cardId() .. "}}", 1, true) ~= nil
        for _, n in ipairs(G().options(182)) do
            if not line:find("{{Collectible" .. n .. "}}", 1, true) then ok = false end
        end
        for _, n in ipairs({ 128, 218, 281 }) do
            if not line:find("{{Collectible" .. n .. "}}", 1, true) then ok = false end
        end
        return ok, line
    end)
    plan.check("item 111's line says it cannot change", function()
        local line = G().eidLine(111) or ""
        return line ~= "" and not line:find("{{Collectible", 1, true), line
    end)
    plan.check("a holder is seen", function() return G().anyHolder() == true end)
end)

case("card", "the card is registered as a rune", function(plan)
    plan.check("pocketitems.xml entry", function()
        local config = Isaac.GetItemConfig():GetCard(cardId())
        if not config then return false, "no card config" end
        return config.Name == "Gebo" and config.Description == "Exchange" and config.MimicCharge == 4
            and config.PickupSubtype == 7793 and config.HudAnim == "Gebo",
            string.format("name=%s desc=%s charge=%s pickup=%s hud=%s", tostring(config.Name),
                tostring(config.Description), tostring(config.MimicCharge), tostring(config.PickupSubtype),
                tostring(config.HudAnim))
    end)
    plan.check("its card type is rune", function()
        local config = Isaac.GetItemConfig():GetCard(cardId())
        if not (config and type(config.CardType) == "number" and ItemConfig and type(ItemConfig.CARDTYPE_RUNE) == "number") then
            return nil, "this build exposes no card type"
        end
        return config.CardType == ItemConfig.CARDTYPE_RUNE, "CardType " .. tostring(config.CardType)
    end)
    plan.section("GEBO card: in the pocket", "the pocket slot shows the dark stone with the gold rune ᚷ")
    holdRune(plan)
    plan.wait(30)
    plan.check("the pocket holds Gebo", function(player)
        return player:GetCard(0) == cardId(), "pocket card " .. tostring(player:GetCard(0))
    end)
end)

-- ---------------------------------------------------------------- manual helpers
local HELPERS = {
    give = function(words, player)
        local n = math.max(1, math.min(4, math.floor(tonumber(words[3]) or 1)))
        for _ = 1, n do player:AddCard(cardId()) end
        out(string.format("Gave %d Gebo (card %d) to the pocket.", n, cardId()))
    end,
    spawn = function(_, player)
        local at = Game():GetRoom():FindFreePickupSpawnPosition(player.Position + Vector(80, 0), 0, true)
        Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD, cardId(), at, Vector.Zero, nil)
        out("Spawned a Gebo rune beside the player.")
    end,
}

function Probe.commands()
    local names = {}
    for _, name in ipairs(Probe.order) do names[#names + 1] = Probe.cases[name] end
    return names
end

function Probe.commandFor(name) return Probe.cases[name] end

function Probe.isHelper(name) return HELPERS[name] ~= nil end

function Probe.helper(name, words, player)
    if not player then out("Start a run first.") return end
    HELPERS[name](words, player)
end

function Probe.list()
    local lines = { "cb test gebo  -> every case below, each from a clean run" }
    for _, name in ipairs(Probe.order) do lines[#lines + 1] = "  " .. Probe.cases[name] end
    lines[#lines + 1] = "Manual helpers on the current run: cb test gebo give [N] | spawn"
    return lines
end

return Probe
