local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- Paired, isolated engine experiments. Native arm uses the same public card
-- operation as AstroItems; the Oath arm only acquires the real active and enters
-- rooms. Expected preservation comes from the item contract, not its ledger.
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")
local C = require("scripts.dev.cycle_compare_support")
local M = {commands = {}}
local capture
local fixtureCapture
local observerMode = "unavailable"

-- Observe only the short fixture-preparation window, without changing a
-- provider callback, return value, entity flag, timeout or removal operation.
local function traceFixture(label, entity, duringRemoval)
    if not fixtureCapture then return end
    local key = tostring(GetPtrHash(entity)) .. ":" .. tostring(entity.InitSeed)
    if not fixtureCapture.keys[key] then return end
    if #fixtureCapture.events >= 12 then
        if not duringRemoval then return end
        -- Keep a late removal even when ordinary update samples filled the
        -- budget. Preserve the initial spawn record and bound the log size.
        table.remove(fixtureCapture.events, 2)
    end
    local ok, detail = pcall(C.describeEntity, entity, duringRemoval)
    fixtureCapture.events[#fixtureCapture.events + 1] = label .. ":" .. (ok and detail or "unreadable=" .. tostring(detail))
    if duringRemoval and debug and type(debug.traceback) == "function" then
        -- An engine-deferred removal may have no originating Lua caller. Keep
        -- the observed stack, but do not infer that the last observer removed it.
        local traced, stack = pcall(debug.traceback, "", 2)
        if traced then fixtureCapture.removalStack = stack:gsub("[\r\n\t]+", " "):sub(1, 1800) end
    end
end

local function fixtureObserver(callback, label, priority, parameter, removing)
    if not callback then return end
    local function observe(_, entity)
        local ok, err = pcall(traceFixture, label, entity, removing)
        if not ok and fixtureCapture and #fixtureCapture.events < 12 then
            fixtureCapture.events[#fixtureCapture.events + 1] = label .. ":observer-error=" .. tostring(err)
        end
    end
    if priority and type(ConchBlessing.AddPriorityCallback) == "function" then
        ConchBlessing:AddPriorityCallback(callback, priority, observe, parameter)
    else
        ConchBlessing:AddCallback(callback, observe, parameter)
    end
end

fixtureObserver(ModCallbacks.MC_PRE_PICKUP_UPDATE, "pre-update", CallbackPriority and CallbackPriority.EARLY,
    PickupVariant.PICKUP_COLLECTIBLE)
fixtureObserver(ModCallbacks.MC_POST_PICKUP_UPDATE, "post-update-early", CallbackPriority and CallbackPriority.EARLY,
    PickupVariant.PICKUP_COLLECTIBLE)
fixtureObserver(ModCallbacks.MC_POST_PICKUP_UPDATE, "post-update-late", CallbackPriority and CallbackPriority.LATE,
    PickupVariant.PICKUP_COLLECTIBLE)
fixtureObserver(ModCallbacks.MC_POST_ENTITY_REMOVE, "remove", CallbackPriority and CallbackPriority.EARLY,
    EntityType.ENTITY_PICKUP, true)

if ModCallbacks.MC_POST_GET_COLLECTIBLE then
    local function observe(_, id, requested, decrease, seed)
        if capture then
            local pool = Game():GetItemPool()
            capture[#capture + 1] = {id = id, requested = requested, decrease = decrease, seed = seed,
                actual = type(pool.GetLastPool) == "function" and pool:GetLastPool() or "unknown"}
        end
        -- Never return an override. SelectedCollectible is not updated by other
        -- POST return values, and PRE overrides can suppress this callback.
        -- Even LATE therefore cannot prove the final returned identity.
    end
    if type(ConchBlessing.AddPriorityCallback) == "function" and CallbackPriority and CallbackPriority.LATE then
        ConchBlessing:AddPriorityCallback(ModCallbacks.MC_POST_GET_COLLECTIBLE, CallbackPriority.LATE, observe)
        observerMode = "late"
    else
        ConchBlessing:AddCallback(ModCallbacks.MC_POST_GET_COLLECTIBLE, observe)
        observerMode = "default"
    end
end

local function soul(player, count)
    for _ = 1, count do player:UseCard(Card.CARD_SOUL_ISAAC, UseFlag.USE_NOANIM | UseFlag.USE_NOANNOUNCER) end
end

local function open(ctx, phase, before)
    assert(not capture, "overlapping comparison windows")
    ctx.window = {name = phase, before = before or C.snapshot(), events = {}, poolBefore = C.poolSnapshot(),
        frame = Game():GetFrameCount(), callbackKnown = observerMode ~= "unavailable"}
    capture = ctx.window.events
end

local function close(plan, validate, required, separateMetadata)
    plan.act(function(player, ctx)
        local w = ctx.window
        capture = nil
        w.after, w.poolAfter = C.snapshot(), C.poolSnapshot()
        w.frames = Game():GetFrameCount() - w.frame
        if w.name == "grant" then w.audit = C.auditGrant(w, ctx.expectedPool) end
        if validate then w.ok, w.reason = validate(player, ctx, w) end
        if separateMetadata then w.metadataOk, w.metadataReason = C.sameMetadata(w.before, w.after) end
    end)
    plan.note("CYCLE_COMPARE", function(_, ctx)
        local w = ctx.window
        local decreasing, preview = C.drawCounts(w.events)
        local delta, trace = C.poolDelta(w.poolBefore, w.poolAfter), {}
        for _, event in ipairs(w.events) do
            trace[#trace + 1] = table.concat({tostring(event.id), tostring(event.requested), tostring(event.actual),
                tostring(event.seed), event.decrease and "D" or "P"}, ":")
        end
        local contract = not validate and "OBSERVED" or w.ok == nil and "SKIP" or w.ok and "PASS" or "FAIL"
        local metadata = not separateMetadata and "NA" or w.metadataOk and "PASS" or "FAIL"
        local status = metadata == "FAIL" and "FAIL" or contract
        local audit = w.audit
        local source = not audit and "NA" or audit.source == nil and "REVIEW" or audit.source and "PASS" or "FAIL"
        return string.format("case=%s arm=%s phase=%s status=%s before=%d after=%d decrease=%d preview=%d weightLost=%s poolKnown=%s frames=%d seed=%s contract=%s metadata=%s observer=%s expectedPool=%s source=%s newSame=%s newCross=%s ringsBefore=%s ringsAfter=%s poolDelta=%s trace=%s reason=%s",
            ctx.recipe, ctx.arm, w.name, status, C.total(w.before), C.total(w.after), decreasing, preview,
            tostring(delta.lost), tostring(delta.known), w.frames, tostring(Game():GetSeeds():GetStartSeed()), contract, metadata, observerMode,
            tostring(ctx.expectedPool), source, audit and tostring(audit.same) or "NA", audit and tostring(audit.cross) or "NA",
            C.signature(w.before, false), C.signature(w.after, false), delta.detail, table.concat(trace, ","),
            (w.reason or "native observation") .. (separateMetadata and "; metadata: " .. w.metadataReason or ""))
    end)
    if validate then
        local check = required and plan.require or plan.check
        check("comparison contract (see preceding CYCLE_COMPARE)", function(_, ctx) return ctx.window.ok, ctx.window.reason end)
    end
    if separateMetadata then
        plan.check("price/options/shop/auto contract", function(_, ctx) return ctx.window.metadataOk, ctx.window.metadataReason end)
    end
end

local function unchanged(_, _, w)
    local before, after = C.signature(w.before, true, false), C.signature(w.after, true, false)
    if before ~= after then return false, "unexpected cycle/identity change; before=" .. before .. "; after=" .. after end
    return C.noCharge(w)
end

local function phase(plan, name, action, ticks, validate, required)
    plan.section(name)
    plan.act(function(player, ctx) open(ctx, name); if action then action(player, ctx) end end)
    plan.wait(ticks)
    close(plan, validate, required, validate == unchanged)
end

local function enter(plan, field)
    plan.act(function(player, ctx)
        ctx.entryRooms = ctx.rooms or 0
        assert(Game():GetLevel():GetCurrentRoomIndex() ~= ctx[field], "test transition already in destination")
        Game():StartRoomTransition(ctx[field], Direction.NO_DIRECTION, RoomTransitionAnim.FADE, player)
    end)
    plan.waitUntil(function(_, ctx)
        local index = Game():GetLevel():GetCurrentRoomIndex()
        local mode = RoomTransition.GetTransitionMode()
        -- A selected descriptor is not proof that room loading/animation has
        -- finished. TestBench counts real POST_NEW_ROOM callbacks in ctx.rooms.
        local arrived = (ctx.rooms or 0) > ctx.entryRooms and index == ctx[field]
        return arrived and mode == 0 and Game():GetRoom():GetFrameCount() > 0,
            string.format("index=%s target=%s arrivals=%s->%s mode=%s", tostring(index), tostring(ctx[field]),
                tostring(ctx.entryRooms), tostring(ctx.rooms), tostring(mode))
    end, 180, "native room transition: " .. field)
end

local function visit(plan, recipe)
    plan.act(function(_, ctx)
        ctx.origin = Game():GetLevel():GetCurrentRoomIndex()
        ctx.roomType = assert(RoomType[recipe.roomType or "ROOM_TREASURE"])
        local rooms = Game():GetLevel():GetRooms()
        for i = 0, rooms.Size - 1 do
            local desc = rooms:Get(i)
            if desc.Data and desc.Data.Type == ctx.roomType then ctx.roomGrid = desc.SafeGridIndex; break end
        end
        assert(ctx.roomGrid, "missing native test room type=" .. ctx.roomType)
    end)
    enter(plan, "roomGrid")
    plan.act(function(_, ctx)
        local room, pool = Game():GetRoom(), Game():GetItemPool()
        assert(room:GetType() == ctx.roomType, "transition reached wrong native room type")
        ctx.expectedPool = pool:GetPoolForRoom(room:GetType(), room:GetSpawnSeed())
        assert(type(ctx.expectedPool) == "number" and ctx.expectedPool >= 0, "no room pool mapping")
        -- Prepare a quiet measurement room; this is not a combat/death test.
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            local npc = entity:ToNPC()
            if npc then npc:Remove() end
        end
        room:SetClear(true)
    end)
    plan.wait(4)
end

local function revisit(plan)
    plan.act(function(_, ctx) ctx.revisitBefore = C.snapshot() end)
    enter(plan, "origin")
    plan.act(function(_, ctx) open(ctx, "revisit", ctx.revisitBefore) end)
    enter(plan, "roomGrid")
    plan.wait(8)
    close(plan, function(_, _, w)
        if C.signature(w.before, "anchor", false) ~= C.signature(w.after, "anchor", false) then
            return false, "revisit changed pedestal identity or circular sequence"
        end
        return C.noCharge(w)
    end, false, true)
end

local function fixture(player, index, seed)
    local room = Game():GetRoom()
    local position = room:FindFreePickupSpawnPosition(room:GetCenterPos() + Vector((index - 2) * 80, -70), 0, true)
    local p = Game():Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, position,
        Vector.Zero, nil, CollectibleType.COLLECTIBLE_SAD_ONION, seed):ToPickup()
    assert(p, "fixture spawn failed")
    return p
