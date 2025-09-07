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
--     pickup: "function name" - called when item is picked up
--     use: "function name" - called when item is used
--     evaluateCache: "function name" - called when cache is calculated
--     tearHit: "function name" - called when tear hits
--     tearCollision: "function name" - called when tear collides
--     gameStarted: "function name" - called when game starts
--   WorkingNow: true/false - item is working now

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
            "#{{Damage}} 최대/최소 데미지 배수 (x3.0/x0.75)"},
            en = {"{{Damage}} Damage multiplier increases by 0.1 as you hit enemies.",
            "#{{Damage}} Damage multiplier decreases by 0.15 as you miss enemies.",
            "#{{Damage}} Damage multiplier is capped at 3.0 and cannot go below 0.75."},
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
        },
        synergies = {
            [CollectibleType.COLLECTIBLE_ROCK_BOTTOM] = {
                kr = "획득하는 즉시 데미지 배수가 최대치가 됩니다",
                en = "When obtained, damage multiplier is set to the maximum value"
            },
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
                "#눈물이 적에게 명중 시 확률로 그 위치에 내 데미지의 보이드 링을 소환합니다.",
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
                "#이터널 하트 1개를 획득합니다."
            },
            en = {
                "Removes curses when they are applied.",
                "#Grants fixed damage +3.0 and fixed fire rate +1.0 permanently when removing curses.",
                "#Gains 1 eternal heart."
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
            update = "eternalflame.onUpdate",
            gameStarted = "eternalflame.onGameStarted"
        },
        onBeforeChange = "eternalflame.onBeforeChange",
        onAfterChange = "eternalflame.onAfterChange",
    },
    POWER_TRAINING = {
        type = "active",
        id = Isaac.GetItemIdByName("Power Training"),
        name = {
            kr = "파워 트레이닝",
            en = "Power Training"
        },
        description = {
            kr = "라잇웨잇 베이비!",
            en = "Lightweight Baby!"
        },
        eid = {
            kr = {
                "사용시 데미지, 연사, 사거리, 행운이 1.0~1.3배가 됩니다.",
                "#중첩시 합연산으로 증가합니다."
            },
            en = {
                "Damage, tears, range, and luck are changed to 1.0~1.3x when used",
                "#When stacked, increases by addition"
            }
        },
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
        initcharge = 0,
        origin = CollectibleType.COLLECTIBLE_EXPERIMENTAL_TREATMENT,
        flag = "positive",
        script = "scripts/items/power_training",
        callbacks = {
            use = "powertraining.onUseItem",
            evaluateCache = "powertraining.onEvaluateCache",
            gameStarted = "powertraining.onGameStarted",
            update = "powertraining.onUpdate"
        },
        onBeforeChange = "powertraining.onBeforeChange",
        onAfterChange = "powertraining.onAfterChange",
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
                "획득시 데미지, 연사, 사거리, 행운이 0.8 ~ 1.5배가 됩니다.",
                "#중첩시 합연산으로 증가합니다."
            },
            en = {
                "Damage, fire rate, range, and luck are changed to 0.8 ~ 1.5x when obtained",
                "#When stacked, increases by addition"
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
        cache = "damage firedelay range luck",
        hidden = false,
        shopprice = 15,
        devilprice = 1,
        origin = CollectibleType.COLLECTIBLE_EXPERIMENTAL_TREATMENT,
        flag = "neutral",
        script = "scripts/items/oral_steroids",
        callbacks = {
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
                "사용시 데미지, 연사, 사거리, 행운이 0.5~2.0배가 됩니다.",
                "#스테이지마다 한번 사용할수 있으며 배터리나 방 클리어로 충전되지 않습니다.",
                "#중첩시 합연산으로 증가합니다.",
                "#{{Warning}} 몸이 점점 노래집니다...",
                "#{{Warning}} 1% 확률로 즉사합니다."
            },
            en = {
                "Damage, fire rate, range, and luck are changed to 0.5~2.0x when used",
                "#Can be used once per stage, and is not charged by batteries or clearing rooms",
                "#When stacked, increases by addition",
                "#{{Warning}}Your body is gradually turning yellow...",
                "#{{Warning}}1% chance of instant death when used"
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
        cache = "damage firedelay range luck",
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
            evaluateCache = "injectablsteroids.onEvaluateCache",
            gameStarted = "injectablsteroids.onGameStarted",
            newLevel = "injectablsteroids.onNewLevel",
            update = "injectablsteroids.onUpdate"
        },
        onBeforeChange = "injectablsteroids.onBeforeChange",
        onAfterChange = "injectablsteroids.onAfterChange",
    },
    RAT = {
        WorkingNow = true,
        type = "passive",
        id = Isaac.GetItemIdByName("Rat"),
        name = {
            kr = "자",
            en = "Rat"
        },
        description = {
            kr = "자",
            en = "Rat"
        },
    },
    OX = {
        WorkingNow = true,
        type = "passive",
        id = Isaac.GetItemIdByName("Ox"),
        name = {
            kr = "축",
            en = "Ox"
        },
        description = {
            kr = "축",
            en = "Ox"
        },
    },
    TIGER = {
        WorkingNow = true,
        type = "passive",
        id = Isaac.GetItemIdByName("Tiger"),
        name = {
            kr = "인",
            en = "Tiger"
        },
        description = {
            kr = "인",
            en = "Tiger"
        },
    },
    RABBIT = {
        WorkingNow = true,
        type = "passive",
        id = Isaac.GetItemIdByName("Rabbit"),
        name = {
            kr = "묘",
            en = "Rabbit"
        },
        description = {
            kr = "묘",
            en = "Rabbit"
        },
    },
    DRAGON = {
        type = "passive",
        id = Isaac.GetItemIdByName("Dragon"),
        name = {
            kr = "진",
            en = "Dragon"
        },
        description = {
            kr = "날씨의 신",
            en = "God of Weather"
        },
        eid = {
            kr = {"공중과 지형관통을 얻습니다.",
                  "#방에 입장하고 5초가 지나면, 5블럭 내 최대 5명의 적에게 5초간 지속되는 낙뢰를 내립니다.",
                  "#위 과정이 한싸이클로 방마다 5번씩 반복됩니다.",
                  "#낙뢰는 데미지의 5%만큼 줍니다."
                },
            en = {"Gain flight and Spectral tears.",
                  "#After entering a room for 5 seconds, can shoot up to 5 lightning bolts to up to 5 enemies within 5 blocks for 5 seconds.",
                  "#This process repeats 5 times per room as a cycle.",
                  "#Lightning bolts deal 5% of the player's damage."}
        },
        pool = {
            RoomType.ROOM_TREASURE,
            RoomType.ROOM_PLANETARIUM
        },
        quality = 4,
        tags = "offensive",
        cache = "flying tearflag",
        hidden = false,
        shopprice = 20,
        devilprice = 2,
        origin = CollectibleType.COLLECTIBLE_TAURUS,
        flag = "positive",
        script = "scripts/items/dragon",
        callbacks = {
            evaluateCache = "dragon.onEvaluateCache",
            update = "dragon.onUpdate",
            postNewRoom = "dragon.onNewRoom",
            postRoomEnter = "dragon.onRoomEnter",
            postRoomClear = "dragon.onRoomClear",
            postLaserUpdate = "dragon.onLaserUpdate",
            gameStarted = "dragon.onGameStarted"
        },
        onBeforeChange = "dragon.onBeforeChange",
        onAfterChange = "dragon.onAfterChange",
    },
    SNAKE = {
        WorkingNow = true,
        type = "passive",
        id = Isaac.GetItemIdByName("Snake"),
        name = {
            kr = "사",
            en = "Snake"
        },
        description = {
            kr = "사",
            en = "Snake"
        },
    },
    HORSE = {
        WorkingNow = true,
        type = "passive",
        id = Isaac.GetItemIdByName("Horse"),
        name = {
            kr = "오",
            en = "Horse"
        },
        description = {
            kr = "오",
            en = "Horse"
        },
    },
    GOAT = {
        WorkingNow = true,
        type = "passive",
        id = Isaac.GetItemIdByName("Goat"),
        name = {
            kr = "미",
            en = "Goat"
        },
        description = {
            kr = "미",
            en = "Goat"
        },
    },
    MONKEY = {
        WorkingNow = true,
        type = "passive",
        id = Isaac.GetItemIdByName("Monkey"),
        name = {
            kr = "신",
            en = "Monkey"
        },
    },
    CHICKEN = {
        WorkingNow = true,
        type = "passive",
        id = Isaac.GetItemIdByName("Chicken"),
        name = {
            kr = "유",
            en = "Chicken"
        },
        description = {
            kr = "유",
            en = "Chicken"
        },
    },
    DOG = {
        WorkingNow = true,
        type = "passive",
        id = Isaac.GetItemIdByName("Dog"),
        name = {
            kr = "술",
            en = "Dog"
        },
        description = {
            kr = "술",
            en = "Dog"
        },
    },
    PIG = {
        WorkingNow = true,
        type = "passive",
        id = Isaac.GetItemIdByName("Pig"),
        name = {
            kr = "해",
            en = "Pig"
        },
        description = {
            kr = "해",
            en = "Pig"
        },
    },
}

