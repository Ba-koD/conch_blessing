-- ItemData table
-- available attributes:
--   type: "passive" | "active" | "familiar" | "null" - item type
--   id: Isaac.GetItemIdByName("item name") - item ID (generated from XML)
--   name, description, eid: player-facing text is not written here. It lives in
--     scripts/locale/<lang>.lua under items.<KEY>, and Locale.applyItemData fills
--     these fields as { en = ..., kr = ... } right after this table is built
--   synergies: { [{ id = CollectibleType.COLLECTIBLE_X, type = "collectible" }] = "line", ... }
--     - each value names its line under items.<KEY>.synergies in the locale files
--   pool: { RoomType.ROOM_XXX, ... } - item pools it appears in (can specify multiple pools as an array)
--     possible pools: ROOM_DEFAULT, ROOM_SHOP, ROOM_TREASURE, ROOM_BOSS, ROOM_MINIBOSS, ROOM_SECRET, ROOM_ARCADE, ROOM_CURSE, ROOM_CHALLENGE, ROOM_LIBRARY, ROOM_SACRIFICE, ROOM_DEVIL, ROOM_ANGEL, ROOM_DUNGEON, ROOM_BOSSRUSH, ROOM_ISAACS, ROOM_BARREN, ROOM_CHEST, ROOM_DICE, ROOM_BLACK_MARKET, ROOM_GREED_EXIT, ROOM_PLANETARIUM, ROOM_TELEPORTER, ROOM_TELEPORTER_EXIT, ROOM_SECRET_EXIT, ROOM_BLUE, ROOM_ULTRASECRET
--     pool can be specified as:
--       - RoomType.ROOM_XXX (uses default values: weight=1.0, decrease_by=1, remove_on=0.1)
--       - {RoomType.ROOM_XXX, weight=1.0, decrease_by=1, remove_on=0.1} (custom values)
--   weight: number - item weight in pool (higher number means more frequent appearance)
--   DecreaseBy: number - weight decrease when item is selected from pool
--   RemoveOn: number - probability of item being removed from pool (0.0-1.0)
--   quality: number - item quality (0-4, 4 is highest quality)
--   tags: "tag1 tag2" - item tags (multiple tags must be separated with a space)
--     possible tags (from IsaacDocs items.xml):
--       dead - Dead things (for the Parasite unlock)
--       syringe - Syringes (for Little Baggy and the Spun! transformation)
--       mom - Mom's things (for Mom's Contact and the Yes Mother? transformation)
--       tech - Technology items (for the Technology Zero unlock)
--       battery - Battery items (for the Jumper Cables unlock)
--       guppy - Guppy items (Guppy transformation)
--       fly - Fly items (Beelzebub transformation)
--       bob - Bob items (Bob transformation)
--       mushroom - Mushroom items (Fun Guy transformation)
--       baby - Baby items (Conjoined transformation)
--       angel - Angel items (Seraphim transformation)
--       devil - Devil items (Leviathan transformation)
--       poop - Poop items (Oh Shit transformation)
--       book - Book items (Book Worm transformation)
--       spider - Spider items (Spider Baby transformation)
--       quest - Quest item (cannot be rerolled or randomly obtained)
--       monstermanual - Can be spawned by Monster Manual
--       nogreed - Cannot appear in Greed Mode
--       food - Food item (for Binge Eater)
--       tearsup - Tears up item (for Lachryphagy unlock detection)
--       offensive - Whitelisted item for Tainted Lost
--       nokeeper - Blacklisted item for Keeper/Tainted Keeper
--       nolostbr - Blacklisted item for Lost's Birthright
--       stars - Star themed items (for the Planetarium unlock)
--       summonable - Summonable items (for Lemegeton)
--       nocantrip - Can't be obtained in Cantripped challenge
--       wisp - Active items that have wisps attached to them (automatically set)
--       uniquefamiliar - Unique familiars that cannot be duplicated
--       nochallenge - Items that shouldn't be obtainable in challenges
--       nodaily - Items that shouldn't be obtainable in daily runs
--       lazarusshared - Items that should be shared between Tainted Lazarus' forms
--       lazarussharedglobal - Items that should be shared between Tainted Lazarus' forms but only through global checks
--       noeden - Items that can't be randomly rolled
--   cache: "cache flag" - cache flag (all, damage, firedelay, shotspeed, range, tearflag, etc.)
--   hidden: true/false - hidden item
--   devilprice: number - price in devil room (heart count)
--   shopprice: number - price in shop (coin count)
--   maxcharges: number - max charges for active item
--   chargetype: "type" - charge type (normal, special)
--   hearts: number - heart change amount (can be negative)
--   maxhearts: number - max heart change amount (can be negative)
--   blackhearts: number - black heart count
--   soulhearts: number - soul heart count
--   script: "script path" - item effect script file path (default path is used if omitted)
--   callbacks: { callback functions } - callback functions to automatically register
--     pickup: legacy MC_POST_PICKUP_INIT alias; not a collectible-acquisition event
--     use: "function name" - called when item is used
--     evaluateCache: "function name" - called when cache is calculated
--     tearHit: "function name" - called when tear hits
--     tearCollision: "function name" - called when tear collides
--     gameStarted: "function name" - called when game starts
--   WorkingNow: true/false - item is working now

-- Trinkets
-- EID golden/mombox replacement config
-- specials supports multiple modes depending on value type:
--   1) Numeric base (multiply mode):
--      - Put a number in normal only (e.g., 0.006). EID auto applies x2 (golden), x3 (golden+Mom's Box)
--      Example:
--          specials = { normal = 0.006 }
--   2) String per-state (replace mode):
--      - Use strings for normal / moms_box / both to replace directly per state
--      Example:
--          specials = { normal = "0.006", moms_box = "0.012", both = "0.018" }
--   3) Array per-state (order replace):
--      - Use arrays to replace numbers IN ORDER of appearance in the text
--      - Moms Box / Both are highlighted gold automatically
--      Example (Korean only, in scripts/locale/kr.lua under items.<KEY>):
--          specials = { normal = { "0.006", "60" }, moms_box = { "0.012", "30" }, both = { "0.018", "20" } }
--   4) Append mode (extra line, base text untouched):
--      - Use `append` with 1-3 strings in { golden, moms_box, both } order
--      - EID prefixes the chosen line with "#{{ColorGold}}" itself, so do not add one
--      - Use this when the golden effect is a NEW behaviour rather than a bigger number
--      Example (per language, in scripts/locale/<lang>.lua under items.<KEY>):
--          specials = { append = { "25% chance ...", "25% chance ...", "33% chance ..." } }
--      `append` wins over normal/moms_box/both when both are present on the same entry.
-- Language scoping:
--   - specials in ItemData apply to all languages as default
--   - items.<KEY>.specials in scripts/locale/<lang>.lua overrides ONLY that language
--     (Locale.applyItemData stores it as specials.<lang>)

-- Conch's Blessing - Items System
-- Item information and callback management system

-- Load template system for upgrade animations
ConchBlessing.template = require("scripts.template")

ConchBlessing.printDebug("Item system loaded!")

-- check if ModCallbacks is defined
if not ModCallbacks then
    ConchBlessing.printError("Error: ModCallbacks is not defined!")
    return
end

