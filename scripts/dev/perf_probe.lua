local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- Dev-only: `conch_test perf` (by name only) measures what this mod costs. It
-- times every handler this mod registered (callback_profiler) through four
-- ten-second windows in a fresh run: Isaac standing in the start room with none
-- of our items; the same with ten harmless, sturdy enemies and Isaac firing at them;
-- then holding every released passive, familiar and trinket of ours, with and
-- without the enemies. Each window logs this mod's milliseconds per update (all
-- handlers, render ones included) and its heaviest handlers. Measurements, not
-- checks. The bench's own progress text and the profiler's wrapper (about a
-- microsecond a call) are counted too.
local TestBench = require("scripts.dev.test_bench")
local Profiler = require("scripts.dev.callback_profiler")

local WINDOW = 300      -- updates per window (ten seconds)
local TOP = 16          -- handlers listed per window
local ENEMIES = 10

local function released(kind)
    local list = {}
    for key, row in pairs(ConchBlessing.ItemData or {}) do
        local id = row.id or -1
        if id > 0 and row.WorkingNow ~= true and row.console ~= true and row.hidden ~= true then
            if (kind == "trinket") == (row.type == "trinket") and row.type ~= "active" then
                list[#list + 1] = { key = key, id = id }
            end
        end
    end
    table.sort(list, function(a, b) return a.key < b.key end)
    return list
end

local function spawnEnemies(ctx)
    local room = Game():GetRoom()
    local tl, br = room:GetTopLeftPos(), room:GetBottomRightPos()
    ctx.enemies = {}
    for i = 1, ENEMIES do
        local x = tl.X + 40 + (br.X - tl.X - 80) * (i - 1) / (ENEMIES - 1)
        -- like the benches' target (item_test_support): a maggot neither shoots
        -- nor spawns anything, and no contact damage keeps Isaac alive
        local npc = Isaac.Spawn(EntityType.ENTITY_MAGGOT, 0, 0, Vector(x, tl.Y + 40), Vector.Zero, nil):ToNPC()
        if npc then
            npc:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
            npc.CollisionDamage = 0
            npc.MaxHitPoints, npc.HitPoints = 100000, 100000
            ctx.enemies[#ctx.enemies + 1] = EntityPtr(npc)
        end
    end
end

local function removeEnemies(ctx)
    for _, ref in ipairs(ctx.enemies or {}) do
        local npc = ref.Ref
        if npc and npc:Exists() then npc:Remove() end
    end
    ctx.enemies = nil
end

-- One window: start the profiler, let it run (firing a tear every 8 updates
-- at the enemies when asked), then log the totals and the heaviest handlers.
local function window(plan, label, firing, tables)
    plan.act(function(_, ctx)
        ctx.handlers = tables and Profiler.startTables(tables()) or Profiler.start()
        ctx.updates = 0
    end)
    plan.waitUntil(function(player, ctx)
        ctx.updates = ctx.updates + 1
        if firing and ctx.updates % 8 == 0 then
            player:FireTear(player.Position, Vector(0, -12), false, true, false)
        end
        return ctx.updates >= WINDOW, ctx.updates .. " updates"
    end, WINDOW + 5, label)
    plan.act(function(_, ctx)
        Profiler.stop()
        local top, total, clockName = Profiler.report(TOP)
        ctx.report = { top = top, total = total, clock = clockName }
    end)
    plan.note(label, function(_, ctx)
        local r = ctx.report
        return string.format("this mod %.3f ms per update over %d updates (%d handlers wrapped, %s); %d entities, %d players",
            r.total / ctx.updates, ctx.updates, ctx.handlers or 0, r.clock, #Isaac.GetRoomEntities(), Game():GetNumPlayers())
    end)
    for i = 1, TOP do
        plan.note(label .. " #" .. i, function(_, ctx)
            local row = ctx.report.top[i]
            if not row then return "-" end
            return string.format("%.4f ms/update, %d calls (%.2f us/call): %s", row.ms / ctx.updates, row.calls,
                row.calls > 0 and row.ms * 1000 / row.calls or 0, row.label)
        end)
    end
end

local function build(plan)
    plan.require("callback profiler available", function()
        return Profiler.available() or nil, "needs REPENTOGON's Isaac.GetCallbacks"
    end)
    plan.wait(30)
    window(plan, "plain", false)
    plan.act(function(_, ctx) spawnEnemies(ctx) end)
    plan.wait(30)
    window(plan, "enemies", true)
    plan.act(function(player, ctx)
        ctx.given = {}
        for _, row in ipairs(released("collectible")) do
            player:AddCollectible(row.id, 0, false)
            ctx.given[#ctx.given + 1] = row.key
        end
        if type(player.AddSmeltedTrinket) == "function" then
            for _, row in ipairs(released("trinket")) do
                player:AddSmeltedTrinket(row.id, false)
                ctx.given[#ctx.given + 1] = row.key
            end
        end
    end)
    plan.note("given", function(_, ctx) return #ctx.given .. " items: " .. table.concat(ctx.given, ",") end)
    plan.wait(60)
    window(plan, "all items, enemies", true)
    plan.act(function(_, ctx) removeEnemies(ctx) end)
    plan.wait(30)
    window(plan, "all items, empty room", false)
    -- inside the heaviest item modules: their namespace functions, inclusive
    window(plan, "item functions", false, function()
        return { kronos = ConchBlessing.kronos, dragon = ConchBlessing.dragon,
            neglect = ConchBlessing.hemispatialneglect, realeyes = ConchBlessing.realeyes }
    end)
end

TestBench.register({ command = "conch_test perf", tag = "PerfProbe", duration = "about 45 seconds",
    restartCommand = "restart 0", build = build,
    cleanup = function(ctx) Profiler.stop(); removeEnemies(ctx) end })

return {}
