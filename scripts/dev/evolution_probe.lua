local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- conch_test evolution: the evolution preview on real, bench-owned pickups in
-- a clean run. It checks through the shipped highlight module that a tree
-- opens for a nearby player, stays open, closes when they leave, that the item
-- hops (its item layer only) while nobody is near, that an upgrade ends the
-- tree and puts the layer back first, that hidden pedestals reveal nothing,
-- that a rotating pedestal keeps one two-level tree through its native turns
-- and that a reroll ends the old tree.
--
-- Expected results come from the ItemData origin/flag declarations, not from
-- the preview's own tables. What the tree looks like stays LOOK lines.
local TestBench = require("scripts.dev.test_bench")
local Visuals = require("scripts.lib.upgrade_visuals")
local View = require("scripts.lib.conch_answer_view")

local FLAG_ORDER = { "positive", "neutral", "negative" }
-- Far is down and to the right: the hop must still stay in place.
local FAR, NEAR = Vector(100, 110), Vector(0, 50)

local function H() return ConchBlessing.UpgradeHighlight end

-- Every ItemData row whose origin is this pickup, in answer order.
local function expectedResults(variant, id)
    local byFlag = {}
    for key, item in pairs(ConchBlessing.ItemData) do
        if item.origin ~= nil and item.flag then
            local originVariant, originId = Visuals.origin(item)
            if originVariant == variant and originId == id then
                byFlag[item.flag] = { key = key, id = item.id, trinket = item.type == "trinket" }
            end
        end
    end
    local list = {}
    for _, flag in ipairs(FLAG_ORDER) do
        if byFlag[flag] then list[#list + 1] = { flag = flag, id = byFlag[flag].id, key = byFlag[flag].key } end
    end
    return list
end

local function describe(results)
    local parts = {}
    for _, r in ipairs(results) do parts[#parts + 1] = r.flag .. "=" .. tostring(r.id) end
    return table.concat(parts, ",")
end

local function sameResults(actual, expected)
    if #actual ~= #expected then return false end
    for i, r in ipairs(expected) do
        if actual[i].flag ~= r.flag or actual[i].id ~= r.id then return false end
    end
    return true
end

local function originOf(key)
    return Visuals.origin(assert(ConchBlessing.ItemData[key], "unknown item " .. key))
end

local function live(ctx)
    local f = ctx.fixture
    local entity = f and f.ptr.Ref
    if entity and entity:Exists() and GetPtrHash(entity) == f.hash then return entity:ToPickup() end
    -- A native Morph (reroll, rotating pedestal) renews the reference.
    if f and f.entity:Exists() and GetPtrHash(f.entity) == f.hash then
        f.ptr = EntityPtr(f.entity)
        return f.entity:ToPickup()
    end
end

local function rec(ctx)
    local pickup = live(ctx)
    return pickup and H().previewFor(pickup) or nil
end

local function itemLayer(pickup)
    local sprite = pickup:GetSprite()
    if type(sprite.GetLayer) ~= "function" then return nil end
    local layer = sprite:GetLayer(pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE and "head" or "body")
    if layer and type(layer.SetPos) == "function" and type(layer.GetPos) == "function"
        and type(layer.GetSize) == "function" then
        return layer
    end
end

local function layerState(pickup)
    local layer = itemLayer(pickup)
    if not layer then return nil end
    local pos, size = layer:GetPos(), layer:GetSize()
    local rotation = type(layer.GetRotation) == "function" and layer:GetRotation() or 0
    return { pos.X, pos.Y, size.X, size.Y, rotation }
end

local function sameState(a, b)
    if not a or not b then return a == b end
    for i = 1, 5 do if math.abs(a[i] - b[i]) > 1e-6 then return false end end
    return true
end

local function stateText(s)
    return s and string.format("pos %.2f,%.2f size %.2f,%.2f rot %.1f", s[1], s[2], s[3], s[4], s[5]) or "none"
end

local function removeFixture(ctx)
    if ctx.job and ctx.job.status ~= "complete" and ctx.job.status ~= "cancelled" then
        ConchBlessing.upgrade.cancel(ctx.job)
    end
    local pickup = live(ctx)
    if pickup then
        H().StopForPickup(pickup)
        pickup:Remove()
    end
    ctx.fixture, ctx.job, ctx.baseLayer = nil, nil, nil
end

local function stand(player, ctx, offset)
    player.Position = ctx.fixturePos + offset
    player.Velocity = Vector(0, 0)
end

local function spawnFixture(plan, label, key)
    plan.act(function(player, ctx)
        removeFixture(ctx)
        local variant, id = originOf(key)
        local room = Game():GetRoom()
        ctx.fixturePos = ctx.fixturePos or room:FindFreePickupSpawnPosition(room:GetCenterPos() + Vector(0, -40), 0, true)
        stand(player, ctx, FAR)
        local entity = Isaac.Spawn(EntityType.ENTITY_PICKUP, variant, id, ctx.fixturePos, Vector(0, 0), nil)
        ctx.fixture = { entity = entity, ptr = EntityPtr(entity), hash = GetPtrHash(entity), variant = variant, id = id }
        local pickup = assert(entity:ToPickup(), "origin is not a pickup")
        pickup.Price, pickup.ShopItemId, pickup.AutoUpdatePrice, pickup.OptionsPickupIndex = 0, -1, false, 0
        ctx.expected = expectedResults(variant, id)
        assert(#ctx.expected > 0, label .. " has no declared results")
    end)
    plan.waitUntil(function(_, ctx)
        local pickup = live(ctx)
        return pickup ~= nil and pickup.FrameCount >= 1, "fixture missing or not initialized"
    end, 60, label .. ": pickup initialized")
end

local function waitTracked(plan, label)
    plan.waitUntil(function(_, ctx)
        return rec(ctx) ~= nil, "no preview record"
    end, 40, label .. ": preview tracked")
end

local function waitOpen(plan, label)
    plan.act(function(player, ctx) stand(player, ctx, NEAR) end)
    plan.waitUntil(function(player, ctx)
        stand(player, ctx, NEAR)
        local r = rec(ctx)
        return r ~= nil and r.open and r.t >= r.layout.openEnd, r and ("t=" .. tostring(r.t)) or "no record"
    end, 60, label .. ": the tree opens for a nearby player")
end

-- Read the resting item layer only while no hop is in the air.
local function captureRest(plan, label)
    plan.waitUntil(function(player, ctx)
        stand(player, ctx, FAR)
        local r = rec(ctx)
        return r ~= nil and r.hop == nil, "hop in the air"
    end, 40, label .. ": the item is at rest")
    plan.act(function(_, ctx)
        local pickup = live(ctx)
        ctx.layerApi = pickup ~= nil and itemLayer(pickup) ~= nil
        ctx.baseLayer = pickup and layerState(pickup)
    end)
end

local function checkResults(plan, label)
    plan.check(label .. ": the tree lists every declared result in answer order", function(_, ctx)
        local r = rec(ctx)
        if not r then return false, "no record" end
        local actual = r.groups[1].results
        return sameResults(actual, ctx.expected) and #r.groups == 1,
            "got " .. describe(actual) .. "; want " .. describe(ctx.expected)
    end)
end

local function checkDrawn(plan, label)
    plan.check(label .. ": the open tree is drawn with every icon, line and label", function(_, ctx)
        local r = rec(ctx)
        local d = r and r.lastDrawn
        if not d then return false, "nothing drawn" end
        local icons = #r.layout.icons
        local labelsWanted = View.hasFont() and #ctx.expected or 0
        return d.icons == icons and d.lines == #r.layout.lines and d.labels == labelsWanted,
            string.format("icons %d/%d, lines %d/%d, labels %d/%d (draws %d)", d.icons, icons, d.lines,
                #r.layout.lines, d.labels, labelsWanted, r.draws)
    end)
end

local function stagePedestal(plan)
    local key = "CEIL" -- Libra: positive Ceil, neutral Round, negative Floor
    plan.section("pedestal with three answers (Libra)",
        "far away, only Libra's item (not the pedestal) keeps hopping in place twice in quick succession, landing squashed, then rests as long and hops again, as if asking to be looked at; up close a pale trunk splits into three straight stems: green 긍정 Ceil on the left, beige 중립 Round in the middle, pink 부정 Floor on the right, each icon with a 1px outline in its colour; a small spark runs up to each result in turn and it pops; it stays while you stand there and folds when you leave")
    spawnFixture(plan, "Libra", key)
    waitTracked(plan, "Libra")
    checkResults(plan, "Libra")
    plan.check("Libra: closed and undrawn while nobody is near", function(_, ctx)
        local r = rec(ctx)
        return r ~= nil and not r.open and r.t == 0 and r.draws == 0,
            r and string.format("open=%s t=%s draws=%d", tostring(r.open), tostring(r.t), r.draws) or "no record"
    end)

    captureRest(plan, "Libra")
    plan.act(function(_, ctx)
        local pickup = live(ctx)
        ctx.basePosition = pickup and Vector(pickup.Position.X, pickup.Position.Y)
        ctx.baseColor = pickup and pickup:GetSprite().Color
        ctx.baseColor = ctx.baseColor and { ctx.baseColor.R, ctx.baseColor.G, ctx.baseColor.B, ctx.baseColor.A }
    end)
    plan.waitUntil(function(player, ctx)
        stand(player, ctx, FAR)
        if not ctx.layerApi then return true end
        local pickup = live(ctx)
        local now = pickup and layerState(pickup)
        ctx.hopSeen = now and not sameState(now, ctx.baseLayer) or ctx.hopSeen
        if now then
            ctx.sideways = math.max(ctx.sideways or 0, math.abs(now[1] - ctx.baseLayer[1]), math.abs(now[5] - ctx.baseLayer[5]))
            ctx.hopHeight = math.min(ctx.hopHeight or 0, now[2] - ctx.baseLayer[2])
        end
        -- Watch one whole hop: it takes off and lands again.
        local r = rec(ctx)
        return ctx.hopSeen and r ~= nil and r.hop == nil, stateText(now)
    end, 120, "Libra: the item hops while nobody is near")
    plan.check("Libra: a 7px hop in place, never toward the player on the right", function(_, ctx)
        if not ctx.layerApi then return nil, "item layer API unavailable without REPENTOGON" end
        return ctx.hopHeight <= -7 and ctx.sideways == 0,
            string.format("highest %.0fpx, largest sideways step or tilt %.2f", -ctx.hopHeight, ctx.sideways)
    end)
    plan.act(function(_, ctx) ctx.hopsBefore = rec(ctx).hops end)
    plan.waitUntil(function(player, ctx)
        stand(player, ctx, FAR)
        local r = rec(ctx)
        return not ctx.layerApi or (r ~= nil and r.hops >= ctx.hopsBefore + 2), r and (r.hops - ctx.hopsBefore) .. " more hops" or "no record"
    end, 100, "Libra: it keeps hopping while nobody comes near")
    plan.check("Libra: the hop moves the item layer, never the pickup or its colour", function(_, ctx)
        if not ctx.layerApi then return nil, "item layer API unavailable without REPENTOGON" end
        local pickup = live(ctx)
        local c = pickup:GetSprite().Color
        local samePlace = pickup.Position.X == ctx.basePosition.X and pickup.Position.Y == ctx.basePosition.Y
        local sameColor = c.R == ctx.baseColor[1] and c.G == ctx.baseColor[2] and c.B == ctx.baseColor[3] and c.A == ctx.baseColor[4]
        return samePlace and sameColor, string.format("position kept %s, colour kept %s", tostring(samePlace), tostring(sameColor))
    end)
    plan.waitUntil(function(player, ctx)
        stand(player, ctx, FAR)
        local r = rec(ctx)
        return not ctx.layerApi or (r ~= nil and r.hop == nil), "hop still in the air"
    end, 40, "Libra: the hop lands")
    plan.check("Libra: a landed hop leaves the item layer exactly as it was", function(_, ctx)
        if not ctx.layerApi then return nil, "item layer API unavailable without REPENTOGON" end
        local now = layerState(live(ctx))
        return sameState(now, ctx.baseLayer), "now " .. stateText(now) .. "; was " .. stateText(ctx.baseLayer)
    end)

    waitOpen(plan, "Libra")
    checkDrawn(plan, "Libra")
    plan.act(function(_, ctx)
        local r = rec(ctx)
        ctx.drawsBefore, ctx.sparksBefore, ctx.popsBefore = r.draws, r.sparks, r.pops
    end)
    for _ = 1, 5 do
        plan.act(function(player, ctx) stand(player, ctx, NEAR) end)
        plan.wait(30)
    end
    plan.check("Libra: the tree stays open while the player stays near (5 seconds)", function(_, ctx)
        local r = rec(ctx)
        return r ~= nil and r.open and r.t == r.layout.openEnd and r.draws > ctx.drawsBefore + 100 and r.opens == 1,
            r and string.format("open=%s t=%s draws +%d opens=%d", tostring(r.open), tostring(r.t),
                r.draws - ctx.drawsBefore, r.opens) or "no record"
    end)
    plan.check("Libra: while open, sparks run to the results and they pop, with no hop", function(_, ctx)
        local r = rec(ctx)
        local sparks, pops = r.sparks - ctx.sparksBefore, r.pops - ctx.popsBefore
        local still = not ctx.layerApi or sameState(layerState(live(ctx)), ctx.baseLayer)
        return sparks > 0 and pops > 0 and still, string.format("spark frames %d, pop frames %d, item layer at rest %s",
            sparks, pops, tostring(still))
    end)
    plan.act(function(player, ctx) stand(player, ctx, FAR) end)
    plan.waitUntil(function(player, ctx)
        stand(player, ctx, FAR)
        local r = rec(ctx)
        return r ~= nil and r.t == 0, r and ("t=" .. tostring(r.t)) or "no record"
    end, 40, "Libra: the tree folds when the player leaves")
    plan.act(function(_, ctx) ctx.drawsBefore = rec(ctx).draws end)
    plan.wait(15)
    plan.check("Libra: a folded tree draws nothing", function(_, ctx)
        local r = rec(ctx)
        return r ~= nil and r.draws == ctx.drawsBefore, r and ("draws +" .. (r.draws - ctx.drawsBefore)) or "no record"
    end)

    -- An upgrade ends the tree and returns the item layer before it starts.
    waitOpen(plan, "Libra")
    plan.act(function(player, ctx)
        local pickup = assert(live(ctx), "fixture disappeared")
        local job, reason = ConchBlessing.upgrade.queuePickup(pickup, key, player)
        assert(job, "queue refused: " .. tostring(reason))
        ctx.job = job
        ctx.afterQueue = { record = H().previewFor(pickup), layer = layerState(pickup) }
    end)
    plan.check("Libra: queueing the upgrade ends the tree at once and leaves the item layer as it was", function(_, ctx)
        local a = ctx.afterQueue
        local layerOk = not ctx.layerApi or sameState(a.layer, ctx.baseLayer)
        return a.record == nil and layerOk, string.format("record %s, layer %s", tostring(a.record ~= nil), stateText(a.layer))
    end)
    plan.waitUntil(function(player, ctx)
        stand(player, ctx, NEAR)
        if rec(ctx) then ctx.duringUpgrade = true end
        return ctx.job.status == "complete" or ctx.job.status == "cancelled", "job=" .. tostring(ctx.job.status)
    end, 400, "Libra: the upgrade finishes")
    plan.check("Libra: no tree during the upgrade, and none for Ceil (not an origin)", function(_, ctx)
        local pickup = live(ctx)
        return ctx.job.status == "complete" and not ctx.duringUpgrade and pickup ~= nil and H().previewFor(pickup) == nil,
            string.format("job=%s during=%s now=%s", tostring(ctx.job.status), tostring(ctx.duringUpgrade == true),
                tostring(pickup and H().previewFor(pickup) ~= nil))
    end)
    plan.act(function(_, ctx) removeFixture(ctx) end)
end

local function stageHopUpgrade(plan)
    plan.section("upgrade in the middle of a hop (Dead Eye)", nil)
    spawnFixture(plan, "Dead Eye", "LIVE_EYE")
    waitTracked(plan, "Dead Eye")
    checkResults(plan, "Dead Eye")
    captureRest(plan, "Dead Eye")
    plan.waitUntil(function(player, ctx)
        stand(player, ctx, FAR)
        if not ctx.layerApi then return true end
        local r, pickup = rec(ctx), live(ctx)
        return r ~= nil and r.hop ~= nil and not sameState(layerState(pickup), ctx.baseLayer), "on the ground"
    end, 120, "Dead Eye: the item is in the air")
    plan.act(function(player, ctx)
        local pickup = assert(live(ctx), "fixture disappeared")
        ctx.job = assert(ConchBlessing.upgrade.queuePickup(pickup, "LIVE_EYE", player))
        ctx.afterQueue = layerState(pickup)
    end)
    plan.check("Dead Eye: queueing mid-hop puts the item layer back before the upgrade reads it", function(_, ctx)
        if not ctx.layerApi then return nil, "item layer API unavailable without REPENTOGON" end
        return sameState(ctx.afterQueue, ctx.baseLayer), "now " .. stateText(ctx.afterQueue) .. "; was " .. stateText(ctx.baseLayer)
    end)
    plan.waitUntil(function(_, ctx)
        return ctx.job.status == "complete" or ctx.job.status == "cancelled", "job=" .. tostring(ctx.job.status)
    end, 400, "Dead Eye: the upgrade finishes")
    plan.check("Dead Eye: the upgrade completed and the item layer is untouched", function(_, ctx)
        local now = live(ctx) and layerState(live(ctx))
        return ctx.job.status == "complete" and (not ctx.layerApi or sameState(now, ctx.baseLayer)),
            "job=" .. tostring(ctx.job.status) .. " " .. stateText(now)
    end)
    plan.act(function(_, ctx) removeFixture(ctx) end)
end

local function stageTrinket(plan)
    plan.section("floor trinket with two answers (Perfection)",
        "up close two stems: green 긍정 Time = Luck on the left, pink 부정 F - on the right")
    spawnFixture(plan, "Perfection", "TIME_LUCK")
    waitTracked(plan, "Perfection")
    checkResults(plan, "Perfection")
    waitOpen(plan, "Perfection")
    checkDrawn(plan, "Perfection")
    plan.act(function(_, ctx) removeFixture(ctx) end)
end

local function stageHidden(plan)
    plan.section("hidden pedestals", nil)
    plan.act(function() Game():GetLevel():AddCurse(LevelCurse.CURSE_OF_BLIND, false) end)
    spawnFixture(plan, "Dead Eye under Curse of the Blind", "LIVE_EYE")
    plan.act(function(player, ctx)
        local pickup = live(ctx)
        ctx.baseLayer = pickup and layerState(pickup)
        stand(player, ctx, NEAR)
    end)
    for _ = 1, 4 do
        plan.act(function(player, ctx) stand(player, ctx, ctx.hiddenNear and NEAR or FAR); ctx.hiddenNear = not ctx.hiddenNear end)
        plan.wait(25)
    end
    plan.check("Curse of the Blind: no tree and no hop, near or far", function(_, ctx)
        local pickup = live(ctx)
        return pickup ~= nil and H().previewFor(pickup) == nil and sameState(layerState(pickup), ctx.baseLayer),
            string.format("record %s, layer %s", tostring(pickup and H().previewFor(pickup) ~= nil),
                stateText(pickup and layerState(pickup)))
    end)
    plan.act(function(_, ctx)
        removeFixture(ctx)
        Game():GetLevel():RemoveCurses(LevelCurse.CURSE_OF_BLIND)
    end)

    spawnFixture(plan, "Libra (forced blind)", "CEIL")
    waitTracked(plan, "Libra (forced blind)")
    waitOpen(plan, "Libra (forced blind)")
    plan.act(function(_, ctx)
        local pickup = live(ctx)
        ctx.canForceBlind = type(pickup.SetForceBlind) == "function"
        if ctx.canForceBlind then pickup:SetForceBlind(true) end
    end)
    plan.waitUntil(function(player, ctx)
        stand(player, ctx, NEAR)
        return not ctx.canForceBlind or rec(ctx) == nil, "still tracked"
    end, 20, "a pedestal turned blind ends its tree")
    plan.check("REPENTOGON IsBlind: a pedestal turned into a question mark stops showing its results", function(_, ctx)
        if not ctx.canForceBlind then return nil, "EntityPickup:SetForceBlind unavailable without REPENTOGON" end
        local reason
        for _, e in ipairs(H().previewEvents()) do
            if e.event == "END" and e.hash == tostring(ctx.fixture.hash) then reason = e.detail end
        end
        return reason == "hidden", "ended: " .. tostring(reason)
    end)
    plan.act(function(_, ctx)
        local pickup = live(ctx)
        if pickup and ctx.canForceBlind then pickup:SetForceBlind(false) end
        removeFixture(ctx)
    end)
end

local function stageCycle(plan)
    plan.section("rotating pedestal (two-level tree)",
        "the pedestal keeps turning Dead Eye, Libra and Sad Onion; up close a trunk splits to small Dead Eye and Libra icons, Dead Eye grows green Live Eye, Libra grows Ceil, Round and Floor; the tree does not restart or flicker as the pedestal turns")
    spawnFixture(plan, "rotating Dead Eye", "LIVE_EYE")
    -- Like conch_test morph cycle: the circle is built after native init.
    plan.act(function(_, ctx)
        local pickup = assert(live(ctx), "fixture disappeared")
        ctx.cycleApi = type(pickup.GetCollectibleCycle) == "function" and type(pickup.AddCollectibleCycle) == "function"
            and type(pickup.RemoveCollectibleCycle) == "function"
        if not ctx.cycleApi then return end
        pickup:RemoveCollectibleCycle()
        local libraVariant, libra = originOf("CEIL")
        assert(libraVariant == PickupVariant.PICKUP_COLLECTIBLE)
        ctx.libra = libra
        for _, extra in ipairs({ libra, CollectibleType.COLLECTIBLE_SAD_ONION }) do
            assert(pickup:AddCollectibleCycle(extra), "AddCollectibleCycle refused " .. extra)
        end
    end)
    plan.waitUntil(function(_, ctx)
        local r = rec(ctx)
        return not ctx.cycleApi or (r ~= nil and r.layout.tree), r and r.identity or "no record"
    end, 40, "rotating pedestal: tracked as one circle")
    plan.check("rotating pedestal: one group per evolvable choice, each with its declared results", function(_, ctx)
        if not ctx.cycleApi then return nil, "collectible cycle API unavailable without REPENTOGON" end
        local r = rec(ctx)
        local want = {
            [ctx.fixture.id] = expectedResults(PickupVariant.PICKUP_COLLECTIBLE, ctx.fixture.id),
            [ctx.libra] = expectedResults(PickupVariant.PICKUP_COLLECTIBLE, ctx.libra),
        }
        local ok, seen, text = #r.groups == 2, {}, {}
        for _, g in ipairs(r.groups) do
            local expected = want[g.source.id]
            ok = ok and expected ~= nil and not seen[g.source.id] and sameResults(g.results, expected)
            seen[g.source.id] = true
            text[#text + 1] = tostring(g.source.id) .. ":" .. describe(g.results)
        end
        return ok, table.concat(text, " | ")
    end)
    plan.act(function(player, ctx)
        if not ctx.cycleApi then return end
        stand(player, ctx, NEAR)
        ctx.cycleRecord, ctx.turns, ctx.head = rec(ctx), 0, live(ctx).SubType
    end)
    plan.waitUntil(function(player, ctx)
        if not ctx.cycleApi then return true end
        stand(player, ctx, NEAR)
        local pickup = live(ctx)
        if pickup and pickup.SubType ~= ctx.head then ctx.turns, ctx.head = ctx.turns + 1, pickup.SubType end
        if rec(ctx) ~= ctx.cycleRecord then ctx.restarted = true end
        return ctx.turns >= 3, ctx.turns .. " turns"
    end, 400, "rotating pedestal: three native turns")
    plan.check("rotating pedestal: the tree stays the same through its turns", function(_, ctx)
        if not ctx.cycleApi then return nil, "collectible cycle API unavailable without REPENTOGON" end
        local r = rec(ctx)
        return r == ctx.cycleRecord and not ctx.restarted and r.opens == 1 and r.t == r.layout.openEnd,
            string.format("same=%s restarted=%s opens=%s t=%s", tostring(r == ctx.cycleRecord),
                tostring(ctx.restarted == true), tostring(r and r.opens), tostring(r and r.t))
    end)
    plan.act(function(_, ctx) removeFixture(ctx) end)
end

local function stageReroll(plan)
    plan.section("reroll (D6)", nil)
    spawnFixture(plan, "Libra (reroll)", "CEIL")
    waitTracked(plan, "Libra (reroll)")
    waitOpen(plan, "Libra (reroll)")
    plan.act(function(player, ctx)
        ctx.oldRecord = rec(ctx)
        ctx.seed = live(ctx).InitSeed
        player:UseActiveItem(CollectibleType.COLLECTIBLE_D6, UseFlag.USE_NOANIM)
    end)
    plan.waitUntil(function(player, ctx)
        stand(player, ctx, NEAR)
        local pickup = live(ctx)
        -- A D6 reroll gives the pedestal a new InitSeed (measured 2026-10-18).
        return pickup ~= nil and pickup.InitSeed ~= ctx.seed, pickup and ("shows " .. pickup.SubType) or "gone"
    end, 20, "the pedestal rerolls")
    plan.wait(2)
    plan.check("reroll: Libra's tree ends; a new item gets its own tree only if it can evolve", function(_, ctx)
        local pickup = live(ctx)
        if pickup and pickup.SubType == ctx.fixture.id then return nil, "rerolled into Libra again; inconclusive" end
        local now = pickup and H().previewFor(pickup)
        local info = pickup and H().getPickupUpgradeInfo(pickup)
        local ok = now ~= ctx.oldRecord and (now == nil) == (info == nil)
            and (now == nil or now.identity == info.originKey)
        return ok, string.format("now %s (%s), eligible %s", tostring(pickup and pickup.SubType),
            tostring(now and now.identity), tostring(info ~= nil))
    end)
    plan.act(function(_, ctx) removeFixture(ctx) end)
end

local function build(plan)
    plan.require("real upgrade queue and preview available", function()
        local ok = ConchBlessing.upgrade and type(ConchBlessing.upgrade.queuePickup) == "function"
            and H() and type(H().previewFor) == "function"
        return ok and true or false, "ConchBlessing.upgrade.queuePickup, UpgradeHighlight.previewFor"
    end)
    plan.require("the conversion map is built", function()
        return next(ConchBlessing.ItemMaps or {}) ~= nil, "ConchBlessing.ItemMaps"
    end)
    stagePedestal(plan)
    stageHopUpgrade(plan)
    stageTrinket(plan)
    stageHidden(plan)
    stageCycle(plan)
    stageReroll(plan)
end

TestBench.register({ command = "conch_test evolution", tag = "EvolutionProbe", duration = "about 40 seconds",
    cleanup = removeFixture, build = build })

return { expectedResults = expectedResults }
