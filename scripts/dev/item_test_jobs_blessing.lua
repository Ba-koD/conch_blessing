local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 욥의 축복 (Job's Blessing): the lifecycle contract and its cases. Every
-- acquisition is a real one: the player walks onto real pickups and
-- pedestals, uses real actives, pills and the Smelter, and every check reads
-- the engine's own counters (coins, hearts, smelted trinkets, item counts).
--
-- Expected amounts come from the user's rules (2026-11-18), never from the
-- implementation: a new passive comes twice, every trinket absorption twice,
-- every pickup absorbed on touch twice, every heal twice; actives, cards,
-- runes, pills and a trinket that only reaches the hand stay single; copies
-- never double again; and nothing appears on the floor that would not
-- without the item (the user, 2026-11-19: pickups only add their numbers once
-- more, nothing is spawned). Other acquisition doublers are measured first
-- without the item (the control arm) and then with it: the item arm must be
-- exactly twice the control.
--
-- Run sharing (user request 2026-11-19: fewer restarts). Every case judges
-- the change of the counters it reads between its own before and after, and
-- `fresh` puts back everything a case reads or that changes what the next one
-- sees (floor pickups, coins, keys, bombs, health, held trinkets, the active,
-- Job's Blessing itself; each case takes away the doubler it added). So the
-- cases run back to back in three shared runs (core, items, doublers); each
-- one stays callable alone with its own fresh run. Cases marked manual are
-- measurements (DIAG lines) run by name only.
local TestBench = require("scripts.dev.test_bench")
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")
local C = {}

local GOLDEN = TrinketType.TRINKET_GOLDEN_FLAG
local KEY = "JOBS_BLESSING"

-- Engine enums are read when a step runs, never while this file loads or a
-- plan is built: the offline bench loads and builds every case without the
-- engine's tables. Cases name them as "Table.KEY" strings.
local function enum(path)
    if type(path) ~= "string" then return path end
    local name, key = path:match("^([%w_]+)%.([%w_]+)$")
    return _G[name][key]
end
local GROUPS = { conditions = true }
local function J() return ConchBlessing.jobsblessing end
local function evidence() return J()._test.evidence() end
local function jobId() return ConchBlessing.ItemData.JOBS_BLESSING.id end

local rooms = 0
ConchBlessing:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function() rooms = rooms + 1 end)

-- ------------------------------------------------------------------ fixtures
local function room() return Game():GetRoom() end
local function spot(dx, dy) return room():GetCenterPos() + Vector(dx or 0, dy or 0) end

local seedCounter = 0
local function spawn(variant, subtype, dx, dy, seed)
    seedCounter = seedCounter + 1
    local entity = Game():Spawn(EntityType.ENTITY_PICKUP, variant, spot(dx, dy), Vector.Zero, nil, subtype,
        seed or (424242 + seedCounter * 7919))
    return entity:ToPickup()
end

local function blackCount(player)
    local mask, n = player:GetBlackHearts(), 0
    while mask > 0 do
        n = n + (mask & 1)
        mask = mask >> 1
    end
    return n
end

local function smeltedOf(player, id)
    if type(player.GetSmeltedTrinkets) ~= "function" then return 0, 0 end
    local entry = player:GetSmeltedTrinkets()[id]
    if type(entry) ~= "table" then return 0, 0 end
    return entry.trinketAmount or 0, entry.goldenTrinketAmount or 0
end

local function wallet(player)
    return {
        coins = player:GetNumCoins(), keys = player:GetNumKeys(), bombs = player:GetNumBombs(),
        red = player:GetHearts(), max = player:GetMaxHearts(), soul = player:GetSoulHearts(),
        black = blackCount(player), eternal = player:GetEternalHearts(), golden = player:GetGoldenHearts(),
        bone = player:GetBoneHearts(), rotten = player:GetRottenHearts(), broken = player:GetBrokenHearts(),
        luck = player.Luck, items = player:GetCollectibleCount(),
        charge = player:GetActiveCharge(ActiveSlot.SLOT_PRIMARY) + player:GetBatteryCharge(ActiveSlot.SLOT_PRIMARY),
        giga = type(player.GetNumGigaBombs) == "function" and player:GetNumGigaBombs() or 0,
    }
end

local function delta(a, b)
    local d = {}
    for k, v in pairs(b) do
        if type(v) == "number" then d[k] = v - (a[k] or 0) end
    end
    return d
end

local function describeDelta(d)
    local parts = {}
    for _, k in ipairs({ "coins", "keys", "bombs", "giga", "red", "max", "soul", "black", "eternal", "golden", "bone",
        "rotten", "broken", "luck", "charge", "items" }) do
        if d[k] and math.abs(d[k]) > 1e-6 then parts[#parts + 1] = string.format("%s%+g", k, d[k]) end
    end
    return #parts > 0 and table.concat(parts, " ") or "no change"
end

-- A pickup still lying on the floor (one playing Collect is already taken).
local function onFloor(variant, subtype)
    local n = 0
    for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, variant or -1, subtype or -1)) do
        if e:Exists() and e:ToPickup():GetSprite():GetAnimation() ~= "Collect" then n = n + 1 end
    end
    return n
end

local function requireModule(plan)
    plan.require("Job's Blessing module, REPENTOGON callbacks and the item ID", function()
        return J() and J()._test and J().available and jobId() > 0 and true or nil,
            string.format("module=%s available=%s id=%s", tostring(J() ~= nil), tostring(J() and J().available),
                tostring(jobId()))
    end)
end

local function hold(plan, copies)
    plan.act(function(player) S.collectible(player, jobId(), copies or 1) end)
end

local function pinOn(player, entity)
    player.Position = entity.Position
    player.Velocity = Vector.Zero
end

local function settled(player)
    return J()._test.pending()[GetPtrHash(player)] == nil
end

-- Walk onto ctx[key] until the engine takes it, then until the item's copy
-- (a queued collectible) has arrived.
local function take(plan, label, key)
    plan.waitUntil(function(player, ctx)
        local p = ctx[key]
        if not p or not p:Exists() then return player:IsItemQueueEmpty() end
        pinOn(player, p)
        if p.Variant == PickupVariant.PICKUP_COLLECTIBLE then
            return p.SubType == 0 and player:IsItemQueueEmpty(), "taking the pedestal"
        end
        return p:GetSprite():GetAnimation() == "Collect", "walking onto " .. label
    end, 150, label .. " is taken")
    plan.waitUntil(function(player)
        player.Velocity = Vector.Zero
        return settled(player), "its doubling on the way"
    end, 30, label .. ": its doubling has settled")
    plan.wait(2)
end

local function snapshot(plan)
    plan.act(function(player, ctx)
        ctx.before = wallet(player)
        ctx.floorBefore = onFloor(-1)
    end)
end

-- Back to a known state between shared cases, without the item: three full
-- red hearts and nothing else, no coins, keys or bombs, empty hands, no active,
-- nothing on the floor.
local function fresh(plan)
    plan.act(function(player)
        S.collectible(player, jobId(), 0)
        for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP)) do e:Remove() end
        for slot = 0, 1 do
            local t = player:GetTrinket(slot)
            if t > 0 then player:TryRemoveTrinket(t) end
        end
        for slot = 0, 1 do
            if player:GetCard(slot) > 0 then player:SetCard(slot, Card.CARD_NULL) end
            if player:GetPill(slot) > 0 then player:SetPill(slot, PillColor.PILL_NULL) end
        end
        for slot = ActiveSlot.SLOT_SECONDARY, ActiveSlot.SLOT_PRIMARY, -1 do
            local active = player:GetActiveItem(slot)
            if active > 0 then player:RemoveCollectible(active, true, slot) end
        end
        player:AddCoins(-player:GetNumCoins())
        player:AddKeys(-player:GetNumKeys())
        if type(player.GetNumGigaBombs) == "function" and type(player.AddGigaBombs) == "function" then
            player:AddGigaBombs(-player:GetNumGigaBombs())
        end
        player:AddBombs(-player:GetNumBombs())
        if player:HasGoldenKey() and type(player.RemoveGoldenKey) == "function" then player:RemoveGoldenKey() end
        if player:HasGoldenBomb() and type(player.RemoveGoldenBomb) == "function" then player:RemoveGoldenBomb() end
        player:AddBrokenHearts(-player:GetBrokenHearts())
        player:AddGoldenHearts(-player:GetGoldenHearts())
        player:AddEternalHearts(-player:GetEternalHearts())
        player:AddRottenHearts(-player:GetRottenHearts())
        player:AddBoneHearts(-player:GetBoneHearts())
        player:AddSoulHearts(-player:GetSoulHearts())
        player:AddMaxHearts(6 - player:GetMaxHearts())
        player:AddHearts(player:GetMaxHearts() - player:GetHearts())
        player.Position = spot(0, -60)
        player.Velocity = Vector.Zero
    end)
    plan.wait(2)
end

-- A case registered alone (with its own fresh run) and listed for a shared run.
local bundles = { core = {}, items = {}, doublers = {} }
local function case(bundle, name, build)
    S.add(KEY, name, GROUPS, build)
    table.insert(bundles[bundle], name)
end

