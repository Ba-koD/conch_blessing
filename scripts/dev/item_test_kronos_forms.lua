local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- Transformation (set) progress of the familiars Kronos and Thurisaz absorb.
-- The engine counts items toward a transformation per collectible; these cases
-- read its own counters (REPENTOGON GetPlayerFormCounter) and the base
-- HasPlayerForm, never this mod's ledger.
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")

local function C(name) return assert(CollectibleType["COLLECTIBLE_" .. name], "unresolved collectible " .. name) end
local function form(name) return assert(PlayerForm["PLAYERFORM_" .. name], "unresolved player form " .. name) end
local function kronosId() return ConchBlessing.ItemData.KRONOS.id end

local function requireCounters(plan)
    plan.require("transformation counters readable", function(player)
        return type(player.GetPlayerFormCounter) == "function" and type(player.HasPlayerForm) == "function" or nil,
            "needs REPENTOGON's GetPlayerFormCounter"
    end)
end

local function describe(player, formName, ids)
    local id = form(formName)
    local parts = { string.format("%s counter=%d form=%s", formName, player:GetPlayerFormCounter(id),
        tostring(player:HasPlayerForm(id))) }
    for _, name in ipairs(ids or {}) do
        parts[#parts + 1] = string.format("%s=%d", name, player:GetCollectibleNum(C(name), true))
    end
    return table.concat(parts, " ")
end

-- A real pedestal pickup: the engine adds the item after the hold-up, exactly
-- as when the player walks over it. `name` is a CollectibleType name, or a
-- function returning an ID found while the bench runs.
local function pickUp(plan, name)
    local function id(ctx) return type(name) == "function" and name(ctx) or C(name) end
    local label = type(name) == "function" and "the found item" or name
    plan.act(function(player, ctx)
        H.suppressRandomGoldenPedestals(ctx)
        local position = Game():GetRoom():GetCenterPos() + Vector(140, 0)
        ctx.pickup = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, id(ctx), position,
            Vector.Zero, nil):ToPickup()
        ctx.pickup.Wait = 0
        player.Position = position
    end)
    plan.waitUntil(function(player, ctx)
        return ctx.pickup and ctx.pickup.SubType ~= id(ctx) and player:IsItemQueueEmpty(), "pedestal still holds " .. label
    end, 180, "picked up " .. label)
    plan.act(function(player, ctx)
        if ctx.pickup and ctx.pickup:Exists() then ctx.pickup:Remove() end
        ctx.pickup = nil
        player.Position = Game():GetRoom():GetCenterPos()
    end)
    plan.wait(2)
end

