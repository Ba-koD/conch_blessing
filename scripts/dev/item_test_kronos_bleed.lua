local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- `cb test kronos bleed_probe` (a measurement, run by name only): how long a
-- REPENTOGON Entity:AddBleeding(source, duration) bleed really lasts. Kronos's
-- absorbed Mom's Razor asks for 150 updates, while the REPENTOGON docs say "The
-- Duration has a maximum of 4 seconds". Each requested duration gets its own
-- pinned target, plus one target with no bleed as the control. DIAG lines report
-- how many updates FLAG_BLEED_OUT stayed set, when the target last lost HP and
-- how much it lost. Nothing here is a PASS for Kronos.
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")

local DURATIONS = { 0, 30, 90, 120, 121, 150, 300 } -- 0 is the control: no bleed asked
local WATCH_UPDATES = 360

local watch = nil -- { rows = { { npc, ask, pos, hp, start, flagUpdates, flagLast, hurtLast, ok } } }

ConchBlessing:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    if not watch then return end
    local frame = Game():GetFrameCount()
    for _, row in ipairs(watch.rows) do
        local npc = row.npc
        if npc and npc:Exists() then
            npc.Position, npc.Velocity = row.pos, Vector.Zero
            if row.start then
                if npc:HasEntityFlags(EntityFlag.FLAG_BLEED_OUT) then
                    row.flagUpdates = row.flagUpdates + 1
                    row.flagLast = frame
                end
                if npc.HitPoints < row.hp - 0.0001 then row.hurtLast = frame end
                row.hp = npc.HitPoints
            end
        end
    end
end)

S.add("KRONOS", "bleed_probe", {}, function(plan)
    plan.require("REPENTOGON's Entity:AddBleeding", function(player)
        return type(player.AddBleeding) == "function" or nil, "needs REPENTOGON's Entity:AddBleeding"
    end)
    plan.act(function(player, ctx)
        local room = Game():GetRoom()
        local center = room:GetCenterPos()
        player.Position = center + Vector(0, 120)
        ctx.rows = {}
        for i, ask in ipairs(DURATIONS) do
            local npc = H.target(player, true)
            local pos = center + Vector((i - (#DURATIONS + 1) / 2) * 60, -80)
            npc.Position = pos
            ctx.rows[#ctx.rows + 1] = { npc = npc, ask = ask, pos = pos, flagUpdates = 0 }
        end
        ctx.cleanupFns = ctx.cleanupFns or {}
        ctx.cleanupFns[#ctx.cleanupFns + 1] = function()
            watch = nil
            for _, row in ipairs(ctx.rows or {}) do
                if row.npc and row.npc:Exists() then row.npc:Remove() end
            end
        end
        watch = { rows = ctx.rows }
    end)
    plan.waitUntil(function(_, ctx)
        for _, row in ipairs(ctx.rows) do
            local ready, why = H.targetReady(row.npc)
            if not ready then return false, why end
        end
        return true
    end, 60, "every target is ready")
    plan.act(function(player, ctx)
        local frame = Game():GetFrameCount()
        for _, row in ipairs(ctx.rows) do
            row.hp, row.hp0, row.start = row.npc.HitPoints, row.npc.HitPoints, frame
            if row.ask > 0 then
                row.ok = pcall(row.npc.AddBleeding, row.npc, EntityRef(player), row.ask)
            end
        end
    end)
    plan.wait(WATCH_UPDATES)
    for i, ask in ipairs(DURATIONS) do
        local label = ask == 0 and "control, no bleed" or string.format("AddBleeding(%d)", ask)
        plan.note(label, function(_, ctx)
            local row = ctx.rows[i]
            local function since(frame) return frame and (frame - row.start) or -1 end
            return string.format("call ok %s; FLAG_BLEED_OUT on %d updates, last at +%d; last HP loss at +%d; HP lost %.2f",
                tostring(row.ok), row.flagUpdates, since(row.flagLast), since(row.hurtLast), row.hp0 - row.hp)
        end)
    end
end)
S.rows[#S.rows].manual = true