-- ------------------------------------------------------------------ lifecycle
-- With n copies a real penny gives 2 coins (n > 0) or 1 (n == 0). The copies
-- are set as items handed back (FirstTime false): acquiring the item doubles
-- it like any other item, so a first-time add would give two (its own case).
C.JOBS_BLESSING = { change = function(player, item, previous, wanted)
    if wanted > previous then
        for _ = previous + 1, wanted do player:AddCollectible(item.id, 0, false) end
    else
        for _ = wanted + 1, previous do player:RemoveCollectible(item.id) end
    end
end, stage = function(plan, _, n)
    snapshot(plan)
    plan.act(function(_, ctx) ctx.p = spawn(PickupVariant.PICKUP_COIN, CoinSubType.COIN_PENNY, 0, 90) end)
    take(plan, "a penny", "p")
    plan.check(string.format("a penny gives %d coin(s) with %d cop%s", n > 0 and 2 or 1, n, n == 1 and "y" or "ies"),
        function(player, ctx)
            local d = player:GetNumCoins() - ctx.before.coins
            return d == (n > 0 and 2 or 1), "coins +" .. d
        end)
end }

-- ------------------------------------------------------------------ pickups
local function pickupCase(name, label, variant, subtype, expect, prepare, spawnsContents)
    case("core", name, function(plan)
        requireModule(plan)
        if prepare then plan.act(function(player, ctx) prepare(player, ctx) end) end
        hold(plan, 1)
        snapshot(plan)
        plan.act(function(_, ctx) ctx.p = spawn(enum(variant), enum(subtype), 0, 90) end)
        take(plan, label, "p")
        plan.check(label, function(player, ctx)
            local d = delta(ctx.before, wallet(player))
            local ok, why = expect(d, player, ctx)
            return ok, (why and why .. "; " or "") .. describeDelta(d)
        end)
        if not spawnsContents then
            plan.check(label .. ": nothing new appears on the floor", function(_, ctx)
                local floor = onFloor(-1)
                return floor == ctx.floorBefore, string.format("pickups on the floor %d -> %d", ctx.floorBefore, floor)
            end)
        end
    end)
end

local function exactly(field, amount, extra)
    return function(d, player, ctx)
        if d[field] ~= amount then return false, string.format("%s %+d, want %+d", field, d[field], amount) end
        if extra then return extra(d, player, ctx) end
        return true
    end
end

local function missing(n) return function(player) player:AddHearts(-n) end end

-- Without the item nothing doubles: the control arm of every pickup kind below.
case("core", "control", function(plan)
    requireModule(plan)
    plan.act(function(player, ctx)
        H.suppressRandomGoldenPedestals(ctx)
        player:AddHearts(-4)
    end)
    snapshot(plan)
    plan.act(function(_, ctx) ctx.p = spawn(PickupVariant.PICKUP_COIN, CoinSubType.COIN_NICKEL, 0, 90) end)
    take(plan, "a nickel", "p")
    plan.act(function(_, ctx) ctx.p = spawn(PickupVariant.PICKUP_HEART, HeartSubType.HEART_FULL, 0, 90) end)
    take(plan, "a red heart", "p")
    plan.act(function(_, ctx) ctx.p = spawn(PickupVariant.PICKUP_COLLECTIBLE, CollectibleType.COLLECTIBLE_SAD_ONION, 0, 90) end)
    take(plan, "a passive", "p")
    plan.act(function(player, ctx)
        ctx.smelted0 = smeltedOf(player, TrinketType.TRINKET_PETRIFIED_POOP)
        ctx.items0 = player:GetCollectibleNum(CollectibleType.COLLECTIBLE_SAD_ONION, true)
        player:AddTrinket(TrinketType.TRINKET_PETRIFIED_POOP, false)
        player:UseActiveItem(CollectibleType.COLLECTIBLE_SMELTER, UseFlag.USE_NOANIM)
        player:AddSoulHearts(2)
    end)
    plan.wait(6)
    plan.check("without the item: 5 coins, 1 heart healed, 1 item, 1 smelt, 1 soul heart", function(player, ctx)
        local d = delta(ctx.before, wallet(player))
        local n = smeltedOf(player, TrinketType.TRINKET_PETRIFIED_POOP) - ctx.smelted0
        return d.coins == 5 and d.red == 2 and d.items == 1 and n == 1 and d.soul == 2,
            string.format("%s smelted %+d", describeDelta(d), n)
    end)
end)

pickupCase("penny", "a penny gives 2 coins", "PickupVariant.PICKUP_COIN", "CoinSubType.COIN_PENNY", exactly("coins", 2))
pickupCase("nickel", "a nickel gives 10 coins", "PickupVariant.PICKUP_COIN", "CoinSubType.COIN_NICKEL", exactly("coins", 10))
pickupCase("dime", "a dime gives 20 coins", "PickupVariant.PICKUP_COIN", "CoinSubType.COIN_DIME", exactly("coins", 20))
pickupCase("double_penny", "a double penny gives 4 coins", "PickupVariant.PICKUP_COIN", "CoinSubType.COIN_DOUBLEPACK",
    exactly("coins", 4))
pickupCase("lucky_penny", "a lucky penny gives 2 coins and +2 luck", "PickupVariant.PICKUP_COIN",
    "CoinSubType.COIN_LUCKYPENNY", exactly("coins", 2, function(d) return math.abs(d.luck - 2) < 1e-6, "luck" end))
pickupCase("key", "a key gives 2 keys", "PickupVariant.PICKUP_KEY", "KeySubType.KEY_NORMAL", exactly("keys", 2))
pickupCase("key_ring", "a key ring gives 4 keys", "PickupVariant.PICKUP_KEY", "KeySubType.KEY_DOUBLEPACK", exactly("keys", 4))
pickupCase("golden_key", "a golden key is taken and no keys come with it", "PickupVariant.PICKUP_KEY",
    "KeySubType.KEY_GOLDEN", function(d, player)
        return player:HasGoldenKey() and d.keys == 0, "golden key " .. tostring(player:HasGoldenKey())
    end)
pickupCase("bomb", "a bomb gives 2 bombs", "PickupVariant.PICKUP_BOMB", "BombSubType.BOMB_NORMAL", exactly("bombs", 2))
pickupCase("double_bomb", "a double bomb gives 4 bombs", "PickupVariant.PICKUP_BOMB", "BombSubType.BOMB_DOUBLEPACK",
    exactly("bombs", 4))
pickupCase("golden_bomb", "a golden bomb is taken and no bombs come with it", "PickupVariant.PICKUP_BOMB",
    "BombSubType.BOMB_GOLDEN", function(d, player)
        return player:HasGoldenBomb() and d.bombs == 0, "golden bomb " .. tostring(player:HasGoldenBomb())
    end)
pickupCase("red_heart", "a red heart heals 2 hearts, not 4", "PickupVariant.PICKUP_HEART", "HeartSubType.HEART_FULL",
    exactly("red", 4), missing(4))
pickupCase("half_heart", "a half heart heals 1 heart", "PickupVariant.PICKUP_HEART", "HeartSubType.HEART_HALF",
    exactly("red", 2), missing(4))
pickupCase("double_heart", "a double heart heals 4 hearts", "PickupVariant.PICKUP_HEART", "HeartSubType.HEART_DOUBLEPACK",
    exactly("red", 8), function(player) player:AddMaxHearts(6); player:AddHearts(-player:GetHearts() + 2) end)
pickupCase("scared_heart", "a scared heart heals 2 hearts", "PickupVariant.PICKUP_HEART", "HeartSubType.HEART_SCARED",
    exactly("red", 4), missing(4))
pickupCase("soul_heart", "a soul heart gives 2 soul hearts", "PickupVariant.PICKUP_HEART", "HeartSubType.HEART_SOUL",
    exactly("soul", 4))
pickupCase("half_soul", "a half soul heart gives 1 soul heart", "PickupVariant.PICKUP_HEART", "HeartSubType.HEART_HALF_SOUL",
    exactly("soul", 2))
pickupCase("black_heart", "a black heart gives 2 black hearts", "PickupVariant.PICKUP_HEART", "HeartSubType.HEART_BLACK",
    exactly("soul", 4, function(d) return d.black == 2, "black hearts " .. d.black end))
pickupCase("eternal_heart", "two eternal halves make a heart container", "PickupVariant.PICKUP_HEART",
    "HeartSubType.HEART_ETERNAL", exactly("max", 2, function(_, player) return player:GetEternalHearts() == 0, "eternal left" end))
pickupCase("golden_heart", "a golden heart gives 2 golden hearts", "PickupVariant.PICKUP_HEART", "HeartSubType.HEART_GOLDEN",
    exactly("golden", 2))
pickupCase("bone_heart", "a bone heart gives 2 bone hearts", "PickupVariant.PICKUP_HEART", "HeartSubType.HEART_BONE",
    exactly("bone", 2))
pickupCase("rotten_heart", "a rotten heart gives 2 rotten hearts", "PickupVariant.PICKUP_HEART", "HeartSubType.HEART_ROTTEN",
    exactly("rotten", 2), missing(4))
pickupCase("blended_heart", "a blended heart with room for red heals 2 red hearts", "PickupVariant.PICKUP_HEART",
    "HeartSubType.HEART_BLENDED", function(d) return d.red == 4 and d.soul == 0, "red/soul" end, missing(4))
pickupCase("battery", "a micro battery charges 4", "PickupVariant.PICKUP_LIL_BATTERY", "BatterySubType.BATTERY_MICRO",
    exactly("charge", 4), function(player)
        player:AddCollectible(CollectibleType.COLLECTIBLE_MEGA_BLAST, 0, false)
        player:SetActiveCharge(0, ActiveSlot.SLOT_PRIMARY)
    end)
