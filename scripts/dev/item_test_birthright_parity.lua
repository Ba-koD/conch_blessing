local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- Severed Oath against the real Isaac's Birthright (user rule 2026-10-28: it
-- must work exactly like Birthright). Every case runs twice on a fresh Isaac
-- run, once holding Birthright (the vanilla control) and once holding the
-- Oath, and both arms must show the same number of extra choices on each
-- pedestal the case looks at. The expectations are Birthright's own (wiki:
-- "All new item pedestals cycle between two options. Previously-seen items
-- are unaffected."), so a failing birthright arm means the expectation is
-- wrong, not the Oath. Birthright is used here only as the control; the Oath
-- never grants it.
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")
local C = require("scripts.dev.cycle_compare_support")
local M = {commands = {}}

-- Fixture items, read when a bench is built.
local function own() return CollectibleType.COLLECTIBLE_BOOK_OF_SHADOWS end
local function spare() return CollectibleType.COLLECTIBLE_BOBS_ROTTEN_HEAD end
local function pedestalActive() return CollectibleType.COLLECTIBLE_YUM_HEART end
local function passive() return CollectibleType.COLLECTIBLE_BREAKFAST end

local function oathId() return ConchBlessing.ItemData.SEVERED_OATH.id end

local function find(anchor)
    for _, p in ipairs(C.stock()) do
        if C.anchor(p) == anchor then return p end
    end
end

local function spawn(offset, id)
    local room = Game():GetRoom()
    local position = room:FindFreePickupSpawnPosition(room:GetCenterPos() + offset, 0, true)
    local p = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, id, position, Vector.Zero, nil):ToPickup()
    return C.anchor(assert(p, "pedestal spawn failed"))
end

local ARM_LABELS = {birthright = "vanilla Birthright control: ", native = "Tainted Isaac alone: ",
    oath = "Severed Oath: "}

local function label(ctx, text)
    return (ARM_LABELS[ctx.arm] or "") .. text
end

-- Extra choices on one pedestal.
local function expectChoices(plan, text, field, want)
    plan.check(text, function(_, ctx)
        local p = find(ctx[field])
        if not p then return false, "pedestal at " .. tostring(ctx[field]) .. " is gone" end
        local got = #p:GetCollectibleCycle()
        return got == want, label(ctx, string.format("item=%d extra choices=%d expected=%d", p.SubType, got, want))
    end)
end