-- define ItemData table
ConchBlessing.ItemData = {
    -- Collectibles
    LIVE_EYE = {
        type = "passive",
        id = Isaac.GetItemIdByName("Live Eye"),
        pool = {
            -- Use default values (weight=1.0, decrease_by=1, remove_on=0.1)
            RoomType.ROOM_ANGEL,
            RoomType.ROOM_SECRET,
            RoomType.ROOM_SUPERSECRET,
            RoomType.ROOM_BLUE,
            -- Use custom values
            -- { RoomType.ROOM_ARCADE, weight=1, decrease_by=1, remove_on=0.1 },
        },
        quality = 4,
        tags = "offensive",
        cache = "damage",
        hidden = false,
        shopprice = 20, -- shop price (coin)
        devilprice = 2, -- devil price (heart)
        maxcharges = 0,
        chargetype = "normal",
        hearts = 0,
        maxhearts = 0,
        blackhearts = 0,
        soulhearts = 0,
        origin = { id = CollectibleType.COLLECTIBLE_DEAD_EYE, type = "collectible" }, -- original item information
        flag = "positive", -- match Magic Conch result type
        script = "scripts/items/collectibles/live_eye",
        callbacks = {
            pickup = "liveeye.onPickup",
            evaluateCache = "liveeye.onEvaluateCache",
            postPlayerUpdate = "liveeye.onPlayerUpdate",
            fireTear = "liveeye.onFireTear",
            tearCollision = "liveeye.onTearCollision",
            tearRemoved = "liveeye.onTearRemoved",
            gameStarted = "liveeye.onGameStarted",
        },
        synergies = {
            [{ id = CollectibleType.COLLECTIBLE_ROCK_BOTTOM, type = "collectible" }] = "rock_bottom",
        }
    },
    VOID_DAGGER = {
        type = "passive",
        id = Isaac.GetItemIdByName("Void Dagger"),
        pool = {
            RoomType.ROOM_DEVIL,
            RoomType.ROOM_TREASURE
        },
        quality = 4,
        tags = "offensive devil",
        cache = "damage firedelay",
        hidden = false,
        shopprice = 20,
        devilprice = 2,
        origin = { id = CollectibleType.COLLECTIBLE_ATHAME, type = "collectible" },
        flag = "neutral",
        script = "scripts/items/collectibles/void_dagger",
        callbacks = {
            tearCollision = "voiddagger.onTearCollision",
            postEntityTakeDmg = "voiddagger.onPostEntityTakeDamage",
            postPlayerUpdate = "voiddagger.onPlayerUpdate"
        },
    },
    ETERNAL_FLAME = {
        type = "passive",
        id = Isaac.GetItemIdByName("Eternal Flame"),
        pool = {
            RoomType.ROOM_ANGEL,
            RoomType.ROOM_ULTRASECRET
        },
        quality = 4,
        tags = "offensive angel",
        cache = "damage firedelay",
        hidden = false,
        shopprice = 20,
        devilprice = 2,
        origin = { id = CollectibleType.COLLECTIBLE_BLACK_CANDLE, type = "collectible" },
        flag = "positive",
        script = "scripts/items/collectibles/eternal_flame",
        callbacks = {
            pickup = "eternalflame.onPickup",
            postPlayerUpdate = "eternalflame.onPlayerUpdate",
            evaluateCache = "eternalflame.onEvaluateCache",
            postNewLevel = "eternalflame.onNewLevel",
            postNewRoom = "eternalflame.onNewRoom",
            update = "eternalflame.onUpdate",
            gameStarted = "eternalflame.onGameStarted"
        },
    },
    POWER_TRAINING = {
        type = "active",
        id = Isaac.GetItemIdByName("Power Training"),
        pool = {
            RoomType.ROOM_TREASURE,
            RoomType.ROOM_SHOP,
            RoomType.ROOM_ANGEL
        },
        quality = 4,
        tags = "offensive",
        cache = "damage firedelay range luck",
        hidden = false,
        shopprice = 20,
        devilprice = 2,
        maxcharges = 12,
        chargetype = "normal",
        initcharge = 6,
        origin = { id = CollectibleType.COLLECTIBLE_EXPERIMENTAL_TREATMENT, type = "collectible" },
        flag = "positive",
        script = "scripts/items/collectibles/power_training",
        callbacks = {
            use = "powertraining.onUseItem",
            evaluateCache = "powertraining.onEvaluateCache",
            gameStarted = "powertraining.onGameStarted",
        },
    },
    ORAL_STEROIDS = {
        type = "passive",
        id = Isaac.GetItemIdByName("Oral Steroids"),
        pool = {
            RoomType.ROOM_DEVIL,
            RoomType.ROOM_CURSE,
            RoomType.ROOM_BLACK_MARKET,
            RoomType.ROOM_SECRET,
            RoomType.ROOM_SUPERSECRET
        },
        quality = 2,
        tags = "offensive",
        cache = "damage firedelay range luck",
        hidden = false,
        shopprice = 20,
        devilprice = 1,
        origin = { id = CollectibleType.COLLECTIBLE_EXPERIMENTAL_TREATMENT, type = "collectible" },
        flag = "neutral",
        script = "scripts/items/collectibles/oral_steroids",
        callbacks = {
            evaluateCache = "oralsteroids.onEvaluateCache",
            postPlayerUpdate = "oralsteroids.onPlayerUpdate",
            gameStarted = "oralsteroids.onGameStarted",
        },
    },
    INJECTABLE_STEROIDS = {
        type = "active",
        id = Isaac.GetItemIdByName("Injectable Steroids"),
        pool = {
            RoomType.ROOM_DEVIL,
            RoomType.ROOM_CURSE,
            RoomType.ROOM_BLACK_MARKET
        },
        quality = 3,
        tags = "offensive",
        cache = "damage firedelay range luck",
        hidden = false,
        shopprice = 15,
        devilprice = 2,
        maxcharges = 12,
        chargetype = "normal",
        initcharge = 6,
        origin = { id = CollectibleType.COLLECTIBLE_EXPERIMENTAL_TREATMENT, type = "collectible" },
        flag = "negative",
        script = "scripts/items/collectibles/injectable_steroids",
        callbacks = {
            use = "injectablsteroids.onUseItem",
            evaluateCache = "injectablsteroids.onEvaluateCache",
            gameStarted = "injectablsteroids.onGameStarted",
            newLevel = "injectablsteroids.onNewLevel",
            update = "injectablsteroids.onUpdate",
            postRoomClear = "injectablsteroids.onRoomClear"
        },
    },
    RAT = {
        WorkingNow = true,
        type = "passive",
        id = Isaac.GetItemIdByName("Rat"),
    },
    OX = {
        WorkingNow = true,
        type = "passive",
        id = Isaac.GetItemIdByName("Ox"),
    },
    TIGER = {
        WorkingNow = true,
        type = "passive",
        id = Isaac.GetItemIdByName("Tiger"),
    },
    RABBIT = {
        WorkingNow = true,
        type = "passive",
        id = Isaac.GetItemIdByName("Rabbit"),
    },
    DRAGON = {
        type = "passive",
        id = Isaac.GetItemIdByName("Dragon"),
        pool = {
            RoomType.ROOM_TREASURE,
            RoomType.ROOM_PLANETARIUM
        },
        synergies = {
            [{type = "collectible", name = "Dragon" }] = "dragon",
        },
        quality = 4,
        tags = "offensive",
        cache = "flying tearflag",
        hidden = false,
        shopprice = 20,
        devilprice = 2,
        origin = { id = CollectibleType.COLLECTIBLE_TAURUS, type = "collectible" },
        flag = "positive",
        script = "scripts/items/collectibles/dragon",
        callbacks = {
            evaluateCache = "dragon.onEvaluateCache",
            weaponFired = "dragon.onWeaponFired",
            postLaserUpdate = "dragon.onPostLaserUpdate",
            postEffectUpdate = "dragon.onPostEffectUpdate",
            postPlayerUpdate = "dragon.onPlayerUpdate",
            postNewRoom = "dragon.onNewRoom",
            gameStarted = "dragon.onGameStarted"
        },
    },
    SNAKE = {
        WorkingNow = true,
        type = "passive",
        id = Isaac.GetItemIdByName("Snake"),
    },
    HORSE = {
        WorkingNow = true,
        type = "passive",
        id = Isaac.GetItemIdByName("Horse"),
    },
    GOAT = {
        WorkingNow = true,
        type = "passive",
        id = Isaac.GetItemIdByName("Goat"),
    },
    MONKEY = {
        WorkingNow = true,
        type = "passive",
        id = Isaac.GetItemIdByName("Monkey"),
    },
    CHICKEN = {
        WorkingNow = true,
        type = "passive",
        id = Isaac.GetItemIdByName("Chicken"),
    },
    DOG = {
        WorkingNow = true,
        type = "passive",
        id = Isaac.GetItemIdByName("Dog"),
    },
    PIG = {
        WorkingNow = true,
        type = "passive",
        id = Isaac.GetItemIdByName("Pig"),
    },
    CRONUS = {
		type = "passive",
		id = Isaac.GetItemIdByName("Cronus"),
		gfx = "cronus.png",
		pool = {
			RoomType.ROOM_ANGEL,
			RoomType.ROOM_DEVIL,
			RoomType.ROOM_TREASURE
		},
		quality = 4,
		tags = "offensive",
		cache = "damage firedelay",
		flag = "negative",
        origin = { id = CollectibleType.COLLECTIBLE_BFFS, type = "collectible" },
		script = "scripts/items/collectibles/cronus",
		callbacks = {
			pickup = "cronus.onPickup",
			postPlayerUpdate = "cronus.onPlayerUpdate",
			evaluateCache = "cronus.onEvaluateCache",
			gameStarted = "cronus.onGameStarted",
            familiarUpdate = "cronus.onFamiliarUpdate",
            fireTear = "cronus.onFireTear",
            entityTakeDmg = "cronus.onEntityTakeDamage",
            postEntityTakeDmg = "cronus.onPostEntityTakeDamage",
            postNewRoom = "cronus.onNewRoom",
            postNewLevel = "cronus.onNewLevel",
            postRoomClear = "cronus.onRoomClear",
            prePlayerCollision = "cronus.onPrePlayerCollision",
            postUpdate = "cronus.onPostUpdate",
            postRender = "cronus.onPostRender",
            preGameExit = "cronus.onPreGameExit"
		},
		synergies = {
            [{ id = CollectibleType.COLLECTIBLE_TWISTED_PAIR, type = "collectible" }] = "twisted_pair",
            [{ id = CollectibleType.COLLECTIBLE_SUCCUBUS, type = "collectible" }] = "succubus",
            [{ id = CollectibleType.COLLECTIBLE_INCUBUS, type = "collectible" }] = "incubus",
            [{ id = CollectibleType.COLLECTIBLE_SERAPHIM, type = "collectible" }] = "seraphim",
            [{ id = CollectibleType.COLLECTIBLE_ROBO_BABY, type = "collectible" }] = "robo_baby",
            [{ id = CollectibleType.COLLECTIBLE_ROBO_BABY_2, type = "collectible" }] = "robo_baby_2",
            [{ id = CollectibleType.COLLECTIBLE_BLUE_BABYS_ONLY_FRIEND, type = "collectible" }] = "blue_babys_only_friend",
            [{ id = CollectibleType.COLLECTIBLE_LIL_BRIMSTONE, type = "collectible" }] = "lil_brimstone",
            [{ id = CollectibleType.COLLECTIBLE_BOBS_BRAIN, type = "collectible" }] = "bobs_brain",
            [{ id = CollectibleType.COLLECTIBLE_LIL_MONSTRO, type = "collectible" }] = "lil_monstro",
            [{ id = CollectibleType.COLLECTIBLE_LIL_HAUNT, type = "collectible" }] = "lil_haunt",
            [{ id = CollectibleType.COLLECTIBLE_BLOOD_PUPPY, type = "collectible" }] = "blood_puppy",
            [{ id = CollectibleType.COLLECTIBLE_ANGELIC_PRISM, type = "collectible" }] = "angelic_prism",
            [{ id = CollectibleType.COLLECTIBLE_BOT_FLY, type = "collectible" }] = "bot_fly",
            [{ id = CollectibleType.COLLECTIBLE_FREEZER_BABY, type = "collectible" }] = "freezer_baby",
            [{ id = CollectibleType.COLLECTIBLE_LIL_ABADDON, type = "collectible" }] = "lil_abaddon",
            [{ id = CollectibleType.COLLECTIBLE_MULTIDIMENSIONAL_BABY, type = "collectible" }] = "multidimensional_baby",
            [{ id = CollectibleType.COLLECTIBLE_HARLEQUIN_BABY, type = "collectible" }] = "harlequin_baby",
            [{ id = CollectibleType.COLLECTIBLE_BROTHER_BOBBY, type = "collectible" }] = "brother_bobby",
            [{ id = CollectibleType.COLLECTIBLE_DEMON_BABY, type = "collectible" }] = "demon_baby",
            [{ id = CollectibleType.COLLECTIBLE_LITTLE_GISH, type = "collectible" }] = "little_gish",
            [{ id = CollectibleType.COLLECTIBLE_LIL_LOKI, type = "collectible" }] = "lil_loki",
            [{ id = CollectibleType.COLLECTIBLE_GHOST_BABY, type = "collectible" }] = "ghost_baby",
            [{ id = CollectibleType.COLLECTIBLE_ROTTEN_BABY, type = "collectible" }] = "rotten_baby",
            [{ id = CollectibleType.COLLECTIBLE_LITTLE_STEVEN, type = "collectible" }] = "little_steven",
            [{ id = CollectibleType.COLLECTIBLE_RAINBOW_BABY, type = "collectible" }] = "rainbow_baby",
            [{ id = CollectibleType.COLLECTIBLE_GUARDIAN_ANGEL, type = "collectible" }] = "guardian_angel",
            [{ id = CollectibleType.COLLECTIBLE_CENSER, type = "collectible" }] = "censer",
            [{ id = CollectibleType.COLLECTIBLE_LEECH, type = "collectible" }] = "leech",
            [{ id = CollectibleType.COLLECTIBLE_BOMB_BAG, type = "collectible" }] = "bomb_bag",
            [{ id = CollectibleType.COLLECTIBLE_DARK_BUM, type = "collectible" }] = "dark_bum",
            [{ id = CollectibleType.COLLECTIBLE_KEY_BUM, type = "collectible" }] = "key_bum",
            [{ id = CollectibleType.COLLECTIBLE_ABEL, type = "collectible" }] = "abel",
            [{ id = CollectibleType.COLLECTIBLE_STAR_OF_BETHLEHEM, type = "collectible" }] = "star_of_bethlehem",
            [{ id = CollectibleType.COLLECTIBLE_FARTING_BABY, type = "collectible" }] = "farting_baby",
            [{ id = CollectibleType.COLLECTIBLE_SAMSONS_CHAINS, type = "collectible" }] = "samsons_chains",
            [{ id = CollectibleType.COLLECTIBLE_FINGER, type = "collectible" }] = "finger",
            [{ id = CollectibleType.COLLECTIBLE_LITTLE_CHAD, type = "collectible" }] = "little_chad",
            [{ id = CollectibleType.COLLECTIBLE_SACK_OF_PENNIES, type = "collectible" }] = "sack_of_pennies",
            [{ id = CollectibleType.COLLECTIBLE_SACK_OF_SACKS, type = "collectible" }] = "sack_of_sacks",
            [{ id = CollectibleType.COLLECTIBLE_CHARGED_BABY, type = "collectible" }] = "charged_baby",
            [{ id = CollectibleType.COLLECTIBLE_YO_LISTEN, type = "collectible" }] = "yo_listen",
            [{ id = CollectibleType.COLLECTIBLE_DADDY_LONGLEGS, type = "collectible" }] = "daddy_longlegs",
            [{ id = CollectibleType.COLLECTIBLE_SISTER_MAGGY, type = "collectible" }] = "sister_maggy",
            [{ id = CollectibleType.COLLECTIBLE_LITTLE_CHUBBY, type = "collectible" }] = "little_chubby",
            [{ id = CollectibleType.COLLECTIBLE_BIG_CHUBBY, type = "collectible" }] = "big_chubby",
            [{ id = CollectibleType.COLLECTIBLE_PEEPER, type = "collectible" }] = "peeper",
            [{ id = CollectibleType.COLLECTIBLE_BBF, type = "collectible" }] = "bbf",
            [{ id = CollectibleType.COLLECTIBLE_FATES_REWARD, type = "collectible" }] = "fates_reward",
            [{ id = CollectibleType.COLLECTIBLE_LIL_GURDY, type = "collectible" }] = "lil_gurdy",
            [{ id = CollectibleType.COLLECTIBLE_BUMBO, type = "collectible" }] = "bumbo",
            [{ id = CollectibleType.COLLECTIBLE_SPIDER_MOD, type = "collectible" }] = "spider_mod",
            [{ id = CollectibleType.COLLECTIBLE_DEPRESSION, type = "collectible" }] = "depression",
            [{ id = CollectibleType.COLLECTIBLE_KING_BABY, type = "collectible" }] = "king_baby",
            [{ id = CollectibleType.COLLECTIBLE_ACID_BABY, type = "collectible" }] = "acid_baby",
            [{ id = CollectibleType.COLLECTIBLE_JAW_BONE, type = "collectible" }] = "jaw_bone",
            [{ id = CollectibleType.COLLECTIBLE_BOILED_BABY, type = "collectible" }] = "boiled_baby",
            [{ id = CollectibleType.COLLECTIBLE_LIL_DUMPY, type = "collectible" }] = "lil_dumpy",
            [{ id = CollectibleType.COLLECTIBLE_FRUITY_PLUM, type = "collectible" }] = "fruity_plum",
            [{ id = CollectibleType.COLLECTIBLE_7_SEALS, type = "collectible" }] = "7_seals",
            [{ id = CollectibleType.COLLECTIBLE_JUICY_SACK, type = "collectible" }] = "juicy_sack",
            [{ id = CollectibleType.COLLECTIBLE_SISSY_LONGLEGS, type = "collectible" }] = "sissy_longlegs",
            [{ id = CollectibleType.COLLECTIBLE_INTRUDER, type = "collectible" }] = "intruder",
            [{ id = CollectibleType.COLLECTIBLE_WORM_FRIEND, type = "collectible" }] = "worm_friend",
            [{ id = CollectibleType.COLLECTIBLE_HALO_OF_FLIES, type = "collectible" }] = "halo_of_flies",
            [{ id = CollectibleType.COLLECTIBLE_DISTANT_ADMIRATION, type = "collectible" }] = "distant_admiration",
            [{ id = CollectibleType.COLLECTIBLE_CUBE_OF_MEAT, type = "collectible" }] = "cube_of_meat",
            [{ id = CollectibleType.COLLECTIBLE_FOREVER_ALONE, type = "collectible" }] = "forever_alone",
            [{ id = CollectibleType.COLLECTIBLE_SACRIFICIAL_DAGGER, type = "collectible" }] = "sacrificial_dagger",
            [{ id = CollectibleType.COLLECTIBLE_GUPPYS_HAIRBALL, type = "collectible" }] = "guppys_hairball",
            [{ id = CollectibleType.COLLECTIBLE_GUILLOTINE, type = "collectible" }] = "guillotine",
            [{ id = CollectibleType.COLLECTIBLE_BALL_OF_BANDAGES, type = "collectible" }] = "ball_of_bandages",
            [{ id = CollectibleType.COLLECTIBLE_SMART_FLY, type = "collectible" }] = "smart_fly",
            [{ id = CollectibleType.COLLECTIBLE_BEST_BUD, type = "collectible" }] = "best_bud",
            [{ id = CollectibleType.COLLECTIBLE_BIG_FAN, type = "collectible" }] = "big_fan",
            [{ id = CollectibleType.COLLECTIBLE_PUNCHING_BAG, type = "collectible" }] = "punching_bag",
            [{ id = CollectibleType.COLLECTIBLE_SWORN_PROTECTOR, type = "collectible" }] = "sworn_protector",
            [{ id = CollectibleType.COLLECTIBLE_FRIEND_ZONE, type = "collectible" }] = "friend_zone",
            [{ id = CollectibleType.COLLECTIBLE_LOST_FLY, type = "collectible" }] = "lost_fly",
            [{ id = CollectibleType.COLLECTIBLE_HUSHY, type = "collectible" }] = "hushy",
            [{ id = CollectibleType.COLLECTIBLE_MOMS_RAZOR, type = "collectible" }] = "moms_razor",
            [{ id = CollectibleType.COLLECTIBLE_ANGRY_FLY, type = "collectible" }] = "angry_fly",
            [{ id = CollectibleType.COLLECTIBLE_LEPROSY, type = "collectible" }] = "leprosy",
            [{ id = CollectibleType.COLLECTIBLE_SLIPPED_RIB, type = "collectible" }] = "slipped_rib",
            [{ id = CollectibleType.COLLECTIBLE_POINTY_RIB, type = "collectible" }] = "pointy_rib",
            [{ id = CollectibleType.COLLECTIBLE_PSY_FLY, type = "collectible" }] = "psy_fly",
            [{ id = CollectibleType.COLLECTIBLE_TINYTOMA, type = "collectible" }] = "tinytoma",
            [{ id = CollectibleType.COLLECTIBLE_HEADLESS_BABY, type = "collectible" }] = "headless_baby",
            [{ id = CollectibleType.COLLECTIBLE_CAINS_OTHER_EYE, type = "collectible" }] = "cains_other_eye",
            [{ id = CollectibleType.COLLECTIBLE_PAPA_FLY, type = "collectible" }] = "papa_fly",
            [{ id = CollectibleType.COLLECTIBLE_SHADE, type = "collectible" }] = "shade",
            [{ id = CollectibleType.COLLECTIBLE_OBSESSED_FAN, type = "collectible" }] = "obsessed_fan",
            [{ id = CollectibleType.COLLECTIBLE_GEMINI, type = "collectible" }] = "gemini",
            [{ id = CollectibleType.COLLECTIBLE_CUBE_BABY, type = "collectible" }] = "cube_baby",
            [{ id = CollectibleType.COLLECTIBLE_LIL_SPEWER, type = "collectible" }] = "lil_spewer",
            [{ id = CollectibleType.COLLECTIBLE_GB_BUG, type = "collectible" }] = "gb_bug",
            [{ id = CollectibleType.COLLECTIBLE_BUM_FRIEND, type = "collectible" }] = "bum_friend",
            [{ id = CollectibleType.COLLECTIBLE_LIL_CHEST, type = "collectible" }] = "lil_chest",
            [{ id = CollectibleType.COLLECTIBLE_RELIC, type = "collectible" }] = "relic",
            [{ id = CollectibleType.COLLECTIBLE_MYSTERY_SACK, type = "collectible" }] = "mystery_sack",
            [{ id = CollectibleType.COLLECTIBLE_RUNE_BAG, type = "collectible" }] = "rune_bag",
            [{ id = CollectibleType.COLLECTIBLE_PASCHAL_CANDLE, type = "collectible" }] = "paschal_candle",
            [{ id = CollectibleType.COLLECTIBLE_HOLY_WATER, type = "collectible" }] = "holy_water",
            [{ id = CollectibleType.COLLECTIBLE_DRY_BABY, type = "collectible" }] = "dry_baby",
            [{ id = CollectibleType.COLLECTIBLE_MILK, type = "collectible" }] = "milk",
            [{ id = CollectibleType.COLLECTIBLE_BIRD_CAGE, type = "collectible" }] = "bird_cage",
            [{ id = CollectibleType.COLLECTIBLE_MYSTERY_EGG, type = "collectible" }] = "mystery_egg",
            [{ id = CollectibleType.COLLECTIBLE_MY_SHADOW, type = "collectible" }] = "my_shadow",
            [{ id = CollectibleType.COLLECTIBLE_HALLOWED_GROUND, type = "collectible" }] = "hallowed_ground",
            [{ id = CollectibleType.COLLECTIBLE_LOST_SOUL, type = "collectible" }] = "lost_soul",
            [{ id = CollectibleType.COLLECTIBLE_BLOODSHOT_EYE, type = "collectible" }] = "bloodshot_eye",
            [{ id = CollectibleType.COLLECTIBLE_MONGO_BABY, type = "collectible" }] = "mongo_baby",
            [{ id = CollectibleType.COLLECTIBLE_BUDDY_IN_A_BOX, type = "collectible" }] = "buddy_in_a_box",
            [{ id = CollectibleType.COLLECTIBLE_LIL_DELIRIUM, type = "collectible" }] = "lil_delirium",
            [{ id = CollectibleType.COLLECTIBLE_BOX_OF_FRIENDS, type = "collectible" }] = "box_of_friends",
            [{ id = CollectibleType.COLLECTIBLE_MONSTER_MANUAL, type = "collectible" }] = "monster_manual",
            [{ id = CollectibleType.COLLECTIBLE_SACRIFICIAL_ALTAR, type = "collectible" }] = "sacrificial_altar",
            [{ id = TrinketType.TRINKET_THE_TWINS, type = "trinket" }] = "trinket_the_twins",
            -- Blacklisted items
            [{ id = CollectibleType.COLLECTIBLE_1UP, type = "collectible" }] = "1up",
            [{ id = CollectibleType.COLLECTIBLE_ISAACS_HEART, type = "collectible" }] = "isaacs_heart",
            [{ id = CollectibleType.COLLECTIBLE_DEAD_CAT, type = "collectible" }] = "dead_cat",
            [{ id = CollectibleType.COLLECTIBLE_KEY_PIECE_1, type = "collectible" }] = "key_piece_1",
            [{ id = CollectibleType.COLLECTIBLE_KEY_PIECE_2, type = "collectible" }] = "key_piece_2",
            [{ id = CollectibleType.COLLECTIBLE_KNIFE_PIECE_1, type = "collectible" }] = "knife_piece_1",
            [{ id = CollectibleType.COLLECTIBLE_KNIFE_PIECE_2, type = "collectible" }] = "knife_piece_2",
            [{ id = CollectibleType.COLLECTIBLE_DAMOCLES_PASSIVE, type = "collectible" }] = "damocles_passive",
            [{ id = CollectibleType.COLLECTIBLE_STRAW_MAN, type = "collectible" }] = "straw_man",
            [{ id = CollectibleType.COLLECTIBLE_BLOOD_OATH, type = "collectible" }] = "blood_oath",
        }
	},
    APPRAISAL_CERTIFICATE = {
        type = "active",
        id = Isaac.GetItemIdByName("Appraisal Certificate"),
        pool = {
            RoomType.ROOM_TREASURE,
            RoomType.ROOM_SHOP,
        },
        quality = 3,
        tags = "offensive",
        cache = "",
        hidden = false,
        shopprice = 20,
        devilprice = 2,
        maxcharges = 0,
        gfx = "appraisal_certificate.png",
        origin = { id = CollectibleType.COLLECTIBLE_DEATH_CERTIFICATE, type = "collectible" },
        flag = "neutral",
        script = "scripts/items/collectibles/appraisal_certificate",
        callbacks = {
            use = "appraisal.onUseItem",
            preUseItem = "appraisal.onPreUseItem",
            inputAction = "appraisal.onInputAction",
        },
        synergies = {
            [{ type = "trinket", name = "Atropos" }] = "atropos"
        },
    },
    MONEY_TEAR = {
        type = "passive",
        id = Isaac.GetItemIdByName("Money = Tear"),
        pool = {
            RoomType.ROOM_TREASURE,
            RoomType.ROOM_SHOP,
            RoomType.ROOM_ANGEL,
        },
        gfx = "money_tear.png",
        tags = "offensive",
        cache = "tears",
        quality = 4,
		origin = { id = CollectibleType.COLLECTIBLE_MONEY_EQUALS_POWER, type = "collectible" },
        flag = "positive",
        shopprice = 20,
        script = "scripts/items/collectibles/money_tear",
        callbacks = {
            gameStarted = "moneytear.onGameStarted",
            update = "moneytear.onUpdate"
        }
    },
    UTILITY_BELT = {
        type = "passive",
        id = Isaac.GetItemIdByName("Utility Belt"),
        pool = {
            RoomType.ROOM_TREASURE,
            RoomType.ROOM_SHOP
        },
        gfx = "utility_belt.png",
        tags = "utility",
        quality = 3,
        origin = { id = CollectibleType.COLLECTIBLE_BELT, type = "collectible" },
        flag = "positive",
        shopprice = 15,
        script = "scripts/items/collectibles/utility_belt",
        callbacks = {
            postPlayerUpdate = "utilitybelt.onPlayerUpdate",
            gameStarted = "utilitybelt.onGameStarted",
            newLevel = "utilitybelt.onNewLevel",
        },
        synergies = {
            [{ id = CollectibleType.COLLECTIBLE_BOOK_OF_VIRTUES, type = "collectible" }] = "book_of_virtues",
            [{ id = CollectibleType.COLLECTIBLE_D_INFINITY, type = "collectible" }] = "d_infinity",
            [{ id = CollectibleType.COLLECTIBLE_BLANK_CARD, type = "collectible" }] = "blank_card",
            [{ id = CollectibleType.COLLECTIBLE_PLACEBO, type = "collectible" }] = "placebo",
            [{ id = CollectibleType.COLLECTIBLE_CLEAR_RUNE, type = "collectible" }] = "clear_rune",
            [{ id = CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS, type = "collectible" }] = "glowing_hour_glass",
            [{ id = CollectibleType.COLLECTIBLE_JAR_OF_WISPS, type = "collectible" }] = "jar_of_wisps",
        }
    },
    SEALED_DEMON_SWORD = {
        type = "passive",
        id = Isaac.GetItemIdByName("Sealed Demon Sword"),
        pool = {
            RoomType.ROOM_DEVIL,
            RoomType.ROOM_CURSE
        },
        gfx = "sealed_demon_sword.png",
        tags = "offensive",
        cache = "speed",
        quality = 0,
        origin = { id = CollectibleType.COLLECTIBLE_RED_STEW, type = "collectible" },
        flag = "positive",
        shopprice = 10,
        devilprice = 1,
        script = "scripts/items/collectibles/sealed_demon_sword",
        callbacks = {
            pickup = "sealeddemonsword.onPickup",
            evaluateCache = "sealeddemonsword.onEvaluateCache",
            postNPCDeath = "sealeddemonsword.onNPCDeath",
            update = "sealeddemonsword.onUpdate",
            postNewRoom = "sealeddemonsword.onNewRoom",
            gameStarted = "sealeddemonsword.onGameStarted",
        },
        synergies = {}
    },
    TYRFING = {
        type = "passive",
        id = Isaac.GetItemIdByName("Tyrfing"),
        pool = {},
        gfx = "tyrfing.png",
        tags = "offensive",
        cache = "damage",
        quality = 4,
        hidden = true,
        origin = { type = "collectible", name = "Sealed Demon Sword" },
        flag = "negative",
        shopprice = 30,
        devilprice = 2,
        script = "scripts/items/collectibles/tyrfing",
        callbacks = {
            pickup = "tyrfing.onPickup",
            evaluateCache = "tyrfing.onEvaluateCache",
            entityTakeDmg = "tyrfing.onEntityTakeDamage",
            postNPCDeath = "tyrfing.onNPCDeath",
            gameStarted = "tyrfing.onGameStarted",
        },
        synergies = {}
    },
    ICE_BREATH = {
        type = "passive",
        id = Isaac.GetItemIdByName("Ice Breath"),
        pool = {
            RoomType.ROOM_SHOP,
            RoomType.ROOM_TREASURE
        },
        quality = 4,
        tags = "offensive",
        hidden = false,
        shopprice = 30,
        devilprice = 2,
        origin = { id = CollectibleType.COLLECTIBLE_CANDLE, type = "collectible" },
        flag = "positive",
        script = "scripts/items/collectibles/ice_breath",
        callbacks = {
            postPlayerUpdate = "icebreath.onPlayerUpdate",
            postEffectUpdate = "icebreath.onEffectUpdate",
            weaponFired = "icebreath.onWeaponFired",
            tearUpdate = "icebreath.onTearUpdate",
            tearCollision = "icebreath.onTearCollision"
        }
    },
    FIRE_BREATH = {
        type = "passive",
        id = Isaac.GetItemIdByName("Fire Breath"),
        pool = {
            RoomType.ROOM_SHOP,
            RoomType.ROOM_TREASURE
        },
        quality = 4,
        tags = "offensive",
        hidden = false,
        shopprice = 30,
        devilprice = 2,
        origin = { id = CollectibleType.COLLECTIBLE_RED_CANDLE, type = "collectible" },
        flag = "positive",
        script = "scripts/items/collectibles/fire_breath",
        callbacks = {
            postPlayerUpdate = "firebreath.onPlayerUpdate",
            weaponFired = "firebreath.onWeaponFired",
            postEffectUpdate = "firebreath.onEffectUpdate",
            tearUpdate = "firebreath.onTearUpdate",
            tearCollision = "firebreath.onTearCollision"
        }
    },
    SOFLAM = {
        type = "passive",
        id = Isaac.GetItemIdByName("SOFLAM"),
        pool = {
            RoomType.ROOM_TREASURE
        },
        quality = 4,
        tags = "offensive",
        cache = "weapon",
        hidden = false,
        shopprice = 25,
        devilprice = 2,
        origin = { id = CollectibleType.COLLECTIBLE_EPIC_FETUS, type = "collectible" },
        flag = "positive",
        script = "scripts/items/collectibles/soflam",
        callbacks = {
            evaluateCache = "soflam.onEvaluateCache",
            tearCollision = "soflam.onTearCollision",
            postEntityTakeDmg = "soflam.onPostEntityTakeDamage",
            update = "soflam.onUpdate",
            postNewRoom = "soflam.onNewRoom",
            gameStarted = "soflam.onGameStarted"
        },
        synergies = {
            [{ id = CollectibleType.COLLECTIBLE_MR_MEGA, type = "collectible" }] = "mr_mega"
        }
    },
    TWO_FACED_PENNY = {
        type = "passive",
        id = Isaac.GetItemIdByName("Two Faced Penny"),
        pool = {
            RoomType.ROOM_TREASURE,
            RoomType.ROOM_SHOP
        },
        gfx = "two_faced_penny.png",
        tags = "utility",
        quality = 4,
        origin = { id = CollectibleType.COLLECTIBLE_CROOKED_PENNY, type = "collectible" },
        flag = "positive",
        shopprice = 15,
        script = "scripts/items/collectibles/two_faced_penny",
        callbacks = {
            postPlayerUpdate = "twofacedpenny.onPlayerUpdate",
            postAddCollectible = "twofacedpenny.onPostAddCollectible",
            entityTakeDmg = "twofacedpenny.onDamage",
            postNewLevel = "twofacedpenny.onNewFloor",
            gameStarted = "twofacedpenny.onGameStarted"
        }
    },
    INF_D6 = {
        type = "active",
        id = Isaac.GetItemIdByName("Inf D6"),
        gfx = "inf_d6.png",
        tags = "utility",
        hidden = true,
        shopprice = 999,
        maxcharges = 0,
        quality = 0,
        chargetype = "normal",
        script = "scripts/items/collectibles/inf_d6",
        callbacks = {
            use = "infd6.onUse",
        }
    },

    SEVERED_OATH = {
        type = "active",
        id = Isaac.GetItemIdByName("Severed Oath"),
        pool = {
            RoomType.ROOM_TREASURE,
            RoomType.ROOM_SECRET,
            RoomType.ROOM_SHOP
        },
        quality = 3,
        tags = "utility",
        hidden = false,
        shopprice = 15,
        devilprice = 2,
        maxcharges = 4,
        chargetype = "normal",
        initcharge = 0,
        gfx = "severed_oath.png",
        origin = { id = CollectibleType.COLLECTIBLE_MEAT_CLEAVER, type = "collectible" },
        flag = "positive",
        script = "scripts/items/collectibles/severed_oath",
        callbacks = {
            use = "severedoath.onUseItem",
            update = "severedoath.onUpdate",
            gameStarted = "severedoath.onGameStarted",
            postNewRoom = "severedoath.onPostNewRoom",
            postPickupInit = "severedoath.onPostPickupInit",
            postPickupUpdate = "severedoath.onPostPickupUpdate",
            executeCmd = "severedoath.onExecuteCmd"
        },
    },
    -- Ceil / Round / Floor share scripts/items/collectibles/stat_rounding,
    -- which registers one late MC_EVALUATE_CACHE priority callback for all three.
    CEIL = {
        type = "passive",
        id = Isaac.GetItemIdByName("Ceil"),
        pool = {
            RoomType.ROOM_TREASURE,
            RoomType.ROOM_PLANETARIUM
        },
        quality = 4,
        tags = "offensive stars",
        cache = "speed firedelay damage range shotspeed luck",
        hidden = false,
        shopprice = 20,
        devilprice = 2,
        origin = { id = CollectibleType.COLLECTIBLE_LIBRA, type = "collectible" },
        flag = "positive",
        script = "scripts/items/collectibles/stat_rounding",
    },
    ROUND = {
        type = "passive",
        id = Isaac.GetItemIdByName("Round"),
        pool = {
            RoomType.ROOM_TREASURE,
            RoomType.ROOM_PLANETARIUM
        },
        quality = 3,
        tags = "offensive stars",
        cache = "speed firedelay damage range shotspeed luck",
        hidden = false,
        shopprice = 15,
        devilprice = 2,
        origin = { id = CollectibleType.COLLECTIBLE_LIBRA, type = "collectible" },
        flag = "neutral",
        script = "scripts/items/collectibles/stat_rounding",
        synergies = {
            [{ type = "collectible", name = "Ceil" }] = "ceil",
        },
    },
    FLOOR = {
        type = "passive",
        id = Isaac.GetItemIdByName("Floor"),
        pool = {
            RoomType.ROOM_TREASURE,
            RoomType.ROOM_PLANETARIUM
        },
        quality = 2,
        tags = "offensive stars",
        cache = "speed firedelay damage range shotspeed luck",
        hidden = false,
        shopprice = 15,
        devilprice = 1,
        origin = { id = CollectibleType.COLLECTIBLE_LIBRA, type = "collectible" },
        flag = "negative",
        script = "scripts/items/collectibles/stat_rounding",
        synergies = {
            [{ type = "collectible", name = "Ceil" }] = "ceil",
            [{ type = "collectible", name = "Round" }] = "round",
        },
    },

    -- Familiars
    TIME_MONEY = {
        type = "familiar",
        id = Isaac.GetItemIdByName("Time = Money"),
        script = "scripts/items/familiars/time_money",
        uniquefamiliar = true,
        -- Entities2.xml generation config
        -- anm2: optional override for ANM2 path under gfx/ (default: "time_money.anm2")
        anm2 = "time_money.anm2",
        entity = { variant = 777, collisiondamage = 0, collisionmass = 3, collisionradius = 5, friction = 1, numgridcollisionpoints = 6, shadowsize = 13, tags = "cansacrifice", customtags = "" },
        gibs = { amount = 0, blood = 0, bone = 0, eye = 0, gut = 0, large = 0 },
        pool = {
            RoomType.ROOM_DEVIL,
            RoomType.ROOM_SHOP,
            RoomType.ROOM_GREED_EXIT,
            RoomType.ROOM_SECRET
        },
        quality = 4,
        tags="baby summonable offensive",
        shopprice = 30,
        devilprice = 2,
        origin = { id = CollectibleType.COLLECTIBLE_SACK_OF_PENNIES, type = "collectible" },
        flag = "positive",
        synergies = {
            [{ id = CollectibleType.COLLECTIBLE_BFFS, type = "collectible" }] = "bffs"
        },
        callbacks = {
            familiarInit = "timemoney.onFamiliarInit",
            familiarUpdate = "timemoney.onFamiliarUpdate",
            postFamiliarRender = "timemoney.onFamiliarRender",
            evaluateCache = "timemoney.onEvaluateCache",
            gameStarted = "timemoney.onGameStarted",
            postPlayerUpdate = "timemoney.onPlayerUpdate",
            entityTakeDmg = "timemoney.onEntityTakeDamage"
        }
    },

    -- Trinkets
    TIME_POWER = {
        type = "trinket",
        id = Isaac.GetTrinketIdByName("Time = Power"),
        gfx = "time_power.png",
        tags = "offensive",
        cache = "damage",
        hidden = false,
        origin = { id = TrinketType.TRINKET_CURVED_HORN, type = "trinket" },
        flag = "positive",
        shopprice=15,
        script = "scripts/items/trinkets/time_power",
        specials = { normal = 0.006 },
        callbacks = {
            evaluateCache = "timepowertrinket.onEvaluateCache",
            gameStarted = "timepowertrinket.onGameStarted",
            update = "timepowertrinket.onUpdate",
            entityTakeDmg = "timepowertrinket.onEntityTakeDamage"
        },
        synergies = {}
    },
    TIME_TEAR = {
        type = "trinket",
        id = Isaac.GetTrinketIdByName("Time = Tear"),
        gfx = "time_tear.png",
        tags = "offensive",
        cache = "fireDelay",
        hidden = false,
        origin = { id = TrinketType.TRINKET_CANCER, type = "trinket" },
        flag = "positive",
        shopprice=15,
        script = "scripts/items/trinkets/time_tear",
        specials = { normal = 0.0066 },
        callbacks = {
            evaluateCache = "timeteartrinket.onEvaluateCache",
            gameStarted = "timeteartrinket.onGameStarted",
            update = "timeteartrinket.onUpdate",
            entityTakeDmg = "timeteartrinket.onEntityTakeDamage"
        },
        synergies = {}
    },
    TIME_LUCK = {
        type = "trinket",
        id = Isaac.GetTrinketIdByName("Time = Luck"),
        gfx = "time_luck.png",
        tags = "utility",
        cache = "luck",
        hidden = false,
        origin = { id = TrinketType.TRINKET_PERFECTION, type = "trinket" },
        flag = "positive",
        shopprice=15,
        script = "scripts/items/trinkets/time_luck",
        specials = { normal = 0.01 },
        callbacks = {
            evaluateCache = "timelucktrinket.onEvaluateCache",
            gameStarted = "timelucktrinket.onGameStarted",
            update = "timelucktrinket.onUpdate",
            entityTakeDmg = "timelucktrinket.onEntityTakeDamage"
        },
        synergies = {}
    },
    F_MINUS = {
        WorkingNow=false,
        type = "trinket",
        id = Isaac.GetTrinketIdByName("F -"),
        gfx = "f_minus.png",
        tags = "offensive",
        cache = "luck",
        hidden = false,
        origin = { id = TrinketType.TRINKET_PERFECTION, type = "trinket" },
        flag = "negative",
        shopprice=15,
        script = "scripts/items/trinkets/f_minus",
        specials = { normal = 5 },
        synergies = {}
    },
    C_MINUS = {
        WorkingNow=false,
        type = "trinket",
        id = Isaac.GetTrinketIdByName("C -"),
        gfx = "c_minus.png",
        tags = "offensive",
        cache = "tears",
        origin = { type = "trinket", name = "F -" },
        flag = "positive",
        hidden = true,
        shopprice=15,
        script = "scripts/items/trinkets/c_minus",
        specials = { normal = {4, 2.0} },
        synergies = {}
    },
    B_MINUS = {
        WorkingNow=false,
        type = "trinket",
        id = Isaac.GetTrinketIdByName("B -"),
        gfx = "b_minus.png",
        tags = "offensive",
        cache = "luck damage",
        origin = { type = "trinket", name = "C -" },
        flag = "positive",
        hidden = true,
        shopprice=15,
        script = "scripts/items/trinkets/b_minus",
        specials = { normal = {3, 3.0} },
        synergies = {}
    },
    A_MINUS = {
        WorkingNow=false,
        type = "trinket",
        id = Isaac.GetTrinketIdByName("A -"),
        gfx = "a_minus.png",
        tags = "offensive",
        cache = "luck damage tears",
        origin = { type = "trinket", name = "B -" },
        flag = "positive",
        hidden = true,
        shopprice=15,
        script = "scripts/items/trinkets/a_minus",
        specials = { normal = {2, 4.0} },
        callbacks = {
            postPEffectUpdate = "aminus.onPostPEffectUpdate",
            evaluateCache = "aminus.onEvaluateCache",
        },
        synergies = {}
    },
    ATROPOS = {
        type = "trinket",
        id = Isaac.GetTrinketIdByName("Atropos"),
        gfx = "atropos.png",
        tags = "utility",
        hidden = false,
        flag = "positive",
        origin = { id = TrinketType.TRINKET_SAFETY_SCISSORS, type = "trinket" },
        shopprice = 15,
        script = "scripts/items/trinkets/atropos",
        callbacks = {
            postUpdate = "atropos.onPostUpdate",
            postNewRoom = "atropos.onPostNewRoom",
            gameStarted = "atropos.onGameStarted",
            prePickupCollision = "atropos.onPrePickupCollision"
        },
        synergies = {
            [{ id = CollectibleType.COLLECTIBLE_DEATH_CERTIFICATE, type = "collectible" }] = "death_certificate"
        }
    },
    ANGELS_CROWN = {
        type = "trinket",
        id = Isaac.GetTrinketIdByName("Angel's Crown"),
        gfx = "angels_crown.png",
        tags = "utility",
        hidden = false,
        origin = { id = TrinketType.TRINKET_DEVILS_CROWN, type = "trinket" },
        flag = "positive",
        shopprice = 15,
        script = "scripts/items/trinkets/angels_crown",
        callbacks = {
            gameStarted = "angelscrown.onGameStarted",
            preGameExit = "angelscrown.onPreGameExit",
            postNewRoom = "angelscrown.onPostNewRoom",
            postUpdate = "angelscrown.onPostUpdate",
            preGetCollectible = "angelscrown.onPreGetCollectible"
        },
        synergies = {
        }
    },

}

