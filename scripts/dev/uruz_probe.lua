local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- cb test uruz [CASE | list | give [N] | spawn | earned]
-- Tyrfing's rune, used for real through EntityPlayer:UseCard (and Clear Rune).
-- For the room it is used in, every monster death gives the user +0.05 damage
-- for good; hits never take it away and leaving the room ends it. Kills are
-- real (H.killTarget: a lethal hit on a live attack fly, confirmed by the
-- engine's own death events) and damage is read from the player's stats.
local TestBench = require("scripts.dev.test_bench")
local H = require("scripts.dev.item_test_support")

local TAG = "UruzProbe"
local Probe = { cases = {}, order = {} }

local function out(line)
    Isaac.ConsoleOutput(tostring(line) .. "\n")
    Isaac.DebugString("[" .. TAG .. "] " .. tostring(line))
end

local function U() return ConchBlessing.uruz end
local function cardId() return ConchBlessing.PocketData and ConchBlessing.PocketData.URUZ.id or -1 end
local function per() return U().data.damagePerKill end
local function earned(player)
    local data = U().earned(player)
    return data and data.damage or 0
end

local function useRune(plan)
    plan.act(function(player) player:UseCard(cardId(), UseFlag.USE_NOANIM | UseFlag.USE_NOANNOUNCER) end)
    plan.wait(2)
end

local function kill(plan, label)
    plan.act(function(player, ctx) H.killTarget(player, ctx) end)
    plan.waitUntil(H.deathObserved, 120, label or "a real monster death")
    plan.wait(4)
end

local function expectEarned(plan, label, kills)
    plan.check(label, function(player, ctx)
        local want = kills * per()
        local damage = H.stats(player).Damage - ctx.base.Damage
        return math.abs(earned(player) - want) < 1e-6 and damage > 0 == (want > 0) and damage >= want * 0.99 - 1e-6,
            string.format("earned %.3f (want %.3f), damage +%.3f", earned(player), want, damage)
    end)
end

local rooms = 0
ConchBlessing:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function() rooms = rooms + 1 end)

local function roomEntry(plan)
    plan.act(function(_, ctx)
        ctx.roomsBefore = rooms
        Game():StartRoomTransition(Game():GetLevel():GetCurrentRoomIndex(), Direction.NO_DIRECTION,
            RoomTransitionAnim.FADE)
    end)
    plan.waitUntil(function(_, ctx) return rooms > ctx.roomsBefore, "rooms " .. rooms end, 150, "a real room entry")
    plan.wait(6)
end