local function expectAll(plan, text, want)
    plan.check(text, function(_, ctx)
        local stock, wrong = C.stock(), {}
        for _, p in ipairs(stock) do
            local got = #p:GetCollectibleCycle()
            if got ~= want then wrong[#wrong + 1] = p.SubType .. ":" .. got end
        end
        if #stock == 0 then return false, "no pedestal to observe" end
        return #wrong == 0, label(ctx, string.format("%d pedestals, expected %d extra each; differing [%s]",
            #stock, want, table.concat(wrong, ",")))
    end)
end

local function travel(plan, field, text)
    plan.act(function(player, ctx)
        Game():StartRoomTransition(ctx[field], Direction.NO_DIRECTION, RoomTransitionAnim.FADE, player)
    end)
    plan.waitUntil(function(_, ctx)
        local index = Game():GetLevel():GetCurrentRoomIndex()
        return index == ctx[field] and RoomTransition.GetTransitionMode() == 0 and Game():GetRoom():GetFrameCount() > 0,
            "room=" .. tostring(index) .. " target=" .. tostring(ctx[field])
    end, 180, text)
    plan.wait(8)
end

-- Walk onto a pedestal and wait until the item is held; a held active drops
-- onto the same pedestal.
local function take(plan, field, text)
    plan.act(function(player, ctx)
        local p = assert(find(ctx[field]), "pedestal to take is gone")
        ctx.takeId, ctx.takeSeed, ctx.takeHash = p.SubType, p.InitSeed, GetPtrHash(p)
        p.Wait = 0
        player.Position = p.Position
    end)
    plan.waitUntil(function(player, ctx)
        return player:HasCollectible(ctx.takeId) and player:IsItemQueueEmpty(), "taking item " .. tostring(ctx.takeId)
    end, 240, text)
    plan.act(function(player) player.Position = Game():GetRoom():GetCenterPos() + Vector(0, 120) end)
    plan.wait(30)
    plan.note("dropped item stands on the same pedestal", function(_, ctx)
        local p = find(ctx[field])
        return p and string.format("item=%d seed %s->%s samePointer=%s touched=%s", p.SubType, tostring(ctx.takeSeed),
            tostring(p.InitSeed), tostring(GetPtrHash(p) == ctx.takeHash), tostring(p.Touched)) or "no pedestal left"
    end)
end

local function setup(plan, case, arm)
    plan.act(function(player, ctx)
        ctx.case, ctx.arm = case, arm
        H.suppressRandomGoldenPedestals(ctx)
        local level, maze = Game():GetLevel(), LevelCurse.CURSE_OF_MAZE
        -- Each arm is a fresh run that is reset afterwards; Maze would redirect travel.
        if level:GetCurses() & maze ~= 0 then level:RemoveCurses(maze) end
        ctx.origin = level:GetCurrentRoomIndex()
        local rooms = level:GetRooms()
        for i = 0, rooms.Size - 1 do
            local desc = rooms:Get(i)
            if desc.Data and desc.Data.Type == RoomType.ROOM_TREASURE then ctx.treasure = desc.SafeGridIndex; break end
        end
        for _, p in ipairs(C.stock()) do p:Remove() end
        player.Position = Game():GetRoom():GetCenterPos() + Vector(0, 120)
    end)
    plan.require("cycle inspection, transition mode and a treasure room", function(player, ctx)
        return (REPENTOGON ~= nil and type(RoomTransition) == "table"
            and type(RoomTransition.GetTransitionMode) == "function" and type(player.IsItemQueueEmpty) == "function"
            and ctx.treasure ~= nil) or nil, "REPENTOGON cycle/transition APIs and a native treasure room required"
    end)
end

-- The held active's golden state decides +1 or +2, and Golden Items keeps it
-- per ID across runs; pin an ordinary Oath and restore the old value.
local function pinOrdinary(plan)
    plan.act(function(player, ctx)
        local provider = Epiphany and type(Epiphany.HasGoldenItem) == "function" and Epiphany or GoldenItems
        if not (provider and type(provider.HasGoldenItem) == "function"
            and type(provider.ExaustGoldenItem) == "function" and type(provider.SetGoldenItem) == "function") then return end
        local id = oathId()
        for _, slot in ipairs({ActiveSlot.SLOT_PRIMARY, ActiveSlot.SLOT_SECONDARY}) do
            if provider:HasGoldenItem(id, player, slot) == true then
                provider:ExaustGoldenItem(id, player, slot)
                ctx.cleanupFns = ctx.cleanupFns or {}
                ctx.cleanupFns[#ctx.cleanupFns + 1] = function() provider:SetGoldenItem(id, player, slot) end
            end
        end
    end)
end

-- Hold the effect under test. With a Schoolbag the Oath sits in the second slot.
local function hold(plan, arm, slot)
    plan.act(function(player)
        if arm == "birthright" then player:AddCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT, 0, false)
        else player:AddCollectible(oathId(), 0, false, slot or ActiveSlot.SLOT_PRIMARY) end
    end)
    if arm == "oath" then pinOrdinary(plan) end
    plan.wait(4)
end

local cases = {}

-- Stock generated on a room's first visit while held gains one choice, once.
cases.first_visit = function(plan, arm)
    hold(plan, arm)
    travel(plan, "treasure", "first visit to the treasure room")
    expectAll(plan, "first-visit stock has one extra choice", 1)
    travel(plan, "origin", "leave the treasure room")
    travel(plan, "treasure", "come back")
    expectAll(plan, "a revisit adds nothing more", 1)
end

-- "Previously-seen items are unaffected."
cases.seen_room = function(plan, arm)
    travel(plan, "treasure", "see the treasure room first")
    expectAll(plan, "stock seen without the item has no extra choice", 0)
    travel(plan, "origin", "leave the treasure room")
    hold(plan, arm)
    travel(plan, "treasure", "come back holding it")
    expectAll(plan, "seen stock stays as it was", 0)
    plan.act(function(_, ctx) ctx.new = spawn(Vector(0, -80), passive()) end)
    plan.wait(8)
    expectChoices(plan, "a pedestal created now gains one", "new", 1)
end

-- Gaining the item in a room reaches only pedestals created afterwards. In the
-- Oath arm it is picked up from its own pedestal while holding another active,
-- which drops that active onto it (the user's first report).
cases.mid_room = function(plan, arm)
    plan.act(function(player, ctx)
        player:AddCollectible(own(), 0, false, ActiveSlot.SLOT_PRIMARY)
        ctx.existing = spawn(Vector(-120, 0), passive())
        ctx.swap = spawn(Vector(120, 0), arm == "oath" and oathId() or pedestalActive())
    end)
    plan.wait(8)
    expectChoices(plan, "existing pedestal before the item", "existing", 0)
    if arm == "oath" then
        pinOrdinary(plan)
        take(plan, "swap", "pick up Severed Oath while holding another active")
        plan.require("Severed Oath is held", function(player) return player:HasCollectible(oathId()), "held" end)
    else
        hold(plan, arm)
        take(plan, "swap", "swap actives onto an existing pedestal")
    end
    expectChoices(plan, "the old active dropped onto the pedestal gains nothing", "swap", 0)
    expectChoices(plan, "a pedestal that existed before stays as it was", "existing", 0)
    plan.act(function(_, ctx) ctx.new = spawn(Vector(0, -80), passive()) end)
    plan.wait(8)
    expectChoices(plan, "a pedestal created afterwards gains one", "new", 1)
end

-- While held, swapping actives drops the old one onto the pedestal it came
-- from; that pedestal never becomes a choice again (the user's second report).
cases.swap_while_held = function(plan, arm)
    plan.act(function(player)
        player:AddCollectible(CollectibleType.COLLECTIBLE_SCHOOLBAG, 0, false)
        player:AddCollectible(own(), 0, false, ActiveSlot.SLOT_PRIMARY)
        if arm == "birthright" then player:AddCollectible(spare(), 0, false, ActiveSlot.SLOT_SECONDARY) end
    end)
    hold(plan, arm, ActiveSlot.SLOT_SECONDARY)
    plan.require("both active slots are full", function(player)
        return player:GetActiveItem(ActiveSlot.SLOT_PRIMARY) == own() and player:GetActiveItem(ActiveSlot.SLOT_SECONDARY) > 0,
            "primary=" .. player:GetActiveItem(ActiveSlot.SLOT_PRIMARY) .. " secondary=" .. player:GetActiveItem(ActiveSlot.SLOT_SECONDARY)
    end)
    plan.act(function(_, ctx) ctx.swap = spawn(Vector(120, 0), pedestalActive()) end)
    plan.wait(8)
    expectChoices(plan, "a new active pedestal gains one", "swap", 1)
    -- Show only the active so the swap is certain; external rewrites stay authoritative.
    plan.act(function(_, ctx) find(ctx.swap):RemoveCollectibleCycle() end)
    plan.wait(2)
    take(plan, "swap", "swap actives while holding the item")
    expectChoices(plan, "the dropped active never becomes a choice", "swap", 0)
    if arm == "oath" then
        plan.require("Severed Oath is still held", function(player)
            return player:GetActiveItem(ActiveSlot.SLOT_SECONDARY) == oathId(), "secondary=" .. player:GetActiveItem(ActiveSlot.SLOT_SECONDARY)
        end)
    end
    -- Rerolling a pedestal that holds a dropped item: recorded for comparison only.
    plan.act(function(player) player:UseActiveItem(CollectibleType.COLLECTIBLE_D6, UseFlag.USE_NOANIM, -1) end)
    plan.wait(10)
    plan.note("D6 on the dropped item's pedestal", function(_, ctx)
        local p = find(ctx.swap)
        return p and string.format("arm=%s item=%d touched=%s choices=%d", ctx.arm, p.SubType, tostring(p.Touched),
            #p:GetCollectibleCycle()) or "no pedestal left"
    end)
end

-- A reroll makes a new pedestal, which gains one again.
cases.dice = function(plan, arm)
    hold(plan, arm)
    plan.act(function(_, ctx) ctx.new = spawn(Vector(0, -80), passive()) end)
    plan.wait(8)
    expectChoices(plan, "a pedestal created while held gains one", "new", 1)
    for roll = 1, 2 do
        plan.act(function(player) player:UseActiveItem(CollectibleType.COLLECTIBLE_D6, UseFlag.USE_NOANIM, -1) end)
        plan.wait(10)
        expectChoices(plan, "D6 " .. roll .. ": the rerolled pedestal has one", "new", 1)
    end
end

-- A Diplopia copy is a new pedestal of its own.
cases.copy = function(plan, arm)
    hold(plan, arm)
    plan.act(function(_, ctx) ctx.new = spawn(Vector(0, -80), passive()) end)
    plan.wait(8)
    expectChoices(plan, "a pedestal created while held gains one", "new", 1)
    plan.act(function(player, ctx)
        ctx.before = {}
        for _, p in ipairs(C.stock()) do ctx.before[C.anchor(p)] = true end
        player:UseActiveItem(CollectibleType.COLLECTIBLE_DIPLOPIA, UseFlag.USE_NOANIM, -1)
    end)
    plan.wait(10)
    plan.act(function(_, ctx)
        for _, p in ipairs(C.stock()) do
            if not ctx.before[C.anchor(p)] then ctx.copy = C.anchor(p) end
        end
    end)
    plan.require("Diplopia made a copy", function(_, ctx) return ctx.copy ~= nil, "copies=" .. #C.stock() end)
    expectChoices(plan, "the source keeps its one", "new", 1)
    expectChoices(plan, "the copy gains one of its own", "copy", 1)
    -- A copy shares its source's seed; record whether its own choice repeats the source's.
    plan.note("the copy's choice against the source's", function(_, ctx)
        local function ring(field)
            local p, ids = find(ctx[field]), {}
            if not p then return "gone" end
            ids[1] = p.SubType
            for _, id in ipairs(p:GetCollectibleCycle()) do ids[#ids + 1] = id end
            table.sort(ids)
            return table.concat(ids, ",")
        end
        return string.format("arm=%s source=[%s] copy=[%s]", ctx.arm, ring("new"), ring("copy"))
    end)
end

-- Nothing in the Death Certificate area gains a choice (the user's third report).
cases.death_certificate = function(plan, arm)
    hold(plan, arm)
    plan.require("native dimension evidence", function()
        return type(Game():GetLevel().GetDimension) == "function" or nil, "Level:GetDimension required"
    end)
    plan.act(function(player) player:UseActiveItem(CollectibleType.COLLECTIBLE_DEATH_CERTIFICATE, UseFlag.USE_NOANIM, -1) end)
    plan.waitUntil(function() return Game():GetLevel():GetDimension() == 2 end, 300, "Death Certificate entry")
    plan.wait(8)
    plan.act(function(player, ctx)
        local room = Game():GetRoom()
        for slot = 0, 7 do
            local door = room:GetDoor(slot)
            if door and door.TargetRoomIndex >= 0 then
                ctx.stock = door.TargetRoomIndex
                Game():StartRoomTransition(ctx.stock, Direction.NO_DIRECTION, RoomTransitionAnim.FADE, player, 2)
                return
            end
        end
        error("no stock room next to the Death Certificate entrance")
    end)
    plan.waitUntil(function(_, ctx)
        return Game():GetLevel():GetCurrentRoomIndex() == ctx.stock and RoomTransition.GetTransitionMode() == 0
    end, 180, "Death Certificate stock room")
    plan.wait(12)
    expectAll(plan, "Death Certificate items have no extra choice", 0)
end

-- Tainted Isaac: every pedestal already cycles between two items. Like
-- Birthright on a cycling source, the Oath stacks one more on the pedestals
-- it may reach and adds nothing anywhere else. Each arm is a fresh Tainted
-- Isaac run: "native" without the Oath (the control), "oath" with it.
local function oathGrants(p)
    local ok, save = pcall(ConchBlessing.SaveManager.TryGetNoRerollPickupSave, p)
    local state = ok and type(save) == "table" and save.severedOath or nil
    return type(state) == "table" and type(state.bonusItems) == "table" and #state.bonusItems or 0
end

local function taintedIsaac(plan, arm)
    local extra = arm == "oath" and 1 or 0
    plan.waitUntil(function(player)
        return player:Exists() and ConchBlessing.SaveManager.GetRunSave(player) ~= nil
    end, 60, "player and run save ready")
    plan.require("a single Tainted Isaac run", function(player)
        return Game():GetNumPlayers() == 1 and player:GetPlayerType() == PlayerType.PLAYER_ISAAC_B,
            "player type=" .. player:GetPlayerType()
    end)
    setup(plan, "tainted_isaac", arm)
    if arm == "oath" then hold(plan, arm) end
    travel(plan, "treasure", "first visit to the treasure room")
    expectAll(plan, "first-visit stock: Tainted Isaac's own choice" .. (extra > 0 and " plus one" or ""), 1 + extra)
    travel(plan, "origin", "leave the treasure room")
    travel(plan, "treasure", "come back")
    expectAll(plan, "a revisit adds nothing more", 1 + extra)
    plan.act(function(_, ctx)
        for _, p in ipairs(C.stock()) do p:Remove() end
        ctx.new = spawn(Vector(0, -80), passive())
    end)
    plan.wait(8)
    expectChoices(plan, "a pedestal created now", "new", 1 + extra)
    plan.act(function(player) player:UseActiveItem(CollectibleType.COLLECTIBLE_D6, UseFlag.USE_NOANIM, -1) end)
    plan.wait(10)
    expectChoices(plan, "after D6", "new", 1 + extra)
    plan.act(function(player, ctx)
        ctx.before = {}
        for _, p in ipairs(C.stock()) do ctx.before[C.anchor(p)] = true end
        player:UseActiveItem(CollectibleType.COLLECTIBLE_DIPLOPIA, UseFlag.USE_NOANIM, -1)
    end)
    plan.wait(10)
    plan.act(function(_, ctx)
        for _, p in ipairs(C.stock()) do
            if not ctx.before[C.anchor(p)] then ctx.copy = C.anchor(p) end
        end
    end)
    plan.require("Diplopia made a copy", function(_, ctx) return ctx.copy ~= nil, "copies=" .. #C.stock() end)
    expectChoices(plan, "the Diplopia copy", "copy", 1 + extra)
    -- Death Certificate: whatever the engine does for Tainted Isaac there, the Oath adds nothing.
    plan.act(function(player) player:UseActiveItem(CollectibleType.COLLECTIBLE_DEATH_CERTIFICATE, UseFlag.USE_NOANIM, -1) end)
    plan.waitUntil(function() return Game():GetLevel():GetDimension() == 2 end, 300, "Death Certificate entry")
    plan.wait(8)
    plan.act(function(player, ctx)
        local room = Game():GetRoom()
        for slot = 0, 7 do
            local door = room:GetDoor(slot)
            if door and door.TargetRoomIndex >= 0 then
                ctx.stock = door.TargetRoomIndex
                Game():StartRoomTransition(ctx.stock, Direction.NO_DIRECTION, RoomTransitionAnim.FADE, player, 2)
                return
            end
        end
        error("no stock room next to the Death Certificate entrance")
    end)
    plan.waitUntil(function(_, ctx)
        return Game():GetLevel():GetCurrentRoomIndex() == ctx.stock and RoomTransition.GetTransitionMode() == 0
    end, 180, "Death Certificate stock room")
    plan.wait(12)
    plan.note("Death Certificate pedestals for Tainted Isaac", function(_, ctx)
        local counts = {}
        for _, p in ipairs(C.stock()) do counts[#counts + 1] = tostring(#p:GetCollectibleCycle()) end
        return string.format("arm=%s extra choices per pedestal=[%s]", ctx.arm, table.concat(counts, ","))
    end)
    plan.check("the Oath adds nothing in the Death Certificate area", function(_, ctx)
        local granted, stock = 0, C.stock()
        for _, p in ipairs(stock) do granted = granted + oathGrants(p) end
        return #stock > 0 and granted == 0, label(ctx, string.format("%d pedestals, Oath grants=%d", #stock, granted))
    end)
end

-- Damocles adds an extra item pedestal (another item, its own seed) to each
-- new room. Measured 2026-10-28: Birthright gives the extra pedestal its own
-- choice too, although the wiki notes it does not cycle with Glitched Crown.
cases.damocles = function(plan, arm)
    plan.act(function(player) player:AddCollectible(CollectibleType.COLLECTIBLE_DAMOCLES_PASSIVE, 0, false) end)
    hold(plan, arm)
    travel(plan, "treasure", "first visit to the treasure room with Damocles")
    plan.note("Damocles pedestals", function(_, ctx)
        local rows = {}
        for _, p in ipairs(C.stock()) do
            rows[#rows + 1] = string.format("%d@seed=%s:choices=%d", p.SubType, tostring(p.InitSeed), #p:GetCollectibleCycle())
        end
        return "arm=" .. ctx.arm .. " " .. table.concat(rows, " ")
    end)
    plan.check("every pedestal, Damocles' extra one included, gains one", function(_, ctx)
        local one, other = 0, 0
        for _, p in ipairs(C.stock()) do
            if #p:GetCollectibleCycle() == 1 then one = one + 1 else other = other + 1 end
        end
        return one >= 2 and other == 0, label(ctx, string.format("pedestals with one extra=%d, other=%d", one, other))
    end)
end

-- Golden Items gives a golden pedestal its own Binge Eater rotation and
-- Morphs it every 30 frames. Recorded for both arms; the two must agree.
cases.golden_binge = function(plan, arm)
    plan.require("Golden Items golden pedestals", function()
        local gold = GoldenItems and GoldenItems.Pickup and GoldenItems.Pickup.GOLDEN_ITEM
        return (gold and type(gold.TurnItemGold) == "function") or nil, "Golden Items with TurnItemGold required"
    end)
    plan.act(function(player) player:AddCollectible(CollectibleType.COLLECTIBLE_BINGE_EATER, 0, false) end)
    hold(plan, arm)
    plan.act(function(_, ctx)
        ctx.new = spawn(Vector(0, -80), passive())
        GoldenItems.Pickup.GOLDEN_ITEM:TurnItemGold(find(ctx.new), false)
    end)
    for second = 1, 3 do
        plan.wait(30)
        plan.note("golden Binge Eater pedestal after " .. second .. "s", function(_, ctx)
            local p = find(ctx.new)
            if not p then return "arm=" .. ctx.arm .. " pedestal gone" end
            local ids = {}
            for _, id in ipairs(p:GetCollectibleCycle()) do ids[#ids + 1] = id end
            return string.format("arm=%s shown=%d extra=[%s]", ctx.arm, p.SubType, table.concat(ids, ","))
        end)
    end
end

local order = {"first_visit", "seen_room", "mid_room", "swap_while_held", "dice", "copy", "death_certificate",
    "damocles", "golden_binge"}
for _, case in ipairs(order) do
    for _, arm in ipairs({"birthright", "oath"}) do
        M.commands[#M.commands + 1] = S.add("SEVERED_OATH", "birthright_" .. case .. "_" .. arm,
            {conditions = true, birthright_parity = true}, function(plan)
                setup(plan, case, arm)
                cases[case](plan, arm)
            end)
    end
end

for _, arm in ipairs({"native", "oath"}) do
    local name = "combo_tainted_isaac_" .. arm
    local command = "conch_test severed_oath " .. name
    S.rows[#S.rows + 1] = {key = "SEVERED_OATH", name = name, command = command,
        groups = {conditions = true, birthright_parity = true}, build = function(plan) taintedIsaac(plan, arm) end}
    require("scripts.dev.test_bench").register({command = command, tag = "ItemTest:SEVERED_OATH",
        duration = "a fresh Tainted Isaac run", restartCommand = "restart 21", finalRestartCommand = "restart 0",
        resetReason = "Tainted Isaac comparison visits rooms and consumes pools; each arm requires a fresh run",
        cleanup = H.cleanup, build = function(plan)
            plan.section("SEVERED_OATH / " .. name)
            taintedIsaac(plan, arm)
        end})
    M.commands[#M.commands + 1] = command
end

return M
