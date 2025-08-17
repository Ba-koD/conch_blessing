-- ItemData table
-- available attributes:
--   type: "passive" | "active" | "familiar" | "null" - item type
--   id: Isaac.GetItemIdByName("item name") - item ID (generated from XML)
--   name: "item name" - item display name
--   description: "description" - item description
--   pool: { RoomType.ROOM_XXX, ... } - item pools it appears in (can specify multiple pools as an array)
--     possible pools: ROOM_DEFAULT, ROOM_SHOP, ROOM_TREASURE, ROOM_BOSS, ROOM_MINIBOSS, ROOM_SECRET, ROOM_ARCADE, ROOM_CURSE, ROOM_CHALLENGE, ROOM_LIBRARY, ROOM_SACRIFICE, ROOM_DEVIL, ROOM_ANGEL, ROOM_DUNGEON, ROOM_BOSSRUSH, ROOM_ISAACS, ROOM_BARREN, ROOM_CHEST, ROOM_DICE, ROOM_BLACK_MARKET, ROOM_GREED_EXIT, ROOM_PLANETARIUM, ROOM_TELEPORTER, ROOM_TELEPORTER_EXIT, ROOM_SECRET_EXIT, ROOM_BLUE, ROOM_ULTRASECRET
--     pool can be specified as:
--       - RoomType.ROOM_XXX (uses default values: weight=1.0, decrease_by=1, remove_on=0.1)
--       - {RoomType.ROOM_XXX, weight=1.0, decrease_by=1, remove_on=0.1} (custom values)
--   weight: number - item weight in pool (higher number means more frequent appearance)
--   DecreaseBy: number - weight decrease when item is selected from pool
--   RemoveOn: number - probability of item being removed from pool (0.0-1.0)
--   quality: number - item quality (0-5, 5 is highest quality)
--   tags: "tag1 tag2" - item tags (offensive, defensive, summonable, mushroom, devil, angel, etc.)
--     possible tags: dead, syringe, mom, tech, battery, guppy, fly, bob, mushroom, baby, angel, devil, poop, book, spider, quest, monstermanual, nogreed
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
--     pickup: "function name" - called when item is picked up
--     use: "function name" - called when item is used
--     evaluateCache: "function name" - called when cache is calculated
--     tearHit: "function name" - called when tear hits
--     tearCollision: "function name" - called when tear collides
--     gameStarted: "function name" - called when game starts

-- Conch's Blessing - Items System
-- Item information and callback management system

-- Load template system for upgrade animations
ConchBlessing.template = require("scripts.template")
require("scripts.lib.stats")

ConchBlessing.printDebug("Item system loaded!")

-- check if ModCallbacks is defined
if not ModCallbacks then
    ConchBlessing.printError("Error: ModCallbacks is not defined!")
    return
end

