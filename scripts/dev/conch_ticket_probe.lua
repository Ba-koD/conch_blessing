local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- conch_test conch_ticket [CASE | list | give [N] | spawn | queue | clear]
-- The Conch Ticket used for real through EntityPlayer:UseCard. Its picker reads
-- the shooting and card keys with Input.IsActionPressed, which MC_INPUT_ACTION
-- cannot fake (measured in game 2026-10-12), so the bench holds keys through the
-- ticket's test-only key source; the picker's own update/confirm path runs as in
-- play. Real keys stay a LOOK check. Answers are checked against what the real
-- Magic Conch then says. Each case starts from a clean run; results land
-- in log.txt. The manual helpers set up and read a live run (Continue, the look).
local TestBench = require("scripts.dev.test_bench")
local H = require("scripts.dev.item_test_support")

local TAG = "ConchTicketProbe"
local BENCH_OWNER = "ConchBlessing Ticket Bench"
local Probe = { cases = {}, order = {} }

local function out(line)
    Isaac.ConsoleOutput(tostring(line) .. "\n")
    Isaac.DebugString("[" .. TAG .. "] " .. tostring(line))
end

local function T() return ConchBlessing.conchTicket end
local function cardId() return ConchBlessing.PocketData and ConchBlessing.PocketData.CONCH_TICKET.id or -1 end
local function conchAPI()
    local provider = rawget(_G, "MagicConch")
    return provider and provider.API
end
local function reservation()
    local api = conchAPI()
    return api and type(api.GetNextResultReservation) == "function" and api.GetNextResultReservation(T()._test.owner) or nil
end
local function reservedKind()
    local r = reservation()
    return r and r.options and r.options.type
end
local function queueText()
    return "{" .. table.concat(T().queue(), ",") .. "}"
end