-- Measurement only: what the engine itself does to a transformation counter.
S.add("KRONOS", "transformation_engine", {}, function(plan)
    requireCounters(plan)
    local ids = { "BROTHER_BOBBY", "GUARDIAN_ANGEL", "DRY_BABY" }
    local function step(label, fn)
        if fn then plan.act(fn) end
        plan.wait(2)
        plan.note(label, function(player) return describe(player, "BABY", ids) end)
    end
    step("start")
    step("AddCollectible(Bobby, FirstTimePickingUp=true)", function(player) player:AddCollectible(C("BROTHER_BOBBY"), 0, true) end)
    step("same item again (duplicate)", function(player) player:AddCollectible(C("BROTHER_BOBBY"), 0, true) end)
    step("AddCollectible(Guardian Angel, FirstTimePickingUp=false)", function(player) player:AddCollectible(C("GUARDIAN_ANGEL"), 0, false) end)
    step("RemoveCollectible(Guardian Angel, RemoveFromPlayerForm=false)", function(player)
        player:RemoveCollectible(C("GUARDIAN_ANGEL"), false, ActiveSlot.SLOT_PRIMARY, false)
    end)
    step("RemoveCollectible(Bobby) default", function(player) player:RemoveCollectible(C("BROTHER_BOBBY")) end)
    pickUp(plan, "DRY_BABY")
    step("pedestal pickup of Dry Baby")
    step("AddCollectible(Guardian Angel, true): third baby item", function(player) player:AddCollectible(C("GUARDIAN_ANGEL"), 0, true) end)
    step("RemoveCollectible(Dry Baby) default after the transformation", function(player) player:RemoveCollectible(C("DRY_BABY")) end)
    step("RemoveCollectible(Guardian Angel) default", function(player) player:RemoveCollectible(C("GUARDIAN_ANGEL")) end)
    step("AddCollectible(Kronos): Kronos absorbs Bobby", function(player) player:AddCollectible(kronosId(), 0, false) end)
    plan.waitUntil(function(player) return player:GetCollectibleNum(C("BROTHER_BOBBY"), true) == 0 end, 120, "Bobby absorbed")
    plan.wait(4)
    step("after the absorption")
    step("Kronos removed: Bobby returns", function(player) player:RemoveCollectible(kronosId()) end)
    plan.waitUntil(function(player) return player:GetCollectibleNum(C("BROTHER_BOBBY"), true) == 1 end, 120, "Bobby returned")
    plan.wait(4)
    step("after the release")
    step("Sacrificial Altar sacrifices the returned Bobby", function(player)
        player:UseActiveItem(C("SACRIFICIAL_ALTAR"), UseFlag.USE_NOANIM, -1)
    end)
    plan.wait(10)
    step("after the Altar")
    step("Bobby picked up again (true)", function(player) player:AddCollectible(C("BROTHER_BOBBY"), 0, true) end)
    step("Guardian Angel added uncounted (false)", function(player) player:AddCollectible(C("GUARDIAN_ANGEL"), 0, false) end)
    step("RemoveCollectible(Guardian Angel) default on the uncounted copy", function(player)
        player:RemoveCollectible(C("GUARDIAN_ANGEL"))
    end)
    step("two more baby items counted", function(player)
        player:AddCollectible(C("DRY_BABY"), 0, true)
        player:AddCollectible(C("GUARDIAN_ANGEL"), 0, true)
    end)
    step("IncrementPlayerFormCounter(BABY, +1)", function(player)
        if type(player.IncrementPlayerFormCounter) == "function" then player:IncrementPlayerFormCounter(form("BABY"), 1) end
    end)
    step("IncrementPlayerFormCounter(BABY, -1)", function(player)
        if type(player.IncrementPlayerFormCounter) == "function" then player:IncrementPlayerFormCounter(form("BABY"), -1) end
    end)
    step("Sacrificial Altar sacrifices two of the three", function(player)
        player:UseActiveItem(C("SACRIFICIAL_ALTAR"), UseFlag.USE_NOANIM, -1)
    end)
    plan.wait(10)
    step("after the second Altar")
    local angels = { "SERAPHIM", "SACRED_HEART", "HALO" }
    local function angel(label, fn)
        if fn then plan.act(fn) end
        plan.wait(2)
        plan.note(label, function(player) return describe(player, "ANGEL", angels) .. "; " .. describe(player, "BABY") end)
    end
    plan.note("runtime ItemConfig tags", function()
        local parts = {}
        for _, name in ipairs({ "SERAPHIM", "SACRED_HEART", "BROTHER_BOBBY" }) do
            local config = Isaac.GetItemConfig():GetCollectible(C(name))
            parts[#parts + 1] = string.format("%s angel=%s baby=%s tags=%s", name, tostring(config:HasTags(ItemConfig.TAG_ANGEL)),
                tostring(config:HasTags(ItemConfig.TAG_BABY)), tostring(config.Tags))
        end
        return table.concat(parts, "; ")
    end)
    angel("angel set start")
    angel("AddCollectible(Seraphim, true)", function(player) player:AddCollectible(C("SERAPHIM"), 0, true) end)
    angel("AddCollectible(Sacred Heart, true)", function(player) player:AddCollectible(C("SACRED_HEART"), 0, true) end)
    angel("AddCollectible(The Halo, true)", function(player) player:AddCollectible(C("HALO"), 0, true) end)
    angel("RemoveCollectible(Seraphim) default", function(player) player:RemoveCollectible(C("SERAPHIM")) end)
    -- Items with two transformation tags.
    local function forms(label, fn)
        if fn then plan.act(fn) end
        plan.wait(2)
        plan.note(label, function(player)
            local parts = {}
            for _, name in ipairs({ "LORD_OF_THE_FLIES", "POOP", "SPIDERBABY", "BABY", "ANGEL" }) do
                parts[#parts + 1] = name .. "=" .. player:GetPlayerFormCounter(form(name))
            end
            return table.concat(parts, " ")
        end)
    end
    forms("two-tag items start")
    forms("AddCollectible(Skatole: poop fly, true)", function(player) player:AddCollectible(C("SKATOLE"), 0, true) end)
    forms("AddCollectible(Hive Mind: spider fly, true)", function(player) player:AddCollectible(C("HIVE_MIND"), 0, true) end)
    forms("RemoveCollectible(Skatole) default", function(player) player:RemoveCollectible(C("SKATOLE")) end)
    forms("RemoveCollectible(Hive Mind) default", function(player) player:RemoveCollectible(C("HIVE_MIND")) end)
    forms("AddCollectible(Seraphim, true) again", function(player) player:AddCollectible(C("SERAPHIM"), 0, true) end)
    forms("Sacrificial Altar sacrifices Seraphim", function(player)
        player:UseActiveItem(C("SACRIFICIAL_ALTAR"), UseFlag.USE_NOANIM, -1)
    end)
end)
S.rows[#S.rows].manual = true

-- ------------------------------------------------------------ gameplay contract
-- Expected counters are the engine's own rule applied to what the player really
-- picked up: +1 per first pickup of an item carrying the transformation's tag.
local TAGS = { BABY = "BABY", LORD_OF_THE_FLIES = "FLY", ANGEL = "ANGEL" }

local function tagged(id, formName)
    local config = Isaac.GetItemConfig():GetCollectible(id)
    return config and config:HasTags(ItemConfig["TAG_" .. TAGS[formName]]) and 1 or 0
end

local function inventory(player)
    local rows = {}
    for id = 1, Isaac.GetItemConfig():GetCollectibles().Size - 1 do
        local count = player:GetCollectibleNum(id, true)
        if count > 0 then rows[id] = count end
    end
    return rows
end

-- What real collectibles gained or lost since `before` add to a counter, leaving
-- out the familiars whose count Kronos keeps while they are absorbed.
local function taggedChange(player, before, formName, exclude)
    local skip, change = {}, 0
    for _, name in ipairs(exclude or {}) do skip[C(name)] = true end
    local after = inventory(player)
    local seen = {}
    for id, count in pairs(after) do
        seen[id] = true
        if not skip[id] then change = change + (count - (before[id] or 0)) * tagged(id, formName) end
    end
    for id, count in pairs(before) do
        if not seen[id] and not skip[id] then change = change - count * tagged(id, formName) end
    end
    return change
end

local function recordBase(plan)
    plan.act(function(player, ctx)
        ctx.formBase = {}
        for name in pairs(TAGS) do ctx.formBase[name] = player:GetPlayerFormCounter(form(name)) end
    end)
end

-- offset: counts above the run's starting counter; transformed: expected
-- HasPlayerForm, or nil to leave it unchecked. Either may be a function.
local function expectCounter(plan, label, formName, offset, transformed)
    plan.check(label, function(player, ctx)
        local id = form(formName)
        local expected = ctx.formBase[formName] + (type(offset) == "function" and offset(player, ctx) or offset)
        local wanted = transformed
        if type(wanted) == "function" then wanted = wanted(player, ctx) end
        local actual, has = player:GetPlayerFormCounter(id), player:HasPlayerForm(id)
        local detail = string.format("%s counter=%d expected=%d; transformed=%s", formName, actual, expected, tostring(has))
        if wanted ~= nil then detail = detail .. " expected=" .. tostring(wanted) end
        return actual == expected and (wanted == nil or has == wanted), detail
    end)
end

local function giveKronos(plan, id)
    plan.act(function(player) player:AddCollectible(id, 0, false) end)
end

local function absorbed(plan, name, copies)
    plan.waitUntil(function(player)
        local owned, ledger = player:GetCollectibleNum(C(name), true), ConchBlessing.kronos._getAbsorbedCount(player, C(name))
        return owned == 0 and ledger >= (copies or 1), string.format("%s owned=%d absorbed=%d", name, owned, ledger)
    end, 120, "Kronos absorbs " .. name)
    plan.wait(4)
end

local function loseKronos(plan, id, names)
    plan.act(function(player) while player:HasCollectible(id) do player:RemoveCollectible(id) end end)
    plan.waitUntil(function(player)
        for _, name in ipairs(names) do
            if player:GetCollectibleNum(C(name), true) < 1 then return false, name .. " not returned yet" end
        end
        return true
    end, 120, "losing Kronos returns the familiars")
    plan.wait(4)
end

local GROUPS = { conditions = true }

-- The altar's devil items stay out of the next pickup's way.
local function clearPedestals(plan)
    plan.act(function()
        for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE)) do
            entity:Remove()
        end
    end)
    plan.wait(2)