local function case(name, title, build)
    local command = "cb test uruz " .. name
    Probe.cases[name] = command
    Probe.order[#Probe.order + 1] = name
    TestBench.register({
        command = command, tag = TAG, duration = "a few seconds", restartCommand = "restart 0", cleanup = H.cleanup,
        build = function(plan)
            plan.section("URUZ " .. name .. ": setup")
            plan.waitUntil(function(player)
                return player:Exists() and ConchBlessing.SaveManager.GetRunSave(player) ~= nil
            end, 60, "player and run save ready")
            plan.require("the rune is registered and its card ID resolves", function()
                return cardId() > 0 and U() and U()._test.started() and true or false, "card id " .. tostring(cardId())
            end)
            plan.act(function(player, ctx)
                assert(Game():GetNumPlayers() == 1 and player:GetPlayerType() == PlayerType.PLAYER_ISAAC,
                    "single-player Isaac test run required")
                player.Position = Game():GetRoom():GetCenterPos()
                H.refresh(player)
                ctx.base = H.stats(player)
                U()._test.resetEvidence()
            end)
            plan.section("URUZ " .. name .. ": " .. title)
            build(plan)
        end,
    })
end

case("kills", "each kill in the room gives +0.05 for good", function(plan)
    kill(plan, "a kill before the rune")
    expectEarned(plan, "a kill before using it gives nothing", 0)
    useRune(plan)
    kill(plan, "the first kill")
    expectEarned(plan, "one kill: +0.05", 1)
    kill(plan, "the second kill")
    expectEarned(plan, "two kills: +0.10", 2)
end)

case("stack", "a second use in the room doubles the reward", function(plan)
    useRune(plan)
    useRune(plan)
    plan.check("two uses counted for this room", function(player)
        return U().uses(player) == 2, "uses " .. U().uses(player)
    end)
    kill(plan)
    expectEarned(plan, "one kill with two uses: +0.10", 2)
end)

case("room_ends", "leaving the room ends it; what was earned stays", function(plan)
    useRune(plan)
    kill(plan)
    expectEarned(plan, "one kill: +0.05", 1)
    roomEntry(plan)
    plan.check("the new room has no Uruz", function(player) return U().uses(player) == 0, "uses " .. U().uses(player) end)
    kill(plan, "a kill after the room changed")
    expectEarned(plan, "the earned +0.05 stays and the new kill adds nothing", 1)
end)

case("hit_keeps", "a hit takes nothing away", function(plan)
    useRune(plan)
    kill(plan)
    H.hit(plan)
    expectEarned(plan, "after a real hit the +0.05 is still there", 1)
end)

case("clear_rune", "a Clear Rune copy works like the rune", function(plan)
    plan.act(function(player)
        player:AddCard(cardId())
        player:UseActiveItem(CollectibleType.COLLECTIBLE_CLEAR_RUNE, UseFlag.USE_NOANIM, -1)
    end)
    plan.wait(2)
    plan.check("the copy counts as a use", function(player) return U().uses(player) >= 1, "uses " .. U().uses(player) end)
    kill(plan)
    plan.check("its kill earns the reward", function(player)
        return earned(player) >= per() - 1e-6, string.format("earned %.3f", earned(player))
    end)
end)

case("card", "the card is registered as a rune", function(plan)
    plan.check("pocketitems.xml entry", function()
        local config = Isaac.GetItemConfig():GetCard(cardId())
        if not config then return false, "no card config" end
        return config.Name == "Uruz" and config.Description == "Strength" and config.MimicCharge == 4
            and config.PickupSubtype == 7783 and config.HudAnim == "Uruz",
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
    plan.section("URUZ card: in the pocket", "the pocket slot shows the dark stone with the gold rune ᚢ")
    plan.act(function(player) player:AddCard(cardId()) end)
    plan.wait(30)
    plan.check("the pocket holds Uruz", function(player)
        return player:GetCard(0) == cardId(), "pocket card " .. tostring(player:GetCard(0))
    end)
end)

-- ---------------------------------------------------------------- manual helpers
local HELPERS = {
    give = function(words, player)
        local n = math.max(1, math.min(4, math.floor(tonumber(words[3]) or 1)))
        for _ = 1, n do player:AddCard(cardId()) end
        out(string.format("Gave %d Uruz (card %d) to the pocket.", n, cardId()))
    end,
    spawn = function(_, player)
        local at = Game():GetRoom():FindFreePickupSpawnPosition(player.Position + Vector(80, 0), 0, true)
        Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD, cardId(), at, Vector.Zero, nil)
        out("Spawned an Uruz rune beside the player.")
    end,
    earned = function()
        local game = Game()
        for i = 0, game:GetNumPlayers() - 1 do
            local player = game:GetPlayer(i)
            local data = U().earned(player)
            out(string.format("Player %d: Uruz damage +%.2f from %d kills; uses in this room %d", i + 1,
                data and data.damage or 0, data and data.kills or 0, U().uses(player)))
        end
    end,
}

function Probe.commands()
    local list = {}
    for _, name in ipairs(Probe.order) do list[#list + 1] = Probe.cases[name] end
    return list
end

function Probe.commandFor(name) return Probe.cases[name] end

function Probe.isHelper(name) return HELPERS[name] ~= nil end

function Probe.helper(name, words, player)
    if not player then out("Start a run first.") return end
    HELPERS[name](words, player)
end

function Probe.list()
    local lines = { "cb test uruz  -> every case below, each from a clean run" }
    for _, name in ipairs(Probe.order) do lines[#lines + 1] = "  " .. Probe.cases[name] end
    lines[#lines + 1] = "Manual helpers on the current run: cb test uruz give [N] | spawn | earned"
    lines[#lines + 1] = "Continue check: kill with Uruz, save and quit, continue, then cb test uruz earned"
    return lines
end

return Probe