-- Results the real Magic Conch hands its listeners while a case runs.
local results = {}
local function listen()
    local api = conchAPI()
    if api and type(api.RegisterCallback) == "function" then
        api.RegisterCallback(function(result) results[#results + 1] = result end, BENCH_OWNER)
    end
end
local function stopListening()
    local api = conchAPI()
    if api and type(api.UnregisterCallback) == "function" then pcall(api.UnregisterCallback, BENCH_OWNER) end
end

-- ---------------------------------------------------------------- plan pieces
local function tap(plan, action)
    plan.act(function() T()._test.hold(action, true) end)
    plan.wait(3)
    plan.act(function() T()._test.hold(action, false) end)
    plan.wait(3)
end

-- Use one ticket and choose: steps to the right from the preselected answer.
local function pick(plan, rights, label)
    plan.act(function(player) player:UseCard(cardId(), UseFlag.USE_NOANIM | UseFlag.USE_NOANNOUNCER) end)
    plan.waitUntil(function(player) return T().picking(player), "no picker" end, 10, "the picker opens over the head")
    for _ = 1, rights do tap(plan, ButtonAction.ACTION_SHOOTRIGHT) end
    tap(plan, ButtonAction.ACTION_PILLCARD)
    plan.require(label or "the card key confirms the choice", function(player)
        return not T().picking(player), "picker still open; queue " .. queueText()
    end)
end

local function roomEntry(plan)
    plan.act(function(_, ctx)
        ctx.beforeRooms = ctx.rooms
        Game():StartRoomTransition(Game():GetLevel():GetCurrentRoomIndex(), Direction.NO_DIRECTION,
            RoomTransitionAnim.FADE)
    end)
    plan.waitUntil(function(_, ctx) return ctx.rooms > ctx.beforeRooms end, 150, "a real room entry")
    plan.wait(6)
end

-- Ask the real Magic Conch and wait for its answer.
local function askConch(plan, label)
    plan.act(function(_, ctx) ctx.heard = #results end)
    plan.waitUntil(function()
        local outcome = conchAPI().TriggerMagicConch(BENCH_OWNER)
        return type(outcome) == "table" and outcome.success == true, outcome and outcome.reason
    end, 300, "the Magic Conch takes the question")
    plan.waitUntil(function(_, ctx) return #results > ctx.heard, "no answer yet" end, 300, label or "the Magic Conch answers")
    plan.wait(4)
end

local function lastAnswer() local r = results[#results]; return r and r.type, r and r.forced end

-- ---------------------------------------------------------------- cases
local function case(name, title, build)
    local command = "conch_test conch_ticket " .. name
    Probe.cases[name] = command
    Probe.order[#Probe.order + 1] = name
    TestBench.register({
        command = command, tag = TAG, duration = "a few seconds", restartCommand = "restart 0", cleanup = H.cleanup,
        build = function(plan)
            plan.section("CONCH_TICKET " .. name .. ": setup")
            plan.waitUntil(function(player)
                return player:Exists() and ConchBlessing.SaveManager.GetRunSave(player) ~= nil
            end, 60, "player and run save ready")
            plan.require("the ticket and the Magic Conch API are ready", function()
                local api = conchAPI()
                return cardId() > 0 and T() ~= nil and api ~= nil and type(api.ReserveNextResult) == "function"
                    and type(api.TriggerMagicConch) == "function", "card id " .. tostring(cardId())
            end)
            plan.act(function(player, ctx)
                assert(Game():GetNumPlayers() == 1 and player:GetPlayerType() == PlayerType.PLAYER_ISAAC,
                    "single-player Isaac test run required")
                player.Position = Game():GetRoom():GetCenterPos()
                T()._test.releaseAll()
                results = {}
                listen()
                ctx.cleanupFns = { function()
                    T()._test.releaseAll()
                    stopListening()
                end }
            end)
            plan.section("CONCH_TICKET " .. name .. ": " .. title)
            build(plan)
        end,
    })
end

case("pick", "choose an answer over the head", function(plan)
    plan.act(function(player) player:UseCard(cardId(), UseFlag.USE_NOANIM | UseFlag.USE_NOANNOUNCER) end)
    plan.waitUntil(function(player) return T().picking(player), "no picker" end, 10, "the picker opens over the head")
    plan.section("CONCH_TICKET pick: the picker",
        "over the head: positive  [neutral]  negative, and below it '< > choose   Q confirm'; with real keys, the shooting keys move it, no tears come out, and Q confirms without using the next pocket item")
    plan.wait(30)
    plan.check("neutral is preselected", function(player)
        return H.expect(ConchBlessing.SaveManager.GetRunSave(player).conchTicketPick.index, 2)
    end)
    tap(plan, ButtonAction.ACTION_SHOOTRIGHT)
    plan.check("a shooting key moves the choice", function(player)
        return H.expect(ConchBlessing.SaveManager.GetRunSave(player).conchTicketPick.index, 3)
    end)
    plan.check("nothing is reserved before confirming", function() return reservedKind() == nil, tostring(reservedKind()) end)
    tap(plan, ButtonAction.ACTION_PILLCARD)
    plan.check("the card key confirms it", function(player)
        return not T().picking(player) and queueText() == "{negative}", "queue " .. queueText()
    end)
    plan.check("the Magic Conch's next answer is reserved", function()
        return reservedKind() == "negative", "reserved " .. tostring(reservedKind())
    end)
    plan.section("CONCH_TICKET pick: the reminder", "'Reserved: negative' sits just above the Magic Conch counter")
    plan.wait(30)
end)

case("rooms", "the reservation outlives rooms and floors", function(plan)
    pick(plan, 1)
    plan.check("reserved", function() return reservedKind() == "negative", tostring(reservedKind()) end)
    roomEntry(plan)
    plan.check("still reserved after a room change", function()
        return reservedKind() == "negative" and queueText() == "{negative}", tostring(reservedKind()) .. " " .. queueText()
    end)
    plan.act(function(_, ctx) ctx.beforeRooms = ctx.rooms; Isaac.ExecuteCommand("stage 2") end)
    plan.waitUntil(function(_, ctx) return ctx.rooms > ctx.beforeRooms end, 150, "a new floor")
    plan.wait(10)
    plan.check("still reserved on a new floor", function()
        return reservedKind() == "negative" and queueText() == "{negative}", tostring(reservedKind()) .. " " .. queueText()
    end)
end)

case("use", "the Magic Conch gives the reserved answers in order", function(plan)
    pick(plan, 2, "the first ticket confirms positive")
    pick(plan, 2, "the second ticket confirms negative")
    plan.check("two answers wait in order", function() return queueText() == "{positive,negative}", queueText() end)
    askConch(plan)
    plan.check("the Conch says the first reserved answer", function()
        local kind, forced = lastAnswer()
        return kind == "positive" and forced == true, tostring(kind) .. " forced=" .. tostring(forced)
    end)
    plan.check("that answer is spent and the next one is reserved", function()
        return queueText() == "{negative}" and reservedKind() == "negative", queueText() .. " " .. tostring(reservedKind())
    end)
    roomEntry(plan)
    askConch(plan)
    plan.check("the Conch says the second reserved answer", function()
        local kind, forced = lastAnswer()
        return kind == "negative" and forced == true, tostring(kind) .. " forced=" .. tostring(forced)
    end)
    plan.check("no ticket answer is left", function()
        return queueText() == "{}" and reservedKind() == nil, queueText() .. " " .. tostring(reservedKind())
    end)
    roomEntry(plan)
    askConch(plan)
    plan.check("the next Conch answers on its own again", function()
        local _, forced = lastAnswer()
        return forced ~= true, "forced=" .. tostring(forced)
    end)
end)

case("card", "the card itself", function(plan)
    plan.check("pocketitems.xml entry", function()
        local config = Isaac.GetItemConfig():GetCard(cardId())
        if not config then return false, "no card config" end
        return config.Name == "Conch Ticket" and config.Description == "Reserved" and config.MimicCharge == 4
            and config.PickupSubtype == 7782 and config.HudAnim == "Conch Ticket",
            string.format("name=%s desc=%s charge=%s pickup=%s hud=%s", tostring(config.Name),
                tostring(config.Description), tostring(config.MimicCharge), tostring(config.PickupSubtype),
                tostring(config.HudAnim))
    end)
    plan.section("CONCH_TICKET card: in the pocket and dropped",
        "the pocket slot shows the cream ticket; dropped, it flicks up, flutters like paper and lands flat")
    plan.act(function(player, ctx)
        player:AddCard(cardId())
        ctx.dropAt = Game():GetRoom():FindFreePickupSpawnPosition(player.Position + Vector(100, 0), 0, true)
    end)
    plan.wait(30)
    plan.act(function(player, ctx) ctx.animations = {}; player:DropPocketItem(0, ctx.dropAt) end)
    plan.waitUntil(function(_, ctx)
        for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD, cardId())) do
            ctx.pickup = entity:ToPickup()
        end
        return ctx.pickup ~= nil, "no ticket pickup yet"
    end, 30, "the dropped ticket lies in the room")
    plan.waitUntil(function(_, ctx)
        local sprite = ctx.pickup:GetSprite()
        for _, name in ipairs({ "Appear", "Idle" }) do
            if sprite:IsPlaying(name) or sprite:IsFinished(name) then ctx.animations[name] = true end
        end
        return ctx.animations.Idle == true, "not idle yet"
    end, 90, "the dropped ticket settles")
    plan.check("it uses the ticket's own animation file", function(_, ctx)
        local name = ctx.pickup:GetSprite():GetFilename()
        return tostring(name):lower():find("005.300_conch_ticket.anm2", 1, true) ~= nil, tostring(name)
    end)
    plan.note("animations seen", function(_, ctx)
        return "Appear=" .. tostring(ctx.animations.Appear == true) .. " Idle=" .. tostring(ctx.animations.Idle == true)
    end)
    plan.act(function(_, ctx) if ctx.pickup and ctx.pickup:Exists() then ctx.pickup:Remove() end end)
end)


-- Natural drops: the game's own random card draws, which room rewards, chests
-- and rune drops use. A share above zero means it is in the pool.
case("pool", "it turns up among the game's random cards", function(plan)
    local ROLLS = 4000
    plan.check("ordinary card drops can give the Conch Ticket", function()
        local pool, hits = Game():GetItemPool(), 0
        for seed = 1, ROLLS do
            if pool:GetCard(seed, true, true, false) == cardId() then hits = hits + 1 end
        end
        return hits > 0, string.format("%d of %d rolls", hits, ROLLS)
    end)
    plan.check("card drops without runes or playing cards can give it", function()
        local pool, hits = Game():GetItemPool(), 0
        for seed = 1, ROLLS do
            if pool:GetCard(seed, false, false, false) == cardId() then hits = hits + 1 end
        end
        return hits > 0, string.format("%d of %d rolls", hits, ROLLS)
    end)
end)

-- ---------------------------------------------------------------- manual helpers
local HELPERS = {
    give = function(words, player)
        local n = math.max(1, math.min(4, math.floor(tonumber(words[3]) or 1)))
        for _ = 1, n do player:AddCard(cardId()) end
        out(string.format("Gave %d Conch Ticket(s) (card %d) to the pocket.", n, cardId()))
    end,
    spawn = function(_, player)
        local at = Game():GetRoom():FindFreePickupSpawnPosition(player.Position + Vector(80, 0), 0, true)
        Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD, cardId(), at, Vector.Zero, nil)
        out("Spawned a Conch Ticket beside the player.")
    end,
    queue = function()
        local game = Game()
        local picks = {}
        for i = 0, game:GetNumPlayers() - 1 do
            local pickSave = ConchBlessing.SaveManager.GetRunSave(game:GetPlayer(i)).conchTicketPick
            picks[#picks + 1] = string.format("P%d open=%s index=%s", i + 1, tostring(pickSave and pickSave.open or 0),
                tostring(pickSave and pickSave.index or "-"))
        end
        local r = reservation()
        out(string.format("Ticket queue %s; Conch reservation %s; pickers %s", queueText(),
            r and (tostring(r.options and r.options.type) .. " (token " .. tostring(r.token) .. ")") or "none",
            table.concat(picks, ", ")))
    end,
    clear = function()
        local run = ConchBlessing.SaveManager.GetRunSave(nil)
        if run.conchTicket then run.conchTicket.queue = {} end
        ConchBlessing.SaveManager.Save()
        T().sync()
        out("Cleared the ticket queue.")
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
    local lines = { "conch_test conch_ticket  -> every case below, each from a clean run" }
    for _, name in ipairs(Probe.order) do lines[#lines + 1] = "  " .. Probe.cases[name] end
    lines[#lines + 1] = "Manual helpers on the current run: conch_test conch_ticket give [N] | spawn | queue | clear"
    lines[#lines + 1] = "Continue check: confirm an answer, save and quit, continue, then conch_test conch_ticket queue"
    return lines
end

return Probe