-- Player-facing text (names, descriptions, EID and synergy lines) lives in
-- scripts/locale/<lang>.lua; fill it into ItemData before anything reads it.
ConchBlessing.Locale = require("scripts.locale.init")
ConchBlessing.Locale.applyItemData(ConchBlessing.ItemData)

--[[
Capricorn(염소자리)
↑ {{Heart}}최대 체력 +1
↑ {{Coin}}동전, {{Bomb}}폭탄, {{Key}}열쇠 +1
↑ {{DamageSmall}}공격력 +0.5
↑ {{TearsSmall}}눈물 딜레이 -1
↑ {{RangeSmall}}사거리 +1.5
↑ {{SpeedSmall}}이동속도 +0.1
자 (쥐) Rat
황금 동전 1개를 드랍합니다.
현재 소지중인 동전의 갯수만큼 황금 동전으로 대체될 확률이 생깁니다.
동전 획득시 1% 확률로 해당 방의 배열 아이템을 1개 소환합니다.

Aquarius(물병자리)
캐릭터가 지나간 자리에 파란 장판이 생깁니다.
파란 장판에 닿은 적은 초당 6의 피해를 받습니다.
축 (소) Ox

Pisces(물고기자리)
↑ {{TearsSmall}}연사 +0.2
↑ {{TearsizeSmall}}눈물크기 x1.25
공격이 적을 더 강하게 밀쳐냅니다.
인 (호랑이) Tiger

Aries(양자리)
↑ {{SpeedSmall}}이동속도 +0.25
높은 속도로 적과 접촉시 적에게 18의 피해를 줍니다.
묘 (토끼) Rabbit

Taurus(황소자리)
↓ {{SpeedSmall}}이동속도{{ColorOrange}}(상한){{CR}} -0.3
그 방에 적이 있는 동안 이동속도가 점점 증가합니다.
{{Collectible77}} 이동속도가 2.0이 되면 5초간 무적 상태가 됩니다.
진 (용) Dragon
공중을 얻습니다.
공중과 지형관통을 얻습니다.
방에 입장하고 5초가 지나면, 5블럭 내 최대 5명의 적에게 5초간 지속되는 낙뢰를 내립니다.
위 과정이 한싸이클로 방마다 5번씩 반복됩니다.
낙뢰는 데미지의 5%만큼 줍니다.

Gemini(쌍둥이자리)
캐릭터와 연결되어 이동하며 적을 따라다닙니다.
접촉한 적에게 초당 6의 피해를 줍니다.
사 (뱀) Snake

Cancer(게자리)
↑ {{SoulHeart}}소울하트 +3
{{Collectible108}} 피격 시 이후 그 방에서 받는 피해를 절반으로 줄여줍니다.
오 (말) Horse

Leo(사자자리)
장애물을 부술 수 있습니다.
미 (양) Goat

Virgo(처녀자리)
{{Pill}} 부정적인 알약 효과가 등장하지 않습니다.
{{Collectible58}} 피격 시 일정 확률로 10초간 무적 상태가 됩니다.
{{LuckSmall}} 행운 10 이상일 때 100% 확률
신 (원숭이) Monkey

Libra(천칭자리)
{{Coin}}동전, {{Bomb}}폭탄, {{Key}}열쇠 +6
{{ArrowUpDown}} {{DamageSmall}}공격력, {{TearsSmall}}연사, {{RangeSmall}}사거리, {{SpeedSmall}}이동속도가 항상 균등하게 조정됩니다.
유 (닭) Chicken

Scorpio(전갈자리)
{{Poison}} 항상 적을 중독시키는 공격이 나갑니다.
술 (개) Dog

Sagitarius(사수자리)
↑ {{SpeedSmall}}이동속도 +0.2
공격이 적을 관통합니다.
해 (돼지) Pig
--]]