end

-- 1. The familiar was picked up before Kronos.
S.add("KRONOS", "transformation_before", GROUPS, function(plan, id)
    requireCounters(plan)
    recordBase(plan)
    pickUp(plan, "BROTHER_BOBBY")
    expectCounter(plan, "a normal pickup counts Brother Bobby toward Conjoined", "BABY", 1, false)
    giveKronos(plan, id)
    absorbed(plan, "BROTHER_BOBBY")
    expectCounter(plan, "Kronos absorbing Bobby keeps its Conjoined progress", "BABY", 1, false)
    loseKronos(plan, id, { "BROTHER_BOBBY" })
    expectCounter(plan, "losing Kronos returns Bobby without counting it twice", "BABY", 1, false)
end)

-- 2. The familiar was picked up while holding Kronos.
S.add("KRONOS", "transformation_after", GROUPS, function(plan, id)
    requireCounters(plan)
    recordBase(plan)
    giveKronos(plan, id)
    plan.wait(4)
    pickUp(plan, "BROTHER_BOBBY")
    absorbed(plan, "BROTHER_BOBBY")
    expectCounter(plan, "Bobby picked up while holding Kronos counts toward Conjoined", "BABY", 1, false)
    loseKronos(plan, id, { "BROTHER_BOBBY" })
    expectCounter(plan, "losing Kronos returns Bobby without counting it twice", "BABY", 1, false)
end)