-- With The Battery a pickup that fills the item to the top could have
-- overcharged: its repeat goes into the battery (+2 then +2 more).
case("core", "battery_cap", function(plan)
    requireModule(plan)
    plan.act(function(player)
        player:AddCollectible(CollectibleType.COLLECTIBLE_BATTERY, 0, false)
        player:AddCollectible(CollectibleType.COLLECTIBLE_D6, 0, false)
        player:SetActiveCharge(4, ActiveSlot.SLOT_PRIMARY)
    end)
    hold(plan, 1)
    snapshot(plan)
    plan.act(function(_, ctx) ctx.p = spawn(PickupVariant.PICKUP_LIL_BATTERY, BatterySubType.BATTERY_MICRO, 0, 90) end)
    take(plan, "a micro battery at 4 of 6 charges", "p")
    plan.check("with The Battery a micro battery that fills the item adds 2 more into the battery", function(player, ctx)
        local d = delta(ctx.before, wallet(player))
        local battery = player:GetBatteryCharge(ActiveSlot.SLOT_PRIMARY)
        return d.charge == 4 and battery == 2, string.format("charge %+d, battery %d", d.charge, battery)
    end)
    plan.act(function(player) S.collectible(player, CollectibleType.COLLECTIBLE_BATTERY, 0) end)
end)

-- Bought for 5 coins: paid once, two keys.
case("core", "shop_key", function(plan)
    requireModule(plan)
    plan.act(function(player) player:AddCoins(10) end)
    hold(plan, 1)
    snapshot(plan)
    plan.act(function(_, ctx)
        ctx.p = spawn(PickupVariant.PICKUP_KEY, KeySubType.KEY_NORMAL, 0, 90)
        ctx.p.AutoUpdatePrice = false
        ctx.p.Price = 5
    end)
    take(plan, "a key for sale", "p")
    plan.check("a bought key costs 5 coins once and gives 2 keys", function(player, ctx)
        local d = delta(ctx.before, wallet(player))
        return d.coins == -5 and d.keys == 2, describeDelta(d)
    end)
end)

-- A giga bomb: whatever counters the engine raises for it alone (the control,
-- taken first without the item), the item raises each of them twice as much.
case("core", "giga_bomb", function(plan)
    requireModule(plan)
    plan.require("REPENTOGON's giga bomb counter", function(player)
        local ok = type(player.GetNumGigaBombs) == "function" and type(player.AddGigaBombs) == "function"
        return ok or nil, ok and "present" or "missing"
    end)
    for _, arm in ipairs({ "control", "item" }) do
        if arm == "item" then hold(plan, 1) end
        plan.act(function(player, ctx)
            ctx[arm] = wallet(player)
            ctx.p = spawn(PickupVariant.PICKUP_BOMB, BombSubType.BOMB_GIGA, 0, 90)
        end)
        take(plan, arm .. " giga bomb", "p")
        plan.act(function(player, ctx) ctx[arm] = delta(ctx[arm], wallet(player)) end)
    end
    plan.check("a giga bomb raises each counter twice as much as without the item", function(_, ctx)
        local c, i = ctx.control, ctx.item
        local ok = c.giga > 0 and i.giga == 2 * c.giga and i.bombs == 2 * c.bombs
        return ok, string.format("control giga %+d bombs %+d, item giga %+d bombs %+d", c.giga, c.bombs, i.giga, i.bombs)
    end)
end)

-- A sack's contents are new pickups on the floor: the sack is not repeated.
pickupCase("sack", "a sack opens once and no second sack appears", "PickupVariant.PICKUP_GRAB_BAG", "SackSubType.SACK_NORMAL",
    function()
        local left = onFloor(PickupVariant.PICKUP_GRAB_BAG)
        return left == 0, "sacks left " .. left
    end, nil, true)
pickupCase("card", "a card stays single", "PickupVariant.PICKUP_TAROTCARD", "Card.CARD_FOOL",
    function(_, player, ctx)
        local held = (player:GetCard(0) == Card.CARD_FOOL and 1 or 0) + (player:GetCard(1) == Card.CARD_FOOL and 1 or 0)
        local floor = onFloor(PickupVariant.PICKUP_TAROTCARD)
        return held == 1 and floor == 0, "held " .. held .. " on floor " .. floor
    end)
pickupCase("pill", "a pill stays single", "PickupVariant.PICKUP_PILL", "PillColor.PILL_BLUE_BLUE",
    function(_, player, ctx)
        local floor = onFloor(PickupVariant.PICKUP_PILL)
        return player:GetPill(0) ~= PillColor.PILL_NULL and floor == 0, "pill " .. player:GetPill(0) .. " on floor " .. floor
    end)

-- Bought for 3 coins: paid once, two hearts.
case("core", "shop_pickup", function(plan)
    requireModule(plan)
    plan.act(function(player) player:AddCoins(10); player:AddHearts(-4) end)
    hold(plan, 1)
    snapshot(plan)
    plan.act(function(_, ctx)
        ctx.p = spawn(PickupVariant.PICKUP_HEART, HeartSubType.HEART_FULL, 0, 90)
        ctx.p.AutoUpdatePrice = false
        ctx.p.Price = 3
    end)
    take(plan, "a heart for sale", "p")
    plan.check("a bought heart costs 3 coins once and heals 2 hearts", function(player, ctx)
        local d = delta(ctx.before, wallet(player))
        return d.coins == -3 and d.red == 4, describeDelta(d)
    end)
end)

-- Three pennies in a row: 6 coins, nothing left anywhere.
case("core", "three_pennies", function(plan)
    requireModule(plan)
    hold(plan, 1)
    snapshot(plan)
    for i = 1, 3 do
        plan.act(function(_, ctx) ctx.p = spawn(PickupVariant.PICKUP_COIN, CoinSubType.COIN_PENNY, 0, 90) end)
        take(plan, "penny " .. i, "p")
    end
    plan.check("three pennies give exactly 6 coins and leave nothing on the floor", function(player, ctx)
        local d = player:GetNumCoins() - ctx.before.coins
        return d == 6 and onFloor(-1) == ctx.floorBefore, string.format("coins +%d floor %d", d, onFloor(-1))
    end)
end)

-- Half a heart short of full: a red heart fills it, the rest is lost as a
-- double heart's is, and nothing is left behind.
case("core", "full_health", function(plan)
    requireModule(plan)
    plan.act(function(player) player:AddHearts(-1) end)
    hold(plan, 1)
    snapshot(plan)
    plan.act(function(_, ctx) ctx.p = spawn(PickupVariant.PICKUP_HEART, HeartSubType.HEART_FULL, 0, 90) end)
    take(plan, "a red heart at half a heart short", "p")
    plan.check("health is full and no heart is left on the floor", function(player, ctx)
        return player:GetHearts() == player:GetMaxHearts() and onFloor(-1) == ctx.floorBefore,
            string.format("red %d/%d floor %d", player:GetHearts(), player:GetMaxHearts(), onFloor(-1))
    end)
end)

-- ------------------------------------------------------------------ healing
local function healCase(name, label, act, field, amount, prepare)
    case("core", name, function(plan)
        requireModule(plan)
        if prepare then plan.act(function(player, ctx) prepare(player, ctx) end) end
        hold(plan, 1)
        snapshot(plan)
        plan.act(function(player) act(player) end)
        plan.wait(3)
        plan.check(label, function(player, ctx)
            local d = delta(ctx.before, wallet(player))
            return d[field] == amount, describeDelta(d)
        end)
    end)
end

healCase("yum_heart", "Yum Heart heals 2 hearts", function(player)
    player:UseActiveItem(CollectibleType.COLLECTIBLE_YUM_HEART, UseFlag.USE_NOANIM)
end, "red", 4, missing(4))
healCase("heal_direct", "a heal of 1 heart from an effect heals 2", function(player) player:AddHearts(2) end, "red", 4, missing(4))
healCase("soul_direct", "1 soul heart from an effect gives 2", function(player) player:AddSoulHearts(2) end, "soul", 4)
healCase("containers", "a heart container is not healing: +1 only", function(player) player:AddMaxHearts(2) end, "max", 2)
healCase("broken", "a broken heart is not healing: +1 only", function(player) player:AddBrokenHearts(1) end, "broken", 1)
healCase("damage", "losing hearts is not halved or doubled", function(player) player:AddHearts(-2) end, "red", -2)

-- ------------------------------------------------------------------ items
local function pedestalCase(name, label, itemName, expectCount, prepare, check, dressPedestal, finish)
    case("items", name, function(plan)
        local function item() return enum(itemName) end
        requireModule(plan)
        plan.act(function(player, ctx)
            H.suppressRandomGoldenPedestals(ctx)
            if prepare then prepare(player, ctx) end
        end)
        hold(plan, 1)
        snapshot(plan)
        plan.act(function(player, ctx)
            ctx.held0 = player:GetCollectibleNum(item(), true)
            ctx.p = spawn(PickupVariant.PICKUP_COLLECTIBLE, item(), 0, 90)
            if dressPedestal then dressPedestal(ctx.p) end
        end)
        take(plan, label, "p")
        plan.check(label, function(player, ctx)
            local gained = player:GetCollectibleNum(item(), true) - ctx.held0
            local ok, why = true, nil
            if check then ok, why = check(player, ctx) end
            return gained == expectCount and ok, string.format("gained %d (want %d)%s; %s", gained, expectCount,
                why and (", " .. why) or "", describeDelta(delta(ctx.before, wallet(player))))
        end)
        if finish then plan.act(function(player, ctx) finish(player, ctx) end) end
    end)
