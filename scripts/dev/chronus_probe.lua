-- Chronus test bench: sets up one in-game scenario per absorbed-familiar feature
-- so each can be checked by hand. Run `restart` between scenarios to keep them
-- apart; they stack otherwise.
--
-- Console:  conch_chronus                 restart the run, test every feature on its own
--                                         (PASS/FAIL/SKIP to console + log.txt), then restart
--                                         again so nothing leaks into play (test_bench.lua)
--           conch_chronus help            list the manual scenarios and helpers
--           conch_chronus <scenario>      give Chronus + the scenario's familiars
--           conch_chronus status          print the Chronus run save
--           conch_chronus hurtme          take one half-heart hit (never lethal)
--           conch_chronus clearsim [n]    run the room-clear reward n times (default 1)
--           conch_chronus enemies [n]     spawn n Fatties (default 3)
--           conch_chronus give <id> [n]   give collectible <id> n times
--           conch_chronus drop            remove Chronus (familiars come back)
--
-- Player 0 only. This file is dev tooling: it only runs from the console.

local TestBench = require("scripts.dev.test_bench")

local probe = {}

local CHRONUS_ID = Isaac.GetItemIdByName("Chronus")
local C = CollectibleType

local function out(line)
    Isaac.ConsoleOutput(tostring(line) .. "\n")
    Isaac.DebugString("[ChronusProbe] " .. tostring(line))
end

-- Spawned targets get this much HP so stomps, Necronomicon and Bird Cage hits
-- can all be seen on the same enemy before it dies.
local ENEMY_HP = 400

local ENEMY = {
    fatty = { EntityType.ENTITY_FATTY, 0 },
    pooter = { EntityType.ENTITY_POOTER, 0 },
}

local SCENARIOS = {
    {
        key = "vfx",
        about = "absorb visual for 5 familiars, staggered",
        give = { { C.COLLECTIBLE_BROTHER_BOBBY, 1 }, { C.COLLECTIBLE_LITTLE_CHUBBY, 1 }, { C.COLLECTIBLE_INCUBUS, 1 },
            { C.COLLECTIBLE_SISTER_MAGGY, 1 }, { C.COLLECTIBLE_GUARDIAN_ANGEL, 1 } },
        checks = { "5 item icons appear above the head one after another, shatter, fly into the body",
            "a gulp sound as each one lands; no familiar stays on screen" },
    },
    {
        key = "gb",
        about = "GB Bug returns half of 6 absorbed familiars",
        give = { { C.COLLECTIBLE_BROTHER_BOBBY, 2 }, { C.COLLECTIBLE_HALO_OF_FLIES, 1 }, { C.COLLECTIBLE_LITTLE_STEVEN, 1 },
            { C.COLLECTIBLE_GUARDIAN_ANGEL, 1 }, { C.COLLECTIBLE_LITTLE_CHUBBY, 1 }, { C.COLLECTIBLE_GB_BUG, 1 } },
        checks = { "after the absorb icons, 3 reverse icons come out of the body", "3 real familiars follow you and stay",
            "status: spared lists them; giving one more copy absorbs only the new one" },
    },
    {
        key = "procs",
        about = "Daddy stomp, Razor bleed, Cube freeze, Spewer creep at 100%",
        give = { { C.COLLECTIBLE_DADDY_LONGLEGS, 10 }, { C.COLLECTIBLE_MOMS_RAZOR, 10 }, { C.COLLECTIBLE_CUBE_BABY, 10 },
            { C.COLLECTIBLE_LIL_SPEWER, 4 } },
        enemies = { "fatty", 3 },
        checks = { "every tear hit: a leg stomps on the enemy, bleed, freeze, red creep under it",
            "a piercing/multi-hit attack still stomps only once per tear" },
    },
    {
        key = "spawns",
        about = "blue fly / spider at 100%, fear, slow",
        give = { { C.COLLECTIBLE_ROTTEN_BABY, 2 }, { C.COLLECTIBLE_JUICY_SACK, 2 }, { C.COLLECTIBLE_LIL_HAUNT, 1 },
            { C.COLLECTIBLE_LITTLE_GISH, 1 } },
        enemies = { "fatty", 3 },
        checks = { "each tear hit: 1 blue fly + 1 blue spider; their own hits spawn nothing",
            "hit enemies show fear and slow" },
    },
    {
        key = "barrier",
        about = "Sworn Protector x20 = 100% projectile ignore",
        give = { { C.COLLECTIBLE_SWORN_PROTECTOR, 20 } },
        enemies = { "pooter", 4 },
        checks = { "enemy projectiles never cost health", "touching an enemy still hurts" },
    },
    {
        key = "hurt",
        about = "effects of getting hit; then use: conch_chronus hurtme",
        give = { { C.COLLECTIBLE_HOLY_WATER, 4 }, { C.COLLECTIBLE_DRY_BABY, 4 }, { C.COLLECTIBLE_MILK, 1 },
            { C.COLLECTIBLE_BIRD_CAGE, 1 }, { C.COLLECTIBLE_MYSTERY_EGG, 2 }, { C.COLLECTIBLE_MY_SHADOW, 2 },
            { C.COLLECTIBLE_HALLOWED_GROUND, 1 } },
        enemies = { "fatty", 2 },
        checks = { "per hit: 4 holy water creeps, Necronomicon flash, nearest enemy -45, 2 charmed flies,",
            "  2 friendly black chargers, a white poop nearby",
            "first hit on the floor: tears +1 (Milk!); second hit: no further tears" },
    },
    {
        key = "clear",
        about = "room-clear drops; then use: conch_chronus clearsim 7",
        give = { { C.COLLECTIBLE_BUM_FRIEND, 10 }, { C.COLLECTIBLE_LIL_CHEST, 10 }, { C.COLLECTIBLE_RELIC, 1 },
            { C.COLLECTIBLE_MYSTERY_SACK, 1 }, { C.COLLECTIBLE_RUNE_BAG, 1 }, { C.COLLECTIBLE_PASCHAL_CANDLE, 1 } },
        checks = { "every clear: 1 random pickup + 1 chest", "6th clear: + soul heart + random pickup; 7th: + rune",
            "tears +0.03 per clear; also clear a real room once to see the drops" },
    },
    {
        key = "gemini",
        about = "Gemini x3 contact damage (18/s)",
        give = { { C.COLLECTIBLE_GEMINI, 3 } },
        enemies = { "fatty", 1 },
        checks = { "touching the Fatty damages it (6 every 1/3 s); use debug 7 to see numbers" },
    },
    {
        key = "pinned",
        about = "Bloodshot Eye, Mongo Baby x3, Succubus, Star of Bethlehem",
        give = { { C.COLLECTIBLE_BLOODSHOT_EYE, 1 }, { C.COLLECTIBLE_MONGO_BABY, 3 }, { C.COLLECTIBLE_SUCCUBUS, 1 },
            { C.COLLECTIBLE_STAR_OF_BETHLEHEM, 1 } },
        enemies = { "fatty", 2 },
        checks = { "no Bloodshot Eye body, but it shoots from you; Succubus/Star aura visible, no body/shadow",
            "3 Minisaacs; after one dies, the next room refills to 3" },
    },
    {
        key = "floor",
        about = "Buddy in a Box x2 + Lil Delirium: random effect per floor",
        give = { { C.COLLECTIBLE_BUDDY_IN_A_BOX, 2 }, { C.COLLECTIBLE_LIL_DELIRIUM, 1 } },
        checks = { "conch_chronus status: 3 floor picks", "stage 2 then status: picks rerolled, serial +1" },
    },
    {
        key = "items",
        about = "new item swaps + Guillotine stats",
        give = { { C.COLLECTIBLE_HEADLESS_BABY, 1 }, { C.COLLECTIBLE_CAINS_OTHER_EYE, 1 }, { C.COLLECTIBLE_PAPA_FLY, 1 },
            { C.COLLECTIBLE_SHADE, 1 }, { C.COLLECTIBLE_GUILLOTINE, 1 } },
        checks = { "you gain Aquarius, Rubber Cement, Hive Mind, Lusty Blood",
            "damage up by about 11 (2 per familiar + Guillotine 1), tears +0.5" },
    },
    {
        key = "lostsoul",
        about = "Lost Soul x2: hit-free floor pays eternal hearts",
        give = { { C.COLLECTIBLE_LOST_SOUL, 2 } },
        checks = { "stage 2 without a hit: 2 eternal hearts in the first room (or the next one)",
            "then conch_chronus hurtme, stage 3: nothing" },
    },
    {
        key = "actives",
        about = "use the temporary-familiar sources by hand (real button / card / trinket)",
        give = { { C.COLLECTIBLE_DADDY_LONGLEGS, 2 }, { C.COLLECTIBLE_BROTHER_BOBBY, 2 }, { C.COLLECTIBLE_BOX_OF_FRIENDS, 1 } },
        setup = "placeActives",
        checks = { "SPACE with Box of Friends: dust icon, no Demon Baby; status shows effect x2 for this room",
            "swap to Monster Manual / Sacrificial Altar from the pedestals and use them; status after each",
            "pick up and use Soul of Lilith; pick up The Twins and walk between rooms" },
    },
    {
        key = "daddy",
        about = "old save: Holy Light granted by Daddy Longlegs is taken back",
        setup = "legacyDaddy",
        checks = { "Holy Light appears then disappears next frame; any Holy Light you had before stays",
            "status: no fam_170 grant left" },
    },
}

