-- Native-Korean-leaning Urimal text for Conch's Blessing. Same layout as en.lua (read its header);
-- anything missing here falls back to English. Keep every entry line-for-line
-- parallel with en.lua, and run `python check_locale.py` after editing.
return {
    items = {
        -- Collectibles
        LIVE_EYE = {
            name = "살아있는 눈",
            description = "놓쳐도 괜찮아",
            eid = {
                "괴물을 맞힐 때마다 {{Damage}}때리는 힘의 배수가 0.1씩 늘어납니다.",
                "#괴물을 맞히지 못하면 {{Damage}}때리는 힘의 배수가 0.15씩 줄어듭니다.",
                "#{{Luck}} 5할의 확률로 줄어들지 않습니다.(행운 1당 5푼)",
                "#{{Damage}} 때리는 힘의 배수: 가장 높을 때/낮을 때 (x3.0/x0.75)",
                "#눈물 말고 다른 것으로 때리면 {{Damage}}때리는 힘의 배수가 x1.5에 머무릅니다.",
            },
            synergies = {
                rock_bottom = "때리는 힘의 배수가 가장 높은 값인 x3.0에 머무릅니다. (눈물 말고 다른 것으로 때려도 같음)",
            },
        },
        VOID_DAGGER = {
            name = "공허의 짧은 칼",
            description = "공허가 열린다",
            eid = {
                "#내 공격으로 적을 다치게 하면 확률에 따라 그 자리에 내 때리는 힘만큼 아프게 하는 공허의 고리를 불러냅니다.",
                "#확률은 (30 - {{Tears}}쏘는 빠르기)%로 5푼보다 작아지지 않습니다",
                "#위 확률은 {{Luck}}운에 따라 (1+0.1×{{Luck}}운) 배수로 늘어납니다. (많아도 100%)",
                "#고리가 머무는 시간은 {{Damage}}때리는 힘에 따라 늘어나며 때리는 힘 10당 5단계로 늘어납니다.",
                "#{{BlackHeart}}검은 하트는 떨어지지 않습니다.",
                "#{{Warning}} REPENTOGON 권장",
            },
        },
        ETERNAL_FLAME = {
            name = "꺼지지 않는 불꽃",
            description = "씻어 내는 불길",
            eid = {
                "저주가 걸릴 때마다 저주를 없앱니다.",
                "#저주를 없앨 때 때리는 힘(고정) +3.0, 쏘는 빠르기 +1.0을 더하며, 이 힘은 사라지지 않습니다.",
                "#{{EternalHeart}} 영원한 하트 1개를 얻습니다.",
            },
        },
        POWER_TRAINING = {
            name = "힘 기르기",
            description = "이쯤이야 가뿐하지!",
            eid = {
                "쓰면 때리는 힘, 쏘는 빠르기, 닿는 거리, 행운이 1.0~1.3배가 됩니다.",
                "#처음 얻을 때 쓸 힘이 반 차 있습니다",
                "#거듭 쓰면 배수가 바뀐 만큼을 더합니다.",
                "#마지막 배수는 0.5 아래로 내려가지 않습니다.",
            },
        },
        ORAL_STEROIDS = {
            name = "먹는 스테로이드",
            description = "바늘은 무서워",
            eid = {
                "얻을 때 때리는 힘, 쏘는 빠르기, 닿는 거리, 행운이 0.8 ~ 1.5배가 됩니다.",
                "#더 얻으면 배수가 바뀐 만큼을 더합니다.",
                "#마지막 배수는 0.4 아래로 내려가지 않습니다.",
            },
        },
        INJECTABLE_STEROIDS = {
            name = "주사 스테로이드",
            description = "힘을 원해...",
            eid = {
                "쓰면 때리는 힘, 쏘는 빠르기, 닿는 거리, 행운이 0.5~2.0배가 됩니다.",
                "#처음 얻을 때 쓸 힘이 반 차 있습니다",
                "#거듭 쓰면 배수가 바뀐 만큼을 더합니다.",
                "#마지막 배수는 0.25 아래로 내려가지 않습니다.",
                "#{{Warning}} 몸이 갈수록 노래집니다...",
                "#{{Warning}} 처음에는 1% 확률로 곧바로 죽습니다.",
                "#{{Warning}} 곧바로 죽는 것은 보호막이나 무적으로도 막지 못하지만, 되살아나는 힘까지 막지는 않습니다.",
                "#{{Warning}} 쓰면 곧바로 죽을 확률이 3%씩 늘고, 층을 바꾸면 처음 값으로 돌아갑니다.",
                "#방 안의 적을 모두 없앨 때마다 곧바로 죽을 확률이 0.25% 줄어듭니다.",
            },
        },
        RAT = {
            name = "자",
            description = "자",
        },
        OX = {
            name = "축",
            description = "축",
        },
        TIGER = {
            name = "인",
            description = "인",
        },
        RABBIT = {
            name = "묘",
            description = "묘",
        },
        DRAGON = {
            name = "진",
            description = "날씨의 신",
            eid = {
                "날아다닐 수 있고, 쏜 것은 바위 같은 걸림돌을 꿰뚫습니다.",
                "#5번 공격할 때마다 아무 쪽으로나 번개 구슬을 5발 쏩니다",
                "#{{Warning}} REPENTOGON이 필요합니다!",
            },
            synergies = {
                dragon = {
                    "번개 구슬이 거센 비바람으로 바뀝니다",
                    "#비바람이 멈추면 그 자리에 소용돌이가 생겨나 2초 동안 적을 끌어당깁니다",
                    "#소용돌이가 사라질 때, 내 때리는 힘의 25배로 터집니다",
                    "#겹쳐 지니면 때리는 힘 25% 늘어남",
                },
            },
        },
        SNAKE = {
            name = "사",
            description = "사",
        },
        HORSE = {
            name = "오",
            description = "오",
        },
        GOAT = {
            name = "미",
            description = "미",
        },
        MONKEY = {
            name = "신",
        },
        CHICKEN = {
            name = "유",
            description = "유",
        },
        DOG = {
            name = "술",
            description = "술",
        },
        PIG = {
            name = "해",
            description = "해",
        },
        KRONOS = {
            name = "크로노스",
            description = "제 새끼를 삼키다",
            eid = {
                "길동무를 삼켜 저마다의 재주와 때리는 힘 2를 얻습니다",
                "#따로 빼 둔 길동무는 삼켜지지 않습니다",
                "#지금 탄알에 다치지 않을 확률: %KRONOS_BLOCK%",
            },
            synergies = {
                twisted_pair = "때리는 힘이 37.5%인 공격을 2개 더합니다.",
                succubus = "기운이 내 둘레를 따라다닙니다.",
                incubus = "때리는 힘이 75%인 공격을 1개 더합니다.",
                seraphim = {
                    "날아다닐 수 있고, 쏜 것은 바위 같은 걸림돌을 꿰뚫습니다.",
                    "{c:SACRED_HEART} 신성한 심장을 얻습니다. (처음 1번만)",
                },
                robo_baby = "{c:TECHNOLOGY} 테크를 얻습니다.",
                robo_baby_2 = "{c:TECHNOLOGY_2} 테크 2를 얻습니다.",
                blue_babys_only_friend = "{c:LUDOVICO_TECHNIQUE} 루도비코를 얻습니다. (처음 1번만)",
                lil_brimstone = "{c:BRIMSTONE} 혈사를 얻습니다.",
                bobs_brain = "{c:IPECAC} 구토제를 얻습니다. (처음 1번만)",
                lil_monstro = "{c:MONSTROS_LUNG} 몬스트로의 폐를 얻습니다. (처음 1번만)",
                lil_haunt = "무엇으로 때리든 적이 겁에 질리게 합니다.",
                blood_puppy = "{c:GIMPY} 김피를 얻습니다. (처음 1번만)",
                angelic_prism = "공격이 4갈래로 갈라져 나갑니다.",
                bot_fly = "{c:LOST_CONTACT} 잃어버린 렌즈를 얻습니다. (처음 1번만)",
                freezer_baby = "{c:URANUS} 천왕성을 얻습니다. (처음 1번만)",
                lil_abaddon = "{c:MAW_OF_THE_VOID} 공허의 구렁텅이를 얻습니다. (처음 1번만)",
                multidimensional_baby = "{c:20_20} 20/20을 얻습니다.",
                harlequin_baby = "{c:THE_WIZ} 법사를 얻습니다.",
                brother_bobby = "{{Tears}} 쏘는 빠르기(고정) +2를 얻습니다.",
                demon_baby = "{c:MARKED} 표식을 얻습니다. (처음 1번만)",
                little_gish = "무엇으로 때리든 적을 느리게 만듭니다.",
                lil_loki = "{c:LOKIS_HORNS} 로키의 뿔을 얻습니다.",
                ghost_baby = "{c:CONTINUUM} 연속체를 얻습니다.",
                rotten_baby = {
                    "적을 때려 다치게 하면 50% 확률로 우리 편 파리를 불러냅니다. ({c:7_SEALS} 7개의 도장과 더함, 많아도 100%)",
                    "지금 우리 편 파리를 불러낼 확률: %KRONOS_FLY%",
                },
                little_steven = "쏜 것이 적을 뒤쫓습니다.",
                rainbow_baby = "{c:FRUIT_CAKE} 과일 케이크를 얻습니다. (처음 1번만)",
                guardian_angel = "움직이는 빠르기{{Speed}} +0.3을 얻습니다.",
                censer = "향로의 기운이 내 자리를 따라다닙니다.",
                leech = "{c:CHARM_VAMPIRE} 흡혈귀의 부적을 얻습니다. (처음 1번만)",
                bomb_bag = "{c:PYRO} 파이로를 얻습니다. (처음 1번만)",
                dark_bum = "{c:MITRE} 주교관을 얻습니다. (처음 1번만)",
                key_bum = "{c:SKELETON_KEY} 해골 열쇠를 얻습니다. (처음 1번만)",
                abel = "{c:MY_REFLECTION} 거울을 얻습니다. (처음 1번만)",
                star_of_bethlehem = {
                    "베들레헴의 별 기운이 내 자리를 따라다닙니다.",
                    "{c:COMPASS} 나침반을 얻습니다. (처음 1번만)",
                },
                farting_baby = "{c:JELLY_BELLY} 젤리 배를 얻습니다. (처음 1번만)",
                samsons_chains = "{c:THUNDER_THIGHS} 천둥 허벅지를 얻습니다. (처음 1번만)",
                finger = "{c:TRACTOR_BEAM} 트랙터 빔을 얻습니다. (처음 1번만)",
                little_chad = "{c:CANDY_HEART} 캔디 하트를 얻습니다. (처음 1번만)",
                sack_of_pennies = "{c:DOLLAR} 달러를 얻습니다. (처음 1번만)",
                sack_of_sacks = "{c:SACK_HEAD} 자루 머리를 얻습니다. (처음 1번만)",
                charged_baby = "{c:9_VOLT} 9볼트를 얻습니다. (처음 1번만)",
                yo_listen = "{c:XRAY_VISION} 엑스레이 투시를 얻습니다. (처음 1번만)",
                daddy_longlegs = {
                    "적을 때려 다치게 하면 10% 확률로 다리가 내려찍어 둘레의 적에게 때리는 힘 x2의 피해를 줍니다. (삼킬 때마다 쌓임)",
                    "지금 내려찍기 확률: %KRONOS_STOMP%",
                },
                sister_maggy = "{c:CRICKETS_HEAD} 크리켓의 머리를 얻습니다. (처음 1번만)",
                little_chubby = "{c:MARS} 화성을 얻습니다. (처음 1번만)",
                big_chubby = {
                    "{c:MARS} 화성을 얻습니다. (처음 1번만)",
                    "적이 쏜 탄알에 맞을 때 1% 확률로 다치지 않습니다. (삼킬 때마다 쌓임)",
                    "지금 탄알에 다치지 않을 확률: %KRONOS_BLOCK%",
                },
                peeper = "{c:MOMS_EYE} 엄마의 눈알을 얻습니다. (처음 1번만)",
                bbf = "{c:FIRE_MIND} 불타는 마음을 얻습니다. (처음 1번만)",
                fates_reward = "{c:20_20} 시력 2.0을 얻습니다. (처음 1번만)",
                lil_gurdy = "{c:CHOCOLATE_MILK} 초콜릿 우유를 얻습니다. (처음 1번만)",
                bumbo = "{c:PIGGY_BANK} 돼지 저금통을 얻습니다. (처음 1번만)",
                spider_mod = "{c:SPIDER_BITE} 거미물림을 얻습니다. (처음 1번만)",
                depression = "{c:HOLY_LIGHT} 신성한 빛을 얻습니다. (처음 1번만)",
                king_baby = "{c:MAGIC_MUSHROOM} 마법의 버섯을 얻습니다. (처음 1번만)",
                acid_baby = "{c:PHD} 박사학위를 얻습니다. (처음 1번만)",
                jaw_bone = "{c:COMPOUND_FRACTURE} 복합 골절을 얻습니다. (처음 1번만)",
                boiled_baby = "{c:EYE_SORE} 흉물을 얻습니다. (처음 1번만)",
                lil_dumpy = "{c:JELLY_BELLY} 젤리 배를 얻습니다. (처음 1번만)",
                fruity_plum = "{c:KIDNEY_STONE} 신장 결석을 얻습니다. (처음 1번만)",
                ["7_seals"] = {
                    "적을 때려 다치게 하면 50% 확률로 우리 편 파리를 불러냅니다. ({c:ROTTEN_BABY} 썩은 아기와 더함, 많아도 100%)",
                    "지금 우리 편 파리를 불러낼 확률: %KRONOS_FLY%",
                },
                juicy_sack = {
                    "적을 때려 다치게 하면 50% 확률로 우리 편 거미를 불러냅니다. ({c:SISSY_LONGLEGS} 눈나 거미와 더함, 많아도 100%)",
                    "지금 우리 편 거미를 불러낼 확률: %KRONOS_SPIDER%",
                },
                sissy_longlegs = {
                    "적을 때려 다치게 하면 50% 확률로 우리 편 거미를 불러냅니다. ({c:JUICY_SACK} 축축한 알집과 더함, 많아도 100%)",
                    "지금 우리 편 거미를 불러낼 확률: %KRONOS_SPIDER%",
                },
                intruder = "무엇으로 때리든 적을 느리게 만듭니다.",
                worm_friend = "무엇으로 때리든 적을 느리게 만듭니다.",
                halo_of_flies = {
                    "적이 쏜 탄알에 맞을 때 1% 확률로 다치지 않습니다. (삼킬 때마다 쌓임)",
                    "지금 탄알에 다치지 않을 확률: %KRONOS_BLOCK%",
                },
                distant_admiration = {
                    "적이 쏜 탄알에 맞을 때 1% 확률로 다치지 않습니다. (삼킬 때마다 쌓임)",
                    "지금 탄알에 다치지 않을 확률: %KRONOS_BLOCK%",
                },
                cube_of_meat = {
                    "적이 쏜 탄알에 맞을 때 1% 확률로 다치지 않습니다. (삼킬 때마다 쌓임)",
                    "지금 탄알에 다치지 않을 확률: %KRONOS_BLOCK%",
                },
                forever_alone = {
                    "적이 쏜 탄알에 맞을 때 1% 확률로 다치지 않습니다. (삼킬 때마다 쌓임)",
                    "지금 탄알에 다치지 않을 확률: %KRONOS_BLOCK%",
                },
                sacrificial_dagger = {
                    "적이 쏜 탄알에 맞을 때 2% 확률로 다치지 않습니다. (삼킬 때마다 쌓임)",
                    "지금 탄알에 다치지 않을 확률: %KRONOS_BLOCK%",
                },
                guppys_hairball = {
                    "적이 쏜 탄알에 맞을 때 1% 확률로 다치지 않습니다. (삼킬 때마다 쌓임)",
                    "지금 탄알에 다치지 않을 확률: %KRONOS_BLOCK%",
                },
                guillotine = {
                    "{{Damage}}때리는 힘 +1, {{Tears}}쏘는 빠르기 +0.5 (삼킬 때마다 쌓임)",
                    "적이 쏜 탄알에 맞을 때 1% 확률로 다치지 않습니다. (삼킬 때마다 쌓임)",
                    "지금 탄알에 다치지 않을 확률: %KRONOS_BLOCK%",
                },
                ball_of_bandages = {
                    "적이 쏜 탄알에 맞을 때 1% 확률로 다치지 않습니다. (삼킬 때마다 쌓임)",
                    "지금 탄알에 다치지 않을 확률: %KRONOS_BLOCK%",
                },
                smart_fly = {
                    "적이 쏜 탄알에 맞을 때 1% 확률로 다치지 않습니다. (삼킬 때마다 쌓임)",
                    "지금 탄알에 다치지 않을 확률: %KRONOS_BLOCK%",
                },
                best_bud = {
                    "적이 쏜 탄알에 맞을 때 1% 확률로 다치지 않습니다. (삼킬 때마다 쌓임)",
                    "지금 탄알에 다치지 않을 확률: %KRONOS_BLOCK%",
                },
                big_fan = {
                    "적이 쏜 탄알에 맞을 때 2% 확률로 다치지 않습니다. (삼킬 때마다 쌓임)",
                    "지금 탄알에 다치지 않을 확률: %KRONOS_BLOCK%",
                },
                punching_bag = {
                    "적이 쏜 탄알에 맞을 때 2% 확률로 다치지 않습니다. (삼킬 때마다 쌓임)",
                    "지금 탄알에 다치지 않을 확률: %KRONOS_BLOCK%",
                },
                sworn_protector = {
                    "적이 쏜 탄알에 맞을 때 5% 확률로 다치지 않습니다. (삼킬 때마다 쌓임)",
                    "지금 탄알에 다치지 않을 확률: %KRONOS_BLOCK%",
                },
                friend_zone = {
                    "적이 쏜 탄알에 맞을 때 1% 확률로 다치지 않습니다. (삼킬 때마다 쌓임)",
                    "지금 탄알에 다치지 않을 확률: %KRONOS_BLOCK%",
                },
                lost_fly = {
                    "적이 쏜 탄알에 맞을 때 1% 확률로 다치지 않습니다. (삼킬 때마다 쌓임)",
                    "지금 탄알에 다치지 않을 확률: %KRONOS_BLOCK%",
                },
                hushy = {
                    "적이 쏜 탄알에 맞을 때 1% 확률로 다치지 않습니다. (삼킬 때마다 쌓임)",
                    "지금 탄알에 다치지 않을 확률: %KRONOS_BLOCK%",
                },
                moms_razor = {
                    "적이 쏜 탄알에 맞을 때 1% 확률로 다치지 않습니다. (삼킬 때마다 쌓임)",
                    "{{BleedingOut}} 적을 때려 다치게 하면 10% 확률로 피를 흘리게 합니다. (삼킬 때마다 쌓임)",
                    "지금 탄알에 다치지 않을 확률: %KRONOS_BLOCK%",
                    "지금 피를 흘리게 할 확률: %KRONOS_BLEED%",
                },
                angry_fly = {
                    "적이 쏜 탄알에 맞을 때 1% 확률로 다치지 않습니다. (삼킬 때마다 쌓임)",
                    "지금 탄알에 다치지 않을 확률: %KRONOS_BLOCK%",
                },
                leprosy = {
                    "적이 쏜 탄알에 맞을 때 1% 확률로 다치지 않습니다. (삼킬 때마다 쌓임)",
                    "지금 탄알에 다치지 않을 확률: %KRONOS_BLOCK%",
                },
                slipped_rib = {
                    "적이 쏜 탄알에 맞을 때 1% 확률로 다치지 않습니다. (삼킬 때마다 쌓임)",
                    "지금 탄알에 다치지 않을 확률: %KRONOS_BLOCK%",
                },
                pointy_rib = {
                    "적이 쏜 탄알에 맞을 때 1% 확률로 다치지 않습니다. (삼킬 때마다 쌓임)",
                    "지금 탄알에 다치지 않을 확률: %KRONOS_BLOCK%",
                },
                psy_fly = {
                    "적이 쏜 탄알에 맞을 때 5% 확률로 다치지 않습니다. (삼킬 때마다 쌓임)",
                    "지금 탄알에 다치지 않을 확률: %KRONOS_BLOCK%",
                },
                tinytoma = {
                    "적이 쏜 탄알에 맞을 때 1% 확률로 다치지 않습니다. (삼킬 때마다 쌓임)",
                    "지금 탄알에 다치지 않을 확률: %KRONOS_BLOCK%",
                },
                headless_baby = "{c:AQUARIUS} 물병자리를 얻습니다. (처음 1번만)",
                cains_other_eye = "{c:RUBBER_CEMENT} 고무 접착제를 얻습니다. (처음 1번만)",
                papa_fly = "{c:HIVE_MIND} 군체의식을 얻습니다. (처음 1번만)",
                shade = "{c:LUSTY_BLOOD} 욕망의 피를 얻습니다. (처음 1번만)",
                obsessed_fan = {
                    "적이 쏜 탄알에 맞을 때 1% 확률로 다치지 않습니다. (삼킬 때마다 쌓임)",
                    "지금 탄알에 다치지 않을 확률: %KRONOS_BLOCK%",
                },
                gemini = "몸이 닿은 적에게 초당 6의 피해를 줍니다. (삼킬 때마다 쌓임)",
                cube_baby = {
                    "{{Freezing}} 적을 때려 다치게 하면 10% 확률로 적을 2초 동안 얼려 멈춥니다. (삼킬 때마다 쌓임)",
                    "지금 얼려 멈출 확률: %KRONOS_FREEZE%",
                },
                lil_spewer = {
                    "적을 때려 다치게 하면 25% 확률로 적이 있는 자리의 바닥에 빨간 웅덩이가 생깁니다. (삼킬 때마다 쌓임)",
                    "지금 웅덩이가 생길 확률: %KRONOS_CREEP%",
                },
                gb_bug = {
                    "삼킬 때 지금까지 삼킨 다른 길동무 가운데 아무렇게나 반을 골라 되돌려줍니다.",
                    "되돌아온 길동무는 다시 삼켜지지 않습니다.",
                },
                bum_friend = {
                    "방 안의 적을 모두 없애면 10% 확률로 주울 것을 아무거나 떨어뜨립니다. (삼킬 때마다 쌓임)",
                    "지금 주울 것을 떨어뜨릴 확률: %KRONOS_PICKUP_DROP%",
                },
                lil_chest = {
                    "{{Chest}} 방 안의 적을 모두 없애면 10% 확률로 상자를 떨어뜨립니다. (삼킬 때마다 쌓임)",
                    "지금 상자를 떨어뜨릴 확률: %KRONOS_CHEST_DROP%",
                },
                relic = "{{SoulHeart}} 방 6개에서 적을 모두 없앨 때마다 푸른 하트를 떨어뜨립니다. (삼킬 때마다 1개씩 더함)",
                mystery_sack = "방 6개에서 적을 모두 없앨 때마다 주울 것을 아무거나 떨어뜨립니다. (삼킬 때마다 1개씩 더함)",
                rune_bag = "{{Rune}} 방 7개에서 적을 모두 없앨 때마다 룬을 떨어뜨립니다. (삼킬 때마다 1개씩 더함)",
                paschal_candle = "{{Tears}} 방 안의 적을 모두 없앨 때마다 쏘는 빠르기 +0.03 (삼킬 때마다 쌓임)",
                holy_water = "맞았을 때 내 발밑에 성수 웅덩이가 생깁니다. (삼킬 때마다 1개씩 더함, 많아도 4개)",
                dry_baby = {
                    "맞았을 때 25% 확률로 {c:NECRONOMICON} 네크로노미콘의 힘이 나옵니다. (삼킬 때마다 쌓임)",
                    "지금 네크로노미콘의 힘이 나올 확률: %KRONOS_NECRONOMICON%",
                },
                milk = "{{Tears}} 층에서 처음 맞았을 때 그 층 동안 쏘는 빠르기 +1 (삼킬 때마다 쌓임)",
                bird_cage = "맞았을 때 가장 가까운 적에게 45의 피해를 줍니다. (삼킬 때마다 쌓임)",
                mystery_egg = "{{Friendly}} 맞았을 때 홀린 우리 편 파리를 불러냅니다. (삼킬 때마다 1마리씩 더함, 많아도 5마리)",
                my_shadow = "{{Friendly}} 맞았을 때 검은 우리 편 애벌레를 불러냅니다. (삼킬 때마다 1마리씩 더함, 많아도 3마리)",
                hallowed_ground = "맞았을 때 가까운 곳에 하얀 똥을 놓습니다.",
                lost_soul = "{{EternalHeart}} 맞지 않고 층을 넘어가면 영원한 하트를 떨어뜨립니다. (삼킬 때마다 1개씩 더함)",
                bloodshot_eye = "피눈물 눈알이 내 자리를 따라다닙니다.",
                mongo_baby = "방에 들어갈 때마다 미니 아이작을 삼킨 수만큼 채워줍니다.",
                buddy_in_a_box = "층마다 다른 길동무 하나를 아무렇게나 골라 삼킨 힘을 얻습니다. (삼킬 때마다 1개씩 더함)",
                lil_delirium = "층마다 다른 길동무 하나를 아무렇게나 골라 삼킨 힘을 얻습니다. (삼킬 때마다 1개씩 더함)",
                box_of_friends = "쓰면 삼켜 얻은 때리는 힘과 저마다의 재주가 그 방에 있는 동안 2배가 됩니다. 방을 나가거나 이어하면 풀리며, 바꿔 받은 아이템은 더 주지 않습니다.",
                monster_manual = "크로노스를 얻기 앞뒤에 불러낸 길동무를 삼켜 그 층에 있는 동안 때리는 힘 +2와 저마다의 재주 또는 바꿔 받은 아이템을 얻습니다. 방을 옮겨도 삼킨 몫을 다시 받지는 않습니다.",
                sacrificial_altar = "쓰면 삼킨 길동무를 많아도 2마리까지 바쳐 악마방 아이템을 만들어 냅니다.",
                trinket_the_twins = "방에 들어가면 50% 확률로 그 방에 있는 동안 삼킨 길동무 하나의 힘이 2배가 됩니다.",
                ["1up"] = "{own:KRONOS} 크로노스에 삼켜지지 않습니다.",
                isaacs_heart = "{own:KRONOS} 크로노스에 삼켜지지 않습니다.",
                dead_cat = "{own:KRONOS} 크로노스에 삼켜지지 않습니다.",
                key_piece_1 = "{own:KRONOS} 크로노스에 삼켜지지 않습니다.",
                key_piece_2 = "{own:KRONOS} 크로노스에 삼켜지지 않습니다.",
                knife_piece_1 = "{own:KRONOS} 크로노스에 삼켜지지 않습니다.",
                knife_piece_2 = "{own:KRONOS} 크로노스에 삼켜지지 않습니다.",
                damocles_passive = "{own:KRONOS} 크로노스에 삼켜지지 않습니다.",
                straw_man = "{own:KRONOS} 크로노스에 삼켜지지 않습니다.",
                blood_oath = "{own:KRONOS} 크로노스에 삼켜지지 않습니다.",
            },
        },
        APPRAISAL_CERTIFICATE = {
            name = "값매김 글",
            description = "이거 훔친 건 아니죠?",
            eid = {
                "{{Coin}} 30원을 써서 지금 들고 있는 장신구를 모두 삼키고 {own:ATROPOS} 아트로포스를 뺀 모든 장신구가 놓인 {c:DEATH_CERTIFICATE} 사망 증명서 차원으로 갑니다.",
                "#첫 번째 방의 왼쪽에는 원래 방으로 돌아가는 문이 늘 열려 있습니다.",
                "#값매김 글로 간 곳에서는 {c:GLOWING_HOUR_GLASS} 빛나는 모래시계를 쓸 수 없습니다.",
            },
            synergies = {
                atropos = {
                    "방마다 장신구 하나를 얻으면 그 방에 남은 장신구만 사라집니다.",
                    "#얻은 장신구는 삼켜지며, 다른 방에서도 하나씩 고를 수 있습니다.",
                },
            },
        },
        MONEY_TEAR = {
            name = "돈 = 쏘는 빠르기",
            description = "돈은 쏘는 빠르기다",
            eid = {
                "지닌 동전 하나마다 쏘는 빠르기(고정)가 0.066 늘어납니다.",
            },
        },
        UTILITY_BELT = {
            name = "여러모로 쓰는 허리띠",
            description = "꼭 갖고 싶은 것",
            eid = {
                "얻을 때 지금 지닌 직접 쓰는 아이템을 주머니 자리로 옮깁니다.",
                "#주머니 자리가 이미 차 있다면 옮기지 않습니다.",
                "#직접 쓰는 아이템이 없다면 다음에 얻는 직접 쓰는 아이템을 주머니 자리로 옮깁니다.",
                "#{{Warning}} 옮길 수 없는 아이템도 있습니다.",
            },
            synergies = {
                book_of_virtues = "{{Warning}} 이 아이템은 주머니 자리로 옮길 수 없습니다",
                d_infinity = "{{Warning}} 이 아이템은 주머니 자리로 옮길 수 없습니다",
                blank_card = "{{Warning}} 이 아이템은 주머니 자리로 옮길 수 없습니다",
                placebo = "{{Warning}} 이 아이템은 주머니 자리로 옮길 수 없습니다",
                clear_rune = "{{Warning}} 이 아이템은 주머니 자리로 옮길 수 없습니다",
                glowing_hour_glass = "{{Warning}} 이 아이템은 주머니 자리로 옮길 수 없습니다",
                jar_of_wisps = "{{Warning}} 이 아이템은 주머니 자리로 옮길 수 없습니다",
            },
        },
        SEALED_DEMON_SWORD = {
            name = "묶인 마검",
            description = "더 많은 피가 필요해...",
            eid = {
                "{{Speed}} 움직이는 빠르기 -0.2",
                "#적이 {c:MEAT_CLEAVER} 고기 도축칼로 쪼개진 채 나타납니다. (체력 40%, 2마리)",
                "#우두머리는 쪼개지지 않습니다.",
                "#{{Warning}} 괴물을 300마리 쓰러뜨리면 {own:TYRFING} 티르핑으로 거듭납니다.",
                "#{{Warning}} REPENTOGON 권장",
            },
        },
        TYRFING = {
            name = "티르핑",
            description = "저주받은 마검",
            eid = {
                "괴물을 쓰러뜨릴 때마다 {{Damage}}때리는 힘이 +0.05 늘어납니다.",
                "#{{Warning}} 맞았을 때 쌓인 때리는 힘의 50%를 잃습니다.",
            },
        },
        ICE_BREATH = {
            name = "얼음 숨결",
            description = "서리의 숨결",
            eid = {
                "(15-{{Luck}}운)번 공격마다 얼음 불꽃 쏘기",
                "#한 번에 많아도 {{Tears}}쏘는 빠르기 수치만큼 쏘기 (적어도 1개)",
                "#얼음 불꽃은 내 {{Damage}}때리는 힘의 20%",
                "#맞히면 {{Luck}}운% 확률로 적이 얼어붙습니다 (많아도 100%)",
                "#{{Warning}} REPENTOGON이 필요합니다!",
            },
        },
        FIRE_BREATH = {
            name = "불꽃 숨결",
            description = "타오르는 숨결",
            eid = {
                "(15-{{Luck}}운)번 공격마다 불꽃 쏘기",
                "#한 번에 많아도 {{Tears}}쏘는 빠르기 수치만큼 쏘기 (적어도 1개)",
                "#불꽃은 내 {{Damage}}때리는 힘의 30%",
                "#맞히면 ({{Luck}}운 x5)% 확률로 적에게 불이 붙습니다 (많아도 100%)",
                "#{{Warning}} REPENTOGON이 필요합니다!",
            },
        },
        SOFLAM = {
            name = "SOFLAM",
            description = "겨눴다!",
            eid = {
                "기본 눈물이 레이저로 바뀝니다",
                "#내 공격으로 적을 다치게 하면 10% 확률로 그 적을 겨눕니다 ({{Luck}}운 x5% 더함)",
                "#겨눈 뒤 1.5초가 지나면 지금 한 번에 쏘는 수만큼 {c:EPIC_FETUS} Epic Fetus 미사일이 1발씩 잇달아 떨어집니다",
                "#미사일이 때리는 힘은 내 {{Damage}}때리는 힘의 3배",
                "#{{Warning}} REPENTOGON이 필요합니다!",
            },
            synergies = {
                mr_mega = {
                    "터지는 범위가 1.5배가 됩니다 (1회)",
                    "#미사일이 때리는 힘에 지닌 Mr. Mega 수만큼 2배씩 거듭 곱합니다",
                },
            },
        },
        TWO_FACED_PENNY = {
            name = "두 얼굴의 돈잎",
            description = "확률은 100%!",
            eid = {
                "얻은 뒤 다음으로 얻는 아이템을 하나 더 얻습니다. 직접 쓰는 아이템은 뺍니다.",
                "#맞지 않고 층을 마치면 그 아이템을 하나 더 얻습니다.",
            },
        },
        INF_D6 = {
            name = "끝없는 주사위",
            description = "마음대로 골라먹는 재미!",
            eid = {
                "더 손쉽게 즐기도록 돕는 아이템",
            },
        },
        SEVERED_OATH = {
            name = "적사단지",
            description = "이어진 운명을 끊다",
            eid = {
                "지니고 방에 들어가면 아이템마다 돌아가며 고를 것을 1개 더합니다.",
                "#이미 고를 수 있던 것에 더해집니다. 적사단지 자체가 황금 강화되어 있으면 2개 더합니다.",
                "#쓰면 방 안에서 돌아가며 보이던 아이템을 하나씩 따로 나눕니다.",
                "#{{Warning}} REPENTOGON이 필요합니다!",
            },
        },
        CEIL = {
            name = "올림",
            description = "모자라면 채운다!",
            eid = {
                "{{Speed}}움직이는 빠르기, {{Tears}}쏘는 빠르기, {{Damage}}때리는 힘, {{Range}}닿는 거리, {{Shotspeed}}날아가는 빠르기, {{Luck}}행운을 올림합니다.",
                "#소수점 둘째 자리 기준으로 0.01이라도 넘으면 올라갑니다.",
            },
        },
        ROUND = {
            name = "반올림",
            description = "반만 넘으면 된다",
            eid = {
                "{{Speed}}움직이는 빠르기, {{Tears}}쏘는 빠르기, {{Damage}}때리는 힘, {{Range}}닿는 거리, {{Shotspeed}}날아가는 빠르기, {{Luck}}행운을 반올림합니다.",
                "#소수점 둘째 자리 기준으로 0.50부터 올라갑니다.",
                "#{{Luck}}행운을 뺀 나머지 값은 0이 되지 않고 적어도 1이 됩니다.",
            },
            synergies = {
                ceil = "먼저 올림하므로 반올림해도 달라지지 않습니다.",
            },
        },
        FLOOR = {
            name = "내림",
            description = "바닥은 있다",
            eid = {
                "{{Speed}}움직이는 빠르기, {{Tears}}쏘는 빠르기, {{Damage}}때리는 힘, {{Range}}닿는 거리, {{Shotspeed}}날아가는 빠르기, {{Luck}}행운을 내림합니다.",
                "#다만, 캐릭터의 기본값보다 낮아지지 않습니다.",
                "#모드에서 더해진 캐릭터는 {{Player0}}아이작의 기본값을 따릅니다.",
            },
            synergies = {
                ceil = "먼저 올림하고, 기본값보다 낮아지지 않게만 해 줍니다.",
                round = "먼저 반올림하고, 기본값보다 낮아지지 않게만 해 줍니다.",
            },
        },

        -- Familiars
        TIME_MONEY = {
            name = "시간 = 돈",
            description = "시간은 돈이다",
            eid = {
                "동전 5개를 떨어뜨립니다.",
                "#60초마다 지금 지닌 동전의 5%만큼 동전을 떨어뜨립니다. (적어도 1개)",
                "#이 길동무가 떨어뜨리는 동전은 5% 확률로 5원, 2% 확률로 황금 동전, 2% 확률로 행운 동전, 1% 확률로 10원으로 바뀝니다.",
                "#행운에 따라 위 확률이 (1+0.1×운{{Luck}})배로 4배까지 늘어납니다.",
                "#맞으면 떨어뜨리는 동전이 1개 줄어듭니다.",
            },
            synergies = {
                bffs = "떨어뜨리는 동전의 몫이 10%로 늘어납니다.",
            },
        },

        -- Trinkets
        TIME_POWER = {
            name = "시간 = 힘",
            description = "시간은 힘이다",
            eid = {
                "지니고 있으면 초당 {{Damage}}때리는 힘이 0.006 늘어납니다.",
                "#적에게 맞았을 때 60초 동안 더 늘어나지 않습니다.",
            },
        },
        TIME_TEAR = {
            name = "시간 = 쏘는 빠르기",
            description = "시간은 쏘는 빠르기다",
            eid = {
                "지니고 있으면 초당 {{Tears}}쏘는 빠르기(고정)가 0.0066 늘어납니다.",
                "#적에게 맞았을 때 60초 동안 더 늘어나지 않습니다.",
            },
        },
        TIME_LUCK = {
            name = "시간 = 행운",
            description = "시간은 행운이다",
            eid = {
                "지니고 있으면 초당 {{Luck}}운이 0.01 늘어납니다.",
                "#적에게 맞았을 때 60초 동안 더 늘어나지 않습니다.",
            },
        },
        F_MINUS = {
            name = "F -",
            description = "정답만 피하는 것도 행운이야",
            eid = {
                "행운이 5 늘어납니다.",
                "#맞지 않은 채로 다음 층으로 넘어가면 {own:C_MINUS} C -로 거듭납니다.",
            },
        },
        C_MINUS = {
            name = "C -",
            description = "그럴 수 있어. 이런 날도 있는 거지 뭐.",
            eid = {
                "행운이 4 늘어납니다.",
                "#{{Tears}} 쏘는 빠르기(고정)가 2.0 늘어납니다.",
                "#맞지 않은 채로 다음 층으로 넘어가면 {own:B_MINUS} B -로 거듭납니다.",
            },
        },
        B_MINUS = {
            name = "B -",
            description = "시작이 반이다",
            eid = {
                "행운이 3 늘어납니다.",
                "#{{Tears}} 쏘는 빠르기(고정)가 3.0 늘어납니다.",
                "#{{Damage}} 때리는 힘이 3.0 늘어납니다.",
                "#맞지 않은 채로 다음 층으로 넘어가면 {own:A_MINUS} A -로 거듭납니다.",
            },
        },
        A_MINUS = {
            name = "A -",
            description = "잘해 봤어. 아이작",
            eid = {
                "행운이 2 늘어납니다.",
                "#{{Tears}} 쏘는 빠르기(고정)가 4.0 늘어납니다.",
                "#{{Damage}} 때리는 힘이 4.0 늘어납니다.",
                "#4배를 때리는 힘, 행운, 쏘는 빠르기에 나누어 곱합니다. (거듭 겹치지 않음)",
                "#각각 0.8배보다 작지 않게 나눕니다.",
                "#맞으면 {own:B_MINUS} B -로 내려갑니다.",
            },
        },
        ATROPOS = {
            name = "아트로포스",
            description = "끊어진 운명",
            eid = {
                "하나만 골라야 했던 아이템을 모두 얻을 수 있습니다.",
                "#{{Warning}} REPENTOGON 권장",
            },
            synergies = {
                death_certificate = {
                    "사망 증명서로 간 곳의 첫 방 왼쪽에 원래 방으로 돌아가는 문이 열립니다.",
                    "#아이템 하나를 얻으면 그 방에 남은 아이템이 모두 사라지지만, 저절로 원래 방으로 돌아가지는 않습니다.",
                },
            },
        },
        ANGELS_CROWN = {
            name = "천사의 머리테",
            description = "하늘에서 값을 치르다",
            eid = {
                "보물방 아이템이 {{AngelRoom}}천사방 아이템으로 바뀌고, 가게처럼 {{Coin}}동전으로 사게 됩니다.",
                "#{{Warning}} REPENTOGON 권장",
            },
            specials = {
                append = {
                    "25% 확률로 축복받은 보물방이 되어 {{AngelRoom}}천사방 아이템 1개와 {{EternalHeart}}영원한 하트가 더해집니다.",
                    "25% 확률로 축복받은 보물방이 되어 {{AngelRoom}}천사방 아이템 1개와 {{EternalHeart}}영원한 하트가 더해집니다.",
                    "33% 확률로 축복받은 보물방이 되어 {{AngelRoom}}천사방 아이템 1개와 {{EternalHeart}}영원한 하트가 더해집니다.",
                },
            },
        },
    },
    ui = {
        morph = {
            applied = "게임에 적용",
            pending = "보류 - 현재 기본 강화 연출",
            controls = "R 다시 보기 | 방향키 고르기 | Backspace 닫기",
        },
        percent = {
            standard = "%s%%",
            zero = "0할",
            unit1 = "%s할",
            unit2 = "%s푼",
            unit3 = "%s리",
            unit4 = "%s모",
            separator = " ",
            negative = "-%s",
        },
        kronos = {
            transfer_damage = "때리는 힘 +2",
            transfer_return = "길동무 돌려보내기",
            transfer_pretty_fly = "탄알에 다치지 않을 확률 +%s",
        },
        conch_mode = {
            transform = "소라고둥 모드 %s일 때 {{item_name}}으로 바뀜",
            flags = {
                positive = "긍정",
                neutral = "중립",
                negative = "부정",
            },
        },
        injectable_steroids = {
            death_chance = "#{{ColorRed}}곧바로 죽을 확률: %s{{CR}}",
            floor_uses = " (이번 층에서 쓴 횟수: %s회)",
        },
        sealed_demon_sword = {
            remaining_kills = "#{{ColorYellow}}더 쓰러뜨려야 할 수: %s{{CR}}",
        },
        tyrfing = {
            accumulated_damage = "#{{Damage}} 쌓인 때리는 힘: +%s",
        },
        utility_belt = {
            pocket_full = "#{{ColorRed}}주머니 자리가 이미 차 있음 - 옮길 수 없음{{CR}}",
            will_move = "#{{ColorGreen}}얻으면 옮길 것: %s{{CR}}",
            no_active = "#{{ColorYellow}}직접 쓰는 아이템 없음 - 다음에 얻는 직접 쓰는 아이템을 옮김{{CR}}",
        },
        void_dagger = {
            proc_chance = "#{{ColorYellow}}지금 나타날 확률: %s{{CR}}",
            proc_detail = " (기본: %s, {{Luck}}x%s)",
        },
    },
}