end

pedestalCase("passive", "a passive pedestal gives 2 copies", "CollectibleType.COLLECTIBLE_SAD_ONION", 2)
pedestalCase("familiar", "a familiar pedestal gives 2 copies and 2 more familiars", "CollectibleType.COLLECTIBLE_BROTHER_BOBBY",
    2, function(_, ctx) ctx.bobbies = #Isaac.FindByType(EntityType.ENTITY_FAMILIAR, FamiliarVariant.BROTHER_BOBBY) end,
    function(_, ctx)
        local n = #Isaac.FindByType(EntityType.ENTITY_FAMILIAR, FamiliarVariant.BROTHER_BOBBY) - ctx.bobbies
        return n == 2, "familiars +" .. n
    end)
-- With the Schoolbag's second slot free, a doubled active would show as a
-- second one held; nothing may land on the floor either.
pedestalCase("active", "an active pedestal stays single (Schoolbag's second slot stays empty)",
    "CollectibleType.COLLECTIBLE_BEAN", 1,
    function(player) player:AddCollectible(CollectibleType.COLLECTIBLE_SCHOOLBAG, 0, false) end,
    function(player, ctx)
        local second = player:GetActiveItem(ActiveSlot.SLOT_SECONDARY)
        local floor = 0
        for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE)) do
            if e:Exists() and e.SubType ~= 0 then floor = floor + 1 end
        end
        return second == 0 and floor == 0, string.format("second slot %d, items on the floor %d", second, floor)
    end, nil,
    function(player) S.collectible(player, CollectibleType.COLLECTIBLE_SCHOOLBAG, 0) end)
pedestalCase("quest", "a quest item comes twice too", "CollectibleType.COLLECTIBLE_KEY_PIECE_1", 2)
pedestalCase("quarter", "A Quarter gives 2 copies and 50 coins", "CollectibleType.COLLECTIBLE_QUARTER", 2, nil,
    function(player, ctx) local d = player:GetNumCoins() - ctx.before.coins; return d == 50, "coins +" .. d end)
pedestalCase("shop_item", "a 15-coin item is paid once and comes twice", "CollectibleType.COLLECTIBLE_INNER_EYE", 2,
    function(player) player:AddCoins(20) end,
    function(player, ctx) local d = player:GetNumCoins() - ctx.before.coins; return d == -15, "coins " .. d end,
    function(p) p.AutoUpdatePrice = false; p.Price = 15 end)
pedestalCase("devil_deal", "a one-heart devil deal costs one heart container once and comes twice",
    "CollectibleType.COLLECTIBLE_CRICKETS_HEAD", 2, nil,
    function(player, ctx) local d = player:GetMaxHearts() - ctx.before.max; return d == -2, "max hearts " .. d end,
    function(p) p.ShopItemId = -2; p.Price = PickupPrice.PRICE_ONE_HEART; p.AutoUpdatePrice = true end)