-- 3. Absorbed familiars add to progress the player already has and complete the
-- transformation at 3, as normal pickups do (Beelzebub: The Mulligan is held).
S.add("KRONOS", "transformation_progress", GROUPS, function(plan, id)
    requireCounters(plan)
    recordBase(plan)
    pickUp(plan, "MULLIGAN")
    expectCounter(plan, "The Mulligan, held as usual, gives 1 of 3 toward Beelzebub", "LORD_OF_THE_FLIES", 1, false)
    giveKronos(plan, id)
    pickUp(plan, "HALO_OF_FLIES")
    absorbed(plan, "HALO_OF_FLIES")
    expectCounter(plan, "absorbed Halo of Flies adds to it: 2 of 3, not yet Beelzebub", "LORD_OF_THE_FLIES", 2, false)
    pickUp(plan, "DISTANT_ADMIRATION")
    absorbed(plan, "DISTANT_ADMIRATION")
    expectCounter(plan, "the third fly item, absorbed, completes Beelzebub", "LORD_OF_THE_FLIES", 3, true)
    loseKronos(plan, id, { "HALO_OF_FLIES", "DISTANT_ADMIRATION" })
    expectCounter(plan, "losing Kronos keeps exactly 3 and Beelzebub", "LORD_OF_THE_FLIES", 3, true)
end)

-- The angel set through a conversion: Seraphim keeps its own count while it is
-- absorbed, and the Sacred Heart it turns into counts like any item picked up.
S.add("KRONOS", "transformation_conversion", GROUPS, function(plan, id)
    requireCounters(plan)
    recordBase(plan)
    local function trail(label)
        plan.note(label, function(player)
            return describe(player, "ANGEL", { "HALO", "SERAPHIM", "SACRED_HEART" }) .. "; " .. describe(player, "BABY")
        end)
    end
    -- The engine counts by the runtime ItemConfig tags; the current base game lists
    -- Seraphim under baby only (2026-10-29), so the expectations read them too.
    local function angels(player, names)
        local total = 0
        for _, name in ipairs(names) do total = total + tagged(C(name), "ANGEL") end
        return total
    end
    local held = { "HALO", "SERAPHIM", "SACRED_HEART" }
    pickUp(plan, "HALO")
    trail("after The Halo")
    giveKronos(plan, id)
    pickUp(plan, "SERAPHIM")
    absorbed(plan, "SERAPHIM")
    plan.waitUntil(function(player) return player:HasCollectible(C("SACRED_HEART"), true) end, 60, "Seraphim converts into Sacred Heart")
    trail("after the conversion")
    expectCounter(plan, "The Halo, absorbed Seraphim and its Sacred Heart count toward the angel set", "ANGEL",
        function(player) return angels(player, held) end, false)
    expectCounter(plan, "absorbed Seraphim keeps its Conjoined count", "BABY", function() return tagged(C("SERAPHIM"), "BABY") end, false)
    pickUp(plan, "ROSARY")
    expectCounter(plan, "a third angel item completes Seraphim on top of the absorbed familiar's conversion", "ANGEL",
        function(player) return angels(player, { "HALO", "SERAPHIM", "SACRED_HEART", "ROSARY" }) end,
        function(player) return angels(player, { "HALO", "SERAPHIM", "SACRED_HEART", "ROSARY" }) >= 3 end)
    loseKronos(plan, id, { "SERAPHIM" })
    plan.check("losing Kronos takes the converted Sacred Heart back", function(player)
        return H.expect(player:GetCollectibleNum(C("SACRED_HEART"), true), 0)
    end)
    expectCounter(plan, "what remains is exactly The Halo, Rosary and the returned Seraphim", "ANGEL",
        function(player) return angels(player, { "HALO", "SERAPHIM", "ROSARY" }) end,
        function(player) return angels(player, { "HALO", "SERAPHIM", "ROSARY" }) >= 3 end)
    expectCounter(plan, "Seraphim's Conjoined count is unchanged after its return", "BABY",
        function() return tagged(C("SERAPHIM"), "BABY") end, false)
end)

