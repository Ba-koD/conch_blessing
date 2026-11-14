local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- Dev-only: `cb test april_fools` switches the April Fools 3D art on and off
-- the way the MCM option does (the setting, then Refresh) and checks every
-- catalogued layer of real subjects: a collectible pedestal and a trinket of
-- ours (turning strips), a familiar of ours (a still sheet) and a standalone
-- sprite kept through Watch. On: each layer shows its 3D sheet, a strip's crop
-- inside the strip. Off: the original sheet at its original crop, at once (the
-- MCM is open, so no update runs) and after updates. Rapid toggles in one
-- update, and a pause (renders without updates) are covered too. Whether the
-- art is drawn is a LOOK check; the sheet and crop it is drawn from are not.
local TestBench = require("scripts.dev.test_bench")
local AF = require("scripts.lib.april_fools")
local Catalogue = require("scripts.lib.april_fools_assets")

local CYCLES = 3

local function setMode(mode)
    ConchBlessing.Config.aprilFools3D = mode
    AF.Refresh()
end

local function idOf(key)
    local row = ConchBlessing.ItemData[key]
    return row and row.id or -1
end

-- The catalogued layers of a sprite: [layer id] = { path, original, x, y }.
local function snapshot(sprite)
    local rows = {}
    if not (sprite and type(sprite.GetAllLayers) == "function") then return rows end
    for _, layer in ipairs(sprite:GetAllLayers()) do
        local id = layer:GetLayerID()
        local p = AF._test.path(layer:GetSpritesheetPath(), sprite)
        local original = AF._test.reverse[p] or (Catalogue[p] and p)
        if original then
            local c = layer:GetCropOffset()
            rows[id] = { path = p, original = original, x = c.X, y = c.Y }
        end
    end
    return rows
end

