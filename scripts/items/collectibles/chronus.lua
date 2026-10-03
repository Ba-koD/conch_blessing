local hiddenItemManager = require("scripts.lib.hidden_item_manager")
local DamageProvenance = require("scripts.lib.damage_provenance")
DamageProvenance.registerCallbacks(ConchBlessing)

ConchBlessing.chronus = ConchBlessing.chronus or {}

-- STATS: Item stat modifiers (Dark Rock style)
ConchBlessing.chronus.STATS = {
    DAMAGE_PER_FAMILIAR = 2.0,        -- Every absorbed familiar, independently of its special effect
    BROTHER_BOBBY_TEARS = 2.0,        -- Tears per absorbed Brother Bobby
    GUARDIAN_ANGEL_SPEED = 0.3,       -- Speed per absorbed Guardian Angel
    GUILLOTINE_DAMAGE = 1.0,          -- Guillotine keeps its vanilla stat bonus per copy
    GUILLOTINE_TEARS = 0.5,
    MILK_TEARS = 1.0,                 -- Per copy, for the rest of the floor after its first hit
    PASCHAL_TEARS_PER_CLEAR = 0.03,   -- Per copy and room clear, permanent while absorbed
}

-- absorbActions re-run every frame from onPlayerUpdate, so an unconditional log
-- there writes the same line ~30 times a second. Emit one only when a count moves.
local absorbLogState = {}
local function logAbsorbOnce(label, total, delta)
    local t = tonumber(total) or 0
    local d = tonumber(delta) or 0
    local previous = absorbLogState[label]
    if previous and previous.total == t and previous.delta == d then return end
    absorbLogState[label] = { total = t, delta = d }
    ConchBlessing.printDebug(string.format(
        "[Chronus] %s absorbed: total=%d, delta=%d", label, t, d))
end

-- Data container: configuration and runtime-safe defaults (no hardcoded debug literals)
ConchBlessing.chronus.data = ConchBlessing.chronus.data or {
    absorbAll = false,
    spriteNullPath = "gfx/ui/null.png",
    pairOffsetPixels = 2.0,
    laserEyeYOffset = -6,
    anchorDepthOffset = -10,
    angelicPrismOffset = 0,
    angelicPrismCount = 1,
    angelicPrismSizeScale = 4,
    -- DEBUG ONLY: leaves the prisms fully rendered (sprite + shadow). Set back to
    -- false before shipping; nothing else reads this.
    angelicPrismDebugVisible = false,
    scanIntervalFrames = 1,
    -- The engine exposes no event for a pinned star's aura switching itself off,
    -- so the star is replaced on room entry (onNewRoom) and then on this bounded
    -- in-room timer, which restarts at every room entry. Shortened from 10s to 8s
    -- for more margin before the aura can drop while staying in one room.
    starOfBethlehemSpawnIntervalFrames = 240,
    blacklist = {
        [CollectibleType.COLLECTIBLE_ONE_UP] = true,
        [CollectibleType.COLLECTIBLE_ISAACS_HEART] = true,
        [CollectibleType.COLLECTIBLE_DEAD_CAT] = true,
        [CollectibleType.COLLECTIBLE_KEY_PIECE_1] = true,
        [CollectibleType.COLLECTIBLE_KEY_PIECE_2] = true,
        [CollectibleType.COLLECTIBLE_KNIFE_PIECE_1] = true,
        [CollectibleType.COLLECTIBLE_KNIFE_PIECE_2] = true,
        -- Absorbing these removes only their drawback or makes no sense to absorb.
        [CollectibleType.COLLECTIBLE_DAMOCLES_PASSIVE] = true,
        [CollectibleType.COLLECTIBLE_STRAW_MAN] = true,
        [CollectibleType.COLLECTIBLE_BLOOD_OATH] = true,
    },
    -- Familiar -> Item conversion mapping
    -- When a familiar is absorbed, it grants this item
    -- maxGrants: 0 = unlimited, 1 = once only, 2 = twice, etc.
    familiarToItemMap = {
        [CollectibleType.COLLECTIBLE_ROBO_BABY] = {  -- Robo-Baby -> Technology
            itemId = CollectibleType.COLLECTIBLE_TECHNOLOGY,
            maxGrants = 0,  -- Unlimited: each Robo Baby grants Technology
        },
        [CollectibleType.COLLECTIBLE_ROBO_BABY_2] = {  -- Robo-Baby 2.0 -> Technology 2
            itemId = CollectibleType.COLLECTIBLE_TECHNOLOGY_2,
            maxGrants = 0,  -- Unlimited: each Robo-Baby 2.0 grants Technology 2
        },
        [CollectibleType.COLLECTIBLE_BLUE_BABYS_ONLY_FRIEND] = {  -- Blue Baby's Only Friend -> Ludovico Technique
            itemId = CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE,
            maxGrants = 1,  -- Only first one grants Ludovico Technique
        },
        [CollectibleType.COLLECTIBLE_LIL_BRIMSTONE] = {  -- Lil Brimstone -> Brimstone
            itemId = CollectibleType.COLLECTIBLE_BRIMSTONE,
            maxGrants = 0,  -- Unlimited: each Lil Brimstone grants Brimstone
        },
        [CollectibleType.COLLECTIBLE_BOBS_BRAIN] = {  -- Bob's Brain -> Ipecac
            itemId = CollectibleType.COLLECTIBLE_IPECAC,
            maxGrants = 1,  -- Only first Bob's Brain grants Ipecac
        },
        [CollectibleType.COLLECTIBLE_LIL_MONSTRO] = {  -- Lil Monstro -> Monstro's Lung
            itemId = CollectibleType.COLLECTIBLE_MONSTROS_LUNG,
            maxGrants = 1,  -- Only first Lil Monstro grants Monstro's Lung
        },
        [CollectibleType.COLLECTIBLE_SERAPHIM] = {  -- Seraphim -> Sacred Heart
            itemId = CollectibleType.COLLECTIBLE_SACRED_HEART,
            maxGrants = 1,  -- Only first Seraphim grants Sacred Heart
        },
        [CollectibleType.COLLECTIBLE_BLOOD_PUPPY] = {  -- Blood Puppy -> Gimpy
            itemId = CollectibleType.COLLECTIBLE_GIMPY,
            maxGrants = 1,  -- Only first Blood Puppy grants Gimpy
        },
        [CollectibleType.COLLECTIBLE_BOT_FLY] = {  -- Bot Fly -> Lost Contact
            itemId = CollectibleType.COLLECTIBLE_LOST_CONTACT,
            maxGrants = 1,  -- Only first Bot Fly grants Lost Contact
        },
        [CollectibleType.COLLECTIBLE_FREEZER_BABY] = {  -- Freezer Baby -> Uranus
            itemId = CollectibleType.COLLECTIBLE_URANUS,
            maxGrants = 1,  -- Only first Freezer Baby grants Uranus
        },
        [CollectibleType.COLLECTIBLE_LIL_ABADDON] = {  -- Lil Abaddon -> Maw of the Void
            itemId = CollectibleType.COLLECTIBLE_MAW_OF_THE_VOID,
            maxGrants = 1,  -- Only first Lil Abaddon grants Maw of the Void
        },
        [CollectibleType.COLLECTIBLE_MULTIDIMENSIONAL_BABY] = {  -- Multidimensional Baby -> 20/20
            itemId = CollectibleType.COLLECTIBLE_20_20,
            maxGrants = 0,  -- Unlimited: each one grants 20/20
        },
        [CollectibleType.COLLECTIBLE_HARLEQUIN_BABY] = {  -- Harlequin Baby -> The Wiz
            itemId = CollectibleType.COLLECTIBLE_THE_WIZ,
            maxGrants = 0,  -- Unlimited: each one grants The Wiz
        },
        [CollectibleType.COLLECTIBLE_LIL_LOKI] = {  -- Lil Loki -> Loki's Horns
            itemId = CollectibleType.COLLECTIBLE_LOKIS_HORNS,
            maxGrants = 0,  -- Unlimited: each one grants Loki's Horns
        },
        [CollectibleType.COLLECTIBLE_GHOST_BABY] = {  -- Ghost Baby -> Continuum
            itemId = CollectibleType.COLLECTIBLE_CONTINUUM,
            maxGrants = 0,  -- Unlimited: each one grants Continuum
        },
        [CollectibleType.COLLECTIBLE_RAINBOW_BABY] = {  -- Rainbow Baby -> Fruit Cake
            itemId = CollectibleType.COLLECTIBLE_FRUIT_CAKE,
            maxGrants = 1,  -- Only first Rainbow Baby grants Fruit Cake
        },
        [CollectibleType.COLLECTIBLE_LEECH] = {  -- Leech -> Charm of the Vampire
            itemId = CollectibleType.COLLECTIBLE_CHARM_VAMPIRE,
            maxGrants = 1,  -- Only first Leech grants Charm of the Vampire
        },
        [CollectibleType.COLLECTIBLE_BOMB_BAG] = {  -- Bomb Bag -> Pyro
            itemId = CollectibleType.COLLECTIBLE_PYRO,
            maxGrants = 1,  -- Only first Bomb Bag grants Pyro
        },
        [CollectibleType.COLLECTIBLE_DARK_BUM] = {  -- Dark Bum -> Mitre
            itemId = CollectibleType.COLLECTIBLE_MITRE,
            maxGrants = 1,  -- Only first Dark Bum grants Mitre
        },
        [CollectibleType.COLLECTIBLE_KEY_BUM] = {  -- Key Bum -> Skeleton Key
            itemId = CollectibleType.COLLECTIBLE_SKELETON_KEY,
            maxGrants = 1,  -- Only first Key Bum grants Skeleton Key
        },
        [CollectibleType.COLLECTIBLE_ABEL] = {  -- Abel -> My Reflection
            itemId = CollectibleType.COLLECTIBLE_MY_REFLECTION,
            maxGrants = 1,  -- Only first Abel grants My Reflection
        },
        [CollectibleType.COLLECTIBLE_DEMON_BABY] = {  -- Demon Baby -> Marked
            itemId = CollectibleType.COLLECTIBLE_MARKED,
            maxGrants = 1,  -- Only first Demon Baby grants Marked
        },
        [CollectibleType.COLLECTIBLE_BROTHER_BOBBY] = {  -- Brother Bobby -> Fire Rate +2 (handled in onEvaluateCache)
            itemId = nil,
            maxGrants = 0,
        },
        [CollectibleType.COLLECTIBLE_LITTLE_GISH] = {  -- Little Gish -> Slowing effect (handled in onEntityTakeDamage)
            itemId = nil,
            maxGrants = 0,
        },
        [CollectibleType.COLLECTIBLE_ROTTEN_BABY] = {  -- Rotten Baby -> Spawn flies (handled in onEntityTakeDamage)
            itemId = nil,
            maxGrants = 0,
        },
        [CollectibleType.COLLECTIBLE_LITTLE_STEVEN] = {  -- Little Steven -> Homing (handled in onFireTear)
            itemId = nil,
            maxGrants = 0,
        },
        [CollectibleType.COLLECTIBLE_GUARDIAN_ANGEL] = {  -- Guardian Angel -> Speed +0.3 (handled in onEvaluateCache)
            itemId = nil,
            maxGrants = 0,
        },
        [CollectibleType.COLLECTIBLE_CENSER] = {  -- Censer -> Fixed position (handled in absorbActions)
            itemId = nil,
            maxGrants = 0,
        },
        [CollectibleType.COLLECTIBLE_STAR_OF_BETHLEHEM] = {  -- Star of Bethlehem -> Compass + Fixed position
            itemId = CollectibleType.COLLECTIBLE_COMPASS,
            maxGrants = 1,  -- Only first one grants Compass
        },
        [CollectibleType.COLLECTIBLE_FARTING_BABY] = {  -- Farting Baby -> Jelly Belly
            itemId = CollectibleType.COLLECTIBLE_JELLY_BELLY,
            maxGrants = 1,  -- Only first one grants Jelly Belly
        },
        [CollectibleType.COLLECTIBLE_SAMSONS_CHAINS] = {  -- Samson's Chains -> Thunder Thighs
            itemId = CollectibleType.COLLECTIBLE_THUNDER_THIGHS,
            maxGrants = 1,  -- Only first one grants Thunder Thighs
        },
        [CollectibleType.COLLECTIBLE_FINGER] = {  -- Finger -> Tractor Beam
            itemId = CollectibleType.COLLECTIBLE_TRACTOR_BEAM,
            maxGrants = 1,  -- Only first one grants Tractor Beam
        },
        [CollectibleType.COLLECTIBLE_LITTLE_CHAD] = {  -- Little C.H.A.D. -> Candy Heart
            itemId = CollectibleType.COLLECTIBLE_CANDY_HEART,
            maxGrants = 1,  -- Only first one grants Candy Heart
        },
        [CollectibleType.COLLECTIBLE_SACK_OF_PENNIES] = {  -- Sack of Pennies -> Dollar
            itemId = CollectibleType.COLLECTIBLE_DOLLAR,
            maxGrants = 1,  -- Only first one grants Dollar
        },
        [CollectibleType.COLLECTIBLE_SACK_OF_SACKS] = {  -- Sack of Sacks -> Sack Head
            itemId = CollectibleType.COLLECTIBLE_SACK_HEAD,
            maxGrants = 1,  -- Only first one grants Sack Head
        },
        [CollectibleType.COLLECTIBLE_CHARGED_BABY] = {  -- Charged Baby -> 9 Volt
            itemId = CollectibleType.COLLECTIBLE_9_VOLT,
            maxGrants = 1,  -- Only first one grants 9 Volt
        },
        [CollectibleType.COLLECTIBLE_YO_LISTEN] = {  -- Yo Listen -> X-Ray Vision
            itemId = CollectibleType.COLLECTIBLE_XRAY_VISION,
            maxGrants = 1,  -- Only first one grants X-Ray Vision
        },
        -- Daddy Longlegs used to grant Holy Light; it now stomps instead (see
        -- RETIRED_GRANTS and the hit-effects section).
        -- Several familiars below share a target item with another mapping (Mars,
        -- Jelly Belly, 20/20); grant baselines are tracked per item.
        [CollectibleType.COLLECTIBLE_SISTER_MAGGY] = {  -- Sister Maggy -> Cricket's Head
            itemId = CollectibleType.COLLECTIBLE_CRICKETS_HEAD,
            maxGrants = 1,
        },
        [CollectibleType.COLLECTIBLE_LITTLE_CHUBBY] = {  -- Little Chubby -> Mars
            itemId = CollectibleType.COLLECTIBLE_MARS,
            maxGrants = 1,
        },
        [CollectibleType.COLLECTIBLE_BIG_CHUBBY] = {  -- Big Chubby -> Mars (+ projectile block)
            itemId = CollectibleType.COLLECTIBLE_MARS,
            maxGrants = 1,
        },
        [CollectibleType.COLLECTIBLE_PEEPER] = {  -- The Peeper -> Mom's Eye
            itemId = CollectibleType.COLLECTIBLE_MOMS_EYE,
            maxGrants = 1,
        },
        [CollectibleType.COLLECTIBLE_BBF] = {  -- BBF -> Fire Mind
            itemId = CollectibleType.COLLECTIBLE_FIRE_MIND,
            maxGrants = 1,
        },
        [CollectibleType.COLLECTIBLE_FATES_REWARD] = {  -- Fate's Reward -> 20/20
            itemId = CollectibleType.COLLECTIBLE_20_20,
            maxGrants = 1,
        },
        [CollectibleType.COLLECTIBLE_LIL_GURDY] = {  -- Lil Gurdy -> Chocolate Milk
            itemId = CollectibleType.COLLECTIBLE_CHOCOLATE_MILK,
            maxGrants = 1,
        },
        [CollectibleType.COLLECTIBLE_BUMBO] = {  -- Bumbo -> Piggy Bank
            itemId = CollectibleType.COLLECTIBLE_PIGGY_BANK,
            maxGrants = 1,
        },
        [CollectibleType.COLLECTIBLE_SPIDER_MOD] = {  -- Spider Mod -> Spider Bite
            itemId = CollectibleType.COLLECTIBLE_SPIDER_BITE,
            maxGrants = 1,
        },
        [CollectibleType.COLLECTIBLE_DEPRESSION] = {  -- Depression -> Holy Light
            itemId = CollectibleType.COLLECTIBLE_HOLY_LIGHT,
            maxGrants = 1,
        },
        [CollectibleType.COLLECTIBLE_KING_BABY] = {  -- King Baby -> Magic Mushroom
            itemId = CollectibleType.COLLECTIBLE_MAGIC_MUSHROOM,
            maxGrants = 1,
        },
        [CollectibleType.COLLECTIBLE_ACID_BABY] = {  -- Acid Baby -> PHD
            itemId = CollectibleType.COLLECTIBLE_PHD,
            maxGrants = 1,
        },
        [CollectibleType.COLLECTIBLE_JAW_BONE] = {  -- Jaw Bone -> Compound Fracture
            itemId = CollectibleType.COLLECTIBLE_COMPOUND_FRACTURE,
            maxGrants = 1,
        },
        [CollectibleType.COLLECTIBLE_BOILED_BABY] = {  -- Boiled Baby -> Eye Sore
            itemId = CollectibleType.COLLECTIBLE_EYE_SORE,
            maxGrants = 1,
        },
        [CollectibleType.COLLECTIBLE_LIL_DUMPY] = {  -- Lil Dumpy -> Jelly Belly
            itemId = CollectibleType.COLLECTIBLE_JELLY_BELLY,
            maxGrants = 1,
        },
        [CollectibleType.COLLECTIBLE_FRUITY_PLUM] = {  -- Fruity Plum -> Kidney Stone
            itemId = CollectibleType.COLLECTIBLE_KIDNEY_STONE,
            maxGrants = 1,
        },
        [CollectibleType.COLLECTIBLE_HEADLESS_BABY] = {  -- Headless Baby -> Aquarius
            itemId = CollectibleType.COLLECTIBLE_AQUARIUS,
            maxGrants = 1,
        },
        [CollectibleType.COLLECTIBLE_CAINS_OTHER_EYE] = {  -- Cain's Other Eye -> Rubber Cement
            itemId = CollectibleType.COLLECTIBLE_RUBBER_CEMENT,
            maxGrants = 1,
        },
        [CollectibleType.COLLECTIBLE_PAPA_FLY] = {  -- Papa Fly -> Hive Mind
            itemId = CollectibleType.COLLECTIBLE_HIVE_MIND,
            maxGrants = 1,
        },
        [CollectibleType.COLLECTIBLE_SHADE] = {  -- Shade -> Lusty Blood
            itemId = CollectibleType.COLLECTIBLE_LUSTY_BLOOD,
            maxGrants = 1,
        },
    },
    absorbActions = {
        [CollectibleType.COLLECTIBLE_TWISTED_PAIR] = function(player, total, delta)
            logAbsorbOnce("Twisted Pair", total, delta)
            ConchBlessing.chronus._ensureTwistedPairs(player)
            ConchBlessing.chronus._updateTwistedPairAnchors(player)
        end,
        [CollectibleType.COLLECTIBLE_INCUBUS] = function(player, total, delta)
            logAbsorbOnce("Incubus", total, delta)
            ConchBlessing.chronus._ensureIncubusStack(player)
            ConchBlessing.chronus._updateIncubusAnchors(player)
        end,
        [CollectibleType.COLLECTIBLE_SUCCUBUS] = function(player, total, delta)
            logAbsorbOnce("Succubus", total, delta)
            ConchBlessing.chronus._ensureSuccubusStack(player)
            ConchBlessing.chronus._updateSuccubusAnchors(player)
        end,
        [CollectibleType.COLLECTIBLE_ANGELIC_PRISM] = function(player, total, delta)
            logAbsorbOnce("Angelic Prism", total, delta)
            ConchBlessing.chronus._ensureAngelicPrismStack(player)
            ConchBlessing.chronus._updateAngelicPrismAnchors(player)
        end,
        [CollectibleType.COLLECTIBLE_SERAPHIM] = function(player, total, delta)
            logAbsorbOnce("Seraphim", total, delta)
            ConchBlessing.chronus._ensureSeraphimEffects(player)
        end,
        [CollectibleType.COLLECTIBLE_CENSER] = function(player, total, delta)
            logAbsorbOnce("Censer", total, delta)
            ConchBlessing.chronus._ensureCenserStack(player)
            ConchBlessing.chronus._updateCenserAnchors(player)
        end,
        [CollectibleType.COLLECTIBLE_STAR_OF_BETHLEHEM] = function(player, total, delta)
            logAbsorbOnce("Star of Bethlehem", total, delta)
            ConchBlessing.chronus._ensureStarOfBethlehemStack(player, (tonumber(delta) or 0) > 0)
            ConchBlessing.chronus._updateStarOfBethlehemAnchors(player)
        end,
        [CollectibleType.COLLECTIBLE_BLOODSHOT_EYE] = function(player, total, delta)
            logAbsorbOnce("Bloodshot Eye", total, delta)
            ConchBlessing.chronus._ensureBloodshotEyeStack(player)
            ConchBlessing.chronus._updateBloodshotEyeAnchors(player)
        end,
    },
}

local CHRONUS_ID = Isaac.GetItemIdByName("Chronus")

local function dbg(msg)
    if ConchBlessing.Config and ConchBlessing.Config.debugMode then
        ConchBlessing.printDebug("[Chronus] " .. tostring(msg))
    end
end

-- Runtime tallies of effects that fired, read only by the dev test bench
-- (scripts/dev/chronus_probe.lua) to verify them in game. Never saved.
ConchBlessing.chronus._counters = {}
local function bump(name, amount)
    local counters = ConchBlessing.chronus._counters
    counters[name] = (counters[name] or 0) + (amount or 1)