-- Hearts an item gives as it is added come with the item: two Breakfasts heal
-- what two Breakfasts heal (like A Quarter's coins), not four times one.
pedestalCase("breakfast", "two Breakfasts: two containers' and two heals' worth, not four heals",
    "CollectibleType.COLLECTIBLE_BREAKFAST", 2,
    function(player, ctx)
        player:AddMaxHearts(12)
        player:AddHearts(2 - player:GetHearts())
        ctx.itemHearts0 = evidence().itemHearts
    end,
    function(player, ctx)
        local config = Isaac.GetItemConfig():GetCollectible(CollectibleType.COLLECTIBLE_BREAKFAST)
        local d = delta(ctx.before, wallet(player))
        local wantMax, wantRed = 2 * config.AddMaxHearts, 2 * config.AddHearts
        return d.max == wantMax and d.red == wantRed,
            string.format("max %+d red %+d (want %+d %+d), heals inside an item add %d", d.max, d.red, wantMax, wantRed,
                evidence().itemHearts - ctx.itemHearts0)
    end)

-- Job's Blessing itself is an item like any other: taken, it comes twice.
case("items", "itself", function(plan)
    requireModule(plan)
    plan.act(function(player, ctx)
        H.suppressRandomGoldenPedestals(ctx)
        ctx.p = spawn(PickupVariant.PICKUP_COLLECTIBLE, jobId(), 0, 90)
    end)
    take(plan, "Job's Blessing", "p")
    plan.check("taking Job's Blessing gives two of it", function(player)
        local n = player:GetCollectibleNum(jobId(), true)
        return n == 2, "held " .. n
    end)
end)

-- Two items in one choice group: the other one goes, the taken one comes twice.
case("items", "choice", function(plan)
    requireModule(plan)
    plan.act(function(_, ctx) H.suppressRandomGoldenPedestals(ctx) end)
    hold(plan, 1)
    plan.act(function(player, ctx)
        ctx.a0 = player:GetCollectibleNum(CollectibleType.COLLECTIBLE_SPOON_BENDER, true)
        ctx.b0 = player:GetCollectibleNum(CollectibleType.COLLECTIBLE_CUPIDS_ARROW, true)
        ctx.p = spawn(PickupVariant.PICKUP_COLLECTIBLE, CollectibleType.COLLECTIBLE_SPOON_BENDER, -60, 90)
        ctx.q = spawn(PickupVariant.PICKUP_COLLECTIBLE, CollectibleType.COLLECTIBLE_CUPIDS_ARROW, 60, 90)
        ctx.p.OptionsPickupIndex, ctx.q.OptionsPickupIndex = 3, 3
    end)
    take(plan, "one choice", "p")
    plan.check("the chosen item comes twice and the other choice is gone", function(player, ctx)
        local a = player:GetCollectibleNum(CollectibleType.COLLECTIBLE_SPOON_BENDER, true) - ctx.a0
        local b = player:GetCollectibleNum(CollectibleType.COLLECTIBLE_CUPIDS_ARROW, true) - ctx.b0
        local other = ctx.q:Exists() and ctx.q.SubType ~= 0
        return a == 2 and b == 0 and not other, string.format("chosen +%d other +%d other pedestal %s", a, b, tostring(other))
    end)
end)

-- An item handed over by an effect is an acquisition too (FirstTime); one
-- handed back is not.
case("items", "granted", function(plan)
    requireModule(plan)
    hold(plan, 1)
    plan.act(function(player, ctx)
        ctx.a0 = player:GetCollectibleNum(CollectibleType.COLLECTIBLE_WIRE_COAT_HANGER, true)
        ctx.b0 = player:GetCollectibleNum(CollectibleType.COLLECTIBLE_STEVEN, true)
        player:AddCollectible(CollectibleType.COLLECTIBLE_WIRE_COAT_HANGER, 0, true)
        player:AddCollectible(CollectibleType.COLLECTIBLE_STEVEN, 0, false)
    end)
    plan.waitUntil(function(player) return settled(player), "copies" end, 20, "copies given")
    plan.check("a new item handed over comes twice; one handed back stays single", function(player, ctx)
        local a = player:GetCollectibleNum(CollectibleType.COLLECTIBLE_WIRE_COAT_HANGER, true) - ctx.a0
        local b = player:GetCollectibleNum(CollectibleType.COLLECTIBLE_STEVEN, true) - ctx.b0
        return a == 2 and b == 1, string.format("first-time +%d, handed back +%d", a, b)
    end)
end)

-- ------------------------------------------------------------------ trinkets
local FIXTURE_TRINKET = TrinketType.TRINKET_PETRIFIED_POOP

-- `act` absorbs (or not) the fixture trinket; the smelted counts must rise by
-- exactly the wanted amounts. `quiet` waits a full sweep to prove nothing came.
local function trinketCase(name, label, act, wantNormal, wantGolden, wantHeld, quiet)
    case("items", name, function(plan)
        requireModule(plan)
        hold(plan, 1)
        plan.wait(1)
        plan.act(function(player, ctx)
            ctx.n0, ctx.g0 = smeltedOf(player, FIXTURE_TRINKET)
            act(player, ctx)
        end)
        if quiet then
            plan.wait(J() and J().smeltSweep + 5 or 35)
        else
            plan.waitUntil(function(player, ctx)
                local n, g = smeltedOf(player, FIXTURE_TRINKET)
                return n - ctx.n0 >= wantNormal and g - ctx.g0 >= wantGolden, "smelted"
            end, 40, "the absorption is repeated")
            -- A whole sweep more, so a late extra repeat would show.
            plan.wait(J() and J().smeltSweep + 5 or 35)
        end
        plan.check(label, function(player, ctx)
            local n, g = smeltedOf(player, FIXTURE_TRINKET)
            local held = (player:GetTrinket(0) & ~GOLDEN == FIXTURE_TRINKET and 1 or 0)
                + (player:GetTrinket(1) & ~GOLDEN == FIXTURE_TRINKET and 1 or 0)
            return n - ctx.n0 == wantNormal and g - ctx.g0 == wantGolden and held == wantHeld,
                string.format("smelted %+d golden %+d held %d (want %+d/%+d/%d)", n - ctx.n0, g - ctx.g0, held,
                    wantNormal, wantGolden, wantHeld)
        end)
    end)
end

-- Taken into the hand: no absorption, nothing doubles.
case("items", "trinket_hand", function(plan)
    requireModule(plan)
    hold(plan, 1)
    plan.act(function(player, ctx)
        local n, g = smeltedOf(player, FIXTURE_TRINKET)
        ctx.n0 = n + g
        ctx.p = spawn(PickupVariant.PICKUP_TRINKET, FIXTURE_TRINKET, 0, 90)
    end)
    take(plan, "a trinket", "p")
    plan.wait(J() and J().smeltSweep + 5 or 35)
    plan.check("a trinket taken into the hand is not absorbed: 1 held, none smelted", function(player, ctx)
        local n, g = smeltedOf(player, FIXTURE_TRINKET)
        n = n + g - ctx.n0
        -- A trinket that appears may roll golden; it is the same trinket.
        local held = (player:GetTrinket(0) & ~GOLDEN == FIXTURE_TRINKET and 1 or 0)
            + (player:GetTrinket(1) & ~GOLDEN == FIXTURE_TRINKET and 1 or 0)
        return n == 0 and held == 1, string.format("smelted %+d held %d", n, held)
    end)
end)
trinketCase("smelter", "the Smelter absorbs a held trinket twice", function(player)
    player:AddTrinket(FIXTURE_TRINKET, false)
    player:UseActiveItem(CollectibleType.COLLECTIBLE_SMELTER, UseFlag.USE_NOANIM)
end, 2, 0, 0)
-- A trinket picked up from the floor and then smelted: the engine sends no
-- trinket event for this smelt (measured 2026-11-19), so the sweep doubles it.
case("items", "smelter_after_pickup", function(plan)
    requireModule(plan)
    hold(plan, 1)
    -- A trinket that appears may roll golden: both kinds count as its copies.
    local function copies(player)
        local n, g = smeltedOf(player, FIXTURE_TRINKET)
        return n + g
    end
    plan.act(function(player, ctx)
        ctx.n0 = copies(player)
        ctx.p = spawn(PickupVariant.PICKUP_TRINKET, FIXTURE_TRINKET, 0, 90)
    end)
    take(plan, "a trinket from the floor", "p")
    plan.act(function(player) player:UseActiveItem(CollectibleType.COLLECTIBLE_SMELTER, UseFlag.USE_NOANIM) end)
    plan.waitUntil(function(player, ctx) return copies(player) - ctx.n0 >= 2, "smelted" end,
        (J() and J().smeltSweep or 30) + 10, "the sweep repeats the absorption")
    plan.wait(J() and J().smeltSweep + 5 or 35)
    plan.check("a floor trinket smelted from the hand is absorbed twice", function(player, ctx)
        local n = copies(player) - ctx.n0
        return n == 2, string.format("smelted %+d", n)
    end)
end)
trinketCase("smelter_golden", "the Smelter absorbs a golden trinket twice as golden", function(player)
    player:AddTrinket(FIXTURE_TRINKET | GOLDEN, false)
    player:UseActiveItem(CollectibleType.COLLECTIBLE_SMELTER, UseFlag.USE_NOANIM)
end, 0, 2, 0)
trinketCase("gulp", "Gulp! absorbs a held trinket twice", function(player)
    player:AddTrinket(FIXTURE_TRINKET, false)
    player:UsePill(PillEffect.PILLEFFECT_GULP, PillColor.PILL_BLUE_BLUE, UseFlag.USE_NOANIM)
end, 2, 0, 0)
trinketCase("smelt_direct", "an absorption by another effect is doubled", function(player)
    player:AddSmeltedTrinket(FIXTURE_TRINKET, true)
end, 2, 0, 0)
-- Two absorptions (+2, each repeated: +2) and one removal (-1) in one update: +3.
trinketCase("smelt_and_remove", "two absorptions and a removal in one update: +2 +2 copies -1", function(player)
    player:AddSmeltedTrinket(FIXTURE_TRINKET, false)
    player:AddSmeltedTrinket(FIXTURE_TRINKET, false)
    player:TryRemoveSmeltedTrinket(FIXTURE_TRINKET)
end, 3, 0, 0)
trinketCase("moms_box", "Mom's Box is no absorption", function(player)
    player:AddCollectible(CollectibleType.COLLECTIBLE_MOMS_BOX, 0, false)
    player:AddTrinket(FIXTURE_TRINKET, false)
end, 0, 0, 1, true)

-- An innate trinket (the Hermit Crab's kind) is held, not absorbed.
local INNATE_GROUP = "ConchBlessingJobsBlessingBench"
case("items", "innate_trinket", function(plan)
    requireModule(plan)
    plan.require("REPENTOGON's innate trinkets", function(player)
        local ok = type(player.AddInnateTrinket) == "function" and type(player.RemoveInnateTrinket) == "function"
        return ok or nil, ok and "present" or "missing"
    end)
    hold(plan, 1)
    plan.wait(1)
    plan.act(function(player, ctx)
        local n, g = smeltedOf(player, FIXTURE_TRINKET)
        ctx.n0 = n + g
        ctx.cleanupFns = ctx.cleanupFns or {}
        table.insert(ctx.cleanupFns, function() player:RemoveInnateTrinket(FIXTURE_TRINKET, 1, INNATE_GROUP) end)
        player:AddInnateTrinket(FIXTURE_TRINKET, 1, INNATE_GROUP, -1, false)
    end)
    plan.wait(J() and J().smeltSweep + 5 or 35)
    plan.check("an innate trinket is not absorbed: none smelted, one innate copy", function(player, ctx)
        local n, g = smeltedOf(player, FIXTURE_TRINKET)
        local innate = player:GetInnateTrinketCount(FIXTURE_TRINKET, INNATE_GROUP)
        return n + g - ctx.n0 == 0 and innate == 1, string.format("smelted %+d innate %d", n + g - ctx.n0, innate)
    end)
end)

-- D4 rerolls every item; a reroll replaces (FirstTime false, measured), so it
-- brings no copy and the item total does not grow (D4 may lose an item). Job's
-- Blessing is held as an innate item here, which D4 does not reroll, so it is
-- still held while every new item arrives. It runs last in the shared run:
-- what D4 leaves behind is random.
local D4_GROUP = "ConchBlessingJobsBlessingBench"
case("items", "d4", function(plan)
    requireModule(plan)
    plan.require("REPENTOGON's innate items", function(player)
        local ok = type(player.AddInnateCollectible) == "function" and type(player.RemoveInnateCollectible) == "function"
        return ok or nil, ok and "present" or "missing"
    end)
    plan.act(function(player, ctx)
        S.collectible(player, jobId(), 0)
        player:AddInnateCollectible(jobId(), 1, D4_GROUP)
        ctx.cleanupFns = ctx.cleanupFns or {}
        table.insert(ctx.cleanupFns, function() player:RemoveInnateCollectible(jobId(), 1, D4_GROUP) end)
        for _, id in ipairs({ CollectibleType.COLLECTIBLE_SAD_ONION, CollectibleType.COLLECTIBLE_SPOON_BENDER,
            CollectibleType.COLLECTIBLE_SKATOLE }) do player:AddCollectible(id, 0, false) end
    end)
    plan.wait(3)
    plan.require("the innate copy counts as held", function(player)
        return J()._test.holds(player) or nil, "held " .. player:GetCollectibleNum(jobId())
    end)
    plan.act(function(player, ctx)
        ctx.total = player:GetCollectibleCount()
        ctx.given = evidence().collectibles
        ctx.notFirst = evidence().notFirst
        player:UseActiveItem(CollectibleType.COLLECTIBLE_D4, UseFlag.USE_NOANIM)
    end)
    plan.wait(6)
    plan.check("D4's new items are no acquisitions: seen while held, no copy, the total does not grow", function(player, ctx)
        local seen = evidence().notFirst - ctx.notFirst
        return seen >= 3 and J()._test.holds(player) and player:GetCollectibleCount() <= ctx.total
            and evidence().collectibles == ctx.given,
            string.format("rerolled adds seen %d, total %d -> %d, copies given %d", seen, ctx.total,
                player:GetCollectibleCount(), evidence().collectibles - ctx.given)
    end)
end)

-- ------------------------------------------------------------------ other doublers: control arm, then the item arm
-- Each case measures the other effect alone, then gives Job's Blessing and
-- repeats it: the control arm must show the other effect working as it says
-- (`wantControl`), and the item arm must be exactly twice the control arm.
-- `finish` takes the doubler away again for the next shared case. A case
-- whose optional mod is not installed reports SKIP and lets the shared run
-- go on (every step of it is passed over).
local function skippable(plan)
    -- Every other step passes through as it is (a plan may supply its steps through a metatable).
    local guarded = setmetatable({}, { __index = plan })
    function guarded.act(fn) plan.act(function(p, c) if not c.skip then return fn(p, c) end end) end
    function guarded.waitUntil(fn, timeout, label)
        plan.waitUntil(function(p, c) if c.skip then return true end return fn(p, c) end, timeout, label)
    end
    function guarded.note(label, fn) plan.note(label, function(p, c) if c.skip then return "skipped" end return fn(p, c) end) end
    function guarded.check(label, fn) plan.check(label, function(p, c) if c.skip then return nil, c.skip end return fn(p, c) end) end
    return guarded
end

local function armCase(name, label, o)
    case("doublers", name, function(outer)
        requireModule(outer)
        local plan = skippable(outer)
        outer.act(function(_, ctx)
            ctx.skip = nil
            if o.available then
                local ok, why = o.available()
                if not ok then ctx.skip = why or "not installed" end
            end
        end)
        plan.act(function(player, ctx)
            H.suppressRandomGoldenPedestals(ctx)
            if o.setup then o.setup(player, ctx) end
        end)
        plan.wait(3)
        for _, arm in ipairs({ "control", "item" }) do
            if arm == "item" then
                -- Let every mod finish reacting to Job's Blessing itself first
                -- (Black Mirror spends a mirror on any new passive, this one too).
                plan.act(function(player) S.collectible(player, jobId(), 1) end)
                plan.wait(8)
            end
            if o.beforeArm then plan.act(function(player, ctx) o.beforeArm(player, ctx, arm) end); plan.wait(2) end
            plan.act(function(player, ctx) ctx.arm = arm; ctx[arm .. "Before"] = o.measure(player, ctx) end)
            o.run(plan, arm)
            plan.act(function(player, ctx) ctx[arm .. "After"] = o.measure(player, ctx) end)
            plan.note(label .. " (" .. arm .. ")", function(_, ctx)
                return string.format("%.2f -> %.2f", ctx[arm .. "Before"], ctx[arm .. "After"])
            end)
        end
        plan.check(label .. ": alone it gives " .. o.wantControl, function(_, ctx)
            local control = ctx.controlAfter - ctx.controlBefore
            return math.abs(control - o.wantControl) < 1e-6, string.format("control %+g", control)
        end)
        plan.check(label .. ": with the item exactly twice the control", function(_, ctx)
            local control = ctx.controlAfter - ctx.controlBefore
            local item = ctx.itemAfter - ctx.itemBefore
            return control > 0 and math.abs(item - 2 * control) < 1e-6,
                string.format("control %+g, with the item %+g (want %+g)", control, item, 2 * control)
        end)
        if o.finish then plan.act(function(player, ctx) o.finish(player, ctx) end) end
    end)
end

-- Golden Items: a golden pedestal gives one more copy.
local GOLDEN_ITEMS = { control = "CollectibleType.COLLECTIBLE_MOMS_LIPSTICK", item = "CollectibleType.COLLECTIBLE_MOMS_EYE" }
armCase("golden_items", "Golden Items golden pedestal", {
    wantControl = 2,
    run = function(plan, arm)
        plan.act(function(_, ctx)
            ctx.p = spawn(PickupVariant.PICKUP_COLLECTIBLE, enum(GOLDEN_ITEMS[arm]), 0, 90)
            GoldenItems.Pickup.GOLDEN_ITEM:TurnItemGold(ctx.p, false)
        end)
        take(plan, arm .. " golden pedestal", "p")
        plan.waitUntil(function(player, ctx)
            ctx.goldWait = (ctx.goldWait or 0) + 1
            return ctx.goldWait > 10 and settled(player), "Golden Items' copy"
        end, 40, "Golden Items' own copy and its copy")
        plan.act(function(_, ctx) ctx.goldWait = nil end)
    end,
    measure = function(player, ctx) return player:GetCollectibleNum(enum(GOLDEN_ITEMS[ctx.arm or "control"]), true) end,
    available = function()
        local provider = rawget(_G, "GoldenItems") and GoldenItems.Pickup and GoldenItems.Pickup.GOLDEN_ITEM
        return provider ~= nil and type(provider.TurnItemGold) == "function", "Golden Items is not loaded"
    end,
})

-- This mod's Two Faced Penny: a coin claims the next item and adds a copy at once.
local PENNY_ITEMS = { control = "CollectibleType.COLLECTIBLE_LUMP_OF_COAL", item = "CollectibleType.COLLECTIBLE_SMALL_ROCK" }
armCase("two_faced_penny", "Two Faced Penny's claim (one free coin per arm)", {
    wantControl = 2,
    run = function(plan, arm)
        plan.act(function(_, ctx) ctx.p = spawn(PickupVariant.PICKUP_COLLECTIBLE, enum(PENNY_ITEMS[arm]), 0, 90) end)
        take(plan, arm .. " item", "p")
    end,
    measure = function(player, ctx) return player:GetCollectibleNum(enum(PENNY_ITEMS[ctx.arm or "control"]), true) end,
    -- Each arm opens one free coin slot of its own.
    beforeArm = function(player) player:AddCollectible(ConchBlessing.ItemData.TWO_FACED_PENNY.id, 0, false) end,
    finish = function(player) S.collectible(player, ConchBlessing.ItemData.TWO_FACED_PENNY.id, 0) end,
})

-- This mod's Conch Debris: absorbed at a touch; every three become a Conch Ticket.
local function debrisWorth(player)
    local ticket = ConchBlessing.PocketData.CONCH_TICKET.id
    local tickets = 0
    for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD, ticket)) do
        if e:ToPickup():GetSprite():GetAnimation() ~= "Collect" then tickets = tickets + 1 end
    end
    for slot = 0, 1 do if player:GetCard(slot) == ticket then tickets = tickets + 1 end end
    return tickets * 3 + ConchBlessing.conchdebris.smeltedCount(player)
