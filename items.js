// Conch's Blessing Items Data
// Auto-generated from conch_blessing_items.lua

const items = {
    LIVE_EYE: {
        type: "passive",
        gfx: "resources/gfx/items/collectibles/live_eye.png",
        quality: 4,
        tags: "offensive",
        cache: "damage",
        hidden: false,
        shopprice: 20,
        devilprice: 2,
        maxcharges: 0,
        chargetype: "normal",
        initcharge: 0,
        hearts: 0,
        maxhearts: 0,
        blackhearts: 0,
        soulhearts: 0,
        origin: "DEAD_EYE",
        flag: "positive",
        pools: ["ROOM_ANGEL", "ROOM_ULTRASECRET"],
        names: {"kr": "살아있는 눈", "en": "Live Eye"},
        descriptions: {"kr": "놓쳐도 괜찮아", "en": "Misses happen"},
        eids: {"kr": ["몬스터를 적중시킬때 마다 데미지 배수가 0.1씩 증가합니다.", "몬스터에 맞지 않으면 데미지 배수가 0.15씩 감소합니다.", "최대/최소 데미지 배수 (x3.0/x0.75)"], "en": ["Damage multiplier increases by 0.1 as you hit enemies.", "Damage multiplier decreases by 0.15 as you miss enemies.", "Damage multiplier is capped at 3.0 and cannot go below 0.75."]},
        synergies: {"ROCK_BOTTOM": {"kr": "획득하는 즉시 데미지 배수가 최대치가 됩니다", "en": "When obtained, damage multiplier is set to the maximum value"}}
    },
    VOID_DAGGER: {
        type: "passive",
        gfx: "resources/gfx/items/collectibles/void_dagger.png",
        quality: 4,
        tags: "offensive devil",
        cache: "damage firedelay",
        hidden: false,
        shopprice: 20,
        devilprice: 2,
        maxcharges: 0,
        chargetype: "normal",
        initcharge: 0,
        hearts: 0,
        maxhearts: 0,
        blackhearts: 0,
        soulhearts: 0,
        origin: "ATHAME",
        flag: "neutral",
        pools: ["ROOM_DEVIL", "ROOM_TREASURE"],
        names: {"kr": "공허의 단검", "en": "Void Dagger"},
        descriptions: {"kr": "공허가 열린다", "en": "The void opens"},
        eids: {"kr": ["눈물이 적에게 명중 시 확률로 그 위치에 내 데미지의 보이드 링을 소환합니다.", "확률은 (30 - 연사)%로 5%보다 작아지지 않습니다", "위 확률은 운에 따라 (1+0.1×운) 배수로 증가합니다. (최대 2배)", "지속시간은 데미지에 따라 증가하며 데미지 10당 6단계로 증가합니다.", "블랙하트는 드랍되지 않습니다."], "en": ["On hit, has a chance to spawn a void ring at the impact that deals your damage", "Chance is (30 − Tears)% guaranteed 5%", "chance is increased by (1+0.1×Luck) (up to 2x)", "Duration increases by 10 frames per 10 Damage by 6 steps", "No black heart drops"]}
    },
    ETERNAL_FLAME: {
        type: "passive",
        gfx: "resources/gfx/items/collectibles/eternal_flame.png",
        quality: 4,
        tags: "offensive angel",
        cache: "damage firedelay",
        hidden: false,
        shopprice: 20,
        devilprice: 2,
        maxcharges: 0,
        chargetype: "normal",
        initcharge: 0,
        hearts: 0,
        maxhearts: 0,
        blackhearts: 0,
        soulhearts: 0,
        origin: "BLACK_CANDLE",
        flag: "positive",
        pools: ["ROOM_ANGEL", "ROOM_ULTRASECRET"],
        names: {"kr": "영원한 불꽃", "en": "Eternal Flame"},
        descriptions: {"kr": "정화의 불길", "en": "Baptize with fire"},
        eids: {"kr": ["저주가 걸릴 때마다 저주를 제거합니다.", "저주 제거 시 고정 데미지 +3.0, 연사 +1.0을 영구적으로 부여합니다.", "저주가 걸릴 확률이 증가합니다."], "en": ["Removes curses when they are applied.", "Grants fixed damage +3.0 and fixed fire rate +1.0 permanently when removing curses.", "Increases curse chance."]}
    },
    POWER_TRAINING: {
        type: "active",
        gfx: "resources/gfx/items/collectibles/power_training.png",
        quality: 4,
        tags: "offensive",
        cache: "damage firedelay range luck",
        hidden: false,
        shopprice: 20,
        devilprice: 2,
        maxcharges: 8,
        chargetype: "normal",
        initcharge: 8,
        hearts: 0,
        maxhearts: 0,
        blackhearts: 0,
        soulhearts: 0,
        origin: "EXPERIMENTAL_TREATMENT",
        flag: "positive",
        pools: ["ROOM_TREASURE", "ROOM_SHOP", "ROOM_ANGEL"],
        names: {"kr": "파워 트레이닝", "en": "Power Training"},
        descriptions: {"kr": "라잇웨잇 베이비!", "en": "Lightweight Baby!"},
        eids: {"kr": ["사용시 데미지, 연사(딜레이 나누기), 사거리, 행운이 1.0~1.3배가 됩니다."], "en": ["Damage, fire rate (delay division), range, and luck are changed to 1.0~1.3x when used"]}
    },
    ORAL_STEROIDS: {
        type: "passive",
        gfx: "resources/gfx/items/collectibles/oral_steroids.png",
        quality: 2,
        tags: "offensive",
        cache: "damage firedelay range luck",
        hidden: false,
        shopprice: 15,
        devilprice: 1,
        maxcharges: 0,
        chargetype: "normal",
        initcharge: 0,
        hearts: 0,
        maxhearts: 0,
        blackhearts: 0,
        soulhearts: 0,
        origin: "EXPERIMENTAL_TREATMENT",
        flag: "neutral",
        pools: ["ROOM_DEVIL", "ROOM_CURSE", "ROOM_BLACK_MARKET", "ROOM_SECRET"],
        names: {"kr": "경구형 스테로이드", "en": "Oral Steroids"},
        descriptions: {"kr": "주사는 무서워", "en": "Shots are scary"},
        eids: {"kr": ["획득시 데미지, 연사, 사거리, 행운이 0.8 ~ 1.5배가 됩니다."], "en": ["Damage, fire rate, range, and luck are changed to 0.8 ~ 1.5x when obtained"]}
    },
    INJECTABLE_STEROIDS: {
        type: "active",
        gfx: "resources/gfx/items/collectibles/injectable_steroids.png",
        quality: 3,
        tags: "offensive",
        cache: "damage firedelay range luck",
        hidden: false,
        shopprice: 15,
        devilprice: 2,
        maxcharges: 1,
        chargetype: "special",
        initcharge: 1,
        hearts: 0,
        maxhearts: 0,
        blackhearts: 0,
        soulhearts: 0,
        origin: "EXPERIMENTAL_TREATMENT",
        flag: "negative",
        pools: ["ROOM_DEVIL", "ROOM_CURSE", "ROOM_BLACK_MARKET", "ROOM_ULTRASECRET"],
        names: {"kr": "주사 스테로이드", "en": "Injectable Steroids"},
        descriptions: {"kr": "힘을 원해...", "en": "I need more power..."},
        eids: {"kr": ["사용시 데미지, 연사, 사거리, 행운이 0.5~2.0배가 됩니다.", "스테이지마다 한번 사용할수 있으며 배터리나 방 클리어로 충전되지 않습니다.", "몸이 점점 노래집니다..."], "en": ["Damage, fire rate, range, and luck are changed to 0.5~2.0x when used", "Can be used once per stage, and is not charged by batteries or clearing rooms", "Your body is gradually turning yellow..."]}
    },
    RAT: {
        gfx: "resources/gfx/items/collectibles/rat.png",
        names: {"kr": "자", "en": "Rat"},
        descriptions: {"kr": "작업중인 아이템입니다", "en": "Work in progress item"},
        eids: {"kr": ["작업중인 아이템입니다"], "en": ["Work in progress item"]}
    },
    OX: {
        gfx: "resources/gfx/items/collectibles/ox.png",
        names: {"kr": "축", "en": "Ox"},
        descriptions: {"kr": "작업중인 아이템입니다", "en": "Work in progress item"},
        eids: {"kr": ["작업중인 아이템입니다"], "en": ["Work in progress item"]}
    },
    TIGER: {
        gfx: "resources/gfx/items/collectibles/tiger.png",
        names: {"kr": "인", "en": "Tiger"},
        descriptions: {"kr": "작업중인 아이템입니다", "en": "Work in progress item"},
        eids: {"kr": ["작업중인 아이템입니다"], "en": ["Work in progress item"]}
    },
    RABBIT: {
        gfx: "resources/gfx/items/collectibles/rabbit.png",
        names: {"kr": "묘", "en": "Rabbit"},
        descriptions: {"kr": "작업중인 아이템입니다", "en": "Work in progress item"},
        eids: {"kr": ["작업중인 아이템입니다"], "en": ["Work in progress item"]}
    },
    DRAGON: {
        gfx: "resources/gfx/items/collectibles/dragon.png",
        names: {"kr": "진", "en": "Dragon"},
        descriptions: {"kr": "작업중인 아이템입니다", "en": "Work in progress item"},
        eids: {"kr": ["작업중인 아이템입니다"], "en": ["Work in progress item"]}
    },
    SNAKE: {
        gfx: "resources/gfx/items/collectibles/snake.png",
        names: {"kr": "사", "en": "Snake"},
        descriptions: {"kr": "작업중인 아이템입니다", "en": "Work in progress item"},
        eids: {"kr": ["작업중인 아이템입니다"], "en": ["Work in progress item"]}
    },
    HORSE: {
        gfx: "resources/gfx/items/collectibles/horse.png",
        names: {"kr": "오", "en": "Horse"},
        descriptions: {"kr": "작업중인 아이템입니다", "en": "Work in progress item"},
        eids: {"kr": ["작업중인 아이템입니다"], "en": ["Work in progress item"]}
    },
    GOAT: {
        gfx: "resources/gfx/items/collectibles/goat.png",
        names: {"kr": "미", "en": "Goat"},
        descriptions: {"kr": "작업중인 아이템입니다", "en": "Work in progress item"},
        eids: {"kr": ["작업중인 아이템입니다"], "en": ["Work in progress item"]}
    },
    MONKEY: {
        gfx: "resources/gfx/items/collectibles/monkey.png",
        names: {"kr": "신", "en": "Monkey"},
        descriptions: {"kr": "작업중인 아이템입니다", "en": "Work in progress item"},
        eids: {"kr": ["작업중인 아이템입니다"], "en": ["Work in progress item"]}
    },
    CHICKEN: {
        gfx: "resources/gfx/items/collectibles/chicken.png",
        names: {"kr": "유", "en": "Chicken"},
        descriptions: {"kr": "작업중인 아이템입니다", "en": "Work in progress item"},
        eids: {"kr": ["작업중인 아이템입니다"], "en": ["Work in progress item"]}
    },
    DOG: {
        gfx: "resources/gfx/items/collectibles/dog.png",
        names: {"kr": "술", "en": "Dog"},
        descriptions: {"kr": "작업중인 아이템입니다", "en": "Work in progress item"},
        eids: {"kr": ["작업중인 아이템입니다"], "en": ["Work in progress item"]}
    },
    PIG: {
        gfx: "resources/gfx/items/collectibles/pig.png",
        names: {"kr": "해", "en": "Pig"},
        descriptions: {"kr": "작업중인 아이템입니다", "en": "Work in progress item"},
        eids: {"kr": ["작업중인 아이템입니다"], "en": ["Work in progress item"]}
    },
};

// Export for use in other modules
if (typeof module !== 'undefined' && module.exports) {
    module.exports = items;
}

// Make available globally for browser
if (typeof window !== 'undefined') {
    window.items = items;
}