end

local function fixtureEvidence(ctx)
    local spawned, live = {}, {}
    for _, row in ipairs(ctx.spawnedFixtures or {}) do
        spawned[#spawned + 1] = row.initial .. "->" .. C.describeEntity(row.pointer.Ref)
    end
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type == EntityType.ENTITY_PICKUP then live[#live + 1] = C.describeEntity(entity) end
    end
    local trace = ctx.fixtureTrace or {}
    return string.format("room=%s target=%s roomAge=%s mode=%s spawned=[%s] livePickups=[%s] trace=[%s] removalStack=%s",
        tostring(Game():GetLevel():GetCurrentRoomIndex()), tostring(ctx.roomGrid),
        tostring(Game():GetRoom():GetFrameCount()), tostring(RoomTransition.GetTransitionMode()),
        table.concat(spawned, ";"), table.concat(live, ";"), table.concat(trace.events or {}, "|"),
        trace.removalStack or "unavailable (no Lua caller attribution)")
end

local function prepare(plan, recipe, arm)
    plan.act(function(player, ctx)
        ctx.recipe, ctx.arm = recipe.name, arm
        ctx.cleanupFns = ctx.cleanupFns or {}
        local controls = player.ControlsEnabled
        player.ControlsEnabled = false
        ctx.cleanupFns[#ctx.cleanupFns + 1] = function()
            capture, fixtureCapture = nil, nil
            if player:Exists() then player.ControlsEnabled = controls end
        end
        H.suppressRandomGoldenPedestals(ctx)
    end)
    plan.require("native card and read-only pool observation available", function(player)
        local pool = Game():GetItemPool()
        return (Card and Card.CARD_SOUL_ISAAC and type(player.UseCard) == "function"
            and observerMode ~= "unavailable" and type(pool.GetNumItemPools) == "function"
            and type(pool.GetCollectiblesFromPool) == "function" and type(pool.GetPoolForRoom) == "function") and true or nil,
            "Soul of Isaac, POST_GET_COLLECTIBLE and native pool inspection/mapping required"
    end)
    plan.require("native room transition completion observable", function()
        return (ModCallbacks.MC_POST_NEW_ROOM and RoomTransition
            and type(RoomTransition.GetTransitionMode) == "function") and true or nil,
            "POST_NEW_ROOM and RoomTransition.GetTransitionMode required; room index alone is insufficient"
    end)
    plan.require("isolated travel curse control available", function()
        local level = Game():GetLevel()
        return (LevelCurse and type(LevelCurse.CURSE_OF_MAZE) == "number"
            and type(level.GetCurses) == "function" and type(level.RemoveCurses) == "function") and true or nil,
            "native curse query/removal required for exact-room comparison"
    end)
    plan.act(function(_, ctx)
        local level, maze = Game():GetLevel(), LevelCurse.CURSE_OF_MAZE
        ctx.travelCurseBefore = level:GetCurses()
        -- These arms already require a fresh run and unconditional final reset.
        -- Maze redirects native travel; remove only that fixture interference.
        if ctx.travelCurseBefore & maze ~= 0 then level:RemoveCurses(maze) end
    end)
    plan.require("isolated travel has no Maze redirection", function(_, ctx)
        local after = Game():GetLevel():GetCurses()
        return after == (ctx.travelCurseBefore & ~LevelCurse.CURSE_OF_MAZE),
            "curse mask before=" .. ctx.travelCurseBefore .. " after=" .. after .. "; only Maze may be removed"
    end)
    if recipe.gold and arm == "oath" then
        plan.require("optional held-active golden provider", function(_, ctx)
            local provider = Epiphany and type(Epiphany.HasGoldenItem) == "function" and Epiphany or GoldenItems
            ctx.gold = provider
            return (provider and type(provider.HasGoldenItem) == "function" and type(provider.SetGoldenItem) == "function"
                and type(provider.ExaustGoldenItem) == "function") and true or nil, "golden public query/set/exhaust APIs required"
        end)
    end
    visit(plan, recipe)
    plan.act(function(player)
        for _, p in ipairs(C.stock()) do p:Remove() end
        player.Position = Game():GetRoom():GetCenterPos() + Vector(0, 100)
        for _, name in ipairs(recipe.modifiers or {}) do player:AddCollectible(assert(CollectibleType[name]), 0, false) end
    end)
    plan.wait(4)
    plan.act(function(player, ctx)
        ctx.spawnedFixtures = {}
        ctx.fixtureTrace = {keys = {}, events = {}}
        fixtureCapture = ctx.fixtureTrace
        for i = 1, recipe.count or 1 do
            local p = fixture(player, i, 740000 + recipe.index * 10 + i)
            ctx.spawnedFixtures[#ctx.spawnedFixtures + 1] = {pointer = EntityPtr(p), initial = C.describeEntity(p)}
            fixtureCapture.keys[tostring(GetPtrHash(p)) .. ":" .. tostring(p.InitSeed)] = true
            traceFixture("spawn-return", p)
        end
    end)
    plan.wait(4)
    plan.require("native cycle inspection and rewrite capability", function(_, ctx)
        fixtureCapture = nil
        local stock = C.stock()
        if #stock ~= (recipe.count or 1) then
            return false, "unexpected fixture count=" .. #stock .. " expected=" .. (recipe.count or 1) .. "; " .. fixtureEvidence(ctx)
        end
        local p = stock[1]
        return (type(p.GetCollectibleCycle) == "function" and type(p.AddCollectibleCycle) == "function"
            and type(p.RemoveCollectibleCycle) == "function") or nil, "REPENTOGON cycle methods required"
    end)
    plan.act(function(_, ctx)
        -- Fixed-ID queue fixtures deliberately include duplicate head/tail IDs.
        -- Native modifier cases keep the engine-generated queue untouched.
        for i, p in ipairs(C.stock()) do
            if recipe.tail then
                p:RemoveCollectibleCycle()
                local ids = {CollectibleType.COLLECTIBLE_BREAKFAST, CollectibleType.COLLECTIBLE_SAD_ONION,
                    CollectibleType.COLLECTIBLE_BREAKFAST, CollectibleType.COLLECTIBLE_INNER_EYE}
                for n = 1, recipe.tail do assert(p:AddCollectibleCycle(ids[(n - 1) % #ids + 1]), "fixture append rejected") end
            end
            p.Price, p.ShopItemId, p.AutoUpdatePrice = recipe.metadata and i * 5 or 0, -1, false
            p.OptionsPickupIndex = recipe.metadata and 7201 or 0
        end
        ctx.fixtures = C.snapshot()
    end)
    plan.require("unowned fixture is valid before either implementation", function(player, ctx)
        if player:HasCollectible(ConchBlessing.ItemData.SEVERED_OATH.id) then return false, "Oath contaminated native baseline" end
        for _, row in ipairs(ctx.fixtures) do
            local expected = recipe.tail and recipe.tail + 1 or recipe.nativeSize
            if expected and #row.ring ~= expected then return false, "native choices=" .. #row.ring .. " expected=" .. expected end
        end
        return true, C.signature(ctx.fixtures, false)
    end)
    -- Both arms enter the same kind of room with the same initial fixtures.
    -- Pools/run seeds are independent: this is NOT an exact random-ID A/B test.
    enter(plan, "origin")
    plan.act(function(player, ctx)
        local id = ConchBlessing.ItemData.SEVERED_OATH.id
        if arm == "oath" then
            player:AddCollectible(id, 0, false, ActiveSlot.SLOT_PRIMARY)
            if ctx.gold then
                local wasGold = ctx.gold:HasGoldenItem(id, player, ActiveSlot.SLOT_PRIMARY) == true
                ctx.cleanupFns[#ctx.cleanupFns + 1] = function()
                    if wasGold then ctx.gold:SetGoldenItem(id, player, ActiveSlot.SLOT_PRIMARY)
                    else ctx.gold:ExaustGoldenItem(id, player, ActiveSlot.SLOT_PRIMARY) end
                end
                ctx.gold:SetGoldenItem(id, player, ActiveSlot.SLOT_PRIMARY)
                assert(ctx.gold:HasGoldenItem(id, player, ActiveSlot.SLOT_PRIMARY) == true, "held active upgrade rejected")
            end
        end
        if recipe.roomType then
            -- A real unrelated preview leaves misleading GetLastPool history.
            -- It is setup, outside the measured grant, in both independent arms.
            local other = ctx.expectedPool == ItemPoolType.POOL_TREASURE and ItemPoolType.POOL_SHOP or ItemPoolType.POOL_TREASURE
            Game():GetItemPool():GetCollectible(other, false, 470001, CollectibleType.COLLECTIBLE_BREAKFAST)
        end
        open(ctx, "grant", ctx.fixtures)
    end)
    enter(plan, "roomGrid")
    plan.act(function(player) if arm == "native" then soul(player, recipe.gold and 2 or 1) end end)
    plan.wait(8)
    close(plan, function(_, _, w) return C.cycleAdditions(w.before, w.after, recipe.gold and 2 or 1) end, true, true)
    plan.check("new choices follow this room's pool (unknown final overrides require review)", function(_, ctx)
        return ctx.window.audit.source, ctx.window.audit.sourceDetail
    end)
    plan.check("no new same-pedestal or cross-pedestal overlaps (existing duplicates preserved)", function(_, ctx)
        return ctx.window.audit.overlap, ctx.window.audit.overlapDetail
    end)
    plan.check("no charge when the full queue delivered no additional choice", function(_, ctx)
        local w = ctx.window
        if C.total(w.after) ~= C.total(w.before) then return true, "bonus delivered; draw amplification is reported as DIAG" end
        return C.noCharge(w)
    end)
    phase(plan, "idle", nil, 96, unchanged)
end

local function rewrite(plan, targetField)
    phase(plan, "same_seed_rewrite", function(_, ctx)
        local stock, p = C.stock()
        if targetField then
            for _, candidate in ipairs(stock) do
                if tostring(GetPtrHash(candidate)) .. ":" .. candidate.InitSeed == ctx[targetField] then p = candidate; break end
            end
        else p = stock[1] end
        assert(p, "missing exact rewrite target")
        local seed, pointer = p.InitSeed, GetPtrHash(p)
        ctx.rewriteExpected = C.copyRows(ctx.window.before)
        for _, row in ipairs(ctx.rewriteExpected) do
            if row.key == tostring(pointer) .. ":" .. seed then
                row.ring = {CollectibleType.COLLECTIBLE_SPOON_BENDER,
                    CollectibleType.COLLECTIBLE_INNER_EYE, CollectibleType.COLLECTIBLE_INNER_EYE}
            end
        end
        p:Morph(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, CollectibleType.COLLECTIBLE_SPOON_BENDER, true, true, true)
        assert(p.InitSeed == seed and GetPtrHash(p) == pointer, "keep-seed Morph changed identity")
        p:RemoveCollectibleCycle()
        assert(p:AddCollectibleCycle(CollectibleType.COLLECTIBLE_INNER_EYE))
        assert(p:AddCollectibleCycle(CollectibleType.COLLECTIBLE_INNER_EYE))
    end, 64, function(_, ctx, w)
        if C.signature(ctx.rewriteExpected, true) ~= C.signature(w.after, true) then return false, "external rewrite resurrected/changed choices or sibling" end
        return C.noCharge(w)
    end)
    phase(plan, "clear_tail", function(_, ctx)
        ctx.rewriteExpected = C.copyRows(ctx.window.before)
        for _, row in ipairs(ctx.rewriteExpected) do row.ring = {row.ring[1]} end
        for _, p in ipairs(C.stock()) do p:RemoveCollectibleCycle() end
    end, 64, function(_, ctx, w)
        if C.signature(ctx.rewriteExpected, true) ~= C.signature(w.after, true) then return false, "cleared historical choices returned" end
        return C.noCharge(w)
    end)
end

local function copying(plan)
    phase(plan, "diplopia", function(player) player:UseActiveItem(CollectibleType.COLLECTIBLE_DIPLOPIA, UseFlag.USE_NOANIM, -1) end,
        8, function(_, ctx, w)
            if #w.before ~= 1 or #w.after ~= 2 then return false, "Diplopia must produce two live pedestals" end
            local original, duplicate
            for _, row in ipairs(w.after) do
                if row.key == w.before[1].key then original = row else duplicate = row end
            end
            if not original or not duplicate or w.after[1].key == w.after[2].key then
                return false, "missing original or distinct native copy identity"
            end
            if C.signature({original}, true, false) ~= C.signature(w.before, true, false) then
                return false, "Diplopia changed original circular sequence"
            end
            -- Native control: Diplopia copies the displayed item, not its
            -- entire rotating queue. Requiring two full queues prevented the
            -- actual same-seed isolation test from ever running.
            if #duplicate.ring ~= 1 or duplicate.ring[1] ~= w.before[1].ring[1] then
                return false, "Diplopia copy differs from displayed original item"
            end
            ctx.copyKey = duplicate.key
            return C.noCharge(w)
        end, true)
    plan.note("copy seeds/pointers (equal seeds are allowed)", function(_, ctx)
        local a, b = ctx.window.after[1], ctx.window.after[2]
        return a.key .. " / " .. b.key .. "; seedEqual=" .. tostring(a.seed == b.seed)
    end)
    rewrite(plan, "copyKey") -- rewrite the exact copy; preserve the original as its sibling oracle
end

local function dice(plan)
    for n = 1, 5 do
        local name = n == 5 and "d100" or "d6_" .. n
        phase(plan, name, function(player)
            player:UseActiveItem(n == 5 and CollectibleType.COLLECTIBLE_D100 or CollectibleType.COLLECTIBLE_D6, UseFlag.USE_NOANIM, -1)
        end, 8, function(player, _, w)
            if #w.after ~= #w.before then return false, "reroll changed pedestal count" end
            local expected = {}
            for _, row in ipairs(w.before) do expected[row.anchor] = C.metadata(row) end
            for _, row in ipairs(w.after) do
                if expected[row.anchor] ~= C.metadata(row) then return false, "reroll changed pedestal price/options contract" end
                if player:HasCollectible(ConchBlessing.ItemData.SEVERED_OATH.id) and #row.ring < 2 then return false, "held Oath lost its reroll bonus" end
            end
            return true, "actual dice result; IDs may change; D100 may also remove the held active"
        end)
        phase(plan, name .. "_settle", nil, 64, unchanged)
    end
end

local function lateStock(plan, arm)
    phase(plan, "late_spawn", function(player, ctx)
        ctx.oldStock = C.snapshot()
        local p = fixture(player, 3, 920001)
        ctx.lateAnchor = string.format("%.0f,%.0f", p.Position.X, p.Position.Y)
    end, 8, function(_, ctx, w)
        local old, new = {}, {}
        for _, row in ipairs(w.after) do
            if row.anchor == ctx.lateAnchor then new[#new + 1] = row else old[#old + 1] = row end
        end
        if C.signature(old, true) ~= C.signature(ctx.oldStock, true) then return false, "late spawn changed old stock" end
        if #new ~= 1 or #new[1].ring ~= (arm == "oath" and 2 or 1) then return false, "late-spawn scope differs from arm contract" end
        return true, arm == "native" and "native one-shot card does not cover future spawns" or "only newly eligible pedestal gains +1"
    end)
    if arm == "native" then
        phase(plan, "card_reapply", function(player) soul(player, 1) end, 8,
            function(_, _, w) return C.additions(w.before, w.after, 1) end)
    else
        phase(plan, "owner_loss", function(player)
            player:RemoveCollectible(ConchBlessing.ItemData.SEVERED_OATH.id, true, ActiveSlot.SLOT_PRIMARY)
        end, 8, unchanged)
        phase(plan, "unowned_spawn", function(player, ctx)
            local p = fixture(player, 2, 920002)
            ctx.unownedKey = tostring(GetPtrHash(p)) .. ":" .. p.InitSeed
        end, 8, function(_, ctx, w)
            local old, new = {}, {}
            for _, row in ipairs(w.after) do
                if row.key == ctx.unownedKey then new[#new + 1] = row else old[#old + 1] = row end
            end
            if #new ~= 1 or #new[1].ring ~= 1 then return false, "unowned spawn gained a bonus" end
            if C.signature(old, true) ~= C.signature(w.before, true) then return false, "unowned spawn changed existing paid choices" end
            return C.noCharge(w)
        end)
        plan.act(function(player, ctx)
            ctx.preReacquire = C.snapshot()
            player:AddCollectible(ConchBlessing.ItemData.SEVERED_OATH.id, 0, false, ActiveSlot.SLOT_PRIMARY)
        end)
        enter(plan, "origin")
        enter(plan, "roomGrid")
        plan.wait(8)
        plan.check("reacquisition pays only the previously unowned pedestal", function(_, ctx)
            local after = C.snapshot()
            for _, old in ipairs(ctx.preReacquire) do
                local found
                for _, row in ipairs(after) do
                    if row.anchor == old.anchor then
                        found = true
                        local ok, reason = C.addition(old, row, #old.ring == 1 and 1 or 0)
                        if not ok then return false, reason end
                    end
                end
                if not found then return false, "pedestal missing after reacquisition" end
            end
            return #after == #ctx.preReacquire, "existing paid choices retained, unpaid stock gains +1"
        end)
    end
end

local recipes = {}
for tail = 0, 8 do recipes[#recipes + 1] = {name = "capacity" .. tail, tail = tail} end
for _, recipe in ipairs({
    {name = "duplicates_metadata", tail = 4, count = 3, metadata = true},
    {name = "copy", tail = 3, event = "copy"}, {name = "rewrite", tail = 3, event = "rewrite"},
    {name = "dice", tail = 0, event = "dice"}, {name = "late_stock", tail = 0, event = "late"},
    {name = "crown", modifiers = {"COLLECTIBLE_GLITCHED_CROWN"}, nativeSize = 5},
    {name = "binge", modifiers = {"COLLECTIBLE_BINGE_EATER"}, nativeSize = 2},
    {name = "crown_binge", modifiers = {"COLLECTIBLE_GLITCHED_CROWN", "COLLECTIBLE_BINGE_EATER"}},
    {name = "birthright", modifiers = {"COLLECTIBLE_BIRTHRIGHT"}, nativeSize = 2},
    {name = "golden0", tail = 0, gold = true}, {name = "golden7", tail = 7, gold = true},
    {name = "golden8", tail = 8, gold = true},
    {name = "room_treasure", tail = 0, count = 4, roomType = "ROOM_TREASURE"},
    {name = "room_shop", tail = 0, count = 4, roomType = "ROOM_SHOP"},
    {name = "room_boss", tail = 0, count = 4, roomType = "ROOM_BOSS"},
    {name = "room_secret", tail = 0, count = 4, roomType = "ROOM_SECRET"},
}) do recipes[#recipes + 1] = recipe end

for index, recipe in ipairs(recipes) do
    recipe.index = index
    for _, arm in ipairs({"native", "oath"}) do
        M.commands[#M.commands + 1] = S.add("SEVERED_OATH", "compare_" .. recipe.name .. "_" .. arm,
            {conditions = true, cycle_compare = true}, function(plan)
                prepare(plan, recipe, arm)
                if recipe.event == "copy" then copying(plan)
                elseif recipe.event == "rewrite" then rewrite(plan)
                elseif recipe.event == "dice" then dice(plan)
                elseif recipe.event == "late" then lateStock(plan, arm) end
                -- Native foreign card addition is also tested while Oath is held.
                if recipe.event == "rewrite" then
                    phase(plan, "external_soul", function(player) soul(player, 1) end, 8,
                        function(_, _, w) return C.additions(w.before, w.after, 1) end)
                    phase(plan, "external_soul_settle", nil, 64, unchanged)
                end
                revisit(plan)
            end)
    end
end
return M