--[[
Capricorn(염소자리)
↑ {{Heart}}최대 체력 +1
↑ {{Coin}}동전, {{Bomb}}폭탄, {{Key}}열쇠 +1
↑ {{DamageSmall}}공격력 +0.5
↑ {{TearsSmall}}눈물 딜레이 -1
↑ {{RangeSmall}}사거리 +1.5
↑ {{SpeedSmall}}이동속도 +0.1
자 (쥐) Rat

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
    
    local originItemFlags = {}
    
    -- Load item scripts and build origin mapping
    if not ConchBlessing._didLoadItemScripts then
        for itemKey, itemData in pairs(ConchBlessing.ItemData) do
            ConchBlessing.printDebug("Processing: " .. itemKey)
            
            -- Build origin mapping for conch mode descriptions
            if itemData.origin and itemData.flag then
                local originID = itemData.origin
                if not originItemFlags[originID] then
                    originItemFlags[originID] = {}
                end
                table.insert(originItemFlags[originID], itemKey)
                ConchBlessing.printDebug("  Auto-mapped " .. itemKey .. " (flag: " .. itemData.flag .. ") to origin: " .. originID)
            end
            
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
    
    if not ConchBlessing._didGenerateConchDescriptions then
        ConchBlessing.printDebug("Generating conch mode descriptions...")
        
        local conchModeDescriptions = {
            kr = {
                positive = "소라고둥 모드 긍정시 {{item_name}}으로 변환",
                neutral = "소라고둥 모드 중립시 {{item_name}}으로 변환",
                negative = "소라고둥 모드 부정시 {{item_name}}으로 변환"
            },
            en = {
                positive = "Conch mode positive: transforms into {{item_name}}",
                neutral = "Conch mode neutral: transforms into {{item_name}}",
                negative = "Conch mode negative: transforms into {{item_name}}"
            }
        }
        
        if EID then
            -- unify: prepare data and register a single modifier handling both conch-mode and synergies
            local function resolveModLang()
                local normalize = (ConchBlessing and ConchBlessing.Config and ConchBlessing.NormalizeLanguage)
                    or (require("scripts.conch_blessing_config").NormalizeLanguage)
                local cfg = ConchBlessing and ConchBlessing.Config and ConchBlessing.Config.language
                local base = cfg or "Auto"
                if base == "Auto" or base == "auto" then
                    local eidLang = (EID and EID.Config and EID.Config.Language) or (EID and EID.UserConfig and EID.UserConfig.Language)
                    if eidLang and eidLang ~= "auto" then
                        base = eidLang
                    else
                        base = (Options and Options.Language) or "en"
                    end
                end
                return normalize(base)
            end

            ConchBlessing._originItemFlags = originItemFlags
            ConchBlessing._conchModeTemplates = conchModeDescriptions
            ConchBlessing._conchDescCache = ConchBlessing._conchDescCache or {}

            -- Build synergy lookup maps once
            if not ConchBlessing._builtSynergyMaps then
                ConchBlessing._synergyByTarget = {}
                ConchBlessing._synergyByMod = {}
                for key, data in pairs(ConchBlessing.ItemData) do
                    if data and data.synergies and data.id and data.id ~= -1 then
                        for targetId, text in pairs(data.synergies) do
                            ConchBlessing._synergyByTarget[targetId] = ConchBlessing._synergyByTarget[targetId] or {}
                            table.insert(ConchBlessing._synergyByTarget[targetId], { key = key, text = text })
                            ConchBlessing._synergyByMod[data.id] = ConchBlessing._synergyByMod[data.id] or {}
                            table.insert(ConchBlessing._synergyByMod[data.id], { target = targetId, text = text })
                        end
                    end
                end
                ConchBlessing._builtSynergyMaps = true
            end

            local function anyPlayerHasCollectible(id)
                local game = Game()
                local n = game:GetNumPlayers()
                for i = 0, n - 1 do
                    local p = game:GetPlayer(i)
                    if p and p:HasCollectible(id) then return true end
                end
                return false
            end

            if not ConchBlessing._didRegisterUnifiedModifier then
                EID:addDescriptionModifier(
                    "ConchBlessing_Unified",
                    function(descObj)
                        return descObj.ObjType == 5 and descObj.ObjVariant == 100
                    end,
                    function(descObj)
                        local lang = resolveModLang()
                        -- Conch mode (origin) part
                        local itemKeys = (ConchBlessing._originItemFlags or {})[descObj.ObjSubType]
                        local templates = ConchBlessing._conchModeTemplates or {}
                        if itemKeys and templates[lang] then
                            local cacheKey = tostring(descObj.ObjSubType) .. "|" .. lang
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
                                EID:appendToDescription(descObj, cached)
                            end
                        end

                        -- Synergy part
                        local targets = ConchBlessing._synergyByTarget and ConchBlessing._synergyByTarget[descObj.ObjSubType]
                        if targets then
                            for _, entry in ipairs(targets) do
                                local d = ConchBlessing.ItemData[entry.key]
                                if d and d.id and anyPlayerHasCollectible(d.id) then
                                    local text = (type(entry.text) == "table" and (entry.text[lang] or entry.text.en)) or tostring(entry.text)
                                    local iconToken = "{{icon_" .. string.lower(entry.key) .. "}}"
                                    EID:appendToDescription(descObj, "#" .. iconToken .. " " .. text)
                                end
                            end
                        end

                        local asMod = ConchBlessing._synergyByMod and ConchBlessing._synergyByMod[descObj.ObjSubType]
                        if asMod then
                            for _, entry in ipairs(asMod) do
                                if anyPlayerHasCollectible(entry.target) then
                                    local text = (type(entry.text) == "table" and (entry.text[lang] or entry.text.en)) or tostring(entry.text)
                                    local iconToken = "{{Collectible" .. tostring(entry.target) .. "}}"
                                    EID:appendToDescription(descObj, "#" .. iconToken .. " " .. text)
                                end
                            end
                        end

                        return descObj
                    end
                )
                ConchBlessing._didRegisterUnifiedModifier = true
                ConchBlessing.printDebug("Unified EID description modifier registered")
            end
        end

        ConchBlessing._didGenerateConchDescriptions = true
        ConchBlessing.printDebug("Conch mode descriptions generated successfully!")
        
        ConchBlessing:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
            if EID then
                ConchBlessing.printDebug("Adding item icons to EID after game start...")
                
                local ICON_PATHS = {
                    collectibles = "gfx/items/collectibles/",
                    familiars = "gfx/items/familiars/",
                    ui = "gfx/ui/"
                }
                
                local conchIconSprite = Sprite()
                conchIconSprite:Load("gfx/005.350_trinket.anm2")
                conchIconSprite:ReplaceSpritesheet(0, ICON_PATHS.ui .. 'MagicConch.png', true)
                conchIconSprite:GetLayer(0):SetSize(Vector.One * (1/3))
                EID:addIcon("ConchMode", "Idle", 0, 16, 16, 6, 8, conchIconSprite)
                
                for itemKey, itemData in pairs(ConchBlessing.ItemData) do
                    local iconName = "icon_" .. string.lower(itemKey)
                    local iconPath = ""
                    
                    if itemData.type == "active" or itemData.type == "passive" then
                        iconPath = ICON_PATHS.collectibles .. string.lower(itemKey) .. ".png"
                    elseif itemData.type == "familiar" then
                        iconPath = ICON_PATHS.familiars .. string.lower(itemKey) .. ".png"
                    else
                        iconPath = ICON_PATHS.collectibles .. string.lower(itemKey) .. ".png"
                    end
                    
                    local success, itemIconSprite = pcall(function()
                        local sprite = Sprite()
                        sprite:Load("gfx/005.350_trinket.anm2")
                        sprite:ReplaceSpritesheet(0, iconPath, true)
                        sprite:GetLayer(0):SetSize(Vector.One * (1/2))
                        return sprite
                    end)
                    
                    if success and itemIconSprite then
                        ConchBlessing.printDebug("Attempting to add EID icon: " .. iconName .. " with path: " .. iconPath)
                        EID:addIcon(iconName, "Idle", 0, 16, 16, 10, 9, itemIconSprite)
                        ConchBlessing.printDebug("Successfully added EID icon for " .. itemKey .. ": " .. iconName .. " -> " .. iconPath)
                    else
                        ConchBlessing.printDebug("Failed to create sprite for " .. itemKey .. " (path: " .. iconPath .. ")")
                    end
                end
                
                ConchBlessing.printDebug("Item icons added to EID successfully!")
                
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
        end)
    else
        ConchBlessing.printDebug("Conch mode descriptions already generated; skipping.")
    end
    
    ConchBlessing.printDebug("Scripts loaded successfully!")
end

loadAllItems()

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
