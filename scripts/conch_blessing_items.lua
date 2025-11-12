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
--      Example (KR only):
--          specials = { kr = { normal = { "0.006", "60" }, moms_box = { "0.012", "30" }, both = { "0.018", "20" } } }
-- Language scoping:
--   - Top-level specials apply to all languages as default
--   - specials.<lang> (e.g., kr/en) overrides ONLY that language

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
            [{ id = CollectibleType.COLLECTIBLE_ROCK_BOTTOM, type = "collectible" }] = {
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
                "#위 확률은 {{Luck}}운에 따라 (1+0.1×{{Luck}}운) 배수로 증가합니다. (최대 100%)",
                "#지속시간은 {{Damage}}데미지에 따라 증가하며 데미지 10당 5단계로 증가합니다.",
                "#{{BlackHeart}}블랙하트는 드랍되지 않습니다."
            },
            en = {
                "#On hit, has a chance to spawn a void ring at the impact that deals your damage",
                "#Chance is (30 − {{Tears}}Tears)% guaranteed 5%",
                "#chance is increased by (1+0.1×{{Luck}}Luck) (up to 100%)",
                "#Duration increases by 10 frames per 10 {{Damage}}Damage by 5 steps",
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
        origin = { id = CollectibleType.COLLECTIBLE_ATHAME, type = "collectible" },
        flag = "neutral",
        script = "scripts/items/collectibles/void_dagger",
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
        origin = { id = CollectibleType.COLLECTIBLE_EXPERIMENTAL_TREATMENT, type = "collectible" },
        flag = "positive",
        script = "scripts/items/collectibles/power_training",
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
            RoomType.ROOM_BLACK_MARKET
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
        origin = { id = CollectibleType.COLLECTIBLE_EXPERIMENTAL_TREATMENT, type = "collectible" },
        flag = "negative",
        script = "scripts/items/collectibles/injectable_steroids",
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
                  "#낙뢰는 데미지의 5%만큼 줍니다.",
                  "#중첩해서 획득시 낙뢰가 용오름으로 변하고 획득할때마다 데미지가 5%씩 증가합니다."
                },
            en = {"Gain flight and Spectral tears.",
                  "#After entering a room for 5 seconds, can shoot up to 5 lightning bolts to up to 5 enemies within 5 blocks for 5 seconds.",
                  "#This process repeats 5 times per room as a cycle.",
                  "#Lightning bolts deal 5% of the player's damage.",
                  "#When stacked, lightning bolts become spout and increase by 5% each time they are obtained."
                }
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
        origin = { id = CollectibleType.COLLECTIBLE_TAURUS, type = "collectible" },
        flag = "positive",
        script = "scripts/items/collectibles/dragon",
        callbacks = {
            evaluateCache = "dragon.onEvaluateCache",
            update = "dragon.onUpdate",
            postNewRoom = "dragon.onNewRoom",
            postRoomEnter = "dragon.onRoomEnter",
            postRoomClear = "dragon.onRoomClear",
            postLaserUpdate = "dragon.onLaserUpdate",
            postBrimstoneUpdate = "dragon.onBrimstoneUpdate",
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
    CHRONUS = {
		type = "passive",
		id = Isaac.GetItemIdByName("Chronus"),
		name = {
			kr = "크로노스",
			en = "Chronus"
		},
		description = {
			kr = "자식을 삼키다",
			en = "Devours its offspring"
		},
		eid = {
			kr = {
				"패밀리어 아이템을 흡수하여 제거합니다.",
				"#흡수한 패밀리어마다 {{Damage}}데미지가 2.0 증가하고, 지정된 패밀리어는 고유한 효과를 부여합니다.",
                "#아이템이 사라질때까지 지속됩니다. (사라지면 패밀리어가 돌아옵니다.)",
				"#일부 패밀리어는 제외 목록에 따라 흡수되지 않습니다."
			},
			en = {
				"Absorbs and removes familiar-type collectibles.",
				"#Each absorbed familiar increases {{Damage}}Damage by 2.0 and may grant a custom effect.",
				"#Some familiars are excluded by a blacklist."
			}
		},
		gfx = "chronus.png",
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
		script = "scripts/items/collectibles/chronus",
		callbacks = {
			pickup = "chronus.onPickup",
			postPlayerUpdate = "chronus.onPlayerUpdate",
            update = "chronus.onPostUpdate",
			evaluateCache = "chronus.onEvaluateCache",
			gameStarted = "chronus.onGameStarted",
            familiarUpdate = "chronus.onFamiliarUpdate",
            fireTear = "chronus.onFireTear",
            entityTakeDmg = "chronus.onEntityTakeDamage"
		},
		synergies = {
            [{ id = CollectibleType.COLLECTIBLE_TWISTED_PAIR, type = "collectible" }] = {
                kr = "75% 데미지의 공격을 2개 추가합니다.",
                en = "Adds 2 additional 75% damage attacks."
            },
            [{ id = CollectibleType.COLLECTIBLE_SUCCUBUS, type = "collectible" }] = {
                kr = "내 주변으로 오라가 고정됩니다.",
                en = "Attracts an aura around the player."
            },
            [{ id = CollectibleType.COLLECTIBLE_INCUBUS, type = "collectible" }] = {
                kr = "75% 데미지의 공격을 1개 추가합니다..",
                en = "Adds 1 additional 75% damage attack."
            },
            [{ id = CollectibleType.COLLECTIBLE_SERAPHIM, type = "collectible" }] = {
                kr = {
                    "공중, 지형관통 효과를 얻습니다.",
                    "신성한 심장을 획득합니다. (최초 1회)"
                },
                en = {
                    "Gains flight, and spectral tear effects.",
                    "Gains a Sacred Heart (first time only)."
                }
            },
            [{ id = CollectibleType.COLLECTIBLE_ROBO_BABY, type = "collectible" }] = {
                kr = "테크를 얻습니다.",
                en = "Gains Technology."
            },
            [{ id = CollectibleType.COLLECTIBLE_BLUE_BABYS_ONLY_FRIEND, type = "collectible" }] = {
                kr = "루도비코를 얻습니다. (최초 1회)",
                en = "Gains Ludovico Technique (first time only)."
            },
            [{ id = CollectibleType.COLLECTIBLE_LIL_BRIMSTONE, type = "collectible" }] = {
                kr = "혈사를 얻습니다.",
                en = "Gains Brimstone."
            },
            [{ id = CollectibleType.COLLECTIBLE_BOBS_BRAIN, type = "collectible" }] = {
                kr = "구토제를 얻습니다. (최초 1회)",
                en = "Gains Ipecac (first time only)."
            },
            [{ id = CollectibleType.COLLECTIBLE_LIL_MONSTRO, type = "collectible" }] = {
                kr = "몬스트로의 폐를 얻습니다. (최초 1회)",
                en = "Gains Monstro's Lung (first time only)."
            },
            [{ id = CollectibleType.COLLECTIBLE_LIL_HAUNT, type = "collectible" }] = {
                kr = "모든 공격에 공포 효과를 부여합니다.",
                en = "Grants fear effect to all attacks."
            },
            [{ id = CollectibleType.COLLECTIBLE_BLOOD_PUPPY, type = "collectible" }] = {
                kr = "김피를 얻습니다. (최초 1회)",
                en = "Gains Gimpy (first time only)."
            },
            [{ id = CollectibleType.COLLECTIBLE_ANGELIC_PRISM, type = "collectible" }] = {
                kr = "공격이 4갈래로 갈라져 나갑니다.",
                en = "Attacks split into 4 beams."
            },
            [{ id = CollectibleType.COLLECTIBLE_BOT_FLY, type = "collectible" }] = {
                kr = "잃어버린 렌즈를 얻습니다. (최초 1회)",
                en = "Gains Lost Contact(first time only)."
            },
            [{ id = CollectibleType.COLLECTIBLE_FREEZER_BABY, type = "collectible" }] = {
                kr = "천왕성을 얻습니다. (최초 1회)",
                en = "Gains Uranus (first time only)."
            },
            [{ id = CollectibleType.COLLECTIBLE_LIL_ABADDON, type = "collectible" }] = {
                kr = "공허의 구렁텅이를 얻습니다. (최초 1회)",
                en = "Gains Maw of the Void (first time only)."
            },
            [{ id = CollectibleType.COLLECTIBLE_MULTIDIMENSIONAL_BABY, type = "collectible" }] = {
                kr = "20/20을 얻습니다.",
                en = "Gains 20/20."
            },
            [{ id = CollectibleType.COLLECTIBLE_HARLEQUIN_BABY, type = "collectible" }] = {
                kr = "법사를 얻습니다.",
                en = "Gains The Wiz."
            },
            [{ id = CollectibleType.COLLECTIBLE_BROTHER_BOBBY, type = "collectible" }] = {
                kr = "{{Tears}} 고정연사 +2를 얻습니다.",
                en = "Gains +2 {{Tears}} fire rate."
            },
            [{ id = CollectibleType.COLLECTIBLE_DEMON_BABY, type = "collectible" }] = {
                kr = "표식을 얻습니다. (최초 1회)",
                en = "Gains Marked (first time only)."
            },
            [{ id = CollectibleType.COLLECTIBLE_LITTLE_GISH, type = "collectible" }] = {
                kr = "모든 공격에 느림 효과를 부여합니다.",
                en = "Grants slowing effect to all attacks."
            },
            [{ id = CollectibleType.COLLECTIBLE_LIL_LOKI, type = "collectible" }] = {
                kr = "로키의 뿔을 얻습니다.",
                en = "Gains Loki's Horns."
            },
            [{ id = CollectibleType.COLLECTIBLE_GHOST_BABY, type = "collectible" }] = {
                kr = "연속체를 얻습니다.",
                en = "Gains Continuum."
            },
            [{ id = CollectibleType.COLLECTIBLE_ROTTEN_BABY, type = "collectible" }] = {
                kr = "적에게 데미지를 줄 때마다 아군 파리를 소환합니다.",
                en = "Spawns friendly flies when dealing damage to enemies."
            },
            [{ id = CollectibleType.COLLECTIBLE_LITTLE_STEVEN, type = "collectible" }] = {
                kr = "유도 효과를 얻습니다.",
                en = "Gains homing effect."
            },
            [{ id = CollectibleType.COLLECTIBLE_RAINBOW_BABY, type = "collectible" }] = {
                kr = "과일 케이크를 얻습니다. (최초 1회)",
                en = "Gains Fruit Cake (first time only)."
            },
            [{ id = CollectibleType.COLLECTIBLE_GUARDIAN_ANGEL, type = "collectible" }] = {
                kr = "이동 속도{{Speed}} +0.3을 얻습니다.",
                en = "Gains +0.3 {{Speed}} speed."
            },
            [{ id = CollectibleType.COLLECTIBLE_CENSER, type = "collectible" }] = {
                kr = "향로의 오라 효과가 플레이어 위치에 고정됩니다.",
                en = "Censer's smoke effect is fixed to player position."
            },
            [{ id = CollectibleType.COLLECTIBLE_LEECH, type = "collectible" }] = {
                kr = "흡혈귀의 부적을 얻습니다. (최초 1회)",
                en = "Gains Charm of the Vampire (first time only)."
            },
            [{ id = CollectibleType.COLLECTIBLE_BOMB_BAG, type = "collectible" }] = {
                kr = "파이로를 얻습니다. (최초 1회)",
                en = "Gains Pyro (first time only)."
            },
            [{ id = CollectibleType.COLLECTIBLE_DARK_BUM, type = "collectible" }] = {
                kr = "주교관을 얻습니다. (최초 1회)",
                en = "Gains Mitre (first time only)."
            },
            [{ id = CollectibleType.COLLECTIBLE_KEY_BUM, type = "collectible" }] = {
                kr = "해골 열쇠를 얻습니다. (최초 1회)",
                en = "Gains Skeleton Key (first time only)."
            },
            [{ id = CollectibleType.COLLECTIBLE_ABEL, type = "collectible" }] = {
                kr = "거울을 얻습니다. (최초 1회)",
                en = "Gains My Reflection (first time only)."
            },
            [{ id = CollectibleType.COLLECTIBLE_STAR_OF_BETHLEHEM, type = "collectible" }] = {
                kr = {
                    "베들레헴의 별 오라가 플레이어 위치에 고정됩니다.",
                    "나침반을 얻습니다. (최초 1회)"
                },
                en = {
                    "Star of Bethlehem's aura is fixed to player position.",
                    "Gains Compass (first time only)."
                }
            },
            [{ id = CollectibleType.COLLECTIBLE_FARTING_BABY, type = "collectible" }] = {
                kr = "젤리 배를 얻습니다. (최초 1회)",
                en = "Gains Jelly Belly (first time only)."
            },
            [{ id = CollectibleType.COLLECTIBLE_SAMSONS_CHAINS, type = "collectible" }] = {
                kr = "천둥 허벅지를 얻습니다. (최초 1회)",
                en = "Gains Thunder Thighs (first time only)."
            },
            [{ id = CollectibleType.COLLECTIBLE_FINGER, type = "collectible" }] = {
                kr = "트랙터 빔을 얻습니다. (최초 1회)",
                en = "Gains Tractor Beam (first time only)."
            },
            [{ id = CollectibleType.COLLECTIBLE_IMMACULATE_CONCEPTION, type = "collectible" }] = {
                kr = "사탕 하트를 얻습니다. (최초 1회)",
                en = "Gains Candy Heart (first time only)."
            },
            [{ id = CollectibleType.COLLECTIBLE_SACK_OF_PENNIES, type = "collectible" }] = {
                kr = "달러를 얻습니다. (최초 1회)",
                en = "Gains Dollar (first time only)."
            },
            [{ id = CollectibleType.COLLECTIBLE_SACK_OF_SACKS, type = "collectible" }] = {
                kr = "자루 머리를 얻습니다. (최초 1회)",
                en = "Gains Sack Head (first time only)."
            },
            [{ id = CollectibleType.COLLECTIBLE_CHARGED_BABY, type = "collectible" }] = {
                kr = "9볼트를 얻습니다. (최초 1회)",
                en = "Gains 9 Volt (first time only)."
            },
            [{ id = CollectibleType.COLLECTIBLE_YO_LISTEN, type = "collectible" }] = {
                kr = "엑스레이 투시를 얻습니다. (최초 1회)",
                en = "Gains X-Ray Vision (first time only)."
            },
            [{ id = CollectibleType.COLLECTIBLE_DADDY_LONGLEGS, type = "collectible" }] = {
                kr = "신성한 빛을 얻습니다. (최초 1회)",
                en = "Gains Holy Light (first time only)."
            },
            -- Blacklisted items
            [{ id = CollectibleType.COLLECTIBLE_ONE_UP, type = "collectible" }] = {
                kr = "크로노스에 흡수되지 않습니다.",
                en = "Cannot be absorbed by Chronus."
            },
            [{ id = CollectibleType.COLLECTIBLE_ISAACS_HEART, type = "collectible" }] = {
                kr = "크로노스에 흡수되지 않습니다.",
                en = "Cannot be absorbed by Chronus."
            },
            [{ id = CollectibleType.COLLECTIBLE_DEAD_CAT, type = "collectible" }] = {
                kr = "크로노스에 흡수되지 않습니다.",
                en = "Cannot be absorbed by Chronus."
            },
            [{ id = CollectibleType.COLLECTIBLE_KEY_PIECE_1, type = "collectible" }] = {
                kr = "크로노스에 흡수되지 않습니다.",
                en = "Cannot be absorbed by Chronus."
            },
            [{ id = CollectibleType.COLLECTIBLE_KEY_PIECE_2, type = "collectible" }] = {
                kr = "크로노스에 흡수되지 않습니다.",
                en = "Cannot be absorbed by Chronus."
            },
            [{ id = CollectibleType.COLLECTIBLE_KNIFE_PIECE_1, type = "collectible" }] = {
                kr = "크로노스에 흡수되지 않습니다.",
                en = "Cannot be absorbed by Chronus."
            },
            [{ id = CollectibleType.COLLECTIBLE_KNIFE_PIECE_2, type = "collectible" }] = {
                kr = "크로노스에 흡수되지 않습니다.",
                en = "Cannot be absorbed by Chronus."
            },
        }
	},
    APPRAISAL_CERTIFICATE = {
        type = "active",
        id = Isaac.GetItemIdByName("Appraisal Certificate"),
        name = {
            kr = "감정 평가서",
            en = "Appraisal Certificate",
        },
        description = {
            kr = "이거 장물 아니죠?",
            en = "Is this a loot?",
        },
        eid = {
            kr = {
                "{{Coin}} 30원을 소비하여 현재 장신구를 흡수하고 모든 장신구 방(사망증서 공간)으로 이동합니다.",
                "#하나를 선택하면 즉시 흡수하고 원래 방으로 돌아옵니다.",
                "#{{Warning}} 사망 증명서 공간을 공유합니다.",
            },
            en = {
                "Consumes {{Coin}} 30 to absorb the current trinket and move to all trinket rooms (Death Certificate space).",
                "#When one is selected, it is immediately absorbed and returns to the original room.",
                "#{{Warning}} Shares Death Certificate space.",
            },
        },
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
        chargetype = "normal",
        gfx = "appraisal_certificate.png",
        initcharge = 0,
        origin = { id = CollectibleType.COLLECTIBLE_DEATH_CERTIFICATE, type = "collectible" },
        flag = "neutral",
        script = "scripts/items/collectibles/appraisal_certificate",
        callbacks = {
            use = "appraisal.onUseItem",
            postPickupInit = "appraisal.onPostPickupInit",
            prePickupCollision = "appraisal.onPrePickupCollision",
            postNewRoom = "appraisal.onPostNewRoom",
            update = "appraisal.onUpdate",
        },
        onBeforeChange = "appraisal.onBeforeChange",
        onAfterChange = "appraisal.onAfterChange",
        synergies = {
            [{ type = "trinket", name = "Atropos" }] = {
                kr = {"감정서 시작 방에서 바보 카드를 드랍합니다.",
                        "장신구를 흡수하지 않습니다."},
                en = {"Drops a Fool card in the AC start room.",
                        "#Trinkets are not smelted."}
            }
        },
    },
    MONEY_TEAR = {
        type = "passive",
        id = Isaac.GetItemIdByName("Money = Tear"),
        name = {
            kr = "돈 = 연사",
            en = "Money = Tear"
        },
        description = {
            kr = "돈은 연사다",
            en = "Money is tears"
        },
        eid = {
            kr = {
                "소지하고 있는 동전당 고정연사가 0.066 증가합니다."
            },
            en = {
                "While held, gains +0.066 {{Tears}}SPS per coin."
            }
        },
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

    -- Trinkets
    TIME_POWER = {
        type = "trinket",
        id = Isaac.GetTrinketIdByName("Time = Power"),
        name = {
            kr = "시간 = 힘",
            en = "Time = Power"
        },
        description = {
            kr = "시간은 힘이다",
            en = "Time is power"
        },
        eid = {
            kr = {
                "소지 중 초당 {{Damage}}공격력이 0.006 증가합니다.",
                "#적에게 피격 시 60초 동안 증가가 중지됩니다."
            },
            en = {
                "While held, gains +0.006 {{Damage}}Damage per second.",
                "#On taking damage, gain is paused for 60 seconds."
            }
        },
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
            entityTakeDmg = "timepowertrinket.onEntityTakeDamage",
            onBeforeChange = "timepowertrinket.onBeforeChange",
            onAfterChange = "timepowertrinket.onAfterChange"
        },
        synergies = {}
    },
    TIME_TEAR = {
        type = "trinket",
        id = Isaac.GetTrinketIdByName("Time = Tear"),
        name = {
            kr = "시간 = 연사",
            en = "Time = Tear"
        },
        description = {
            kr = "시간은 연사다",
            en = "Time is tears"
        },
        eid = {
            kr = {
                "소지 중 초당 {{Tears}}고정연사가 0.0066 증가합니다.",
                "#적에게 피격 시 60초 동안 증가가 중지됩니다."
            },
            en = {
                "While held, gains +0.0066 {{Tears}}SPS per second.",
                "#On taking damage, gain is paused for 60 seconds."
            }
        },
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
            entityTakeDmg = "timeteartrinket.onEntityTakeDamage",
            onBeforeChange = "timeteartrinket.onBeforeChange",
            onAfterChange = "timeteartrinket.onAfterChange"
        },
        synergies = {}
    },
    TIME_LUCK = {
        type = "trinket",
        id = Isaac.GetTrinketIdByName("Time = Luck"),
        name = {
            kr = "시간 = 행운",
            en = "Time = Luck"
        },
        description = {
            kr = "시간은 행운이다",
            en = "Time is luck"
        },
        eid = {
            kr = {
                "소지 중 초당 {{Luck}}운이 0.01 증가합니다.",
                "#적에게 피격 시 60초 동안 증가가 중지됩니다."
            },
            en = {
                "While held, gains +0.01 {{Luck}}Luck per second.",
                "#On taking damage, gain is paused for 60 seconds."
            }
        },
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
            entityTakeDmg = "timelucktrinket.onEntityTakeDamage",
            onBeforeChange = "timelucktrinket.onBeforeChange",
            onAfterChange = "timelucktrinket.onAfterChange"
        },
        synergies = {}
    },
    F_MINUS = {
        WorkingNow=false,
        type = "trinket",
        id = Isaac.GetTrinketIdByName("F -"),
        name = {
            kr = "F -",
            en = "F -"
        },
        description = {
            kr = "정답만 피하는 것도 행운이야",
            en = "Just avoiding the right answer is luck too."
        },
        eid = {
            kr = {
                "행운이 5 증가합니다.",
                "#피격 당하지 않은 채로 다음 층으로 이동 시, C -로 진화합니다."
            },
            en = {
                "Luck increases by 5.",
                "#When moving to the next floor without taking damage, evolves into C -."
            }
        },
        gfx = "f_minus.png",
        tags = "offensive",
        cache = "luck",
        hidden = false,
        origin = { id = TrinketType.TRINKET_PERFECTION, type = "trinket" },
        flag = "negative",
        shopprice=15,
        script = "scripts/items/trinkets/f_minus",
        specials = { normal = 5 },
        callbacks = {
        },
        synergies = {}
    },
    C_MINUS = {
        WorkingNow=false,
        type = "trinket",
        id = Isaac.GetTrinketIdByName("C -"),
        name = {
            kr = "C -",
            en = "C -"
        },
        description = {
            kr = "그럴 수 있어. 이런 날도 있는 거지 뭐.",
            en = "BETTER LUCK NEXT TIME!"
        },
        eid = {
            kr = {
                "행운이 4 증가합니다.",
                "#{{Tears}} 고정연사가 2.0 증가합니다.",
                "#피격 당하지 않은 채로 다음 층으로 이동 시, B -로 진화합니다."
            },
            en = {
                "Luck increases by 4.",
                "#{{Tears}} Fixed SPS increases by 2.0.",
                "#When moving to the next floor without taking damage, evolves into B -."
            }
        },
        gfx = "c_minus.png",
        tags = "offensive",
        cache = "tears",
        origin = { type = "trinket", name = "F -" },
        flag = "positive",
        hidden = true,
        shopprice=15,
        script = "scripts/items/trinkets/c_minus",
        specials = { normal = {4, 2.0} },
        callbacks = {
        },
        synergies = {}
    },
    B_MINUS = {
        WorkingNow=false,
        type = "trinket",
        id = Isaac.GetTrinketIdByName("B -"),
        name = {
            kr = "B -",
            en = "B -"
        },
        description = {
            kr = "시작이 반이다",
            en = "Well begun is half done."
        },
        eid = {
            kr = {
                "행운이 3 증가합니다.",
                "#{{Tears}} 고정 연사가 3.0 증가합니다.",
                "#{{Damage}} 공격력이 3.0 증가합니다.",
                "#피격 당하지 않은 채로 다음 층으로 이동 시, A -로 진화합니다."
            },
            en = {
                "Luck increases by 3.",
                "#{{Tears}}Fixed SPS increases by 3.0.",
                "#{{Damage}}Damage increases by 3.0.",
                "#When moving to the next floor without taking damage, evolves into A -."
            }
        },
        gfx = "b_minus.png",
        tags = "offensive",
        cache = "luck damage",
        origin = { type = "trinket", name = "C -" },
        flag = "positive",
        hidden = true,
        shopprice=15,
        script = "scripts/items/trinkets/b_minus",
        specials = { normal = {3, 3.0} },
        callbacks = {
        },
        synergies = {}
    },
    A_MINUS = {
        WorkingNow=false,
        type = "trinket",
        id = Isaac.GetTrinketIdByName("A -"),
        name = {
            kr = "A -",
            en = "A -"
        },
        description = {
            kr = "좋은 시도였어. 아이작",
            en = "Nice try, did he?"
        },
        eid = {
            kr = {
                "행운이 2 증가합니다.",
                "#{{Tears}} 고정연사가 4.0 증가합니다.",
                "#{{Damage}} 공격력이 4.0 증가합니다.",
                "#4배수가 공격력, 행운, 연사에 나눠서 적용됩니다. (중첩X)",
                "#0.8배이상으로 나눠서 적용됩니다.",
            },
            en = {
                "Luck increases by 2.",
                "#{{Tears}} Fixed SPS increases by 4.0.",
                "#{{Damage}} Damage increases by 4.0.",
                "#4x multipliers are distributed to Damage, Luck, and SPS. (No stacking)",
                "#Multipliers are at least 0.8x.",
            }
        },
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
        name = {
            kr = "아트로포스",
            en = "Atropos"
        },
        description = {
            kr = "끊어진 운명",
            en = "Broken Destiny"
        },
        eid = {
            kr = {
                "모든 선택지 아이템을 획득할 수 있게 합니다.",
            },
            en = {
                "Allows picking all optioned items"
            }
        },
        gfx = "atropos.png",
        tags = "utility",
        hidden = false,
        flag = "positive",
        origin = { id = TrinketType.TRINKET_SAFETY_SCISSORS, type = "trinket" },
        shopprice = 15,
        script = "scripts/items/trinkets/atropos",
        callbacks = {
            postUpdate = "atropos.onPostUpdate",
            postNewRoom = "atropos.onPostNewRoom"
        },
        synergies = {
            [{ id = CollectibleType.COLLECTIBLE_DEATH_CERTIFICATE, type = "collectible" }] = {
                kr = "사망 증명서 방에서 바보 카드를 드랍합니다.",
                en = "Drops a Fool card in Death Certificate rooms."
            }
        }
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
        name = {
            kr = "시간 = 돈",
            en = "Time = Money"
        },
        description = {
            kr = "시간은 돈이다",
            en = "Time is money"
        },
        eid = {
            kr = {
                "동전 5개를 드랍합니다.",
                "#60초마다 현재 소지중인 동전의 5% 개수만큼 동전을 드랍합니다. (최소 1개)",
                "#이 패밀리어가 드랍하는 동전은 5% 확률로 5원, 2% 확률로 황금 동전, 2% 확률로 행운 동전, 1% 확률로 10원으로 대체됩니다.",
                "#행운에 따라 위 확률이 (1+0.1×운{{Luck}})배로 4배까지 증가합니다.",
                "#피격시 드랍되는 동전의 갯수가 1개 감소합니다."
            },
            en = {
                "Drops 5 coins on pickup.",
                "#Every 60 seconds, drops coins equal to 5% of current money (minimum 1).",
                "#Coins dropped by this familiar are replaced with nickel 5% of the time, golden coin 2% of the time, lucky coin 2% of the time, and dime 1% of the time.",
                "#The probability of the above is increased by (1+0.1×Luck{{Luck}}) times up to 4 times.",
                "#When taking damage, the number of coins dropped is reduced by 1."
            }
        },
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
            [{ id = CollectibleType.COLLECTIBLE_BFFS, type = "collectible" }] = {
                kr = "동전 드랍 비율이 10%로 증가합니다.",
                en = "Drop rate increases to 10%."
            }
        },
        callbacks = {
            familiarInit = "timemoney.onFamiliarInit",
            familiarUpdate = "timemoney.onFamiliarUpdate",
            postFamiliarRender = "timemoney.onFamiliarRender",
            evaluateCache = "timemoney.onEvaluateCache",
            gameStarted = "timemoney.onGameStarted",
            postGetCollectible = "timemoney.onPostGetCollectible",
            postPlayerUpdate = "timemoney.onPlayerUpdate",
            entityTakeDmg = "timemoney.onEntityTakeDamage"
        }
    }
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
							table.insert(ConchBlessing._synergyByTarget[targetId], { key = key, text = text })
								ConchBlessing._synergyByMod[data.id] = ConchBlessing._synergyByMod[data.id] or {}
							table.insert(ConchBlessing._synergyByMod[data.id], { target = targetId, targetIsTrinket = targetIsTrinket, text = text })
							end
                        end
                    end
                end
                ConchBlessing._builtSynergyMaps = true
            end

            -- Helper: check if any player has a collectible or trinket with given ID
			local function anyPlayerHas(id)
				if type(id) ~= "number" then return false end
                local game = Game()
                local n = game:GetNumPlayers()
                for i = 0, n - 1 do
                    local p = game:GetPlayer(i)
                    if p then
                        if p:HasCollectible(id) then return true end
                        if p:HasTrinket(id) then return true end
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

            if not ConchBlessing._didRegisterUnifiedModifier then
                EID:addDescriptionModifier(
                    "ConchBlessing_ByOriginType",
                    function(descObj)
                        -- Support both Collectibles (100) and Trinkets (350)
                        return descObj.ObjType == 5 and (descObj.ObjVariant == 100 or descObj.ObjVariant == 350)
                    end,
                    function(descObj)
                        local lang = resolveModLang()
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
						
						ConchBlessing.printDebug("[EID] Checking pickup: ObjType=" .. tostring(descObj.ObjType) .. ", Variant=" .. tostring(descObj.ObjVariant) .. ", SubType=" .. tostring(subId) .. ", category=" .. tostring(originCategory))
						
						if not originCategory then
							ConchBlessing.printDebug("[EID] Skipping: not a collectible or trinket pickup")
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
								ConchBlessing.printDebug("[EID] Conch attach OK: " .. pickupTypeName .. " id=" .. tostring(subId) .. ", keys=" .. tostring(table.concat(itemKeys, ",")))
                                EID:appendToDescription(descObj, cached)
                            end
						else
							ConchBlessing.printDebug("[EID] Conch attach SKIP: no " .. pickupTypeName .. " mapping for id=" .. tostring(subId))
						end

                        -- Synergy part
                        local targets = ConchBlessing._synergyByTarget and ConchBlessing._synergyByTarget[subId]
                        if targets then
						for _, entry in ipairs(targets) do
							local d = ConchBlessing.ItemData[entry.key]
							if d and d.id and anyPlayerHas(d.id) then
								local t = (type(entry.text) == "table" and (entry.text[lang] or entry.text.en)) or entry.text
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
                                if anyPlayerHas(entry.target) then
                                    local t = (type(entry.text) == "table" and (entry.text[lang] or entry.text.en)) or entry.text
                                    local iconToken
                                    -- Use the explicitly stored targetIsTrinket flag from synergy definition
                                    ConchBlessing.printDebug("[EID Synergy] Processing target ID: " .. tostring(entry.target) .. ", targetIsTrinket flag: " .. tostring(entry.targetIsTrinket))
                                    if entry.targetIsTrinket == true then
                                        iconToken = "{{Trinket" .. tostring(entry.target) .. "}}"
                                        ConchBlessing.printDebug("[EID Synergy] Using Trinket icon for ID: " .. tostring(entry.target))
                                    elseif entry.targetIsTrinket == false then
                                        iconToken = "{{Collectible" .. tostring(entry.target) .. "}}"
                                        ConchBlessing.printDebug("[EID Synergy] Using Collectible icon for ID: " .. tostring(entry.target))
                                    else
                                        -- Fallback: auto-detect if type was not explicitly specified
                                        local isTrinket = isTrinketId(entry.target)
                                        ConchBlessing.printDebug("[EID Synergy] Auto-detecting type for ID: " .. tostring(entry.target) .. ", isTrinket: " .. tostring(isTrinket))
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