-- automatically load scripts and callbacks based on ItemData
local function loadAllItems()
    ConchBlessing.printDebug("Loading scripts and callbacks based on ItemData...")
    
    -- Load external systems
    local systems = {
        { name = "EID language support", path = "scripts.eid_language" },
        { name = "Callback manager", path = "scripts.callback_manager" }
    }
    
    if not ConchBlessing._didLoadExternalSystems then
        for _, system in ipairs(systems) do
            local success, err = pcall(function()
                require(system.path)
            end)
            if success then
                ConchBlessing.printDebug(system.name .. " loaded successfully")
            else
                ConchBlessing.printError(system.name .. " load failed: " .. tostring(err))
            end
        end
        ConchBlessing._didLoadExternalSystems = true
    else
        ConchBlessing.printDebug("External systems already loaded; skipping.")
    end
    
	-- Separate origin mappings by type to support IDs that exist as both collectible and trinket (Separate mappings solve ID collision issues like 109 and 145)
	local originItemFlags = {
		collectible = {}, -- [originID] = { itemKey1, itemKey2, ... }
		trinket = {}      -- [originID] = { itemKey1, itemKey2, ... }
	}

	-- Normalize origin declaration to an ID and optional explicit type
	local function resolveOriginAny(origin)
		-- Supports:
		-- 1) number (collectible/trinket id)
		-- 2) { id = number, type = "collectible"|"trinket" }
		-- 3) { name = string, type = "collectible"|"trinket" }
		-- 4) { collectible = string } or { trinket = string }
		if type(origin) == "number" then
			return origin, nil
		end
		if type(origin) == "table" then
			local explicitType = origin.type
			local id = origin.id
			if not id then
				if origin.name and explicitType == "trinket" then
					id = Isaac.GetTrinketIdByName(origin.name)
				elseif origin.name and explicitType == "collectible" then
					id = Isaac.GetItemIdByName(origin.name)
				elseif origin.trinket then
					id = Isaac.GetTrinketIdByName(origin.trinket)
					explicitType = explicitType or "trinket"
				elseif origin.collectible then
					id = Isaac.GetItemIdByName(origin.collectible)
					explicitType = explicitType or "collectible"
				end
			end
			local isTrink = nil
			if explicitType == "trinket" then
				isTrink = true
			elseif explicitType == "collectible" then
				isTrink = false
			end
			return id or -1, isTrink
		end
		return nil, nil
	end
    
    -- Load item scripts and build origin mapping
    if not ConchBlessing._didLoadItemScripts then
        for itemKey, itemData in pairs(ConchBlessing.ItemData) do
            ConchBlessing.printDebug("Processing: " .. itemKey)
            
		if itemData.origin and itemData.flag then
			local originID, originIsTrinkExp = resolveOriginAny(itemData.origin)
			if type(originID) ~= "number" or originID <= 0 then
				ConchBlessing.printError("  Invalid origin ID for " .. itemKey .. ": " .. tostring(originID) .. " (origin: " .. tostring(itemData.origin) .. ")")
			else
				local originIsTrinket = originIsTrinkExp
				ConchBlessing.printDebug("[EID] Processing origin for " .. itemKey .. ": originID=" .. tostring(originID) .. ", explicitType=" .. tostring(originIsTrinkExp))
				
				if originIsTrinket == nil then
					local cfg = Isaac.GetItemConfig()
					local hasTrinket = (cfg and cfg:GetTrinket(originID) ~= nil) or false
					local hasCollectible = (cfg and cfg:GetCollectible(originID) ~= nil) or false
					ConchBlessing.printDebug("[EID] Auto-detecting origin ID " .. tostring(originID) .. ": hasTrinket=" .. tostring(hasTrinket) .. ", hasCollectible=" .. tostring(hasCollectible))
					
					if hasTrinket and not hasCollectible then
						originIsTrinket = true
					elseif hasCollectible and not hasTrinket then
						originIsTrinket = false
					else
						ConchBlessing.printDebug("[EID] Ambiguous origin ID " .. tostring(originID) .. " for " .. itemKey .. "; requires explicit type declaration")
						originIsTrinket = nil
					end
				end
				
				if originIsTrinket == true then
					if not originItemFlags.trinket[originID] then
						originItemFlags.trinket[originID] = {}
					end
					table.insert(originItemFlags.trinket[originID], itemKey)
					ConchBlessing.printDebug("[EID] ✓ Mapped " .. itemKey .. " to TRINKET origin " .. tostring(originID) .. " (flag: " .. itemData.flag .. ")")
				elseif originIsTrinket == false then
					if not originItemFlags.collectible[originID] then
						originItemFlags.collectible[originID] = {}
					end
					table.insert(originItemFlags.collectible[originID], itemKey)
					ConchBlessing.printDebug("[EID] ✓ Mapped " .. itemKey .. " to COLLECTIBLE origin " .. tostring(originID) .. " (flag: " .. itemData.flag .. ")")
				else
					ConchBlessing.printDebug("[EID] ✗ FAILED to map " .. itemKey .. " - originIsTrinket is nil")
				end
			end
        end
            
            local scriptPath = itemData.script
            if not scriptPath or scriptPath == "" then
                -- Auto-resolve default script path when missing: infer by type and item key
                local baseDir = "scripts/items/collectibles"
                if itemData.type == "trinket" then
                    baseDir = "scripts/items/trinkets"
                elseif itemData.type == "familiar" then
                    baseDir = "scripts/items/familiars"
                end
                local guessed = baseDir .. "/" .. string.lower(itemKey)
                ConchBlessing.printDebug("  No script path; auto-resolving to: " .. guessed)
                scriptPath = guessed
            end

            ConchBlessing.printDebug("  Loading script: " .. scriptPath)
            local scriptSuccess, scriptErr = pcall(function()
                require(scriptPath)
            end)
            if scriptSuccess then
                ConchBlessing.printDebug("  Script loaded successfully: " .. scriptPath)
            else
                ConchBlessing.printError("  Script load failed: " .. scriptPath .. " - " .. tostring(scriptErr))
            end
            ConchBlessing.printDebug("  " .. itemKey .. " processed")
        end
		
        ConchBlessing._didLoadItemScripts = true
    else
        ConchBlessing.printDebug("Item scripts already loaded; skipping.")
    end
    
    ConchBlessing._originItemFlags = originItemFlags

    if not ConchBlessing._didGenerateConchDescriptions then
        ConchBlessing.printDebug("Generating conch mode descriptions...")
        
        -- Color definitions for flag types
        local flagColors = {
            positive = "{{ColorGreen}}",
            neutral = "{{ColorYellow}}",
            negative = "{{ColorRed}}"
        }
        
        -- The flag words and the transform line come from ui.conch_mode in
        -- scripts/locale/<lang>.lua. Only languages with a locale file get a
        -- template, so any other language shows no conch-mode line.
        local function colorizeFlag(flagType, lang)
            local color = flagColors[flagType] or ""
            return color .. ConchBlessing.Locale.textIn(lang, "ui.conch_mode.flags." .. flagType) .. "{{CR}}"
        end

        local conchModeDescriptions = {}
        for _, lang in ipairs(ConchBlessing.Locale.languages()) do
            conchModeDescriptions[lang] = {}
            for _, flagType in ipairs({ "positive", "neutral", "negative" }) do
                conchModeDescriptions[lang][flagType] =
                    ConchBlessing.Locale.textIn(lang, "ui.conch_mode.transform", colorizeFlag(flagType, lang))
            end
        end

        if EID then
            -- unify: prepare data and register a single modifier handling both conch-mode and synergies
            local function resolveModLang()
                local ConchBlessing_Config = require("scripts.conch_blessing_config")
                return ConchBlessing_Config.GetCurrentLanguage()
            end

            -- origin maps already exported above
            ConchBlessing._conchModeTemplates = conchModeDescriptions
            ConchBlessing._conchDescCache = ConchBlessing._conchDescCache or {}

            -- Build synergy lookup maps once
            if not ConchBlessing._builtSynergyMaps then
                ConchBlessing._synergyByTarget = {}
                ConchBlessing._synergyByMod = {}
				-- Resolve helper: allow targets specified by { type = "trinket"|"active"|"passive", name = "..." }
				local function resolveTargetId(targetKey)
					-- Returns: id (number or nil), isTrinket (boolean or nil)
					if type(targetKey) == "number" then
						return targetKey, nil
					end
					if type(targetKey) == "table" then
						-- Support { id = number, type = "collectible"|"trinket" }
						if type(targetKey.id) == "number" then
							local t = targetKey.type or targetKey.kind
							local isTrink
							if type(t) == "string" then
								local tl = string.lower(t)
								isTrink = (tl == "trinket")
							end
							return targetKey.id, isTrink
						end
						-- Support { name = string, type = "collectible"|"active"|"passive"|"trinket" }
						local t = targetKey.type or targetKey.kind
						local n = targetKey.name
						if type(n) ~= "string" or type(t) ~= "string" then return nil, nil end
						t = string.lower(t)
						if t == "trinket" then
							return Isaac.GetTrinketIdByName(n), true
						else
							-- treat active/passive/collectible the same for ID resolution
							return Isaac.GetItemIdByName(n), false
						end
					end
					return nil, nil
				end

				for key, data in pairs(ConchBlessing.ItemData) do
                    if data and data.synergies and data.id and data.id ~= -1 then
						for targetKey, text in pairs(data.synergies) do
						local targetId, targetIsTrinket = resolveTargetId(targetKey)
						if type(targetId) == "number" and targetId > 0 then
								ConchBlessing._synergyByTarget[targetId] = ConchBlessing._synergyByTarget[targetId] or {}
							table.insert(ConchBlessing._synergyByTarget[targetId], { key = key, text = text, targetIsTrinket = targetIsTrinket })
								ConchBlessing._synergyByMod[data.id] = ConchBlessing._synergyByMod[data.id] or {}
							table.insert(ConchBlessing._synergyByMod[data.id], { target = targetId, targetIsTrinket = targetIsTrinket, text = text })
							end
                        end
                    end
                end
                ConchBlessing._builtSynergyMaps = true
            end

            -- Helper: check if any player has a collectible or trinket with given ID
			-- Synergy text may carry %TOKEN% placeholders that an item fills with a live
			-- value at render time (ConchBlessing.EIDDynamicTokens[TOKEN] returns a string).
			-- An unknown token or a failing resolver leaves the text as written.
			local function expandDynamicTokens(text)
				local function expand(line)
					if type(line) ~= "string" or not line:find("%", 1, true) then return line end
					return (line:gsub("%%([%u_]+)%%", function(name)
						local resolver = ConchBlessing.EIDDynamicTokens and ConchBlessing.EIDDynamicTokens[name]
						if type(resolver) ~= "function" then return nil end
						local ok, value = pcall(resolver)
						if ok and value ~= nil then return tostring(value) end
						return nil
					end))
				end
				if type(text) == "table" then
					local lines = {}
					for i = 1, #text do lines[i] = expand(text[i]) end
					return lines
				end
				return expand(text)
			end

			-- isTrinket: true checks only trinkets, false only collectibles, nil both.
			-- Trinket and collectible ids overlap (The Twins and Tooth Picks are both 183).
			local function anyPlayerHas(id, isTrinket)
				if type(id) ~= "number" then return false end
                local game = Game()
                local n = game:GetNumPlayers()
                for i = 0, n - 1 do
                    local p = game:GetPlayer(i)
                    if p then
                        if isTrinket ~= true and p:HasCollectible(id) then return true end
                        if isTrinket ~= false and p:HasTrinket(id) then return true end
                    end
                end
                return false
            end

            -- Helper: determine if an ID corresponds to a trinket in config
            local function isTrinketId(id)
                local cfg = Isaac.GetItemConfig()
                if not cfg then return false end
                return cfg:GetTrinket(id) ~= nil
            end

            -- EID description modifiers run every render frame, so an unconditional
            -- printDebug here repeats the same line thousands of times a minute.
            -- Messages carry their own ids, so one line per distinct message is enough.
            local eidLoggedOnce = {}
            local function eidDebugOnce(message)
                if eidLoggedOnce[message] then return end
                eidLoggedOnce[message] = true
                ConchBlessing.printDebug(message)
            end

            if not ConchBlessing._didRegisterUnifiedModifier then
                EID:addDescriptionModifier(
                    "ConchBlessing_ByOriginType",
                    function(descObj)
                        -- Support both Collectibles (100) and Trinkets (350)
                        return descObj.ObjType == 5 and (descObj.ObjVariant == 100 or descObj.ObjVariant == 350)
                    end,
                    function(descObj)
                        local lang = resolveModLang()
                        -- Base item descriptions can show live values even when
                        -- the player has no synergy item yet.
                        descObj.Description = expandDynamicTokens(descObj.Description)
                        -- 0) Dynamic specials scaling for our items (EID text):
                        --    If this is our item and it has specials, multiply matching numbers by scale
                        --    Scale rules (trinket): Golden +1x, Mom's Box +1x; both => x3. Only exact specials values are scaled.
                        do
                            local rawSub = descObj.ObjSubType or -1
                            local isTrinketPickup = (descObj.ObjVariant == 350)
                            local baseId = rawSub
                            local goldenPickup = false
                            if isTrinketPickup and rawSub >= 32768 then
                                baseId = rawSub - 32768
                                goldenPickup = true
                            end
                            -- Build reverse id->key map once
                            if not ConchBlessing._idToItemKey then
                                ConchBlessing._idToItemKey = {}
                                for key, data in pairs(ConchBlessing.ItemData or {}) do
                                    if type(data.id) == "number" and data.id > 0 then
                                        ConchBlessing._idToItemKey[data.id] = key
                                    end
                                end
                            end
                            local itemKey = ConchBlessing._idToItemKey[baseId]
                            local itemData = itemKey and ConchBlessing.ItemData[itemKey] or nil
                            if itemData and itemData.specials and descObj.Description then
                                -- Determine scale only for trinkets
                                local scale = 1
                                if isTrinketPickup then
                                    if goldenPickup then scale = scale + 1 end
                                    if anyPlayerHas(CollectibleType.COLLECTIBLE_MOMS_BOX) then scale = scale + 1 end
                                end
                                if scale > 1 then
                                    -- Flatten specials list from { normal = X or {..} }
                                    local values = {}
                                    local function pushVal(v)
                                        if type(v) == "number" then table.insert(values, v) end
                                    end
                                    if type(itemData.specials.normal) == "table" then
                                        for _, v in ipairs(itemData.specials.normal) do pushVal(v) end
                                    else
                                        pushVal(itemData.specials.normal)
                                    end
                                    -- Replace exact tokens in Description
                                    local text = descObj.Description
                                    -- Only replace decimal tokens (e.g., 4.0), never plain integers (e.g., 4)
                                    for _, v in ipairs(values) do
                                        local sDec = string.format("%.1f", v)
                                        local patDec = "%f[%d]" .. sDec:gsub('%.', '%%.') .. "%f[^%d]"
                                        if text:find(patDec) then
                                            local rep = string.format("%.1f", v * scale)
                                            rep = "{{ColorYellow}}" .. rep .. "{{CR}}"
                                            text = text:gsub(patDec, rep)
                                        else
                                            local sInt = tostring(math.floor(v + 0.0))
                                            local patInt = "%f[%d]" .. sInt .. "%f[^%d]"
                                            -- Only replace integer tokens when decimal form is not present
                                            text = text:gsub(patInt, function(match)
                                                local repInt = tostring(math.floor(v * scale + 0.0))
                                                return "{{ColorYellow}}" .. repInt .. "{{CR}}"
                                            end)
                                        end
                                    end
                                    descObj.Description = text
                                end
                            end
                        end
                        -- Conch mode (origin) part (Select appropriate origin category based on pickup type)
                        local subId = descObj.ObjSubType
                        if descObj.ObjVariant == 350 and subId and subId >= 32768 then
                            -- Golden trinket: strip golden flag to match origin/synergy maps
                            subId = subId - 32768
                        end
						
						-- Select origin category based on pickup variant (Use collectible or trinket category based on actual pickup type)
						local originCategory = nil
						local pickupTypeName = "unknown"
						if descObj.ObjType == 5 then
							if descObj.ObjVariant == 100 then
								originCategory = "collectible"
								pickupTypeName = "collectible"
							elseif descObj.ObjVariant == 350 then
								originCategory = "trinket"
								pickupTypeName = "trinket"
							end
						end
						
						eidDebugOnce("[EID] Checking pickup: ObjType=" .. tostring(descObj.ObjType) .. ", Variant=" .. tostring(descObj.ObjVariant) .. ", SubType=" .. tostring(subId) .. ", category=" .. tostring(originCategory))
						
						if not originCategory then
							eidDebugOnce("[EID] Skipping: not a collectible or trinket pickup")
							return descObj
						end
						
						local originMaps = ConchBlessing._originItemFlags or {}
						local itemKeys = originMaps[originCategory] and originMaps[originCategory][subId] or nil
						local templates = ConchBlessing._conchModeTemplates or {}
						
						if itemKeys and templates[lang] then
                            local cacheKey = originCategory .. "|" .. tostring(subId) .. "|" .. lang
                            local cached = ConchBlessing._conchDescCache[cacheKey]
                            if not cached then
                                local lines = {}
                                local order = { "positive", "neutral", "negative" }
                                for _, f in ipairs(order) do
                                    for _, dynKey in ipairs(itemKeys) do
                                        local d = ConchBlessing.ItemData[dynKey]
                                        if d and d.flag == f then
                                            local name = (type(d.name) == "table" and (d.name[lang] or d.name.en)) or d.name or dynKey
                                            local tmpl = templates[lang] and templates[lang][f]
                                            if tmpl then
                                                local iconNameDyn = "icon_" .. string.lower(dynKey)
                                                local finalLine = string.gsub(tmpl, "{{item_name}}", "{{" .. iconNameDyn .. "}}(" .. name .. ")")
                                                table.insert(lines, "#{{ConchMode}} " .. finalLine)
                                            end
                                        end
                                    end
                                end
                                cached = table.concat(lines, "")
                                ConchBlessing._conchDescCache[cacheKey] = cached
                            end
                            if cached and #cached > 0 then
								eidDebugOnce("[EID] Conch attach OK: " .. pickupTypeName .. " id=" .. tostring(subId) .. ", keys=" .. tostring(table.concat(itemKeys, ",")))
                                EID:appendToDescription(descObj, cached)
                            end
						else
							eidDebugOnce("[EID] Conch attach SKIP: no " .. pickupTypeName .. " mapping for id=" .. tostring(subId))
						end

                        -- Synergy part
                        -- Prevent duplicate lines when self-synergy (e.g. Dragon -> Dragon)
                        -- is matched by both target and mod views in the same pass.
                        local appendedSynergyPairs = {}
                        local function shouldAppendSynergy(sourceId, targetId)
                            local key = tostring(sourceId) .. "->" .. tostring(targetId)
                            if appendedSynergyPairs[key] then
                                return false
                            end
                            appendedSynergyPairs[key] = true
                            return true
                        end

                        local targets = ConchBlessing._synergyByTarget and ConchBlessing._synergyByTarget[subId]
                        if targets then
						for _, entry in ipairs(targets) do
							local d = ConchBlessing.ItemData[entry.key]
							local typeMatches = entry.targetIsTrinket == nil
								or (entry.targetIsTrinket == true and descObj.ObjVariant == 350)
								or (entry.targetIsTrinket == false and descObj.ObjVariant == 100)
							if typeMatches and d and d.id and anyPlayerHas(d.id) and shouldAppendSynergy(d.id, subId) then
								local t = expandDynamicTokens((type(entry.text) == "table" and (entry.text[lang] or entry.text.en)) or entry.text)
								local iconToken
								if entry.targetIsTrinket == true then
									iconToken = "{{Trinket" .. tostring(subId) .. "}}"
								elseif entry.targetIsTrinket == false then
									iconToken = "{{Collectible" .. tostring(subId) .. "}}"
								else
									iconToken = "{{icon_" .. string.lower(entry.key) .. "}}"
								end
                                    local function normLine(s)
                                        s = tostring(s or "")
                                        -- strip leading # to avoid double newlines
                                        return (s:gsub("^#+", ""))
                                    end
                                    local msg
                                    if type(t) == "table" then
                                        msg = ""
                                        for i = 1, #t do
                                            msg = msg .. "#" .. iconToken .. " " .. normLine(t[i])
                                        end
                                    else
                                        msg = "#" .. iconToken .. " " .. normLine(t)
                                    end
                                    EID:appendToDescription(descObj, msg)
                                end
                            end
                        end

                        local asMod = ConchBlessing._synergyByMod and ConchBlessing._synergyByMod[subId]
                        if asMod then
                            for _, entry in ipairs(asMod) do
                                if anyPlayerHas(entry.target, entry.targetIsTrinket) and shouldAppendSynergy(subId, entry.target) then
                                    local t = expandDynamicTokens((type(entry.text) == "table" and (entry.text[lang] or entry.text.en)) or entry.text)
                                    local iconToken
                                    -- Use the explicitly stored targetIsTrinket flag from synergy definition
                                    eidDebugOnce("[EID Synergy] Processing target ID: " .. tostring(entry.target) .. ", targetIsTrinket flag: " .. tostring(entry.targetIsTrinket))
                                    if entry.targetIsTrinket == true then
                                        iconToken = "{{Trinket" .. tostring(entry.target) .. "}}"
                                        eidDebugOnce("[EID Synergy] Using Trinket icon for ID: " .. tostring(entry.target))
                                    elseif entry.targetIsTrinket == false then
                                        iconToken = "{{Collectible" .. tostring(entry.target) .. "}}"
                                        eidDebugOnce("[EID Synergy] Using Collectible icon for ID: " .. tostring(entry.target))
                                    else
                                        -- Fallback: auto-detect if type was not explicitly specified
                                        local isTrinket = isTrinketId(entry.target)
                                        eidDebugOnce("[EID Synergy] Auto-detecting type for ID: " .. tostring(entry.target) .. ", isTrinket: " .. tostring(isTrinket))
                                        if isTrinket then
                                            iconToken = "{{Trinket" .. tostring(entry.target) .. "}}"
                                        else
                                            iconToken = "{{Collectible" .. tostring(entry.target) .. "}}"
                                        end
                                    end
                                    local function normLine(s)
                                        s = tostring(s or "")
                                        return (s:gsub("^#+", ""))
                                    end
                                    local msg
                                    if type(t) == "table" then
                                        msg = ""
                                        for i = 1, #t do
                                            msg = msg .. "#" .. iconToken .. " " .. normLine(t[i])
                                        end
                                    else
                                        msg = "#" .. iconToken .. " " .. normLine(t)
                                    end
                                    EID:appendToDescription(descObj, msg)
                                end
                            end
                        end
                        return descObj
                    end
                )
            end
        end

        ConchBlessing._didGenerateConchDescriptions = true
        ConchBlessing.printDebug("Conch mode descriptions generated successfully!")

        local function registerEIDIcons()
            if ConchBlessing._eidIconsAdded then return end
            if EID then
                ConchBlessing.printDebug("Adding item icons to EID after game start...")
                
                local ICON_PATHS = {
                    collectibles = "gfx/items/collectibles/",
                    ui = "gfx/ui/"
                }
                
                -- Rep/Rep+ safe: use our minimal 1-layer ANM2 template and size via EID's width/height
                local conchIconSprite = Sprite()
                conchIconSprite:Load("gfx/ui/eid_icon_template_third.anm2", true)
                ConchBlessing.printDebug("[EID Icon] Template(1/3) loaded (conch)")
                conchIconSprite:ReplaceSpritesheet(0, ICON_PATHS.ui .. 'MagicConch.png', true)
                ConchBlessing.printDebug("[EID Icon] Spritesheet replaced (conch)")
                conchIconSprite:LoadGraphics()
                EID:addIcon("ConchMode", "Idle", 0, 16, 16, 9, 5, conchIconSprite)
                -- Also register a dedicated mod-indicator icon key
                EID:addIcon("ConchBlessing ModIcon", "Idle", 0, 16, 16, 9, 5, conchIconSprite)
                
                for itemKey, itemData in pairs(ConchBlessing.ItemData) do
                    local iconName = "icon_" .. string.lower(itemKey)
                    local iconPath = ""
                    
                    if itemData.type == "active" or itemData.type == "passive" then
                        iconPath = ICON_PATHS.collectibles .. string.lower(itemKey) .. ".png"
                    elseif itemData.type == "trinket" then
                        iconPath = "gfx/items/trinkets/" .. string.lower(itemKey) .. ".png"
                    elseif itemData.type == "familiar" then
                        iconPath = ICON_PATHS.collectibles .. string.lower(itemKey) .. ".png"
                    else
                        iconPath = ICON_PATHS.collectibles .. string.lower(itemKey) .. ".png"
                    end
                    
                    local success, itemIconSprite = pcall(function()
                        local sprite = Sprite()
                        sprite:Load("gfx/ui/eid_icon_template_half.anm2", true)
                        ConchBlessing.printDebug("[EID Icon] Template(1/2) loaded for " .. itemKey)
                        sprite:ReplaceSpritesheet(0, iconPath, true)
                        ConchBlessing.printDebug("[EID Icon] Spritesheet replaced for " .. itemKey .. ", path=" .. iconPath)
                        sprite:LoadGraphics()
                        return sprite
                    end)
                    
                    if success and itemIconSprite then
                        ConchBlessing.printDebug("Attempting to add EID icon: " .. iconName .. " with path: " .. iconPath)
                        EID:addIcon(iconName, "Idle", 0, 16, 16, 10, 5, itemIconSprite)
                        ConchBlessing.printDebug("Successfully added EID icon for " .. itemKey .. ": " .. iconName .. " -> " .. iconPath)
                    else
                        ConchBlessing.printDebug("Failed to create sprite for " .. itemKey .. " (path: " .. iconPath .. ")")
                    end
                end
                
                -- Ensure EID mod indicator shows our mod name and icon (like Epiphany)
                local prevCurrentMod = EID._currentMod
                EID._currentMod = "Conch's Blessing"
                EID.ModIndicator = EID.ModIndicator or {}
                EID.ModIndicator["Conch's Blessing"] = EID.ModIndicator["Conch's Blessing"] or { Name = "Conch's Blessing", Icon = nil }
                if EID.setModIndicatorName then
                    EID:setModIndicatorName("Conch's Blessing")
                end
                if EID.setModIndicatorIcon then
                    EID:setModIndicatorIcon("ConchBlessing ModIcon")
                end
                -- restore previous mod context to avoid affecting other mods
                EID._currentMod = prevCurrentMod

                ConchBlessing.printDebug("Item icons added to EID successfully!")
                ConchBlessing._eidIconsAdded = true
                
                if EID and EID.icons then
                    ConchBlessing.printDebug("EID icons loaded. Available icons:")
                    for iconName, _ in pairs(EID.icons) do
                        ConchBlessing.printDebug("  - " .. iconName)
                    end
                else
                    ConchBlessing.printDebug("Warning: EID.icons not available")
                end
            else
                ConchBlessing.printDebug("EID not available during POST_GAME_STARTED")
            end
        end

        ConchBlessing:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
            registerEIDIcons()
        end)

        ConchBlessing:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
            if EID and not ConchBlessing._eidIconsAdded then
                ConchBlessing.printDebug("EID detected late; registering icons now...")
                registerEIDIcons()
            end
        end)
    else
        ConchBlessing.printDebug("Conch mode descriptions already generated; skipping.")
    end
    
    ConchBlessing.printDebug("Scripts loaded successfully!")