end

local function getRunSave(player)
    local sm = ConchBlessing.SaveManager
    if not sm then return nil end
    local globalSave = sm.GetRunSave(nil)
    if not globalSave then return nil end
    globalSave.chronus = globalSave.chronus or {
        absorbed = {},
        totalAbsorbed = 0,
        itemGrants = {},  -- Track how many items granted per familiar: ["fam_95"] = 3
        itemGrantTotals = {}, -- Lifetime grants for maxGrants limits
        itemGrantBaselines = {}, -- Preserve non-Chronus copies of converted items
    }

    if player then
        local per = sm.GetRunSave(player)
        if per and per.chronus and (per.chronus.absorbed or per.chronus.totalAbsorbed) then
            dbg("Migrating per-player chronus data to global store")
            local g = globalSave.chronus
            g.absorbed = g.absorbed or {}
            g.itemGrants = g.itemGrants or {}
            g.itemGrantTotals = g.itemGrantTotals or {}
            g.itemGrantBaselines = g.itemGrantBaselines or {}
            for cid, entry in pairs(per.chronus.absorbed or {}) do
                local prev = (g.absorbed[cid] and g.absorbed[cid].count) or 0
                local add = (entry and entry.count) or 0
                if add > 0 then
                    g.absorbed[cid] = { count = prev + add }
                end
            end
            for key, count in pairs(per.chronus.itemGrants or {}) do
                g.itemGrants[key] = math.max(tonumber(g.itemGrants[key]) or 0, tonumber(count) or 0)
            end
            for key, count in pairs(per.chronus.itemGrantTotals or per.chronus.itemGrants or {}) do
                g.itemGrantTotals[key] = math.max(tonumber(g.itemGrantTotals[key]) or 0, tonumber(count) or 0)
            end
            for key, count in pairs(per.chronus.itemGrantBaselines or {}) do
                if g.itemGrantBaselines[key] == nil then
                    g.itemGrantBaselines[key] = math.max(0, tonumber(count) or 0)
                end
            end
            g.totalAbsorbed = (g.totalAbsorbed or 0) + (per.chronus.totalAbsorbed or 0)
            per.chronus = nil
            sm.Save()
        end
    end

    return globalSave.chronus
end

local function ownsAnyBlacklisted(player)
    local bl = (ConchBlessing.chronus.data and ConchBlessing.chronus.data.blacklist) or {}
    for id, v in pairs(bl) do
        if v then
            local ok, has = pcall(function() return player:HasCollectible(id, true) end)
            if ok and has then return true end
        end
    end
    return false
end

local function findChronusOwner()
    local game = Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local player = game:GetPlayer(i)
        if player and player:HasCollectible(CHRONUS_ID) then
            return player
        end
    end
    return nil
end

local function clearChronusRuntime(player)
    if not player then return end

    local pdata = player:GetData()
    local runtimeLists = {
        "__chronusTwistedPairs",
        "__chronusIncubi",
        "__chronusSuccubi",
        "__chronusCensers",
        "__chronusStarsOfBethlehem",
        "__chronusAngelicPrisms",
        "__chronusBloodshotEyes",
    }
    for _, key in ipairs(runtimeLists) do
        for _, entity in ipairs(pdata[key] or {}) do
            if entity and entity:Exists() then
                entity:Remove()
            end
        end
        pdata[key] = nil
    end

    pdata.__chronusNextStarOfBethlehemSpawnFrame = nil
    pdata.__chronusNextStarOfBethlehemRetryFrame = nil
    pdata.__chronusNextScan = nil
    pdata.__chronusLastFireDir = nil
end

function ConchBlessing.chronus.registerAbsorbAction(familiarCollectibleId, fn)
    if type(familiarCollectibleId) ~= "number" then return end
    if type(fn) ~= "function" then return end
    ConchBlessing.chronus.data.absorbActions[familiarCollectibleId] = fn
end

function ConchBlessing.chronus.addToBlacklist(familiarCollectibleId)
    if type(familiarCollectibleId) ~= "number" then return end
    ConchBlessing.chronus.data.blacklist[familiarCollectibleId] = true
end