end
armCase("conch_debris", "Conch Debris absorbed at a touch (tickets x3 + smelted)", {
    wantControl = 3,
    run = function(plan, arm)
        for i = 1, 3 do
            plan.act(function(_, ctx)
                ctx.p = spawn(PickupVariant.PICKUP_TRINKET, ConchBlessing.ItemData.CONCH_DEBRIS.id, 0, 90)
            end)
            plan.waitUntil(function(player, ctx)
                if not ctx.p:Exists() then return true end
                pinOn(player, ctx.p)
                return false, "touching debris"
            end, 120, arm .. " debris " .. i)
            plan.wait(3)
        end
        plan.waitUntil(function(player, ctx)
            ctx.debrisWait = (ctx.debrisWait or 0) + 1
            return ctx.debrisWait > 6 and ConchBlessing.conchdebris.smeltedCount(player) < 3, "tickets"
        end, 40, arm .. ": absorptions settle into tickets")
        plan.act(function(_, ctx) ctx.debrisWait = nil end)
    end,
    measure = debrisWorth,
    available = function()
        return ConchBlessing.conchdebris and ConchBlessing.conchdebris.available(), "Conch Debris needs REPENTOGON"
    end,
})

-- Astro's Black Mirror: absorbed, it makes the next passive come once more per
-- mirror. The control arm absorbs two mirrors (the passive comes 3 times); the
-- item arm one, which the item absorbs twice, and the 3 acquisitions double.
local function mirrorId()
    local astro = rawget(_G, "Astro")
    return astro and astro.Trinket and astro.Trinket.BLACK_MIRROR or -1
end
local MIRROR_ITEMS = { control = "CollectibleType.COLLECTIBLE_MOMS_WIG", item = "CollectibleType.COLLECTIBLE_MOMS_PERFUME" }
local function mirrors(player)
    local n, g = smeltedOf(player, mirrorId())
    return n + g
end
armCase("black_mirror", "Black Mirror (two absorbed mirrors)", {
    wantControl = 3,
    run = function(plan, arm)
        plan.act(function(player, ctx)
            ctx.mirrors0 = mirrors(player)
            player:AddTrinket(mirrorId(), false)
        end)
        plan.waitUntil(function(player, ctx)
            return mirrors(player) - ctx.mirrors0 >= (arm == "item" and 2 or 1), "mirror"
        end, 60, arm .. ": mirror absorbed")
        if arm == "control" then
            plan.act(function(player) player:AddTrinket(mirrorId(), false) end)
            plan.waitUntil(function(player, ctx) return mirrors(player) - ctx.mirrors0 >= 2, "mirror" end, 60,
                "second mirror absorbed")
        end
        plan.wait(J() and J().smeltSweep + 5 or 35)
        plan.check(arm .. ": two mirrors absorbed", function(player, ctx)
            local n = mirrors(player) - ctx.mirrors0
            return n == 2, string.format("mirrors %+d", n)
        end)
        plan.act(function(_, ctx) ctx.p = spawn(PickupVariant.PICKUP_COLLECTIBLE, enum(MIRROR_ITEMS[arm]), 0, 90) end)
        take(plan, arm .. " passive", "p")
        plan.waitUntil(function(player, ctx)
            ctx.mirrorWait = (ctx.mirrorWait or 0) + 1
            return ctx.mirrorWait > 10 and settled(player), "mirror copies"
        end, 40, arm .. ": mirror copies settle")
        plan.act(function(_, ctx) ctx.mirrorWait = nil end)
    end,
    measure = function(player, ctx) return player:GetCollectibleNum(enum(MIRROR_ITEMS[ctx.arm or "control"]), true) end,
    available = function() return mirrorId() > 0, "Astro's Black Mirror is not installed" end,
})

-- Astro's Blood Of Hatred adds itself once more on its first acquisition.
-- Astro counts that first acquisition once a run, so the control arm and the
-- item arm are separate fresh runs: alone it comes twice, with the item four
-- times (both acquisitions doubled).
local function bloodOfHatred(withItem)
    return function(plan)
        requireModule(plan)
        plan.require("Astro's Blood Of Hatred", function()
            return Isaac.GetItemIdByName("Blood Of Hatred") > 0 or nil, "not installed"
        end)
        plan.act(function(_, ctx) H.suppressRandomGoldenPedestals(ctx) end)
        if withItem then hold(plan, 1); plan.wait(8) end
        plan.act(function(_, ctx)
            ctx.p = spawn(PickupVariant.PICKUP_COLLECTIBLE, Isaac.GetItemIdByName("Blood Of Hatred"), 0, 90)
        end)
        take(plan, "Blood Of Hatred", "p")
        plan.waitUntil(function(player, ctx)
            ctx.bloodWait = (ctx.bloodWait or 0) + 1
            return ctx.bloodWait > 10 and settled(player), "its own copy"
        end, 40, "Blood Of Hatred's own copy and its doubling")
        plan.check("Blood Of Hatred comes " .. (withItem and "4 times (2 x 2)" or "twice"), function(player)
            local n = player:GetCollectibleNum(Isaac.GetItemIdByName("Blood Of Hatred"), true)
            return n == (withItem and 4 or 2), "held " .. n
        end)
    end