end

loadAllItems()

-- All behavior modules now exist, so register their callbacks before the first
-- MC_POST_GAME_STARTED dispatch. The manager keeps its game-start hook only as
-- a fallback for unusual load ordering.
if ConchBlessing.CallbackManager
    and type(ConchBlessing.CallbackManager.registerAllCallbacks) == "function"
then
    ConchBlessing.CallbackManager.registerAllCallbacks()
else
    ConchBlessing.printError("CallbackManager unavailable after item script loading")
end

-- Signal that ItemData is fully loaded and ready
ConchBlessing.ItemDataReady = true
ConchBlessing.printDebug("ItemData is now fully loaded and ready for use!")

-- item pools are handled in the XML file (content/itempools.xml)
ConchBlessing.printDebug("Item pools are handled in the XML file (content/itempools.xml)")

-- item management functions (add as needed)

-- Apply natural spawn setting: remove our items from pools unless enabled
local function applyNaturalSpawnSetting()
    local pool = Game():GetItemPool()
    if not pool then return end
    local cfg = ConchBlessing.Config or {}
    local allowGlobal = cfg.naturalSpawn
    local allowCollectibles = (cfg.spawnCollectibles == true)
    local allowTrinkets = (cfg.spawnTrinkets == true)
    for _, itemData in pairs(ConchBlessing.ItemData) do
        if itemData.id and itemData.id ~= -1 then
            local isTrinket = (itemData.type == "trinket")
            local allowType = isTrinket and allowTrinkets or allowCollectibles
            -- legacy global toggle still grants allow if ON
            if not (allowGlobal or allowType) then
                -- Remove from all pools (call once is enough; engine tracks per-pool)
                if isTrinket then
                    ConchBlessing.printDebug("[Pool] Removing trinket from pools: id=" .. tostring(itemData.id))
                    pool:RemoveTrinket(itemData.id)
                else
                    ConchBlessing.printDebug("[Pool] Removing collectible from pools: id=" .. tostring(itemData.id))
                    pool:RemoveCollectible(itemData.id)
                end
            end
        end
    end