-- define ItemData table
ConchBlessing.ItemData = {
    LIVE_EYE = {
        type = "passive",
        id = Isaac.GetItemIdByName("Live Eye"),
        name = {
            kr = "살아있는 눈", -- Korean
            en = "Live Eye"
        },
        description = {
            kr = "놓쳐도 괜찮아", -- Korean
            en = "Misses happen",
        },
        eid ={
            kr = {"몬스터를 적중시킬때 마다 {{Damage}}데미지 배수가 0.1씩 증가합니다.",
            "#몬스터에 맞지 않으면 {{Damage}}데미지 배수가 0.15씩 감소합니다.",
            "#{{Damage}}최대/최소 데미지 배수 (x3.0/x0.75)"},
            en = {"{{Damage}}Damage multiplier increases by 0.1 as you hit enemies.",
            "#{{Damage}}Damage multiplier decreases by 0.15 as you miss enemies.",
            "#{{Damage}}Damage multiplier is capped at 3.0 and cannot go below 0.75."},
        },
        pool = {
            -- Use default values (weight=1.0, decrease_by=1, remove_on=0.1)
            RoomType.ROOM_ANGEL,
            RoomType.ROOM_ULTRASECRET
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
        origin = CollectibleType.COLLECTIBLE_DEAD_EYE, -- original item information
        flag = "positive", -- match Magic Conch result type
        script = "scripts/items/live_eye",
        -- optional functions/effects around morph
        -- onBeforeChange / upgradeEffectsBefore: run BEFORE morph
        -- onAfterChange / upgradeEffectsAfter: run AFTER morph
        -- Back-compat: onUpgrade / upgradeEffects act as AFTER
        onBeforeChange = "liveeye.onBeforeChange",
        onAfterChange = "liveeye.onAfterChange",
        callbacks = {
            pickup = "liveeye.onPickup",
            evaluateCache = "liveeye.onEvaluateCache",
            fireTear = "liveeye.onFireTear",
            tearCollision = "liveeye.onTearCollision",
            tearRemoved = "liveeye.onTearRemoved",
            gameStarted = "liveeye.onGameStarted",
            update = "liveeye.onUpdate"
        }
    },
    VOID_DAGGER = {
        type = "passive",
        id = Isaac.GetItemIdByName("Void Dagger"),
        name = {
            kr = "공허의 단검",
            en = "Void Dagger"
        },
        description = {
            kr = "공허가 열린다",
            en = "The void opens"
        },
        eid = {
            kr = {
                "#적에게 명중 시 확률로 그 위치에 내 데미지의 보이드 링을 소환합니다.",
                "#확률은 (30 - {{Tears}}연사)%로 5%보다 작아지지 않습니다",
                "#위 확률은 {{Luck}}운에 따라 (1+0.1×{{Luck}}운) 배수로 증가합니다. (최대 2배)",
                "#지속시간은 {{Damage}}데미지에 따라 증가하며 데미지 10당 6단계로 증가합니다.",
                "#{{BlackHeart}}블랙하트는 드랍되지 않습니다."
            },
            en = {
                "#On hit, has a chance to spawn a void ring at the impact that deals your damage",
                "#Chance is (30 − {{Tears}}Tears)% guaranteed 5%",
                "#chance is increased by (1+0.1×{{Luck}}Luck) (up to 2x)",
                "#Duration increases by 10 frames per 10 {{Damage}}Damage by 6 steps",
                "#{{BlackHeart}}No black heart drops"
            }
        },
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
        origin = CollectibleType.COLLECTIBLE_ATHAME,
        flag = "neutral",
        script = "scripts/items/void_dagger",
        callbacks = {
            tearCollision = "voiddagger.onTearCollision",
            update = "voiddagger.onUpdate",
            postPlayerUpdate = "voiddagger.onPlayerUpdate"
        },
        -- Upgrade visuals (Neutral flavor)
        onBeforeChange = "voiddagger.onBeforeChange",
        onAfterChange = "voiddagger.onAfterChange",
    },
    ETERNAL_FLAME = {
        type = "passive",
        id = Isaac.GetItemIdByName("Eternal Flame"),
        name = {
            kr = "영원한 불꽃",
            en = "Eternal Flame"
        },
        description = {
            kr = "정화의 불길",
            en = "Baptize with fire"
        },
        eid = {
            kr = {
                "저주가 걸릴 때마다 저주를 제거합니다.",
                "#저주 제거 시 고정 데미지 +3.0, 연사 +1.0을 영구적으로 부여합니다.",
                "#저주가 걸릴 확률이 증가합니다."
            },
            en = {
                "Removes curses when they are applied.",
                "#Grants fixed damage +3.0 and fixed fire rate +1.0 permanently when removing curses.",
                "#Increases curse chance."
            }
        },
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
        origin = CollectibleType.COLLECTIBLE_BLACK_CANDLE,
        flag = "positive",
        script = "scripts/items/eternal_flame",
        callbacks = {
            pickup = "eternalflame.onPickup",
            postPlayerUpdate = "eternalflame.onPlayerUpdate",
            evaluateCache = "eternalflame.onEvaluateCache",
            postNewLevel = "eternalflame.onNewLevel",
            postNewRoom = "eternalflame.onNewRoom",
            postCurseEval = "eternalflame.onCurseEval",
            update = "eternalflame.onUpdate"
        },
        onBeforeChange = "eternalflame.onBeforeChange",
        onAfterChange = "eternalflame.onAfterChange",
    },
    ORAL_STEROIDS = {
        type = "passive",
        id = Isaac.GetItemIdByName("Oral Steroids"),
        name = {
            kr = "경구형 스테로이드",
            en = "Oral Steroids"
        },
        description = {
            kr = "주사는 무서워",
            en = "Shots are scary"
        },
        eid = {
            kr = {
                "획득시 모든 스탯이 0.8 ~ 1.5배가 됩니다."
            },
            en = {
                "All stats are changed to 0.8 ~ 1.5x when obtained"
            }
        },
        pool = {
            RoomType.ROOM_DEVIL,
            RoomType.ROOM_CURSE,
            RoomType.ROOM_BLACK_MARKET,
            RoomType.ROOM_SECRET
        },
        quality = 2,
        tags = "offensive",
        cache = "all",
        hidden = false,
        shopprice = 15,
        devilprice = 1,
        origin = CollectibleType.COLLECTIBLE_EXPERIMENTAL_TREATMENT,
        flag = "neutral",
        script = "scripts/items/oral_steroids",
        callbacks = {
            postGetCollectible = "oralsteroids.onGetCollectible",
            evaluateCache = "oralsteroids.onEvaluateCache",
            gameStarted = "oralsteroids.onGameStarted",
            update = "oralsteroids.onUpdate"
        },
        onBeforeChange = "oralsteroids.onBeforeChange",
        onAfterChange = "oralsteroids.onAfterChange",
    },
    INJECTABLE_STEROIDS = {
        type = "active",
        id = Isaac.GetItemIdByName("Injectable Steroids"),
        name = {
            kr = "주사 스테로이드",
            en = "Injectable Steroids"
        },
        description = {
            kr = "힘을 원해...",
            en = "I need more power..."
        },
        eid = {
            kr = {
                "사용시 모든 스탯이 0.5 ~ 2.0배가 됩니다.",
                "#층 변경시 충전이 초기화됩니다.",
                "#{{Warning}} 몸이 점점 노래집니다..."
            },
            en = {
                "All stats are changed to 0.5 ~ 2.0x when used",
                "#Charge is reset when changing floors",
                "#{{Warning}}Your body is getting weaker..."
            }
        },
        pool = {
            RoomType.ROOM_DEVIL,
            RoomType.ROOM_CURSE,
            RoomType.ROOM_BLACK_MARKET,
            RoomType.ROOM_ULTRASECRET
        },
        quality = 3,
        tags = "offensive",
        cache = "all",
        hidden = false,
        shopprice = 15,
        devilprice = 2,
        maxcharges = 1,
        chargetype = "special",
        initcharge = 1,
        origin = CollectibleType.COLLECTIBLE_EXPERIMENTAL_TREATMENT,
        flag = "negative",
        script = "scripts/items/injectable_steroids",
        callbacks = {
            use = "injectablsteroids.onUseItem",
            postGetCollectible = "injectablsteroids.onGetCollectible",
            evaluateCache = "injectablsteroids.onEvaluateCache",
            gameStarted = "injectablsteroids.onGameStarted",
            newLevel = "injectablsteroids.onNewLevel",
            update = "injectablsteroids.onUpdate"
        },
        onBeforeChange = "injectablsteroids.onBeforeChange",
        onAfterChange = "injectablsteroids.onAfterChange",
    },
}

-- automatically load scripts and callbacks based on ItemData
local function loadAllItems()
    ConchBlessing.printDebug("Loading scripts and callbacks based on ItemData...")
    
    -- Load external systems
    local systems = {
        { name = "EID language support", path = "scripts.eid_language" },
        { name = "Callback manager", path = "scripts.callback_manager" }
    }
    
    -- Load external systems only once per run
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
    
    -- Load item scripts
    -- Load item scripts only once per run
    if not ConchBlessing._didLoadItemScripts then
        for itemKey, itemData in pairs(ConchBlessing.ItemData) do
            ConchBlessing.printDebug("Processing: " .. itemKey)
            local scriptPath = itemData.script
            if not scriptPath then
                ConchBlessing.printError("  Warning: " .. itemKey .. " has no script path!")
            else
                ConchBlessing.printDebug("  Loading script: " .. scriptPath)
                local scriptSuccess, scriptErr = pcall(function()
                    require(scriptPath)
                end)
                if scriptSuccess then
                    ConchBlessing.printDebug("  Script loaded successfully: " .. scriptPath)
                else
                    ConchBlessing.printError("  Script load failed: " .. scriptPath .. " - " .. tostring(scriptErr))
                end
            end
            ConchBlessing.printDebug("  " .. itemKey .. " processed")
        end
        ConchBlessing._didLoadItemScripts = true
    else
        ConchBlessing.printDebug("Item scripts already loaded; skipping.")
    end
    
    ConchBlessing.printDebug("Scripts loaded successfully!")
end

loadAllItems()

-- item pools are handled in the XML file (content/itempools.xml)
ConchBlessing.printDebug("Item pools are handled in the XML file (content/itempools.xml)")

-- item management functions (add as needed)

-- Apply natural spawn setting: remove our items from pools unless enabled
local function applyNaturalSpawnSetting()
    local pool = Game():GetItemPool()
    if not pool then return end
    local allow = ConchBlessing.Config and ConchBlessing.Config.naturalSpawn
    for _, itemData in pairs(ConchBlessing.ItemData) do
        if itemData.id and itemData.id ~= -1 then
            if not allow then
                -- Remove from all pools (call once is enough; engine tracks per-pool)
                pool:RemoveCollectible(itemData.id)
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