-- Temporary sources add no progress, and familiars handed back (GB Bug, losing
-- Kronos) come back without counting twice.
S.add("KRONOS", "transformation_release", GROUPS, function(plan, id)
    requireCounters(plan)
    recordBase(plan)
    giveKronos(plan, id)
    pickUp(plan, "BROTHER_BOBBY")
    pickUp(plan, "DRY_BABY")
    absorbed(plan, "BROTHER_BOBBY")
    absorbed(plan, "DRY_BABY")
    expectCounter(plan, "two absorbed baby familiars count 2 of 3", "BABY", 2, false)
    local familiars = { "BROTHER_BOBBY", "DRY_BABY", "GB_BUG" }
    plan.act(function(player, ctx)
        ctx.inventory = inventory(player)
        player:UseActiveItem(C("BOX_OF_FRIENDS"), UseFlag.USE_NOANIM, -1)
    end)
    plan.wait(30)
    expectCounter(plan, "Box of Friends' temporary copies add no progress", "BABY",
        function(player, ctx) return 2 + taggedChange(player, ctx.inventory, "BABY", familiars) end, false)
    plan.act(function(player) player:UseActiveItem(C("MONSTER_MANUAL"), UseFlag.USE_NOANIM, -1) end)
    plan.wait(30)
    expectCounter(plan, "Monster Manual's temporary familiar adds none beyond real items it grants", "BABY",
        function(player, ctx) return 2 + taggedChange(player, ctx.inventory, "BABY", familiars) end, nil)
    pickUp(plan, "GB_BUG")
    absorbed(plan, "GB_BUG")
    plan.waitUntil(function(player)
        return player:GetCollectibleNum(C("BROTHER_BOBBY"), true) + player:GetCollectibleNum(C("DRY_BABY"), true) == 1,
            "GB Bug has not handed a familiar back"
    end, 60, "GB Bug hands back half of the absorbed familiars")
    expectCounter(plan, "the familiar GB Bug hands back is not counted twice", "BABY",
        function(player, ctx) return 2 + taggedChange(player, ctx.inventory, "BABY", familiars) + tagged(C("GB_BUG"), "BABY") end, nil)
    loseKronos(plan, id, familiars)
    expectCounter(plan, "losing Kronos returns the rest without counting them twice", "BABY",
        function(player, ctx) return 2 + taggedChange(player, ctx.inventory, "BABY", familiars) + tagged(C("GB_BUG"), "BABY") end, nil)
end)