end
S.add(KEY, "blood_of_hatred_control", GROUPS, bloodOfHatred(false))
S.add(KEY, "blood_of_hatred", GROUPS, bloodOfHatred(true))

-- ------------------------------------------------------------------ shared runs
S.sequenceBundle(KEY, "core", GROUPS, bundles.core, function(plan) fresh(plan) end)
S.sequenceBundle(KEY, "items", GROUPS, bundles.items, function(plan) fresh(plan) end)
S.sequenceBundle(KEY, "doublers", GROUPS, bundles.doublers, function(plan) fresh(plan) end)

-- ------------------------------------------------------------------ co-op: only the holder doubles
TestBench.register({
    command = "cb test jobs_blessing coop", tag = "ItemTest:JOBS_BLESSING", restartCommand = "restart 19",
    finalRestartCommand = "restart 0", duration = "a fresh Jacob & Esau run", cleanup = H.cleanup,
    build = function(plan)
        plan.section("JOBS_BLESSING / coop")
        requireModule(plan)
        plan.require("Jacob and Esau", function()
            local a, b = Isaac.GetPlayer(0), Isaac.GetPlayer(1)
            return Game():GetNumPlayers() == 2 and a and b and a:GetPlayerType() == PlayerType.PLAYER_JACOB
                and b:GetPlayerType() == PlayerType.PLAYER_ESAU or nil, "players " .. Game():GetNumPlayers()
        end)
        plan.act(function(player, ctx)
            H.suppressRandomGoldenPedestals(ctx)
            player:AddCollectible(jobId(), 0, false)
            ctx.esau = Isaac.GetPlayer(1)
            ctx.esau.Position = spot(-150, 0)
            player.Position = spot(150, 0)
        end)
        plan.wait(2)
        for _, who in ipairs({ "esau", "jacob" }) do
            local dx = who == "esau" and -150 or 150
            plan.act(function(player, ctx)
                ctx.coins0 = player:GetNumCoins()
                ctx.p = spawn(PickupVariant.PICKUP_COIN, CoinSubType.COIN_NICKEL, dx, 80)
            end)
            plan.waitUntil(function(player, ctx)
                local body = who == "esau" and ctx.esau or player
                if not ctx.p:Exists() then return true end
                pinOn(body, ctx.p)
                return ctx.p:GetSprite():GetAnimation() == "Collect", who .. " walks onto a nickel"
            end, 150, who .. " takes a nickel")
            plan.wait(3)
            plan.check(who .. "'s nickel gives " .. (who == "esau" and 5 or 10) .. " coins", function(player, ctx)
                local d = player:GetNumCoins() - ctx.coins0
                return d == (who == "esau" and 5 or 10), "coins +" .. d
            end)
            -- Healing is the holder's alone too.
            plan.act(function(player, ctx)
                local body = who == "esau" and ctx.esau or player
                if body:GetMaxHearts() < 6 then body:AddMaxHearts(6 - body:GetMaxHearts()) end
                body:AddHearts(2 - body:GetHearts())
                ctx.red0 = body:GetHearts()
                ctx.p = spawn(PickupVariant.PICKUP_HEART, HeartSubType.HEART_FULL, dx, 80)
            end)
            plan.waitUntil(function(player, ctx)
                local body = who == "esau" and ctx.esau or player
                if not ctx.p:Exists() then return true end
                pinOn(body, ctx.p)
                return ctx.p:GetSprite():GetAnimation() == "Collect", who .. " walks onto a red heart"
            end, 150, who .. " takes a red heart")
            plan.wait(3)
            plan.check(who .. "'s red heart heals " .. (who == "esau" and 1 or 2) .. " heart(s)", function(player, ctx)
                local body = who == "esau" and ctx.esau or player
                local d = body:GetHearts() - ctx.red0
                return d == (who == "esau" and 2 or 4), string.format("red %+d", d)
            end)
            local function item()
                return who == "esau" and CollectibleType.COLLECTIBLE_SPOON_BENDER or CollectibleType.COLLECTIBLE_INNER_EYE
            end
            plan.act(function(player, ctx) ctx.p = spawn(PickupVariant.PICKUP_COLLECTIBLE, item(), dx, 80) end)
            plan.waitUntil(function(player, ctx)
                local body = who == "esau" and ctx.esau or player
                if not ctx.p:Exists() or ctx.p.SubType == 0 then return body:IsItemQueueEmpty() end
                pinOn(body, ctx.p)
                return false, who .. " walks onto a pedestal"
            end, 150, who .. " takes an item")
            plan.waitUntil(function(player, ctx)
                local body = who == "esau" and ctx.esau or player
                return J()._test.pending()[GetPtrHash(body)] == nil, "copy"
            end, 20, who .. ": copy settled")
            plan.wait(2)
            plan.check(who .. "'s item comes " .. (who == "esau" and "once" or "twice"), function(player, ctx)
                local body = who == "esau" and ctx.esau or player
                local n = body:GetCollectibleNum(item(), true)
                return n == (who == "esau" and 1 or 2), "held " .. n
            end)
        end
    end,
})
S.link(KEY, "cb test jobs_blessing coop", GROUPS, { "coop" })

-- ------------------------------------------------------------------ Multiplier Get (measurement)
-- Multiplier Get keeps its switch in its own saved settings, reachable only
-- through Mod Config Menu; this measurement turns it on (collectibles x2)
-- through that menu entry, records what happens with and without Job's
-- Blessing, and restores its saved settings. Run by name only.
local function multiplierSetting(name)
    if not (ModConfigMenu and ModConfigMenu.MenuData) then return nil end
    for _, category in ipairs(ModConfigMenu.MenuData) do
        if category.Name == "Multiplier Get" then
            for _, sub in ipairs(category.Subcategories or {}) do
                for _, option in ipairs(sub.Options or {}) do
                    local ok, text = pcall(function() return option.Display and option.Display() or "" end)
                    if ok and type(text) == "string" and text:find(name, 1, true) then return option end
                end
            end
        end
    end
end

S.add(KEY, "multiplier_get", {}, function(plan)
    requireModule(plan)
    plan.require("Multiplier Get's menu entries", function()
        return multiplierSetting("Mod Enabled") and multiplierSetting("Collectible") and true or nil, "not found"
    end)
    plan.act(function(_, ctx)
        local enabled, multiplier = multiplierSetting("Mod Enabled"), multiplierSetting("Collectible")
        ctx.mgEnabled, ctx.mgMultiplier = enabled.CurrentSetting(), multiplier.CurrentSetting()
        ctx.cleanupFns = ctx.cleanupFns or {}
        table.insert(ctx.cleanupFns, function()
            multiplierSetting("Collectible").OnChange(ctx.mgMultiplier)
            multiplierSetting("Mod Enabled").OnChange(ctx.mgEnabled)
        end)
        H.suppressRandomGoldenPedestals(ctx)
        multiplier.OnChange(2)
        enabled.OnChange(true)
    end)
    plan.wait(2)
    for _, arm in ipairs({ "control", "item" }) do
        local function item()
            return arm == "control" and CollectibleType.COLLECTIBLE_SPOON_BENDER or CollectibleType.COLLECTIBLE_INNER_EYE
        end
        if arm == "item" then hold(plan, 1) end
        plan.act(function(_, ctx) ctx.p = spawn(PickupVariant.PICKUP_COLLECTIBLE, item(), 0, 90) end)
        plan.waitUntil(function(player, ctx)
            if not ctx.p:Exists() or ctx.p.SubType == 0 then return player:IsItemQueueEmpty() end
            pinOn(player, ctx.p)
            return false, "taking the pedestal"
        end, 150, arm .. " item is taken")
        for t = 1, 8 do
            plan.wait(15)
            plan.note(arm .. " copies after " .. (t * 15) .. " updates", function(player, ctx)
                ctx[arm .. t] = player:GetCollectibleNum(item(), true)
                return tostring(ctx[arm .. t])
            end)
        end
    end
    -- Multiplier Get doubles the pickup (2); Job's Blessing doubles both of
    -- those acquisitions (+2); Multiplier Get doubles those copies too (+2);
    -- its answer to a copy is not doubled again, so it stops at 6.
    plan.check("with Multiplier Get x2 the control holds 2 and the item arm stops at 6", function(_, ctx)
        return ctx.control8 == 2 and ctx.item1 == 6 and ctx.item8 == 6,
            string.format("control %s, item %s ... %s", tostring(ctx.control8), tostring(ctx.item1), tostring(ctx.item8))
    end)
end)
S.rows[#S.rows].manual = true

-- ------------------------------------------------------------------ engine measurements (manual)
-- What the engine reports for each kind of acquisition, without the item:
-- the collision animation, the add events' FirstTime flags, heart types,
-- smelted counts at the trinket events, and how soon a pickup that appears
-- under a player who stands still is taken. DIAG only; run by name.
local watch = nil
local function note(line) if watch then watch[#watch + 1] = line end end
local luckProbe = nil
if ModCallbacks.MC_PRE_PICKUP_COLLISION and ModCallbacks.MC_POST_PICKUP_COLLISION then
    ConchBlessing:AddCallback(ModCallbacks.MC_PRE_PICKUP_COLLISION, function(_, pickup, collider)
        local player = collider and collider:ToPlayer()
        if luckProbe and player and pickup.Variant == PickupVariant.PICKUP_COIN and luckProbe.pre == nil then
            luckProbe.pre = player.Luck
        end
    end)
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_PICKUP_COLLISION, function(_, pickup, collider)
        local player = collider and collider:ToPlayer()
        if luckProbe and player and pickup.Variant == PickupVariant.PICKUP_COIN and luckProbe.post == nil then
            luckProbe.post = player.Luck
        end
    end)
end
if ModCallbacks.MC_POST_ADD_COLLECTIBLE then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_ADD_COLLECTIBLE, function(_, id, _, firstTime)
        note(string.format("add collectible %d first=%s", id, tostring(firstTime)))
    end)