end

ConchBlessing:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
    applyNaturalSpawnSetting()
end)

-- Also apply when entering a new level (fresh pools)
ConchBlessing:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, function()
    applyNaturalSpawnSetting()
end)

-- Ensure minus chain evolution logic is loaded
pcall(function() require("scripts.items.trinkets.minus_chain") end)

-- Dev tooling: registers the conch_rng console probe. Safe to remove.
pcall(function() require("scripts.dev.rng_probe") end)

-- Dev tooling: registers the conch_round console probe. Safe to remove.
do
    local ok, err = pcall(require, "scripts.dev.stat_rounding_probe")
    if not ok then
        ConchBlessing.printError("[StatRoundingProbe] load failed: " .. tostring(err))
    end
end

-- Dev tooling: registers the conch_cronus test bench. Safe to remove.
do
    local ok, err = pcall(require, "scripts.dev.cronus_probe")
    if not ok then
        ConchBlessing.printError("[CronusProbe] load failed: " .. tostring(err))
    end
end

-- Dev tooling: registers the conch_liveeye test bench. Safe to remove.
do
    local ok, err = pcall(require, "scripts.dev.liveeye_probe")
    if not ok then
        ConchBlessing.printError("[LiveEyeProbe] load failed: " .. tostring(err))
    end
end

-- Dev tooling: registers the conch_locale test bench. Safe to remove.
do
    local ok, err = pcall(require, "scripts.dev.locale_probe")
    if not ok then
        ConchBlessing.printError("[LocaleProbe] load failed: " .. tostring(err))
    end
end

-- Dev tooling: registers the conch_appraisal test bench. Safe to remove.
do
    local ok, err = pcall(require, "scripts.dev.appraisal_probe")
    if not ok then
        ConchBlessing.printError("[AppraisalProbe] load failed: " .. tostring(err))
    end
end