local function findScenario(key)
    for _, scenario in ipairs(SCENARIOS) do
        if scenario.key == key then return scenario end
    end
    return nil
end

local function itemName(id)
    local config = Isaac.GetItemConfig():GetCollectible(id)
    local name = config and config.Name or "?"
    return (tostring(name):gsub("^#", ""):gsub("_NAME$", ""))
end

local function ensureChronus(player)
    -- A mid-run `luamod` reload drops the game-start gate; the run is live here.
    ConchBlessing.chronus._runReady = true
    if not player:HasCollectible(CHRONUS_ID) then
        player:AddCollectible(CHRONUS_ID, 0, false)
        out("  gave Chronus")
    end
end

local function give(player, id, count)
    for _ = 1, count do
        player:AddCollectible(id, 0, false)
    end
    out(string.format("  gave %s (%d) x%d", itemName(id), id, count))
end

local function spawnEnemies(kind, count)
    local enemy = ENEMY[kind]
    if not enemy then return end
    local room = Game():GetRoom()
    local center = room:GetCenterPos()
    for i = 1, count do
        local position = room:FindFreePickupSpawnPosition(center + Vector.FromAngle(i * 360 / count) * 100, 0, true)
        local npc = Isaac.Spawn(enemy[1], enemy[2], 0, position, Vector.Zero, nil):ToNPC()
        if npc then
            npc.MaxHitPoints = ENEMY_HP
            npc.HitPoints = ENEMY_HP
        end
    end
    out(string.format("  spawned %d %s (%d HP)", count, kind, ENEMY_HP))
end

local function getRunSave(player)
    ConchBlessing.chronus._getAbsorbedCount(player, C.COLLECTIBLE_BROTHER_BOBBY) -- creates the table
    local run = ConchBlessing.SaveManager.GetRunSave(nil)
    return run and run.chronus or nil
end

function probe.legacyDaddy(player)
    local rs = getRunSave(player)
    if not rs then out("  no run save") return end
    local daddy, holy = C.COLLECTIBLE_DADDY_LONGLEGS, C.COLLECTIBLE_HOLY_LIGHT
    local key = "fam_" .. daddy
    local before = player:GetCollectibleNum(holy, true)
    player:AddCollectible(holy, 0, false)
    rs.absorbed[key] = { count = ConchBlessing.chronus._getAbsorbedCount(player, daddy) + 1, id = daddy }
    rs.totalAbsorbed = (rs.totalAbsorbed or 0) + 1
    rs.itemGrants = rs.itemGrants or {}
    rs.itemGrantTotals = rs.itemGrantTotals or {}
    rs.itemGrantBaselines = rs.itemGrantBaselines or {}
    rs.itemGrants[key] = 1
    rs.itemGrantTotals[key] = 1
    rs.itemGrantBaselines[key] = before
    out(string.format("  wrote an old-save Daddy -> Holy Light grant (Holy Light %d -> %d)", before, before + 1))
end

function probe.placeActives(player)
    local room = Game():GetRoom()
    local function place(offset, variant, subtype)
        local position = room:FindFreePickupSpawnPosition(player.Position + offset, 0, true)
        Isaac.Spawn(EntityType.ENTITY_PICKUP, variant, subtype, position, Vector.Zero, nil)
    end
    if type(player.FullCharge) == "function" then player:FullCharge(ActiveSlot.SLOT_PRIMARY, true) end
    place(Vector(-80, 60), PickupVariant.PICKUP_COLLECTIBLE, C.COLLECTIBLE_MONSTER_MANUAL)
    place(Vector(0, 80), PickupVariant.PICKUP_COLLECTIBLE, C.COLLECTIBLE_SACRIFICIAL_ALTAR)
    place(Vector(80, 60), PickupVariant.PICKUP_TAROTCARD, Card.CARD_SOUL_LILITH)
    place(Vector(80, -60), PickupVariant.PICKUP_TRINKET, TrinketType.TRINKET_THE_TWINS)
    out("  placed Monster Manual, Sacrificial Altar, Soul of Lilith and The Twins around you")
end