-- An absorbed familiar sacrificed on Sacrificial Altar gives its count back, as
-- the vanilla altar does for a held familiar (measured first as the control).
S.add("KRONOS", "transformation_sacrifice", GROUPS, function(plan, id)
    requireCounters(plan)
    plan.require("transformation counter writable", function(player)
        return type(player.IncrementPlayerFormCounter) == "function" or nil, "needs REPENTOGON's IncrementPlayerFormCounter"
    end)
    recordBase(plan)
    pickUp(plan, "BROTHER_BOBBY")
    plan.act(function(player, ctx)
        ctx.controlBefore = player:GetPlayerFormCounter(form("BABY"))
        player:UseActiveItem(C("SACRIFICIAL_ALTAR"), UseFlag.USE_NOANIM, -1)
    end)
    plan.wait(10)
    clearPedestals(plan)
    plan.require("vanilla control: the altar sacrifices a held Bobby and takes its count", function(player, ctx)
        ctx.perFamiliar = ctx.controlBefore - player:GetPlayerFormCounter(form("BABY"))
        return player:GetCollectibleNum(C("BROTHER_BOBBY"), true) == 0 and ctx.perFamiliar == 1,
            string.format("Bobby=%d, counter %d -> %d", player:GetCollectibleNum(C("BROTHER_BOBBY"), true),
                ctx.controlBefore, player:GetPlayerFormCounter(form("BABY")))
    end)
    plan.act(function(player, ctx) ctx.formBase.BABY = player:GetPlayerFormCounter(form("BABY")) end)
    giveKronos(plan, id)
    pickUp(plan, "BROTHER_BOBBY")
    pickUp(plan, "DRY_BABY")
    absorbed(plan, "BROTHER_BOBBY")
    absorbed(plan, "DRY_BABY")
    expectCounter(plan, "two absorbed baby familiars count 2 of 3", "BABY", 2, false)
    plan.act(function(player) player:UseActiveItem(C("SACRIFICIAL_ALTAR"), UseFlag.USE_NOANIM, -1) end)
    plan.wait(10)
    clearPedestals(plan)
    plan.require("the altar sacrificed both absorbed familiars", function(player)
        local left = ConchBlessing.kronos._getAbsorbedCount(player, C("BROTHER_BOBBY"))
            + ConchBlessing.kronos._getAbsorbedCount(player, C("DRY_BABY"))
        return left == 0, "absorbed copies left=" .. left
    end)
    expectCounter(plan, "each sacrificed absorbed familiar gives its count back like a held one", "BABY",
        function(_, ctx) return 2 - 2 * ctx.perFamiliar end, false)
end)

-- Thurisaz devours a familiar for good; its progress stays as if still held.
S.add("KRONOS", "transformation_thurisaz", GROUPS, function(plan)
    requireCounters(plan)
    plan.require("Thurisaz registered", function()
        local data = ConchBlessing.PocketData and ConchBlessing.PocketData.THURISAZ
        return data and data.id and data.id > 0 or nil, "card id " .. tostring(data and data.id)
    end)
    recordBase(plan)
    pickUp(plan, "BROTHER_BOBBY")
    plan.act(function(player)
        player:UseCard(ConchBlessing.PocketData.THURISAZ.id, UseFlag.USE_NOANIM | UseFlag.USE_NOANNOUNCER)
    end)
    plan.waitUntil(function(player) return player:GetCollectibleNum(C("BROTHER_BOBBY"), true) == 0 end, 60, "Thurisaz devours Bobby")
    plan.wait(4)
    expectCounter(plan, "Bobby devoured by Thurisaz keeps its Conjoined progress", "BABY", 1, false)
end)

-- Items that count toward several transformations at once. Every transformation
-- an item can count toward, by the tag the engine reads at run time.
local ALL_FORMS = { GUPPY = "GUPPY", LORD_OF_THE_FLIES = "FLY", MUSHROOM = "MUSHROOM", ANGEL = "ANGEL", BOB = "BOB",
    DRUGS = "SYRINGE", MOM = "MOM", BABY = "BABY", EVIL_ANGEL = "DEVIL", POOP = "POOP", BOOK_WORM = "BOOK",
    SPIDERBABY = "SPIDER" }