local function subjects(ctx)
    local list = {}
    for _, name in ipairs({ "pedestal", "trinket", "familiar" }) do
        local ref = ctx[name]
        local entity = ref and ref.Ref
        list[#list + 1] = { name = name, sprite = entity and entity:Exists() and entity:GetSprite() or nil }
    end
    list[#list + 1] = { name = "standalone", sprite = ctx.standalone }
    return list
end

local function describe(rows)
    local parts = {}
    for id, row in pairs(rows) do
        parts[#parts + 1] = string.format("L%d %s (%g,%g)", id, row.path:match("[^/]+$"), row.x, row.y)
    end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, "; ") or "no catalogued layer"
end

-- On: every catalogued layer shows its 3D sheet; a strip's crop is a whole
-- frame inside it, on the original row.
local function check3D(ctx, list)
    for _, subject in ipairs(list) do
        local base = ctx.base[subject.name]
        local now = snapshot(subject.sprite)
        if not next(base) then return false, subject.name .. ": nothing catalogued at the start" end
        for id, b in pairs(base) do
            local row = Catalogue[b.original]
            local n = now[id]
            if not n then return false, subject.name .. " L" .. id .. ": layer lost its catalogued sheet (" .. describe(now) .. ")" end
            local spin = row.spin and n.path == row.spin:lower()
            if not (spin or n.path == row.still:lower()) then
                return false, subject.name .. " L" .. id .. ": still 2D (" .. describe(now) .. ")"
            end
            if spin then
                local dx = n.x - b.x
                if dx < 0 or dx > 32 * (row.frames - 1) or dx % 32 ~= 0 or n.y ~= b.y then
                    return false, string.format("%s L%d: strip crop (%g,%g) outside the strip (base %g,%g)",
                        subject.name, id, n.x, n.y, b.x, b.y)
                end
            elseif n.x ~= b.x or n.y ~= b.y then
                return false, string.format("%s L%d: still sheet at crop (%g,%g), base (%g,%g)", subject.name, id, n.x, n.y, b.x, b.y)
            end
        end
    end
    return true, "every catalogued layer shows its 3D sheet inside its frame"
end

-- Off: the original sheet at the original crop.
local function check2D(ctx, list)
    for _, subject in ipairs(list) do
        local base = ctx.base[subject.name]
        local now = snapshot(subject.sprite)
        for id, b in pairs(base) do
            local n = now[id]
            if not (n and n.path == b.path and n.x == b.x and n.y == b.y) then
                return false, subject.name .. " L" .. id .. ": " .. (n and describe({ [id] = n }) or "missing")
                    .. ", want " .. describe({ [id] = b })
            end
        end
    end
    return true, "every catalogued layer is back on its original sheet and crop"
end

local function build(plan)
    plan.require("REPENTOGON layer inspection", function()
        return Sprite and type(Sprite().GetAllLayers) == "function" or nil, "needs Sprite:GetAllLayers"
    end)
    plan.act(function(player, ctx)
        ctx.mode = ConchBlessing.Config.aprilFools3D
        setMode("off")
        local room = Game():GetRoom()
        local center = room:GetCenterPos()
        local function spawn(variant, subtype, offset)
            local pos = room:FindFreePickupSpawnPosition(center + offset, 0, true)
            local e = Isaac.Spawn(EntityType.ENTITY_PICKUP, variant, subtype, pos, Vector.Zero, nil)
            return EntityPtr(e)
        end
        ctx.pedestal = spawn(PickupVariant.PICKUP_COLLECTIBLE, idOf("KRONOS"), Vector(-80, 0))
        ctx.trinket = spawn(PickupVariant.PICKUP_TRINKET, idOf("ATROPOS"), Vector(80, 0))
        player:AddCollectible(idOf("HERMIT_CRAB"), 0, false)
        local s = Sprite()
        s:Load("gfx/005.100_collectible.anm2", true)
        s:ReplaceSpritesheet(1, "gfx/items/collectibles/kronos.png")
        s:LoadGraphics()
        s:SetFrame("Idle", 0)
        ctx.standalone = s
        AF.Watch(s)
    end)
    plan.wait(40) -- pedestals settle, the crab arrives
    plan.require("subjects are in the room", function(player, ctx)
        local crab = Isaac.FindByType(EntityType.ENTITY_FAMILIAR, ConchBlessing.ItemData.HERMIT_CRAB.entity.variant)
        ctx.familiar = crab[1] and EntityPtr(crab[1]) or nil
        return ctx.pedestal.Ref and ctx.trinket.Ref and ctx.familiar ~= nil, "pedestal, trinket and crab"
    end)
    plan.act(function(_, ctx)
        ctx.base = {}
        for _, subject in ipairs(subjects(ctx)) do ctx.base[subject.name] = snapshot(subject.sprite) end
    end)
    plan.note("2D start", function(_, ctx)
        local parts = {}
        for _, subject in ipairs(subjects(ctx)) do parts[#parts + 1] = subject.name .. ": " .. describe(ctx.base[subject.name]) end
        return table.concat(parts, " | ")
    end)
    for cycle = 1, CYCLES do
        plan.section("April Fools / cycle " .. cycle .. ": on")
        plan.act(function() setMode("on") end)
        plan.wait(3)
        plan.check("on: 3D sheets, strips inside their frames", function(_, ctx) return check3D(ctx, subjects(ctx)) end)
        plan.wait(17)
        plan.check("on: still inside the strip after it turned", function(_, ctx) return check3D(ctx, subjects(ctx)) end)
        plan.section("April Fools / cycle " .. cycle .. ": off")
        plan.act(function(_, ctx)
            setMode("off")
            -- the MCM is open: no update runs before the next draw
            ctx.immediate = { check2D(ctx, subjects(ctx)) }
        end)
        plan.check("off at once: original sheets and crops", function(_, ctx) return ctx.immediate[1], ctx.immediate[2] end)
        plan.wait(3)
        plan.check("off after updates: still original", function(_, ctx) return check2D(ctx, subjects(ctx)) end)
    end
    plan.section("April Fools / rapid toggles in one update")
    plan.act(function()
        setMode("on"); setMode("off"); setMode("on")
    end)
    plan.wait(5)
    plan.check("on after on-off-on: 3D inside the frames", function(_, ctx) return check3D(ctx, subjects(ctx)) end)
    plan.act(function()
        setMode("off"); setMode("on"); setMode("off")
    end)
    plan.wait(3)
    plan.check("off after off-on-off: original sheets and crops", function(_, ctx) return check2D(ctx, subjects(ctx)) end)
    -- A missed restore can leave the original sheet at a strip frame's crop,
    -- drawn from empty texture. Switching on and off must both heal it.
    plan.section("April Fools / a crop left inside the strip")
    plan.act(function(_, ctx)
        local sprite = ctx.pedestal.Ref and ctx.pedestal.Ref:GetSprite()
        for id in pairs(ctx.base.pedestal) do
            local b = ctx.base.pedestal[id]
            sprite:GetLayer(id):SetCropOffset(Vector(b.x + 96, b.y))
        end
        setMode("on")
    end)
    plan.wait(3)
    plan.check("on from a crop inside the strip: inside its frames", function(_, ctx) return check3D(ctx, subjects(ctx)) end)
    plan.act(function() setMode("off") end)
    plan.wait(2)
    plan.check("off again: the original crop, not the strip's", function(_, ctx) return check2D(ctx, subjects(ctx)) end)
    -- Every catalogued thing at once: all our released passives and familiars,
    -- trinkets, card pickups and pedestals (one of them rotating). A sprite that
    -- Apply swaps again and again would reload its texture each time and draw
    -- blank; native turns and spin frames never need a second swap.
    plan.section("April Fools / the whole room")
    plan.act(function(player, ctx)
        local room = Game():GetRoom()
        local center = room:GetCenterPos()
        ctx.extra = {}
        local function spawn(variant, subtype, offset)
            local pos = room:FindFreePickupSpawnPosition(center + offset, 0, true)
            local e = Isaac.Spawn(EntityType.ENTITY_PICKUP, variant, subtype, pos, Vector.Zero, nil)
            ctx.extra[#ctx.extra + 1] = EntityPtr(e)
            return e:ToPickup()
        end
        local col, tri = {}, {}
        for key, row in pairs(ConchBlessing.ItemData) do
            local id = row.id or -1
            if id > 0 and not row.WorkingNow and not row.hidden and not row.console then
                if row.type == "trinket" then tri[#tri + 1] = id
                elseif row.type ~= "active" then
                    col[#col + 1] = id
                    player:AddCollectible(id, 0, false)
                end
            end
        end
        table.sort(col); table.sort(tri)
        for i = 1, math.min(6, #col) do spawn(PickupVariant.PICKUP_COLLECTIBLE, col[i], Vector(-160 + 64 * (i - 1), -90)) end
        for i = 1, math.min(4, #tri) do spawn(PickupVariant.PICKUP_TRINKET, tri[i], Vector(-160 + 64 * (i - 1), 90)) end
        for _, row in pairs(ConchBlessing.PocketData or {}) do
            local card = row.id or (row.name and Isaac.GetCardIdByName(row.name))
            if type(card) == "number" and card > 0 then spawn(PickupVariant.PICKUP_TAROTCARD, card, Vector(120, 90)) end
        end
        local turning = spawn(PickupVariant.PICKUP_COLLECTIBLE, col[1], Vector(160, -90))
        if turning and type(turning.AddCollectibleCycle) == "function" then
            for i = 2, math.min(4, #col) do turning:AddCollectibleCycle(col[i]) end
        end
        setMode("on")
    end)
    plan.wait(60)
    plan.act(function(_, ctx)
        ctx.swaps = {}
        for k, v in pairs(AF.swaps) do ctx.swaps[k] = v end
    end)
    plan.act(function() AF.trace = {} end)
    plan.wait(90)
    plan.note("swap trace", function()
        local lines = AF.trace or {}
        AF.trace = nil
        return #lines .. " swaps: " .. table.concat(lines, " | ", 1, math.min(#lines, 60))
    end)
    plan.check("on, 90 updates later: no sheet swapped again and again", function(_, ctx)
        local worst, rows = 0, {}
        for k, v in pairs(AF.swaps) do
            local n = v - (ctx.swaps[k] or 0)
            if n > 0 then rows[#rows + 1] = k:match("[^/]+$") .. " x" .. n end
            if n > worst then worst = n end
        end
        table.sort(rows)
        return worst <= 8, "swaps in 90 updates: " .. (#rows > 0 and table.concat(rows, ", ") or "none")
    end)
    for cycle = 1, 2 do
        plan.act(function() setMode("off") end)
        plan.wait(10)
        plan.act(function(_, ctx)
            setMode("on")
            ctx.swaps = {}
            for k, v in pairs(AF.swaps) do ctx.swaps[k] = v end
        end)
        plan.wait(60)
        plan.check("after off and on again (" .. cycle .. "): no sheet swapped again and again", function(_, ctx)
            local worst, rows = 0, {}
            for k, v in pairs(AF.swaps) do
                local n = v - (ctx.swaps[k] or 0)
                if n > 1 then rows[#rows + 1] = k:match("[^/]+$") .. " x" .. n end
                if n > worst then worst = n end
            end
            table.sort(rows)
            return worst <= 8, "more than one swap in 60 updates: " .. (#rows > 0 and table.concat(rows, ", ") or "none")
        end)
    end
    plan.note("LOOK", function() return "the pedestal, trinket and crab are visible after every switch (screen)" end)
end

local function cleanup(ctx)
    AF.trace = nil
    if ctx.mode ~= nil then setMode(ctx.mode) end
    for _, name in ipairs({ "pedestal", "trinket" }) do
        local e = ctx[name] and ctx[name].Ref
        if e and e:Exists() then e:Remove() end
    end
    for _, ref in ipairs(ctx.extra or {}) do
        local e = ref.Ref
        if e and e:Exists() then e:Remove() end
    end
end

TestBench.register({ command = "cb test april_fools", tag = "AprilFoolsProbe", duration = "about 25 seconds",
    restartCommand = "restart 0", build = build, cleanup = cleanup })

return {}