function probe.status(player)
    local rs = getRunSave(player)
    if not rs then out("no Chronus run save") return end
    local function sortedKeys(t)
        local keys = {}
        for k in pairs(t or {}) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        return keys
    end
    out(string.format("== Chronus status (held: %s, total absorbed %d) ==",
        tostring(player:HasCollectible(CHRONUS_ID)), tonumber(rs.totalAbsorbed) or 0))
    local state = ConchBlessing.getUnifiedMultiplierState(player)
    local entry = state and state.itemAdditions and state.itemAdditions[CHRONUS_ID]
        and state.itemAdditions[CHRONUS_ID].Damage
    local damage = state and state.statMultipliers and state.statMultipliers.Damage
    out(string.format("  damage actual=%.4f expectedChronus=%.4f registeredChronus=%s disabled=%s providerTotalAdd=%s",
        player.Damage, ((tonumber(rs.totalAbsorbed) or 0)
            + ConchBlessing.chronus._getTemporaryDamageCopies(player)) * ConchBlessing.chronus.STATS.DAMAGE_PER_FAMILIAR,
        tostring(entry and entry.cumulative), tostring(entry and entry.disabled),
        tostring(damage and damage.totalAdditions)))
    for id, count in pairs(ConchBlessing.chronus._test.readTemporaryFamiliarEffects(player)) do
        out(string.format("  live familiar effect %d x%d", id, count))
    end
    for key, count in pairs(rs.tempFloor and rs.tempFloor.counts or {}) do
        out(string.format("  Manual absorbed %s x%d (grants %s)", key, count,
            tostring(rs.tempFloor.grants and rs.tempFloor.grants[key])))
    end
    for _, key in ipairs(sortedKeys(rs.absorbed)) do
        local entry = rs.absorbed[key]
        local id = entry.id or tonumber(tostring(key):match("%d+"))
        out(string.format("  absorbed %-26s x%d  effect=%d", itemName(id) .. " (" .. id .. ")",
            entry.count or 0, ConchBlessing.chronus._getEffectCount(player, id)))
    end
    local picks = rs.floorPicks
    if type(picks) == "table" and type(picks.ids) == "table" then
        local names = {}
        for _, id in ipairs(picks.ids) do names[#names + 1] = itemName(id) .. "(" .. id .. ")" end
        out(string.format("  floor picks (serial %s): %s", tostring(picks.serial), table.concat(names, ", ")))
    end
    for _, key in ipairs(sortedKeys(rs.spared)) do
        out(string.format("  spared %s x%d", key, rs.spared[key]))
    end
    for _, key in ipairs(sortedKeys(rs.itemGrants)) do
        out(string.format("  grant %s = %s (lifetime %s)", key, tostring(rs.itemGrants[key]),
            tostring(rs.itemGrantTotals and rs.itemGrantTotals[key])))
    end
    for _, key in ipairs(sortedKeys(rs.clearCounters)) do
        out(string.format("  clear counter %s = %s", key, tostring(rs.clearCounters[key])))
    end
    out(string.format("  floorSerial=%s hurtSerial=%s milkSerial=%s paschal=+%.2f lostSoulPending=%s",
        tostring(rs.floorSerial or 0), tostring(rs.hurtSerial), tostring(rs.milkSerial),
        (tonumber(rs.paschalHundredths) or 0) / 100, tostring(rs.lostSoulRewardPending)))
end

function probe.help()
    out("conch_chronus <scenario>  manual setups (run `restart` between them)")
    for _, scenario in ipairs(SCENARIOS) do
        out(string.format("  %-9s %s", scenario.key, scenario.about))
    end
    out("helpers: status | hurtme | clearsim [n] | enemies [n] | give <id> [n] | drop")
end

function probe.run(scenario, player)
    out("== conch_chronus " .. scenario.key .. ": " .. scenario.about .. " ==")
    ensureChronus(player)
    for _, entry in ipairs(scenario.give or {}) do
        give(player, entry[1], entry[2])
    end
    if scenario.setup then probe[scenario.setup](player) end
    if scenario.enemies then spawnEnemies(scenario.enemies[1], scenario.enemies[2]) end
    out("check:")
    for _, line in ipairs(scenario.checks or {}) do
        out("  - " .. line)
    end
end

-- ------------------------------------------------------------------ automatic run
-- The plan below is run by scripts/dev/test_bench.lua: `conch_chronus` restarts
-- the run, walks every feature on its own (gives familiars, fires tears, takes
-- hits, uses the temporary-familiar sources, reloads the room for The Twins),
-- prints PASS/FAIL/SKIP and LOOK lines, and restarts the run again.
-- Stand still while it runs: the projectile test aims at where you stand.
local TARGET_HP = 1000

local function counters()
    return ConchBlessing.chronus._counters or {}
end

local function snapshotCounters(ctx)
    ctx.c0 = {}
    for name, value in pairs(counters()) do ctx.c0[name] = value end
end

local function delta(ctx, name)
    return (counters()[name] or 0) - (ctx.c0 and ctx.c0[name] or 0)
end

local function runSave()
    local run = ConchBlessing.SaveManager.GetRunSave(nil)
    return run and run.chronus or {}
end

local function absorbed(player, id)
    return ConchBlessing.chronus._getAbsorbedCount(player, id)
end

local function owns(player, id)
    return player:GetCollectibleNum(id, true)
end

local function countEntities(entityType, variant, subtype, filter)
    local n = 0
    for _, entity in ipairs(Isaac.FindByType(entityType, variant or -1, subtype or -1)) do
        if not filter or filter(entity) then n = n + 1 end
    end
    return n
end

local function sumValues(t)
    local total = 0
    for _, value in pairs(type(t) == "table" and t or {}) do total = total + (tonumber(value) or 0) end
    return total
end

local function totalAbsorbed()
    return tonumber(runSave().totalAbsorbed) or 0
end

local function ownedFamiliarItems(player)
    local total = 0
    local config = Isaac.GetItemConfig()
    for id = 1, CollectibleType.NUM_COLLECTIBLES - 1 do
        local item = config:GetCollectible(id)
        if item and item.Type == ItemType.ITEM_FAMILIAR then
            total = total + player:GetCollectibleNum(id, true)
        end
    end
    return total
end

local function countWhitePoops()
    local room = Game():GetRoom()
    local n = 0
    for i = 0, room:GetGridSize() - 1 do
        local grid = room:GetGridEntity(i)
        if grid and grid:GetType() == GridEntityType.GRID_POOP and grid:GetVariant() == 6 then n = n + 1 end
    end
    return n
end

local function spawnTarget(player, ctx)
    local room = Game():GetRoom()
    local position = room:GetClampedPosition(player.Position + Vector(160, 0), 20)
    local npc = Isaac.Spawn(EntityType.ENTITY_FATTY, 0, 0, position, Vector.Zero, nil):ToNPC()
    npc.MaxHitPoints = TARGET_HP
    npc.HitPoints = TARGET_HP
    -- Frozen in place, and colliding only with player attacks: a target the
    -- player can touch keeps them invincible and swallows the test's own hits.
    npc:AddEntityFlags(EntityFlag.FLAG_FREEZE)
    npc.EntityCollisionClass = EntityCollisionClass.ENTCOLL_PLAYEROBJECTS
    ctx.target = npc
end

-- Self-inflicted test hits only land once the player's invincibility is over.
local function vulnerable(player)
    if type(player.GetDamageCooldown) ~= "function" then return true end
    return player:GetDamageCooldown() <= 0
end

local function fireAt(player, ctx)
    local target = ctx.target
    if not (target and target:Exists()) then spawnTarget(player, ctx) target = ctx.target end
    local from = target.Position + Vector(-60, 0)
    player:FireTear(from, Vector(12, 0), false, true, false)
end

local function giveAll(player, list)
    for _, entry in ipairs(list) do
        for _ = 1, entry[2] do player:AddCollectible(entry[1], 0, false) end
    end
end

local function buildPlan(plan)
    local act, wait, check, section, waitUntil = plan.act, plan.wait, plan.check, plan.section, plan.waitUntil
    local eqCheck, atLeast = plan.eq, plan.atLeast

    -- setup ----------------------------------------------------------------
    section("setup", nil)
    act(function(player, ctx)
        ctx.savedDebugMode = ConchBlessing.Config and ConchBlessing.Config.debugMode
        if ConchBlessing.Config then ConchBlessing.Config.debugMode = false end
        ConchBlessing.chronus._runReady = true
        player:AddMaxHearts(12, false)
        player:AddHearts(24)
        player:AddCollectible(CHRONUS_ID, 0, false)
        spawnTarget(player, ctx)
    end)
    wait(10)

    section("damage: all familiars", nil)
    for _, id in ipairs({ C.COLLECTIBLE_GUARDIAN_ANGEL, C.COLLECTIBLE_ROTTEN_BABY, C.COLLECTIBLE_BROTHER_BOBBY }) do
        act(function(player, ctx)
            ctx.damageBefore = player.Damage
            player:AddCollectible(id, 0, false)
        end)
        wait(10)
        check("+2 independent of special effect: " .. id, function(player, ctx)
            return math.abs(player.Damage - ctx.damageBefore - 2) < 0.001,
                string.format("damage %.4f -> %.4f", ctx.damageBefore, player.Damage)
        end)
    end
    act(function(player, ctx)
        ctx.damageBefore = player.Damage
        while player:HasCollectible(CHRONUS_ID) do player:RemoveCollectible(CHRONUS_ID) end
    end)
    wait(10)
    check("losing Chronus removes all three +2 bonuses", function(player, ctx)
        return math.abs(player.Damage - ctx.damageBefore + 6) < 0.001,
            string.format("damage %.4f -> %.4f", ctx.damageBefore, player.Damage)
    end)
    act(function(player)
        for _, id in ipairs({ C.COLLECTIBLE_GUARDIAN_ANGEL, C.COLLECTIBLE_ROTTEN_BABY, C.COLLECTIBLE_BROTHER_BOBBY }) do
            while player:HasCollectible(id, true) do player:RemoveCollectible(id) end
        end
        player:AddCollectible(CHRONUS_ID, 0, false)
    end)
    wait(10)

    section("temp: Manual before Chronus", nil)
    act(function(player, ctx)
        player:RemoveCollectible(CHRONUS_ID)
        ctx.manualEffects = {}
    end)
    wait(10)
    -- Use the real active until at least one summoned familiar has an item
    -- conversion; no invented TemporaryEffect substitutes for this boundary.
    for _ = 1, 12 do
        act(function(player, ctx)
            if not ctx.manualConversion then
                player:UseActiveItem(C.COLLECTIBLE_MONSTER_MANUAL, UseFlag.USE_NOANIM, -1)
            end
        end)
        wait(3)
        act(function(player, ctx)
            ctx.manualEffects = ConchBlessing.chronus._test.readTemporaryFamiliarEffects(player)
            for id in pairs(ctx.manualEffects) do
                local conversion = ConchBlessing.chronus.data.familiarToItemMap[id]
                if conversion and conversion.itemId then ctx.manualConversion = true end
            end
        end)
    end
    check("Manual stays vanilla before acquisition", function(player, ctx)
        return sumValues(ctx.manualEffects) > 0 and not player:HasCollectible(CHRONUS_ID),
            string.format("%d live effects", sumValues(ctx.manualEffects))
    end)
    act(function(player) player:AddCollectible(CHRONUS_ID, 0, false) end)
    wait(20)
    check("Manual used before Chronus is absorbed", function(_, ctx)
        local credited = sumValues(runSave().tempFloor and runSave().tempFloor.counts)
        return credited == sumValues(ctx.manualEffects) and credited > 0,
            string.format("%d summoned, %d credited", sumValues(ctx.manualEffects), credited)
    end)
    check("every Manual absorption registers +2", function(player, ctx)
        local state = ConchBlessing.getUnifiedMultiplierState(player, ConchBlessing.stats.unifiedMultipliers)
        local entry = state and state.itemAdditions and state.itemAdditions[CHRONUS_ID]
        local actual = entry and entry.Damage and entry.Damage.cumulative or 0
        local expected = sumValues(ctx.manualEffects) * 2
        return math.abs(actual - expected) < 0.001,
            string.format("registered %.4f, expected %.4f", actual, expected)
    end)
    check("Manual grants each configured conversion", function(player, ctx)
        local checked = 0
        for id, count in pairs(ctx.manualEffects) do
            local conversion = ConchBlessing.chronus.data.familiarToItemMap[id]
            if conversion and conversion.itemId then
                checked = checked + 1
                local expected = conversion.maxGrants == 0 and count or math.min(count, conversion.maxGrants or 0)
                local actual = runSave().itemGrants["fam_" .. id] or 0
                if actual ~= expected or owns(player, conversion.itemId) < expected then
                    return false, string.format("familiar %d: %d grants, expected %d", id, actual, expected)
                end
            end
        end
        return checked > 0, string.format("%d conversion mappings checked", checked)
    end)
    act(function(player, ctx)
        ctx.manualCredits = sumValues(runSave().tempFloor and runSave().tempFloor.counts)
        ctx.manualGrants = sumValues(runSave().itemGrants)
        ctx.room = Game():GetLevel():GetCurrentRoomIndex()
        Isaac.ExecuteCommand("goto s.shop")
    end)
    wait(20)
    check("Manual entities stay consumed in the next room", function(player, ctx)
        local live = 0
        for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR)) do
            local fam = entity:ToFamiliar()
            if fam and fam.Player and GetPtrHash(fam.Player) == GetPtrHash(player)
                and type(fam.GetItemConfig) == "function" then
                local ok, config = pcall(fam.GetItemConfig, fam)
                if ok and config and ctx.manualEffects[config.ID] then live = live + 1 end
            end
        end
        local credits = sumValues(runSave().tempFloor and runSave().tempFloor.counts)
        return live == 0 and credits == ctx.manualCredits and sumValues(runSave().itemGrants) == ctx.manualGrants,
            string.format("%d live Manual entities, credits %d -> %d", live, ctx.manualCredits, credits)
    end)
    act(function(player, ctx)
        Game():StartRoomTransition(ctx.room, Direction.NO_DIRECTION, RoomTransitionAnim.FADE)
    end)
    wait(20)
    act(function(player) player:RemoveCollectible(CHRONUS_ID) end)
    wait(10)
    check("Manual conversions removed with Chronus", function(player, ctx)
        for id in pairs(ctx.manualEffects) do
            local conversion = ConchBlessing.chronus.data.familiarToItemMap[id]
            if conversion and conversion.itemId and owns(player, conversion.itemId) > 0 then
                return false, "converted item remains: " .. conversion.itemId
            end
        end
        return sumValues(runSave().itemGrants) == 0, "converted inventory and active ledger cleared"
    end)
    act(function(player, ctx)
        for id in pairs(ctx.manualEffects) do player:GetEffects():RemoveCollectibleEffect(id, -1) end
        ConchBlessing.SaveManager.GetFloorSave(player).chronusManual = nil
        player:AddCacheFlags(CacheFlag.CACHE_FAMILIARS)
        player:EvaluateItems()
        player:AddCollectible(CHRONUS_ID, 0, false)
        if ConchBlessing.Config then ConchBlessing.Config.debugMode = ctx.savedDebugMode end
    end)
    wait(10)

    -- absorb + dust visual ----------------------------------------------------
    section("absorb", "3 item icons crumble into dust above your head and swirl into your body, with a gulp each")
    act(function(player)
        giveAll(player, { { C.COLLECTIBLE_BROTHER_BOBBY, 1 }, { C.COLLECTIBLE_HALO_OF_FLIES, 1 }, { C.COLLECTIBLE_LITTLE_CHUBBY, 1 } })
    end)
    wait(90)
    eqCheck("Brother Bobby absorbed", function(p) return absorbed(p, C.COLLECTIBLE_BROTHER_BOBBY) end, 1)
    eqCheck("Little Chubby absorbed", function(p) return absorbed(p, C.COLLECTIBLE_LITTLE_CHUBBY) end, 1)
    eqCheck("familiar items removed from inventory", function(p) return ownedFamiliarItems(p) end, 0)
    eqCheck("Little Chubby granted Mars", function(p) return owns(p, C.COLLECTIBLE_MARS) end, 1)

    -- GB Bug ------------------------------------------------------------------
    section("gb", "3 reverse dust swirls come OUT of your body; 3 real familiars appear")
    act(function(player, ctx)
        giveAll(player, { { C.COLLECTIBLE_GUARDIAN_ANGEL, 1 }, { C.COLLECTIBLE_LITTLE_STEVEN, 1 },
            { C.COLLECTIBLE_ROTTEN_BABY, 1 }, { C.COLLECTIBLE_GB_BUG, 1 } })
    end)
    wait(150)
    eqCheck("GB Bug absorbed", function(p) return absorbed(p, C.COLLECTIBLE_GB_BUG) end, 1)
    eqCheck("half of 6 returned (3 left absorbed)", function() return totalAbsorbed() - 1 end, 3)
    eqCheck("3 copies spared", function() return sumValues(runSave().spared) end, 3)
    eqCheck("3 familiar items back in inventory", function(p) return ownedFamiliarItems(p) end, 3)
    act(function(player, ctx)
        for key in pairs(runSave().spared or {}) do
            ctx.sparedId = tonumber(tostring(key):match("%d+"))
            break
        end
        if not ctx.sparedId then return end
        ctx.sparedBefore = absorbed(player, ctx.sparedId)
        player:AddCollectible(ctx.sparedId, 0, false)
    end)
    wait(20)
    check("a new copy of a spared familiar is absorbed, the spared one stays", function(player, ctx)
        if not ctx.sparedId then return false, "nothing was spared" end
        local ok = absorbed(player, ctx.sparedId) == ctx.sparedBefore + 1 and ownedFamiliarItems(player) == 3
        return ok, string.format("familiar %s absorbed %d -> %d, owned familiar items %d",
            tostring(ctx.sparedId), ctx.sparedBefore, absorbed(player, ctx.sparedId), ownedFamiliarItems(player))
    end)

    -- attack procs ---------------------------------------------------------------
    section("procs", "a leg stomps the Fatty, red creep under it; blue fly + blue spider appear")
    act(function(player)
        giveAll(player, { { C.COLLECTIBLE_DADDY_LONGLEGS, 10 }, { C.COLLECTIBLE_MOMS_RAZOR, 10 }, { C.COLLECTIBLE_CUBE_BABY, 10 },
            { C.COLLECTIBLE_LIL_SPEWER, 4 }, { C.COLLECTIBLE_ROTTEN_BABY, 2 }, { C.COLLECTIBLE_JUICY_SACK, 2 },
            { C.COLLECTIBLE_LIL_HAUNT, 1 }, { C.COLLECTIBLE_LITTLE_GISH, 1 } })
    end)
    wait(40)
    act(function(player, ctx) snapshotCounters(ctx) fireAt(player, ctx) end)
    wait(30)
    -- Each proc rolls once per attack, but its output is a new attack for the
    -- other procs (the stomp's damage, the creep's ticks), so at 100% the others
    -- fire more than once per tear. Only the stomp must stay at exactly one.
    eqCheck("one tear -> exactly one stomp", function(_, ctx) return delta(ctx, "stomps") end, 1)
    atLeast("bleed", function(_, ctx) return delta(ctx, "bleeds") end, 1)
    atLeast("freeze", function(_, ctx) return delta(ctx, "freezes") end, 1)
    atLeast("red creep", function(_, ctx) return delta(ctx, "creeps") end, 1)
    atLeast("blue fly", function(_, ctx) return delta(ctx, "flies") end, 1)
    atLeast("blue spider", function(_, ctx) return delta(ctx, "spiders") end, 1)

    -- projectile barrier ----------------------------------------------------------
    section("barrier", nil)
    act(function(player) giveAll(player, { { C.COLLECTIBLE_SWORN_PROTECTOR, 20 } }) end)
    wait(40)
    act(function(player, ctx)
        snapshotCounters(ctx)
        ctx.hearts = player:GetHearts() + player:GetSoulHearts()
        -- Spawned right beside the player so no orbital can block it first.
        Isaac.Spawn(EntityType.ENTITY_PROJECTILE, 0, 0, player.Position + Vector(12, 0), Vector(-4, 0), ctx.target)
    end)
    wait(30)
    eqCheck("projectile hit ignored", function(_, ctx) return delta(ctx, "projectileBlocks") end, 1)
    check("no health lost", function(player, ctx)
        local now = player:GetHearts() + player:GetSoulHearts()
        return now == ctx.hearts, string.format("hearts %d -> %d", ctx.hearts, now)
    end)
    section("barrier EID", "the Halo of Flies pedestal's EID ends with the current projectile ignore chance: 100%")
    act(function(player)
        local room = Game():GetRoom()
        local position = room:FindFreePickupSpawnPosition(player.Position + Vector(0, 60), 0, true)
        Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, C.COLLECTIBLE_HALO_OF_FLIES,
            position, Vector.Zero, nil)
    end)
    check("EID token shows the live chance", function()
        local resolver = ConchBlessing.EIDDynamicTokens and ConchBlessing.EIDDynamicTokens.CHRONUS_BLOCK
        if type(resolver) ~= "function" then return false, "no CHRONUS_BLOCK resolver" end
        local value = resolver()
        return value == "100%", "token = " .. tostring(value)
    end)
    wait(90)

    -- getting hit -------------------------------------------------------------------
    section("hurt", "4 holy water puddles, Necronomicon flash, 2 charmed flies, 2 black chargers, a white poop")
    act(function(player)
        giveAll(player, { { C.COLLECTIBLE_HOLY_WATER, 4 }, { C.COLLECTIBLE_DRY_BABY, 4 }, { C.COLLECTIBLE_MILK, 1 },
            { C.COLLECTIBLE_BIRD_CAGE, 1 }, { C.COLLECTIBLE_MYSTERY_EGG, 2 }, { C.COLLECTIBLE_MY_SHADOW, 2 },
            { C.COLLECTIBLE_HALLOWED_GROUND, 1 } })
    end)
    wait(40)
    waitUntil(function(player) return vulnerable(player) end, 120)
    act(function(player, ctx)
        spawnTarget(player, ctx)
        snapshotCounters(ctx)
        ctx.fireDelay = player.MaxFireDelay
        ctx.poops = countWhitePoops()
        ctx.flies = countEntities(EntityType.ENTITY_ATTACKFLY, -1, -1, function(e) return e:HasEntityFlags(EntityFlag.FLAG_CHARM) end)
        ctx.chargers = countEntities(EntityType.ENTITY_CHARGER, 2)
        ctx.creep = countEntities(EntityType.ENTITY_EFFECT, EffectVariant.PLAYER_CREEP_HOLYWATER)
        player:TakeDamage(1, DamageFlag.DAMAGE_NOKILL, EntityRef(player), 30)
    end)
    wait(20)
    eqCheck("hurt effects ran once", function(_, ctx) return delta(ctx, "hurts") end, 1)
    eqCheck("Dry Baby -> Necronomicon", function(_, ctx) return delta(ctx, "necronomicon") end, 1)
    eqCheck("Bird Cage hit", function(_, ctx) return delta(ctx, "birdCage") end, 1)
    atLeast("holy water creep", function(_, ctx)
        return countEntities(EntityType.ENTITY_EFFECT, EffectVariant.PLAYER_CREEP_HOLYWATER) - ctx.creep end, 4)
    atLeast("charmed flies", function(_, ctx) return countEntities(EntityType.ENTITY_ATTACKFLY, -1, -1,
        function(e) return e:HasEntityFlags(EntityFlag.FLAG_CHARM) end) - ctx.flies end, 2)
    atLeast("friendly black chargers", function(_, ctx) return countEntities(EntityType.ENTITY_CHARGER, 2) - ctx.chargers end, 2)
    atLeast("white poop placed", function(_, ctx) return countWhitePoops() - ctx.poops end, 1)
    check("Milk!: tears up after the first hit", function(player, ctx)
        ctx.fireDelayAfterFirst = player.MaxFireDelay
        return player.MaxFireDelay < ctx.fireDelay - 0.01,
            string.format("MaxFireDelay %.2f -> %.2f", ctx.fireDelay, player.MaxFireDelay)
    end)
    wait(10)
    waitUntil(function(player) return vulnerable(player) end, 120)
    act(function(player) player:TakeDamage(1, DamageFlag.DAMAGE_NOKILL, EntityRef(player), 30) end)
    wait(20)
    check("Milk!: no further tears on the second hit", function(player, ctx)
        return math.abs(player.MaxFireDelay - ctx.fireDelayAfterFirst) < 0.01,
            string.format("MaxFireDelay %.2f -> %.2f", ctx.fireDelayAfterFirst, player.MaxFireDelay)
    end)

    -- room clear --------------------------------------------------------------------
    section("clear", "pickups, chests, a soul heart and a rune pop out")
    act(function(player)
        giveAll(player, { { C.COLLECTIBLE_BUM_FRIEND, 10 }, { C.COLLECTIBLE_LIL_CHEST, 10 }, { C.COLLECTIBLE_RELIC, 1 },
            { C.COLLECTIBLE_MYSTERY_SACK, 1 }, { C.COLLECTIBLE_RUNE_BAG, 1 }, { C.COLLECTIBLE_PASCHAL_CANDLE, 1 } })
    end)
    wait(40)
    act(function(player, ctx)
        ctx.chests = countEntities(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_CHEST)
        ctx.soul = countEntities(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_HEART, HeartSubType.HEART_SOUL)
        ctx.cards = countEntities(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD)
        ctx.paschal = tonumber(runSave().paschalHundredths) or 0
        local center = Game():GetRoom():GetCenterPos()
        for _ = 1, 7 do ConchBlessing.chronus.onRoomClear(nil, nil, center) end
    end)
    wait(10)
    atLeast("7 chests (Lil Chest 100%)", function(_, ctx)
        return countEntities(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_CHEST) - ctx.chests end, 7)
    atLeast("Relic soul heart on the 6th clear", function(_, ctx) return countEntities(EntityType.ENTITY_PICKUP,
        PickupVariant.PICKUP_HEART, HeartSubType.HEART_SOUL) - ctx.soul end, 1)
    atLeast("Rune Bag rune on the 7th clear", function(_, ctx)
        return countEntities(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD) - ctx.cards end, 1)
    eqCheck("Paschal Candle +0.21 tears", function(_, ctx) return (tonumber(runSave().paschalHundredths) or 0) - ctx.paschal end, 21)

    -- Gemini --------------------------------------------------------------------------
    section("gemini", nil)
    act(function(player) giveAll(player, { { C.COLLECTIBLE_GEMINI, 3 } }) end)
    wait(40)
    act(function(player, ctx)
        snapshotCounters(ctx)
        -- A fresh, unfrozen Fatty on top of the player: the first target is
        -- usually dead by now (the friendly chargers keep hitting it).
        local npc = Isaac.Spawn(EntityType.ENTITY_FATTY, 0, 0, player.Position, Vector.Zero, nil):ToNPC()
        npc.MaxHitPoints = TARGET_HP
        npc.HitPoints = TARGET_HP
        ctx.geminiTarget = npc
    end)
    wait(30)
    atLeast("contact damage ticks", function(_, ctx) return delta(ctx, "gemini") end, 1)
    act(function(_, ctx)
        if ctx.geminiTarget and ctx.geminiTarget:Exists() then ctx.geminiTarget:Remove() end
    end)

    -- pinned familiars -------------------------------------------------------------------
    section("pinned", "Succubus / Star auras around you with no body or shadow; no Bloodshot Eye body")
    act(function(player)
        giveAll(player, { { C.COLLECTIBLE_BLOODSHOT_EYE, 1 }, { C.COLLECTIBLE_MONGO_BABY, 3 },
            { C.COLLECTIBLE_SUCCUBUS, 1 }, { C.COLLECTIBLE_STAR_OF_BETHLEHEM, 1 } })
    end)
    wait(60)
    eqCheck("hidden Bloodshot Eye pinned", function()
        return countEntities(EntityType.ENTITY_FAMILIAR, FamiliarVariant.BLOODSHOT_EYE, -1,
            function(e) return e:GetData().__chronusBloodshotEye and not e.Visible end) end, 1)
    eqCheck("3 Minisaacs from Mongo Baby", function()
        return countEntities(EntityType.ENTITY_FAMILIAR, FamiliarVariant.MINISAAC, -1,
            function(e) return e:GetData().__chronusMongoMinisaac end) end, 3)
    eqCheck("Succubus aura pinned", function()
        return countEntities(EntityType.ENTITY_FAMILIAR, FamiliarVariant.SUCCUBUS, -1,
            function(e) return e:GetData().__chronusSuccubus end) end, 1)

    -- floor picks ---------------------------------------------------------------------------
    section("floor", nil)
    act(function(player) giveAll(player, { { C.COLLECTIBLE_BUDDY_IN_A_BOX, 2 }, { C.COLLECTIBLE_LIL_DELIRIUM, 1 } }) end)
    wait(60)
    eqCheck("3 floor picks", function() local picks = runSave().floorPicks return picks and #picks.ids or 0 end, 3)

    -- item swaps ------------------------------------------------------------------------------
    section("items", nil)
    act(function(player)
        giveAll(player, { { C.COLLECTIBLE_HEADLESS_BABY, 1 }, { C.COLLECTIBLE_CAINS_OTHER_EYE, 1 },
            { C.COLLECTIBLE_PAPA_FLY, 1 }, { C.COLLECTIBLE_SHADE, 1 }, { C.COLLECTIBLE_GUILLOTINE, 1 } })
    end)
    wait(60)
    eqCheck("Aquarius", function(p) return owns(p, C.COLLECTIBLE_AQUARIUS) end, 1)
    eqCheck("Rubber Cement", function(p) return owns(p, C.COLLECTIBLE_RUBBER_CEMENT) end, 1)
    eqCheck("Hive Mind", function(p) return owns(p, C.COLLECTIBLE_HIVE_MIND) end, 1)
    eqCheck("Lusty Blood", function(p) return owns(p, C.COLLECTIBLE_LUSTY_BLOOD) end, 1)

    -- old-save Daddy Longlegs grant ---------------------------------------------------------------
    section("daddy", nil)
    act(function(player, ctx)
        ctx.holy = owns(player, C.COLLECTIBLE_HOLY_LIGHT)
        probe.legacyDaddy(player)
    end)
    wait(10)
    check("old Holy Light grant taken back", function(player, ctx)
        local grants = runSave().itemGrants or {}
        local ok = owns(player, C.COLLECTIBLE_HOLY_LIGHT) == ctx.holy and grants["fam_" .. C.COLLECTIBLE_DADDY_LONGLEGS] == nil
        return ok, string.format("Holy Light %d -> %d", ctx.holy, owns(player, C.COLLECTIBLE_HOLY_LIGHT))
    end)

    -- temporary familiars -------------------------------------------------------------------------
    section("temp: Box of Friends", "a Box of Friends icon dissolves into you; no Demon Baby appears")
    act(function(player, ctx)
        ctx.daddyEffect = ConchBlessing.chronus._getEffectCount(player, C.COLLECTIBLE_DADDY_LONGLEGS)
        player:UseActiveItem(C.COLLECTIBLE_BOX_OF_FRIENDS, UseFlag.USE_NOANIM, -1)
    end)
    wait(20)
    eqCheck("room doubling active", function() return ConchBlessing.chronus._getRoomTemporary().double end, 1)
    check("effects count twice", function(player, ctx)
        local now = ConchBlessing.chronus._getEffectCount(player, C.COLLECTIBLE_DADDY_LONGLEGS)
        return now == ctx.daddyEffect * 2, string.format("Daddy Longlegs effect %d -> %d", ctx.daddyEffect, now)
    end)
    eqCheck("no Demon Baby familiar", function()
        return countEntities(EntityType.ENTITY_FAMILIAR, FamiliarVariant.DEMON_BABY) end, 0)

    section("temp: Monster Manual", "the summoned familiar's icon dissolves into you")
    act(function(player, ctx)
        snapshotCounters(ctx)
        player:UseActiveItem(C.COLLECTIBLE_MONSTER_MANUAL, UseFlag.USE_NOANIM, -1)
    end)
    wait(20)
    check("summoned familiar absorbed for the floor", function(_, ctx)
        local floor = runSave().tempFloor
        local credited = floor and sumValues(floor.counts) or 0
        if credited > 0 then return true, string.format("%d credited for the floor", credited) end
        return false, "no temporary familiar effect found (engine may summon it another way)"
    end)
    act(function(player, ctx)
        ctx.manualCredits = sumValues(runSave().tempFloor and runSave().tempFloor.counts)
        ctx.manualGrants = sumValues(runSave().itemGrants)
        ctx.manualDamage = player.Damage
        ctx.room = Game():GetLevel():GetCurrentRoomIndex()
        Isaac.ExecuteCommand("goto s.shop")
    end)
    wait(20)
    check("room entry does not credit Manual twice", function(player, ctx)
        local credits = sumValues(runSave().tempFloor and runSave().tempFloor.counts)
        return credits == ctx.manualCredits and sumValues(runSave().itemGrants) == ctx.manualGrants,
            string.format("credits %d -> %d, damage %.4f -> %.4f", ctx.manualCredits, credits, ctx.manualDamage, player.Damage)
    end)
    act(function(player, ctx)
        Game():StartRoomTransition(ctx.room, Direction.NO_DIRECTION, RoomTransitionAnim.FADE)
    end)
    wait(20)

    section("temp: Soul of Lilith", nil)
    act(function(player, ctx)
        ctx.total = totalAbsorbed()
        ctx.permanent = sumValues(runSave().tempPermanent)
        player:UseCard(Card.CARD_SOUL_LILITH, UseFlag.USE_NOANIM)
    end)
    -- Soul of Lilith hands its familiar over through the item pickup queue, so
    -- it lands (and is absorbed) only after the hold-up animation.
    waitUntil(function(_, ctx)
        return totalAbsorbed() > ctx.total or sumValues(runSave().tempPermanent) > ctx.permanent
    end, 150)
    wait(5)
    check("Lilith's familiar absorbed", function(_, ctx)
        local asItem = totalAbsorbed() - ctx.total
        local asEffect = sumValues(runSave().tempPermanent) - ctx.permanent
        return asItem + asEffect >= 1, string.format("as collectible +%d, as temporary effect +%d", asItem, asEffect)
    end)

    section("temp: Pretty Fly pill", nil)
    act(function(player, ctx)
        ctx.prettyFlies = tonumber(runSave().prettyFlies) or 0
        player:UsePill(PillEffect.PILLEFFECT_PRETTY_FLY, PillColor.PILL_BLUE_BLUE, UseFlag.USE_NOANIM)
    end)
    wait(20)
    check("pretty fly absorbed as a 5% block", function(_, ctx)
        if type(ModCallbacks.MC_PRE_USE_PILL) ~= "number" then return nil, "needs REPENTOGON" end
        local now = tonumber(runSave().prettyFlies) or 0
        return now == ctx.prettyFlies + 1, string.format("pretty flies %d -> %d", ctx.prettyFlies, now)
    end)

    section("temp: Sacrificial Altar", "2 reverse dust swirls, then 2 devil items appear")
    act(function(player, ctx)
        ctx.total = totalAbsorbed()
        ctx.pedestals = countEntities(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE)
        player:UseActiveItem(C.COLLECTIBLE_SACRIFICIAL_ALTAR, UseFlag.USE_NOANIM, -1)
    end)
    wait(20)
    -- The altar picks its own familiars first (the ones GB Bug handed back,
    -- Minisaacs...); only the rest of its 2 comes out of the absorbed pool.
    check("absorbed pool covers only what the altar left", function(_, ctx)
        local items = countEntities(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE) - ctx.pedestals
        local fromAbsorbed = ctx.total - totalAbsorbed()
        return items == 2 and fromAbsorbed <= 2, string.format("absorbed -%d, devil items +%d", fromAbsorbed, items)
    end)

    section("temp: The Twins", "room reloads until The Twins fires (50% per entry)")
    act(function(player, ctx)
        player:AddTrinket(TrinketType.TRINKET_THE_TWINS, false)
        ctx.twinsHit = false
    end)
    for _ = 1, 8 do
        act(function(_, ctx)
            if ctx.twinsHit then return end
            ctx.roomsBefore = ctx.rooms
            local level = Game():GetLevel()
            Game():StartRoomTransition(level:GetCurrentRoomIndex(), Direction.NO_DIRECTION, RoomTransitionAnim.FADE)
        end)
        waitUntil(function(_, ctx) return ctx.twinsHit or ctx.rooms > ctx.roomsBefore end, 120)
        wait(15)
        act(function(_, ctx)
            if next(ConchBlessing.chronus._getRoomTemporary().twins) or next(ConchBlessing.chronus._getRoomTemporary().counts) then
                ctx.twinsHit = true
            end
        end)
    end
    check("The Twins doubled an absorbed familiar", function(player, ctx)
        player:TryRemoveTrinket(TrinketType.TRINKET_THE_TWINS)
        if ctx.twinsHit then return true, "doubled on a room entry" end
        return false, "8 room entries without a Twins stand-in (or room reload unsupported)"
    end)

    -- spawned summons that must stay vanilla ---------------------------------------------------
    -- Only the allow-listed sources are absorbed; these keep their own behaviour.
    local untouched = {
        { "Book of Virtues wisp", FamiliarVariant.WISP, 1,
            -- Book of Virtues only makes wisps for a book the player holds; the
            -- engine's own wisp API makes the same familiar without that setup.
            function(p) p:AddWisp(C.COLLECTIBLE_BOOK_OF_VIRTUES, p.Position) end },
        { "Lemegeton item wisp", FamiliarVariant.ITEM_WISP, 1,
            function(p) p:UseActiveItem(C.COLLECTIBLE_LEMEGETON, UseFlag.USE_NOANIM, -1) end },
        { "Guppy's Head blue flies", FamiliarVariant.BLUE_FLY, 2,
            function(p) p:UseActiveItem(C.COLLECTIBLE_GUPPYS_HEAD, UseFlag.USE_NOANIM, -1) end },
        { "Brown Nugget pooter", FamiliarVariant.BROWN_NUGGET_POOTER, 1,
            function(p) p:UseActiveItem(C.COLLECTIBLE_BROWN_NUGGET, UseFlag.USE_NOANIM, -1) end },
        { "XV - The Devil? Seraphim", FamiliarVariant.SERAPHIM, 1,
            function(p) p:UseCard(Card.CARD_REVERSE_DEVIL, UseFlag.USE_NOANIM) end },
    }
    for _, source in ipairs(untouched) do
        local label, variant, minimum, use = source[1], source[2], source[3], source[4]
        section("vanilla: " .. label, nil)
        act(function(player, ctx)
            snapshotCounters(ctx)
            ctx.total = totalAbsorbed()
            ctx.count = countEntities(EntityType.ENTITY_FAMILIAR, variant)
            use(player)
        end)
        wait(45)
        check(label .. " appears and is not absorbed", function(_, ctx)
            local gained = countEntities(EntityType.ENTITY_FAMILIAR, variant) - ctx.count
            local absorbedNow = totalAbsorbed() - ctx.total + delta(ctx, "tempAbsorbed")
            return gained >= minimum and absorbedNow == 0,
                string.format("familiars +%d (want >= %d), absorbed +%d (want 0)", gained, minimum, absorbedNow)
        end)
    end

    -- Tonsil stays vanilla: the engine keeps its count in a player field with no API,
    -- so an absorbed Tonsil would just be respawned from that count.
    section("vanilla: Tonsil", "take hits until a Tonsil familiar appears")
    act(function(player, ctx)
        ctx.total = totalAbsorbed()
        player:AddMaxHearts(12, false)
        player:AddHearts(24)
        player:AddTrinket(TrinketType.TRINKET_TONSIL, false)
        ctx.tonsilHits = 0
        ctx.tonsilBefore = countEntities(EntityType.ENTITY_FAMILIAR, FamiliarVariant.TONSIL)
    end)
    -- Tonsil needs 6-12 landed hits. The damage cooldown can read 0 while the
    -- engine still ignores hits, so every attempt waits until the hit actually
    -- registered (or 45 updates pass, after which the next attempt lands).
    local function tonsilDone(ctx)
        return countEntities(EntityType.ENTITY_FAMILIAR, FamiliarVariant.TONSIL) > ctx.tonsilBefore
            or delta(ctx, "hurts") >= 13
    end
    for _ = 1, 40 do
        act(function(player, ctx)
            if tonsilDone(ctx) then return end
            ctx.tonsilHits = ctx.tonsilHits + 1
            ctx.hurtsBefore = counters().hurts or 0
            player:TakeDamage(1, DamageFlag.DAMAGE_NOKILL, EntityRef(player), 2)
        end)
        waitUntil(function(_, ctx)
            return tonsilDone(ctx) or (counters().hurts or 0) > (ctx.hurtsBefore or 0)
        end, 45)
    end
    check("Tonsil appears and is not absorbed", function(player, ctx)
        local tonsils = countEntities(EntityType.ENTITY_FAMILIAR, FamiliarVariant.TONSIL) - ctx.tonsilBefore
        player:TryRemoveTrinket(TrinketType.TRINKET_TONSIL)
        return tonsils >= 1 and totalAbsorbed() == ctx.total,
            string.format("Tonsil familiars +%d after %d registered hits (%d attempts), absorbed +%d",
                tonsils, delta(ctx, "hurts"), ctx.tonsilHits, totalAbsorbed() - ctx.total)
    end)

    -- losing Chronus -----------------------------------------------------------------------------
    section("drop", "every absorbed familiar comes back out of your body in reverse dust")
    act(function(player, ctx)
        ctx.total = totalAbsorbed()
        ctx.owned = ownedFamiliarItems(player)
        while player:HasCollectible(CHRONUS_ID, true) do player:RemoveCollectible(CHRONUS_ID) end
    end)
    wait(30)
    check("absorbed familiars returned", function(player, ctx)
        local gained = ownedFamiliarItems(player) - ctx.owned
        return gained == ctx.total, string.format("familiar items +%d, absorbed was %d", gained, ctx.total)
    end)
    eqCheck("granted Aquarius taken back", function(p) return owns(p, C.COLLECTIBLE_AQUARIUS) end, 0)
    eqCheck("ledger cleared", function() return totalAbsorbed() end, 0)
end

-- Manual setups and helpers, reached as `conch_chronus <action>`.
local function handleCommand(action, words, player)
    local scenario = findScenario(action)
    if scenario then
        probe.run(scenario, player)
    elseif action == "status" then
        probe.status(player)
    elseif action == "hurtme" then
        player:TakeDamage(1, DamageFlag.DAMAGE_NOKILL, EntityRef(player), 30)
        out("hit taken (no kill). Effects run on the next update.")
    elseif action == "clearsim" then
        ConchBlessing.chronus._runReady = true
        local count = math.max(1, math.floor(tonumber(words[2]) or 1))
        local center = Game():GetRoom():GetCenterPos()
        for _ = 1, count do
            ConchBlessing.chronus.onRoomClear(nil, nil, center)
        end
        out(string.format("ran the room-clear reward %d time(s)", count))
    elseif action == "enemies" then
        spawnEnemies("fatty", math.max(1, math.floor(tonumber(words[2]) or 3)))
    elseif action == "give" then
        local id = tonumber(words[2])
        if not id then out("usage: conch_chronus give <id> [count]") return true end
        give(player, id, math.max(1, math.floor(tonumber(words[3]) or 1)))
    elseif action == "drop" then
        while player:HasCollectible(CHRONUS_ID, true) do
            player:RemoveCollectible(CHRONUS_ID)
        end
        out("Chronus removed: absorbed familiars return with the reverse visual, granted items are taken back")
    else
        return false
    end
    return true
end

TestBench.register({
    command = "conch_chronus",
    tag = "ChronusProbe",
    duration = "about 2 minutes",
    build = buildPlan,
    onSection = snapshotCounters,
    handle = handleCommand,
    help = probe.help,
})

ConchBlessing.chronusProbe = probe
return probe