local function getFamiliarCollectibleIds()
    local cached = ConchBlessing.chronus._familiarCollectibleIds
    if cached then
        return cached
    end

    local ids = {}
    local cfg = Isaac.GetItemConfig()
    if not cfg then
        return ids
    end

    for id = 1, CollectibleType.NUM_COLLECTIBLES - 1 do
        local okItem, item = pcall(function() return cfg:GetCollectible(id) end)
        if okItem and item and item.Type == ItemType.ITEM_FAMILIAR then
            ids[#ids + 1] = id
        end
    end

    ConchBlessing.chronus._familiarCollectibleIds = ids
    return ids
end

local function countOwnedFamiliarCollectibles(player)
    local counts = {}
    for _, id in ipairs(getFamiliarCollectibleIds()) do
        local okOwned, owned = pcall(function() return player:GetCollectibleNum(id, true) end)
        if okOwned and owned and owned > 0 then counts[id] = owned end
    end
    return counts
end

function ConchBlessing.chronus._getAbsorbedCount(player, famId)
    local rs = getRunSave(player)
    if not rs then return 0 end
    -- Use string key to match how we save it
    local key = "fam_" .. tostring(famId)
    local sub = rs.absorbed[key]
    local count = (sub and sub.count) or 0
    return count
end

-- Buddy in a Box and Lil Delirium lend one random familiar's absorbed effect per
-- copy for the current floor (see _ensureFloorPicks). A pick only adds to effect
-- counts; it never grants a collectible or spawns a pinned familiar, so ledger and
-- pinned-entity code keep reading _getAbsorbedCount.
local function getFloorPickCount(rs, famId)
    local picks = rs and type(rs.floorPicks) == "table" and rs.floorPicks.ids or nil
    if type(picks) ~= "table" then return 0 end
    local count = 0
    for _, id in ipairs(picks) do
        if tonumber(id) == famId then count = count + 1 end
    end
    return count
end

-- Temporary familiars absorbed for the current room only: Box of Friends uses
-- (`double`, every effect count x2 per use), The Twins (`twins`, one absorbed
-- familiar's copies counted again) and room-scoped absorbed familiars (`counts`).
-- Runtime only; it ends with the room. The table is cleared in place, never replaced.
local roomTemp = { counts = {}, double = 0, twins = {} }
local refreshEffectCaches

-- Absorbed familiars that did not come from an owned collectible: Monster Manual
-- (`tempFloor`, this floor) and Soul of Lilith (`tempPermanent`), plus the room ones.
local function getTemporaryCount(rs, famId)
    local key = "fam_" .. tostring(famId)
    local count = tonumber(roomTemp.counts[key]) or 0
    local floor = rs and rs.tempFloor
    if type(floor) == "table" and floor.serial == (tonumber(rs.floorSerial) or 0) and type(floor.counts) == "table" then
        count = count + (tonumber(floor.counts[key]) or 0)
    end
    if rs and type(rs.tempPermanent) == "table" then
        count = count + (tonumber(rs.tempPermanent[key]) or 0)
    end
    return count
end

function ConchBlessing.chronus._getEffectCount(player, famId)
    local rs = getRunSave(player)
    if not rs then return 0 end
    local absorbed = ConchBlessing.chronus._getAbsorbedCount(player, famId)
    local count = absorbed + getFloorPickCount(rs, famId) + getTemporaryCount(rs, famId)
        + absorbed * (roomTemp.twins[famId] or 0)
    return count * (1 + roomTemp.double)
end

function ConchBlessing.chronus._getRoomTemporary()
    return roomTemp
end

-- Several familiars can convert into the same collectible (both Chubbies grant
-- Mars), so the player's pre-grant baseline belongs to the granted item, not to a
-- familiar: two per-familiar baselines would each count the other's copy as the
-- player's and charge one lost copy twice. Grants stay per familiar.
local function getGrantGroups()
    local cached = ConchBlessing.chronus._grantGroups
    if cached then return cached end
    local groups = {}
    for familiarId, conversionData in pairs(ConchBlessing.chronus.data.familiarToItemMap or {}) do
        local itemId = type(conversionData) == "table" and conversionData.itemId or conversionData
        if type(itemId) == "number" then
            groups[itemId] = groups[itemId] or {}
            table.insert(groups[itemId], familiarId)
        end
    end
    for _, familiarIds in pairs(groups) do
        table.sort(familiarIds)
    end
    ConchBlessing.chronus._grantGroups = groups
    return groups
end

local function familiarGrantCount(rs, familiarId)
    return math.max(0, math.floor(tonumber(rs.itemGrants["fam_" .. tostring(familiarId)]) or 0))
end

local function itemGrantCount(rs, itemId)
    local total = 0
    for _, familiarId in ipairs(getGrantGroups()[itemId] or {}) do
        total = total + familiarGrantCount(rs, familiarId)
    end
    return total
end

local function itemBaselineKey(itemId)
    return "item_" .. tostring(itemId)
end

-- Saves made before baselines moved to the item stored them under the familiar
-- key; every item had a single familiar then, so that value carries over as is.
local function getItemBaseline(rs, itemId)
    local key = itemBaselineKey(itemId)
    local value = rs.itemGrantBaselines[key]
    if value == nil then
        for _, familiarId in ipairs(getGrantGroups()[itemId] or {}) do
            local legacyKey = "fam_" .. tostring(familiarId)
            if rs.itemGrantBaselines[legacyKey] ~= nil then
                value = rs.itemGrantBaselines[legacyKey]
                rs.itemGrantBaselines[legacyKey] = nil
            end
        end
        if value ~= nil then
            rs.itemGrantBaselines[key] = value
        end
    end
    if value == nil then return nil end
    return math.max(0, math.floor(tonumber(value) or 0))
end

-- Mappings that used to grant a collectible and no longer do. The copies they
-- granted are taken back once, above the item baseline and the live grants of the
-- item's current familiars, and their ledger keys are dropped. Run this before
-- anything infers a baseline from the item count, or the retired copy would be
-- adopted as the player's own.
local RETIRED_GRANTS = {
    [CollectibleType.COLLECTIBLE_DADDY_LONGLEGS] = CollectibleType.COLLECTIBLE_HOLY_LIGHT,
}

local function migrateRetiredGrants(player, rs)
    if not (player and rs) then return false end
    rs.itemGrants = rs.itemGrants or {}
    rs.itemGrantTotals = rs.itemGrantTotals or {}
    rs.itemGrantBaselines = rs.itemGrantBaselines or {}
    local changed = false
    for familiarId, itemId in pairs(RETIRED_GRANTS) do
        local key = "fam_" .. tostring(familiarId)
        local legacyBaseline = rs.itemGrantBaselines[key]
        if rs.itemGrants[key] ~= nil or rs.itemGrantTotals[key] ~= nil or legacyBaseline ~= nil then
            local retired = math.max(0, math.floor(tonumber(rs.itemGrants[key]) or 0))
            local itemKey = itemBaselineKey(itemId)
            local liveGrants = itemGrantCount(rs, itemId)
            local current = player:GetCollectibleNum(itemId, true)
            local baseline = tonumber(rs.itemGrantBaselines[itemKey]) or tonumber(legacyBaseline)
            if baseline == nil then
                baseline = math.max(0, current - liveGrants - retired)
            end
            baseline = math.max(0, math.floor(baseline))
            local removable = math.max(0, current - baseline - liveGrants)
            for _ = 1, math.min(retired, removable) do
                player:RemoveCollectible(itemId)
            end
            rs.itemGrants[key] = nil
            rs.itemGrantTotals[key] = nil
            rs.itemGrantBaselines[key] = nil
            rs.itemGrantBaselines[itemKey] = liveGrants > 0 and baseline or nil
            changed = true
            dbg(string.format("Retired grant: familiar %d no longer grants item %d (removed %d)",
                familiarId, itemId, math.min(retired, removable)))
        end
    end
    if changed then
        ConchBlessing.SaveManager.Save()
    end
    return changed
end

function ConchBlessing.chronus._handleFamiliarToItemConversion(player, familiarId, total, delta)
    local rs = getRunSave(player)
    if not rs then return end
    
    -- Check if this familiar has an item conversion defined in the map
    local conversionData = ConchBlessing.chronus.data.familiarToItemMap[familiarId]
    if not conversionData or not conversionData.itemId then return end
    
    local maxGrants = conversionData.maxGrants or 0
    local key = "fam_" .. tostring(familiarId)
    rs.itemGrants = rs.itemGrants or {}
    rs.itemGrantTotals = rs.itemGrantTotals or {}
    rs.itemGrantBaselines = rs.itemGrantBaselines or {}
    local currentGrants = math.max(0, math.floor(tonumber(rs.itemGrants[key]) or 0))
    local storedTotalGrants = math.max(0, math.floor(tonumber(rs.itemGrantTotals[key]) or 0))
    local totalGrants = math.max(currentGrants, storedTotalGrants)
    local totalCreated = false
    if totalGrants > storedTotalGrants then
        rs.itemGrantTotals[key] = totalGrants
        totalCreated = true
    end
    local itemsToGrant = 0
    
    if maxGrants == 0 then
        -- Unlimited: grant for each absorbed
        itemsToGrant = delta
    else
        -- Limited: grant only up to maxGrants over this Chronus ownership.
        itemsToGrant = math.max(0, math.min(delta, maxGrants - totalGrants))
    end
    
    local baselineCreated = false
    local groupGrants = itemGrantCount(rs, conversionData.itemId)
    if (groupGrants > 0 or itemsToGrant > 0) and getItemBaseline(rs, conversionData.itemId) == nil then
        local currentItemCount = player:GetCollectibleNum(conversionData.itemId, true)
        rs.itemGrantBaselines[itemBaselineKey(conversionData.itemId)] = math.max(0, currentItemCount - groupGrants)
        baselineCreated = true
    end

    if itemsToGrant > 0 then
        for i = 1, itemsToGrant do
            player:AddCollectible(conversionData.itemId, 0, true)
        end
        -- Update only the Chronus-owned contribution; baseline copies stay player-owned.
        rs.itemGrants[key] = currentGrants + itemsToGrant
        rs.itemGrantTotals[key] = totalGrants + itemsToGrant
        ConchBlessing.SaveManager.Save()
        
        -- Update cache for item effects
        player:AddCacheFlags(CacheFlag.CACHE_ALL)
        player:EvaluateItems()
        
        dbg(string.format("[Chronus] Familiar ID=%d -> Granted %d item(s) (ID=%d) (total granted: %d, maxGrants: %d)", 
            tonumber(familiarId) or 0, itemsToGrant, tonumber(conversionData.itemId) or 0, rs.itemGrants[key], maxGrants))
    elseif delta > 0 then
        if baselineCreated or totalCreated then
            ConchBlessing.SaveManager.Save()
        end
        dbg(string.format("[Chronus] Familiar ID=%d absorbed but no items granted (max %d already granted)",
            tonumber(familiarId) or 0, maxGrants))
    end
end

function ConchBlessing.chronus._detectAndAbsorb(player)
    if not player then return false end

    local rs = getRunSave(player)
    if not rs then return false end

    local owned = countOwnedFamiliarCollectibles(player)
    local changed = false
    local bl = ConchBlessing.chronus.data.blacklist or {}
    local actions = ConchBlessing.chronus.data.absorbActions or {}

    -- Copies a GB Bug handed back stay with the player. The exemption follows the
    -- copies, so it shrinks as soon as the player owns fewer of them.
    rs.spared = rs.spared or {}
    local spared = rs.spared
    local sparedChanged = false
    for key, count in pairs(spared) do
        local famId = tonumber(tostring(key):match("^fam_(%d+)$"))
        local keep = famId and math.min(math.max(0, math.floor(tonumber(count) or 0)), owned[famId] or 0) or 0
        if keep ~= count then
            spared[key] = keep > 0 and keep or nil
            sparedChanged = true
        end
    end

    -- Store absorbed familiars info for later processing
    local absorbedFamiliars = {}

    for famId, ownedNow in pairs(owned) do
        local keep = tonumber(spared["fam_" .. tostring(famId)]) or 0
        if not bl[famId] and ownedNow > keep then
            local prev = ConchBlessing.chronus._getAbsorbedCount(player, famId)
            local removed = 0
            for _ = 1, ownedNow - keep do
                if player:HasCollectible(famId, true) then
                    player:RemoveCollectible(famId)
                    removed = removed + 1
                    ConchBlessing.chronus._queueTransferEffect(player, famId, false)
                end
            end
            if removed > 0 then
                -- Use string key to prevent SaveManager from converting to array index
                local key = "fam_" .. tostring(famId)
                rs.absorbed[key] = { count = prev + removed, id = famId }
                rs.totalAbsorbed = (rs.totalAbsorbed or 0) + removed
                changed = true
                
                dbg(string.format("[Chronus] Absorbed familiar: ID=%d (key=%s), prev=%d, removed=%d, total=%d", 
                    tonumber(famId) or 0, key, prev, removed, prev + removed))
                
                -- Store for later processing
                table.insert(absorbedFamiliars, {
                    famId = famId,
                    total = prev + removed,
                    delta = removed
                })
            end
        end
    end

    if changed then ConchBlessing.chronus._syncAbsorbedDamage(player) end
    
    -- Now run absorbActions and item conversions AFTER base damage
    for _, info in ipairs(absorbedFamiliars) do
        -- 1. Run custom absorb action if defined (e.g., positioning, special effects)
        local fn = actions[info.famId]
        if type(fn) == "function" then
            pcall(fn, player, info.total, info.delta)
        end
        
        -- 2. Auto-handle familiarToItemMap conversions for ALL familiars
        ConchBlessing.chronus._handleFamiliarToItemConversion(player, info.famId, info.total, info.delta)
    end

    -- 3. GB Bug: each absorbed copy hands back a random half of the others.
    for _, info in ipairs(absorbedFamiliars) do
        if info.famId == CollectibleType.COLLECTIBLE_GB_BUG then
            for _ = 1, info.delta do
                ConchBlessing.chronus._releaseRandomHalf(player)
            end
        end
    end

    if changed then
        ConchBlessing.chronus._ensureFloorPicks(player)
        ConchBlessing.chronus._topUpMongoMinisaacs(player)
    end
    if changed or sparedChanged then
        ConchBlessing.SaveManager.Save()
    end

    return changed
end

function ConchBlessing.chronus._finalizeAbsorb(player)
    if not player then return end
    ConchBlessing.chronus._syncAbsorbedDamage(player)
    local um = ConchBlessing.stats and ConchBlessing.stats.unifiedMultipliers
    if um and um.QueueCacheUpdate then
        um:QueueCacheUpdate(player, "Damage")
        um:QueueCacheUpdate(player, "Tears")
        um:QueueCacheUpdate(player, "Speed")
        um:QueueCacheUpdate(player, "Flying")
    else
        player:AddCacheFlags(CacheFlag.CACHE_DAMAGE | CacheFlag.CACHE_FIREDELAY | CacheFlag.CACHE_SPEED | CacheFlag.CACHE_FLYING)
        player:EvaluateItems()
    end
end

-- Track converted item removal for all familiar->item mappings
function ConchBlessing.chronus._trackConvertedItemRemoval(player)
    if not player then return end
    
    local rs = getRunSave(player)
    if not rs then return end
    
    rs.itemGrants = rs.itemGrants or {}
    rs.itemGrantTotals = rs.itemGrantTotals or {}
    rs.itemGrantBaselines = rs.itemGrantBaselines or {}
    local saveChanged = false

    for itemId, familiarIds in pairs(getGrantGroups()) do
        local grantedCount = itemGrantCount(rs, itemId)
        local baselineKey = itemBaselineKey(itemId)
        if grantedCount <= 0 then
            if getItemBaseline(rs, itemId) ~= nil then
                rs.itemGrantBaselines[baselineKey] = nil
                saveChanged = true
            end
            goto continue
        end
        for _, familiarId in ipairs(familiarIds) do
            local key = "fam_" .. tostring(familiarId)
            local familiarGrants = familiarGrantCount(rs, familiarId)
            if (tonumber(rs.itemGrantTotals[key]) or 0) < familiarGrants then
                rs.itemGrantTotals[key] = familiarGrants
                saveChanged = true
            end
        end

        local currentItemCount = player:GetCollectibleNum(itemId, true)
        local baseline = getItemBaseline(rs, itemId)
        if baseline == nil then
            baseline = math.max(0, currentItemCount - grantedCount)
            rs.itemGrantBaselines[baselineKey] = baseline
            saveChanged = true
        end

        local inferredBaseline = math.max(0, currentItemCount - grantedCount)
        if inferredBaseline > baseline then
            baseline = inferredBaseline
            rs.itemGrantBaselines[baselineKey] = baseline
            saveChanged = true
        end

        -- Counts at or below the baseline belong to the player, not Chronus.
        -- Any missing copies above it are consumed from the conversion grants.
        local presentConvertedItems = math.max(0, currentItemCount - baseline)
        local itemsRemoved = math.max(0, grantedCount - presentConvertedItems)

        if currentItemCount < baseline then
            rs.itemGrantBaselines[baselineKey] = currentItemCount
            saveChanged = true
        end

        if itemsRemoved > 0 then
            -- Charge each lost copy to exactly one familiar, highest id first, and
            -- give back one absorbed familiar per lost copy it had granted.
            local remaining = itemsRemoved
            for index = #familiarIds, 1, -1 do
                if remaining <= 0 then break end
                local familiarId = familiarIds[index]
                local key = "fam_" .. tostring(familiarId)
                local familiarGrants = familiarGrantCount(rs, familiarId)
                local taken = math.min(remaining, familiarGrants)
                if taken > 0 then
                    remaining = remaining - taken
                    rs.itemGrants[key] = familiarGrants - taken

                    local floor = rs.tempFloor
                    local floorTaken = math.min(taken,
                        tonumber(floor and floor.grants and floor.grants[key]) or 0,
                        tonumber(floor and floor.counts and floor.counts[key]) or 0)
                    if floorTaken > 0 then
                        floor.grants[key] = floor.grants[key] - floorTaken
                        floor.counts[key] = floor.counts[key] - floorTaken
                    end
                    local absorbedCount = ConchBlessing.chronus._getAbsorbedCount(player, familiarId)
                    local permanentTaken = math.min(absorbedCount, taken - floorTaken)
                    local newAbsorbedCount = absorbedCount - permanentTaken
                    if newAbsorbedCount > 0 then
                        rs.absorbed[key] = { count = newAbsorbedCount, id = familiarId }
                    else
                        rs.absorbed[key] = nil
                    end
                    rs.totalAbsorbed = math.max(0, (rs.totalAbsorbed or 0) - permanentTaken)

                    dbg(string.format("[Chronus] Detected %d item (ID:%d) removal, reduced familiar (ID:%d) count: %d -> %d",
                        taken, tonumber(itemId) or 0, tonumber(familiarId) or 0, absorbedCount, newAbsorbedCount))
                    if familiarId == CollectibleType.COLLECTIBLE_STAR_OF_BETHLEHEM then
                        ConchBlessing.chronus._ensureStarOfBethlehemStack(player, true)
                    end
                end
            end
            if itemGrantCount(rs, itemId) == 0 then
                rs.itemGrantBaselines[baselineKey] = nil
            end
            saveChanged = true
        end

        ::continue::
    end

    if saveChanged then
        ConchBlessing.chronus._syncAbsorbedDamage(player)
        clearChronusRuntime(player)
        refreshEffectCaches()
        ConchBlessing.SaveManager.Save()
    end
end

-- Pinned stand-ins follow the effect count, which a room or floor can raise
-- (Box of Friends, The Twins, Monster Manual) and later lower again.
local function trimPinned(list, target)
    while #list > target do
        local fam = table.remove(list)
        if fam and fam:Exists() then fam:Remove() end
    end
end

-- Twisted Pair: spawn both original Twisted Baby subtypes invisibly (2 per pair)
local function spawnInvisibleTwistedBaby(player, pairIndex, side)
    local subtype = side < 0 and 1 or 0
    dbg(string.format("Spawning Twisted Baby: pairIndex=%d, side=%d, subtype=%d", tonumber(pairIndex) or 0, tonumber(side) or 0, subtype))
    local ent = Isaac.Spawn(EntityType.ENTITY_FAMILIAR, FamiliarVariant.TWISTED_BABY, subtype, player.Position, Vector.Zero, player)
    local fam = ent and ent:ToFamiliar() or nil
    if not fam then
        dbg("Failed to spawn Twisted Baby entity")
        return nil
    end
    fam:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
    local spr = fam:GetSprite()
    local path = tostring(ConchBlessing.chronus.data.spriteNullPath or "gfx/ui/null.png")
    -- Replace all sprite layers to hide wings and body
    for i = 0, 10 do
        pcall(function() spr:ReplaceSpritesheet(i, path) end)
    end
    pcall(function() spr:LoadGraphics() end)
    fam.DepthOffset = tonumber(ConchBlessing.chronus.data.anchorDepthOffset) or 0
    local fd = fam:GetData()
    fd.__chronusTwistedPair = true
    fd.__chronusPairIndex = tonumber(pairIndex) or 1
    fd.__chronusSide = tonumber(side) or 1
    dbg(string.format("Twisted Baby spawned at position (%f, %f)", fam.Position.X, fam.Position.Y))
    return fam
end

function ConchBlessing.chronus._ensureTwistedPairs(player)
    if not player then return end
    
    local absorbedPairs = ConchBlessing.chronus._getEffectCount(player, CollectibleType.COLLECTIBLE_TWISTED_PAIR)
    local target = math.max(0, absorbedPairs * 2)
    
    local pdata = player:GetData()
    pdata.__chronusTwistedPairs = pdata.__chronusTwistedPairs or {}
    
    local kept = {}
    for _, f in ipairs(pdata.__chronusTwistedPairs) do
        if f and f:Exists() and f:ToFamiliar() then
            local fd = f:GetData()
            if fd and fd.__chronusTwistedPair then
                if f.Variant == FamiliarVariant.TWISTED_BABY then
                    table.insert(kept, f)
                else
                    f:Remove()
                end
            end
        end
    end
    pdata.__chronusTwistedPairs = kept
    trimPinned(pdata.__chronusTwistedPairs, target)

    while #pdata.__chronusTwistedPairs < target do
        local idx = math.floor(#pdata.__chronusTwistedPairs / 2) + 1
        local side = (#pdata.__chronusTwistedPairs % 2 == 0) and 1 or -1
        dbg(string.format("Spawning Twisted Baby %d/%d", #pdata.__chronusTwistedPairs + 1, target))
        local fam = spawnInvisibleTwistedBaby(player, idx, side)
        if not fam then
            dbg("Failed to spawn Twisted Baby, breaking loop")
            break 
        end
        table.insert(pdata.__chronusTwistedPairs, fam)
    end
end

function ConchBlessing.chronus._updateTwistedPairAnchors(player)
    local pdata = player and player:GetData() or nil
    local list = pdata and pdata.__chronusTwistedPairs or nil
    if not list or #list == 0 then return end
    local dir = player:GetShootingInput()
    if not (dir and dir:Length() > 0) then dir = player:GetAimDirection() end
    if not (dir and dir:Length() > 0) then dir = player:GetMovementInput() end
    if not (dir and dir:Length() > 0) then dir = Vector(1, 0) end
    dir = dir:Normalized()
    local perp = Vector(-dir.Y, dir.X)
    if perp:Length() > 0 then perp = perp:Normalized() end
    local baseOffset = tonumber(ConchBlessing.chronus.data.pairOffsetPixels) or 0
    local eyeY = tonumber(ConchBlessing.chronus.data.laserEyeYOffset) or 0
    local depth = tonumber(ConchBlessing.chronus.data.anchorDepthOffset) or 0
    for _, fam in ipairs(list) do
        if fam and fam:Exists() then
            local fd = fam:GetData()
            local side = (fd and fd.__chronusSide) or 1
            local pos = player.Position + perp * (side * baseOffset) + Vector(0, eyeY)
            fam.Position = pos
            fam.DepthOffset = depth
            fam.Velocity = Vector.Zero
            fam:AddEntityFlags(EntityFlag.FLAG_NO_QUERY)
        end
    end
end

-- Incubus: spawn invisible Incubus fixed to player position (1 per item)
local function spawnInvisibleIncubus(player)
    dbg("Spawning Incubus (fixed position)")
    local ent = Isaac.Spawn(EntityType.ENTITY_FAMILIAR, FamiliarVariant.INCUBUS, 0, player.Position, Vector.Zero, player)
    local fam = ent and ent:ToFamiliar() or nil
    if not fam then 
        dbg("Failed to spawn Incubus entity")
        return nil 
    end
    fam:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
    local spr = fam:GetSprite()
    local path = tostring(ConchBlessing.chronus.data.spriteNullPath or "gfx/ui/null.png")
    -- Replace all sprite layers to hide wings and body
    for i = 0, 10 do
        pcall(function() spr:ReplaceSpritesheet(i, path) end)
    end
    pcall(function() spr:LoadGraphics() end)
    fam.DepthOffset = tonumber(ConchBlessing.chronus.data.anchorDepthOffset) or 0
    fam:AddEntityFlags(EntityFlag.FLAG_NO_KNOCKBACK | EntityFlag.FLAG_NO_PHYSICS_KNOCKBACK)
    fam.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    fam.GridCollisionClass = GridCollisionClass.COLLISION_NONE
    local fd = fam:GetData()
    fd.__chronusIncubus = true
    dbg(string.format("Incubus spawned at position (%f, %f)", fam.Position.X, fam.Position.Y))
    return fam
end

function ConchBlessing.chronus._ensureIncubusStack(player)
    if not player then return end
    
    local absorbed = ConchBlessing.chronus._getEffectCount(player, CollectibleType.COLLECTIBLE_INCUBUS)
    local target = math.max(0, absorbed)
    
    local pdata = player:GetData()
    pdata.__chronusIncubi = pdata.__chronusIncubi or {}

    local kept = {}
    for _, f in ipairs(pdata.__chronusIncubi) do
        if f and f:Exists() and f:ToFamiliar() then
            local fd = f:GetData()
            if fd and fd.__chronusIncubus then table.insert(kept, f) end
        end
    end
    pdata.__chronusIncubi = kept
    trimPinned(pdata.__chronusIncubi, target)

    while #pdata.__chronusIncubi < target do
        dbg(string.format("Spawning Incubus %d/%d", #pdata.__chronusIncubi + 1, target))
        local fam = spawnInvisibleIncubus(player)
        if not fam then 
            dbg("Failed to spawn Incubus, breaking loop")
            break 
        end
        table.insert(pdata.__chronusIncubi, fam)
    end
end

function ConchBlessing.chronus._updateIncubusAnchors(player)
    local pdata = player and player:GetData() or nil
    local list = pdata and pdata.__chronusIncubi or nil
    if not list or #list == 0 then return end
    local depth = tonumber(ConchBlessing.chronus.data.anchorDepthOffset) or 0
    for _, fam in ipairs(list) do
        if fam and fam:Exists() then
            fam.Position = player.Position
            fam.DepthOffset = depth
            fam.Velocity = Vector.Zero
        end
    end
end

-- Aura familiars keep their aura visible and hide only the body. In the vanilla
-- anm2s spritesheet 0 is the body; Censer and Succubus draw their halo from sheet 1.
local AURA_FAMILIAR_BODY_SHEETS = { 0 }

local function hideFamiliarBody(fam, sheets)
    local spr = fam:GetSprite()
    local path = tostring(ConchBlessing.chronus.data.spriteNullPath or "gfx/ui/null.png")
    for _, i in ipairs(sheets) do
        pcall(function() spr:ReplaceSpritesheet(i, path) end)
    end
    pcall(function() spr:LoadGraphics() end)
end

-- The engine draws a familiar's floor shadow outside its sprite, so a nulled body
-- still leaves it behind. REPENTOGON can zero it; the base API can only hide the
-- whole entity, which would hide the aura as well, so without it the shadow stays.
local function hideFamiliarShadow(fam)
    if type(fam.SetShadowSize) == "function" then
        pcall(fam.SetShadowSize, fam, 0)
    end
end

local function spawnInvisibleSuccubus(player)
    local ent = Isaac.Spawn(EntityType.ENTITY_FAMILIAR, FamiliarVariant.SUCCUBUS, 0, player.Position, Vector.Zero, player)
    local fam = ent and ent:ToFamiliar() or nil
    if not fam then return nil end
    fam:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
    hideFamiliarBody(fam, AURA_FAMILIAR_BODY_SHEETS)
    hideFamiliarShadow(fam)
    fam.DepthOffset = tonumber(ConchBlessing.chronus.data.anchorDepthOffset) or 0
    fam:AddEntityFlags(EntityFlag.FLAG_NO_KNOCKBACK | EntityFlag.FLAG_NO_PHYSICS_KNOCKBACK)
    fam.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    fam.GridCollisionClass = GridCollisionClass.COLLISION_NONE
    local fd = fam:GetData()
    fd.__chronusSuccubus = true
    return fam
end

function ConchBlessing.chronus._ensureSuccubusStack(player)
    if not player then return end
    local absorbed = ConchBlessing.chronus._getEffectCount(player, CollectibleType.COLLECTIBLE_SUCCUBUS)
    local target = math.max(0, absorbed)
    local pdata = player:GetData()
    pdata.__chronusSuccubi = pdata.__chronusSuccubi or {}

    local kept = {}
    for _, f in ipairs(pdata.__chronusSuccubi) do
        if f and f:Exists() and f:ToFamiliar() then
            local fd = f:GetData()
            if fd and fd.__chronusSuccubus then table.insert(kept, f) end
        end
    end
    pdata.__chronusSuccubi = kept
    trimPinned(pdata.__chronusSuccubi, target)

    while #pdata.__chronusSuccubi < target do
        local fam = spawnInvisibleSuccubus(player)
        if not fam then break end
        table.insert(pdata.__chronusSuccubi, fam)
    end
end

-- Angelic Prism placement.
-- One prism pinned on the player, its hitbox radius scaled off the player's own Size.
-- Tested in game: the engine's prism split is a contact test that reads Entity.Size,
-- not the collisionRadius="10" constant from entities2.xml and not an
-- outside-to-inside transition. So a single centred prism does split, provided its
-- radius clears the ring the projectiles spawn on: sizeScale 4 (radius ~24) splits,
-- 3 (~18) does not. Do not trim sizeScale to the measured floor -- player.Size and the
-- spawn offset both vary per character and weapon.
-- The ring layout (count > 1 with a non-zero offset) still works and stays supported;
-- the `or` defaults below spell out its proven values so a missing config lands there.
local function isAngelicPrismDebugVisible()
    return ConchBlessing.chronus.data.angelicPrismDebugVisible == true
end

local function getAngelicPrismCount()
    local count = math.floor(tonumber(ConchBlessing.chronus.data.angelicPrismCount) or 16)
    if count < 1 then count = 1 end
    return count
end

local function getAngelicPrismBaseDir(player)
    local pdata = player:GetData()
    local dir = player:GetAimDirection()
    if dir and dir:Length() > 0 then
        pdata.__chronusLastFireDir = dir:Normalized()
    end
    local baseDir = pdata.__chronusLastFireDir
    if baseDir and baseDir:Length() > 0 then
        return baseDir
    end
    return Vector(1, 0)
end

local function applyAngelicPrismAnchor(fam, player, baseDir)
    local fd = fam:GetData()
    local slot = (fd and fd.__chronusPrismDirection) or 0
    local angle = slot * (2 * math.pi) / getAngelicPrismCount()
    local slotDir = Vector(
        baseDir.X * math.cos(angle) - baseDir.Y * math.sin(angle),
        baseDir.X * math.sin(angle) + baseDir.Y * math.cos(angle)
    )
    local ringRadius = tonumber(ConchBlessing.chronus.data.angelicPrismOffset) or 22
    fam.Position = player.Position + (slotDir * ringRadius)
    fam.Velocity = Vector.Zero
    fam.DepthOffset = tonumber(ConchBlessing.chronus.data.anchorDepthOffset) or 0
    fam.Visible = isAngelicPrismDebugVisible()
    local sizeScale = tonumber(ConchBlessing.chronus.data.angelicPrismSizeScale) or 0
    if sizeScale > 0 then
        fam.Size = player.Size * sizeScale
        if isAngelicPrismDebugVisible() then
            -- Size is a hitbox radius and never touches rendering. While debugging,
            -- stretch the sprite to match it so the catch area is what you actually see.
            -- 10 is the vanilla collisionRadius for this familiar in entities2.xml.
            fam.SpriteScale = Vector.One * (fam.Size / 10)
        end
        if fd and not fd.__chronusPrismSizeLogged then
            fd.__chronusPrismSizeLogged = true
            dbg(string.format("Angelic Prism hitbox: player %.2f x%.2f -> %.2f (engine default 10)",
                player.Size, sizeScale, fam.Size))
        end
    end
end

-- Angelic Prism: spawn invisible Angelic Prism positioned ahead in firing direction (1 per item)
local function spawnInvisibleAngelicPrism(player)
    dbg("Spawning Angelic Prism")
    local ent = Isaac.Spawn(EntityType.ENTITY_FAMILIAR, FamiliarVariant.ANGELIC_PRISM, 0, player.Position, Vector.Zero, player)
    local fam = ent and ent:ToFamiliar() or nil
    if not fam then
        dbg("Failed to spawn Angelic Prism entity")
        return nil
    end
    fam:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
    if not isAngelicPrismDebugVisible() then
        local spr = fam:GetSprite()
        local path = tostring(ConchBlessing.chronus.data.spriteNullPath or "gfx/ui/null.png")
        -- Replace all sprite layers
        for i = 0, 10 do
            pcall(function() spr:ReplaceSpritesheet(i, path) end)
        end
        pcall(function() spr:LoadGraphics() end)
    end
    fam.DepthOffset = tonumber(ConchBlessing.chronus.data.anchorDepthOffset) or 0
    fam:AddEntityFlags(EntityFlag.FLAG_NO_KNOCKBACK | EntityFlag.FLAG_NO_PHYSICS_KNOCKBACK)
    fam.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    fam.GridCollisionClass = GridCollisionClass.COLLISION_NONE
    -- Hide the entity itself, not only its sprite: a nulled spritesheet still
    -- leaves the familiar's engine-drawn floor shadow behind.
    fam.Visible = isAngelicPrismDebugVisible()
    local fd = fam:GetData()
    fd.__chronusAngelicPrism = true
    dbg(string.format("Angelic Prism spawned at position (%f, %f)", fam.Position.X, fam.Position.Y))
    return fam
end

function ConchBlessing.chronus._ensureAngelicPrismStack(player)
    if not player then return end
    
    local absorbed = ConchBlessing.chronus._getEffectCount(player, CollectibleType.COLLECTIBLE_ANGELIC_PRISM)
    -- One prism per ring slot once any Angelic Prism is absorbed
    local target = (absorbed > 0) and getAngelicPrismCount() or 0
    
    local pdata = player:GetData()
    pdata.__chronusAngelicPrisms = pdata.__chronusAngelicPrisms or {}
    
    -- Remove original Angelic Prism familiars in the room (not managed by Chronus)
    if absorbed > 0 then
        local room = Game():GetRoom()
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            local fam = entity:ToFamiliar()
            if fam and fam.Variant == FamiliarVariant.ANGELIC_PRISM then
                local fd = fam:GetData()
                -- Remove if NOT managed by Chronus
                if not (fd and fd.__chronusAngelicPrism) then
                    fam:Remove()
                end
            end
        end
    end

    -- Keep existing prisms
    local kept = {}
    for _, f in ipairs(pdata.__chronusAngelicPrisms) do
        if f and f:Exists() and f:ToFamiliar() then
            local fd = f:GetData()
            if fd and fd.__chronusAngelicPrism then 
                table.insert(kept, f)
            end
        end
    end
    pdata.__chronusAngelicPrisms = kept
    
    -- Remove excess prisms if we have more than target
    while #pdata.__chronusAngelicPrisms > target do
        local fam = table.remove(pdata.__chronusAngelicPrisms)
        if fam and fam:Exists() then
            fam:Remove()
        end
    end

    -- Fill the lowest free ring slots. Deriving the slot from the list length
    -- instead would hand a new prism a slot a surviving prism already owns as soon
    -- as one dies mid-list, leaving that direction uncovered.
    local usedSlots = {}
    for _, f in ipairs(pdata.__chronusAngelicPrisms) do
        local fd = f:GetData()
        if fd and fd.__chronusPrismDirection then
            usedSlots[fd.__chronusPrismDirection] = true
        end
    end
    local nextSlot = 0
    while #pdata.__chronusAngelicPrisms < target do
        while nextSlot < target and usedSlots[nextSlot] do
            nextSlot = nextSlot + 1
        end
        if nextSlot >= target then break end
        local fam = spawnInvisibleAngelicPrism(player)
        if not fam then
            break
        end
        fam:GetData().__chronusPrismDirection = nextSlot
        usedSlots[nextSlot] = true
        table.insert(pdata.__chronusAngelicPrisms, fam)
    end
end

function ConchBlessing.chronus._updateAngelicPrismAnchors(player)
    if not player then return end
    local pdata = player:GetData()
    if not pdata then return end
    local list = pdata.__chronusAngelicPrisms
    if not list or #list == 0 then return end

    local baseDir = getAngelicPrismBaseDir(player)
    for _, fam in ipairs(list) do
        if fam and fam:Exists() then
            applyAngelicPrismAnchor(fam, player, baseDir)
        end
    end
end

function ConchBlessing.chronus._ensureSeraphimEffects(player)
    if not player then return end
    local absorbed = ConchBlessing.chronus._getAbsorbedCount(player, CollectibleType.COLLECTIBLE_SERAPHIM)
    if absorbed > 0 then
        -- Flying effect is granted via onEvaluateCache (CACHE_FLYING)
        -- No costume needed - keep appearance clean like other absorbed familiars
        dbg(string.format("[Chronus] Seraphim absorbed: %d (flying granted without costume)", absorbed))
    end
end

function ConchBlessing.chronus._updateSuccubusAnchors(player)
    local pdata = player and player:GetData() or nil
    local list = pdata and pdata.__chronusSuccubi or nil
    if not list or #list == 0 then return end
    local depth = tonumber(ConchBlessing.chronus.data.anchorDepthOffset) or 0
    for _, fam in ipairs(list) do
        if fam and fam:Exists() then
            fam.Position = player.Position
            fam.DepthOffset = depth
            fam.Velocity = Vector.Zero
        end
    end
end

--- Censer: spawn invisible Censer fixed to player position
local function spawnInvisibleCenser(player)
    local ent = Isaac.Spawn(EntityType.ENTITY_FAMILIAR, FamiliarVariant.CENSER, 0, player.Position, Vector.Zero, player)
    local fam = ent and ent:ToFamiliar() or nil
    if not fam then return nil end
    fam:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
    hideFamiliarBody(fam, AURA_FAMILIAR_BODY_SHEETS)
    hideFamiliarShadow(fam)
    fam.DepthOffset = tonumber(ConchBlessing.chronus.data.anchorDepthOffset) or 0
    fam:AddEntityFlags(EntityFlag.FLAG_NO_KNOCKBACK | EntityFlag.FLAG_NO_PHYSICS_KNOCKBACK)
    fam.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    fam.GridCollisionClass = GridCollisionClass.COLLISION_NONE
    local fd = fam:GetData()
    fd.__chronusCenser = true
    return fam
end

function ConchBlessing.chronus._ensureCenserStack(player)
    if not player then return end
    local absorbed = ConchBlessing.chronus._getEffectCount(player, CollectibleType.COLLECTIBLE_CENSER)
    local target = math.max(0, absorbed)
    local pdata = player:GetData()
    pdata.__chronusCensers = pdata.__chronusCensers or {}

    local kept = {}
    for _, f in ipairs(pdata.__chronusCensers) do
        if f and f:Exists() and f:ToFamiliar() then
            local fd = f:GetData()
            if fd and fd.__chronusCenser then table.insert(kept, f) end
        end
    end
    pdata.__chronusCensers = kept
    trimPinned(pdata.__chronusCensers, target)

    while #pdata.__chronusCensers < target do
        local fam = spawnInvisibleCenser(player)
        if not fam then break end
        table.insert(pdata.__chronusCensers, fam)
    end
    dbg(string.format("[Chronus] Ensured %d Censers (target: %d)", #pdata.__chronusCensers, target))
end

function ConchBlessing.chronus._updateCenserAnchors(player)
    local pdata = player and player:GetData() or nil
    local list = pdata and pdata.__chronusCensers or nil
    if not list or #list == 0 then return end
    local depth = tonumber(ConchBlessing.chronus.data.anchorDepthOffset) or 0
    for _, fam in ipairs(list) do
        if fam and fam:Exists() then
            fam.Position = player.Position
            fam.DepthOffset = depth
            fam.Velocity = Vector.Zero
        end
    end
end

--- Star of Bethlehem: spawn invisible Star of Bethlehem fixed to player position
local function spawnInvisibleStarOfBethlehem(player)
    local ent = Isaac.Spawn(EntityType.ENTITY_FAMILIAR, FamiliarVariant.STAR_OF_BETHLEHEM, 0, player.Position, Vector.Zero, player)
    local fam = ent and ent:ToFamiliar() or nil
    if not fam then return nil end
    fam:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
    hideFamiliarBody(fam, AURA_FAMILIAR_BODY_SHEETS)
    hideFamiliarShadow(fam)
    fam.DepthOffset = tonumber(ConchBlessing.chronus.data.anchorDepthOffset) or 0
    fam:AddEntityFlags(EntityFlag.FLAG_NO_KNOCKBACK | EntityFlag.FLAG_NO_PHYSICS_KNOCKBACK)
    fam.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    fam.GridCollisionClass = GridCollisionClass.COLLISION_NONE
    local fd = fam:GetData()
    fd.__chronusStarOfBethlehem = true
    return fam
end

function ConchBlessing.chronus._ensureStarOfBethlehemStack(player, forceRespawn)
    if not player then return end
    local absorbed = ConchBlessing.chronus._getEffectCount(player, CollectibleType.COLLECTIBLE_STAR_OF_BETHLEHEM)
    local target = math.max(0, absorbed)
    local pdata = player:GetData()
    pdata.__chronusStarsOfBethlehem = pdata.__chronusStarsOfBethlehem or {}

    local kept = {}
    for _, f in ipairs(pdata.__chronusStarsOfBethlehem) do
        if f and f:Exists() and f:ToFamiliar() then
            local fd = f:GetData()
            if fd and fd.__chronusStarOfBethlehem then table.insert(kept, f) end
        end
    end
    pdata.__chronusStarsOfBethlehem = kept

    if target <= 0 then
        for _, fam in ipairs(pdata.__chronusStarsOfBethlehem) do
            if fam and fam:Exists() then fam:Remove() end
        end
        pdata.__chronusStarsOfBethlehem = {}
        pdata.__chronusNextStarOfBethlehemSpawnFrame = nil
        pdata.__chronusNextStarOfBethlehemRetryFrame = nil
        return
    end

    local frame = Game():GetFrameCount()
    local interval = math.max(1, math.floor(tonumber(ConchBlessing.chronus.data.starOfBethlehemSpawnIntervalFrames) or 300))
    local nextSpawnFrame = tonumber(pdata.__chronusNextStarOfBethlehemSpawnFrame)
    -- Missing entities are replenished on every update, without deleting healthy
    -- peers or waiting for a retry timer. An existing star can still lose its
    -- native aura without a removal event, so retain the bounded refresh fallback.
    local refresh = forceRespawn == true or (nextSpawnFrame ~= nil and frame >= nextSpawnFrame)
    if refresh then
        for _, fam in ipairs(pdata.__chronusStarsOfBethlehem) do
            if fam and fam:Exists() then fam:Remove() end
        end
        pdata.__chronusStarsOfBethlehem = {}
    end
    trimPinned(pdata.__chronusStarsOfBethlehem, target)
    local previousCount = #pdata.__chronusStarsOfBethlehem

    while #pdata.__chronusStarsOfBethlehem < target do
        local fam = spawnInvisibleStarOfBethlehem(player)
        if not fam then break end
        table.insert(pdata.__chronusStarsOfBethlehem, fam)
    end
    if refresh or nextSpawnFrame == nil then
        pdata.__chronusNextStarOfBethlehemSpawnFrame = frame + interval
    end
    if refresh or #pdata.__chronusStarsOfBethlehem ~= previousCount then
        dbg(string.format(
            "[Chronus] Ensured %d Stars of Bethlehem (target: %d, next: %d)",
            #pdata.__chronusStarsOfBethlehem, target, pdata.__chronusNextStarOfBethlehemSpawnFrame))
    end
end

function ConchBlessing.chronus._updateStarOfBethlehemAnchors(player)
    local pdata = player and player:GetData() or nil
    local list = pdata and pdata.__chronusStarsOfBethlehem or nil
    if not list or #list == 0 then return end
    local depth = tonumber(ConchBlessing.chronus.data.anchorDepthOffset) or 0
    for _, fam in ipairs(list) do
        if fam and fam:Exists() then
            fam.Position = player.Position
            fam.DepthOffset = depth
            fam.Velocity = Vector.Zero
        end
    end
end

--- Bloodshot Eye: pinned on the player. Its tears and lasers are separate
--- entities, so hiding the familiar entity (body and floor shadow) keeps them visible.
local function spawnInvisibleBloodshotEye(player)
    local ent = Isaac.Spawn(EntityType.ENTITY_FAMILIAR, FamiliarVariant.BLOODSHOT_EYE, 0, player.Position, Vector.Zero, player)
    local fam = ent and ent:ToFamiliar() or nil
    if not fam then return nil end
    fam:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
    fam.Visible = false
    fam.DepthOffset = tonumber(ConchBlessing.chronus.data.anchorDepthOffset) or 0
    fam:AddEntityFlags(EntityFlag.FLAG_NO_KNOCKBACK | EntityFlag.FLAG_NO_PHYSICS_KNOCKBACK)
    fam.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    fam.GridCollisionClass = GridCollisionClass.COLLISION_NONE
    fam:GetData().__chronusBloodshotEye = true
    return fam
end

function ConchBlessing.chronus._ensureBloodshotEyeStack(player)
    if not player then return end
    local target = math.max(0, ConchBlessing.chronus._getEffectCount(player, CollectibleType.COLLECTIBLE_BLOODSHOT_EYE))
    local pdata = player:GetData()
    pdata.__chronusBloodshotEyes = pdata.__chronusBloodshotEyes or {}

    local kept = {}
    for _, f in ipairs(pdata.__chronusBloodshotEyes) do
        if f and f:Exists() and f:ToFamiliar() then
            local fd = f:GetData()
            if fd and fd.__chronusBloodshotEye then table.insert(kept, f) end
        end
    end
    pdata.__chronusBloodshotEyes = kept
    trimPinned(pdata.__chronusBloodshotEyes, target)

    while #pdata.__chronusBloodshotEyes < target do
        local fam = spawnInvisibleBloodshotEye(player)
        if not fam then break end
        table.insert(pdata.__chronusBloodshotEyes, fam)
    end
end

function ConchBlessing.chronus._updateBloodshotEyeAnchors(player)
    local pdata = player and player:GetData() or nil
    local list = pdata and pdata.__chronusBloodshotEyes or nil
    if not list or #list == 0 then return end
    local depth = tonumber(ConchBlessing.chronus.data.anchorDepthOffset) or 0
    for _, fam in ipairs(list) do
        if fam and fam:Exists() then
            fam.Position = player.Position
            fam.DepthOffset = depth
            fam.Velocity = Vector.Zero
            fam.Visible = false
        end
    end
end

ConchBlessing.chronus.onPickup = function(_, player, collectibleType)
    if collectibleType ~= CHRONUS_ID then return end
    player:GetData().__chronusHadCollectible = true
    dbg("Picked up - initial sweep")
    local changed = ConchBlessing.chronus._detectAndAbsorb(player)
    if changed then ConchBlessing.chronus._finalizeAbsorb(player) end
end

ConchBlessing.chronus.onPlayerUpdate = function(_, player)
    if not player then return end

    local frame = Game():GetFrameCount()
    local pdata = player:GetData()
    ConchBlessing.chronus._processPendingTempScans(player)
    if player:HasCollectible(CHRONUS_ID) then
        pdata.__chronusHadCollectible = true
        migrateRetiredGrants(player, getRunSave(player))
        pdata.__chronusNextScan = pdata.__chronusNextScan or 0
        local interval = tonumber(ConchBlessing.chronus.data.scanIntervalFrames) or 15
        if frame >= pdata.__chronusNextScan then
            pdata.__chronusNextScan = frame + interval
            local ok, changed = pcall(function() return ConchBlessing.chronus._detectAndAbsorb(player) end)
            if ok and changed then ConchBlessing.chronus._finalizeAbsorb(player) end
        end

        -- Track converted item removal (all familiar->item conversions)
        ConchBlessing.chronus._trackConvertedItemRemoval(player)
        ConchBlessing.chronus._syncAbsorbedDamage(player)

        -- Auto-execute absorbActions for all absorbed familiars
        local absorbActions = ConchBlessing.chronus.data.absorbActions
        if absorbActions then
            for familiarId, action in pairs(absorbActions) do
                local count = ConchBlessing.chronus._getEffectCount(player, familiarId)
                if count > 0 and type(action) == "function" then
                    action(player, count, 0)
                end
            end
        end
    elseif pdata.__chronusHadCollectible then
        pdata.__chronusHadCollectible = false
        clearChronusRuntime(player)
        local um = ConchBlessing.stats and ConchBlessing.stats.unifiedMultipliers
        if um and um.RemoveItemAddition then
            um:RemoveItemAddition(player, CHRONUS_ID, "Damage")
            um:QueueCacheUpdate(player, "Damage")
        end
        player:AddCacheFlags(CacheFlag.CACHE_DAMAGE | CacheFlag.CACHE_FLYING | CacheFlag.CACHE_FIREDELAY | CacheFlag.CACHE_SPEED)
        player:EvaluateItems()
        if not findChronusOwner() then
            ConchBlessing.chronus._revertAll(player)
        end
    end
end

-- Room entry is where the pinned Star of Bethlehem aura kept dropping out, so a
-- fresh star replaces it as soon as the room loads instead of waiting for the
-- in-room refresh timer; that timer restarts from this entry.
ConchBlessing.chronus.onNewRoom = function()
    ConchBlessing.chronus._clearRoomVisuals()
    ConchBlessing.chronus._resetRoomTemporary()
    local game = Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local player = game:GetPlayer(i)
        if player and player:HasCollectible(CHRONUS_ID) then
            if ConchBlessing.chronus._getEffectCount(player, CollectibleType.COLLECTIBLE_STAR_OF_BETHLEHEM) > 0 then
                ConchBlessing.chronus._ensureStarOfBethlehemStack(player, true)
                ConchBlessing.chronus._updateStarOfBethlehemAnchors(player)
            end
            ConchBlessing.chronus._topUpMongoMinisaacs(player)
            ConchBlessing.chronus._scanTwins(player)
        end
    end
    ConchBlessing.chronus._payLostSoulReward()
end

ConchBlessing.chronus.onEvaluateCache = function(_, player, cacheFlag)
    if not player then return end
    if not player:HasCollectible(CHRONUS_ID) then return end
    
    -- Grant flying ability when Seraphim is absorbed
    if cacheFlag == CacheFlag.CACHE_FLYING then
        local seraphimCount = ConchBlessing.chronus._getEffectCount(player, CollectibleType.COLLECTIBLE_SERAPHIM)
        if seraphimCount > 0 then
            player.CanFly = true
            dbg(string.format("[Chronus] Granted flying ability (Seraphim absorbed: %d)", seraphimCount))
        end
    end
    
    local stats = ConchBlessing.chronus.STATS
    local effectCount = ConchBlessing.chronus._getEffectCount

    -- Per-familiar damage, including temporary copies, is owned by the unified
    -- ledger. Only Guillotine's separate vanilla bonus is applied here.
    if cacheFlag == CacheFlag.CACHE_DAMAGE then
        local bonus = stats.GUILLOTINE_DAMAGE * effectCount(player, CollectibleType.COLLECTIBLE_GUILLOTINE)
        if bonus > 0 and ConchBlessing.stats and ConchBlessing.stats.damage and ConchBlessing.stats.damage.applyAddition then
            ConchBlessing.stats.damage.applyAddition(player, bonus, nil)
        end
    end

    -- Brother Bobby, Guillotine, Milk! (after its first hit on this floor) and
    -- Paschal Candle (accumulated per room clear) all add tears.
    if cacheFlag == CacheFlag.CACHE_FIREDELAY then
        local rs = getRunSave(player)
        local bonusSPS = stats.BROTHER_BOBBY_TEARS * effectCount(player, CollectibleType.COLLECTIBLE_BROTHER_BOBBY)
            + stats.GUILLOTINE_TEARS * effectCount(player, CollectibleType.COLLECTIBLE_GUILLOTINE)
        if rs and rs.milkSerial ~= nil and rs.milkSerial == (tonumber(rs.floorSerial) or 0) then
            bonusSPS = bonusSPS + stats.MILK_TEARS * effectCount(player, CollectibleType.COLLECTIBLE_MILK)
        end
        if rs then
            bonusSPS = bonusSPS + (tonumber(rs.paschalHundredths) or 0) / 100
        end
        if bonusSPS > 0 and ConchBlessing.stats and ConchBlessing.stats.tears and ConchBlessing.stats.tears.applyAddition then
            ConchBlessing.stats.tears.applyAddition(player, bonusSPS, nil)
            dbg(string.format("[Chronus] Absorbed fire rate bonus: +%.2f SPS", bonusSPS))
        end
    end

    -- Increase speed when Guardian Angel is absorbed
    if cacheFlag == CacheFlag.CACHE_SPEED then
        local guardianAngelCount = effectCount(player, CollectibleType.COLLECTIBLE_GUARDIAN_ANGEL)
        if guardianAngelCount > 0 then
            local bonusSpeed = stats.GUARDIAN_ANGEL_SPEED * guardianAngelCount
            if ConchBlessing.stats and ConchBlessing.stats.speed and ConchBlessing.stats.speed.applyAddition then
                ConchBlessing.stats.speed.applyAddition(player, bonusSpeed, nil)
            end
            dbg(string.format("[Chronus] Guardian Angel speed bonus: +%.2f (count: %d)", bonusSpeed, guardianAngelCount))
        end
    end
end

ConchBlessing.chronus.onGameStarted = function(_)
    -- Floor-scoped run state (new-level rewards, floor picks) waits for this: the
    -- first MC_POST_NEW_LEVEL of a run fires before it, while SaveManager can still
    -- expose the previous run's table.
    ConchBlessing.chronus._runReady = true
    local player = findChronusOwner()
    if not player then
        local firstPlayer = Isaac.GetPlayer(0)
        if firstPlayer then
            ConchBlessing.chronus._revertAll(firstPlayer)
        end
        return
    end
    player:GetData().__chronusHadCollectible = true
    local rs = getRunSave(player)
    if rs then
        dbg(string.format("Loaded: total=%d, kinds=%d", tonumber(rs.totalAbsorbed or 0), rs.absorbed and (function(t) local c=0 for _ in pairs(t) do c=c+1 end return c end)(rs.absorbed) or 0))
        
        if rs.absorbed then
            for key, data in pairs(rs.absorbed) do
                local famId = data.id or tonumber(key:match("fam_(%d+)")) or 0
                dbg(string.format("[Chronus] Loaded absorbed familiar: key=%s, ID=%d, count=%d", 
                    tostring(key), tonumber(famId) or 0, data.count or 0))
            end
        end
        
        ConchBlessing.chronus._syncAbsorbedDamage(player)
        
        if rs.absorbedBonusDamage or rs.absorbActionBonusDamage then
            rs.absorbedBonusDamage = nil
            rs.absorbActionBonusDamage = nil
            ConchBlessing.SaveManager.Save()
            dbg("[Chronus] Cleaned up legacy damage bonus fields from save data")
        end
        
        local seraphimCount = ConchBlessing.chronus._getAbsorbedCount(player, CollectibleType.COLLECTIBLE_SERAPHIM)
        dbg(string.format("Found %d absorbed Seraphim on game start", tonumber(seraphimCount) or 0))
        
        migrateRetiredGrants(player, rs)

        -- Reconcile conversion grants without re-adding collectibles already persisted
        -- by the run. This also grants items introduced by a newly added mapping.
        local familiarToItemMap = ConchBlessing.chronus.data.familiarToItemMap or {}
        rs.itemGrants = rs.itemGrants or {}
        rs.itemGrantTotals = rs.itemGrantTotals or {}
        rs.itemGrantBaselines = rs.itemGrantBaselines or {}
        local grantsChanged = false

        for familiarId, conversionData in pairs(familiarToItemMap) do
            if type(conversionData) ~= "table" then
                conversionData = { itemId = conversionData, maxGrants = 0 }
            end
            
            local itemId = conversionData.itemId
            if not itemId then goto continue_restore end  -- Skip if no item
            
            local familiarCount = ConchBlessing.chronus._getAbsorbedCount(player, familiarId)
            local maxGrants = conversionData.maxGrants or 0
            local desiredGrants = maxGrants == 0
                and familiarCount
                or math.min(familiarCount, maxGrants)
            local key = "fam_" .. tostring(familiarId)
            local trackedGrants = math.max(0, math.floor(tonumber(rs.itemGrants[key]) or 0))
            local storedTotalGrants = math.max(0, math.floor(tonumber(rs.itemGrantTotals[key]) or 0))
            local totalGrants = math.max(trackedGrants, storedTotalGrants)
            if totalGrants > storedTotalGrants then
                rs.itemGrantTotals[key] = totalGrants
                grantsChanged = true
            end

            local missingGrants
            if maxGrants == 0 then
                missingGrants = math.max(0, desiredGrants - trackedGrants)
            else
                missingGrants = math.max(0, desiredGrants - totalGrants)
            end

            if (trackedGrants > 0 or missingGrants > 0) and getItemBaseline(rs, itemId) == nil then
                local currentItemCount = player:GetCollectibleNum(itemId, true)
                rs.itemGrantBaselines[itemBaselineKey(itemId)] = math.max(0, currentItemCount - itemGrantCount(rs, itemId))
                grantsChanged = true
            end

            if missingGrants > 0 then
                for _ = 1, missingGrants do
                    player:AddCollectible(itemId, 0, true)
                end
                rs.itemGrants[key] = trackedGrants + missingGrants
                rs.itemGrantTotals[key] = totalGrants + missingGrants
                grantsChanged = true
                dbg(string.format("Reconciled %d missing item grant(s) (ID:%d) from %d absorbed familiar (ID:%d, maxGrants=%d)",
                    missingGrants, tonumber(itemId) or 0, familiarCount, tonumber(familiarId) or 0, maxGrants))
            end

            ::continue_restore::
        end

        -- A baseline only means something while some familiar still has a grant of that item.
        for itemId in pairs(getGrantGroups()) do
            if itemGrantCount(rs, itemId) == 0 and getItemBaseline(rs, itemId) ~= nil then
                rs.itemGrantBaselines[itemBaselineKey(itemId)] = nil
                grantsChanged = true
            end
        end

        if grantsChanged then
            ConchBlessing.SaveManager.Save()
        end

        ConchBlessing.chronus._ensureFloorPicks(player)

        player:AddCacheFlags(CacheFlag.CACHE_DAMAGE | CacheFlag.CACHE_FLYING | CacheFlag.CACHE_TEARFLAG | CacheFlag.CACHE_FIREDELAY | CacheFlag.CACHE_SPEED)
        player:EvaluateItems()
    end
end

-- Absorbed-effect state that only means something while Chronus is held.
local EFFECT_STATE_KEYS = { "spared", "floorPicks", "paschalHundredths", "milkSerial", "clearCounters", "lostSoulRewardPending",
    "tempFloor", "tempPermanent", "prettyFlies" }

local function clearEffectState(rs)
    local cleared = false
    for _, key in ipairs(EFFECT_STATE_KEYS) do
        if rs[key] ~= nil then
            rs[key] = nil
            cleared = true
        end
    end
    return cleared
end

function ConchBlessing.chronus._revertAll(player)
    clearChronusRuntime(player)
    local rs = getRunSave(player)
    if not rs or not rs.absorbed then return false end
    migrateRetiredGrants(player, rs)
    ConchBlessing.chronus._restoreNonItemFamiliars(player, rs)
    local effectStateCleared = clearEffectState(rs)
    local hadAny = next(rs.itemGrants or {}) ~= nil
    local familiarToItemMap = ConchBlessing.chronus.data.familiarToItemMap or {}
    
    for key, entry in pairs(rs.absorbed) do
        local count = (entry and entry.count) or 0
        if count > 0 then
            hadAny = true
            -- Extract actual ID from entry or key
            local famId = entry.id or tonumber(key:match("fam_(%d+)"))
            
            if famId then
                for _ = 1, count do
                    player:AddCollectible(famId, 0, false)
                    ConchBlessing.chronus._queueTransferEffect(player, famId, true)
                end
                dbg(string.format("[Chronus] Restored familiar: key=%s, ID=%d, count=%d", tostring(key), tonumber(famId) or 0, count))
            end
        end
    end
    if hadAny then
        -- Remove all damage additions and multipliers using unified system
        local um = ConchBlessing.stats and ConchBlessing.stats.unifiedMultipliers
        if um and um.RemoveItemAddition then
            -- RemoveItemAddition removes BOTH flat additions AND additive multipliers for the item
            um:RemoveItemAddition(player, CHRONUS_ID, "Damage")
            um:QueueCacheUpdate(player, "Damage")
        else
            player:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
            player:EvaluateItems()
        end
        
        -- Remove only the converted-item contribution; all familiars were restored above.
        rs.itemGrants = rs.itemGrants or {}
        rs.itemGrantBaselines = rs.itemGrantBaselines or {}
        
        for itemId in pairs(getGrantGroups()) do
            local grantedCount = itemGrantCount(rs, itemId)
            if grantedCount > 0 then
                local currentItemCount = player:GetCollectibleNum(itemId, true)
                local baseline = getItemBaseline(rs, itemId) or math.max(0, currentItemCount - grantedCount)

                -- Never remove the player's pre-existing copies of the same item.
                local presentConvertedItems = math.max(0, currentItemCount - baseline)
                local itemsToRemove = math.min(presentConvertedItems, grantedCount)
                for _ = 1, itemsToRemove do
                    player:RemoveCollectible(itemId)
                end

                dbg(string.format("[Chronus] Removed %d converted item(s) (ID:%d) (granted:%d, baseline:%d)",
                    itemsToRemove, tonumber(itemId) or 0, grantedCount, baseline))
            end
        end
        
        rs.absorbed = {}
        rs.totalAbsorbed = 0
        rs.itemGrants = {}  -- Clear granted item counts
        rs.itemGrantTotals = {}
        rs.itemGrantBaselines = {}
        -- Legacy fields cleanup (unified system manages these now)
        rs.absorbedBonusDamage = nil
        rs.absorbActionBonusDamage = nil
        ConchBlessing.SaveManager.Save()
        dbg("Reverted all Chronus effects and restored familiars")
        return true
    end

    local hadGrantState = next(rs.itemGrants or {}) ~= nil
        or next(rs.itemGrantTotals or {}) ~= nil
        or next(rs.itemGrantBaselines or {}) ~= nil
    if hadGrantState or effectStateCleared then
        rs.itemGrants = {}
        rs.itemGrantTotals = {}
        rs.itemGrantBaselines = {}
        ConchBlessing.SaveManager.Save()
        return true
    end

    return false
end

ConchBlessing.chronus.onFamiliarUpdate = function(_, fam)
    local f = fam and fam:ToFamiliar() or nil
    if not f then return end
    local fd = f:GetData() or {}
    if ConchBlessing.chronus._suppressConsumedManualFamiliar(f) then return end
    
    -- Handle Twisted Baby (offset position with side)
    if f.Variant == FamiliarVariant.TWISTED_BABY and fd.__chronusTwistedPair then
        if not fd.__chronusTwistedPairSpr then
            local spr = f:GetSprite()
            local path = tostring(ConchBlessing.chronus.data.spriteNullPath or "gfx/ui/null.png")
            -- Replace all sprite layers to hide wings and body
            for i = 0, 10 do
                pcall(function() spr:ReplaceSpritesheet(i, path) end)
            end
            pcall(function() spr:LoadGraphics() end)
            fd.__chronusTwistedPairSpr = true
            dbg(string.format("Twisted Baby sprite initialized (all layers): pairIdx=%s, side=%s",
                tostring(fd.__chronusPairIndex or "nil"), 
                tostring(fd.__chronusSide or "nil")))
        end
        return
    end
    
    -- Handle Incubus (fixed to player position)
    if f.Variant == FamiliarVariant.INCUBUS and fd.__chronusIncubus then
        if not fd.__chronusIncubusSpr then
            local spr = f:GetSprite()
            local path = tostring(ConchBlessing.chronus.data.spriteNullPath or "gfx/ui/null.png")
            -- Replace all sprite layers to hide wings and body
            for i = 0, 10 do
                pcall(function() spr:ReplaceSpritesheet(i, path) end)
            end
            pcall(function() spr:LoadGraphics() end)
            fd.__chronusIncubusSpr = true
            dbg("Incubus sprite initialized (all layers, fixed position)")
        end
        f:AddEntityFlags(EntityFlag.FLAG_NO_KNOCKBACK | EntityFlag.FLAG_NO_PHYSICS_KNOCKBACK)
        f.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
        f.GridCollisionClass = GridCollisionClass.COLLISION_NONE
        local player = f.Player
        if player then
            f.Position = player.Position
            f.Velocity = Vector.Zero
            f.DepthOffset = tonumber(ConchBlessing.chronus.data.anchorDepthOffset) or 0
        end
        return
    end
    
    -- Handle Succubus (fixed to player position)
    if f.Variant == FamiliarVariant.SUCCUBUS and fd.__chronusSuccubus then
        if not fd.__chronusSuccubusSpr then
            hideFamiliarBody(f, AURA_FAMILIAR_BODY_SHEETS)
            fd.__chronusSuccubusSpr = true
            dbg("Succubus sprite initialized (body hidden, aura kept, fixed position)")
        end
        hideFamiliarShadow(f)
        f:AddEntityFlags(EntityFlag.FLAG_NO_KNOCKBACK | EntityFlag.FLAG_NO_PHYSICS_KNOCKBACK)
        f.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
        f.GridCollisionClass = GridCollisionClass.COLLISION_NONE
        local player = f.Player
        if player then
            f.Position = player.Position
            f.Velocity = Vector.Zero
            f.DepthOffset = tonumber(ConchBlessing.chronus.data.anchorDepthOffset) or 0
        end
        return
    end
    
    -- Handle Censer (fixed to player position)
    if f.Variant == FamiliarVariant.CENSER and fd.__chronusCenser then
        if not fd.__chronusCenserSpr then
            hideFamiliarBody(f, AURA_FAMILIAR_BODY_SHEETS)
            fd.__chronusCenserSpr = true
            dbg("Censer sprite initialized (body hidden, aura kept, fixed position)")
        end
        hideFamiliarShadow(f)
        f:AddEntityFlags(EntityFlag.FLAG_NO_KNOCKBACK | EntityFlag.FLAG_NO_PHYSICS_KNOCKBACK)
        f.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
        f.GridCollisionClass = GridCollisionClass.COLLISION_NONE
        local player = f.Player
        if player then
            f.Position = player.Position
            f.Velocity = Vector.Zero
            f.DepthOffset = tonumber(ConchBlessing.chronus.data.anchorDepthOffset) or 0
        end
        return
    end
    
    -- Handle Star of Bethlehem (fixed to player position)
    if f.Variant == FamiliarVariant.STAR_OF_BETHLEHEM and fd.__chronusStarOfBethlehem then
        if not fd.__chronusStarOfBethlehemSpr then
            hideFamiliarBody(f, AURA_FAMILIAR_BODY_SHEETS)
            fd.__chronusStarOfBethlehemSpr = true
            dbg("Star of Bethlehem sprite initialized (body hidden, aura kept, fixed position)")
        end
        hideFamiliarShadow(f)
        f:AddEntityFlags(EntityFlag.FLAG_NO_KNOCKBACK | EntityFlag.FLAG_NO_PHYSICS_KNOCKBACK)
        f.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
        f.GridCollisionClass = GridCollisionClass.COLLISION_NONE
        local player = f.Player
        if player then
            f.Position = player.Position
            f.Velocity = Vector.Zero
            f.DepthOffset = tonumber(ConchBlessing.chronus.data.anchorDepthOffset) or 0
        end
        return
    end
    
    -- Handle Bloodshot Eye (hidden, fixed to player position)
    if f.Variant == FamiliarVariant.BLOODSHOT_EYE and fd.__chronusBloodshotEye then
        f.Visible = false
        f:AddEntityFlags(EntityFlag.FLAG_NO_KNOCKBACK | EntityFlag.FLAG_NO_PHYSICS_KNOCKBACK)
        f.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
        f.GridCollisionClass = GridCollisionClass.COLLISION_NONE
        local player = f.Player
        if player then
            f.Position = player.Position
            f.Velocity = Vector.Zero
            f.DepthOffset = tonumber(ConchBlessing.chronus.data.anchorDepthOffset) or 0
        end
        return
    end

    -- Handle Angelic Prism (pinned to its ring slot around the player)
    if f.Variant == FamiliarVariant.ANGELIC_PRISM and fd.__chronusAngelicPrism then
        if not fd.__chronusAngelicPrismSpr and not isAngelicPrismDebugVisible() then
            local spr = f:GetSprite()
            local path = tostring(ConchBlessing.chronus.data.spriteNullPath or "gfx/ui/null.png")
            -- Replace all sprite layers
            for i = 0, 10 do
                pcall(function() spr:ReplaceSpritesheet(i, path) end)
            end
            pcall(function() spr:LoadGraphics() end)
            fd.__chronusAngelicPrismSpr = true
        end
        f:AddEntityFlags(EntityFlag.FLAG_NO_KNOCKBACK | EntityFlag.FLAG_NO_PHYSICS_KNOCKBACK)
        f.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
        f.GridCollisionClass = GridCollisionClass.COLLISION_NONE

        local player = f.Player
        if player and player:GetData() then
            applyAngelicPrismAnchor(f, player, getAngelicPrismBaseDir(player))
        end
        return
    end
end

-- Add homing and spectral effects when Seraphim is absorbed
-- Also track actual firing direction from tear velocity for Angelic Prism positioning
ConchBlessing.chronus.onFireTear = function(_, tear)
    local player = tear.SpawnerEntity and tear.SpawnerEntity:ToPlayer() or nil
    if not player or not player:HasCollectible(CHRONUS_ID) then return end
    
    -- Track actual tear firing direction (360 degrees, accurate for analog sticks and items like Marked)
    local pdata = player:GetData()
    if pdata and tear.Velocity and tear.Velocity:Length() > 0 then
        pdata.__chronusLastFireDir = tear.Velocity:Normalized()
    end
    
    -- Seraphim: homing + spectral
    local seraphimCount = ConchBlessing.chronus._getEffectCount(player, CollectibleType.COLLECTIBLE_SERAPHIM)
    if seraphimCount > 0 then
        tear:AddTearFlags(TearFlags.TEAR_HOMING | TearFlags.TEAR_SPECTRAL)
    end
    
    -- Little Steven: homing
    local littleStevenCount = ConchBlessing.chronus._getEffectCount(player, CollectibleType.COLLECTIBLE_LITTLE_STEVEN)
    if littleStevenCount > 0 then
        tear:AddTearFlags(TearFlags.TEAR_HOMING)
    end
end

-- ------------------------------------------------------------ hit effects
-- Absorbed barrier familiars become a chance to ignore an enemy projectile hit,
-- in percent per absorbed copy. Barriers block projectiles, so other damage
-- (contact, lasers, explosions) is never ignored.
local PROJECTILE_BLOCK_PERCENT = {
    [CollectibleType.COLLECTIBLE_HALO_OF_FLIES] = 1,
    [CollectibleType.COLLECTIBLE_DISTANT_ADMIRATION] = 1,
    [CollectibleType.COLLECTIBLE_CUBE_OF_MEAT] = 1,
    [CollectibleType.COLLECTIBLE_FOREVER_ALONE] = 1,
    [CollectibleType.COLLECTIBLE_SACRIFICIAL_DAGGER] = 2,
    [CollectibleType.COLLECTIBLE_GUPPYS_HAIRBALL] = 1,
    [CollectibleType.COLLECTIBLE_GUILLOTINE] = 1,
    [CollectibleType.COLLECTIBLE_BALL_OF_BANDAGES] = 1,
    [CollectibleType.COLLECTIBLE_SMART_FLY] = 1,
    [CollectibleType.COLLECTIBLE_BEST_BUD] = 1,
    [CollectibleType.COLLECTIBLE_BIG_FAN] = 2,
    [CollectibleType.COLLECTIBLE_PUNCHING_BAG] = 2,
    [CollectibleType.COLLECTIBLE_SWORN_PROTECTOR] = 5,
    [CollectibleType.COLLECTIBLE_FRIEND_ZONE] = 1,
    [CollectibleType.COLLECTIBLE_LOST_FLY] = 1,
    [CollectibleType.COLLECTIBLE_HUSHY] = 1,
    [CollectibleType.COLLECTIBLE_BIG_CHUBBY] = 1,
    [CollectibleType.COLLECTIBLE_MOMS_RAZOR] = 1,
    [CollectibleType.COLLECTIBLE_ANGRY_FLY] = 1,
    [CollectibleType.COLLECTIBLE_LEPROSY] = 1,
    [CollectibleType.COLLECTIBLE_SLIPPED_RIB] = 1,
    [CollectibleType.COLLECTIBLE_POINTY_RIB] = 1,
    [CollectibleType.COLLECTIBLE_PSY_FLY] = 5,
    [CollectibleType.COLLECTIBLE_TINYTOMA] = 1,
    [CollectibleType.COLLECTIBLE_OBSESSED_FAN] = 1,
}
-- An absorbed Pretty Fly (the pill's orbital fly) blocks like a barrier familiar.
local PRETTY_FLY_BLOCK_PERCENT = 5

-- Every absorbed copy adds this chance to spawn one blue fly or spider when an
-- attack damages an enemy; two copies (or one of each familiar) make it certain.
local SPAWN_CHANCE_PER_STACK = 0.5
local FLY_SPAWN_FAMILIARS = {
    CollectibleType.COLLECTIBLE_ROTTEN_BABY,
    CollectibleType.COLLECTIBLE_7_SEALS,
}
local SPIDER_SPAWN_FAMILIARS = {
    CollectibleType.COLLECTIBLE_JUICY_SACK,
    CollectibleType.COLLECTIBLE_SISSY_LONGLEGS,
}
local SLOW_FAMILIARS = {
    CollectibleType.COLLECTIBLE_LITTLE_GISH,
    CollectibleType.COLLECTIBLE_INTRUDER,
    CollectibleType.COLLECTIBLE_WORM_FRIEND,
}
local FLY_PROC_KEY = "chronus_blue_fly"
local SPIDER_PROC_KEY = "chronus_blue_spider"
-- Fear and slow are plain per-hit statuses, not procs: nothing is ever marked with
-- this key, so they apply to any player-owned attack, other procs' output included.
local STATUS_KEY = "chronus_status"
local STATUS_FRAMES = 90

-- Per-copy chance, in percent, of the absorbed chance effects. Attack procs roll
-- once per physical attack, room-clear drops once per cleared room, Dry Baby once
-- per hit taken. Copies add up, capped at 100%.
local PROC_CHANCE_PERCENT = {
    [CollectibleType.COLLECTIBLE_DADDY_LONGLEGS] = 10,
    [CollectibleType.COLLECTIBLE_MOMS_RAZOR] = 10,
    [CollectibleType.COLLECTIBLE_CUBE_BABY] = 10,
    [CollectibleType.COLLECTIBLE_LIL_SPEWER] = 25,
    [CollectibleType.COLLECTIBLE_DRY_BABY] = 25,
    [CollectibleType.COLLECTIBLE_BUM_FRIEND] = 10,
    [CollectibleType.COLLECTIBLE_LIL_CHEST] = 10,
}
-- Rooms to clear per drop. The counter is not random; every copy adds one drop.
local CLEAR_REWARD_INTERVAL = {
    [CollectibleType.COLLECTIBLE_RELIC] = 6,
    [CollectibleType.COLLECTIBLE_MYSTERY_SACK] = 6,
    [CollectibleType.COLLECTIBLE_RUNE_BAG] = 7,
}
local DADDY_PROC_KEY = "chronus_daddy_stomp"
local RAZOR_PROC_KEY = "chronus_razor_bleed"
local CUBE_PROC_KEY = "chronus_cube_freeze"
local SPEWER_PROC_KEY = "chronus_spewer_creep"
local GEMINI_PROC_KEY = "chronus_gemini_contact"
local BIRD_CAGE_PROC_KEY = "chronus_bird_cage"
local STOMP_RADIUS = 50
local STOMP_DAMAGE_MULTIPLIER = 2
local BLEED_FRAMES = 150
local FREEZE_FRAMES = 60
-- Aquarius creep deals 0.66x damage per tick; the creeps spawned here match it.
local CREEP_DAMAGE_MULTIPLIER = 0.66
local CREEP_TIMEOUT_FRAMES = 90
-- Contact damage needs a tick rate and the engine has no contact-tick event, so
-- each enemy takes Gemini damage at most once per GEMINI_TICK_FRAMES updates:
-- 2 every 10 updates is the vanilla 6 per second, per copy.
local GEMINI_TICK_FRAMES = 10
local GEMINI_DAMAGE_PER_TICK = 2
local BIRD_CAGE_DAMAGE = 45
local MAX_HOLY_WATER_CREEPS = 4
local MAX_SHADOW_CHARGERS = 3
local MAX_EGG_FLIES = 5
local DANK_CHARGER_VARIANT = 2
local WHITE_POOP_VARIANT = 6

-- Familiars a Buddy in a Box / Lil Delirium copy can lend for a floor: every
-- effect-only familiar plus the projectile-block table. Item-granting and pinned
-- familiars stay out because a pick only raises an effect count.
local FLOOR_PICK_SOURCES = {
    CollectibleType.COLLECTIBLE_BUDDY_IN_A_BOX,
    CollectibleType.COLLECTIBLE_LIL_DELIRIUM,
}
local FLOOR_PICK_EFFECTS = {
    CollectibleType.COLLECTIBLE_BROTHER_BOBBY,
    CollectibleType.COLLECTIBLE_LITTLE_STEVEN,
    CollectibleType.COLLECTIBLE_GUARDIAN_ANGEL,
    CollectibleType.COLLECTIBLE_RELIC,
    CollectibleType.COLLECTIBLE_LITTLE_GISH,
    CollectibleType.COLLECTIBLE_BUM_FRIEND,
    CollectibleType.COLLECTIBLE_DADDY_LONGLEGS,
    CollectibleType.COLLECTIBLE_HOLY_WATER,
    CollectibleType.COLLECTIBLE_DRY_BABY,
    CollectibleType.COLLECTIBLE_JUICY_SACK,
    CollectibleType.COLLECTIBLE_ROTTEN_BABY,
    CollectibleType.COLLECTIBLE_MYSTERY_SACK,
    CollectibleType.COLLECTIBLE_SISSY_LONGLEGS,
    CollectibleType.COLLECTIBLE_GEMINI,
    CollectibleType.COLLECTIBLE_MONGO_BABY,
    CollectibleType.COLLECTIBLE_LIL_CHEST,
    CollectibleType.COLLECTIBLE_RUNE_BAG,
    CollectibleType.COLLECTIBLE_LIL_HAUNT,
    CollectibleType.COLLECTIBLE_MY_SHADOW,
    CollectibleType.COLLECTIBLE_MILK,
    CollectibleType.COLLECTIBLE_LIL_SPEWER,
    CollectibleType.COLLECTIBLE_MYSTERY_EGG,
    CollectibleType.COLLECTIBLE_HALLOWED_GROUND,
    CollectibleType.COLLECTIBLE_PASCHAL_CANDLE,
    CollectibleType.COLLECTIBLE_7_SEALS,
    CollectibleType.COLLECTIBLE_BIRD_CAGE,
    CollectibleType.COLLECTIBLE_LOST_SOUL,
    CollectibleType.COLLECTIBLE_WORM_FRIEND,
    CollectibleType.COLLECTIBLE_CUBE_BABY,
    CollectibleType.COLLECTIBLE_INTRUDER,
}

---@param percentPerCopy number
---@param copies number
---@return number chance in [0, 1]
local function getStackedChance(percentPerCopy, copies)
    local stacked = math.max(0, tonumber(percentPerCopy) or 0) * math.max(0, tonumber(copies) or 0)
    return math.min(1, stacked / 100)
end

--- `count` draws from `pool` with replacement. randomInt(n) returns 0..n-1, so a
--- longer draw from the same seed keeps every earlier pick.
local function pickFromPool(pool, count, randomInt)
    local picks = {}
    if #pool == 0 then return picks end
    for i = 1, math.max(0, math.floor(tonumber(count) or 0)) do
        picks[i] = pool[randomInt(#pool) + 1]
    end
    return picks
end

--- `count` distinct entries of `copies` (one entry per absorbed copy), chosen
--- uniformly without replacement by a partial Fisher-Yates shuffle.
local function pickRandomCopies(copies, count, randomInt)
    local work = {}
    for i, value in ipairs(copies) do work[i] = value end
    local picked = {}
    local n = #work
    for i = 1, math.min(math.max(0, math.floor(tonumber(count) or 0)), n) do
        local j = i + randomInt(n - i + 1)
        work[i], work[j] = work[j], work[i]
        picked[i] = work[i]
    end
    return picked
end

local floorPickPool
local function getFloorPickPool()
    if floorPickPool then return floorPickPool end
    local set = {}
    for _, id in ipairs(FLOOR_PICK_EFFECTS) do set[id] = true end
    for id in pairs(PROJECTILE_BLOCK_PERCENT) do set[id] = true end
    local pool = {}
    for id in pairs(set) do pool[#pool + 1] = id end
    table.sort(pool)
    floorPickPool = pool
    return pool
end

---@param counts table familiar collectible id -> absorbed count
---@param prettyFlies number|nil absorbed Pretty Flies
---@return number chance in [0, 1]
local function getProjectileBlockChance(counts, prettyFlies)
    local percent = PRETTY_FLY_BLOCK_PERCENT * math.max(0, tonumber(prettyFlies) or 0)
    for familiarId, perCopy in pairs(PROJECTILE_BLOCK_PERCENT) do
        percent = percent + perCopy * math.max(0, tonumber(counts[familiarId]) or 0)
    end
    return math.min(1, percent / 100)
end

---@param stacks number absorbed copies feeding one spawn effect
---@return number chance in [0, 1]
local function getSpawnChance(stacks)
    return math.min(1, SPAWN_CHANCE_PER_STACK * math.max(0, tonumber(stacks) or 0))
end

local function sumEffectCounts(player, familiarIds)
    local total = 0
    for _, familiarId in ipairs(familiarIds) do
        total = total + ConchBlessing.chronus._getEffectCount(player, familiarId)
    end
    return total
end

local function getProjectileBlockCounts(player)
    local counts = {}
    for familiarId in pairs(PROJECTILE_BLOCK_PERCENT) do
        counts[familiarId] = ConchBlessing.chronus._getEffectCount(player, familiarId)
    end
    return counts
end

local function getProcChance(player, familiarId)
    return getStackedChance(PROC_CHANCE_PERCENT[familiarId], ConchBlessing.chronus._getEffectCount(player, familiarId))
end

local function isHostileTarget(npc)
    return npc and npc:Exists() and npc:IsVulnerableEnemy() and npc:IsActiveEnemy()
        and not npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
        and not npc:HasEntityFlags(EntityFlag.FLAG_CHARM)
end

-- One roll per physical attack: the claim comes before the RNG, so a piercing
-- tear or a beam does not reroll per target. A familiar body (blue flies and
-- spiders included) cannot claim an attack, so their contact damage never triggers
-- a proc, and each proc's output carries its key so nothing it causes re-enters it.
local function tryAttackProc(source, extraSource, procKey, chanceFor, rngItem, apply)
    local attackEntity, player, provenance = DamageProvenance.getEligiblePlayerAttack(source, extraSource, procKey)
    if not (attackEntity and player and player:HasCollectible(CHRONUS_ID)) then return end
    local chance = chanceFor(player)
    if chance <= 0 then return end
    if not DamageProvenance.tryClaimAttackProc(attackEntity, procKey) then return end
    if player:GetCollectibleRNG(rngItem):RandomFloat() >= chance then return end
    apply(player, provenance)
end

local function spawnPlayerCreep(player, variant, position, provenance, procKey)
    local entity = Isaac.Spawn(EntityType.ENTITY_EFFECT, variant, 0, position, Vector.Zero, player)
    local creep = entity and entity:ToEffect() or nil
    if not creep then return nil end
    creep.CollisionDamage = player.Damage * CREEP_DAMAGE_MULTIPLIER
    creep:SetTimeout(CREEP_TIMEOUT_FRAMES)
    if procKey then
        DamageProvenance.markTriggeredAttack(creep, procKey, provenance, procKey)
    end
    return creep
end

-- The anm2 has no stomp event, so the damage lands at the proc and the leg is a
-- cosmetic that starts one frame before its landing frame (10 of 50).
local STOMP_ANM2 = "gfx/003.016_daddys foot.anm2"
local STOMP_ANIMATION = "StompLeg"
local STOMP_VISUAL_START_FRAME = 9
local stompVisuals = {}

local function addStompVisual(position)
    local sprite = Sprite()
    sprite:Load(STOMP_ANM2, true)
    sprite:Play(STOMP_ANIMATION, true)
    sprite:SetFrame(STOMP_VISUAL_START_FRAME)
    stompVisuals[#stompVisuals + 1] = { sprite = sprite, position = position }
end

local function daddyStomp(player, center, provenance)
    local damage = player.Damage * STOMP_DAMAGE_MULTIPLIER
    DamageProvenance.withTriggeredSource(player, DADDY_PROC_KEY, provenance, DADDY_PROC_KEY, function()
        for _, entity in ipairs(Isaac.FindInRadius(center, STOMP_RADIUS, EntityPartition.ENEMY)) do
            local target = entity:ToNPC()
            if target and isHostileTarget(target) then
                target:TakeDamage(damage, 0, EntityRef(player), 0)
            end
        end
    end)
    SFXManager():Play(SoundEffect.SOUND_FORESTBOSS_STOMPS, 0.6)
    Game():ShakeScreen(4)
    addStompVisual(center)
    bump("stomps")
end

-- REPENTOGON has a bleed API with a duration; the base game only has the flag.
local function applyBleed(npc, player)
    bump("bleeds")
    if type(npc.AddBleeding) == "function" and pcall(npc.AddBleeding, npc, EntityRef(player), BLEED_FRAMES) then
        return
    end
    npc:AddEntityFlags(EntityFlag.FLAG_BLEED_OUT)
end

local function applyHitEffects(npc, source, extraSource)
    if not isHostileTarget(npc) then return end
    local effectCount = ConchBlessing.chronus._getEffectCount

    local _, player = DamageProvenance.getEligiblePlayerAttack(source, extraSource, STATUS_KEY)
    if player and player:HasCollectible(CHRONUS_ID) then
        if effectCount(player, CollectibleType.COLLECTIBLE_LIL_HAUNT) > 0 then
            npc:AddFear(EntityRef(player), STATUS_FRAMES)
        end
        if sumEffectCounts(player, SLOW_FAMILIARS) > 0 then
            npc:AddSlowing(EntityRef(player), STATUS_FRAMES, 0.5, Color(0.5, 0.5, 0.5, 1, 0, 0, 0))
        end
    end

    tryAttackProc(source, extraSource, FLY_PROC_KEY,
        function(owner) return getSpawnChance(sumEffectCounts(owner, FLY_SPAWN_FAMILIARS)) end,
        CollectibleType.COLLECTIBLE_ROTTEN_BABY,
        function(owner, provenance)
            local fly = owner:AddBlueFlies(1, owner.Position, nil)
            bump("flies")
            if fly then DamageProvenance.markTriggeredAttack(fly, FLY_PROC_KEY, provenance, FLY_PROC_KEY) end
        end)
    tryAttackProc(source, extraSource, SPIDER_PROC_KEY,
        function(owner) return getSpawnChance(sumEffectCounts(owner, SPIDER_SPAWN_FAMILIARS)) end,
        CollectibleType.COLLECTIBLE_JUICY_SACK,
        function(owner, provenance)
            local spider = owner:AddBlueSpider(owner.Position)
            bump("spiders")
            if spider then DamageProvenance.markTriggeredAttack(spider, SPIDER_PROC_KEY, provenance, SPIDER_PROC_KEY) end
        end)
    tryAttackProc(source, extraSource, DADDY_PROC_KEY,
        function(owner) return getProcChance(owner, CollectibleType.COLLECTIBLE_DADDY_LONGLEGS) end,
        CollectibleType.COLLECTIBLE_DADDY_LONGLEGS,
        function(owner, provenance) daddyStomp(owner, npc.Position, provenance) end)
    tryAttackProc(source, extraSource, RAZOR_PROC_KEY,
        function(owner) return getProcChance(owner, CollectibleType.COLLECTIBLE_MOMS_RAZOR) end,
        CollectibleType.COLLECTIBLE_MOMS_RAZOR,
        function(owner)
            if npc:Exists() and not npc:IsDead() then applyBleed(npc, owner) end
        end)
    tryAttackProc(source, extraSource, CUBE_PROC_KEY,
        function(owner) return getProcChance(owner, CollectibleType.COLLECTIBLE_CUBE_BABY) end,
        CollectibleType.COLLECTIBLE_CUBE_BABY,
        function(owner)
            if npc:Exists() and not npc:IsDead() then
                npc:AddFreeze(EntityRef(owner), FREEZE_FRAMES)
                bump("freezes")
            end
        end)
    tryAttackProc(source, extraSource, SPEWER_PROC_KEY,
        function(owner) return getProcChance(owner, CollectibleType.COLLECTIBLE_LIL_SPEWER) end,
        CollectibleType.COLLECTIBLE_LIL_SPEWER,
        function(owner, provenance)
            spawnPlayerCreep(owner, EffectVariant.PLAYER_CREEP_RED, npc.Position, provenance, SPEWER_PROC_KEY)
            bump("creeps")
        end)
end

-- ------------------------------------------------------------ hurt effects
-- Effects of being hit run on the next update, after the damage callback has
-- unwound, so Necronomicon and the spawns never re-enter a damage callback.
local pendingHurts = {}

local function queueHurt(player)
    local key = GetPtrHash(player)
    local entry = pendingHurts[key]
    if entry then
        entry.count = entry.count + 1
    else
        pendingHurts[key] = { player = player, count = 1 }
    end
end

local function findNearestEnemy(position)
    local best, bestDistance
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local npc = entity:ToNPC()
        if npc and isHostileTarget(npc) then
            local distance = position:DistanceSquared(npc.Position)
            if not bestDistance or distance < bestDistance then
                best, bestDistance = npc, distance
            end
        end
    end
    return best
end

local function spawnCharmedEnemy(player, entityType, variant)
    local room = Game():GetRoom()
    local position = room:FindFreePickupSpawnPosition(player.Position, 20, true)
    local entity = Isaac.Spawn(entityType, variant, 0, position, Vector.Zero, player)
    local npc = entity and entity:ToNPC() or nil
    if npc then
        npc:AddCharmed(EntityRef(player), -1)
    end
end

local function runHurtEffects(player)
    local rs = getRunSave(player)
    if not rs then return end
    bump("hurts")
    local effectCount = ConchBlessing.chronus._getEffectCount
    local serial = tonumber(rs.floorSerial) or 0
    local saveChanged = false

    -- Lost Soul pays out only for a floor without a hit; remember this one.
    if rs.hurtSerial ~= serial then
        rs.hurtSerial = serial
        saveChanged = true
    end
    -- Milk!: the first hit on a floor turns on its tears bonus until the floor ends.
    if effectCount(player, CollectibleType.COLLECTIBLE_MILK) > 0 and rs.milkSerial ~= serial then
        rs.milkSerial = serial
        saveChanged = true
        player:AddCacheFlags(CacheFlag.CACHE_FIREDELAY)
        player:EvaluateItems()
    end
    if saveChanged then
        ConchBlessing.SaveManager.Save()
    end

    local position = player.Position
    local holyWater = math.min(effectCount(player, CollectibleType.COLLECTIBLE_HOLY_WATER), MAX_HOLY_WATER_CREEPS)
    for i = 1, holyWater do
        local offset = i == 1 and Vector.Zero or Vector.FromAngle((i - 2) * 120) * 24
        spawnPlayerCreep(player, EffectVariant.PLAYER_CREEP_HOLYWATER, position + offset, nil, nil)
    end

    if player:GetCollectibleRNG(CollectibleType.COLLECTIBLE_DRY_BABY):RandomFloat()
        < getProcChance(player, CollectibleType.COLLECTIBLE_DRY_BABY) then
        bump("necronomicon")
        pcall(player.UseActiveItem, player, CollectibleType.COLLECTIBLE_NECRONOMICON,
            UseFlag.USE_NOANIM | UseFlag.USE_NOCOSTUME, -1)
    end

    local birdCage = effectCount(player, CollectibleType.COLLECTIBLE_BIRD_CAGE)
    if birdCage > 0 then
        local target = findNearestEnemy(position)
        if target then
            DamageProvenance.withTriggeredSource(player, BIRD_CAGE_PROC_KEY, nil, BIRD_CAGE_PROC_KEY, function()
                target:TakeDamage(BIRD_CAGE_DAMAGE * birdCage, 0, EntityRef(player), 0)
            end)
            bump("birdCage")
            SFXManager():Play(SoundEffect.SOUND_FORESTBOSS_STOMPS, 0.8)
            Game():ShakeScreen(6)
        end
    end

    for _ = 1, math.min(effectCount(player, CollectibleType.COLLECTIBLE_MYSTERY_EGG), MAX_EGG_FLIES) do
        spawnCharmedEnemy(player, EntityType.ENTITY_ATTACKFLY, 0)
    end
    for _ = 1, math.min(effectCount(player, CollectibleType.COLLECTIBLE_MY_SHADOW), MAX_SHADOW_CHARGERS) do
        spawnCharmedEnemy(player, EntityType.ENTITY_CHARGER, DANK_CHARGER_VARIANT)
    end

    if effectCount(player, CollectibleType.COLLECTIBLE_HALLOWED_GROUND) > 0 then
        local room = Game():GetRoom()
        local ok, tile = pcall(room.FindFreeTilePosition, room, position, 120)
        if ok and tile then
            Isaac.GridSpawn(GridEntityType.GRID_POOP, WHITE_POOP_VARIANT, tile, false)
        end
    end
end

local function processPendingHurts()
    if next(pendingHurts) == nil then return end
    local batch = pendingHurts
    pendingHurts = {}
    for _, entry in pairs(batch) do
        local player = entry.player
        if player and player:Exists() and player:HasCollectible(CHRONUS_ID) then
            for _ = 1, math.min(entry.count, 3) do
                runHurtEffects(player)
            end
        end
    end
end

-- Gemini: contact damage from the player to touching enemies, rate-limited per enemy.
ConchBlessing.chronus.onPrePlayerCollision = function(_, player, collider)
    local npc = collider and collider:ToNPC()
    if not (npc and player and player:HasCollectible(CHRONUS_ID)) then return end
    if not isHostileTarget(npc) then return end
    local copies = ConchBlessing.chronus._getEffectCount(player, CollectibleType.COLLECTIBLE_GEMINI)
    if copies <= 0 then return end
    local data = npc:GetData()
    local frame = Game():GetFrameCount()
    if data.__chronusGeminiNextFrame and frame < data.__chronusGeminiNextFrame then return end
    data.__chronusGeminiNextFrame = frame + GEMINI_TICK_FRAMES
    DamageProvenance.withTriggeredSource(player, GEMINI_PROC_KEY, nil, GEMINI_PROC_KEY, function()
        npc:TakeDamage(GEMINI_DAMAGE_PER_TICK * copies, 0, EntityRef(player), 0)
    end)
    bump("gemini")
end

-- Pre-damage: the projectile block for the Chronus owner, plus the base-game
-- fallback for enemy hits when the REPENTOGON applied-damage callback is missing
-- (that fallback runs before damage is final and may count a cancelled hit).
ConchBlessing.chronus.onEntityTakeDamage = function(_, entity, amount, flags, source, countdown)
    local player = entity and entity:ToPlayer()
    if player then
        if not player:HasCollectible(CHRONUS_ID) then return end
        if source and source.Type == EntityType.ENTITY_PROJECTILE then
            local chance = getProjectileBlockChance(getProjectileBlockCounts(player),
                ConchBlessing.chronus._getPrettyFlyCount(player))
            if chance > 0 and player:GetCollectibleRNG(CHRONUS_ID):RandomFloat() < chance then
                dbg(string.format("Projectile hit ignored (chance %.0f%%)", chance * 100))
                bump("projectileBlocks")
                return false
            end
        end
        -- Without REPENTOGON the hit is recorded before it is final, so another
        -- callback cancelling it afterwards still runs the hurt effects.
        if not DamageProvenance.hasAppliedDamageCallback() then
            queueHurt(player)
        end
        return
    end

    if DamageProvenance.hasAppliedDamageCallback() then return end
    local npc = entity and entity:ToNPC()
    if not npc then return end
    applyHitEffects(npc, source, nil)
end

-- REPENTOGON: apply hit effects only after the damage really landed.
ConchBlessing.chronus.onPostEntityTakeDamage = function(_, entity, amount, _flags, source, _countdown, extraSource)
    if not entity then return end
    local player = entity:ToPlayer()
    if player then
        if player:HasCollectible(CHRONUS_ID) then queueHurt(player) end
        return
    end
    if (tonumber(amount) or 0) <= 0 then return end
    local npc = entity:ToNPC()
    if not npc then return end
    applyHitEffects(npc, source, extraSource)
end

-- ------------------------------------------------------------ room clear
local function spawnPickup(variant, subtype, position, rng)
    local game = Game()
    local spawnAt = game:GetRoom():FindFreePickupSpawnPosition(position, 0, true)
    local seed = rng:Next()
    if seed == 0 then seed = 1 end
    game:Spawn(EntityType.ENTITY_PICKUP, variant, spawnAt, Vector.Zero, nil, subtype, seed)
end

local function spawnClearReward(familiarId, position, rng)
    if familiarId == CollectibleType.COLLECTIBLE_RELIC then
        spawnPickup(PickupVariant.PICKUP_HEART, HeartSubType.HEART_SOUL, position, rng)
    elseif familiarId == CollectibleType.COLLECTIBLE_RUNE_BAG then
        local rune = Game():GetItemPool():GetCard(math.max(1, rng:Next()), false, true, true)
        spawnPickup(PickupVariant.PICKUP_TAROTCARD, rune, position, rng)
    else
        spawnPickup(PickupVariant.PICKUP_NULL, 0, position, rng)
    end
end

-- MC_PRE_SPAWN_CLEAN_AWARD. The absorbed pool is shared by every Chronus holder,
-- so a room clear pays out once. The engine's award RNG is left untouched.
ConchBlessing.chronus.onRoomClear = function(_, _rng, spawnPosition)
    local player = findChronusOwner()
    if not player then return end
    local rs = getRunSave(player)
    if not rs then return end
    local effectCount = ConchBlessing.chronus._getEffectCount
    local position = spawnPosition or Game():GetRoom():GetCenterPos()
    bump("roomClears")

    local bumFriend = player:GetCollectibleRNG(CollectibleType.COLLECTIBLE_BUM_FRIEND)
    if bumFriend:RandomFloat() < getProcChance(player, CollectibleType.COLLECTIBLE_BUM_FRIEND) then
        spawnPickup(PickupVariant.PICKUP_NULL, 0, position, bumFriend)
    end
    local lilChest = player:GetCollectibleRNG(CollectibleType.COLLECTIBLE_LIL_CHEST)
    if lilChest:RandomFloat() < getProcChance(player, CollectibleType.COLLECTIBLE_LIL_CHEST) then
        spawnPickup(PickupVariant.PICKUP_CHEST, ChestSubType.CHEST_CLOSED, position, lilChest)
    end

    local saveChanged = false
    rs.clearCounters = rs.clearCounters or {}
    for familiarId, interval in pairs(CLEAR_REWARD_INTERVAL) do
        local copies = effectCount(player, familiarId)
        if copies > 0 then
            local key = "fam_" .. tostring(familiarId)
            local progress = (tonumber(rs.clearCounters[key]) or 0) + 1
            if progress >= interval then
                progress = 0
                local rng = player:GetCollectibleRNG(familiarId)
                for _ = 1, copies do
                    spawnClearReward(familiarId, position, rng)
                end
            end
            rs.clearCounters[key] = progress
            saveChanged = true
        end
    end

    local paschal = effectCount(player, CollectibleType.COLLECTIBLE_PASCHAL_CANDLE)
    if paschal > 0 then
        local perClear = math.floor(ConchBlessing.chronus.STATS.PASCHAL_TEARS_PER_CLEAR * 100 + 0.5)
        rs.paschalHundredths = (tonumber(rs.paschalHundredths) or 0) + perClear * paschal
        saveChanged = true
        local game = Game()
        for i = 0, game:GetNumPlayers() - 1 do
            local holder = game:GetPlayer(i)
            if holder and holder:HasCollectible(CHRONUS_ID) then
                holder:AddCacheFlags(CacheFlag.CACHE_FIREDELAY)
                holder:EvaluateItems()
            end
        end
    end

    if saveChanged then
        ConchBlessing.SaveManager.Save()
    end
end

-- ------------------------------------------------------------ floor state
refreshEffectCaches = function()
    local game = Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local holder = game:GetPlayer(i)
        if holder and holder:HasCollectible(CHRONUS_ID) then
            ConchBlessing.chronus._syncAbsorbedDamage(holder)
            holder:AddCacheFlags(CacheFlag.CACHE_DAMAGE | CacheFlag.CACHE_FIREDELAY | CacheFlag.CACHE_SPEED | CacheFlag.CACHE_FLYING)
            holder:EvaluateItems()
        end
    end
end

--- Keep one floor pick per absorbed Buddy in a Box / Lil Delirium copy. Picks are
--- drawn from the stage seed and floor serial, so a continue or an extra copy on
--- the same floor keeps the earlier picks and a new floor rerolls all of them.
function ConchBlessing.chronus._ensureFloorPicks(player)
    local rs = getRunSave(player)
    if not rs then return false end
    local wanted = 0
    for _, id in ipairs(FLOOR_PICK_SOURCES) do
        wanted = wanted + ConchBlessing.chronus._getAbsorbedCount(player, id)
    end
    local serial = tonumber(rs.floorSerial) or 0
    local current = rs.floorPicks
    if wanted <= 0 then
        if current == nil then return false end
        rs.floorPicks = nil
    elseif type(current) == "table" and current.serial == serial
        and type(current.ids) == "table" and #current.ids == wanted then
        return false
    else
        local game = Game()
        local seed = (game:GetSeeds():GetStageSeed(game:GetLevel():GetStage()) + serial * 7919) % 4294967296
        if seed == 0 then seed = 1 end
        local rng = RNG()
        rng:SetSeed(seed, 35)
        local ids = pickFromPool(getFloorPickPool(), wanted, function(n) return rng:RandomInt(n) end)
        rs.floorPicks = { serial = serial, ids = ids }
        dbg(string.format("Floor picks (serial %d): %s", serial, table.concat(ids, ", ")))
    end
    ConchBlessing.SaveManager.Save()
    refreshEffectCaches()
    return true
end

ConchBlessing.chronus.onNewLevel = function()
    if not ConchBlessing.chronus._runReady then return end
    local player = findChronusOwner()
    if not player then return end
    local rs = getRunSave(player)
    if not rs then return end
    local previous = tonumber(rs.floorSerial) or 0
    -- Lost Soul: a floor left without a hit pays out in the next room that loads.
    local lostSoul = ConchBlessing.chronus._getEffectCount(player, CollectibleType.COLLECTIBLE_LOST_SOUL)
    if lostSoul > 0 and rs.hurtSerial ~= previous then
        rs.lostSoulRewardPending = (tonumber(rs.lostSoulRewardPending) or 0) + lostSoul
    end
    rs.floorSerial = previous + 1
    -- Monster Manual familiars last one floor.
    local hadFloorTemp = rs.tempFloor ~= nil
    ConchBlessing.chronus._clearManualGrants(player, rs)
    rs.tempFloor = nil
    ConchBlessing.chronus._syncAbsorbedDamage(player)
    ConchBlessing.SaveManager.Save()
    if hadFloorTemp then
        clearChronusRuntime(player)
    end
    if not ConchBlessing.chronus._ensureFloorPicks(player) then
        refreshEffectCaches()
    end
end

function ConchBlessing.chronus._payLostSoulReward()
    if not ConchBlessing.chronus._runReady then return end
    local player = findChronusOwner()
    if not player then return end
    local rs = getRunSave(player)
    local pending = rs and math.floor(tonumber(rs.lostSoulRewardPending) or 0) or 0
    if pending <= 0 then return end
    rs.lostSoulRewardPending = nil
    ConchBlessing.SaveManager.Save()
    local rng = player:GetCollectibleRNG(CollectibleType.COLLECTIBLE_LOST_SOUL)
    for _ = 1, pending do
        spawnPickup(PickupVariant.PICKUP_HEART, HeartSubType.HEART_ETERNAL, player.Position, rng)
    end
end

-- Mongo Baby: keep one Minisaac per copy, refilled at every room entry.
function ConchBlessing.chronus._topUpMongoMinisaacs(player)
    if not player or type(player.AddMinisaac) ~= "function" then return end
    local target = ConchBlessing.chronus._getEffectCount(player, CollectibleType.COLLECTIBLE_MONGO_BABY)
    if target <= 0 then return end
    local owner = GetPtrHash(player)
    local live = 0
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, FamiliarVariant.MINISAAC)) do
        local fam = entity:ToFamiliar()
        if fam and fam.Player and GetPtrHash(fam.Player) == owner and fam:GetData().__chronusMongoMinisaac then
            live = live + 1
        end
    end
    for _ = live + 1, target do
        local ok, minisaac = pcall(player.AddMinisaac, player, player.Position, true)
        if ok and minisaac then
            minisaac:GetData().__chronusMongoMinisaac = true
        end
    end
end

-- ------------------------------------------------------------ GB Bug release
-- A released familiar returns as the real collectible, so its grant above the
-- remaining copies is taken back (lifetime totals too: the grant was returned,
-- not lost) and the copy is recorded in `spared` so it is not absorbed again.
local function trimGrantsToAbsorbed(player, rs, familiarId, absorbedCount)
    local conversion = ConchBlessing.chronus.data.familiarToItemMap[familiarId]
    if type(conversion) ~= "table" or not conversion.itemId then return end
    local key = "fam_" .. tostring(familiarId)
    local grants = familiarGrantCount(rs, familiarId)
    local maxGrants = conversion.maxGrants or 0
    local allowed = maxGrants == 0 and absorbedCount or math.min(absorbedCount, maxGrants)
    local excess = grants - allowed
    if excess <= 0 then return end

    local itemId = conversion.itemId
    local current = player:GetCollectibleNum(itemId, true)
    local baseline = getItemBaseline(rs, itemId) or math.max(0, current - itemGrantCount(rs, itemId))
    local present = math.max(0, current - baseline)
    for _ = 1, math.min(excess, present) do
        player:RemoveCollectible(itemId)
    end
    rs.itemGrants[key] = grants - excess
    rs.itemGrantTotals[key] = math.max(0, math.floor(tonumber(rs.itemGrantTotals[key]) or 0) - excess)
    if itemGrantCount(rs, itemId) == 0 then
        rs.itemGrantBaselines[itemBaselineKey(itemId)] = nil
    end
end

-- returnToPlayer = false consumes the copies instead (Sacrificial Altar).
local function releaseCopies(player, rs, familiarIds, returnToPlayer)
    if returnToPlayer == nil then returnToPlayer = true end
    local byFamiliar = {}
    for _, familiarId in ipairs(familiarIds) do
        byFamiliar[familiarId] = (byFamiliar[familiarId] or 0) + 1
    end
    local order = {}
    for familiarId in pairs(byFamiliar) do order[#order + 1] = familiarId end
    table.sort(order)

    rs.spared = rs.spared or {}
    rs.itemGrants = rs.itemGrants or {}
    rs.itemGrantTotals = rs.itemGrantTotals or {}
    rs.itemGrantBaselines = rs.itemGrantBaselines or {}
    local released = 0
    for _, familiarId in ipairs(order) do
        local key = "fam_" .. tostring(familiarId)
        local before = ConchBlessing.chronus._getAbsorbedCount(player, familiarId)
        local count = math.min(byFamiliar[familiarId], before)
        if count > 0 then
            local after = before - count
            rs.absorbed[key] = after > 0 and { count = after, id = familiarId } or nil
            rs.totalAbsorbed = math.max(0, (rs.totalAbsorbed or 0) - count)
            trimGrantsToAbsorbed(player, rs, familiarId, after)
            if returnToPlayer then
                rs.spared[key] = (tonumber(rs.spared[key]) or 0) + count
            end
            for _ = 1, count do
                if returnToPlayer then
                    player:AddCollectible(familiarId, 0, false)
                end
                ConchBlessing.chronus._queueTransferEffect(player, familiarId, true)
            end
            released = released + count
            dbg(string.format("%s familiar %d x%d (%d -> %d)", returnToPlayer and "Released" or "Sacrificed",
                familiarId, count, before, after))
        end
    end

    if released > 0 then
        ConchBlessing.chronus._syncAbsorbedDamage(player)
        -- Pinned stand-ins are rebuilt from the new counts on the next update.
        clearChronusRuntime(player)
        ConchBlessing.SaveManager.Save()
        player:AddCacheFlags(CacheFlag.CACHE_ALL)
        player:EvaluateItems()
    end
    return released
end

--- GB Bug: hand back a random half (rounded down) of the other absorbed copies.
function ConchBlessing.chronus._releaseRandomHalf(player)
    local rs = getRunSave(player)
    if not rs or not rs.absorbed then return 0 end
    local ids = {}
    for key, entry in pairs(rs.absorbed) do
        local familiarId = type(entry) == "table" and (entry.id or tonumber(tostring(key):match("^fam_(%d+)$"))) or nil
        if familiarId and familiarId ~= CollectibleType.COLLECTIBLE_GB_BUG then
            ids[#ids + 1] = familiarId
        end
    end
    table.sort(ids)
    local copies = {}
    for _, familiarId in ipairs(ids) do
        for _ = 1, ConchBlessing.chronus._getAbsorbedCount(player, familiarId) do
            copies[#copies + 1] = familiarId
        end
    end
    local count = math.floor(#copies / 2)
    if count <= 0 then return 0 end
    local rng = player:GetCollectibleRNG(CollectibleType.COLLECTIBLE_GB_BUG)
    local picked = pickRandomCopies(copies, count, function(n) return rng:RandomInt(n) end)
    return releaseCopies(player, rs, picked)
end

-- ------------------------------------------------------------ temporary familiars
-- Familiars that do not come from an owned collectible. Only these sources are
-- handled; every other one (wisps, blue flies, locusts, Umbilical Cord, cards
-- such as XV - The Devil?) keeps its vanilla behaviour:
--   Box of Friends   every absorbed effect counts twice for the room; its stand-in
--                    familiar (Demon Baby) is swallowed instead of spawning
--   Monster Manual   its familiar is absorbed for the rest of the floor
--   The Twins        when it duplicates (50%), one absorbed familiar counts twice
--                    for the room instead of a Brother Bobby / Sister Maggy
--   Soul of Lilith   a familiar it adds as a temporary effect is absorbed for good
--                    (one it adds as a collectible is absorbed like any other)
--   Pretty Fly pill  (REPENTOGON) the fly is absorbed as a 5% projectile block
--   Sacrificial Altar sacrifices up to 2 absorbed familiars for devil-pool items
-- These sources add their familiars to the player's TemporaryEffects, so the
-- absorption reads and removes exactly those effects after the source fires.
local SOURCE_BOX = "box"
local SOURCE_MANUAL = "manual"
local SOURCE_TWINS = "twins"
local SOURCE_LILITH = "lilith"
local ALTAR_MAX_SACRIFICES = 2
local pendingTempScans = {}
local pendingManualScans = {}
local altarSnapshots = {}

function ConchBlessing.chronus._getPrettyFlyCount(player)
    local rs = getRunSave(player)
    return math.max(0, tonumber(rs and rs.prettyFlies) or 0) * (1 + roomTemp.double)
end

--- Damage copies on top of the real absorbed ones, which StatsAPI already counts.
function ConchBlessing.chronus._getTemporaryDamageCopies(player)
    local rs = getRunSave(player)
    if not rs then return 0 end
    local copies = 0
    for _, count in pairs(roomTemp.counts) do copies = copies + (tonumber(count) or 0) end
    local floor = rs.tempFloor
    if type(floor) == "table" and floor.serial == (tonumber(rs.floorSerial) or 0) and type(floor.counts) == "table" then
        for _, count in pairs(floor.counts) do copies = copies + (tonumber(count) or 0) end
    end
    for _, count in pairs(type(rs.tempPermanent) == "table" and rs.tempPermanent or {}) do
        copies = copies + (tonumber(count) or 0)
    end
    for famId, times in pairs(roomTemp.twins) do
        copies = copies + ConchBlessing.chronus._getAbsorbedCount(player, famId) * times
    end
    copies = copies + math.max(0, tonumber(rs.prettyFlies) or 0)
    return copies + (math.max(0, tonumber(rs.totalAbsorbed) or 0) + copies) * roomTemp.double
end

-- SetItemAddition is a delta API. Read the provider's actual contribution instead
-- of remembering the last delta: cache resets, continue and reward removal must
-- all converge to the same ledger, without double-crediting an absorption.
function ConchBlessing.chronus._syncAbsorbedDamage(player)
    local um = ConchBlessing.stats and ConchBlessing.stats.unifiedMultipliers
    if not (player and um and type(um.SetItemAddition) == "function") then return end
    local rs = getRunSave(player)
    if not rs then return end
    local copies = player:HasCollectible(CHRONUS_ID)
        and (math.max(0, tonumber(rs.totalAbsorbed) or 0)
            + ConchBlessing.chronus._getTemporaryDamageCopies(player)) or 0
    local wanted = copies * ConchBlessing.chronus.STATS.DAMAGE_PER_FAMILIAR
    local state = ConchBlessing.getUnifiedMultiplierState(player, um)
    local entry = state and state.itemAdditions and state.itemAdditions[CHRONUS_ID]
        and state.itemAdditions[CHRONUS_ID].Damage
    local actual = tonumber(entry and entry.cumulative) or 0
    if wanted > 0 and entry and entry.disabled == true
        and type(um.SetItemMultiplierDisabled) == "function" then
        um:SetItemMultiplierDisabled(player, CHRONUS_ID, "Damage", false)
    end
    local delta = wanted - actual
    if math.abs(delta) < 0.00001 then return end
    um:SetItemAddition(player, CHRONUS_ID, "Damage", delta, string.format("Chronus: %d familiars", copies))
    if type(um.QueueCacheUpdate) == "function" then um:QueueCacheUpdate(player, "Damage") end
    if type(um.SaveToSaveManager) == "function" then um:SaveToSaveManager(player) end
    player:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
    player:EvaluateItems()
    dbg(string.format("Damage reconciled: copies=%d previous=%.2f wanted=%.2f delta=%+.2f playerDamage=%.2f",
        copies, actual, wanted, delta, player.Damage))
end

local function readTemporaryFamiliarEffects(player)
    local effects = player:GetEffects()
    if not (effects and type(effects.GetEffectsList) == "function") then return {} end
    local ok, list = pcall(effects.GetEffectsList, effects)
    if not ok or not list then return {} end
    local blacklist = ConchBlessing.chronus.data.blacklist or {}
    local found = {}
    for i = 0, (tonumber(list.Size) or 0) - 1 do
        local effect = list:Get(i)
        local item = effect and effect.Item
        local count = effect and tonumber(effect.Count) or 0
        if item and item.Type == ItemType.ITEM_FAMILIAR and not blacklist[item.ID] and count > 0 then
            found[item.ID] = (found[item.ID] or 0) + count
        end
    end
    return found
end

-- Effect removal alone can leave already-spawned familiars alive. Exhausted
-- item effects can be matched through the optional provider's GetItemConfig;
-- leave genuine inventory copies and unrelated entity sources untouched.
local function removeTemporaryFamiliarEffects(player, found)
    local effects = player:GetEffects()
    for id, count in pairs(found) do
        effects:RemoveCollectibleEffect(id, count)
    end
    if next(found) then
        for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR)) do
            local fam = entity:ToFamiliar()
            if fam and fam.Player and GetPtrHash(fam.Player) == GetPtrHash(player)
                and type(fam.GetItemConfig) == "function" then
                local ok, item = pcall(fam.GetItemConfig, fam)
                if ok and item and found[item.ID] and player:GetCollectibleNum(item.ID, true) == 0
                    and effects:GetCollectibleEffectNum(item.ID) == 0 then
                    fam:Remove()
                end
            end
        end
        player:AddCacheFlags(CacheFlag.CACHE_FAMILIARS)
        player:EvaluateItems()
    end
end

local function takeTemporaryFamiliarEffects(player)
    local found = readTemporaryFamiliarEffects(player)
    removeTemporaryFamiliarEffects(player, found)
    return found
end

-- Record Manual uses before Chronus acquisition, in the triggering player's
-- floor save. Consumed counts are tombstones so a cache/room replay cannot pay
-- damage or conversion rewards again. Other sources are never swept here.
local function getManualSource(player)
    local floor = ConchBlessing.SaveManager.GetFloorSave(player)
    if not floor then return nil end
    floor.chronusManual = floor.chronusManual or { counts = {}, absorbed = {} }
    return floor.chronusManual
end

-- Room transitions can preserve/recreate an entity even after its collectible
-- effect was removed. Suppress that already-consumed source without paying it
-- again. No inventory or non-item familiar is removed by this callback.
function ConchBlessing.chronus._suppressConsumedManualFamiliar(fam)
    local player = fam.Player
    if not (player and player:HasCollectible(CHRONUS_ID)
        and type(fam.GetItemConfig) == "function") then return false end
    local ok, item = pcall(fam.GetItemConfig, fam)
    if not (ok and item) then return false end
    local source = getManualSource(player)
    if not (source and (tonumber(source.absorbed["fam_" .. item.ID]) or 0) > 0) then return false end
    if player:GetCollectibleNum(item.ID, true) > 0
        or player:GetEffects():GetCollectibleEffectNum(item.ID) > 0 then return false end
    fam:Remove()
    return true
end

local function captureManualUse(player, pending)
    local source = getManualSource(player)
    if not source then return end
    local changed = false
    for id, count in pairs(readTemporaryFamiliarEffects(player)) do
        local added = math.max(0, count - (pending.before[id] or 0))
        local delta = added - (pending.seen[id] or 0)
        if delta > 0 then
            local key = "fam_" .. id
            source.counts[key] = (tonumber(source.counts[key]) or 0) + delta
            pending.seen[id] = added
            changed = true
        end
    end
    if changed then ConchBlessing.SaveManager.Save() end
end

function ConchBlessing.chronus._clearManualGrants(player, rs)
    local floor = rs.tempFloor
    for key, count in pairs(type(floor) == "table" and floor.grants or {}) do
        local id = tonumber(key:match("^fam_(%d+)$"))
        local conversion = id and ConchBlessing.chronus.data.familiarToItemMap[id]
        local itemId = conversion and conversion.itemId
        if itemId then
            local granted = math.min(tonumber(count) or 0, familiarGrantCount(rs, id))
            local baseline = getItemBaseline(rs, itemId) or math.max(0,
                player:GetCollectibleNum(itemId, true) - itemGrantCount(rs, itemId))
            local removable = math.min(granted, math.max(0, player:GetCollectibleNum(itemId, true) - baseline))
            for _ = 1, removable do player:RemoveCollectible(itemId) end
            rs.itemGrants[key] = familiarGrantCount(rs, id) - granted
            if itemGrantCount(rs, itemId) == 0 then rs.itemGrantBaselines[itemBaselineKey(itemId)] = nil end
        end
    end
end

function ConchBlessing.chronus._scanManualFamiliars(player)
    if not player:HasCollectible(CHRONUS_ID) then return end
    local source = getManualSource(player)
    local rs = getRunSave(player)
    if not (source and rs) then return end
    if next(source.counts) == nil then return end
    local current = readTemporaryFamiliarEffects(player)
    local remove, found = {}, {}
    for key, total in pairs(source.counts) do
        local id = tonumber(key:match("^fam_(%d+)$"))
        local live = current[id] or 0
        local credited = tonumber(source.absorbed[key]) or 0
        local new = math.min(math.max(0, total - credited), live)
        if new > 0 then
            source.absorbed[key] = credited + new
            found[id] = new
        end
        local consumed = math.min(live, credited + new)
        if consumed > 0 then remove[id] = consumed end
    end
    removeTemporaryFamiliarEffects(player, remove)
    if next(found) then ConchBlessing.chronus._absorbTemporary(player, SOURCE_MANUAL, found) end
end

-- The Twins: count one absorbed familiar's copies again for this room. With no
-- absorbed familiar to double, the stand-in itself is kept for the room.
local function applyTwinsDouble(player, standInId)
    local candidates, seen = {}, {}
    for _, id in ipairs(getFloorPickPool()) do seen[id] = true end
    for id in pairs(ConchBlessing.chronus.data.absorbActions or {}) do seen[id] = true end
    for id in pairs(seen) do
        if ConchBlessing.chronus._getAbsorbedCount(player, id) > 0 then candidates[#candidates + 1] = id end
    end
    table.sort(candidates)
    if #candidates == 0 then
        local key = "fam_" .. tostring(standInId)
        roomTemp.counts[key] = (roomTemp.counts[key] or 0) + 1
        return standInId
    end
    local pick = candidates[player:GetTrinketRNG(TrinketType.TRINKET_THE_TWINS):RandomInt(#candidates) + 1]
    roomTemp.twins[pick] = (roomTemp.twins[pick] or 0) + 1
    return pick
end

function ConchBlessing.chronus._absorbTemporary(player, source, captured)
    if not (player and player:HasCollectible(CHRONUS_ID)) then return 0 end
    local rs = getRunSave(player)
    if not rs then return 0 end
    local found = captured or takeTemporaryFamiliarEffects(player)
    local ids = {}
    for id in pairs(found) do ids[#ids + 1] = id end
    table.sort(ids)
    local total = 0
    for _, id in ipairs(ids) do
        local count = found[id]
        local key = "fam_" .. tostring(id)
        total = total + count
        if source == SOURCE_MANUAL then
            local serial = tonumber(rs.floorSerial) or 0
            if type(rs.tempFloor) ~= "table" or rs.tempFloor.serial ~= serial then
                rs.tempFloor = { serial = serial, counts = {} }
            end
            rs.tempFloor.counts[key] = (tonumber(rs.tempFloor.counts[key]) or 0) + count
            local before = familiarGrantCount(rs, id)
            ConchBlessing.chronus._handleFamiliarToItemConversion(player, id,
                ConchBlessing.chronus._getEffectCount(player, id), count)
            rs.tempFloor.grants = rs.tempFloor.grants or {}
            rs.tempFloor.grants[key] = (tonumber(rs.tempFloor.grants[key]) or 0)
                + familiarGrantCount(rs, id) - before
        elseif source == SOURCE_LILITH then
            rs.tempPermanent = rs.tempPermanent or {}
            rs.tempPermanent[key] = (tonumber(rs.tempPermanent[key]) or 0) + count
        elseif source == SOURCE_TWINS then
            for _ = 1, count do
                local doubled = applyTwinsDouble(player, id)
                ConchBlessing.chronus._queueTransferEffect(player, doubled, false)
            end
        end
        -- SOURCE_BOX: the stand-in is swallowed; the room doubling is the payoff.
        if source ~= SOURCE_TWINS then
            for _ = 1, count do
                ConchBlessing.chronus._queueTransferEffect(player, id, false)
            end
        end
        dbg(string.format("Temporary familiar absorbed: %s x%d (source %s)", tostring(id), count, source))
    end
    if total > 0 then
        bump("tempAbsorbed", total)
        ConchBlessing.SaveManager.Save()
        clearChronusRuntime(player)
        refreshEffectCaches()
    end
    return total
end

-- A source may add its familiar after its own callback returns; one rescan on
-- the player's next update covers that and is then dropped.
local function scanNowAndNextUpdate(player, source)
    local found = ConchBlessing.chronus._absorbTemporary(player, source)
    pendingTempScans[GetPtrHash(player)] = { source = source, foundBefore = found }
end

function ConchBlessing.chronus._processPendingTempScans(player)
    local key = GetPtrHash(player)
    local manual = pendingManualScans[key]
    if manual then
        pendingManualScans[key] = nil
        captureManualUse(player, manual)
    end
    ConchBlessing.chronus._scanManualFamiliars(player)
    local pending = pendingTempScans[key]
    if not pending then return end
    pendingTempScans[key] = nil
    local found = ConchBlessing.chronus._absorbTemporary(player, pending.source)
    if found + (pending.foundBefore or 0) == 0 and pending.source ~= SOURCE_TWINS then
        dbg("No temporary familiar effect found after " .. pending.source .. "; vanilla behaviour kept")
    end
end

function ConchBlessing.chronus._resetRoomTemporary()
    local had = roomTemp.double > 0 or next(roomTemp.counts) ~= nil or next(roomTemp.twins) ~= nil
    roomTemp.double = 0
    for key in pairs(roomTemp.counts) do roomTemp.counts[key] = nil end
    for key in pairs(roomTemp.twins) do roomTemp.twins[key] = nil end
    if not had then return end
    local game = Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local holder = game:GetPlayer(i)
        if holder and holder:HasCollectible(CHRONUS_ID) then
            clearChronusRuntime(holder)
        end
    end
    refreshEffectCaches()
end

function ConchBlessing.chronus._scanTwins(player)
    if player:HasTrinket(TrinketType.TRINKET_THE_TWINS) then
        scanNowAndNextUpdate(player, SOURCE_TWINS)
    end
end

--- Chronus lost: hand back the non-item familiars it was holding.
function ConchBlessing.chronus._restoreNonItemFamiliars(player, rs)
    local flies = math.max(0, math.floor(tonumber(rs.prettyFlies) or 0))
    if flies > 0 and type(player.AddPrettyFly) == "function" then
        for _ = 1, flies do
            player:AddPrettyFly()
            ConchBlessing.chronus._queueTransferEffect(player, CollectibleType.COLLECTIBLE_HALO_OF_FLIES, true)
        end
    end
    local restored = flies > 0
    local function giveBack(counts)
        if type(counts) ~= "table" then return end
        for key, value in pairs(counts) do
            local id = tonumber(tostring(key):match("^fam_(%d+)$"))
            local count = math.max(0, math.floor(tonumber(value) or 0))
            if id and count > 0 then
                player:GetEffects():AddCollectibleEffect(id, false, count)
                restored = true
                for _ = 1, count do
                    ConchBlessing.chronus._queueTransferEffect(player, id, true)
                end
            end
        end
    end
    giveBack(rs.tempPermanent)
    if type(rs.tempFloor) == "table" and rs.tempFloor.serial == (tonumber(rs.floorSerial) or 0) then
        giveBack(rs.tempFloor.counts)
    end
    local source = getManualSource(player)
    if source then source.absorbed = {} end
    roomTemp.double = 0
    for key in pairs(roomTemp.counts) do roomTemp.counts[key] = nil end
    for key in pairs(roomTemp.twins) do roomTemp.twins[key] = nil end
    if restored then
        player:AddCacheFlags(CacheFlag.CACHE_FAMILIARS)
    end
end

local function onUseBoxOfFriends(_, _item, _rng, player)
    if not (player and player:HasCollectible(CHRONUS_ID)) then return end
    roomTemp.double = roomTemp.double + 1
    bump("boxUses")
    ConchBlessing.chronus._queueTransferEffect(player, CollectibleType.COLLECTIBLE_BOX_OF_FRIENDS, false)
    scanNowAndNextUpdate(player, SOURCE_BOX)
    -- Pinned stand-ins are rebuilt at the doubled count on the next update.
    clearChronusRuntime(player)
    refreshEffectCaches()
end

local function onPreUseMonsterManual(_, _item, _rng, player)
    if not player then return end
    pendingManualScans[GetPtrHash(player)] = { before = readTemporaryFamiliarEffects(player), seen = {} }
end

local function onUseMonsterManual(_, _item, _rng, player)
    if not player then return end
    local pending = pendingManualScans[GetPtrHash(player)]
    if pending then captureManualUse(player, pending) end
end

local function onUseSoulOfLilith(_, _card, player)
    if player and player:HasCollectible(CHRONUS_ID) then
        scanNowAndNextUpdate(player, SOURCE_LILITH)
    end
end

-- REPENTOGON MC_PRE_USE_PILL runs inside the pill effect, after the pill was
-- consumed, so cancelling it only skips the fly. A horse pill counts twice.
local function onPreUsePrettyFly(_, _pillEffect, pillColor, player)
    if not (player and player:HasCollectible(CHRONUS_ID)) then return end
    local rs = getRunSave(player)
    if not rs then return end
    local flies = ((tonumber(pillColor) or 0) & PillColor.PILL_GIANT_FLAG) ~= 0 and 2 or 1
    rs.prettyFlies = (tonumber(rs.prettyFlies) or 0) + flies
    ConchBlessing.SaveManager.Save()
    bump("prettyFlies", flies)
    for _ = 1, flies do
        ConchBlessing.chronus._queueTransferEffect(player, CollectibleType.COLLECTIBLE_HALO_OF_FLIES, false)
    end
    return true
end

local function countPedestals()
    return #Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE)
end

local function onPreUseSacrificialAltar(_, _item, _rng, player)
    if player and player:HasCollectible(CHRONUS_ID) then
        altarSnapshots[GetPtrHash(player)] = countPedestals()
    end
end

-- The altar sacrifices up to 2 familiars of its own choosing (owned items and
-- familiar entities alike) and spawns one devil item each, synchronously. The
-- items it spawned are its count; the rest of the 2 comes out of the absorbed
-- pool, each paying out a devil-pool item.
local function onUseSacrificialAltar(_, _item, rng, player)
    if not player then return end
    local key = GetPtrHash(player)
    local before = altarSnapshots[key]
    altarSnapshots[key] = nil
    if not player:HasCollectible(CHRONUS_ID) then return end
    local rs = getRunSave(player)
    if not (rs and rs.absorbed) then return end
    local takenByVanilla = before and math.max(0, countPedestals() - before) or 0
    local slots = ALTAR_MAX_SACRIFICES - takenByVanilla
    if slots <= 0 then return end

    local ids = {}
    for entryKey, entry in pairs(rs.absorbed) do
        local id = type(entry) == "table" and (entry.id or tonumber(tostring(entryKey):match("^fam_(%d+)$"))) or nil
        if id then ids[#ids + 1] = id end
    end
    table.sort(ids)
    local copies = {}
    for _, id in ipairs(ids) do
        for _ = 1, ConchBlessing.chronus._getAbsorbedCount(player, id) do copies[#copies + 1] = id end
    end
    local picked = pickRandomCopies(copies, slots, function(n) return rng:RandomInt(n) end)
    local sacrificed = releaseCopies(player, rs, picked, false)

    local game = Game()
    local room = game:GetRoom()
    for i = 1, sacrificed do
        local seed = rng:Next()
        if seed == 0 then seed = 1 end
        local itemId = game:GetItemPool():GetCollectible(ItemPoolType.POOL_DEVIL, true, seed)
        local position = room:FindFreePickupSpawnPosition(player.Position + Vector((i - 1.5) * 80, 80), 0, true)
        game:Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, position, Vector.Zero, nil, itemId, seed)
    end
    bump("altarSacrifices", sacrificed)
end

-- ------------------------------------------------------------ transfer visual
-- Absorbing shows the familiar's collectible above the player, crumbles it into
-- dust from the top down and pulls the grains into the body in a swirl; a
-- familiar leaving plays the same in reverse. Cosmetic only: ticks advance in
-- MC_POST_UPDATE and nothing reads them back.
local TRANSFER_ANM2 = "gfx/005.100_collectible.anm2"
local TRANSFER_ANIMATION = "PlayerPickup"
local TRANSFER_APPEAR = 10
local TRANSFER_HOLD = 8
-- Grains start crumbling over this many updates (top row first, with jitter)...
local TRANSFER_CRUMBLE = 16
-- ...and each one takes FLIGHT plus up to FLIGHT_JITTER updates to reach the body.
local TRANSFER_FLIGHT = 16
local TRANSFER_FLIGHT_JITTER = 6
local TRANSFER_TOTAL = TRANSFER_APPEAR + TRANSFER_HOLD + TRANSFER_CRUMBLE + TRANSFER_FLIGHT + TRANSFER_FLIGHT_JITTER
-- Share of a grain's flight spent floating loose before the pull starts.
local TRANSFER_FLOAT_SHARE = 0.35
local TRANSFER_FLOAT_DISTANCE = 6
local TRANSFER_FLOAT_JITTER = 10
local TRANSFER_SWIRL = 0.45
local TRANSFER_STAGGER = 8
local TRANSFER_MAX_PER_PLAYER = 12
local TRANSFER_ICON_CENTER_Y = -46 -- screen px above the player's feet
local TRANSFER_BODY_Y = -14
-- PlayerPickup draws the 32x32 icon at (0, -8) with a centred pivot, so it spans
-- (-16, -24) to (16, 8) around the render position; grains are 2x2 cuts of it.
local TRANSFER_ICON_SIZE = 32
local TRANSFER_GRAIN = 2
local TRANSFER_GRID = TRANSFER_ICON_SIZE // TRANSFER_GRAIN
local TRANSFER_INTACT_COLOR = Color(1, 1, 1, 1, 0, 0, 0)
local transferEffects = {}

local function newTransferSprite(itemId)
    local config = Isaac.GetItemConfig():GetCollectible(itemId)
    local gfx = config and config.GfxFileName
    if type(gfx) ~= "string" or gfx == "" then return nil end
    local sprite = Sprite()
    sprite:Load(TRANSFER_ANM2, false)
    sprite:ReplaceSpritesheet(1, gfx)
    sprite:LoadGraphics()
    sprite:SetFrame(TRANSFER_ANIMATION, 0)
    return sprite
end

-- Cosmetic per-grain jitter from an integer hash, so the visual never draws on
-- math.random or any game RNG.
local function grainNoise(seed, i, j, salt)
    local h = (seed ~ (i * 374761393) ~ (j * 668265263) ~ (salt * 2246822519)) & 0x7fffffff
    h = ((h ~ (h >> 13)) * 1274126177) & 0x7fffffff
    return (h ~ (h >> 16)) / 0x7fffffff
end

local function buildGrains(seed)
    local grains = {}
    local half = TRANSFER_ICON_SIZE / 2
    for j = 0, TRANSFER_GRID - 1 do
        for i = 0, TRANSFER_GRID - 1 do
            local r1, r2, r3 = grainNoise(seed, i, j, 1), grainNoise(seed, i, j, 2), grainNoise(seed, i, j, 3)
            local cx = TRANSFER_GRAIN * i + TRANSFER_GRAIN / 2
            local cy = TRANSFER_GRAIN * j + TRANSFER_GRAIN / 2
            -- Offset from the icon centre, and from the sprite render position.
            local home = Vector(cx - half, cy - half)
            local angle = math.atan(home.Y, home.X) + (r2 - 0.5) * 1.4
            local float = Vector(math.cos(angle), math.sin(angle) - 0.6)
                * (TRANSFER_FLOAT_DISTANCE + r3 * TRANSFER_FLOAT_JITTER)
            -- Plain numbers: the render loop allocates one Vector per grain.
            grains[#grains + 1] = {
                hx = home.X, hy = home.Y,
                ox = cx - half, oy = cy - half - 8,
                fx = float.X, fy = float.Y,
                topLeft = Vector(TRANSFER_GRAIN * i, TRANSFER_GRAIN * j),
                bottomRight = Vector(TRANSFER_ICON_SIZE - TRANSFER_GRAIN * (i + 1),
                    TRANSFER_ICON_SIZE - TRANSFER_GRAIN * (j + 1)),
                delay = (j / (TRANSFER_GRID - 1)) * (TRANSFER_CRUMBLE * 0.65) + r1 * (TRANSFER_CRUMBLE * 0.35),
                flight = TRANSFER_FLIGHT + r2 * TRANSFER_FLIGHT_JITTER,
                swirl = (r1 - 0.5) * 2 * TRANSFER_SWIRL,
                sparkle = r3 > 0.9,
            }
        end
    end
    return grains
end

function ConchBlessing.chronus._queueTransferEffect(player, itemId, reverse)
    if not player then return end
    local hash = GetPtrHash(player)
    local queued, startIn = 0, 0
    for _, effect in ipairs(transferEffects) do
        if effect.hash == hash then
            queued = queued + 1
            local ready = effect.startIn > 0 and (effect.startIn + TRANSFER_STAGGER) or (TRANSFER_STAGGER - effect.tick)
            if ready > startIn then startIn = ready end
        end
    end
    if queued >= TRANSFER_MAX_PER_PLAYER then return end
    local ok, sprite = pcall(newTransferSprite, itemId)
    if not ok or not sprite then return end
    local seed = (tonumber(itemId) or 0) * 7919 + Game():GetFrameCount() * 104729 + #transferEffects * 31
    transferEffects[#transferEffects + 1] = {
        player = player, hash = hash, sprite = sprite, grains = buildGrains(seed),
        reverse = reverse == true, startIn = startIn, tick = 0,
    }
end

local function easeOut(x) return 1 - (1 - x) * (1 - x) end
local function easeIn(x) return x * x end

local function renderTransfer(effect)
    local player = effect.player
    local sprite = effect.sprite
    local base = Isaac.WorldToScreen(player.Position + player.PositionOffset)
    local t = effect.reverse and (TRANSFER_TOTAL - effect.tick) or effect.tick
    local iconCenter = base + Vector(0, TRANSFER_ICON_CENTER_Y)

    if t < TRANSFER_APPEAR + TRANSFER_HOLD then
        local a = math.min(1, t / TRANSFER_APPEAR)
        local scale = 0.4 + 0.6 * easeOut(a)
        local bob = t > TRANSFER_APPEAR and math.sin((t - TRANSFER_APPEAR) * 0.6) or 0
        sprite.Scale = Vector(scale, scale)
        sprite.Color = Color(1, 1, 1, a, 0, 0, 0)
        sprite:Render(iconCenter + Vector(0, 8 * scale + bob))
        return
    end

    sprite.Scale = Vector.One
    local s = t - TRANSFER_APPEAR - TRANSFER_HOLD
    local cx, cy = iconCenter.X, iconCenter.Y
    local bx, by = base.X, base.Y + TRANSFER_BODY_Y
    local share = TRANSFER_FLOAT_SHARE
    local intact = false
    for _, grain in ipairs(effect.grains) do
        local u = s - grain.delay
        if u < grain.flight then
            local hx, hy = cx + grain.hx, cy + grain.hy
            local x, y = hx, hy
            if u <= 0 then
                if not intact then
                    sprite.Color = TRANSFER_INTACT_COLOR
                    intact = true
                end
            else
                local p = u / grain.flight
                local alpha, glow
                if p < share then
                    local e = easeOut(p / share)
                    x, y = hx + grain.fx * e, hy + grain.fy * e
                    alpha, glow = 1, 0.35 * p / share
                else
                    -- Quadratic curve from the loose grain to the body, bent
                    -- sideways so the dust swirls in instead of flying straight.
                    local q = easeIn((p - share) / (1 - share))
                    local lx, ly = hx + grain.fx, hy + grain.fy
                    local dx, dy = bx - lx, by - ly
                    local kx, ky = lx + dx * 0.5 - dy * grain.swirl, ly + dy * 0.5 + dx * grain.swirl
                    local ax, ay = lx + (kx - lx) * q, ly + (ky - ly) * q
                    local ex, ey = kx + (bx - kx) * q, ky + (by - ky) * q
                    x, y = ax + (ex - ax) * q, ay + (ey - ay) * q
                    alpha, glow = 1 - 0.85 * q, 0.35 + 0.45 * q
                end
                if grain.sparkle then glow = glow + 0.4 end
                sprite.Color = Color(1, 1, 1, alpha, glow * 0.55, glow * 0.25, glow)
                intact = false
            end
            sprite:Render(Vector(x - grain.ox, y - grain.oy), grain.topLeft, grain.bottomRight)
        end
    end
end

local function updateTransferEffects()
    local sfx = SFXManager()
    local i = 1
    while i <= #transferEffects do
        local effect = transferEffects[i]
        local alive = effect.player and effect.player:Exists()
        if alive then
            if effect.startIn > 0 then
                effect.startIn = effect.startIn - 1
            else
                if effect.tick == 0 and effect.reverse then
                    sfx:Play(SoundEffect.SOUND_SUMMONSOUND, 0.6)
                end
                effect.tick = effect.tick + 1
                if effect.tick == TRANSFER_TOTAL and not effect.reverse then
                    sfx:Play(SoundEffect.SOUND_VAMP_GULP, 0.6)
                end
            end
        end
        if not alive or effect.tick >= TRANSFER_TOTAL then
            table.remove(transferEffects, i)
        else
            i = i + 1
        end
    end
end

local function updateStompVisuals()
    local i = 1
    while i <= #stompVisuals do
        local visual = stompVisuals[i]
        visual.sprite:Update()
        if visual.sprite:IsFinished(STOMP_ANIMATION) then
            table.remove(stompVisuals, i)
        else
            i = i + 1
        end
    end
end

function ConchBlessing.chronus._clearRoomVisuals()
    stompVisuals = {}
end

ConchBlessing.chronus.onPostUpdate = function()
    processPendingHurts()
    if #transferEffects > 0 then updateTransferEffects() end
    if #stompVisuals > 0 then updateStompVisuals() end
end

ConchBlessing.chronus.onPostRender = function()
    if #transferEffects == 0 and #stompVisuals == 0 then return end
    if Game():IsPaused() then return end
    for _, visual in ipairs(stompVisuals) do
        visual.sprite:Render(Isaac.WorldToScreen(visual.position))
    end
    for _, effect in ipairs(transferEffects) do
        if effect.startIn <= 0 and effect.player:Exists() then
            renderTransfer(effect)
        end
    end
end

ConchBlessing.chronus.onPreGameExit = function()
    ConchBlessing.chronus._runReady = false
    roomTemp.double = 0
    for key in pairs(roomTemp.counts) do roomTemp.counts[key] = nil end
    for key in pairs(roomTemp.twins) do roomTemp.twins[key] = nil end
    for key in pairs(pendingTempScans) do pendingTempScans[key] = nil end
    for key in pairs(pendingManualScans) do pendingManualScans[key] = nil end
    for key in pairs(altarSnapshots) do altarSnapshots[key] = nil end
    pendingHurts = {}
    transferEffects = {}
    stompVisuals = {}
end

-- Test/diagnostic hooks for the RNG and Chronus probes.
ConchBlessing.chronus._test = {
    getProjectileBlockChance = getProjectileBlockChance,
    getSpawnChance = getSpawnChance,
    getStackedChance = getStackedChance,
    pickFromPool = pickFromPool,
    pickRandomCopies = pickRandomCopies,
    getFloorPickPool = getFloorPickPool,
    readTemporaryFamiliarEffects = readTemporaryFamiliarEffects,
    PROJECTILE_BLOCK_PERCENT = PROJECTILE_BLOCK_PERCENT,
    PRETTY_FLY_BLOCK_PERCENT = PRETTY_FLY_BLOCK_PERCENT,
    SPAWN_CHANCE_PER_STACK = SPAWN_CHANCE_PER_STACK,
    PROC_CHANCE_PERCENT = PROC_CHANCE_PERCENT,
    CLEAR_REWARD_INTERVAL = CLEAR_REWARD_INTERVAL,
}

-- EID: every barrier familiar's synergy shows the live total through this token.
ConchBlessing.EIDDynamicTokens = ConchBlessing.EIDDynamicTokens or {}
ConchBlessing.EIDDynamicTokens.CHRONUS_BLOCK = function()
    local player = findChronusOwner() or Isaac.GetPlayer(0)
    if not player then return nil end
    local chance = getProjectileBlockChance(getProjectileBlockCounts(player),
        ConchBlessing.chronus._getPrettyFlyCount(player))
    return string.format("%g%%", math.floor(chance * 1000 + 0.5) / 10)
end

-- The temporary-familiar sources are other items, cards and pills, so they are
-- registered here with their own filters: ItemData callbacks filter by Chronus's id.
ConchBlessing:AddCallback(ModCallbacks.MC_USE_ITEM, onUseBoxOfFriends, CollectibleType.COLLECTIBLE_BOX_OF_FRIENDS)
ConchBlessing:AddCallback(ModCallbacks.MC_USE_ITEM, onUseMonsterManual, CollectibleType.COLLECTIBLE_MONSTER_MANUAL)
ConchBlessing:AddCallback(ModCallbacks.MC_PRE_USE_ITEM, onPreUseMonsterManual, CollectibleType.COLLECTIBLE_MONSTER_MANUAL)
ConchBlessing:AddCallback(ModCallbacks.MC_PRE_USE_ITEM, onPreUseSacrificialAltar, CollectibleType.COLLECTIBLE_SACRIFICIAL_ALTAR)
ConchBlessing:AddCallback(ModCallbacks.MC_USE_ITEM, onUseSacrificialAltar, CollectibleType.COLLECTIBLE_SACRIFICIAL_ALTAR)
ConchBlessing:AddCallback(ModCallbacks.MC_USE_CARD, onUseSoulOfLilith, Card.CARD_SOUL_LILITH)
if type(ModCallbacks.MC_PRE_USE_PILL) == "number" then
    ConchBlessing:AddCallback(ModCallbacks.MC_PRE_USE_PILL, onPreUsePrettyFly, PillEffect.PILLEFFECT_PRETTY_FLY)
end

-- POST_ADD_COLLECTIBLE: Vanishing Twin effect - DISABLED (causes conflicts with other mods)
-- TODO: Re-implement in a safer way later
-- ConchBlessing.chronus.onAddCollectible = function(_, player, collectibleType, charge, firstTime, slot, varData)
--     -- Vanishing Twin duplication logic
-- end