local function formsOf(id)
    local config, list = Isaac.GetItemConfig():GetCollectible(id), {}
    if config then
        for name, tag in pairs(ALL_FORMS) do
            if config:HasTags(ItemConfig["TAG_" .. tag]) then list[#list + 1] = name end
        end
    end
    table.sort(list)
    return list, config
end

local function snapshotForms(plan)
    plan.act(function(player, ctx)
        ctx.allBase = {}
        for name in pairs(ALL_FORMS) do ctx.allBase[name] = player:GetPlayerFormCounter(form(name)) end
    end)
end

-- Every form of the item at `offset` above its snapshot, every other form unchanged.
local function expectForms(plan, label, idOf, offset)
    plan.check(label, function(player, ctx)
        local id = idOf(ctx)
        local mine, ok, parts = {}, true, {}
        for _, name in ipairs((formsOf(id))) do mine[name] = true end
        local names = {}
        for name in pairs(ALL_FORMS) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            local expected = ctx.allBase[name] + (mine[name] and offset or 0)
            local actual = player:GetPlayerFormCounter(form(name))
            if actual ~= expected then ok = false end
            if mine[name] or actual ~= expected then
                parts[#parts + 1] = string.format("%s=%d expected=%d", name, actual, expected)
            end
        end
        return ok, table.concat(parts, " ")
    end)
end

S.add("KRONOS", "transformation_multi", GROUPS, function(plan, id)
    requireCounters(plan)
    -- The production helpers on a real item with two transformation tags.
    local function skatole() return C("SKATOLE") end
    plan.require("Skatole counts toward two transformations", function()
        local forms = formsOf(C("SKATOLE"))
        return #forms >= 2 or nil, table.concat(forms, ", ")
    end)
    snapshotForms(plan)
    pickUp(plan, "SKATOLE")
    expectForms(plan, "picking Skatole up counts it toward each of its sets", skatole, 1)
    plan.act(function(player) ConchBlessing.kronos._removeKeepingForms(player, C("SKATOLE")) end)
    plan.wait(2)
    plan.require("Kronos's absorbing removal took Skatole", function(player)
        return H.expect(player:GetCollectibleNum(C("SKATOLE"), true), 0)
    end)
    expectForms(plan, "Kronos's absorbing removal keeps every one of its sets", skatole, 1)
    plan.act(function(player) player:AddCollectible(C("SKATOLE"), 0, false) end)
    plan.wait(2)
    expectForms(plan, "the release path brings it back without counting any set twice", skatole, 1)
    plan.require("transformation counter writable", function(player)
        return type(player.IncrementPlayerFormCounter) == "function" or nil, "needs REPENTOGON's IncrementPlayerFormCounter"
    end)
    plan.act(function(player)
        ConchBlessing.kronos._removeKeepingForms(player, C("SKATOLE"))
        ConchBlessing.kronos._withdrawForms(player, C("SKATOLE"), 1)
    end)
    plan.wait(2)
    expectForms(plan, "a used-up copy gives back its count in every one of its sets", skatole, 0)

    -- A familiar of this install that counts toward several sets, through Kronos.
    plan.act(function(_, ctx)
        ctx.multi = {}
        local blacklist = ConchBlessing.kronos.data.blacklist or {}
        for itemId = 1, Isaac.GetItemConfig():GetCollectibles().Size - 1 do
            local forms, config = formsOf(itemId)
            if config and #forms >= 2 then
                ctx.multi[#ctx.multi + 1] = { id = itemId, name = tostring(config.Name), forms = forms,
                    absorbable = config.Type == ItemType.ITEM_FAMILIAR and config.Hidden ~= true and not blacklist[itemId] }
            end
        end
    end)
    plan.note("items counting toward several sets (runtime tags)", function(_, ctx)
        local parts = {}
        for _, row in ipairs(ctx.multi) do
            parts[#parts + 1] = string.format("%d %s [%s]%s", row.id, row.name, table.concat(row.forms, "+"),
                row.absorbable and " familiar" or "")
        end
        return #parts > 0 and table.concat(parts, "; ") or "none"
    end)
    plan.require("an absorbable familiar counts toward several sets", function(_, ctx)
        for _, row in ipairs(ctx.multi) do
            if row.absorbable then
                ctx.target = row
                return true, string.format("%d %s [%s]", row.id, row.name, table.concat(row.forms, "+"))
            end
        end
        return nil, "no familiar in this install counts toward two sets at run time"
    end)
    local function target(ctx) return ctx.target.id end
    snapshotForms(plan)
    pickUp(plan, target)
    expectForms(plan, "picking the familiar up counts it toward each of its sets", target, 1)
    giveKronos(plan, id)
    plan.waitUntil(function(player, ctx)
        return player:GetCollectibleNum(ctx.target.id, true) == 0 and ConchBlessing.kronos._getAbsorbedCount(player, ctx.target.id) >= 1,
            "familiar still owned"
    end, 120, "Kronos absorbs the familiar")
    plan.wait(4)
    expectForms(plan, "absorbing it keeps every one of its sets", target, 1)
    plan.act(function(player) while player:HasCollectible(id) do player:RemoveCollectible(id) end end)
    plan.waitUntil(function(player, ctx) return player:GetCollectibleNum(ctx.target.id, true) == 1 end, 120, "losing Kronos returns it")
    plan.wait(4)
    expectForms(plan, "losing Kronos returns it without counting any set twice", target, 1)
end)

return {}