end
if ModCallbacks.MC_POST_TRIGGER_TRINKET_ADDED then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_TRIGGER_TRINKET_ADDED, function(_, player, id, firstTime, innate)
        if watch then
            local n, g = smeltedOf(player, id & ~GOLDEN)
            note(string.format("trinket added %d first=%s innate=%s smelted-now %d/%d", id, tostring(firstTime),
                tostring(innate), n, g))
        end
    end)
end
if ModCallbacks.MC_POST_TRIGGER_TRINKET_REMOVED then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_TRIGGER_TRINKET_REMOVED, function(_, player, id)
        if watch then
            local n, g = smeltedOf(player, id & ~GOLDEN)
            note(string.format("trinket removed %d smelted-now %d/%d", id, n, g))
        end
    end)
end
if ModCallbacks.MC_PRE_PLAYER_ADD_HEARTS then
    ConchBlessing:AddCallback(ModCallbacks.MC_PRE_PLAYER_ADD_HEARTS, function(_, _, amount, kind)
        note(string.format("hearts %+d type %d", amount, kind))
    end)
end
if ModCallbacks.MC_POST_PICKUP_COLLISION then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_PICKUP_COLLISION, function(_, pickup, collider)
        if watch and collider and collider:ToPlayer() and pickup.Variant ~= PickupVariant.PICKUP_COLLECTIBLE then
            note(string.format("collision %d.%d anim=%s dead=%s exists=%s price=%d keys=%d", pickup.Variant,
                pickup.SubType, pickup:GetSprite():GetAnimation(), tostring(pickup:IsDead()), tostring(pickup:Exists()),
                pickup.Price, collider:ToPlayer():GetNumKeys()))
        end
    end)
end

local function diag(plan, label, act, wait)
    plan.act(function(player, ctx)
        watch = {}
        act(player, ctx)
    end)
    plan.wait(wait or 6)
    plan.note("DIAG " .. label, function(player)
        local list = watch or {}
        watch = nil
        local n, g = smeltedOf(player, FIXTURE_TRINKET)
        return (#list > 0 and table.concat(list, "; ") or "nothing")
            .. string.format(" | smelted %d/%d held %d,%d", n, g, player:GetTrinket(0), player:GetTrinket(1))
    end)
end

S.add(KEY, "engine", {}, function(plan)
    plan.act(function(player, ctx)
        H.suppressRandomGoldenPedestals(ctx)
        player:AddHearts(-4)
        player:AddCollectible(CollectibleType.COLLECTIBLE_SCHOOLBAG, 0, false)
    end)
    for _, row in ipairs({
        { "penny", "PickupVariant.PICKUP_COIN", 1 }, { "red heart", "PickupVariant.PICKUP_HEART", 1 },
        { "key", "PickupVariant.PICKUP_KEY", 1 }, { "bomb", "PickupVariant.PICKUP_BOMB", 1 },
        { "sack", "PickupVariant.PICKUP_GRAB_BAG", 1 }, { "card", "PickupVariant.PICKUP_TAROTCARD", "Card.CARD_FOOL" },
        { "trinket", "PickupVariant.PICKUP_TRINKET", "TrinketType.TRINKET_PETRIFIED_POOP" },
        { "passive", "PickupVariant.PICKUP_COLLECTIBLE", "CollectibleType.COLLECTIBLE_SAD_ONION" },
        { "active", "PickupVariant.PICKUP_COLLECTIBLE", "CollectibleType.COLLECTIBLE_BEAN" },
    }) do
        plan.act(function(_, ctx) ctx.p = spawn(enum(row[2]), enum(row[3]), 0, 90); watch = {} end)
        plan.waitUntil(function(player, ctx)
            local p = ctx.p
            if not p:Exists() then return player:IsItemQueueEmpty() end
            pinOn(player, p)
            if p.Variant == PickupVariant.PICKUP_COLLECTIBLE then return p.SubType == 0 and player:IsItemQueueEmpty() end
            return p:GetSprite():GetAnimation() == "Collect" or p:GetSprite():GetAnimation() == "PlayerPickupSparkle"
        end, 150, row[1] .. " is taken")
        plan.wait(6)
        plan.note("DIAG " .. row[1] .. " taken", function()
            local list = watch or {}
            watch = nil
            return #list > 0 and table.concat(list, "; ") or "nothing"
        end)
    end
    diag(plan, "Smelter on the held trinket", function(player)
        player:UseActiveItem(CollectibleType.COLLECTIBLE_SMELTER, UseFlag.USE_NOANIM)
    end)
    diag(plan, "Gulp! on a held trinket", function(player)
        player:AddTrinket(FIXTURE_TRINKET, false)
        player:UsePill(PillEffect.PILLEFFECT_GULP, PillColor.PILL_BLUE_BLUE, UseFlag.USE_NOANIM)
    end)
    diag(plan, "AddSmeltedTrinket(first=true)", function(player) player:AddSmeltedTrinket(FIXTURE_TRINKET, true) end)
    diag(plan, "TryRemoveSmeltedTrinket", function(player) player:TryRemoveSmeltedTrinket(FIXTURE_TRINKET) end)
    diag(plan, "AddCollectible(first=true)", function(player) player:AddCollectible(CollectibleType.COLLECTIBLE_STEVEN, 0, true) end)
    diag(plan, "AddCollectible(first=false)", function(player) player:AddCollectible(CollectibleType.COLLECTIBLE_STEVEN, 0, false) end)
    diag(plan, "D4", function(player) player:UseActiveItem(CollectibleType.COLLECTIBLE_D4, UseFlag.USE_NOANIM) end, 10)
    diag(plan, "D100", function(player) player:UseActiveItem(CollectibleType.COLLECTIBLE_D100, UseFlag.USE_NOANIM) end, 10)
    diag(plan, "Yum Heart", function(player)
        player:AddHearts(-2)
        player:UseActiveItem(CollectibleType.COLLECTIBLE_YUM_HEART, UseFlag.USE_NOANIM)
    end)
    diag(plan, "Breakfast added", function(player) player:AddCollectible(CollectibleType.COLLECTIBLE_BREAKFAST, 0, true) end)
    -- When does a lucky penny's luck rise: during its collision or later?
    plan.act(function(player, ctx)
        ctx.p = spawn(PickupVariant.PICKUP_COIN, CoinSubType.COIN_LUCKYPENNY, 0, 90)
        luckProbe = { pre = nil, post = nil }
    end)
    plan.waitUntil(function(player, ctx)
        if not ctx.p:Exists() or ctx.p:GetSprite():GetAnimation() == "Collect" then return true end
        pinOn(player, ctx.p)
        return false
    end, 150, "the lucky penny is taken")
    plan.act(function(player, ctx) ctx.luckNext = player.Luck end)
    plan.wait(2)
    plan.note("DIAG lucky penny luck: before collision, after collision, next update, two updates later", function(player, ctx)
        local probe = luckProbe or {}
        luckProbe = nil
        return string.format("%s, %s, %.2f, %.2f", tostring(probe.pre), tostring(probe.post), ctx.luckNext, player.Luck)
    end)
end)
S.rows[#S.rows].manual = true

-- What a bought pickup looks like in its collision (without the item): the
-- animation, whether it is dead or gone, and when its number rises. DIAG only.
S.add(KEY, "shop_engine", {}, function(plan)
    plan.act(function(player, ctx)
        player:AddCoins(20)
        ctx.keys0 = player:GetNumKeys()
        ctx.p = spawn(PickupVariant.PICKUP_KEY, KeySubType.KEY_NORMAL, 0, 90)
        ctx.p.AutoUpdatePrice = false
        ctx.p.Price = 5
        watch = {}
    end)
    plan.waitUntil(function(player, ctx)
        if not ctx.p:Exists() or ctx.p:IsDead() then return true end
        pinOn(player, ctx.p)
        return false, "walking onto a key for sale"
    end, 150, "the key is bought")
    plan.wait(6)
    plan.note("DIAG bought key", function(player, ctx)
        local list = watch or {}
        watch = nil
        return (#list > 0 and table.concat(list, "; ") or "nothing")
            .. string.format(" | keys %+d, pickup exists %s", player:GetNumKeys() - ctx.keys0, tostring(ctx.p:Exists()))
    end)
end)
S.rows[#S.rows].manual = true

return C
