local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 선녀 (Seonnyeo): the lifecycle contract and its cases. Every check reads
-- the maidens really in the room, their real positions and the player's real
-- fire rate (30 / (MaxFireDelay + 1)) against the rate measured without the
-- item; the expected rate is 1.3 per light the player stands in.
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")
local C = {}

local function seonnyeo() return ConchBlessing.seonnyeo end

local function maidens(player)
    local list, v = {}, seonnyeo()._test.variant()
    if not v then return list end
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local fam = entity.Type == EntityType.ENTITY_FAMILIAR and entity.Variant == v and entity:ToFamiliar()
        if fam and fam:Exists() and fam.Player and GetPtrHash(fam.Player) == GetPtrHash(player) then
            list[#list + 1] = fam
        end
    end
    return list
end

local function tears(player) return 30 / (player.MaxFireDelay + 1) end

local function give(player, id, n)
    while player:GetCollectibleNum(id) < n do player:AddCollectible(id, 0, false) end
    while player:GetCollectibleNum(id) > n do player:RemoveCollectible(id) end
end

local function requireModule(plan)
    plan.require("선녀 module and its familiar ready", function()
        local m = seonnyeo()
        return m and m._test and m._test.itemId() > 0 and m._test.variant() ~= nil and true or false,
            "module or variant missing"
    end)
end

-- Holds every maiden of the player at `offset` from them for this update;
-- called each update of a measured window so her roaming cannot carry her
-- out of (or into) the light while it is measured.
local function pin(player, offset)
    for _, fam in ipairs(maidens(player)) do
        fam.Position = player.Position + offset
        fam.Velocity = Vector.Zero
    end
end

-- Pins the maidens at `offset()` (read when the case runs) for a few updates,
-- then compares the fire rate with the rate without the item times 1.3^`lights`.
local function expectRate(plan, label, offset, lights)
    plan.act(function(player, ctx) ctx.pin = offset() end)
    for _ = 1, 4 do
        plan.act(function(player, ctx) pin(player, ctx.pin) end)
        plan.wait(1)
    end
    plan.check(label, function(player, ctx)
        -- where she really was for the stat, before pinning her again
        local seen = {}
        for _, fam in ipairs(maidens(player)) do
            seen[#seen + 1] = string.format("%.1f", fam.Position:Distance(player.Position) - seonnyeo().data.radius)
        end
        local counted = seonnyeo().lightsOver(player, maidens(player))
        pin(player, ctx.pin)
        local want = ctx.baseTears * seonnyeo().data.tears ^ lights
        return H.near(tears(player), want), string.format("tears %.4f, expected %.4f (base %.4f, %d light(s)); "
            .. "maidens past the edge by [%s], lights counted %d", tears(player), want, ctx.baseTears, lights,
            table.concat(seen, ","), counted)
    end)
end

C.SEONNYEO = { stage = function(plan, _, n)
    plan.check("one maiden per copy", function(player)
        return #maidens(player) == n, string.format("maidens=%d copies=%d", #maidens(player), n)
    end)
    plan.check("no maiden is one of the owner's followers", function(player)
        for _, fam in ipairs(maidens(player)) do
            if fam.IsFollower then return false, "IsFollower was true" end
        end
        return true, "none follow"
    end)
end }

-- Her light: x1.3 inside it, nothing outside, two lights x1.69, and the
-- multiplier gone once the item is.
S.add("SEONNYEO", "light", {}, function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        H.refresh(player)
        ctx.baseTears = tears(player)
        give(player, id, 1)
    end)
    plan.waitUntil(function(player) return #maidens(player) == 1, "maidens=" .. #maidens(player) end, 30, "the maiden appears")
    expectRate(plan, "standing in her light: tears x1.3", function() return Vector(20, 0) end, 1)
    -- Pinned once an update, she still moves on her own between the pin and
    -- the moment the light is counted: up to about 13 units either way
    -- (measured 2026-11-13: pinned 6 outside the edge she was counted 1.2
    -- inside it, and pinned 4 inside she was 4.2 outside). The edge is tested
    -- 20 units either side of it.
    expectRate(plan, "near the inside edge of her light: still x1.3",
        function() return Vector(seonnyeo().data.radius - 20, 0) end, 1)
    expectRate(plan, "just outside it: no change", function() return Vector(seonnyeo().data.radius + 20, 0) end, 0)
    plan.act(function(player) give(player, id, 2) end)
    plan.waitUntil(function(player) return #maidens(player) == 2, "maidens=" .. #maidens(player) end, 30, "a second maiden appears")
    expectRate(plan, "in two lights: tears x1.69", function() return Vector(10, 0) end, 2)
    plan.act(function(player) give(player, id, 0) end)
    plan.waitUntil(function(player) return #maidens(player) == 0, "maidens=" .. #maidens(player) end, 30, "the maidens leave")
    plan.wait(3)
    plan.check("without the item the fire rate is back", function(player, ctx)
        return H.near(tears(player), ctx.baseTears), string.format("tears %.4f, base %.4f", tears(player), ctx.baseTears)
    end)
end)

-- Her light hurts the enemies in it: each tick deals her owner's tears
-- (shots a second), an enemy outside it takes nothing, and BFFS widens the
-- light but leaves each tick as it is (Succubus's 2.5 stays 2.5 with BFFS).
-- Measured on a real enemy's HP over three ticks.
-- The bench builds its windows before the module is read (offline too), so
-- it carries her tick itself and requires the module to agree.
local TICK = 7

-- `offset()` is where the maiden is held from the enemy (read when it runs).
local function lightWindow(plan, label, offset, factor)
    plan.act(function(player, ctx)
        local npc = ctx.lightTarget.Ref
        ctx.spot = npc and npc.Position
        local o = offset()
        ctx.at = function() return ctx.spot + o end
    end)
    local function hold(player, ctx)
        local npc = ctx.lightTarget.Ref
        if npc then npc.Position, npc.Velocity = ctx.spot, Vector.Zero end
        for _, fam in ipairs(maidens(player)) do fam.Position, fam.Velocity = ctx.at(), Vector.Zero end
    end
    -- line the window up with a tick: wait until a maiden is about to strike
    plan.waitUntil(function(player, ctx)
        hold(player, ctx)
        local fam = maidens(player)[1]
        return fam and fam.FrameCount % seonnyeo().data.tick == seonnyeo().data.tick - 1 or false, "aligning"
    end, 30, "a tick boundary")
    plan.act(function(_, ctx) ctx.hp = ctx.lightTarget.Ref and ctx.lightTarget.Ref.HitPoints end)
    for _ = 1, 3 * TICK do
        plan.act(hold)
        plan.wait(1)
    end
    plan.check(label, function(player, ctx)
        local npc = ctx.lightTarget.Ref
        local lost = npc and ctx.hp and ctx.hp - npc.HitPoints or -1
        local want = factor * 3 * tears(player) * seonnyeo().data.perTears
        return math.abs(lost - want) <= 0.01 * math.max(1, want),
            string.format("HP lost %.3f over three ticks, expected %.3f (tears %.3f)", lost, want, tears(player))
    end)
end

S.add("SEONNYEO", "light_damage", {}, function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        give(player, id, 1)
        local npc = H.target(player, true)
        npc.HitPoints, npc.MaxHitPoints = 1000, 1000
        ctx.lightTarget = EntityPtr(npc)
        ctx.cleanupFns = ctx.cleanupFns or {}
        table.insert(ctx.cleanupFns, function() if ctx.lightTarget.Ref then ctx.lightTarget.Ref:Remove() end end)
    end)
    plan.waitUntil(function(player, ctx)
        return #maidens(player) == 1 and H.targetReady(ctx.lightTarget.Ref) or false, "maiden and target"
    end, 60, "the maiden and a harmless enemy are ready")
    plan.require("her tick is the bench's tick", function()
        return seonnyeo().data.tick == TICK, "tick " .. seonnyeo().data.tick
    end)
    lightWindow(plan, "an enemy in her light loses her owner's tears each tick", function() return Vector.Zero end, 1)
    lightWindow(plan, "an enemy outside her light loses nothing",
        function() return Vector(seonnyeo().data.radius + 30, 0) end, 0)
    plan.act(function(player) player:AddCollectible(CollectibleType.COLLECTIBLE_BFFS, 0, false) end)
    plan.wait(2)
    lightWindow(plan, "with BFFS each tick deals the same, as Succubus's does", function() return Vector.Zero end, 1)
    plan.act(function(player)
        player:RemoveCollectible(CollectibleType.COLLECTIBLE_BFFS)
        give(player, id, 0)
    end)
    plan.wait(4)
end)

-- BFFS works as Succubus's does (EID: the damaging aura grows, the
-- damage-up aura does not): a spot just past the plain edge gets no tears
-- either way, but an enemy there is hurt only with BFFS.
S.add("SEONNYEO", "bffs", {}, function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        H.refresh(player)
        ctx.baseTears = tears(player)
        give(player, id, 1)
        local npc = H.target(player, true)
        npc.HitPoints, npc.MaxHitPoints = 1000, 1000
        ctx.lightTarget = EntityPtr(npc)
        ctx.cleanupFns = ctx.cleanupFns or {}
        table.insert(ctx.cleanupFns, function() if ctx.lightTarget.Ref then ctx.lightTarget.Ref:Remove() end end)
    end)
    plan.waitUntil(function(player, ctx)
        return #maidens(player) == 1 and H.targetReady(ctx.lightTarget.Ref) or false, "maiden and target"
    end, 60, "the maiden and a harmless enemy are ready")
    local function past() return Vector(seonnyeo().data.radius + 12, 0) end
    expectRate(plan, "without BFFS a spot past the plain edge gets no tears", past, 0)
    lightWindow(plan, "without BFFS an enemy past the plain edge is not hurt", past, 0)
    plan.act(function(player) player:AddCollectible(CollectibleType.COLLECTIBLE_BFFS, 0, false) end)
    plan.wait(2)
    expectRate(plan, "with BFFS the same spot still gets no tears", past, 0)
    lightWindow(plan, "with BFFS an enemy there is hurt each tick", past, 1)
    plan.act(function(player)
        player:RemoveCollectible(CollectibleType.COLLECTIBLE_BFFS)
        give(player, id, 0)
    end)
    plan.wait(4)
end, { "bffs" })

-- Kronos absorbs her like Succubus: her light stays on its holder. No
-- maiden is left in the room; the holder's tears are x1.3 wherever they stand
-- and an enemy near them loses their tears each tick, one far away nothing.
S.add("SEONNYEO", "kronos", {}, function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        H.refresh(player)
        ctx.baseTears = tears(player)
        give(player, id, 1)
        player:AddCollectible(ConchBlessing.ItemData.KRONOS.id, 0, false)
        local npc = H.target(player, true)
        npc.HitPoints, npc.MaxHitPoints = 1000, 1000
        ctx.lightTarget = EntityPtr(npc)
        ctx.cleanupFns = ctx.cleanupFns or {}
        table.insert(ctx.cleanupFns, function() if ctx.lightTarget.Ref then ctx.lightTarget.Ref:Remove() end end)
    end)
    plan.waitUntil(function(player)
        return seonnyeo().absorbed(player) >= 1 and player:GetCollectibleNum(id) == 0 and #maidens(player) == 0,
            "absorbed=" .. seonnyeo().absorbed(player) .. " maidens=" .. #maidens(player)
    end, 120, "Kronos absorbs her")
    plan.wait(4)
    plan.check("her light stays on the holder: tears x1.3", function(player, ctx)
        local want = ctx.baseTears * seonnyeo().data.tears
        return H.near(tears(player), want), string.format("tears %.4f, expected %.4f", tears(player), want)
    end)
    local function window(label, near, factor)
        plan.act(function(player, ctx)
            ctx.spot = player.Position + Vector(near and 40 or seonnyeo().data.radius + 40, 0)
        end)
        plan.waitUntil(function(player, ctx)
            local npc = ctx.lightTarget.Ref
            if npc then npc.Position, npc.Velocity = ctx.spot, Vector.Zero end
            return player.FrameCount % TICK == TICK - 1, "aligning"
        end, 30, "a tick boundary")
        plan.act(function(_, ctx) ctx.hp = ctx.lightTarget.Ref and ctx.lightTarget.Ref.HitPoints end)
        for _ = 1, 3 * TICK do
            plan.act(function(_, ctx)
                local npc = ctx.lightTarget.Ref
                if npc then npc.Position, npc.Velocity = ctx.spot, Vector.Zero end
            end)
            plan.wait(1)
        end
        plan.check(label, function(player, ctx)
            local npc = ctx.lightTarget.Ref
            local lost = npc and ctx.hp and ctx.hp - npc.HitPoints or -1
            local want = factor * 3 * tears(player) * seonnyeo().data.perTears
            return math.abs(lost - want) <= 0.01 * math.max(1, want),
                string.format("HP lost %.3f over three ticks, expected %.3f (tears %.3f)", lost, want, tears(player))
        end)
    end
    window("an enemy beside the holder loses their tears each tick", true, 1)
    window("an enemy beyond the light loses nothing", false, 0)
    plan.act(function(player) player:RemoveCollectible(ConchBlessing.ItemData.KRONOS.id) end)
    plan.waitUntil(function(player)
        return seonnyeo().absorbed(player) == 0 and #maidens(player) == 1,
            "absorbed=" .. seonnyeo().absorbed(player) .. " maidens=" .. #maidens(player)
    end, 120, "losing Kronos gives her back")
    plan.check("losing Kronos gives her back as a maiden", function(player)
        return player:GetCollectibleNum(id) == 1, "copies " .. player:GetCollectibleNum(id)
    end)
    plan.act(function(player) give(player, id, 0) end)
    plan.wait(4)
end, { "kronos" })

-- She roams the room on her own like Succubus: away from her owner, inside
-- the walls, at a steady pace.
S.add("SEONNYEO", "roam", {}, function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        give(player, id, 1)
        ctx.home = player.Position
        ctx.samples, ctx.far, ctx.outside, ctx.fastest, ctx.slowest, ctx.steady = 0, 0, 0, 0, math.huge, 0
    end)
    plan.waitUntil(function(player) return #maidens(player) == 1 end, 30, "the maiden appears")
    plan.waitUntil(function(player, ctx)
        local fam = maidens(player)[1]
        if fam then
            ctx.samples = ctx.samples + 1
            ctx.far = math.max(ctx.far, fam.Position:Distance(ctx.home))
            if not Game():GetRoom():IsPositionInRoom(fam.Position, 0) then ctx.outside = ctx.outside + 1 end
            local speed = fam.Velocity:Length()
            ctx.fastest = math.max(ctx.fastest, speed)
            ctx.slowest = math.min(ctx.slowest, speed)
            if math.abs(speed - seonnyeo().data.speed) < 0.15 then ctx.steady = ctx.steady + 1 end
        end
        return ctx.samples >= 300, "samples=" .. ctx.samples
    end, 330, "she drifts for ten seconds")
    plan.check("she drifts away from her owner and stays inside the walls", function(player, ctx)
        return ctx.far >= 120 and ctx.outside == 0 and player.Position:Distance(ctx.home) < 1,
            string.format("farthest %.0f from the owner, %d samples outside", ctx.far, ctx.outside)
    end)
    plan.check("at Succubus's pace, slowing only to turn", function(_, ctx)
        local speed = seonnyeo().data.speed
        return math.abs(ctx.fastest - speed) < 0.15 and ctx.steady >= 0.8 * ctx.samples,
            string.format("speed %.2f-%.2f, %d of %d updates at %.2f", ctx.slowest, ctx.fastest, ctx.steady,
                ctx.samples, speed)
    end)
    plan.act(function(player) give(player, id, 0) end)
    plan.wait(4)
    plan.section("SEONNYEO / roam", "she drifts about the room upright, silk and hem swaying, in a gold halo")
end)

-- Measurement only (run by name): how the real vanilla Succubus moves, so
-- 선녀 can move the same way. Records its position every update for twenty
-- seconds in the start room and reports its speed, its headings, where it
-- turns (how far from the walls) and whether it turns anywhere else.
S.add("SEONNYEO", "succubus_probe", {}, function(plan)
    plan.act(function(player, ctx)
        player:AddCollectible(CollectibleType.COLLECTIBLE_SUCCUBUS, 0, false)
        ctx.track = {}
    end)
    plan.waitUntil(function()
        return #Isaac.FindByType(EntityType.ENTITY_FAMILIAR, FamiliarVariant.SUCCUBUS) > 0
    end, 30, "the Succubus appears")
    plan.act(function(player, ctx)
        local fam = Isaac.FindByType(EntityType.ENTITY_FAMILIAR, FamiliarVariant.SUCCUBUS)[1]
        ctx.ref = EntityPtr(fam)
        ctx.spawnOffset = fam.Position - player.Position
    end)
    plan.waitUntil(function(_, ctx)
        local fam = ctx.ref.Ref
        if fam then ctx.track[#ctx.track + 1] = { p = fam.Position, v = fam.Velocity } end
        return #ctx.track >= 600, "samples=" .. #ctx.track
    end, 640, "twenty seconds of its path")
    plan.note("Succubus path", function(_, ctx)
        local room = Game():GetRoom()
        local tl, br = room:GetTopLeftPos(), room:GetBottomRightPos()
        local steps, turns, angles = {}, {}, {}
        local lo, hi, sum = math.huge, 0, 0
        for i = 2, #ctx.track do
            local d = ctx.track[i].p - ctx.track[i - 1].p
            local speed = d:Length()
            lo, hi, sum = math.min(lo, speed), math.max(hi, speed), sum + speed
            steps[#steps + 1] = d
            if speed > 0.05 then
                local a = math.floor(d:GetAngleDegrees() / 5 + 0.5) * 5
                angles[a] = (angles[a] or 0) + 1
            end
            local prev = steps[#steps - 1]
            if prev and prev:Length() > 0.05 and speed > 0.05 then
                local turn = math.abs(((d:GetAngleDegrees() - prev:GetAngleDegrees() + 540) % 360) - 180)
                if turn > 10 then
                    local p = ctx.track[i].p
                    local wall = math.min(p.X - tl.X, br.X - p.X, p.Y - tl.Y, br.Y - p.Y)
                    turns[#turns + 1] = string.format("@%d %.0fdeg wall %.0f", i, turn, wall)
                end
            end
        end
        local list = {}
        for a, n in pairs(angles) do list[#list + 1] = string.format("%d:%d", a, n) end
        table.sort(list)
        return string.format("spawn offset (%.0f, %.0f); speed %.2f-%.2f avg %.2f; headings {%s}; turns %d [%s]",
            ctx.spawnOffset.X, ctx.spawnOffset.Y, lo, hi, sum / math.max(1, #steps), table.concat(list, " "),
            #turns, table.concat(turns, ", "))
    end)
    plan.note("Succubus samples (every 10th: position, velocity)", function(_, ctx)
        local parts = {}
        for i = 1, #ctx.track, 10 do
            local t = ctx.track[i]
            parts[#parts + 1] = string.format("%d:(%.0f,%.0f|%.2f,%.2f)", i, t.p.X, t.p.Y, t.v.X, t.v.Y)
        end
        return table.concat(parts, " ")
    end)
    -- its aura on a harmless enemy held in its middle, then with BFFS
    for _, bffs in ipairs({ false, true }) do
        plan.act(function(player, ctx)
            if bffs then player:AddCollectible(CollectibleType.COLLECTIBLE_BFFS, 0, false) end
            local npc = ctx.npc and ctx.npc.Ref
            if not npc then
                npc = H.target(player, true)
                npc.HitPoints, npc.MaxHitPoints = 1000, 1000
                ctx.npc = EntityPtr(npc)
                ctx.cleanupFns = ctx.cleanupFns or {}
                table.insert(ctx.cleanupFns, function() if ctx.npc.Ref then ctx.npc.Ref:Remove() end end)
            end
            ctx.hits = {}
            ctx.lastHp = npc.HitPoints
            ctx.frame = 0
        end)
        plan.waitUntil(function(player, ctx)
            local fam, npc = ctx.ref.Ref, ctx.npc.Ref
            if not fam or not npc then return false, "lost" end
            npc.Position, npc.Velocity = fam.Position, Vector.Zero
            ctx.frame = ctx.frame + 1
            if npc.HitPoints < ctx.lastHp - 1e-4 then
                ctx.hits[#ctx.hits + 1] = { f = ctx.frame, d = ctx.lastHp - npc.HitPoints }
            end
            ctx.lastHp = npc.HitPoints
            return ctx.frame >= 150, "frames=" .. ctx.frame
        end, 170, bffs and "five seconds of its aura with BFFS" or "five seconds of its aura")
        plan.note(bffs and "Succubus aura with BFFS" or "Succubus aura", function(player, ctx)
            local parts, gaps = {}, {}
            for i, h in ipairs(ctx.hits) do
                parts[#parts + 1] = string.format("%d:%.2f", h.f, h.d)
                if i > 1 then gaps[#gaps + 1] = tostring(h.f - ctx.hits[i - 1].f) end
            end
            return string.format("player damage %.2f, tears %.2f; %d hits [%s]; gaps [%s]", player.Damage, tears(player),
                #ctx.hits, table.concat(parts, " "), table.concat(gaps, ","))
        end)
    end
    plan.act(function(player)
        player:RemoveCollectible(CollectibleType.COLLECTIBLE_BFFS)
        player:RemoveCollectible(CollectibleType.COLLECTIBLE_SUCCUBUS)
    end)
    plan.wait(4)
end)
S.rows[#S.rows].manual = true

-- Measurement only (run by name): what Kronos holding six absorbed Succubi
-- costs next to six absorbed 선녀, with harmless enemies in the room. Each
-- window logs this mod's milliseconds per update and its heaviest handlers
-- (callback_profiler), the process's CPU time per update (engine included),
-- and for 선녀 the time inside her module's and Kronos's functions.
local Profiler = require("scripts.dev.callback_profiler")
local PERF_WINDOW, PERF_TOP, PERF_COPIES = 300, 10, 6

local function perfWindow(plan, label, tables)
    plan.act(function(_, ctx)
        ctx.handlers = tables and Profiler.startTables(tables()) or Profiler.start()
        ctx.updates, ctx.cpu0 = 0, os.clock()
    end)
    plan.waitUntil(function(_, ctx)
        ctx.updates = ctx.updates + 1
        return ctx.updates >= PERF_WINDOW, ctx.updates .. " updates"
    end, PERF_WINDOW + 5, label)
    plan.act(function(_, ctx)
        ctx.cpu = (os.clock() - ctx.cpu0) * 1000 / math.max(1, ctx.updates)
        Profiler.stop()
        local top, total = Profiler.report(PERF_TOP)
        ctx.report = { top = top, total = total }
    end)
    plan.note(label, function(_, ctx)
        return string.format("this mod %.3f ms per update, process CPU %.2f ms per update; %d entities",
            ctx.report.total / ctx.updates, ctx.cpu, #Isaac.GetRoomEntities())
    end)
    for i = 1, PERF_TOP do
        plan.note(label .. " #" .. i, function(_, ctx)
            local row = ctx.report.top[i]
            if not row then return "-" end
            return string.format("%.4f ms/update, %d calls (%.2f us/call): %s", row.ms / ctx.updates, row.calls,
                row.calls > 0 and row.ms * 1000 / row.calls or 0, row.label)
        end)
    end
end

local function absorbAll(plan, id, label)
    plan.act(function(player)
        for _ = 1, PERF_COPIES do player:AddCollectible(id, 0, false) end
    end)
    plan.waitUntil(function(player)
        local n = ConchBlessing.kronos._getEffectCount(player, id)
        return n >= PERF_COPIES and player:GetCollectibleNum(id) == 0, "absorbed=" .. n
    end, 600, "Kronos absorbs six " .. label)
    plan.wait(30)
end

S.add("SEONNYEO", "kronos_perf", {}, function(plan, id)
    requireModule(plan)
    plan.require("callback profiler available", function()
        return Profiler.available() or nil, "needs REPENTOGON's Isaac.GetCallbacks"
    end)
    plan.act(function(player, ctx)
        player:AddCollectible(ConchBlessing.ItemData.KRONOS.id, 0, false)
        ctx.targets = {}
        for i = 1, 5 do
            local npc = H.target(player, true)
            npc.Position = player.Position + Vector(-120 + 60 * i, -60)
            ctx.targets[i] = EntityPtr(npc)
        end
        ctx.cleanupFns = ctx.cleanupFns or {}
        table.insert(ctx.cleanupFns, function()
            Profiler.stop()
            for _, ref in ipairs(ctx.targets) do if ref.Ref then ref.Ref:Remove() end end
        end)
    end)
    plan.wait(30)
    perfWindow(plan, "Kronos alone")
    absorbAll(plan, CollectibleType.COLLECTIBLE_SUCCUBUS, "Succubi")
    perfWindow(plan, "Kronos + 6 Succubus")
    plan.act(function(player)
        player:RemoveCollectible(ConchBlessing.ItemData.KRONOS.id)
    end)
    plan.wait(30)
    plan.act(function(player)
        while player:GetCollectibleNum(CollectibleType.COLLECTIBLE_SUCCUBUS) > 0 do
            player:RemoveCollectible(CollectibleType.COLLECTIBLE_SUCCUBUS)
        end
        player:AddCollectible(ConchBlessing.ItemData.KRONOS.id, 0, false)
    end)
    plan.wait(30)
    absorbAll(plan, id, "maidens")
    perfWindow(plan, "Kronos + 6 Seonnyeo")
    perfWindow(plan, "Kronos + 6 Seonnyeo, functions", function()
        return { seonnyeo = ConchBlessing.seonnyeo, kronos = ConchBlessing.kronos }
    end)
end)
S.rows[#S.rows].manual = true

-- Measurement only (run by name): the engine's own Succubus movement,
-- EntityFamiliar:MoveDiagonally, drives 선녀 with several values in turn, and
-- her real speed and headings are recorded for each, to find the value that
-- matches Succubus (4.7 units an update, 32-45 degrees off the horizontal).
S.add("SEONNYEO", "diagonal_probe", {}, function(plan, id)
    requireModule(plan)
    plan.act(function(player) give(player, id, 1) end)
    plan.waitUntil(function(player) return #maidens(player) == 1 end, 30, "the maiden appears")
    plan.require("the engine has MoveDiagonally", function(player)
        local fam = maidens(player)[1]
        return fam and type(fam.MoveDiagonally) == "function" or false, "EntityFamiliar.MoveDiagonally missing"
    end)
    for _, value in ipairs({ 0.5, 1, 2, 3, 4.7 }) do
        plan.act(function(_, ctx)
            seonnyeo()._test.diagonal = value
            ctx.track = {}
            ctx.cleanupFns = ctx.cleanupFns or {}
            table.insert(ctx.cleanupFns, function() seonnyeo()._test.diagonal = nil end)
        end)
        plan.wait(15)
        plan.waitUntil(function(player, ctx)
            local fam = maidens(player)[1]
            if fam then ctx.track[#ctx.track + 1] = fam.Position end
            return #ctx.track >= 150, "samples=" .. #ctx.track
        end, 170, "five seconds at MoveDiagonally(" .. value .. ")")
        plan.note("MoveDiagonally(" .. value .. ")", function(_, ctx)
            local room = Game():GetRoom()
            local tl, br = room:GetTopLeftPos(), room:GetBottomRightPos()
            local lo, hi, sum, n, angles, turns, prev = math.huge, 0, 0, 0, {}, {}, nil
            for i = 2, #ctx.track do
                local d = ctx.track[i] - ctx.track[i - 1]
                local speed = d:Length()
                lo, hi, sum, n = math.min(lo, speed), math.max(hi, speed), sum + speed, n + 1
                if speed > 0.05 then
                    local a = math.floor(d:GetAngleDegrees() / 5 + 0.5) * 5
                    angles[a] = (angles[a] or 0) + 1
                    if prev and prev:Length() > 0.05 then
                        local turn = math.abs(((d:GetAngleDegrees() - prev:GetAngleDegrees() + 540) % 360) - 180)
                        if turn > 10 then
                            local p = ctx.track[i]
                            turns[#turns + 1] = string.format("@%d %.0fdeg wall %.0f", i, turn,
                                math.min(p.X - tl.X, br.X - p.X, p.Y - tl.Y, br.Y - p.Y))
                        end
                    end
                end
                prev = d
            end
            local list = {}
            for a, c in pairs(angles) do list[#list + 1] = string.format("%d:%d", a, c) end
            table.sort(list)
            return string.format("speed %.2f-%.2f avg %.2f; headings {%s}; turns %d [%s]", lo, hi, sum / math.max(1, n),
                table.concat(list, " "), #turns, table.concat(turns, ", "))
        end)
    end
    plan.act(function(player)
        seonnyeo()._test.diagonal = nil
        give(player, id, 0)
    end)
    plan.wait(4)
end)
S.rows[#S.rows].manual = true

return C
